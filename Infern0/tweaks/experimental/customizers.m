#import "customizers.h"
#import "../remote_objc.h"
#import "../sb_walk.h"
#import "../darksword_tweaks.h"
#import "../../TaskRop/RemoteCall.h"
#import "../../LogTextView.h"

#import <Foundation/Foundation.h>
#import <math.h>
#import <string.h>

typedef struct { double x, y, width, height; } CUSRect;
typedef struct { double a, b, c, d, tx, ty; } CUSAffine;

static int gLockClockScale = 100;
static int gLockXOffset = 0;
static int gLockYOffset = 0;
static bool gLockHideQuickActions = false;
static bool gLockHideDots = false;
static int gLockContentAlpha = 100;
static int gLockMediaScale = 92;
static bool gLockHideMediaArtwork = false;
static bool gMetalLockLightEnabled = false;
static int gMetalLockLightIntensity = 72;
static int gMetalLockLightThickness = 5;
static int gMetalLockLightStyle = 0;
static uint64_t gMetalLockLightOverlay = 0;
static bool gLockConfigDirty = false;

static void cus_class_name(uint64_t obj, char *out, size_t outLen)
{
    (void)sb_read_class_name(obj, out, outLen);
}

static void cus_set_alpha(uint64_t view, double alpha)
{
    if (r_is_objc_ptr(view) && r_responds_main(view, "setAlpha:"))
        r_msg2_main_raw(view, "setAlpha:", &alpha, sizeof(alpha), NULL, 0, NULL, 0, NULL, 0);
}

static bool cus_get_rect(uint64_t view, const char *sel, CUSRect *out)
{
    if (!r_is_objc_ptr(view) || !out || !r_responds_main(view, sel)) return false;
    memset(out, 0, sizeof(*out));
    return r_msg2_main_struct_ret(view, sel, out, sizeof(*out), NULL, 0, NULL, 0, NULL, 0, NULL, 0);
}

static void cus_set_rect(uint64_t view, CUSRect frame)
{
    if (r_is_objc_ptr(view) && r_responds_main(view, "setFrame:"))
        r_msg2_main_raw(view, "setFrame:", &frame, sizeof(frame), NULL, 0, NULL, 0, NULL, 0);
}

static void cus_set_transform(uint64_t view, CUSAffine transform)
{
    if (r_is_objc_ptr(view) && r_responds_main(view, "setTransform:"))
        r_msg2_main_raw(view, "setTransform:", &transform, sizeof(transform), NULL, 0, NULL, 0, NULL, 0);
}

static bool cus_contains(const char *name, const char *needle)
{
    return name && needle && strstr(name, needle) != NULL;
}
static bool lockcustomizer_window_visible(uint64_t window)
{
    if (!r_is_objc_ptr(window)) return false;
    if (r_responds_main(window, "isHidden") &&
        (r_msg2_main(window, "isHidden", 0, 0, 0, 0) & 0xff)) return false;
    double alpha = 1.0;
    if (r_responds_main(window, "alpha") &&
        !r_msg2_main_struct_ret(window, "alpha", &alpha, sizeof(alpha),
                                NULL, 0, NULL, 0, NULL, 0, NULL, 0))
        return false;
    return alpha > 0.01;
}

static bool lockcustomizer_matches_window(uint64_t window)
{
    if (!r_is_objc_ptr(window)) return false;
    char cls[160] = {0};
    cus_class_name(window, cls, sizeof(cls));
    if (cus_contains(cls, "CoverSheet") || cus_contains(cls, "LockScreen") ||
        cus_contains(cls, "DashBoard")) return true;
    uint64_t controller = r_responds_main(window, "rootViewController")
        ? r_msg2_main(window, "rootViewController", 0, 0, 0, 0) : 0;
    cus_class_name(controller, cls, sizeof(cls));
    return cus_contains(cls, "CoverSheet") || cus_contains(cls, "LockScreen") ||
           cus_contains(cls, "DashBoard") || cus_contains(cls, "CSCombined");
}

