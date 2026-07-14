#import "magma.h"
#import "../remote_objc.h"
#import "../sb_walk.h"
#import "../../TaskRop/RemoteCall.h"

#import <Foundation/Foundation.h>
#import <string.h>

static uint64_t gMagmaTint = 0;
static int gMagmaRed = 255;
static int gMagmaGreen = 71;
static int gMagmaBlue = 20;
static int gMagmaAlpha = 100;
static bool gMagmaColorToggles = true;
static bool gMagmaColorSliders = true;
static bool gMagmaColorMedia = true;
static bool gMagmaColorBackground = false;

static uint64_t magma_color(double red, double green, double blue, double alpha)
{
    uint64_t UIColor = r_class("UIColor");
    if (!r_is_objc_ptr(UIColor)) return 0;
    return r_msg2_main_raw(UIColor, "colorWithRed:green:blue:alpha:",
                           &red, sizeof(red), &green, sizeof(green),
                           &blue, sizeof(blue), &alpha, sizeof(alpha));
}

static uint64_t magma_key_window(void)
{
    uint64_t UIApplication = r_class("UIApplication");
    if (!r_is_objc_ptr(UIApplication)) return 0;
    uint64_t app = r_msg2_main(UIApplication, "sharedApplication", 0, 0, 0, 0);
    return r_is_objc_ptr(app) ? r_msg2_main(app, "keyWindow", 0, 0, 0, 0) : 0;
}

static void magma_class_name(uint64_t obj, char *out, size_t outLen)
{
    if (!out || outLen == 0) return;
    out[0] = '\0';
    if (!r_is_objc_ptr(obj)) return;
    uint64_t cls = r_dlsym_call(R_TIMEOUT, "object_getClass", obj, 0, 0, 0, 0, 0, 0, 0);
    uint64_t name = r_is_objc_ptr(cls) ? r_dlsym_call(R_TIMEOUT, "class_getName", cls, 0, 0, 0, 0, 0, 0, 0) : 0;
    if (!name) return;
    uint64_t buf = r_dlsym_call(R_TIMEOUT, "strdup", name, 0, 0, 0, 0, 0, 0, 0);
    if (!buf) return;
    remote_read(buf, out, outLen - 1);
    out[outLen - 1] = '\0';
    r_free(buf);
}

static void magma_scan(uint64_t parent, uint64_t color, bool restore, bool ccContext, int depth, int *hits)
{
    if (!r_is_objc_ptr(parent) || depth > 12) return;
    char cls[160] = {0};
    magma_class_name(parent, cls, sizeof(cls));
    ccContext = ccContext || strstr(cls, "CCUI") || strstr(cls, "ControlCenter");
    bool isToggle = strstr(cls, "Toggle") || strstr(cls, "Button") || strstr(cls, "Glyph") || strstr(cls, "Connectivity");
    bool isSlider = strstr(cls, "Slider") || strstr(cls, "ContinuousSlider");
    bool isMedia = strstr(cls, "Media") || strstr(cls, "NowPlaying") || strstr(cls, "MRU");
    bool isBackground = strstr(cls, "Platter") || strstr(cls, "Background") || strstr(cls, "Container");
    bool target = ccContext && ((gMagmaColorToggles && isToggle) || (gMagmaColorSliders && isSlider) ||
                  (gMagmaColorMedia && isMedia));
    if (target && r_is_objc_ptr(color)) {
        r_msg2_main(parent, "setTintColor:", color, 0, 0, 0);
        if (r_responds_main(parent, "setTextColor:")) r_msg2_main(parent, "setTextColor:", color, 0, 0, 0);
        if (hits) (*hits)++;
    }
    if (ccContext && gMagmaColorBackground && isBackground && r_is_objc_ptr(color) && r_responds_main(parent, "setBackgroundColor:")) {
        uint64_t bgColor = color;
        if (restore) {
            uint64_t UIColor = r_class("UIColor");
            uint64_t clear = r_is_objc_ptr(UIColor) ? r_msg2_main(UIColor, "clearColor", 0, 0, 0, 0) : 0;
            if (r_is_objc_ptr(clear)) bgColor = clear;
        }
        r_msg2_main(parent, "setBackgroundColor:", bgColor, 0, 0, 0);
        if (hits) (*hits)++;
    }
    uint64_t subviews = r_msg2_main(parent, "subviews", 0, 0, 0, 0);
    if (!r_is_objc_ptr(subviews)) return;
    uint64_t count = r_msg2_main(subviews, "count", 0, 0, 0, 0);
    if (count > 120) count = 120;
    for (uint64_t i = 0; i < count; i++) magma_scan(r_msg2_main(subviews, "objectAtIndex:", i, 0, 0, 0), color, restore, ccContext, depth + 1, hits);
}

bool magma_apply_in_session(void)
{
    printf("[MAGMA] apply\n");
    gMagmaTint = magma_color((double)gMagmaRed / 255.0,
                             (double)gMagmaGreen / 255.0,
                             (double)gMagmaBlue / 255.0,
                             (double)gMagmaAlpha / 100.0);
    uint64_t windows[64] = {0};
    int windowCount = sb_collect_control_center_windows(windows, 64), hits = 0;
    for (int i = 0; i < windowCount; i++) magma_scan(windows[i], gMagmaTint, false, false, 0, &hits);
    printf("[MAGMA EVO] toggles=%d sliders=%d media=%d background=%d hits=%d windows=%d\n",
           gMagmaColorToggles, gMagmaColorSliders, gMagmaColorMedia, gMagmaColorBackground, hits, windowCount);
    return hits > 0;
}

bool magma_stop_in_session(void)
{
    printf("[MAGMA] stop\n");
    uint64_t white = magma_color(1, 1, 1, 1);
    uint64_t windows[64] = {0};
    int windowCount = sb_collect_control_center_windows(windows, 64), hits = 0;
    for (int i = 0; i < windowCount; i++) magma_scan(windows[i], white, true, false, 0, &hits);
    gMagmaTint = 0;
    return true;
}

void magma_configure(int red, int green, int blue, int alpha,
                     bool colorToggles, bool colorSliders, bool colorMedia, bool colorBackground)
{
    if (red < 0) red = 0; if (red > 255) red = 255;
    if (green < 0) green = 0; if (green > 255) green = 255;
    if (blue < 0) blue = 0; if (blue > 255) blue = 255;
    if (alpha < 5) alpha = 5; if (alpha > 100) alpha = 100;
    gMagmaRed = red;
    gMagmaGreen = green;
    gMagmaBlue = blue;
    gMagmaAlpha = alpha;
    gMagmaColorToggles = colorToggles;
    gMagmaColorSliders = colorSliders;
    gMagmaColorMedia = colorMedia;
    gMagmaColorBackground = colorBackground;
}

void magma_forget_remote_state(void) { gMagmaTint = 0; }
