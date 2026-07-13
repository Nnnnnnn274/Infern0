#import "pullover.h"
#import "../remote_objc.h"
#import "../sb_walk.h"
#import "../../TaskRop/RemoteCall.h"

#import <Foundation/Foundation.h>

typedef struct {
    double x;
    double y;
    double width;
    double height;
} PullOverRect;

static uint64_t gPullOverView = 0;
static int gPullOverWidth = 76;
static int gPullOverYOffset = 130;
static int gPullOverMaxHeight = 420;
static int gPullOverCornerRadius = 20;
static int gPullOverBackgroundAlphaPercent = 88;

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
    PullOverRect frame = { 8, 230, 60, 24 };
    label = r_msg2_main_raw(label, "initWithFrame:", &frame, sizeof(frame), NULL, 0, NULL, 0, NULL, 0);
    if (!r_is_objc_ptr(label)) return 0;
    uint64_t str = r_nsstr_retained("App");
    if (r_is_objc_ptr(str)) {
        r_msg2_main(label, "setText:", str, 0, 0, 0);
        r_msg2_main(str, "release", 0, 0, 0, 0);
    }
    r_msg2_main(label, "setTextAlignment:", 1, 0, 0, 0);
    uint64_t white = pullover_color(1, 1, 1, 0.92);
    if (r_is_objc_ptr(white)) r_msg2_main(label, "setTextColor:", white, 0, 0, 0);
    uint64_t UIFont = r_class("UIFont");
    if (r_is_objc_ptr(UIFont)) {
        double size = 13.0;
        uint64_t font = r_msg2_main_raw(UIFont, "boldSystemFontOfSize:", &size, sizeof(size), NULL, 0, NULL, 0, NULL, 0);
        if (r_is_objc_ptr(font)) r_msg2_main(label, "setFont:", font, 0, 0, 0);
    }
    return label;
}

static void pullover_add_grabber(uint64_t tray, double trayWidth)
{
    uint64_t grabber = pullover_alloc_view((trayWidth - 5.0) / 2.0, 18.0, 5.0, 44.0);
    if (!r_is_objc_ptr(grabber)) return;
    uint64_t bg = pullover_color(1, 1, 1, 0.52);
    if (r_is_objc_ptr(bg)) r_msg2_main(grabber, "setBackgroundColor:", bg, 0, 0, 0);
    uint64_t layer = r_msg2_main(grabber, "layer", 0, 0, 0, 0);
    if (r_is_objc_ptr(layer)) {
        double radius = 2.5;
        r_msg2_main_raw(layer, "setCornerRadius:", &radius, sizeof(radius), NULL, 0, NULL, 0, NULL, 0);
        r_msg2_main(layer, "setMasksToBounds:", 1, 0, 0, 0);
    }
    r_msg2_main(tray, "addSubview:", grabber, 0, 0, 0);
}

static void pullover_add_icon_slot(uint64_t tray, double x, double y, double side)
{
    uint64_t slot = pullover_alloc_view(x, y, side, side);
    if (!r_is_objc_ptr(slot)) return;
    uint64_t bg = pullover_color(1, 1, 1, 0.14);
    if (r_is_objc_ptr(bg)) r_msg2_main(slot, "setBackgroundColor:", bg, 0, 0, 0);
    uint64_t layer = r_msg2_main(slot, "layer", 0, 0, 0, 0);
    if (r_is_objc_ptr(layer)) {
        double radius = side * 0.24;
        r_msg2_main_raw(layer, "setCornerRadius:", &radius, sizeof(radius), NULL, 0, NULL, 0, NULL, 0);
        r_msg2_main(layer, "setMasksToBounds:", 1, 0, 0, 0);
    }
    r_msg2_main(tray, "addSubview:", slot, 0, 0, 0);
}

bool pullover_apply_in_session(void)
{
    printf("[PULLOVER] apply\n");
    if (r_is_objc_ptr(gPullOverView)) {
        r_msg2_main(gPullOverView, "removeFromSuperview", 0, 0, 0, 0);
        gPullOverView = 0;
    }
    uint64_t win = sb_frontmost_window();
    if (!r_is_objc_ptr(win)) return false;
    PullOverRect bounds = pullover_bounds_for_view(win);
    double trayHeight = bounds.height - 260.0;
    if (trayHeight < 260.0) trayHeight = 260.0;
    if (trayHeight > (double)gPullOverMaxHeight) trayHeight = (double)gPullOverMaxHeight;
    uint64_t tray = pullover_alloc_view(bounds.width - (double)gPullOverWidth - 8.0,
                                        (double)gPullOverYOffset,
                                        (double)gPullOverWidth,
                                        trayHeight);
    if (!r_is_objc_ptr(tray)) return false;
    uint64_t bg = pullover_color(0.05, 0.06, 0.07, (double)gPullOverBackgroundAlphaPercent / 100.0);
    if (r_is_objc_ptr(bg)) r_msg2_main(tray, "setBackgroundColor:", bg, 0, 0, 0);
    uint64_t layer = r_msg2_main(tray, "layer", 0, 0, 0, 0);
    if (r_is_objc_ptr(layer)) {
        double radius = (double)gPullOverCornerRadius;
        r_msg2_main_raw(layer, "setCornerRadius:", &radius, sizeof(radius), NULL, 0, NULL, 0, NULL, 0);
        r_msg2_main(layer, "setMasksToBounds:", 1, 0, 0, 0);
    }
    pullover_add_grabber(tray, (double)gPullOverWidth);
    double iconSide = (double)gPullOverWidth - 24.0;
    if (iconSide < 32.0) iconSide = 32.0;
    if (iconSide > 64.0) iconSide = 64.0;
    pullover_add_icon_slot(tray, ((double)gPullOverWidth - iconSide) / 2.0, 88.0, iconSide);
    pullover_add_icon_slot(tray, ((double)gPullOverWidth - iconSide) / 2.0, 156.0, iconSide);
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

void pullover_configure(int width, int yOffset, int maxHeight, int cornerRadius, int backgroundAlphaPercent)
{
    if (width < 52) width = 52; if (width > 140) width = 140;
    if (yOffset < 40) yOffset = 40; if (yOffset > 300) yOffset = 300;
    if (maxHeight < 220) maxHeight = 220; if (maxHeight > 720) maxHeight = 720;
    if (cornerRadius < 0) cornerRadius = 0; if (cornerRadius > 40) cornerRadius = 40;
    if (backgroundAlphaPercent < 20) backgroundAlphaPercent = 20; if (backgroundAlphaPercent > 100) backgroundAlphaPercent = 100;
    gPullOverWidth = width;
    gPullOverYOffset = yOffset;
    gPullOverMaxHeight = maxHeight;
    gPullOverCornerRadius = cornerRadius;
    gPullOverBackgroundAlphaPercent = backgroundAlphaPercent;
}

void pullover_forget_remote_state(void) { gPullOverView = 0; }