static uint64_t lockcustomizer_window(bool *visible)
{
    if (visible) *visible = false;
    uint64_t windows[64] = {0};
    int count = sb_collect_windows(windows, 64);
    for (int i = count - 1; i >= 0; i--) {
        if (lockcustomizer_matches_window(windows[i]) &&
            lockcustomizer_window_visible(windows[i])) {
            if (visible) *visible = true;
            return windows[i];
        }
    }
    // SpringBoard normally builds and retains the Cover Sheet window before
    // it becomes visible. Pre-arming only this class-verified hierarchy makes
    // lock-screen settings survive the Settings app being suspended on lock.
    for (int i = count - 1; i >= 0; i--)
        if (lockcustomizer_matches_window(windows[i])) return windows[i];
    return 0;
}

static void lockcustomizer_scan(uint64_t view, int depth, bool lockContext,
                                int *visited, int *changed)
{
    if (!r_is_objc_ptr(view) || depth > 12 || !visited || *visited >= 384 ||
        (changed && *changed >= 64)) return;
    (*visited)++;
    char cls[160] = {0};
    cus_class_name(view, cls, sizeof(cls));
    bool isLock = cus_contains(cls, "LockScreen") || cus_contains(cls, "CoverSheet") ||
                  cus_contains(cls, "CSPageControl") || cus_contains(cls, "CSCoverSheet") ||
                  cus_contains(cls, "CSMainPage") || cus_contains(cls, "SBDashBoard") ||
                  cus_contains(cls, "CSCombined");
    lockContext = lockContext || isLock;
    bool isClock = cus_contains(cls, "LockScreenDateView") || cus_contains(cls, "CSDateView") ||
                   cus_contains(cls, "CoverSheetDateView") || cus_contains(cls, "ClockView");
    bool isQuick = cus_contains(cls, "QuickAction") || cus_contains(cls, "CameraGrabber") || cus_contains(cls, "Flashlight");
    bool isDots = cus_contains(cls, "PageControl") || cus_contains(cls, "PageIndicator");
    bool isMedia = cus_contains(cls, "MediaControlsPanelView") || cus_contains(cls, "NowPlayingContainer");
    bool isArtwork = cus_contains(cls, "Artwork") || cus_contains(cls, "CoverArt");
    if (isClock && lockContext) {
        double scale = (double)gLockClockScale / 100.0;
        CUSAffine t = {scale, 0, 0, scale, gLockXOffset, gLockYOffset};
        bool didChange = sb_cc_override_bytes("lockcustomizer", view, "transform", "setTransform:", &t, sizeof(t));
        double alpha = (double)gLockContentAlpha / 100.0;
        didChange = sb_cc_override_bytes("lockcustomizer", view, "alpha", "setAlpha:", &alpha, sizeof(alpha)) || didChange;
        if (didChange && changed) (*changed)++;
    } else if (isQuick && lockContext && gLockHideQuickActions) {
        double alpha = 0.0;
        if (sb_cc_override_bytes("lockcustomizer", view, "alpha", "setAlpha:", &alpha, sizeof(alpha)) && changed) (*changed)++;
    } else if (isDots && lockContext && gLockHideDots) {
        double alpha = 0.0;
        if (sb_cc_override_bytes("lockcustomizer", view, "alpha", "setAlpha:", &alpha, sizeof(alpha)) && changed) (*changed)++;
    } else if (isArtwork && lockContext && gLockHideMediaArtwork) {
        double alpha = 0.0;
        if (sb_cc_override_bytes("lockcustomizer", view, "alpha", "setAlpha:", &alpha, sizeof(alpha)) && changed) (*changed)++;
    } else if (isMedia && lockContext) {
        double scale = (double)gLockMediaScale / 100.0;
        CUSAffine t = { scale, 0, 0, scale, 0, 0 };
        if (sb_cc_override_bytes("lockcustomizer", view, "transform", "setTransform:", &t, sizeof(t)) && changed) (*changed)++;
    }
    uint64_t subs = r_msg2_main(view, "subviews", 0, 0, 0, 0);
    uint64_t count = r_is_objc_ptr(subs) ? r_msg2_main(subs, "count", 0, 0, 0, 0) : 0;
    if (count > 96) count = 96;
    for (uint64_t i = 0; i < count; i++)
        lockcustomizer_scan(r_msg2_main(subs, "objectAtIndex:", i, 0, 0, 0),
                            depth + 1, lockContext, visited, changed);
}

