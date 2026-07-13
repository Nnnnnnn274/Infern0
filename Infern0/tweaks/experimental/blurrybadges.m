#import "blurrybadges.h"
#import "../remote_objc.h"
#import "../sb_walk.h"
#import "../../TaskRop/RemoteCall.h"

#import <Foundation/Foundation.h>
#import <string.h>

static uint64_t gBlurryBadgesTint = 0;
static int gBlurryBadgesRed = 59;
static int gBlurryBadgesGreen = 140;
static int gBlurryBadgesBlue = 255;
static int gBlurryBadgesAlphaPercent = 92;

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
    if (!out || outLen == 0) return;
    out[0] = '\0';
    if (!r_is_objc_ptr(obj)) return;
    uint64_t cls = r_dlsym_call(R_TIMEOUT, "object_getClass", obj, 0, 0, 0, 0, 0, 0, 0);
    if (!r_is_objc_ptr(cls)) return;
    uint64_t name = r_dlsym_call(R_TIMEOUT, "class_getName", cls, 0, 0, 0, 0, 0, 0, 0);
    if (!name) return;
    uint64_t buf = r_dlsym_call(R_TIMEOUT, "strdup", name, 0, 0, 0, 0, 0, 0, 0);
    if (!buf) return;
    remote_read(buf, out, outLen - 1);
    out[outLen - 1] = '\0';
    r_free(buf);
}

static void blurrybadges_scan_and_tint(uint64_t parent, uint64_t color, int depth, int *hits)
{
    if (!r_is_objc_ptr(parent) || !r_is_objc_ptr(color) || depth > 12) return;

    char cls[128] = {0};
    blurrybadges_class_name(parent, cls, sizeof(cls));
    if (strstr(cls, "Badge")) {
        r_msg2_main(parent, "setTintColor:", color, 0, 0, 0);
        if (r_responds_main(parent, "setTextColor:")) r_msg2_main(parent, "setTextColor:", color, 0, 0, 0);
        if (r_responds_main(parent, "setBackgroundColor:")) r_msg2_main(parent, "setBackgroundColor:", color, 0, 0, 0);
        if (hits) (*hits)++;
    }

    uint64_t subviews = r_msg2_main(parent, "subviews", 0, 0, 0, 0);
    if (!r_is_objc_ptr(subviews)) return;
    uint64_t count = r_msg2_main(subviews, "count", 0, 0, 0, 0);
    if (count > 128) count = 128;
    for (uint64_t i = 0; i < count; i++) {
        uint64_t sv = r_msg2_main(subviews, "objectAtIndex:", i, 0, 0, 0);
        blurrybadges_scan_and_tint(sv, color, depth + 1, hits);
    }
}

bool blurrybadges_apply_in_session(void)
{
    printf("[BLURRYBADGES] apply\n");
    uint64_t win = sb_frontmost_window();
    if (!r_is_objc_ptr(win)) return false;
    gBlurryBadgesTint = blurrybadges_color((double)gBlurryBadgesRed / 255.0,
                                           (double)gBlurryBadgesGreen / 255.0,
                                           (double)gBlurryBadgesBlue / 255.0,
                                           (double)gBlurryBadgesAlphaPercent / 100.0);
    int hits = 0;
    blurrybadges_scan_and_tint(win, gBlurryBadgesTint, 0, &hits);
    printf("[BLURRYBADGES] tinted %d badge-ish views\n", hits);
    return hits > 0;
}

bool blurrybadges_stop_in_session(void)
{
    printf("[BLURRYBADGES] stop\n");
    uint64_t win = sb_frontmost_window();
    uint64_t red = blurrybadges_color(1.0, 0.23, 0.19, 1.0);
    int hits = 0;
    if (r_is_objc_ptr(win)) blurrybadges_scan_and_tint(win, red, 0, &hits);
    gBlurryBadgesTint = 0;
    return true;
}

void blurrybadges_configure(int red, int green, int blue, int alphaPercent)
{
    if (red < 0) red = 0; if (red > 255) red = 255;
    if (green < 0) green = 0; if (green > 255) green = 255;
    if (blue < 0) blue = 0; if (blue > 255) blue = 255;
    if (alphaPercent < 10) alphaPercent = 10; if (alphaPercent > 100) alphaPercent = 100;
    gBlurryBadgesRed = red;
    gBlurryBadgesGreen = green;
    gBlurryBadgesBlue = blue;
    gBlurryBadgesAlphaPercent = alphaPercent;
}

void blurrybadges_forget_remote_state(void) { gBlurryBadgesTint = 0; }
