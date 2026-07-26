//
//  magsafe_enabler.m
//  Based on MinePlayer16/cyanide's MagSafe Enabler (Iggy05), rewritten for
//  Infern0 with an owned touch-through overlay window and bounded lifecycle.
//

#import "magsafe_enabler.h"
#import "../remote_objc.h"
#import "../../LogTextView.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <math.h>
#import <stdio.h>

typedef struct { double x, y, width, height; } MagSafeRect;

static uint64_t s_window = 0;
static uint64_t s_panel = 0;
static uint64_t s_ring = 0;
static uint64_t s_label = 0;
static uint64_t s_animation = 0;
static uint64_t s_animation_key = 0;
static bool s_active = false;
static bool s_visible = false;
static bool s_dirty = true;
static int s_size = 200;
static int s_y = 300;
static int s_ring_width = 12;
static int s_duration_ms = 1200;
static int s_background_alpha = 82;
static int s_accent_style = 0;
static unsigned long long s_show_count = 0;
static unsigned long long s_hide_count = 0;

static uint64_t mag_msg(uint64_t object, const char *selector,
                        uint64_t a0, uint64_t a1, uint64_t a2, uint64_t a3)
{
    if (!r_is_objc_ptr(object) || !selector ||
        !r_responds_main(object, selector)) return 0;
    return r_msg2_main(object, selector, a0, a1, a2, a3);
}

static void mag_set_double(uint64_t object, const char *selector, double value)
{
    if (!r_is_objc_ptr(object) || !r_responds_main(object, selector)) return;
    r_msg2_main_raw(object, selector, &value, sizeof(value),
                    NULL, 0, NULL, 0, NULL, 0);
}

static uint64_t mag_color(double red, double green, double blue, double alpha)
{
    uint64_t cls = r_class("UIColor");
    return r_is_objc_ptr(cls)
        ? r_msg2_main_raw(cls, "colorWithRed:green:blue:alpha:",
                          &red, sizeof(red), &green, sizeof(green),
                          &blue, sizeof(blue), &alpha, sizeof(alpha)) : 0;
}

static uint64_t mag_accent(double batteryLevel)
{
    switch (s_accent_style) {
        case 1: return mag_color(0.20, 0.82, 1.00, 1.0);
        case 2: return mag_color(0.67, 0.38, 1.00, 1.0);
        case 3: return mag_color(1.00, 0.55, 0.15, 1.0);
        default:
            return batteryLevel <= 0.20
                ? mag_color(1.00, 0.22, 0.22, 1.0)
                : mag_color(0.18, 0.90, 0.42, 1.0);
    }
}

static uint64_t mag_window_scene(void)
{
    uint64_t appClass = r_class("UIApplication");
    uint64_t app = r_is_objc_ptr(appClass)
        ? r_msg2_main(appClass, "sharedApplication", 0, 0, 0, 0) : 0;
    if (!r_is_objc_ptr(app)) return 0;
    uint64_t keyWindow = mag_msg(app, "keyWindow", 0, 0, 0, 0);
    uint64_t scene = mag_msg(keyWindow, "windowScene", 0, 0, 0, 0);
    if (r_is_objc_ptr(scene)) return scene;
    uint64_t scenes = mag_msg(app, "connectedScenes", 0, 0, 0, 0);
    if (r_is_objc_ptr(scenes) && r_responds_main(scenes, "allObjects"))
        scenes = mag_msg(scenes, "allObjects", 0, 0, 0, 0);
    uint64_t count = r_is_objc_ptr(scenes)
        ? r_msg2_main(scenes, "count", 0, 0, 0, 0) : 0;
    if (count > 16) count = 16;
    for (uint64_t i = 0; i < count; i++) {
        uint64_t candidate = r_msg2_main(scenes, "objectAtIndex:", i, 0, 0, 0);
        if (r_is_objc_ptr(candidate) &&
            r_responds_main(candidate, "windows")) return candidate;
    }
    return 0;
}

