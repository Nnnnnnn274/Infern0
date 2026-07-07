#import "snapper.h"
#import "../remote_objc.h"
#import "../../TaskRop/RemoteCall.h"

#import <Foundation/Foundation.h>

typedef struct {
    double x;
    double y;
    double width;
    double height;
} SnapperRect;

static uint64_t gSnapperView = 0;

static uint64_t snapper_color(double red, double green, double blue, double alpha)
{
    uint64_t UIColor = r_class("UIColor");
    if (!r_is_objc_ptr(UIColor)) return 0;
    return r_msg2_main_raw(UIColor, "colorWithRed:green:blue:alpha:",
                           &red, sizeof(red),
                           &green, sizeof(green),
                           &blue, sizeof(blue),
                           &alpha, sizeof(alpha));
}

static uint64_t snapper_key_window(void)
{
    uint64_t UIApplication = r_class("UIApplication");
    if (!r_is_objc_ptr(UIApplication)) return 0;
    uint64_t app = r_msg2_main(UIApplication, "sharedApplication", 0, 0, 0, 0);
    if (!r_is_objc_ptr(app)) return 0;
    return r_msg2_main(app, "keyWindow", 0, 0, 0, 0);
}

static uint64_t snapper_alloc_view(double x, double y, double w, double h)
{
    uint64_t UIView = r_class("UIView");
    if (!r_is_objc_ptr(UIView)) return 0;
    uint64_t view = r_msg2_main(UIView, "alloc", 0, 0, 0, 0);
    if (!r_is_objc_ptr(view)) return 0;
    SnapperRect frame = { x, y, w, h };
    view = r_msg2_main_raw(view, "initWithFrame:", &frame, sizeof(frame), NULL, 0, NULL, 0, NULL, 0);
    return r_is_objc_ptr(view) ? view : 0;
}

static uint64_t snapper_alloc_label(const char *text)
{
    uint64_t UILabel = r_class("UILabel");
    if (!r_is_objc_ptr(UILabel)) return 0;
    uint64_t label = r_msg2_main(UILabel, "alloc", 0, 0, 0, 0);
    if (!r_is_objc_ptr(label)) return 0;
    SnapperRect frame = { 8, 8, 120, 24 };
    label = r_msg2_main_raw(label, "initWithFrame:", &frame, sizeof(frame), NULL, 0, NULL, 0, NULL, 0);
    if (!r_is_objc_ptr(label)) return 0;
    uint64_t str = r_nsstr_retained(text ?: "");
    if (r_is_objc_ptr(str)) {
        r_msg2_main(label, "setText:", str, 0, 0, 0);
        r_msg2_main(str, "release", 0, 0, 0, 0);
    }
    return label;
}

bool snapper_apply_in_session(void)
{
    printf("[SNAPPER] apply\n");
    if (r_is_objc_ptr(gSnapperView)) return true;
    uint64_t win = snapper_key_window();
    if (!r_is_objc_ptr(win)) return false;
    uint64_t frame = snapper_alloc_view(44, 160, 300, 220);
    if (!r_is_objc_ptr(frame)) return false;
    uint64_t clear = snapper_color(0.05, 0.18, 0.32, 0.16);
    if (r_is_objc_ptr(clear)) r_msg2_main(frame, "setBackgroundColor:", clear, 0, 0, 0);
    uint64_t layer = r_msg2_main(frame, "layer", 0, 0, 0, 0);
    if (r_is_objc_ptr(layer)) {
        double borderWidth = 2.0;
        double radius = 12.0;
        uint64_t border = snapper_color(0.15, 0.66, 1.0, 0.95);
        uint64_t cg = r_is_objc_ptr(border) ? r_msg2_main(border, "CGColor", 0, 0, 0, 0) : 0;
        if (cg) r_msg2_main(layer, "setBorderColor:", cg, 0, 0, 0);
        r_msg2_main_raw(layer, "setBorderWidth:", &borderWidth, sizeof(borderWidth), NULL, 0, NULL, 0, NULL, 0);
        r_msg2_main_raw(layer, "setCornerRadius:", &radius, sizeof(radius), NULL, 0, NULL, 0, NULL, 0);
    }
    uint64_t label = snapper_alloc_label("Snapper");
    if (r_is_objc_ptr(label)) r_msg2_main(frame, "addSubview:", label, 0, 0, 0);
    r_msg2_main(win, "addSubview:", frame, 0, 0, 0);
    gSnapperView = frame;
    return true;
}

bool snapper_stop_in_session(void)
{
    printf("[SNAPPER] stop\n");
    if (r_is_objc_ptr(gSnapperView)) r_msg2_main(gSnapperView, "removeFromSuperview", 0, 0, 0, 0);
    gSnapperView = 0;
    return true;
}

void snapper_forget_remote_state(void) { gSnapperView = 0; }
