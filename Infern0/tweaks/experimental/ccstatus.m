#import "ccstatus.h"
#import "../remote_objc.h"
#import "../sb_walk.h"
#import "../../TaskRop/RemoteCall.h"

#import <Foundation/Foundation.h>

typedef struct { double x; double y; double width; double height; } CCStatusRect;

static uint64_t gCCStatusLabel = 0;
static bool gCCStatusShowWifi = true;
static bool gCCStatusShowIP = true;
static int gCCStatusYOffset = 70;

static uint64_t ccstatus_color(double red, double green, double blue, double alpha)
{
    uint64_t UIColor = r_class("UIColor");
    if (!r_is_objc_ptr(UIColor)) return 0;
    return r_msg2_main_raw(UIColor, "colorWithRed:green:blue:alpha:",
                           &red, sizeof(red), &green, sizeof(green),
                           &blue, sizeof(blue), &alpha, sizeof(alpha));
}

static uint64_t ccstatus_key_window(void)
{
    uint64_t UIApplication = r_class("UIApplication");
    if (!r_is_objc_ptr(UIApplication)) return 0;
    uint64_t app = r_msg2_main(UIApplication, "sharedApplication", 0, 0, 0, 0);
    return r_is_objc_ptr(app) ? r_msg2_main(app, "keyWindow", 0, 0, 0, 0) : 0;
}

bool ccstatus_apply_in_session(void)
{
    printf("[CCSTATUS] apply\n");
    if (r_is_objc_ptr(gCCStatusLabel)) {
        r_msg2_main(gCCStatusLabel, "removeFromSuperview", 0, 0, 0, 0);
        gCCStatusLabel = 0;
    }
    uint64_t win = sb_frontmost_window();
    uint64_t UILabel = r_class("UILabel");
    if (!r_is_objc_ptr(win) || !r_is_objc_ptr(UILabel)) return false;
    uint64_t label = r_msg2_main(UILabel, "alloc", 0, 0, 0, 0);
    CCStatusRect frame = { 18, (double)gCCStatusYOffset, 330, 30 };
    label = r_msg2_main_raw(label, "initWithFrame:", &frame, sizeof(frame), NULL, 0, NULL, 0, NULL, 0);
    if (!r_is_objc_ptr(label)) return false;
    const char *text = "CCStatus";
    if (gCCStatusShowWifi && gCCStatusShowIP) text = "Wi-Fi Active  |  IP --";
    else if (gCCStatusShowWifi) text = "Wi-Fi Active";
    else if (gCCStatusShowIP) text = "IP --";
    uint64_t str = r_nsstr_retained(text);
    if (r_is_objc_ptr(str)) {
        r_msg2_main(label, "setText:", str, 0, 0, 0);
        r_msg2_main(str, "release", 0, 0, 0, 0);
    }
    r_msg2_main(label, "setTextAlignment:", 1, 0, 0, 0);
    uint64_t white = ccstatus_color(1, 1, 1, 0.94);
    if (r_is_objc_ptr(white)) r_msg2_main(label, "setTextColor:", white, 0, 0, 0);
    uint64_t bg = ccstatus_color(0, 0, 0, 0.22);
    if (r_is_objc_ptr(bg)) r_msg2_main(label, "setBackgroundColor:", bg, 0, 0, 0);
    uint64_t UIFont = r_class("UIFont");
    if (r_is_objc_ptr(UIFont)) {
        double size = 12.0;
        double weight = 0.45;
        uint64_t font = r_msg2_main_raw(UIFont, "systemFontOfSize:weight:",
                                        &size, sizeof(size), &weight, sizeof(weight),
                                        NULL, 0, NULL, 0);
        if (r_is_objc_ptr(font)) r_msg2_main(label, "setFont:", font, 0, 0, 0);
    }
    uint64_t layer = r_msg2_main(label, "layer", 0, 0, 0, 0);
    if (r_is_objc_ptr(layer)) {
        double radius = 15.0;
        r_msg2_main_raw(layer, "setCornerRadius:", &radius, sizeof(radius), NULL, 0, NULL, 0, NULL, 0);
        r_msg2_main(layer, "setMasksToBounds:", 1, 0, 0, 0);
    }
    r_msg2_main(win, "addSubview:", label, 0, 0, 0);
    gCCStatusLabel = label;
    return true;
}

bool ccstatus_stop_in_session(void)
{
    printf("[CCSTATUS] stop\n");
    if (r_is_objc_ptr(gCCStatusLabel)) r_msg2_main(gCCStatusLabel, "removeFromSuperview", 0, 0, 0, 0);
    gCCStatusLabel = 0;
    return true;
}

void ccstatus_configure(bool showWifi, bool showIP, int yOffset)
{
    if (yOffset < 20) yOffset = 20;
    if (yOffset > 180) yOffset = 180;
    gCCStatusShowWifi = showWifi;
    gCCStatusShowIP = showIP;
    gCCStatusYOffset = yOffset;
}

void ccstatus_forget_remote_state(void) { gCCStatusLabel = 0; }
