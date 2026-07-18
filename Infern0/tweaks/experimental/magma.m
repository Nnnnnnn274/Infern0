#import "magma.h"
#import "../remote_objc.h"
#import "../sb_walk.h"
#import "../../LogTextView.h"

#import <stdio.h>
#import <string.h>
#import <sys/time.h>

#define MAGMA_SCAN_CAP 180
#define MAGMA_DEPTH_CAP 8
#define MAGMA_CHILD_CAP 48
#define MAGMA_PROPERTY_CAP 96
#define MAGMA_RESCAN_INTERVAL_US 2500000ULL

typedef struct {
    uint64_t object;
    uint8_t depth;
    bool mediaContext;
} MagmaScanNode;

static int gMagmaRed = 255;
static int gMagmaGreen = 71;
static int gMagmaBlue = 20;
static int gMagmaAlpha = 100;
static bool gMagmaColorToggles = true;
static bool gMagmaColorSliders = true;
static bool gMagmaColorMedia = true;
static bool gMagmaColorBackground = false;
static bool gMagmaConfigDirty = true;
static uint64_t gMagmaAppliedWindow = 0;
static uint64_t gMagmaLastScanUS = 0;
static bool gMagmaLastApplySucceeded = false;
static bool gMagmaLoggedWaiting = false;

static uint64_t magma_now_us(void)
{
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (uint64_t)tv.tv_sec * 1000000ULL + (uint64_t)tv.tv_usec;
}

static uint64_t magma_color(double red, double green, double blue, double alpha)
{
    uint64_t colorClass = r_class("UIColor");
    if (!r_is_objc_ptr(colorClass)) return 0;
    return r_msg2_main_raw(colorClass, "colorWithRed:green:blue:alpha:",
                           &red, sizeof(red), &green, sizeof(green),
                           &blue, sizeof(blue), &alpha, sizeof(alpha));
}

static bool magma_is_kind(uint64_t object, uint64_t cls)
{
    return r_is_objc_ptr(object) && r_is_objc_ptr(cls) &&
           (r_msg2_main(object, "isKindOfClass:", cls, 0, 0, 0) & 0xff) != 0;
}

static bool magma_override(uint64_t object, const char *getter,
                           const char *setter, uint64_t color, int *properties)
{
    if (!properties || *properties >= MAGMA_PROPERTY_CAP ||
        !r_is_objc_ptr(object) || !r_is_objc_ptr(color)) return false;
    bool changed = sb_cc_override_object("magma2", object, getter, setter, color);
    if (changed) (*properties)++;
    return changed;
}

static bool magma_class_contains(const char *className, const char *needle)
{
    return className && needle && strstr(className, needle) != NULL;
}

static bool magma_is_media_root(const char *className)
{
    return magma_class_contains(className, "MRU") ||
           magma_class_contains(className, "MediaControls") ||
           magma_class_contains(className, "NowPlaying");
}

static void magma_tint_toggle(uint64_t view, uint64_t accent, uint64_t foreground,
                              int *properties, int *hits)
{
    bool specialized = false;
    if (r_responds_main(view, "glyphColor") && r_responds_main(view, "setGlyphColor:")) {
        specialized = magma_override(view, "glyphColor", "setGlyphColor:", accent, properties) || specialized;
    }
    if (r_responds_main(view, "selectedGlyphColor") && r_responds_main(view, "setSelectedGlyphColor:")) {
        specialized = magma_override(view, "selectedGlyphColor", "setSelectedGlyphColor:", foreground, properties) || specialized;
    }
    if (r_responds_main(view, "highlightColor") && r_responds_main(view, "setHighlightColor:")) {
        specialized = magma_override(view, "highlightColor", "setHighlightColor:", accent, properties) || specialized;
    }
    if (r_responds_main(view, "highlightTintColor") && r_responds_main(view, "setHighlightTintColor:")) {
        specialized = magma_override(view, "highlightTintColor", "setHighlightTintColor:", foreground, properties) || specialized;
    }
    if (specialized && hits) (*hits)++;
}

static void magma_tint_slider(uint64_t view, uint64_t accent, uint64_t foreground,
                              int *properties, int *hits)
{
    bool changed = magma_override(view, "tintColor", "setTintColor:", accent, properties);
    uint64_t glyphContainer = r_responds_main(view, "glyphContainerView")
        ? r_msg2_main(view, "glyphContainerView", 0, 0, 0, 0) : 0;
    if (r_is_objc_ptr(glyphContainer))
        changed = magma_override(glyphContainer, "tintColor", "setTintColor:", foreground, properties) || changed;

    // Verified CCUIContinuousSliderView ivar. Only the fill view is colored;
    // no gesture, interaction, material recipe, or slider value is touched.
    uint64_t fillView = r_ivar_value(view, "_backgroundFillView");
    if (r_is_objc_ptr(fillView))
        changed = magma_override(fillView, "backgroundColor", "setBackgroundColor:", accent, properties) || changed;
    if (changed && hits) (*hits)++;
}

