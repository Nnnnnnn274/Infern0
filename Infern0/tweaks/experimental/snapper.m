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
static int gSnapperX = 44;
static int gSnapperY = 160;
static int gSnapperWidth = 300;
static int gSnapperHeight = 220;
static int gSnapperBorderWidth = 2;
static int gSnapperCornerRadius = 12;

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
    uint64_t white = snapper_color(1, 1, 1, 0.98);
    if (r_is_objc_ptr(white)) r_msg2_main(label, "setTextColor:", white, 0, 0, 0);
    uint64_t UIFont = r_class("UIFont");
    if (r_is_objc_ptr(UIFont)) {
        double size = 12.0;
        uint64_t font = r_msg2_main_raw(UIFont, "boldSystemFontOfSize:", &size, sizeof(size), NULL, 0, NULL, 0, NULL, 0);
        if (r_is_objc_ptr(font)) r_msg2_main(label, "setFont:", font, 0, 0, 0);
    }
    return label;
}

static void snapper_add_handle(uint64_t parent, double x, double y)
{
    uint64_t handle = snapper_alloc_view(x, y, 14.0, 14.0);
    if (!r_is_objc_ptr(handle)) return;
    uint64_t bg = snapper_color(1.0, 0.22, 0.08, 0.96);
    if (r_is_objc_ptr(bg)) r_msg2_main(handle, "setBackgroundColor:", bg, 0, 0, 0);
    uint64_t layer = r_msg2_main(handle, "layer", 0, 0, 0, 0);
    if (r_is_objc_ptr(layer)) {
        double radius = 7.0;
        r_msg2_main_raw(layer, "setCornerRadius:", &radius, sizeof(radius), NULL, 0, NULL, 0, NULL, 0);
        r_msg2_main(layer, "setMasksToBounds:", 1, 0, 0, 0);
    }
    r_msg2_main(parent, "addSubview:", handle, 0, 0, 0);
}

bool snapper_apply_in_session(void)
{
    printf("[SNAPPER] apply\n");
    if (r_is_objc_ptr(gSnapperView)) {
        r_msg2_main(gSnapperView, "removeFromSuperview", 0, 0, 0, 0);
        gSnapperView = 0;
    }
    uint64_t win = snapper_key_window();
    if (!r_is_objc_ptr(win)) return false;
    uint64_t frame = snapper_alloc_view((double)gSnapperX,
                                        (double)gSnapperY,
                                        (double)gSnapperWidth,
                                        (double)gSnapperHeight);
    if (!r_is_objc_ptr(frame)) return false;
    uint64_t clear = snapper_color(0.02, 0.10, 0.18, 0.10);
    if (r_is_objc_ptr(clear)) r_msg2_main(frame, "setBackgroundColor:", clear, 0, 0, 0);
    uint64_t layer = r_msg2_main(frame, "layer", 0, 0, 0, 0);
    if (r_is_objc_ptr(layer)) {
        double borderWidth = (double)gSnapperBorderWidth;
        double radius = (double)gSnapperCornerRadius;
        uint64_t border = snapper_color(1.0, 0.22, 0.08, 0.95);
        uint64_t cg = r_is_objc_ptr(border) ? r_msg2_main(border, "CGColor", 0, 0, 0, 0) : 0;
        if (cg) r_msg2_main(layer, "setBorderColor:", cg, 0, 0, 0);
        r_msg2_main_raw(layer, "setBorderWidth:", &borderWidth, sizeof(borderWidth), NULL, 0, NULL, 0, NULL, 0);
        r_msg2_main_raw(layer, "setCornerRadius:", &radius, sizeof(radius), NULL, 0, NULL, 0, NULL, 0);
    }
    snapper_add_handle(frame, -7.0, -7.0);
    snapper_add_handle(frame, (double)gSnapperWidth - 7.0, -7.0);
    snapper_add_handle(frame, -7.0, (double)gSnapperHeight - 7.0);
    snapper_add_handle(frame, (double)gSnapperWidth - 7.0, (double)gSnapperHeight - 7.0);
    uint64_t label = snapper_alloc_label("Snap");
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

void snapper_configure(int x, int y, int width, int height, int borderWidth, int cornerRadius)
{
    if (x < 0) x = 0; if (x > 220) x = 220;
    if (y < 40) y = 40; if (y > 520) y = 520;
    if (width < 80) width = 80; if (width > 390) width = 390;
    if (height < 80) height = 80; if (height > 640) height = 640;
    if (borderWidth < 1) borderWidth = 1; if (borderWidth > 8) borderWidth = 8;
    if (cornerRadius < 0) cornerRadius = 0; if (cornerRadius > 40) cornerRadius = 40;
    gSnapperX = x;
    gSnapperY = y;
    gSnapperWidth = width;
    gSnapperHeight = height;
    gSnapperBorderWidth = borderWidth;
    gSnapperCornerRadius = cornerRadius;
}

void snapper_forget_remote_state(void) { gSnapperView = 0; }
