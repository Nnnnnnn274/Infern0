#import "pullover.h"
#import "../remote_objc.h"
#import "../../TaskRop/RemoteCall.h"

#import <Foundation/Foundation.h>

typedef struct {
    double x;
    double y;
    double width;
    double height;
} PullOverRect;

static uint64_t gPullOverView = 0;

static uint64_t pullover_color(double red, double green, double blue, double alpha)
{
    uint64_t UIColor = r_class("UIColor");
    if (!r_is_objc_ptr(UIColor)) return 0;
    return r_msg2_main_raw(UIColor, "colorWithRed:green:blue:alpha:",
                           &red, sizeof(red),
                           &green, sizeof(green),
                           &blue, sizeof(blue),
                           &alpha, sizeof(alpha));
}

static uint64_t pullover_key_window(void)
{
    uint64_t UIApplication = r_class("UIApplication");
    if (!r_is_objc_ptr(UIApplication)) return 0;
    uint64_t app = r_msg2_main(UIApplication, "sharedApplication", 0, 0, 0, 0);
    if (!r_is_objc_ptr(app)) return 0;
    return r_msg2_main(app, "keyWindow", 0, 0, 0, 0);
}

static PullOverRect pullover_bounds_for_view(uint64_t view)
{
    PullOverRect bounds = { 0, 0, 390, 844 };
    if (r_is_objc_ptr(view)) {
        r_msg2_main_struct_ret(view, "bounds", &bounds, sizeof(bounds),
                               NULL, 0, NULL, 0, NULL, 0, NULL, 0);
    }
    if (bounds.width <= 0) bounds.width = 390;
    if (bounds.height <= 0) bounds.height = 844;
    return bounds;
}

static uint64_t pullover_alloc_view(double x, double y, double w, double h)
{
    uint64_t UIView = r_class("UIView");
    if (!r_is_objc_ptr(UIView)) return 0;
    uint64_t view = r_msg2_main(UIView, "alloc", 0, 0, 0, 0);
    if (!r_is_objc_ptr(view)) return 0;
    PullOverRect frame = { x, y, w, h };
    view = r_msg2_main_raw(view, "initWithFrame:", &frame, sizeof(frame), NULL, 0, NULL, 0, NULL, 0);
    return r_is_objc_ptr(view) ? view : 0;
}

static uint64_t pullover_alloc_label(void)
{
    uint64_t UILabel = r_class("UILabel");
    if (!r_is_objc_ptr(UILabel)) return 0;
    uint64_t label = r_msg2_main(UILabel, "alloc", 0, 0, 0, 0);
    if (!r_is_objc_ptr(label)) return 0;
    PullOverRect frame = { 8, 120, 60, 90 };
    label = r_msg2_main_raw(label, "initWithFrame:", &frame, sizeof(frame), NULL, 0, NULL, 0, NULL, 0);
    if (!r_is_objc_ptr(label)) return 0;
    uint64_t str = r_nsstr_retained("Pull\nOver");
    if (r_is_objc_ptr(str)) {
        r_msg2_main(label, "setText:", str, 0, 0, 0);
        r_msg2_main(str, "release", 0, 0, 0, 0);
    }
    r_msg2_main(label, "setNumberOfLines:", 2, 0, 0, 0);
    r_msg2_main(label, "setTextAlignment:", 1, 0, 0, 0);
    return label;
}

bool pullover_apply_in_session(void)
{
    printf("[PULLOVER] apply\n");
    if (r_is_objc_ptr(gPullOverView)) return true;
    uint64_t win = pullover_key_window();
    if (!r_is_objc_ptr(win)) return false;
    PullOverRect bounds = pullover_bounds_for_view(win);
    double trayHeight = bounds.height - 260.0;
    if (trayHeight < 260.0) trayHeight = 260.0;
    if (trayHeight > 420.0) trayHeight = 420.0;
    uint64_t tray = pullover_alloc_view(bounds.width - 84.0, 130, 76, trayHeight);
    if (!r_is_objc_ptr(tray)) return false;
    uint64_t bg = pullover_color(0.08, 0.09, 0.11, 0.88);
    if (r_is_objc_ptr(bg)) r_msg2_main(tray, "setBackgroundColor:", bg, 0, 0, 0);
    uint64_t layer = r_msg2_main(tray, "layer", 0, 0, 0, 0);
    if (r_is_objc_ptr(layer)) {
        double radius = 20.0;
        r_msg2_main_raw(layer, "setCornerRadius:", &radius, sizeof(radius), NULL, 0, NULL, 0, NULL, 0);
        r_msg2_main(layer, "setMasksToBounds:", 1, 0, 0, 0);
    }
    uint64_t label = pullover_alloc_label();
    if (r_is_objc_ptr(label)) r_msg2_main(tray, "addSubview:", label, 0, 0, 0);
    r_msg2_main(win, "addSubview:", tray, 0, 0, 0);
    gPullOverView = tray;
    return true;
}

bool pullover_stop_in_session(void)
{
    printf("[PULLOVER] stop\n");
    if (r_is_objc_ptr(gPullOverView)) r_msg2_main(gPullOverView, "removeFromSuperview", 0, 0, 0, 0);
    gPullOverView = 0;
    return true;
}

void pullover_forget_remote_state(void) { gPullOverView = 0; }