static uint64_t mag_new_view(const char *className, MagSafeRect frame)
{
    uint64_t cls = r_class(className);
    uint64_t alloc = r_is_objc_ptr(cls)
        ? r_msg2_main(cls, "alloc", 0, 0, 0, 0) : 0;
    return r_is_objc_ptr(alloc)
        ? r_msg2_main_raw(alloc, "initWithFrame:",
                          &frame, sizeof(frame), NULL, 0, NULL, 0, NULL, 0) : 0;
}

void magsafe_enabler_configure(int size,
                               int yPosition,
                               int ringWidth,
                               int animationDurationMs,
                               int backgroundAlphaPercent,
                               int accentStyle)
{
    if (size < 150) size = 150;
    if (size > 280) size = 280;
    if (yPosition < 80) yPosition = 80;
    if (yPosition > 620) yPosition = 620;
    if (ringWidth < 4) ringWidth = 4;
    if (ringWidth > 26) ringWidth = 26;
    if (animationDurationMs < 350) animationDurationMs = 350;
    if (animationDurationMs > 3000) animationDurationMs = 3000;
    if (backgroundAlphaPercent < 20) backgroundAlphaPercent = 20;
    if (backgroundAlphaPercent > 100) backgroundAlphaPercent = 100;
    if (accentStyle < 0) accentStyle = 0;
    if (accentStyle > 3) accentStyle = 3;
    if (s_size != size || s_y != yPosition || s_ring_width != ringWidth ||
        s_duration_ms != animationDurationMs ||
        s_background_alpha != backgroundAlphaPercent ||
        s_accent_style != accentStyle) s_dirty = true;
    s_size = size;
    s_y = yPosition;
    s_ring_width = ringWidth;
    s_duration_ms = animationDurationMs;
    s_background_alpha = backgroundAlphaPercent;
    s_accent_style = accentStyle;
    log_user("[MAGSAFE][CONFIG] size=%dpt y=%dpt ring=%dpt animation=%dms background=%d%% accent=%d trigger=battery-state.\n",
             s_size, s_y, s_ring_width, s_duration_ms,
             s_background_alpha, s_accent_style);
}

bool magsafe_enabler_stop_in_session(void)
{
    bool removed = r_is_objc_ptr(s_window) || r_is_objc_ptr(s_panel);
    if (r_is_objc_ptr(s_window)) r_msg2_main(s_window, "setHidden:", 1, 0, 0, 0);
    if (r_is_objc_ptr(s_panel)) {
        r_msg2_main(s_panel, "removeFromSuperview", 0, 0, 0, 0);
        r_msg2_main(s_panel, "release", 0, 0, 0, 0);
    }
    if (r_is_objc_ptr(s_animation))
        r_msg2_main(s_animation, "release", 0, 0, 0, 0);
    if (r_is_objc_ptr(s_animation_key))
        r_msg2_main(s_animation_key, "release", 0, 0, 0, 0);
    if (r_is_objc_ptr(s_window))
        r_msg2_main(s_window, "release", 0, 0, 0, 0);
    s_window = s_panel = s_ring = s_label = 0;
    s_animation = s_animation_key = 0;
    s_active = false;
    s_visible = false;
    s_dirty = true;
    log_user("[MAGSAFE][RESTORE] overlayRemoved=%d showEvents=%llu hideEvents=%llu stockWindowMutations=0 result=%s.\n",
             removed, s_show_count, s_hide_count,
             removed ? "success" : "already-stock");
    return true;
}

