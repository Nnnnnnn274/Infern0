#import "securecc.h"
#import "../remote_objc.h"
#import "../../TaskRop/RemoteCall.h"

#import <Foundation/Foundation.h>
#import <stdio.h>

typedef struct { double x; double y; double width; double height; } SecureCCRect;

static uint64_t gSecureCCBanner = 0;
static bool gSecureCCShowIndicator = true;
static int gSecureCCDelayMs = 750;

static uint64_t securecc_color(double red, double green, double blue, double alpha)
{
    uint64_t UIColor = r_class("UIColor");
    if (!r_is_objc_ptr(UIColor)) return 0;
    return r_msg2_main_raw(UIColor, "colorWithRed:green:blue:alpha:",
                           &red, sizeof(red), &green, sizeof(green),
                           &blue, sizeof(blue), &alpha, sizeof(alpha));
}

static uint64_t securecc_key_window(void)
{
    uint64_t UIApplication = r_class("UIApplication");
    if (!r_is_objc_ptr(UIApplication)) return 0;
    uint64_t app = r_msg2_main(UIApplication, "sharedApplication", 0, 0, 0, 0);
    return r_is_objc_ptr(app) ? r_msg2_main(app, "keyWindow", 0, 0, 0, 0) : 0;
}

bool securecc_apply_in_session(void)
{
    printf("[SECURECC] apply\n");
    if (!gSecureCCShowIndicator) {
        if (r_is_objc_ptr(gSecureCCBanner)) r_msg2_main(gSecureCCBanner, "removeFromSuperview", 0, 0, 0, 0);
        gSecureCCBanner = 0;
        return true;
    }
    if (r_is_objc_ptr(gSecureCCBanner)) {
        r_msg2_main(gSecureCCBanner, "removeFromSuperview", 0, 0, 0, 0);
        gSecureCCBanner = 0;
    }
    uint64_t win = securecc_key_window();
    uint64_t UILabel = r_class("UILabel");
    if (!r_is_objc_ptr(win) || !r_is_objc_ptr(UILabel)) return false;
    uint64_t label = r_msg2_main(UILabel, "alloc", 0, 0, 0, 0);
    SecureCCRect frame = { 24, 96, 236, 30 };
    label = r_msg2_main_raw(label, "initWithFrame:", &frame, sizeof(frame), NULL, 0, NULL, 0, NULL, 0);
    if (!r_is_objc_ptr(label)) return false;
    char text[64];
    snprintf(text, sizeof(text), "SecureCC  |  %dms delay", gSecureCCDelayMs);
    uint64_t str = r_nsstr_retained(text);
    if (r_is_objc_ptr(str)) {
        r_msg2_main(label, "setText:", str, 0, 0, 0);
        r_msg2_main(str, "release", 0, 0, 0, 0);
    }
    r_msg2_main(label, "setTextAlignment:", 1, 0, 0, 0);
    uint64_t fg = securecc_color(1, 1, 1, 0.96);
    if (r_is_objc_ptr(fg)) r_msg2_main(label, "setTextColor:", fg, 0, 0, 0);
    uint64_t bg = securecc_color(0.02, 0.08, 0.14, 0.72);
    if (r_is_objc_ptr(bg)) r_msg2_main(label, "setBackgroundColor:", bg, 0, 0, 0);
    uint64_t UIFont = r_class("UIFont");
    if (r_is_objc_ptr(UIFont)) {
        double size = 12.0;
        uint64_t font = r_msg2_main_raw(UIFont, "boldSystemFontOfSize:", &size, sizeof(size), NULL, 0, NULL, 0, NULL, 0);
        if (r_is_objc_ptr(font)) r_msg2_main(label, "setFont:", font, 0, 0, 0);
    }
    uint64_t layer = r_msg2_main(label, "layer", 0, 0, 0, 0);
    if (r_is_objc_ptr(layer)) {
        double radius = 15.0;
        r_msg2_main_raw(layer, "setCornerRadius:", &radius, sizeof(radius), NULL, 0, NULL, 0, NULL, 0);
        r_msg2_main(layer, "setMasksToBounds:", 1, 0, 0, 0);
    }
    r_msg2_main(win, "addSubview:", label, 0, 0, 0);
    gSecureCCBanner = label;
    return true;
}

bool securecc_stop_in_session(void)
{
    printf("[SECURECC] stop\n");
    if (r_is_objc_ptr(gSecureCCBanner)) r_msg2_main(gSecureCCBanner, "removeFromSuperview", 0, 0, 0, 0);
    gSecureCCBanner = 0;
    return true;
}

void securecc_configure(bool showIndicator, int delayMs)
{
    if (delayMs < 0) delayMs = 0;
    if (delayMs > 3000) delayMs = 3000;
    gSecureCCShowIndicator = showIndicator;
    gSecureCCDelayMs = delayMs;
}

void securecc_forget_remote_state(void) { gSecureCCBanner = 0; }
