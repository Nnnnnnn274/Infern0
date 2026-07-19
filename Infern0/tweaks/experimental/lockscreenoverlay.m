//
//  lockscreenoverlay.m
//  Standalone, Watch Layout-style RemoteCall overlay for the Cover Sheet.
//

#import "lockscreenoverlay.h"
#import "../remote_objc.h"
#import "../../LogTextView.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <stdio.h>
#import <string.h>

typedef struct { double x, y, width, height; } LSOFrame;

typedef struct {
    uint64_t view;
    bool originalHidden;
} LSOHiddenView;

enum {
    LSO_MAX_HIDDEN = 64,
    LSO_MAX_VISITED = 384,
    LSO_OVERLAY_TAG = 0x4C534F56, // "LSOV"
};

static uint64_t s_overlay = 0;
static uint64_t s_time_label = 0;
static uint64_t s_date_label = 0;
static uint64_t s_status_label = 0;
static uint64_t s_host_window = 0;
static LSOHiddenView s_hidden[LSO_MAX_HIDDEN];
static int s_hidden_count = 0;
static bool s_active = false;
static bool s_config_dirty = true;
static int s_vertical_offset = 0;
static int s_width_percent = 88;
static int s_accent_style = 0;
static int s_glass_alpha = 72;
static bool s_hide_quick_actions = true;
static bool s_hide_page_dots = true;

static uint64_t lso_safe_msg(uint64_t object, const char *selector,
                             uint64_t a0, uint64_t a1, uint64_t a2, uint64_t a3)
{
    if (!r_is_objc_ptr(object) || !selector || !r_responds_main(object, selector)) return 0;
    return r_msg2_main(object, selector, a0, a1, a2, a3);
}

static void lso_set_frame(uint64_t object, LSOFrame frame)
{
    if (!r_is_objc_ptr(object) || !r_responds_main(object, "setFrame:")) return;
    r_msg2_main_raw(object, "setFrame:", &frame, sizeof(frame),
                    NULL, 0, NULL, 0, NULL, 0);
}

static void lso_set_double(uint64_t object, const char *selector, double value)
{
    if (!r_is_objc_ptr(object) || !r_responds_main(object, selector)) return;
    r_msg2_main_raw(object, selector, &value, sizeof(value),
                    NULL, 0, NULL, 0, NULL, 0);
}

static uint64_t lso_color(double red, double green, double blue, double alpha)
{
    uint64_t cls = r_class("UIColor");
    return r_is_objc_ptr(cls)
        ? r_msg2_main_raw(cls, "colorWithRed:green:blue:alpha:",
                          &red, sizeof(red), &green, sizeof(green),
                          &blue, sizeof(blue), &alpha, sizeof(alpha))
        : 0;
}

static uint64_t lso_accent_color(void)
{
    switch (s_accent_style) {
        case 1: return lso_color(0.66, 0.36, 1.00, 1.0); // violet
        case 2: return lso_color(1.00, 0.28, 0.34, 1.0); // infern0 red
        case 3: return lso_color(1.00, 0.69, 0.24, 1.0); // gold
        default:return lso_color(0.25, 0.82, 1.00, 1.0); // cyan
    }
}

static bool lso_is_kind_of_named_class(uint64_t object, const char *name)
{
    if (!r_is_objc_ptr(object) || !name) return false;
    uint64_t cls = r_class(name);
    return r_is_objc_ptr(cls) &&
           (r_msg2_main(object, "isKindOfClass:", cls, 0, 0, 0) & 0xff) != 0;
}