void lockcustomizer_configure(int clockScalePercent, int horizontalOffset, int verticalOffset,
                              bool hideQuickActions, bool hidePageDots, int contentAlphaPercent,
                              int mediaScalePercent, bool hideMediaArtwork,
                              bool metalLightEnabled, int metalLightIntensityPercent,
                              int metalLightThickness, int metalLightStyle)
{
    if (clockScalePercent < 50) clockScalePercent = 50;
    if (clockScalePercent > 180) clockScalePercent = 180;
    if (horizontalOffset < -160) horizontalOffset = -160;
    if (horizontalOffset > 160) horizontalOffset = 160;
    if (verticalOffset < -300) verticalOffset = -300;
    if (verticalOffset > 300) verticalOffset = 300;
    if (contentAlphaPercent < 20) contentAlphaPercent = 20;
    if (contentAlphaPercent > 100) contentAlphaPercent = 100;
    if (mediaScalePercent < 65) mediaScalePercent = 65;
    if (mediaScalePercent > 115) mediaScalePercent = 115;
    if (metalLightIntensityPercent < 10) metalLightIntensityPercent = 10;
    if (metalLightIntensityPercent > 100) metalLightIntensityPercent = 100;
    if (metalLightThickness < 1) metalLightThickness = 1;
    if (metalLightThickness > 18) metalLightThickness = 18;
    if (metalLightStyle < 0) metalLightStyle = 0;
    if (metalLightStyle > 2) metalLightStyle = 2;
    if (gLockClockScale != clockScalePercent || gLockXOffset != horizontalOffset ||
        gLockYOffset != verticalOffset || gLockHideQuickActions != hideQuickActions ||
        gLockHideDots != hidePageDots || gLockContentAlpha != contentAlphaPercent ||
        gLockMediaScale != mediaScalePercent || gLockHideMediaArtwork != hideMediaArtwork ||
        gMetalLockLightEnabled != metalLightEnabled ||
        gMetalLockLightIntensity != metalLightIntensityPercent ||
        gMetalLockLightThickness != metalLightThickness ||
        gMetalLockLightStyle != metalLightStyle) {
        gLockConfigDirty = true;
    }
    gLockClockScale = clockScalePercent;
    gLockXOffset = horizontalOffset;
    gLockYOffset = verticalOffset;
    gLockHideQuickActions = hideQuickActions;
    gLockHideDots = hidePageDots;
    gLockContentAlpha = contentAlphaPercent;
    gLockMediaScale = mediaScalePercent;
    gLockHideMediaArtwork = hideMediaArtwork;
    gMetalLockLightEnabled = metalLightEnabled;
    gMetalLockLightIntensity = metalLightIntensityPercent;
    gMetalLockLightThickness = metalLightThickness;
    gMetalLockLightStyle = metalLightStyle;
    log_user("[LOCKCUSTOM][CONFIG] clockScale=%d%% offset=%d/%dpt hideQuickActions=%d hidePageDots=%d clockAlpha=%d%% mediaScale=%d%% hideArtwork=%d metalLight=%d metalIntensity=%d%% metalThickness=%dpt metalStyle=%d.\n",
             gLockClockScale, gLockXOffset, gLockYOffset, gLockHideQuickActions,
             gLockHideDots, gLockContentAlpha, gLockMediaScale,
             gLockHideMediaArtwork, gMetalLockLightEnabled,
             gMetalLockLightIntensity, gMetalLockLightThickness, gMetalLockLightStyle);
}