static void magma_tint_media_leaf(uint64_t view, uint64_t accent,
                                  uint64_t buttonClass, uint64_t labelClass,
                                  int *properties, int *hits)
{
    bool changed = false;
    if (magma_is_kind(view, buttonClass))
        changed = magma_override(view, "tintColor", "setTintColor:", accent, properties);
    else if (magma_is_kind(view, labelClass))
        changed = magma_override(view, "textColor", "setTextColor:", accent, properties);
    if (changed && hits) (*hits)++;
}

static bool magma_scan_window(uint64_t window, uint64_t accent, uint64_t foreground,
                              int *visitedOut, int *propertiesOut,
                              int *toggleHitsOut, int *sliderHitsOut,
                              int *mediaHitsOut, int *backgroundHitsOut)
{
    if (!r_is_objc_ptr(window)) return false;
    uint64_t viewClass = r_class("UIView");
    uint64_t buttonClass = r_class("UIButton");
    uint64_t labelClass = r_class("UILabel");
    uint64_t sliderClass = r_class("CCUIBaseSliderView");
    uint64_t backgroundClass = r_class("CCUIContentModuleBackgroundView");
    if (!r_is_objc_ptr(viewClass)) return false;

    MagmaScanNode queue[MAGMA_SCAN_CAP] = {0};
    int head = 0, tail = 0, visited = 0, properties = 0;
    int toggleHits = 0, sliderHits = 0, mediaHits = 0, backgroundHits = 0;
    queue[tail++] = (MagmaScanNode){ .object = window, .depth = 0, .mediaContext = false };

    while (head < tail && visited < MAGMA_SCAN_CAP && properties < MAGMA_PROPERTY_CAP) {
        MagmaScanNode node = queue[head++];
        if (!magma_is_kind(node.object, viewClass)) continue;
        visited++;

        char className[160] = {0};
        sb_read_class_name(node.object, className, sizeof(className));
        bool mediaContext = node.mediaContext || magma_is_media_root(className);
        bool ccButtonCandidate = magma_class_contains(className, "CCUI") &&
            (magma_class_contains(className, "Button") ||
             magma_class_contains(className, "Toggle") ||
             magma_class_contains(className, "Round"));
        bool sliderCandidate = magma_class_contains(className, "Slider");
        bool backgroundCandidate = magma_class_contains(className, "Background");

        if (gMagmaColorToggles && ccButtonCandidate)
            magma_tint_toggle(node.object, accent, foreground, &properties, &toggleHits);
        if (gMagmaColorSliders && sliderCandidate && magma_is_kind(node.object, sliderClass))
            magma_tint_slider(node.object, accent, foreground, &properties, &sliderHits);
        if (gMagmaColorMedia && mediaContext)
            magma_tint_media_leaf(node.object, accent, buttonClass, labelClass,
                                  &properties, &mediaHits);
        if (gMagmaColorBackground && backgroundCandidate && magma_is_kind(node.object, backgroundClass)) {
            if (magma_override(node.object, "backgroundColor", "setBackgroundColor:",
                               accent, &properties)) backgroundHits++;
        }

        if (node.depth >= MAGMA_DEPTH_CAP || properties >= MAGMA_PROPERTY_CAP) continue;
        uint64_t subviews = r_msg2_main(node.object, "subviews", 0, 0, 0, 0);
        if (!r_is_objc_ptr(subviews)) continue;
        uint64_t count = r_msg2_main(subviews, "count", 0, 0, 0, 0);
        if (count > MAGMA_CHILD_CAP) count = MAGMA_CHILD_CAP;
        for (uint64_t i = 0; i < count && tail < MAGMA_SCAN_CAP; i++) {
            uint64_t child = r_msg2_main(subviews, "objectAtIndex:", i, 0, 0, 0);
            if (r_is_objc_ptr(child)) {
                queue[tail++] = (MagmaScanNode){
                    .object = child,
                    .depth = (uint8_t)(node.depth + 1),
                    .mediaContext = mediaContext,
                };
            }
        }
    }

    if (visitedOut) *visitedOut = visited;
    if (propertiesOut) *propertiesOut = properties;
    if (toggleHitsOut) *toggleHitsOut = toggleHits;
    if (sliderHitsOut) *sliderHitsOut = sliderHits;
    if (mediaHitsOut) *mediaHitsOut = mediaHits;
    if (backgroundHitsOut) *backgroundHitsOut = backgroundHits;
    return properties > 0;
}