static bool lso_controller_matches(uint64_t controller, int depth)
{
    static const char *classes[] = {
        "CSCoverSheetViewController",
        "CSCombinedListViewController",
        "CSMainPageViewController",
        "CSPageViewController",
        "SBDashBoardViewController",
        "SBDashBoardCombinedListViewController",
        "SBLockScreenViewController",
    };
    if (!r_is_objc_ptr(controller) || depth > 5) return false;
    for (unsigned i = 0; i < sizeof(classes) / sizeof(classes[0]); i++)
        if (lso_is_kind_of_named_class(controller, classes[i])) return true;

    uint64_t children = lso_safe_msg(controller, "childViewControllers", 0, 0, 0, 0);
    uint64_t count = r_is_objc_ptr(children)
        ? r_msg2_main(children, "count", 0, 0, 0, 0) : 0;
    if (count > 24) count = 24;
    for (uint64_t i = 0; i < count; i++) {
        uint64_t child = r_msg2_main(children, "objectAtIndex:", i, 0, 0, 0);
        if (lso_controller_matches(child, depth + 1)) return true;
    }
    return false;
}

static bool lso_window_matches(uint64_t window)
{
    static const char *classes[] = {
        "CSCoverSheetWindow",
        "CSLockScreenWindow",
        "SBDashBoardWindow",
        "SBLockScreenWindow",
    };
    if (!r_is_objc_ptr(window)) return false;
    for (unsigned i = 0; i < sizeof(classes) / sizeof(classes[0]); i++)
        if (lso_is_kind_of_named_class(window, classes[i])) return true;
    return lso_controller_matches(
        lso_safe_msg(window, "rootViewController", 0, 0, 0, 0), 0);
}

static bool lso_window_visible(uint64_t window)
{
    if (!r_is_objc_ptr(window)) return false;
    if (r_responds_main(window, "isHidden") &&
        (r_msg2_main(window, "isHidden", 0, 0, 0, 0) & 0xff)) return false;
    return true;
}

static uint64_t lso_find_window(bool *visible)
{
    if (visible) *visible = false;
    uint64_t appClass = r_class("UIApplication");
    uint64_t app = r_is_objc_ptr(appClass)
        ? r_msg2_main(appClass, "sharedApplication", 0, 0, 0, 0) : 0;
    if (!r_is_objc_ptr(app)) return 0;

    uint64_t fallback = 0;
    uint64_t scenes = lso_safe_msg(app, "connectedScenes", 0, 0, 0, 0);
    if (r_is_objc_ptr(scenes) && r_responds_main(scenes, "allObjects"))
        scenes = lso_safe_msg(scenes, "allObjects", 0, 0, 0, 0);
    uint64_t sceneCount = r_is_objc_ptr(scenes)
        ? r_msg2_main(scenes, "count", 0, 0, 0, 0) : 0;
    if (sceneCount > 16) sceneCount = 16;
    for (uint64_t s = 0; s < sceneCount; s++) {
        uint64_t scene = r_msg2_main(scenes, "objectAtIndex:", s, 0, 0, 0);
        uint64_t windows = lso_safe_msg(scene, "windows", 0, 0, 0, 0);
        uint64_t count = r_is_objc_ptr(windows)
            ? r_msg2_main(windows, "count", 0, 0, 0, 0) : 0;
        if (count > 32) count = 32;
        for (uint64_t i = 0; i < count; i++) {
            uint64_t window = r_msg2_main(windows, "objectAtIndex:", i, 0, 0, 0);
            if (!lso_window_matches(window)) continue;
            if (lso_window_visible(window)) {
                if (visible) *visible = true;
                return window;
            }
            fallback = window;
        }
    }

    uint64_t windows = lso_safe_msg(app, "windows", 0, 0, 0, 0);
    uint64_t count = r_is_objc_ptr(windows)
        ? r_msg2_main(windows, "count", 0, 0, 0, 0) : 0;
    if (count > 64) count = 64;
    for (uint64_t i = 0; i < count; i++) {
        uint64_t window = r_msg2_main(windows, "objectAtIndex:", i, 0, 0, 0);
        if (!lso_window_matches(window)) continue;
        if (lso_window_visible(window)) {
            if (visible) *visible = true;
            return window;
        }
        fallback = window;
    }
    return fallback;
}