static uint64_t metal_lock_light_color(void)
{
    double red = 0.30, green = 0.72, blue = 1.0, alpha = 1.0;
    if (gMetalLockLightStyle == 1) { red = 0.72; green = 0.38; blue = 1.0; }
    if (gMetalLockLightStyle == 2) { red = 1.0; green = 0.67; blue = 0.24; }
    uint64_t cls = r_class("UIColor");
    return r_is_objc_ptr(cls)
        ? r_msg2_main_raw(cls, "colorWithRed:green:blue:alpha:",
                          &red, sizeof(red), &green, sizeof(green),
                          &blue, sizeof(blue), &alpha, sizeof(alpha)) : 0;
}

static bool metal_lock_light_apply(uint64_t lockWindow)
{
    if (!gMetalLockLightEnabled) {
        bool removed = r_is_objc_ptr(gMetalLockLightOverlay);
        if (removed)
            r_msg2_main(gMetalLockLightOverlay, "removeFromSuperview", 0, 0, 0, 0);
        if (removed)
            r_msg2_main(gMetalLockLightOverlay, "release", 0, 0, 0, 0);
        gMetalLockLightOverlay = 0;
        log_user("[METALLOCK][DISABLED] overlayRemoved=%d result=stock-edge-light.\n", removed);
        return false;
    }
    if (!r_is_objc_ptr(lockWindow)) {
        printf("[METALLOCK] lock window not visible yet\n");
        log_user("[METALLOCK][WAIT] no visible CoverSheet window; apply will retry while the lock screen is presented.\n");
        return false;
    }
    CUSRect bounds;
    if (!cus_get_rect(lockWindow, "bounds", &bounds)) return false;
    if (!r_is_objc_ptr(gMetalLockLightOverlay)) {
        uint64_t alloc = r_msg2_main(r_class("UIView"), "alloc", 0, 0, 0, 0);
        gMetalLockLightOverlay = r_is_objc_ptr(alloc)
            ? r_msg2_main_raw(alloc, "initWithFrame:", &bounds, sizeof(bounds), NULL, 0, NULL, 0, NULL, 0) : 0;
        if (!r_is_objc_ptr(gMetalLockLightOverlay)) return false;
        r_msg2_main(gMetalLockLightOverlay, "setUserInteractionEnabled:", 0, 0, 0, 0);
        r_msg2_main(lockWindow, "addSubview:", gMetalLockLightOverlay, 0, 0, 0);
    } else {
        uint64_t parent = r_msg2_main(gMetalLockLightOverlay, "superview", 0, 0, 0, 0);
        if (parent != lockWindow)
            r_msg2_main(lockWindow, "addSubview:", gMetalLockLightOverlay, 0, 0, 0);
    }
    cus_set_rect(gMetalLockLightOverlay, bounds);
    cus_set_alpha(gMetalLockLightOverlay, (double)gMetalLockLightIntensity / 100.0);
    uint64_t layer = r_msg2_main(gMetalLockLightOverlay, "layer", 0, 0, 0, 0);
    uint64_t color = metal_lock_light_color();
    uint64_t cgColor = r_is_objc_ptr(color) ? r_msg2_main(color, "CGColor", 0, 0, 0, 0) : 0;
    double width = (double)gMetalLockLightThickness, radius = 26.0, shadowRadius = width * 2.2;
    float shadowOpacity = 0.92f;
    r_msg2_main_raw(layer, "setBorderWidth:", &width, sizeof(width), NULL, 0, NULL, 0, NULL, 0);
    if (cgColor) {
        r_msg2_main(layer, "setBorderColor:", cgColor, 0, 0, 0);
        r_msg2_main(layer, "setShadowColor:", cgColor, 0, 0, 0);
    }
    r_msg2_main_raw(layer, "setCornerRadius:", &radius, sizeof(radius), NULL, 0, NULL, 0, NULL, 0);
    r_msg2_main_raw(layer, "setShadowOpacity:", &shadowOpacity, sizeof(shadowOpacity), NULL, 0, NULL, 0, NULL, 0);
    r_msg2_main_raw(layer, "setShadowRadius:", &shadowRadius, sizeof(shadowRadius), NULL, 0, NULL, 0, NULL, 0);
    printf("[METALLOCK] style=%d intensity=%d%% thickness=%d overlay=0x%llx window=0x%llx touches=passthrough\n",
           gMetalLockLightStyle, gMetalLockLightIntensity, gMetalLockLightThickness,
           gMetalLockLightOverlay, lockWindow);
    log_user("[METALLOCK] applied style=%d intensity=%d%% thickness=%dpt; overlay is noninteractive and cleanup is registered.\n",
             gMetalLockLightStyle, gMetalLockLightIntensity, gMetalLockLightThickness);
    return true;
}

