#import "securecc.h"
#import "../remote_objc.h"
#import "../sb_walk.h"
#import "../../TaskRop/RemoteCall.h"

#import <Foundation/Foundation.h>
#import <stdio.h>
#import <string.h>

typedef struct { double x; double y; double width; double height; } SecureCCRect;

static uint64_t gSecureCCBanner = 0;
static bool gSecureCCShowIndicator = true;
static int gSecureCCDelayMs = 750;

static bool securecc_is_locked(bool *locked)
{
    if (!locked) return false;
    uint64_t cls = r_class("SBLockScreenManager");
    uint64_t manager = r_is_objc_ptr(cls) ? r_msg2_main(cls, "sharedInstance", 0, 0, 0, 0) : 0;
    if (!r_is_objc_ptr(manager)) return false;
    const char *selector = r_responds_main(manager, "isUILocked") ? "isUILocked" :
                           (r_responds_main(manager, "isLocked") ? "isLocked" : NULL);
    if (!selector) return false;
    *locked = (r_msg2_main(manager, selector, 0, 0, 0, 0) & 0xff) != 0;
    return true;
}

static void securecc_class_name(uint64_t obj, char *out, size_t outLen)
{
    if (!out || outLen == 0) return;
    out[0] = '\0';
    uint64_t cls = r_is_objc_ptr(obj) ? r_dlsym_call(R_TIMEOUT, "object_getClass", obj, 0, 0, 0, 0, 0, 0, 0) : 0;
    uint64_t name = r_is_objc_ptr(cls) ? r_dlsym_call(R_TIMEOUT, "class_getName", cls, 0, 0, 0, 0, 0, 0, 0) : 0;
    if (!name) return;
    uint64_t copy = r_dlsym_call(R_TIMEOUT, "strdup", name, 0, 0, 0, 0, 0, 0, 0);
    if (!copy) return;
    remote_read(copy, out, outLen - 1);
    out[outLen - 1] = '\0';
    r_free(copy);
}

static void securecc_set_controls_enabled(uint64_t view, bool enabled, int depth, int *hits)
{
    if (!r_is_objc_ptr(view) || depth > 14) return;
    char cls[160] = {0};
    securecc_class_name(view, cls, sizeof(cls));
    bool ccControl = (strstr(cls, "CCUI") || strstr(cls, "ControlCenter")) &&
                     (strstr(cls, "Button") || strstr(cls, "Module") || strstr(cls, "Control"));
    if (ccControl && r_responds_main(view, "setUserInteractionEnabled:")) {
        r_msg2_main(view, "setUserInteractionEnabled:", enabled ? 1 : 0, 0, 0, 0);
        if (hits) (*hits)++;
    }
    uint64_t subviews = r_msg2_main(view, "subviews", 0, 0, 0, 0);
    uint64_t count = r_is_objc_ptr(subviews) ? r_msg2_main(subviews, "count", 0, 0, 0, 0) : 0;
    if (count > 160) count = 160;
    for (uint64_t i = 0; i < count; i++)
        securecc_set_controls_enabled(r_msg2_main(subviews, "objectAtIndex:", i, 0, 0, 0), enabled, depth + 1, hits);
}

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
    bool locked = false;
    if (!securecc_is_locked(&locked)) return false;
    uint64_t win = sb_frontmost_window();
    int controls = 0;
    if (r_is_objc_ptr(win)) securecc_set_controls_enabled(win, !locked, 0, &controls);
    if (!locked || !gSecureCCShowIndicator) {
        if (r_is_objc_ptr(gSecureCCBanner)) r_msg2_main(gSecureCCBanner, "removeFromSuperview", 0, 0, 0, 0);
        gSecureCCBanner = 0;
        return true;
    }
    if (r_is_objc_ptr(gSecureCCBanner) &&
        r_is_objc_ptr(r_msg2_main(gSecureCCBanner, "superview", 0, 0, 0, 0))) return true;
    if (r_is_objc_ptr(gSecureCCBanner)) {
        r_msg2_main(gSecureCCBanner, "removeFromSuperview", 0, 0, 0, 0);
        gSecureCCBanner = 0;
    }
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
    uint64_t win = sb_frontmost_window();
    if (r_is_objc_ptr(win)) securecc_set_controls_enabled(win, true, 0, NULL);
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