static uint64_t lso_new_view(LSOFrame frame)
{
    uint64_t cls = r_class("UIView");
    uint64_t alloc = r_is_objc_ptr(cls) ? r_msg2_main(cls, "alloc", 0, 0, 0, 0) : 0;
    return r_is_objc_ptr(alloc)
        ? r_msg2_main_raw(alloc, "initWithFrame:", &frame, sizeof(frame),
                          NULL, 0, NULL, 0, NULL, 0)
        : 0;
}

static uint64_t lso_new_label(LSOFrame frame, double size, double weight)
{
    uint64_t cls = r_class("UILabel");
    uint64_t alloc = r_is_objc_ptr(cls) ? r_msg2_main(cls, "alloc", 0, 0, 0, 0) : 0;
    uint64_t label = r_is_objc_ptr(alloc)
        ? r_msg2_main_raw(alloc, "initWithFrame:", &frame, sizeof(frame),
                          NULL, 0, NULL, 0, NULL, 0)
        : 0;
    if (!r_is_objc_ptr(label)) return 0;
    r_msg2_main(label, "setTextAlignment:", 1, 0, 0, 0);
    r_msg2_main(label, "setUserInteractionEnabled:", 0, 0, 0, 0);
    r_msg2_main(label, "setAdjustsFontSizeToFitWidth:", 1, 0, 0, 0);
    uint64_t fontClass = r_class("UIFont");
    uint64_t font = r_is_objc_ptr(fontClass)
        ? r_msg2_main_raw(fontClass, "systemFontOfSize:weight:",
                          &size, sizeof(size), &weight, sizeof(weight),
                          NULL, 0, NULL, 0)
        : 0;
    if (!r_is_objc_ptr(font) && r_is_objc_ptr(fontClass))
        font = r_msg2_main_raw(fontClass, "systemFontOfSize:",
                               &size, sizeof(size), NULL, 0, NULL, 0, NULL, 0);
    if (r_is_objc_ptr(font)) r_msg2_main(label, "setFont:", font, 0, 0, 0);
    return label;
}

static void lso_set_text(uint64_t label, NSString *text)
{
    if (!r_is_objc_ptr(label)) return;
    uint64_t value = r_nsstr_retained((text ?: @"").UTF8String);
    if (!r_is_objc_ptr(value)) return;
    r_msg2_main(label, "setText:", value, 0, 0, 0);
    r_msg2_main(value, "release", 0, 0, 0, 0);
}

static void lso_update_text(void)
{
    NSDate *now = NSDate.date;
    NSDateFormatter *time = [[NSDateFormatter alloc] init];
    time.locale = NSLocale.currentLocale;
    time.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"j:mm" options:0 locale:time.locale];
    NSDateFormatter *date = [[NSDateFormatter alloc] init];
    date.locale = NSLocale.currentLocale;
    date.dateFormat = @"EEEE, MMMM d";
    lso_set_text(s_time_label, [time stringFromDate:now]);
    lso_set_text(s_date_label, [[date stringFromDate:now] uppercaseString]);
    lso_set_text(s_status_label, @"INFERN0  •  LOCKED & LOADED");
}

static bool lso_already_hidden(uint64_t view)
{
    for (int i = 0; i < s_hidden_count; i++)
        if (s_hidden[i].view == view) return true;
    return false;
}

static void lso_hide_stock_view(uint64_t view)
{
    if (!r_is_objc_ptr(view) || s_hidden_count >= LSO_MAX_HIDDEN || lso_already_hidden(view)) return;
    if (!r_responds_main(view, "isHidden") || !r_responds_main(view, "setHidden:")) return;
    bool hidden = (r_msg2_main(view, "isHidden", 0, 0, 0, 0) & 0xff) != 0;
    r_msg2_main(view, "retain", 0, 0, 0, 0);
    s_hidden[s_hidden_count++] = (LSOHiddenView){ .view = view, .originalHidden = hidden };
    r_msg2_main(view, "setHidden:", 1, 0, 0, 0);
}