static bool lockcustomizer_run(bool restore)
{
    if (restore) {
        int restored = sb_cc_restore_owner("lockcustomizer");
        bool overlayRemoved = r_is_objc_ptr(gMetalLockLightOverlay);
        if (overlayRemoved) {
            r_msg2_main(gMetalLockLightOverlay, "removeFromSuperview", 0, 0, 0, 0);
            r_msg2_main(gMetalLockLightOverlay, "release", 0, 0, 0, 0);
        }
        gMetalLockLightOverlay = 0;
        log_user("[LOCKCUSTOM][RESTORE] exactProperties=%d metalOverlayRemoved=%d result=%s.\n",
                 restored, overlayRemoved, (restored > 0 || overlayRemoved) ? "success" : "nothing-owned");
        return restored > 0 || overlayRemoved;
    }
    if (gLockConfigDirty) {
        int restored = sb_cc_restore_owner("lockcustomizer");
        log_user("[LOCKCUSTOM][RECONFIGURE] restoredPriorProperties=%d before applying the new selection.\n",
                 restored);
        gLockConfigDirty = false;
    }
    bool windowVisible = false;
    uint64_t lockWindow = lockcustomizer_window(&windowVisible);
    if (!r_is_objc_ptr(lockWindow)) {
        log_user("[LOCKCUSTOM][WAIT] no class-verified Cover Sheet window exists yet; no hierarchy was touched.\n");
        return false;
    }
    int visited = 0, changed = 0;
    lockcustomizer_scan(lockWindow, 0, true, &visited, &changed);
    bool metalOK = metal_lock_light_apply(lockWindow);
    printf("[LOCKCUSTOM] restore=%d scale=%d%% x=%d y=%d quick=%d dots=%d alpha=%d%% mediaScale=%d%% hideArtwork=%d metal=%d metalOK=%d visited=%d changed=%d\n",
           restore, gLockClockScale, gLockXOffset, gLockYOffset,
           gLockHideQuickActions, gLockHideDots, gLockContentAlpha,
           gLockMediaScale, gLockHideMediaArtwork, gMetalLockLightEnabled, metalOK, visited, changed);
    log_user("[LOCKCUSTOM][%s] window=0x%llx presentation=%s visited=%d matchedViews=%d clockScale=%d%% offset=%d/%dpt hideQuick=%d hideDots=%d alpha=%d%% mediaScale=%d%% hideArtwork=%d metalEnabled=%d metalResult=%d result=%s.\n",
             restore ? "RESTORE" : "APPLY", lockWindow,
             windowVisible ? "visible" : "prearmed-hidden", visited, changed,
             gLockClockScale, gLockXOffset, gLockYOffset,
             gLockHideQuickActions, gLockHideDots, gLockContentAlpha,
             gLockMediaScale, gLockHideMediaArtwork, gMetalLockLightEnabled,
             metalOK, (changed > 0 || metalOK) ? "success" : "no supported views");
    return changed > 0 || metalOK;
}

bool lockcustomizer_apply_in_session(void) { return lockcustomizer_run(false); }
bool lockcustomizer_stop_in_session(void) { return lockcustomizer_run(true); }
void lockcustomizer_forget_remote_state(void)
{
    bool hadOverlay = r_is_objc_ptr(gMetalLockLightOverlay);
    gMetalLockLightOverlay = 0;
    gLockConfigDirty = false;
    sb_cc_forget_owner("lockcustomizer");
    log_user("[LOCKCUSTOM][FORGET] cleared remote state; hadMetalOverlay=%d.\n", hadOverlay);
}
