#import "iconstyles.h"
#import "../remote_objc.h"
#import "../sb_walk.h"
#import "../../TaskRop/RemoteCall.h"

#import <Foundation/Foundation.h>
#import <math.h>
#import <string.h>

typedef struct { double x, y, width, height; } ISRect;
typedef struct { double a, b, c, d, tx, ty; } ISAffineTransform;

static int gRoundedRadius = 18;
static int gWatchCompactPercent = 82;
static int gWatchScalePercent = 88;
static uint64_t gWatchIcons[512] = {0};
static ISRect gWatchFrames[512] = {0};
static int gWatchIconCount = 0;

static bool is_get_rect(uint64_t obj, const char *selector, ISRect *out)
{
    if (!r_is_objc_ptr(obj) || !out || !r_responds_main(obj, selector)) return false;
    memset(out, 0, sizeof(*out));
    return r_msg2_main_struct_ret(obj, selector, out, sizeof(*out),
                                  NULL, 0, NULL, 0, NULL, 0, NULL, 0);
}

static void is_set_rect(uint64_t obj, const char *selector, ISRect value)
{
    if (!r_is_objc_ptr(obj) || !r_responds_main(obj, selector)) return;
    r_msg2_main_raw(obj, selector, &value, sizeof(value), NULL, 0, NULL, 0, NULL, 0);
}

static uint64_t is_icon_image_view(uint64_t icon)
{
    const char *selectors[] = { "_iconImageView", "iconImageView", "_imageView", NULL };
    for (int i = 0; selectors[i]; i++) {
        if (!r_responds_main(icon, selectors[i])) continue;
        uint64_t view = r_msg2_main(icon, selectors[i], 0, 0, 0, 0);
        if (r_is_objc_ptr(view)) return view;
    }
    return icon;
}

static void is_round_view(uint64_t view, double radius)
{
    uint64_t layer = r_is_objc_ptr(view) ? r_msg2_main(view, "layer", 0, 0, 0, 0) : 0;
    if (!r_is_objc_ptr(layer)) return;
    r_msg2_main_raw(layer, "setCornerRadius:", &radius, sizeof(radius), NULL, 0, NULL, 0, NULL, 0);
    r_msg2_main(layer, "setMasksToBounds:", radius > 0.0, 0, 0, 0);
    if (r_responds_main(layer, "setCornerCurve:")) {
        uint64_t curve = r_nsstr_retained("continuous");
        if (r_is_objc_ptr(curve)) {
            r_msg2_main(layer, "setCornerCurve:", curve, 0, 0, 0);
            r_msg2_main(curve, "release", 0, 0, 0, 0);
        }
    }
}

void roundedicons_configure(int cornerRadius)
{
    if (cornerRadius < 0) cornerRadius = 0;
    if (cornerRadius > 36) cornerRadius = 36;
    gRoundedRadius = cornerRadius;
}

bool roundedicons_apply_in_session(void)
{
    uint64_t iconClass = r_class("SBIconView");
    uint64_t icons[512] = {0};
    int count = r_is_objc_ptr(iconClass) ? sb_collect_views_in_windows(iconClass, icons, 512) : 0;
    int rounded = 0;
    for (int i = 0; i < count; i++) {
        uint64_t icon = icons[i];
        uint64_t image = is_icon_image_view(icon);
        if (!r_is_objc_ptr(image)) continue;
        is_round_view(image, (double)gRoundedRadius);
        r_msg2_main(icon, "setUserInteractionEnabled:", 1, 0, 0, 0);
        rounded++;
    }
    printf("[ROUNDEDICONS] radius=%d applied=%d discovered=%d taps=preserved\n",
           gRoundedRadius, rounded, count);
    return rounded > 0;
}

bool roundedicons_stop_in_session(void)
{
    uint64_t iconClass = r_class("SBIconView");
    uint64_t icons[512] = {0};
    int count = r_is_objc_ptr(iconClass) ? sb_collect_views_in_windows(iconClass, icons, 512) : 0;
    for (int i = 0; i < count; i++) is_round_view(is_icon_image_view(icons[i]), 0.0);
    printf("[ROUNDEDICONS] restored=%d\n", count);
    return true;
}

void roundedicons_forget_remote_state(void) {}

