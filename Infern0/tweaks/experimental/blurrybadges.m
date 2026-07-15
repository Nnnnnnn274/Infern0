#import "blurrybadges.h"
#import "../remote_objc.h"
#import "../sb_walk.h"
#import "../../TaskRop/RemoteCall.h"
#import "../../LogTextView.h"

#import <Foundation/Foundation.h>
#import <string.h>

static uint64_t gBlurryBadgesTint = 0;
static int gBlurryBadgesRed = 59;
static int gBlurryBadgesGreen = 140;
static int gBlurryBadgesBlue = 255;
static int gBlurryBadgesAlphaPercent = 92;
static bool gBlurryBadgesGrowEnabled = true;
static int gBlurryBadgesMaxScalePercent = 160;
static bool gBlurryBadgesConfigDirty = false;
typedef struct { double a, b, c, d, tx, ty; } BlurryBadgesAffine;

static uint64_t blurrybadges_color(double red, double green, double blue, double alpha)
{
    uint64_t UIColor = r_class("UIColor");
    if (!r_is_objc_ptr(UIColor)) return 0;
    return r_msg2_main_raw(UIColor, "colorWithRed:green:blue:alpha:",
                           &red, sizeof(red),
                           &green, sizeof(green),
                           &blue, sizeof(blue),
                           &alpha, sizeof(alpha));
}

static uint64_t blurrybadges_key_window(void)
{
    uint64_t UIApplication = r_class("UIApplication");
    if (!r_is_objc_ptr(UIApplication)) return 0;
    uint64_t app = r_msg2_main(UIApplication, "sharedApplication", 0, 0, 0, 0);
    if (!r_is_objc_ptr(app)) return 0;

    uint64_t windows = r_msg2_main(app, "windows", 0, 0, 0, 0);
    if (r_is_objc_ptr(windows)) {
        uint64_t count = r_msg2_main(windows, "count", 0, 0, 0, 0);
        if (count > 64) count = 64;
        for (uint64_t i = 0; i < count; i++) {
            uint64_t win = r_msg2_main(windows, "objectAtIndex:", i, 0, 0, 0);
            if (!r_is_objc_ptr(win)) continue;
            uint64_t isKey = r_msg2_main(win, "isKeyWindow", 0, 0, 0, 0);
            if (isKey & 0xff) return win;
        }
    }
    return r_msg2_main(app, "keyWindow", 0, 0, 0, 0);
}

static void blurrybadges_class_name(uint64_t obj, char *out, size_t outLen)
{
    (void)sb_read_class_name(obj, out, outLen);
}

static int blurrybadges_count(uint64_t badge)
{
    const char *selectors[] = { "badgeValue", "text", "string" };
    for (int i = 0; i < 3; i++) {
        if (!r_responds_main(badge, selectors[i])) continue;
        uint64_t value = r_msg2_main(badge, selectors[i], 0, 0, 0, 0);
        if (r_is_objc_ptr(value) && r_responds_main(value, "integerValue")) {
            int count = (int)r_msg2_main(value, "integerValue", 0, 0, 0, 0);
            if (count > 0) return count;
        }
    }
    return 1;
}