bool magsafe_enabler_apply_in_session(void)
{
    if (s_active && !s_dirty && r_is_objc_ptr(s_window) &&
        r_is_objc_ptr(s_panel)) return true;
    if (s_active || r_is_objc_ptr(s_window) || r_is_objc_ptr(s_panel))
        magsafe_enabler_stop_in_session();

    log_user("[MAGSAFE][1/4] Resolving an active SpringBoard UIWindowScene without private window scanning...\n");
    uint64_t scene = mag_window_scene();
    if (!r_is_objc_ptr(scene)) {
        log_user("[MAGSAFE][FAIL] UIWindowScene unavailable; no overlay objects were attached.\n");
        return false;
    }

    log_user("[MAGSAFE][2/4] Creating an owned touch-through overlay window...\n");
    uint64_t windowClass = r_class("UIWindow");
    uint64_t alloc = r_is_objc_ptr(windowClass)
        ? r_msg2_main(windowClass, "alloc", 0, 0, 0, 0) : 0;
    uint64_t window = r_is_objc_ptr(alloc)
        ? r_msg2_main(alloc, "initWithWindowScene:", scene, 0, 0, 0) : 0;
    if (!r_is_objc_ptr(window)) {
        log_user("[MAGSAFE][FAIL] UIWindow allocation failed; SpringBoard remains untouched.\n");
        return false;
    }
    uint64_t clear = mag_color(0, 0, 0, 0);
    if (r_is_objc_ptr(clear))
        r_msg2_main(window, "setBackgroundColor:", clear, 0, 0, 0);
    r_msg2_main(window, "setUserInteractionEnabled:", 0, 0, 0, 0);
    double windowLevel = 2005.0;
    mag_set_double(window, "setWindowLevel:", windowLevel);

    CGRect screen = UIScreen.mainScreen.bounds;
    MagSafeRect windowFrame = {screen.origin.x, screen.origin.y,
                               screen.size.width, screen.size.height};
    r_msg2_main_raw(window, "setFrame:",
                    &windowFrame, sizeof(windowFrame),
                    NULL, 0, NULL, 0, NULL, 0);
    double size = (double)s_size;
    double x = (screen.size.width - size) * 0.5;
    double y = fmin(fmax((double)s_y, 30.0), screen.size.height - size - 30.0);
    uint64_t panel = mag_new_view("UIView", (MagSafeRect){x, y, size, size});
    if (!r_is_objc_ptr(panel)) {
        r_msg2_main(window, "release", 0, 0, 0, 0);
        log_user("[MAGSAFE][FAIL] Charging panel allocation failed.\n");
        return false;
    }
    uint64_t background = mag_color(0.035, 0.04, 0.055,
                                    (double)s_background_alpha / 100.0);
    if (r_is_objc_ptr(background))
        r_msg2_main(panel, "setBackgroundColor:", background, 0, 0, 0);
    r_msg2_main(panel, "setUserInteractionEnabled:", 0, 0, 0, 0);
    uint64_t panelLayer = mag_msg(panel, "layer", 0, 0, 0, 0);
    mag_set_double(panelLayer, "setCornerRadius:", size * 0.5);
    r_msg2_main(panelLayer, "setMasksToBounds:", 1, 0, 0, 0);

    log_user("[MAGSAFE][3/4] Building the charging ring, percentage label, and animation template...\n");
    uint64_t shapeClass = r_class("CAShapeLayer");
    uint64_t shapeAlloc = r_is_objc_ptr(shapeClass)
        ? r_msg2_main(shapeClass, "alloc", 0, 0, 0, 0) : 0;
    uint64_t ring = r_is_objc_ptr(shapeAlloc)
        ? r_msg2_main(shapeAlloc, "init", 0, 0, 0, 0) : 0;
    double inset = fmax(10.0, (double)s_ring_width);
    uint64_t pathClass = r_class("UIBezierPath");
    MagSafeRect pathRect = {inset, inset, size - inset * 2.0, size - inset * 2.0};
    uint64_t path = r_is_objc_ptr(pathClass)
        ? r_msg2_main_raw(pathClass, "bezierPathWithOvalInRect:",
                          &pathRect, sizeof(pathRect), NULL, 0, NULL, 0, NULL, 0) : 0;
    uint64_t cgPath = mag_msg(path, "CGPath", 0, 0, 0, 0);
    if (r_is_objc_ptr(ring) && cgPath)
        r_msg2_main(ring, "setPath:", cgPath, 0, 0, 0);
    uint64_t clearCG = r_is_objc_ptr(clear)
        ? r_msg2_main(clear, "CGColor", 0, 0, 0, 0) : 0;
    if (r_is_objc_ptr(ring) && clearCG)
        r_msg2_main(ring, "setFillColor:", clearCG, 0, 0, 0);
    mag_set_double(ring, "setLineWidth:", s_ring_width);
    uint64_t round = r_nsstr_retained("round");
    if (r_is_objc_ptr(round)) {
        r_msg2_main(ring, "setLineCap:", round, 0, 0, 0);
        r_msg2_main(round, "release", 0, 0, 0, 0);
    }
    if (r_is_objc_ptr(panelLayer) && r_is_objc_ptr(ring))
        r_msg2_main(panelLayer, "addSublayer:", ring, 0, 0, 0);

    uint64_t label = mag_new_view("UILabel", (MagSafeRect){0, 0, size, size});
    if (r_is_objc_ptr(label)) {
        double fontSize = fmax(26.0, size * 0.17);
        uint64_t fontClass = r_class("UIFont");
        uint64_t font = r_is_objc_ptr(fontClass)
            ? r_msg2_main_raw(fontClass, "boldSystemFontOfSize:",
                              &fontSize, sizeof(fontSize), NULL, 0, NULL, 0, NULL, 0) : 0;
        uint64_t white = mag_color(1, 1, 1, 1);
        if (r_is_objc_ptr(font)) r_msg2_main(label, "setFont:", font, 0, 0, 0);
        if (r_is_objc_ptr(white)) r_msg2_main(label, "setTextColor:", white, 0, 0, 0);
        r_msg2_main(label, "setTextAlignment:", 1, 0, 0, 0);
        r_msg2_main(label, "setUserInteractionEnabled:", 0, 0, 0, 0);
        r_msg2_main(panel, "addSubview:", label, 0, 0, 0);
    }

    uint64_t animationClass = r_class("CABasicAnimation");
    uint64_t key = r_nsstr_retained("strokeEnd");
    uint64_t animation = r_is_objc_ptr(animationClass) && r_is_objc_ptr(key)
        ? r_msg2_main(animationClass, "animationWithKeyPath:", key, 0, 0, 0) : 0;
    if (r_is_objc_ptr(animation)) {
        r_msg2_main(animation, "retain", 0, 0, 0, 0);
        mag_set_double(animation, "setDuration:", (double)s_duration_ms / 1000.0);
        uint64_t numberClass = r_class("NSNumber");
        double zero = 0.0;
        uint64_t from = r_is_objc_ptr(numberClass)
            ? r_msg2_main_raw(numberClass, "numberWithDouble:",
                              &zero, sizeof(zero), NULL, 0, NULL, 0, NULL, 0) : 0;
        if (r_is_objc_ptr(from))
            r_msg2_main(animation, "setFromValue:", from, 0, 0, 0);
    }

    if (!r_is_objc_ptr(ring) || !r_is_objc_ptr(label) ||
        !r_is_objc_ptr(animation) || !r_is_objc_ptr(key)) {
        if (r_is_objc_ptr(ring)) r_msg2_main(ring, "release", 0, 0, 0, 0);
        if (r_is_objc_ptr(label)) r_msg2_main(label, "release", 0, 0, 0, 0);
        if (r_is_objc_ptr(animation)) r_msg2_main(animation, "release", 0, 0, 0, 0);
        if (r_is_objc_ptr(key)) r_msg2_main(key, "release", 0, 0, 0, 0);
        r_msg2_main(panel, "release", 0, 0, 0, 0);
        r_msg2_main(window, "release", 0, 0, 0, 0);
        log_user("[MAGSAFE][FAIL] One or more ring components could not be created.\n");
        return false;
    }

    r_msg2_main(window, "addSubview:", panel, 0, 0, 0);
    r_msg2_main(window, "setHidden:", 1, 0, 0, 0);
    r_msg2_main(ring, "release", 0, 0, 0, 0);
    r_msg2_main(label, "release", 0, 0, 0, 0);
    s_window = window;
    s_panel = panel;
    s_ring = ring;
    s_label = label;
    s_animation = animation;
    s_animation_key = key;
    s_active = true;
    s_visible = false;
    s_dirty = false;
    log_user("[MAGSAFE][4/4] active=1 visible=0 overlayWindow=owned touches=passthrough size=%dpt y=%dpt vmClassScans=0 stockWindowMutations=0.\n",
             s_size, s_y);
    return true;
}