static bool lso_matches_any_class(uint64_t object,
                                  const char *const *classes,
                                  unsigned count)
{
    for (unsigned i = 0; i < count; i++)
        if (lso_is_kind_of_named_class(object, classes[i])) return true;
    return false;
}

static void lso_scan_and_hide(uint64_t view, int depth, bool lockContext, int *visited)
{
    if (!r_is_objc_ptr(view) || !visited || depth > 12 || *visited >= LSO_MAX_VISITED) return;
    (*visited)++;
    static const char *lockClasses[] = {
        "CSCoverSheetView", "CSMainPageView", "CSCombinedListView",
        "SBDashBoardView", "SBLockScreenView",
    };
    static const char *clockClasses[] = {
        "SBFLockScreenDateView", "SBFLockScreenDateSubtitleView",
        "CSDateView", "CSCoverSheetDateView", "SBUIProudLockIconView",
    };
    static const char *quickClasses[] = {
        "CSQuickActionsView", "CSQuickActionsButton", "CSCameraQuickActionButton",
        "CSFlashlightQuickActionButton", "SBDashBoardQuickActionsView",
    };
    static const char *dotClasses[] = {
        "CSPageControl", "CSPageIndicator", "SBDashBoardPageControl",
    };
    bool lockClass = lso_matches_any_class(
        view, lockClasses, sizeof(lockClasses) / sizeof(lockClasses[0]));
    lockContext = lockContext || lockClass;
    bool clock = lso_matches_any_class(
        view, clockClasses, sizeof(clockClasses) / sizeof(clockClasses[0]));
    bool quick = lso_matches_any_class(
        view, quickClasses, sizeof(quickClasses) / sizeof(quickClasses[0]));
    bool dots = lso_matches_any_class(
        view, dotClasses, sizeof(dotClasses) / sizeof(dotClasses[0]));
    if (lockContext && (clock || (s_hide_quick_actions && quick) || (s_hide_page_dots && dots)))
        lso_hide_stock_view(view);

    uint64_t subviews = lso_safe_msg(view, "subviews", 0, 0, 0, 0);
    uint64_t count = r_is_objc_ptr(subviews) ? r_msg2_main(subviews, "count", 0, 0, 0, 0) : 0;
    if (count > 96) count = 96;
    for (uint64_t i = 0; i < count; i++)
        lso_scan_and_hide(r_msg2_main(subviews, "objectAtIndex:", i, 0, 0, 0),
                          depth + 1, lockContext, visited);
}

static void lso_release_hidden(bool restore)
{
    for (int i = 0; i < s_hidden_count; i++) {
        if (!r_is_objc_ptr(s_hidden[i].view)) continue;
        if (restore)
            r_msg2_main(s_hidden[i].view, "setHidden:", s_hidden[i].originalHidden ? 1 : 0, 0, 0, 0);
        r_msg2_main(s_hidden[i].view, "release", 0, 0, 0, 0);
    }
    memset(s_hidden, 0, sizeof(s_hidden));
    s_hidden_count = 0;
}

void lockscreenoverlay_configure(int verticalOffset, int widthPercent,
                                 int accentStyle, int glassAlphaPercent,
                                 bool hideQuickActions, bool hidePageDots)
{
    if (verticalOffset < -180) verticalOffset = -180;
    if (verticalOffset > 260) verticalOffset = 260;
    if (widthPercent < 68) widthPercent = 68;
    if (widthPercent > 96) widthPercent = 96;
    if (accentStyle < 0) accentStyle = 0;
    if (accentStyle > 3) accentStyle = 3;
    if (glassAlphaPercent < 25) glassAlphaPercent = 25;
    if (glassAlphaPercent > 95) glassAlphaPercent = 95;
    if (s_vertical_offset != verticalOffset || s_width_percent != widthPercent ||
        s_accent_style != accentStyle || s_glass_alpha != glassAlphaPercent ||
        s_hide_quick_actions != hideQuickActions || s_hide_page_dots != hidePageDots)
        s_config_dirty = true;
    s_vertical_offset = verticalOffset;
    s_width_percent = widthPercent;
    s_accent_style = accentStyle;
    s_glass_alpha = glassAlphaPercent;
    s_hide_quick_actions = hideQuickActions;
    s_hide_page_dots = hidePageDots;
    log_user("[LOCKOVERLAY][CONFIG] engine=standalone-overlay-v1 y=%dpt width=%d%% accent=%d glass=%d%% hideQuick=%d hideDots=%d.\n",
             s_vertical_offset, s_width_percent, s_accent_style, s_glass_alpha,
             s_hide_quick_actions, s_hide_page_dots);
}