static void blurrybadges_scan_and_tint(uint64_t parent, uint64_t color, bool restore,
                                       int depth, int *visited, int *hits, int *grown)
{
    if (!r_is_objc_ptr(parent) || !r_is_objc_ptr(color) || depth > 10 ||
        !visited || *visited >= 640 || (hits && *hits >= 128)) return;
    (*visited)++;

    char cls[128] = {0};
    blurrybadges_class_name(parent, cls, sizeof(cls));
    if (strstr(cls, "IconBadge") || strstr(cls, "SBIconBadge")) {
        sb_cc_override_object("blurrybadges", parent, "tintColor", "setTintColor:", color);
        if (r_responds_main(parent, "setTextColor:")) sb_cc_override_object("blurrybadges", parent, "textColor", "setTextColor:", color);
        if (r_responds_main(parent, "setBackgroundColor:")) sb_cc_override_object("blurrybadges", parent, "backgroundColor", "setBackgroundColor:", color);
        if (gBlurryBadgesGrowEnabled && r_responds_main(parent, "setTransform:")) {
            int count = restore ? 1 : blurrybadges_count(parent);
            if (count > 99) count = 99;
            double scale = (!restore && gBlurryBadgesGrowEnabled)
                ? 1.0 + ((double)(count - 1) / 98.0) * ((double)(gBlurryBadgesMaxScalePercent - 100) / 100.0)
                : 1.0;
            BlurryBadgesAffine transform = { scale, 0, 0, scale, 0, 0 };
            sb_cc_override_bytes("blurrybadges", parent, "transform", "setTransform:", &transform, sizeof(transform));
            if (scale > 1.001 && grown) (*grown)++;
        }
        if (hits) (*hits)++;
    }

    uint64_t subviews = r_msg2_main(parent, "subviews", 0, 0, 0, 0);
    if (!r_is_objc_ptr(subviews)) return;
    uint64_t count = r_msg2_main(subviews, "count", 0, 0, 0, 0);
    if (count > 128) count = 128;
    for (uint64_t i = 0; i < count; i++) {
        uint64_t sv = r_msg2_main(subviews, "objectAtIndex:", i, 0, 0, 0);
        blurrybadges_scan_and_tint(sv, color, restore, depth + 1, visited, hits, grown);
    }
}

bool blurrybadges_apply_in_session(void)
{
    printf("[BLURRYBADGES] apply\n");
    if (gBlurryBadgesConfigDirty) {
        int restored = sb_cc_restore_owner("blurrybadges");
        log_user("[BLURRYBADGES][RECONFIGURE] exactPriorProperties=%d.\n", restored);
        gBlurryBadgesConfigDirty = false;
    }
    gBlurryBadgesTint = blurrybadges_color((double)gBlurryBadgesRed / 255.0,
                                           (double)gBlurryBadgesGreen / 255.0,
                                           (double)gBlurryBadgesBlue / 255.0,
                                           (double)gBlurryBadgesAlphaPercent / 100.0);
    uint64_t windows[64] = {0};
    int windowCount = sb_collect_windows(windows, 64), visited = 0, hits = 0, grown = 0;
    for (int i = 0; i < windowCount; i++)
        blurrybadges_scan_and_tint(windows[i], gBlurryBadgesTint, false, 0, &visited, &hits, &grown);
    printf("[BLURRYBADGES] visited=%d tinted=%d grown=%d maxScale=%d%% windows=%d\n", visited, hits, grown, gBlurryBadgesMaxScalePercent, windowCount);
    return hits > 0;
}

bool blurrybadges_stop_in_session(void)
{
    printf("[BLURRYBADGES] stop\n");
    int hits = sb_cc_restore_owner("blurrybadges");
    gBlurryBadgesTint = 0;
    return hits > 0;
}

void blurrybadges_configure(int red, int green, int blue, int alphaPercent,
                            bool growEnabled, int maxScalePercent)
{
    if (red < 0) red = 0; if (red > 255) red = 255;
    if (green < 0) green = 0; if (green > 255) green = 255;
    if (blue < 0) blue = 0; if (blue > 255) blue = 255;
    if (alphaPercent < 10) alphaPercent = 10; if (alphaPercent > 100) alphaPercent = 100;
    if (maxScalePercent < 100) maxScalePercent = 100;
    if (maxScalePercent > 220) maxScalePercent = 220;
    if (gBlurryBadgesRed != red || gBlurryBadgesGreen != green ||
        gBlurryBadgesBlue != blue || gBlurryBadgesAlphaPercent != alphaPercent ||
        gBlurryBadgesGrowEnabled != growEnabled ||
        gBlurryBadgesMaxScalePercent != maxScalePercent)
        gBlurryBadgesConfigDirty = true;
    gBlurryBadgesRed = red;
    gBlurryBadgesGreen = green;
    gBlurryBadgesBlue = blue;
    gBlurryBadgesAlphaPercent = alphaPercent;
    gBlurryBadgesGrowEnabled = growEnabled;
    gBlurryBadgesMaxScalePercent = maxScalePercent;
}

void blurrybadges_forget_remote_state(void) { gBlurryBadgesTint = 0; gBlurryBadgesConfigDirty = false; sb_cc_forget_owner("blurrybadges"); }
