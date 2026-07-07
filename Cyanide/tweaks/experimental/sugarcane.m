#import "sugarcane.h"
#import "../remote_objc.h"
#import "../../TaskRop/RemoteCall.h"

#import <Foundation/Foundation.h>

typedef struct { double x; double y; double width; double height; } SugarCaneRect;

static uint64_t gSugarCaneLabel = 0;
static bool gSugarCaneShowBrightness = true;
static bool gSugarCaneShowVolume = true;
static int gSugarCaneFontSize = 13;

static uint64_t sugarcane_key_window(void)
{
    uint64_t UIApplication = r_class("UIApplication");
    if (!r_is_objc_ptr(UIApplication)) return 0;
    uint64_t app = r_msg2_main(UIApplication, "sharedApplication", 0, 0, 0, 0);
    return r_is_objc_ptr(app) ? r_msg2_main(app, "keyWindow", 0, 0, 0, 0) : 0;
}

static uint64_t sugarcane_color(double red, double green, double blue, double alpha)
{
    uint64_t UIColor = r_class("UIColor");
    if (!r_is_objc_ptr(UIColor)) return 0;
    return r_msg2_main_raw(UIColor, "colorWithRed:green:blue:alpha:",
                           &red, sizeof(red), &green, sizeof(green),
                           &blue, sizeof(blue), &alpha, sizeof(alpha));
}

bool sugarcane_apply_in_session(void)
{
    printf("[SUGARCANE] apply\n");
    if (r_is_objc_ptr(gSugarCaneLabel)) {
        r_msg2_main(gSugarCaneLabel, "removeFromSuperview", 0, 0, 0, 0);
        gSugarCaneLabel = 0;
    }
    uint64_t win = sugarcane_key_window();
    uint64_t UILabel = r_class("UILabel");
    if (!r_is_objc_ptr(win) || !r_is_objc_ptr(UILabel)) return false;
    uint64_t label = r_msg2_main(UILabel, "alloc", 0, 0, 0, 0);
    SugarCaneRect frame = { 28, 112, 160, 28 };
    label = r_msg2_main_raw(label, "initWithFrame:", &frame, sizeof(frame), NULL, 0, NULL, 0, NULL, 0);
    if (!r_is_objc_ptr(label)) return false;
    const char *text = "Brightness 50%  Volume 50%";
    if (gSugarCaneShowBrightness && !gSugarCaneShowVolume) text = "Brightness 50%";
    if (!gSugarCaneShowBrightness && gSugarCaneShowVolume) text = "Volume 50%";
    if (!gSugarCaneShowBrightness && !gSugarCaneShowVolume) text = "SugarCane";
    uint64_t str = r_nsstr_retained(text);
    if (r_is_objc_ptr(str)) {
        r_msg2_main(label, "setText:", str, 0, 0, 0);
        r_msg2_main(str, "release", 0, 0, 0, 0);
    }
    uint64_t white = sugarcane_color(1, 1, 1, 0.95);
    if (r_is_objc_ptr(white)) r_msg2_main(label, "setTextColor:", white, 0, 0, 0);
    uint64_t UIFont = r_class("UIFont");
    if (r_is_objc_ptr(UIFont)) {
        double size = (double)gSugarCaneFontSize;
        uint64_t font = r_msg2_main_raw(UIFont, "boldSystemFontOfSize:", &size, sizeof(size), NULL, 0, NULL, 0, NULL, 0);
        if (r_is_objc_ptr(font)) r_msg2_main(label, "setFont:", font, 0, 0, 0);
    }
    r_msg2_main(label, "setTextAlignment:", 1, 0, 0, 0);
    r_msg2_main(win, "addSubview:", label, 0, 0, 0);
    gSugarCaneLabel = label;
    return true;
}

bool sugarcane_stop_in_session(void)
{
    printf("[SUGARCANE] stop\n");
    if (r_is_objc_ptr(gSugarCaneLabel)) r_msg2_main(gSugarCaneLabel, "removeFromSuperview", 0, 0, 0, 0);
    gSugarCaneLabel = 0;
    return true;
}

void sugarcane_configure(bool showBrightness, bool showVolume, int fontSize)
{
    if (fontSize < 10) fontSize = 10;
    if (fontSize > 24) fontSize = 24;
    gSugarCaneShowBrightness = showBrightness;
    gSugarCaneShowVolume = showVolume;
    gSugarCaneFontSize = fontSize;
}

void sugarcane_forget_remote_state(void) { gSugarCaneLabel = 0; }