bool magsafe_enabler_show(double batteryLevel)
{
    if (!isfinite(batteryLevel) || batteryLevel < 0.0) batteryLevel = 0.0;
    if (batteryLevel > 1.0) batteryLevel = 1.0;
    if (!s_active || s_dirty || !r_is_objc_ptr(s_window))
        if (!magsafe_enabler_apply_in_session()) return false;

    int percent = (int)lround(batteryLevel * 100.0);
    char text[24] = {0};
    snprintf(text, sizeof(text), "%d%%", percent);
    uint64_t value = r_nsstr_retained(text);
    if (r_is_objc_ptr(value)) {
        r_msg2_main(s_label, "setText:", value, 0, 0, 0);
        r_msg2_main(value, "release", 0, 0, 0, 0);
    }
    uint64_t color = mag_accent(batteryLevel);
    uint64_t cgColor = r_is_objc_ptr(color)
        ? r_msg2_main(color, "CGColor", 0, 0, 0, 0) : 0;
    if (cgColor) r_msg2_main(s_ring, "setStrokeColor:", cgColor, 0, 0, 0);
    uint64_t numberClass = r_class("NSNumber");
    uint64_t toValue = r_is_objc_ptr(numberClass)
        ? r_msg2_main_raw(numberClass, "numberWithDouble:",
                          &batteryLevel, sizeof(batteryLevel),
                          NULL, 0, NULL, 0, NULL, 0) : 0;
    if (r_is_objc_ptr(toValue))
        r_msg2_main(s_animation, "setToValue:", toValue, 0, 0, 0);
    mag_set_double(s_ring, "setStrokeEnd:", batteryLevel);
    r_msg2_main(s_ring, "removeAllAnimations", 0, 0, 0, 0);
    r_msg2_main(s_ring, "addAnimation:forKey:",
                s_animation, s_animation_key, 0, 0);
    r_msg2_main(s_window, "setHidden:", 0, 0, 0, 0);
    s_visible = true;
    s_show_count++;
    log_user("[MAGSAFE][SHOW] event=%llu battery=%d%% accent=%d duration=%dms visible=1.\n",
             s_show_count, percent, s_accent_style, s_duration_ms);
    return true;
}

bool magsafe_enabler_hide(void)
{
    if (!s_active || !r_is_objc_ptr(s_window)) return true;
    if (s_visible) {
        r_msg2_main(s_window, "setHidden:", 1, 0, 0, 0);
        s_visible = false;
        s_hide_count++;
        log_user("[MAGSAFE][HIDE] event=%llu overlayWindowHidden=1 objectsRetainedForNextCharge=1.\n",
                 s_hide_count);
    }
    return true;
}

void magsafe_enabler_forget_remote_state(void)
{
    s_window = s_panel = s_ring = s_label = 0;
    s_animation = s_animation_key = 0;
    s_active = false;
    s_visible = false;
    s_dirty = true;
    log_user("[MAGSAFE][FORGET] cleared stale remote overlay pointers.\n");
}