bool lockscreenoverlay_stop_in_session(void)
{
    bool removed = r_is_objc_ptr(s_overlay);
    if (removed) {
        r_msg2_main(s_overlay, "removeFromSuperview", 0, 0, 0, 0);
        r_msg2_main(s_overlay, "release", 0, 0, 0, 0);
    }
    int restored = s_hidden_count;
    lso_release_hidden(true);
    if (r_is_objc_ptr(s_host_window)) r_msg2_main(s_host_window, "release", 0, 0, 0, 0);
    s_overlay = s_time_label = s_date_label = s_status_label = s_host_window = 0;
    s_active = false;
    s_config_dirty = true;
    log_user("[LOCKOVERLAY][RESTORE] overlayRemoved=%d stockHiddenStatesRestored=%d result=%s.\n",
             removed, restored, (removed || restored > 0) ? "success" : "already-stock");
    return true;
}

bool lockscreenoverlay_apply_in_session(void)
{
    if (s_active && !s_config_dirty && r_is_objc_ptr(s_overlay)) {
        bool visible = false;
        uint64_t currentHost = lso_find_window(&visible);
        uint64_t parent = lso_safe_msg(s_overlay, "superview", 0, 0, 0, 0);
        if (r_is_objc_ptr(currentHost) && parent == currentHost) {
            lso_update_text();
            int before = s_hidden_count;
            int visited = 0;
            lso_scan_and_hide(currentHost, 0, true, &visited);
            lso_safe_msg(currentHost, "bringSubviewToFront:", s_overlay, 0, 0, 0);
            if (s_hidden_count > before)
                log_user("[LOCKOVERLAY][REFRESH] lazy stock views discovered=%d totalHidden=%d visited=%d presentation=%s.\n",
                         s_hidden_count - before, s_hidden_count, visited,
                         visible ? "visible" : "hidden");
            return true;
        }
        log_user("[LOCKOVERLAY][REBUILD] Cover Sheet host changed or detached; restoring the old capture before rebuilding.\n");
    }
    if (s_active || r_is_objc_ptr(s_overlay)) (void)lockscreenoverlay_stop_in_session();

    log_user("[LOCKOVERLAY][1/4] Locating a class-verified Cover Sheet window...\n");
    bool visible = false;
    uint64_t host = lso_find_window(&visible);
    CGRect localBounds = UIScreen.mainScreen.bounds;
    LSOFrame bounds = { 0, 0, localBounds.size.width, localBounds.size.height };
    if (!r_is_objc_ptr(host) || bounds.width < 200.0 || bounds.height < 300.0) {
        log_user("[LOCKOVERLAY][WAIT] Cover Sheet host is unavailable; stock Lock Screen was left untouched.\n");
        return false;
    }

    log_user("[LOCKOVERLAY][2/4] Building the independent glass clock overlay...\n");
    double width = bounds.width * ((double)s_width_percent / 100.0);
    double height = 218.0;
    double x = (bounds.width - width) * 0.5;
    double y = 92.0 + (double)s_vertical_offset;
    if (y < 24.0) y = 24.0;
    if (y + height > bounds.height - 80.0) y = bounds.height - height - 80.0;
    LSOFrame panelFrame = { x, y, width, height };
    uint64_t panel = lso_new_view(panelFrame);
    if (!r_is_objc_ptr(panel)) {
        log_user("[LOCKOVERLAY][FAIL] UIView allocation failed; stock Lock Screen was left untouched.\n");
        return false;
    }
    r_msg2_main(panel, "setTag:", LSO_OVERLAY_TAG, 0, 0, 0);
    r_msg2_main(panel, "setUserInteractionEnabled:", 0, 0, 0, 0);
    uint64_t background = lso_color(0.035, 0.045, 0.065, (double)s_glass_alpha / 100.0);
    if (r_is_objc_ptr(background)) r_msg2_main(panel, "setBackgroundColor:", background, 0, 0, 0);

    uint64_t layer = lso_safe_msg(panel, "layer", 0, 0, 0, 0);
    uint64_t accent = lso_accent_color();
    uint64_t accentCG = r_is_objc_ptr(accent) ? r_msg2_main(accent, "CGColor", 0, 0, 0, 0) : 0;
    if (r_is_objc_ptr(layer)) {
        lso_set_double(layer, "setCornerRadius:", 30.0);
        lso_set_double(layer, "setBorderWidth:", 1.25);
        lso_set_double(layer, "setShadowRadius:", 18.0);
        float opacity = 0.72f;
        r_msg2_main_raw(layer, "setShadowOpacity:", &opacity, sizeof(opacity), NULL, 0, NULL, 0, NULL, 0);
        if (accentCG) {
            r_msg2_main(layer, "setBorderColor:", accentCG, 0, 0, 0);
            r_msg2_main(layer, "setShadowColor:", accentCG, 0, 0, 0);
        }
    }

    // Optional native blur. The dark tint remains as a fallback on builds
    // where UIVisualEffectView cannot be constructed in SpringBoard.
    uint64_t blurClass = r_class("UIBlurEffect");
    uint64_t effectViewClass = r_class("UIVisualEffectView");
    uint64_t effect = r_is_objc_ptr(blurClass)
        ? r_msg2_main(blurClass, "effectWithStyle:", 2, 0, 0, 0)
        : 0;
    uint64_t effectAlloc = r_is_objc_ptr(effectViewClass) && r_is_objc_ptr(effect)
        ? r_msg2_main(effectViewClass, "alloc", 0, 0, 0, 0)
        : 0;
    uint64_t blurView = r_is_objc_ptr(effectAlloc) && r_is_objc_ptr(effect)
        ? r_msg2_main(effectAlloc, "initWithEffect:", effect, 0, 0, 0)
        : 0;
    if (r_is_objc_ptr(blurView)) {
        LSOFrame blurFrame = { 0, 0, width, height };
        lso_set_frame(blurView, blurFrame);
        r_msg2_main(blurView, "setUserInteractionEnabled:", 0, 0, 0, 0);
        r_msg2_main(blurView, "setClipsToBounds:", 1, 0, 0, 0);
        uint64_t blurLayer = lso_safe_msg(blurView, "layer", 0, 0, 0, 0);
        lso_set_double(blurLayer, "setCornerRadius:", 30.0);
        r_msg2_main(panel, "addSubview:", blurView, 0, 0, 0);
        r_msg2_main(blurView, "release", 0, 0, 0, 0);
    }

    uint64_t accentRail = lso_new_view((LSOFrame){ 0, 34, 4, height - 68 });
    if (r_is_objc_ptr(accentRail)) {
        if (r_is_objc_ptr(accent)) r_msg2_main(accentRail, "setBackgroundColor:", accent, 0, 0, 0);
        r_msg2_main(accentRail, "setUserInteractionEnabled:", 0, 0, 0, 0);
        lso_set_double(lso_safe_msg(accentRail, "layer", 0, 0, 0, 0), "setCornerRadius:", 2.0);
        r_msg2_main(panel, "addSubview:", accentRail, 0, 0, 0);
        r_msg2_main(accentRail, "release", 0, 0, 0, 0);
    }

    LSOFrame dateFrame = { 18, 20, width - 36, 26 };
    LSOFrame timeFrame = { 14, 43, width - 28, 112 };
    LSOFrame statusFrame = { 18, 168, width - 36, 24 };
    uint64_t dateLabel = lso_new_label(dateFrame, 15.0, 0.6);
    uint64_t timeLabel = lso_new_label(timeFrame, 82.0, 0.3);
    uint64_t statusLabel = lso_new_label(statusFrame, 11.0, 0.6);
    if (!r_is_objc_ptr(dateLabel) || !r_is_objc_ptr(timeLabel) || !r_is_objc_ptr(statusLabel)) {
        if (r_is_objc_ptr(dateLabel)) r_msg2_main(dateLabel, "release", 0, 0, 0, 0);
        if (r_is_objc_ptr(timeLabel)) r_msg2_main(timeLabel, "release", 0, 0, 0, 0);
        if (r_is_objc_ptr(statusLabel)) r_msg2_main(statusLabel, "release", 0, 0, 0, 0);
        r_msg2_main(panel, "release", 0, 0, 0, 0);
        log_user("[LOCKOVERLAY][FAIL] Label allocation failed; stock Lock Screen was left untouched.\n");
        return false;
    }
    uint64_t white = lso_color(1.0, 1.0, 1.0, 1.0);
    if (r_is_objc_ptr(white)) r_msg2_main(timeLabel, "setTextColor:", white, 0, 0, 0);
    if (r_is_objc_ptr(accent)) {
        r_msg2_main(dateLabel, "setTextColor:", accent, 0, 0, 0);
        r_msg2_main(statusLabel, "setTextColor:", accent, 0, 0, 0);
    }
    r_msg2_main(panel, "addSubview:", dateLabel, 0, 0, 0);
    r_msg2_main(panel, "addSubview:", timeLabel, 0, 0, 0);
    r_msg2_main(panel, "addSubview:", statusLabel, 0, 0, 0);

    s_overlay = panel;
    s_date_label = dateLabel;
    s_time_label = timeLabel;
    s_status_label = statusLabel;
    // The panel now owns the labels. Keep borrowed pointers, matching Watch
    // Layout's retained-root ownership model.
    r_msg2_main(dateLabel, "release", 0, 0, 0, 0);
    r_msg2_main(timeLabel, "release", 0, 0, 0, 0);
    r_msg2_main(statusLabel, "release", 0, 0, 0, 0);
    lso_update_text();
    r_msg2_main(host, "addSubview:", panel, 0, 0, 0);
    if (lso_safe_msg(panel, "superview", 0, 0, 0, 0) != host) {
        r_msg2_main(panel, "release", 0, 0, 0, 0);
        s_overlay = s_date_label = s_time_label = s_status_label = 0;
        log_user("[LOCKOVERLAY][FAIL] Overlay attachment did not verify; stock Lock Screen was left untouched.\n");
        return false;
    }

    log_user("[LOCKOVERLAY][3/4] Overlay attachment verified; hiding matched stock clock controls...\n");
    int visited = 0;
    lso_scan_and_hide(host, 0, true, &visited);
    r_msg2_main(host, "retain", 0, 0, 0, 0);
    s_host_window = host;
    s_active = true;
    s_config_dirty = false;
    log_user("[LOCKOVERLAY][4/4] active=1 presentation=%s overlay=0x%llx host=0x%llx visited=%d hiddenStockViews=%d touches=passthrough nativeBlur=%d dimensions=%.0fx%.0f vmReads=0.\n",
             visible ? "visible" : "prearmed-hidden", s_overlay, host, visited,
             s_hidden_count, r_is_objc_ptr(blurView), width, height);
    return true;
}

void lockscreenoverlay_forget_remote_state(void)
{
    memset(s_hidden, 0, sizeof(s_hidden));
    s_hidden_count = 0;
    s_overlay = s_time_label = s_date_label = s_status_label = s_host_window = 0;
    s_active = false;
    s_config_dirty = true;
    log_user("[LOCKOVERLAY][FORGET] cleared stale remote overlay state.\n");
}
