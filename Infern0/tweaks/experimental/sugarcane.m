#import "sugarcane.h"
#import "../remote_objc.h"
#import "../sb_walk.h"
#import "../../TaskRop/RemoteCall.h"

#import <Foundation/Foundation.h>
#import <stdio.h>
#import <string.h>

typedef struct { double x; double y; double width; double height; } SugarCaneRect;

static uint64_t gSugarCaneLabels[8] = {0};
static uint64_t gSugarCaneHosts[8] = {0};
static int gSugarCaneLabelCount = 0;
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

static void sugarcane_class_name(uint64_t obj, char *out, size_t outLen)
{
    if (!out || outLen == 0) return;
    out[0] = '\0';
    if (!r_is_objc_ptr(obj)) return;
    uint64_t cls = r_dlsym_call(R_TIMEOUT, "object_getClass", obj, 0, 0, 0, 0, 0, 0, 0);
    uint64_t name = r_is_objc_ptr(cls) ? r_dlsym_call(R_TIMEOUT, "class_getName", cls, 0, 0, 0, 0, 0, 0, 0) : 0;
    if (!name) return;
    uint64_t buf = r_dlsym_call(R_TIMEOUT, "strdup", name, 0, 0, 0, 0, 0, 0, 0);
    if (!buf) return;
    remote_read(buf, out, outLen - 1);
    out[outLen - 1] = '\0';
    r_free(buf);
}

static SugarCaneRect sugarcane_bounds(uint64_t view)
{
    SugarCaneRect bounds = { 0, 0, 120, 44 };
    if (r_is_objc_ptr(view)) {
        r_msg2_main_struct_ret(view, "bounds", &bounds, sizeof(bounds),
                               NULL, 0, NULL, 0, NULL, 0, NULL, 0);
    }
    if (bounds.width <= 0) bounds.width = 120;
    if (bounds.height <= 0) bounds.height = 44;
    return bounds;
}

static void sugarcane_remove_labels(void)
{
    for (int i = 0; i < gSugarCaneLabelCount && i < 8; i++) {
        if (r_is_objc_ptr(gSugarCaneLabels[i])) {
            r_msg2_main(gSugarCaneLabels[i], "removeFromSuperview", 0, 0, 0, 0);
        }
        gSugarCaneLabels[i] = 0;
        gSugarCaneHosts[i] = 0;
    }
    gSugarCaneLabelCount = 0;
}

static bool sugarcane_read_percent(uint64_t host, int *percent)
{
    if (!r_is_objc_ptr(host) || !percent) return false;
    float value = 0.0f;
    bool ok = r_responds_main(host, "value") &&
              r_msg2_main_struct_ret(host, "value", &value, sizeof(value),
                                     NULL, 0, NULL, 0, NULL, 0, NULL, 0);
    if (!ok && r_responds_main(host, "sliderValue")) {
        ok = r_msg2_main_struct_ret(host, "sliderValue", &value, sizeof(value),
                                    NULL, 0, NULL, 0, NULL, 0, NULL, 0);
    }
    if (!ok) return false;
    if (value < 0.0f) value = 0.0f;
    if (value > 1.0f) value = 1.0f;
    *percent = (int)(value * 100.0f + 0.5f);
    return true;
}

static void sugarcane_update_label(uint64_t label, uint64_t host)
{
    int percent = 0;
    if (!r_is_objc_ptr(label) || !sugarcane_read_percent(host, &percent)) return;
    char text[16] = {0};
    snprintf(text, sizeof(text), "%d%%", percent);
    uint64_t str = r_nsstr_retained(text);
    if (r_is_objc_ptr(str)) {
        r_msg2_main(label, "setText:", str, 0, 0, 0);
        r_msg2_main(str, "release", 0, 0, 0, 0);
    }
}