bool magma_apply_in_session(void)
{
    uint64_t nowUS = magma_now_us();
    uint64_t window = sb_control_center_window();
    if (!r_is_objc_ptr(window)) {
        if (!gMagmaLoggedWaiting) {
            log_user("[MAGMA2][WAITING] Open Control Center; no visible CC window was mutated.\n");
            gMagmaLoggedWaiting = true;
        }
        gMagmaLastScanUS = 0;
        return false;
    }
    gMagmaLoggedWaiting = false;

    if (gMagmaConfigDirty || (gMagmaAppliedWindow && gMagmaAppliedWindow != window)) {
        int restored = sb_cc_restore_owner("magma2");
        log_user("[MAGMA2][RESET] reason=%s restoredProperties=%d.\n",
                 gMagmaConfigDirty ? "configuration-change" : "new-presentation", restored);
        gMagmaConfigDirty = false;
        gMagmaLastScanUS = 0;
        gMagmaLastApplySucceeded = false;
    }
    if (gMagmaAppliedWindow == window && gMagmaLastScanUS &&
        nowUS - gMagmaLastScanUS < MAGMA_RESCAN_INTERVAL_US)
        return gMagmaLastApplySucceeded;

    double red = (double)gMagmaRed / 255.0;
    double green = (double)gMagmaGreen / 255.0;
    double blue = (double)gMagmaBlue / 255.0;
    double alpha = (double)gMagmaAlpha / 100.0;
    double luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue;
    uint64_t accent = magma_color(red, green, blue, alpha);
    uint64_t foreground = luminance > 0.62
        ? magma_color(0.08, 0.08, 0.10, 1.0)
        : magma_color(1.0, 1.0, 1.0, 1.0);
    if (!r_is_objc_ptr(accent) || !r_is_objc_ptr(foreground)) {
        log_user("[MAGMA2][COLOR-FAIL] UIColor creation failed; nothing was mutated.\n");
        return false;
    }

    int visited = 0, properties = 0, toggles = 0, sliders = 0, media = 0, backgrounds = 0;
    bool ok = magma_scan_window(window, accent, foreground, &visited, &properties,
                                &toggles, &sliders, &media, &backgrounds);
    gMagmaAppliedWindow = window;
    gMagmaLastScanUS = nowUS;
    gMagmaLastApplySucceeded = ok;
    printf("[MAGMA2] window=0x%llx visited=%d properties=%d toggles=%d sliders=%d media=%d backgrounds=%d result=%d\n",
           window, visited, properties, toggles, sliders, media, backgrounds, ok);
    log_user("[MAGMA2][SCAN] visited=%d/%d properties=%d/%d toggles=%d sliders=%d media=%d backgrounds=%d result=%s.\n",
             visited, MAGMA_SCAN_CAP, properties, MAGMA_PROPERTY_CAP,
             toggles, sliders, media, backgrounds, ok ? "applied" : "no-compatible-targets");
    return ok;
}

bool magma_stop_in_session(void)
{
    int restored = sb_cc_restore_owner("magma2");
    gMagmaAppliedWindow = 0;
    gMagmaLastScanUS = 0;
    gMagmaLastApplySucceeded = false;
    gMagmaLoggedWaiting = false;
    log_user("[MAGMA2][RESTORE] exactProperties=%d result=%s.\n",
             restored, restored > 0 ? "restored" : "nothing-owned");
    return restored > 0;
}

void magma_configure(int red, int green, int blue, int alpha,
                     bool colorToggles, bool colorSliders,
                     bool colorMedia, bool colorBackground)
{
    if (red < 0) red = 0; else if (red > 255) red = 255;
    if (green < 0) green = 0; else if (green > 255) green = 255;
    if (blue < 0) blue = 0; else if (blue > 255) blue = 255;
    if (alpha < 5) alpha = 5; else if (alpha > 100) alpha = 100;
    if (gMagmaRed != red || gMagmaGreen != green || gMagmaBlue != blue ||
        gMagmaAlpha != alpha || gMagmaColorToggles != colorToggles ||
        gMagmaColorSliders != colorSliders || gMagmaColorMedia != colorMedia ||
        gMagmaColorBackground != colorBackground) gMagmaConfigDirty = true;
    gMagmaRed = red;
    gMagmaGreen = green;
    gMagmaBlue = blue;
    gMagmaAlpha = alpha;
    gMagmaColorToggles = colorToggles;
    gMagmaColorSliders = colorSliders;
    gMagmaColorMedia = colorMedia;
    gMagmaColorBackground = colorBackground;
    printf("[MAGMA2] configure rgba=%d/%d/%d/%d toggles=%d sliders=%d media=%d background=%d dirty=%d\n",
           red, green, blue, alpha, colorToggles, colorSliders,
           colorMedia, colorBackground, gMagmaConfigDirty);
}

void magma_forget_remote_state(void)
{
    // SpringBoard may already be gone. This path deliberately performs no
    // remote messages; the coordinator drops stale pointers locally.
    sb_cc_forget_owner("magma2");
    gMagmaConfigDirty = true;
    gMagmaAppliedWindow = 0;
    gMagmaLastScanUS = 0;
    gMagmaLastApplySucceeded = false;
    gMagmaLoggedWaiting = false;
}