void watchlayout_configure(int compactPercent, int iconScalePercent)
{
    if (compactPercent < 60) compactPercent = 60;
    if (compactPercent > 100) compactPercent = 100;
    if (iconScalePercent < 60) iconScalePercent = 60;
    if (iconScalePercent > 110) iconScalePercent = 110;
    gWatchCompactPercent = compactPercent;
    gWatchScalePercent = iconScalePercent;
}

static int is_saved_watch_icon_index(uint64_t icon)
{
    for (int i = 0; i < gWatchIconCount; i++) if (gWatchIcons[i] == icon) return i;
    return -1;
}

bool watchlayout_apply_in_session(void)
{
    uint64_t iconClass = r_class("SBIconView");
    uint64_t icons[512] = {0};
    int count = r_is_objc_ptr(iconClass) ? sb_collect_views_in_windows(iconClass, icons, 512) : 0;
    int changed = 0;
    double compact = (double)gWatchCompactPercent / 100.0;
    double scale = (double)gWatchScalePercent / 100.0;
    ISAffineTransform transform = { scale, 0, 0, scale, 0, 0 };
    for (int i = 0; i < count; i++) {
        uint64_t icon = icons[i];
        uint64_t parent = r_is_objc_ptr(icon) ? r_msg2_main(icon, "superview", 0, 0, 0, 0) : 0;
        ISRect frame, bounds;
        if (!r_is_objc_ptr(parent) || !is_get_rect(icon, "frame", &frame) ||
            !is_get_rect(parent, "bounds", &bounds) || frame.width <= 0 || frame.height <= 0) continue;
        int savedIndex = is_saved_watch_icon_index(icon);
        if (savedIndex < 0 && gWatchIconCount < 512) {
            gWatchIcons[gWatchIconCount] = icon;
            gWatchFrames[gWatchIconCount] = frame;
            savedIndex = gWatchIconCount;
            gWatchIconCount++;
        }
        if (savedIndex >= 0) frame = gWatchFrames[savedIndex];
        double cx = frame.x + frame.width * 0.5;
        double cy = frame.y + frame.height * 0.5;
        double pcx = bounds.x + bounds.width * 0.5;
        double pcy = bounds.y + bounds.height * 0.5;
        cx = pcx + (cx - pcx) * compact;
        cy = pcy + (cy - pcy) * compact;
        frame.x = cx - frame.width * 0.5;
        frame.y = cy - frame.height * 0.5;
        is_set_rect(icon, "setFrame:", frame);
        if (r_responds_main(icon, "setTransform:"))
            r_msg2_main_raw(icon, "setTransform:", &transform, sizeof(transform), NULL, 0, NULL, 0, NULL, 0);
        uint64_t image = is_icon_image_view(icon);
        ISRect imageBounds;
        double radius = 30.0 * scale;
        if (is_get_rect(image, "bounds", &imageBounds) && imageBounds.width > 0 && imageBounds.height > 0)
            radius = fmin(imageBounds.width, imageBounds.height) * 0.5;
        is_round_view(image, radius);
        r_msg2_main(icon, "setUserInteractionEnabled:", 1, 0, 0, 0);
        changed++;
    }
    printf("[WATCHLAYOUT] compact=%d%% scale=%d%% icons=%d pages=all-discovered taps=preserved\n",
           gWatchCompactPercent, gWatchScalePercent, changed);
    return changed > 0;
}

bool watchlayout_stop_in_session(void)
{
    ISAffineTransform identity = {1, 0, 0, 1, 0, 0};
    int restored = 0;
    for (int i = 0; i < gWatchIconCount; i++) {
        uint64_t icon = gWatchIcons[i];
        if (!r_is_objc_ptr(icon)) continue;
        is_set_rect(icon, "setFrame:", gWatchFrames[i]);
        if (r_responds_main(icon, "setTransform:"))
            r_msg2_main_raw(icon, "setTransform:", &identity, sizeof(identity), NULL, 0, NULL, 0, NULL, 0);
        is_round_view(is_icon_image_view(icon), 0.0);
        restored++;
    }
    memset(gWatchIcons, 0, sizeof(gWatchIcons));
    memset(gWatchFrames, 0, sizeof(gWatchFrames));
    gWatchIconCount = 0;
    printf("[WATCHLAYOUT] restored=%d\n", restored);
    return true;
}

void watchlayout_forget_remote_state(void)
{
    memset(gWatchIcons, 0, sizeof(gWatchIcons));
    memset(gWatchFrames, 0, sizeof(gWatchFrames));
    gWatchIconCount = 0;
}