static uint64_t sugarcane_alloc_percent_label(uint64_t host, const char *text)
{
    uint64_t UILabel = r_class("UILabel");
    if (!r_is_objc_ptr(host) || !r_is_objc_ptr(UILabel)) return 0;
    SugarCaneRect bounds = sugarcane_bounds(host);
    double w = 48.0;
    double h = 22.0;
    double x = bounds.width - w - 8.0;
    double y = (bounds.height - h) / 2.0;
    if (x < 6.0) x = 6.0;
    if (y < 4.0) y = 4.0;
    SugarCaneRect frame = { x, y, w, h };
    uint64_t label = r_msg2_main(UILabel, "alloc", 0, 0, 0, 0);
    label = r_msg2_main_raw(label, "initWithFrame:", &frame, sizeof(frame), NULL, 0, NULL, 0, NULL, 0);
    if (!r_is_objc_ptr(label)) return 0;

    uint64_t str = r_nsstr_retained(text ?: "--%");
    if (r_is_objc_ptr(str)) {
        r_msg2_main(label, "setText:", str, 0, 0, 0);
        r_msg2_main(str, "release", 0, 0, 0, 0);
    }
    r_msg2_main(label, "setTextAlignment:", 1, 0, 0, 0);

    uint64_t UIFont = r_class("UIFont");
    if (r_is_objc_ptr(UIFont)) {
        double size = (double)gSugarCaneFontSize;
        uint64_t font = r_msg2_main_raw(UIFont, "boldSystemFontOfSize:", &size, sizeof(size), NULL, 0, NULL, 0, NULL, 0);
        if (r_is_objc_ptr(font)) r_msg2_main(label, "setFont:", font, 0, 0, 0);
    }
    uint64_t textColor = sugarcane_color(1, 1, 1, 0.96);
    if (r_is_objc_ptr(textColor)) r_msg2_main(label, "setTextColor:", textColor, 0, 0, 0);
    uint64_t bg = sugarcane_color(0, 0, 0, 0.28);
    if (r_is_objc_ptr(bg)) r_msg2_main(label, "setBackgroundColor:", bg, 0, 0, 0);
    uint64_t layer = r_msg2_main(label, "layer", 0, 0, 0, 0);
    if (r_is_objc_ptr(layer)) {
        double radius = 11.0;
        r_msg2_main_raw(layer, "setCornerRadius:", &radius, sizeof(radius), NULL, 0, NULL, 0, NULL, 0);
        r_msg2_main(layer, "setMasksToBounds:", 1, 0, 0, 0);
    }
    return label;
}

static void sugarcane_scan_sliders(uint64_t parent, int depth, int *hits)
{
    if (!r_is_objc_ptr(parent) || depth > 14 || gSugarCaneLabelCount >= 8) return;
    char cls[160] = {0};
    sugarcane_class_name(parent, cls, sizeof(cls));
    bool isBrightness = strstr(cls, "Brightness") != NULL;
    bool isVolume = strstr(cls, "Volume") != NULL;
    bool isSlider = strstr(cls, "Slider") != NULL;
    if (((isBrightness && gSugarCaneShowBrightness) || (isVolume && gSugarCaneShowVolume) ||
         (isSlider && (gSugarCaneShowBrightness || gSugarCaneShowVolume))) && gSugarCaneLabelCount < 8) {
        int percent = 0;
        bool readValue = sugarcane_read_percent(parent, &percent);
        char text[16] = "--%";
        if (readValue) snprintf(text, sizeof(text), "%d%%", percent);
        uint64_t label = sugarcane_alloc_percent_label(parent, text);
        if (r_is_objc_ptr(label)) {
            r_msg2_main(parent, "addSubview:", label, 0, 0, 0);
            gSugarCaneLabels[gSugarCaneLabelCount] = label;
            gSugarCaneHosts[gSugarCaneLabelCount] = parent;
            gSugarCaneLabelCount++;
            if (hits) (*hits)++;
        }
    }
    uint64_t subviews = r_msg2_main(parent, "subviews", 0, 0, 0, 0);
    if (!r_is_objc_ptr(subviews)) return;
    uint64_t count = r_msg2_main(subviews, "count", 0, 0, 0, 0);
    if (count > 160) count = 160;
    for (uint64_t i = 0; i < count; i++) {
        sugarcane_scan_sliders(r_msg2_main(subviews, "objectAtIndex:", i, 0, 0, 0), depth + 1, hits);
    }
}

bool sugarcane_apply_in_session(void)
{
    int liveLabels = 0;
    for (int i = 0; i < gSugarCaneLabelCount && i < 8; i++) {
        uint64_t superview = r_is_objc_ptr(gSugarCaneLabels[i]) ?
            r_msg2_main(gSugarCaneLabels[i], "superview", 0, 0, 0, 0) : 0;
        if (r_is_objc_ptr(superview) && r_is_objc_ptr(gSugarCaneHosts[i])) {
            sugarcane_update_label(gSugarCaneLabels[i], gSugarCaneHosts[i]);
            liveLabels++;
        }
    }
    if (liveLabels > 0) return true;
    sugarcane_remove_labels();
    uint64_t win = sb_frontmost_window();
    if (!r_is_objc_ptr(win)) return false;
    int hits = 0;
    sugarcane_scan_sliders(win, 0, &hits);
    if (hits > 0) printf("[SUGARCANE] added %d slider percent labels\n", hits);
    return hits > 0;
}

bool sugarcane_stop_in_session(void)
{
    printf("[SUGARCANE] stop\n");
    sugarcane_remove_labels();
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

void sugarcane_forget_remote_state(void)
{
    for (int i = 0; i < 8; i++) {
        gSugarCaneLabels[i] = 0;
        gSugarCaneHosts[i] = 0;
    }
    gSugarCaneLabelCount = 0;
}
