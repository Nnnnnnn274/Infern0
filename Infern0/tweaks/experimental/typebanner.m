//
//  typebanner.m
//

#import "typebanner.h"
#import "../remote_objc.h"
#import "../../TaskRop/RemoteCall.h"
#import "../../LogTextView.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <math.h>
#import <sys/time.h>
#import <unistd.h>

#pragma mark - Banner globals (SpringBoard side)

static const uint64_t kTypeBannerOverlayTag = 99431;
static const double kTypeBannerHeight = 36.0;
static const double kTypeBannerCornerRadius = 18.0;
static const double kTypeBannerWinLevel = 999999.0;
static const double kTypeBannerSideMargin = 12.0;
static const double kTypeBannerHorizontalPadding = 14.0;
static const double kTypeBannerIconSize = 20.0;
static const double kTypeBannerIconLabelGap = 8.0;
static const uint64_t kTypeBannerRBSLegacyPreventSuspendFlag = 1;
static const uint64_t kTypeBannerRBSLegacyBackgroundUIReason = 7;
static const uint64_t kTypeBannerMobileBootstrapCooldownUS = 3000000;
static const uint64_t kTypeBannerImagentProbeCooldownUS = 1000000;
static const bool kTypeBannerDaemonOnlyDetection = true;
static const bool kTypeBannerResolveMobileSMSNames = false;
// Crash logs from iOS 26.0.1 show SpringBoard-hosted RBSAssertion acquisition
// can wedge runningboardd's RBAssertionManager while Cyanide is blocked in the
// synchronous RemoteCall. Keep the API around, but don't exercise that path.
static const bool kTypeBannerSpringBoardRBSKeepAliveEnabled = false;

static uint64_t gTypeBannerWindow = 0;
static uint64_t gTypeBannerLabel = 0;
static uint64_t gTypeBannerFontPtr = 0;
static NSString *gTypeBannerLastName = nil;
static uint64_t gTypeBannerMobileKeepAliveAssertion = 0;
static uint32_t gTypeBannerMobileKeepAlivePid = 0;
static bool gTypeBannerMobileKeepAliveFailureLogged = false;
static bool gTypeBannerPollRemoteHealthy = true;
static RemoteCallInitFailure gTypeBannerLastMobileInitFailure = RemoteCallInitFailureNone;
static uint32_t gTypeBannerLastMobileInitFailurePid = 0;
static bool gTypeBannerMobileUnreachableLastTick = false;
static uint32_t gTypeBannerMobileBootstrapCooldownPid = 0;
static uint64_t gTypeBannerMobileBootstrapCooldownUntilUS = 0;
static bool gTypeBannerMobileBootstrapCooldownLogged = false;
static bool gTypeBannerImagentPollRemoteHealthy = true;
static bool gTypeBannerImagentReachableLastTick = false;
static uint64_t gTypeBannerImagentProbeCooldownUntilUS = 0;
static bool gTypeBannerImagentProbeCooldownLogged = false;
static RemoteCallInitFailure gTypeBannerLastImagentInitFailure = RemoteCallInitFailureNone;
static uint32_t gTypeBannerLastImagentInitFailurePid = 0;
static NSString * const kTypeBannerHostProcessName = @"MobileSMS";

static uint64_t tb_now_us(void)
{
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return ((uint64_t)tv.tv_sec * 1000000ULL) + (uint64_t)tv.tv_usec;
}

#pragma mark - Banner helpers (SpringBoard side)

typedef struct { double x, y, width, height; } TBRect64;

static bool tb_send_rect_main(uint64_t obj, const char *selName,
                              double x, double y, double w, double h)
{
    if (!r_is_objc_ptr(obj)) return false;
    TBRect64 rect = { x, y, w, h };
    r_msg2_main_raw(obj, selName,
                    &rect, sizeof(rect),
                    NULL, 0,
                    NULL, 0,
                    NULL, 0);
    usleep(20000);
    return true;
}

static bool tb_send_double_main(uint64_t obj, const char *selName, double value)
{
    if (!r_is_objc_ptr(obj)) return false;
    r_msg2_main_raw(obj, selName,
                    &value, sizeof(value),
                    NULL, 0,
                    NULL, 0,
                    NULL, 0);
    usleep(20000);
    return true;
}

static uint64_t tb_remote_nsstring(NSString *s)
{
    const char *utf8 = s.UTF8String;
    if (!utf8) utf8 = "";
    uint64_t buf = r_alloc_str(utf8);
    if (!buf) return 0;

    uint64_t NSString_cls = r_class("NSString");
    if (!r_is_objc_ptr(NSString_cls)) { r_free(buf); return 0; }
    uint64_t alloc = r_msg2(NSString_cls, "alloc", 0, 0, 0, 0);
    uint64_t ns = r_is_objc_ptr(alloc) ? r_msg2(alloc, "initWithUTF8String:", buf, 0, 0, 0) : 0;
    r_free(buf);
    return ns;
}

static uint64_t tb_springboard_application(void)
{
    uint64_t UIApplication = r_class("UIApplication");
    if (!r_is_objc_ptr(UIApplication)) return 0;
    return r_msg2_main(UIApplication, "sharedApplication", 0, 0, 0, 0);
}

static double tb_banner_top_y(void)
{
    // Find safe-area top from any UIWindow in SpringBoard so we sit just
    // below the Dynamic Island / notch.
    uint64_t app = tb_springboard_application();
    if (!r_is_objc_ptr(app)) return 50.0;

    uint64_t keyWin = r_msg2_main(app, "keyWindow", 0, 0, 0, 0);
    if (!r_is_objc_ptr(keyWin)) {
        uint64_t windows = r_msg2_main(app, "windows", 0, 0, 0, 0);
        uint64_t count = r_is_objc_ptr(windows) ? r_msg2_main(windows, "count", 0, 0, 0, 0) : 0;
        if (count > 0 && count < 64) keyWin = r_msg2_main(windows, "objectAtIndex:", 0, 0, 0, 0);
    }
    if (!r_is_objc_ptr(keyWin)) return 50.0;

    struct { double top, left, bottom, right; } insets = {0};
    bool ok = r_msg2_main_struct_ret(keyWin, "safeAreaInsets",
                                     &insets, sizeof(insets),
                                     NULL, 0, NULL, 0, NULL, 0, NULL, 0);
    if (!ok) return 50.0;

    double topY = insets.top;
    if (topY > 47.0) topY += 4.0;  // Dynamic Island offset
    else topY = topY + 4.0;
    if (topY < 8.0) topY = 8.0;
    return topY;
}

static uint64_t tb_banner_font(void)
{
    if (r_is_objc_ptr(gTypeBannerFontPtr)) return gTypeBannerFontPtr;

    uint64_t UIFont = r_class("UIFont");
    if (!r_is_objc_ptr(UIFont)) return 0;

    double size = 14.0;
    double weight = 0.30;  // UIFontWeightMedium
    uint64_t font = r_msg2_main_raw(UIFont, "systemFontOfSize:weight:",
                                    &size, sizeof(size),
                                    &weight, sizeof(weight),
                                    NULL, 0,
                                    NULL, 0);
    if (!r_is_objc_ptr(font)) {
        font = r_msg2_main_raw(UIFont, "systemFontOfSize:",
                               &size, sizeof(size),
                               NULL, 0, NULL, 0, NULL, 0);
    }
    if (r_is_objc_ptr(font)) gTypeBannerFontPtr = font;
    return font;
}

static double tb_estimate_label_width(NSString *text)
{
    // Rough estimate: 8pt per char + 10pt slack. Good enough for the banner pill;
    // we don't need precise sizing.
    if (text.length == 0) return 200.0;
    double w = (double)text.length * 8.0 + 10.0;
    if (w < 120.0) w = 120.0;
    if (w > 320.0) w = 320.0;
    return w;
}

static NSString *tb_banner_text_for_display_name(NSString *displayName)
{
    if (displayName.length == 0) {
        return @"Someone is typing…";
    }
    if ([displayName isEqualToString:@"__SEVERAL_PEOPLE__"]) {
        return @"Several people are typing…";
    }
    return [NSString stringWithFormat:@" %@ is typing… ", displayName];
}

static uint64_t tb_find_existing_window(void)
{
    if (r_is_objc_ptr(gTypeBannerWindow)) return gTypeBannerWindow;

    uint64_t app = tb_springboard_application();
    if (!r_is_objc_ptr(app)) return 0;

    // Recover any window we created on a previous run via assoc key.
    uint64_t assocKey = r_sel("cyanideTypeBannerOverlayWindow");
    if (!assocKey) return 0;
    uint64_t cachedWin = r_dlsym_call(R_TIMEOUT, "objc_getAssociatedObject",
                                      app, assocKey, 0, 0, 0, 0, 0, 0);
    if (r_is_objc_ptr(cachedWin)) {
        uint64_t cachedLabel = r_msg2_main(cachedWin, "viewWithTag:",
                                           kTypeBannerOverlayTag, 0, 0, 0);
        if (r_is_objc_ptr(cachedLabel)) {
            gTypeBannerWindow = cachedWin;
            gTypeBannerLabel = cachedLabel;
            printf("[TYPEBANNER] recovered cached window=0x%llx label=0x%llx\n",
                   cachedWin, cachedLabel);
            return cachedWin;
        }
    }
    return 0;
}

static uint64_t tb_find_or_create_window(void)
{
    uint64_t existing = tb_find_existing_window();
    if (r_is_objc_ptr(existing)) return existing;

    uint64_t app = tb_springboard_application();
    if (!r_is_objc_ptr(app)) { printf("[TYPEBANNER] sharedApplication nil\n"); return 0; }

    uint64_t assocKey = r_sel("cyanideTypeBannerOverlayWindow");
    if (!assocKey) return 0;
    uint64_t cachedWin = r_dlsym_call(R_TIMEOUT, "objc_getAssociatedObject",
                                      app, assocKey, 0, 0, 0, 0, 0, 0);
    if (r_is_objc_ptr(cachedWin)) {
        r_dlsym_call(R_TIMEOUT, "objc_setAssociatedObject",
                     app, assocKey, 0, 1, 0, 0, 0, 0);
    }

    uint64_t keyWin = r_msg2_main(app, "keyWindow", 0, 0, 0, 0);
    if (!r_is_objc_ptr(keyWin)) {
        uint64_t windows = r_msg2_main(app, "windows", 0, 0, 0, 0);
        uint64_t count = r_is_objc_ptr(windows) ? r_msg2_main(windows, "count", 0, 0, 0, 0) : 0;
        if (count > 0 && count < 64) keyWin = r_msg2_main(windows, "objectAtIndex:", 0, 0, 0, 0);
    }
    if (!r_is_objc_ptr(keyWin)) { printf("[TYPEBANNER] keyWindow nil\n"); return 0; }

    uint64_t scene = r_msg2_main(keyWin, "windowScene", 0, 0, 0, 0);
    if (!r_is_objc_ptr(scene)) { printf("[TYPEBANNER] windowScene nil\n"); return 0; }

    uint64_t UIWindow = r_class("UIWindow");
    if (!r_is_objc_ptr(UIWindow)) { printf("[TYPEBANNER] UIWindow missing\n"); return 0; }

    printf("[TYPEBANNER] creating SpringBoard overlay window scene=0x%llx\n", scene);
    uint64_t winAlloc = r_msg2_main(UIWindow, "alloc", 0, 0, 0, 0);
    if (!r_is_objc_ptr(winAlloc)) return 0;
    uint64_t win = r_msg2_main(winAlloc, "initWithWindowScene:", scene, 0, 0, 0);
    if (!r_is_objc_ptr(win)) return 0;

    // Window: clear background, alert-level, no user interaction so taps
    // pass through everywhere except the banner pill itself (which is just
    // a label — no interaction yet).
    uint64_t UIColor = r_class("UIColor");
    if (r_is_objc_ptr(UIColor)) {
        uint64_t clear = r_msg2_main(UIColor, "clearColor", 0, 0, 0, 0);
        if (r_is_objc_ptr(clear)) r_msg2_main(win, "setBackgroundColor:", clear, 0, 0, 0);
    }
    r_msg2_main(win, "setUserInteractionEnabled:", 0, 0, 0, 0);

    // Label as the banner pill itself.
    uint64_t UILabel = r_class("UILabel");
    if (!r_is_objc_ptr(UILabel)) return 0;
    uint64_t labelAlloc = r_msg2_main(UILabel, "alloc", 0, 0, 0, 0);
    if (!r_is_objc_ptr(labelAlloc)) return 0;
    uint64_t label = r_msg2_main(labelAlloc, "init", 0, 0, 0, 0);
    if (!r_is_objc_ptr(label)) return 0;

    r_msg2_main(label, "setTag:", kTypeBannerOverlayTag, 0, 0, 0);
    r_msg2_main(label, "setTextAlignment:", 1, 0, 0, 0);  // NSTextAlignmentCenter
    r_msg2_main(label, "setNumberOfLines:", 1, 0, 0, 0);
    r_msg2_main(label, "setAdjustsFontSizeToFitWidth:", 1, 0, 0, 0);
    if (r_is_objc_ptr(UIColor)) {
        uint64_t black = r_msg2_main(UIColor, "blackColor", 0, 0, 0, 0);
        uint64_t white = r_msg2_main(UIColor, "whiteColor", 0, 0, 0, 0);
        if (r_is_objc_ptr(black)) r_msg2_main(label, "setBackgroundColor:", black, 0, 0, 0);
        if (r_is_objc_ptr(white)) r_msg2_main(label, "setTextColor:", white, 0, 0, 0);
    }
    uint64_t font = tb_banner_font();
    if (r_is_objc_ptr(font)) r_msg2_main(label, "setFont:", font, 0, 0, 0);

    // Rounded pill: setCornerRadius + masksToBounds on the label's layer.
    uint64_t layer = r_msg2_main(label, "layer", 0, 0, 0, 0);
    if (r_is_objc_ptr(layer)) {
        tb_send_double_main(layer, "setCornerRadius:", kTypeBannerCornerRadius);
        r_msg2_main(layer, "setMasksToBounds:", 1, 0, 0, 0);
    }

    r_msg2_main(win, "addSubview:", label, 0, 0, 0);
    tb_send_double_main(win, "setWindowLevel:", kTypeBannerWinLevel);
    r_msg2_main(win, "setHidden:", 1, 0, 0, 0);  // start hidden, show on demand

    r_dlsym_call(R_TIMEOUT, "objc_setAssociatedObject",
                 app, assocKey, win, 1, 0, 0, 0, 0);
    gTypeBannerWindow = win;
    gTypeBannerLabel = label;
    printf("[TYPEBANNER] created window=0x%llx label=0x%llx\n", win, label);
    return win;
}

static bool tb_apply_banner_text_and_frame(NSString *text)
{
    if (!r_is_objc_ptr(gTypeBannerWindow) || !r_is_objc_ptr(gTypeBannerLabel)) {
        return false;
    }
    if (text.length == 0) text = @"Someone is typing…";

    uint64_t ns = tb_remote_nsstring(text);
    if (!r_is_objc_ptr(ns)) {
        printf("[TYPEBANNER] banner: NSString alloc failed\n");
        return false;
    }
    r_msg2_main(gTypeBannerLabel, "setText:", ns, 0, 0, 0);
    r_dlsym_call(R_TIMEOUT, "CFRelease", ns, 0, 0, 0, 0, 0, 0, 0);

    CGRect screen = UIScreen.mainScreen.bounds;
    double screenW = screen.size.width > 100.0 ? screen.size.width : 390.0;
    double width = tb_estimate_label_width(text);
    if (width > screenW - 2 * kTypeBannerSideMargin) width = screenW - 2 * kTypeBannerSideMargin;
    double x = floor((screenW - width) / 2.0);
    double y = tb_banner_top_y();

    tb_send_rect_main(gTypeBannerWindow, "setFrame:", x, y, width, kTypeBannerHeight);
    tb_send_rect_main(gTypeBannerLabel, "setFrame:", 0, 0, width, kTypeBannerHeight);
    return true;
}

bool typebanner_prepare_in_springboard_session(void)
{
    uint64_t win = tb_find_or_create_window();
    if (!r_is_objc_ptr(win) || !r_is_objc_ptr(gTypeBannerLabel)) {
        printf("[TYPEBANNER] prepare: no window\n");
        return false;
    }

    NSString *text = tb_banner_text_for_display_name(nil);
    bool ok = tb_apply_banner_text_and_frame(text);
    if (ok) {
        r_msg2_main(gTypeBannerWindow, "setHidden:", 1, 0, 0, 0);
        printf("[TYPEBANNER] prepare: hidden window ready text='%s'\n",
               text.UTF8String ?: "");
    }
    return ok;
}

bool typebanner_show_in_springboard_session(NSString *displayName)
{
    uint64_t win = tb_find_or_create_window();
    if (!r_is_objc_ptr(win) || !r_is_objc_ptr(gTypeBannerLabel)) {
        printf("[TYPEBANNER] show: no window\n");
        return false;
    }

    NSString *text = tb_banner_text_for_display_name(displayName);
    if (!tb_apply_banner_text_and_frame(text)) return false;

    r_msg2_main(win, "setHidden:", 0, 0, 0, 0);
    printf("[TYPEBANNER] show: '%s'\n", text.UTF8String);
    return true;
}

bool typebanner_hide_in_springboard_session(void)
{
    if (!r_is_objc_ptr(gTypeBannerWindow)) {
        tb_find_existing_window();
    }
    if (!r_is_objc_ptr(gTypeBannerWindow)) return true;

    r_msg2_main(gTypeBannerWindow, "setHidden:", 1, 0, 0, 0);
    printf("[TYPEBANNER] hide\n");
    return true;
}

bool typebanner_show_in_springboard_remote_session(RemoteCallSession *session, NSString *displayName)
{
    __block bool ok = false;
    remote_call_with_session(session, ^{
        ok = typebanner_show_in_springboard_session(displayName);
    });
    return ok;
}

bool typebanner_prepare_in_springboard_remote_session(RemoteCallSession *session)
{
    __block bool ok = false;
    remote_call_with_session(session, ^{
        ok = typebanner_prepare_in_springboard_session();
    });
    return ok;
}

bool typebanner_hide_in_springboard_remote_session(RemoteCallSession *session)
{
    __block bool ok = false;
    remote_call_with_session(session, ^{
        ok = typebanner_hide_in_springboard_session();
    });
    return ok;
}

static uint64_t tb_mobilesms_keepalive_assoc_key(void)
{
    return r_sel("cyanideTypeBannerMobileSMSKeepAliveAssertion");
}

static void tb_load_runningboard_services_if_needed(void)
{
    if (r_is_objc_ptr(r_class("RBSAssertion"))) return;

    uint64_t path = r_alloc_str("/System/Library/PrivateFrameworks/RunningBoardServices.framework/RunningBoardServices");
    if (!path) return;
    r_dlsym_call(R_TIMEOUT, "dlopen", path, 1, 0, 0, 0, 0, 0, 0);
    r_free(path);
}

bool typebanner_release_mobilesms_keepalive_in_springboard_session(void)
{
    if (!kTypeBannerSpringBoardRBSKeepAliveEnabled) {
        gTypeBannerMobileKeepAliveAssertion = 0;
        gTypeBannerMobileKeepAlivePid = 0;
        gTypeBannerMobileKeepAliveFailureLogged = false;
        return true;
    }

    uint64_t app = tb_springboard_application();
    uint64_t assocKey = tb_mobilesms_keepalive_assoc_key();
    uint64_t assertion = 0;
    if (r_is_objc_ptr(app) && assocKey) {
        assertion = r_dlsym_call(R_TIMEOUT, "objc_getAssociatedObject",
                                 app, assocKey, 0, 0, 0, 0, 0, 0);
    }
    if (r_is_objc_ptr(assertion)) {
        r_msg2(assertion, "invalidate", 0, 0, 0, 0);
        printf("[TYPEBANNER] released MobileSMS keepalive assertion pid=%u ptr=0x%llx\n",
               gTypeBannerMobileKeepAlivePid, assertion);
    }
    if (r_is_objc_ptr(app) && assocKey) {
        r_dlsym_call(R_TIMEOUT, "objc_setAssociatedObject",
                     app, assocKey, 0, 1, 0, 0, 0, 0);
    }

    gTypeBannerMobileKeepAliveAssertion = 0;
    gTypeBannerMobileKeepAlivePid = 0;
    gTypeBannerMobileKeepAliveFailureLogged = false;
    return true;
}

bool typebanner_ensure_mobilesms_keepalive_in_springboard_session(uint32_t pid)
{
    if (pid == 0) return false;
    if (!kTypeBannerSpringBoardRBSKeepAliveEnabled) return false;

    uint64_t app = tb_springboard_application();
    uint64_t assocKey = tb_mobilesms_keepalive_assoc_key();
    uint64_t existing = 0;
    if (r_is_objc_ptr(app) && assocKey) {
        existing = r_dlsym_call(R_TIMEOUT, "objc_getAssociatedObject",
                                app, assocKey, 0, 0, 0, 0, 0, 0);
    }
    if (r_is_objc_ptr(existing)) {
        uint64_t valid = r_msg2(existing, "isValid", 0, 0, 0, 0);
        if (gTypeBannerMobileKeepAlivePid == pid && (valid & 0xff) != 0) {
            gTypeBannerMobileKeepAliveAssertion = existing;
            return true;
        }
        r_msg2(existing, "invalidate", 0, 0, 0, 0);
        r_dlsym_call(R_TIMEOUT, "objc_setAssociatedObject",
                     app, assocKey, 0, 1, 0, 0, 0, 0);
    }
    gTypeBannerMobileKeepAliveAssertion = 0;
    gTypeBannerMobileKeepAlivePid = 0;

    tb_load_runningboard_services_if_needed();

    uint64_t RBSAssertion = r_class("RBSAssertion");
    uint64_t RBSTarget = r_class("RBSTarget");
    uint64_t RBSLegacyAttribute = r_class("RBSLegacyAttribute");
    uint64_t NSArray = r_class("NSArray");
    if (!r_is_objc_ptr(RBSAssertion) ||
        !r_is_objc_ptr(RBSTarget) ||
        !r_is_objc_ptr(RBSLegacyAttribute) ||
        !r_is_objc_ptr(NSArray)) {
        if (!gTypeBannerMobileKeepAliveFailureLogged) {
            printf("[TYPEBANNER] MobileSMS keepalive unavailable: RBS classes missing assertion=0x%llx target=0x%llx legacy=0x%llx array=0x%llx\n",
                   RBSAssertion, RBSTarget, RBSLegacyAttribute, NSArray);
            gTypeBannerMobileKeepAliveFailureLogged = true;
        }
        return false;
    }

    uint64_t target = r_msg2(RBSTarget, "targetWithPid:", pid, 0, 0, 0);
    uint64_t legacy = r_msg2(RBSLegacyAttribute, "attributeWithReason:flags:",
                             kTypeBannerRBSLegacyBackgroundUIReason,
                             kTypeBannerRBSLegacyPreventSuspendFlag,
                             0, 0);
    uint64_t attributes = r_is_objc_ptr(legacy)
        ? r_msg2(NSArray, "arrayWithObject:", legacy, 0, 0, 0)
        : 0;
    NSString *nameString = [NSString stringWithFormat:@"Cyanide TypeBanner MobileSMS pid %u", pid];
    uint64_t explanation = tb_remote_nsstring(nameString);
    uint64_t alloc = r_msg2(RBSAssertion, "alloc", 0, 0, 0, 0);
    uint64_t assertion = (r_is_objc_ptr(alloc) &&
                          r_is_objc_ptr(target) &&
                          r_is_objc_ptr(attributes) &&
                          r_is_objc_ptr(explanation))
        ? r_msg2(alloc, "initWithExplanation:target:attributes:",
                 explanation, target, attributes, 0)
        : 0;
    if (r_is_objc_ptr(explanation)) {
        r_dlsym_call(R_TIMEOUT, "CFRelease", explanation, 0, 0, 0, 0, 0, 0, 0);
    }

    uint64_t acquired = 0;
    uint64_t valid = 0;
    if (r_is_objc_ptr(assertion)) {
        acquired = r_msg2(assertion, "acquireWithError:", 0, 0, 0, 0);
        valid = r_msg2(assertion, "isValid", 0, 0, 0, 0);
    }
    if (!r_is_objc_ptr(assertion) || (((acquired | valid) & 0xff) == 0)) {
        if (r_is_objc_ptr(assertion)) r_msg2(assertion, "invalidate", 0, 0, 0, 0);
        if (!gTypeBannerMobileKeepAliveFailureLogged) {
            printf("[TYPEBANNER] MobileSMS keepalive acquire failed pid=%u target=0x%llx legacy=0x%llx assertion=0x%llx acquired=%llu valid=%llu\n",
                   pid, target, legacy, assertion, acquired, valid);
            gTypeBannerMobileKeepAliveFailureLogged = true;
        }
        return false;
    }

    if (r_is_objc_ptr(app) && assocKey) {
        r_dlsym_call(R_TIMEOUT, "objc_setAssociatedObject",
                     app, assocKey, assertion, 1, 0, 0, 0, 0);
    }
    gTypeBannerMobileKeepAliveAssertion = assertion;
    gTypeBannerMobileKeepAlivePid = pid;
    gTypeBannerMobileKeepAliveFailureLogged = false;
    printf("[TYPEBANNER] acquired MobileSMS keepalive assertion pid=%u ptr=0x%llx valid=%llu\n",
           pid, assertion, valid);
    return true;
}

bool typebanner_ensure_mobilesms_keepalive_in_springboard_remote_session(RemoteCallSession *session, uint32_t pid)
{
    __block bool ok = false;
    remote_call_with_session(session, ^{
        ok = typebanner_ensure_mobilesms_keepalive_in_springboard_session(pid);
    });
    return ok;
}

bool typebanner_release_mobilesms_keepalive_in_springboard_remote_session(RemoteCallSession *session)
{
    __block bool ok = false;
    remote_call_with_session(session, ^{
        ok = typebanner_release_mobilesms_keepalive_in_springboard_session();
    });
    return ok;
}

bool typebanner_has_remote_state(void)
{
    return r_is_objc_ptr(gTypeBannerWindow) ||
           r_is_objc_ptr(gTypeBannerLabel) ||
           r_is_objc_ptr(gTypeBannerMobileKeepAliveAssertion) ||
           gTypeBannerMobileKeepAlivePid != 0 ||
           gTypeBannerLastName.length > 0;
}

void typebanner_forget_remote_state(void)
{
    gTypeBannerWindow = 0;
    gTypeBannerLabel = 0;
    gTypeBannerFontPtr = 0;
    gTypeBannerLastName = nil;
    gTypeBannerMobileKeepAliveAssertion = 0;
    gTypeBannerMobileKeepAlivePid = 0;
    gTypeBannerMobileKeepAliveFailureLogged = false;
    gTypeBannerMobileUnreachableLastTick = false;
    gTypeBannerMobileBootstrapCooldownPid = 0;
    gTypeBannerMobileBootstrapCooldownUntilUS = 0;
    gTypeBannerMobileBootstrapCooldownLogged = false;
    gTypeBannerImagentPollRemoteHealthy = true;
    gTypeBannerImagentReachableLastTick = false;
    gTypeBannerImagentProbeCooldownUntilUS = 0;
    gTypeBannerImagentProbeCooldownLogged = false;
    gTypeBannerLastImagentInitFailure = RemoteCallInitFailureNone;
    gTypeBannerLastImagentInitFailurePid = 0;
    printf("[TYPEBANNER] forgot remote state\n");
}

bool typebanner_mobile_was_unreachable_last_tick(void)
{
    return gTypeBannerMobileUnreachableLastTick;
}

#pragma mark - Detection helpers (MobileSMS side)

// Cap on chats per poll. IMChatRegistry.allExistingChats is typically <300
// on a busy device; cap so a bogus return doesn't melt us.
static const uint64_t kTbMaxChatsPerPoll = 512;

static NSString *tb_remote_nsstring_to_utf8(uint64_t nsStringObj, uint64_t selUTF8)
{
    char buf[256] = {0};
    (void)selUTF8;
    if (!r_is_objc_ptr(nsStringObj)) return nil;

    uint64_t remoteBuf = r_dlsym_call(R_TIMEOUT, "malloc", sizeof(buf), 0, 0, 0, 0, 0, 0, 0);
    if (!remoteBuf) return nil;

    bool ok = remote_write(remoteBuf, buf, sizeof(buf));
    uint64_t selGetCString = r_sel("getCString:maxLength:encoding:");
    if (ok && selGetCString) {
        ok = ((r_msg(nsStringObj,
                     selGetCString,
                     remoteBuf,
                     sizeof(buf) - 1,
                     0x08000100,  // NSUTF8StringEncoding
                     0) & 0xff) != 0);
    } else {
        ok = false;
    }
    if (ok) ok = remote_read(remoteBuf, buf, sizeof(buf) - 1);
    r_free(remoteBuf);
    if (!ok) return nil;

    if (buf[0] == '\0') return nil;
    return [NSString stringWithUTF8String:buf];
}

static NSString *tb_trimmed_name(NSString *s)
{
    if (s.length == 0) return nil;
    NSString *trimmed = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) return nil;
    if ([trimmed isEqualToString:@"(null)"] ||
        [trimmed isEqualToString:@"<null>"] ||
        [trimmed isEqualToString:@"null"]) {
        return nil;
    }
    return trimmed;
}

static bool tb_obj_responds(uint64_t obj, uint64_t selResponds, uint64_t sel)
{
    if (!r_is_objc_ptr(obj) || !selResponds || !sel) return false;
    return (r_msg(obj, selResponds, sel, 0, 0, 0) & 0xff) != 0;
}

static uint64_t tb_msg0_if_responds(uint64_t obj, uint64_t selResponds, uint64_t sel)
{
    if (!tb_obj_responds(obj, selResponds, sel)) return 0;
    return r_msg(obj, sel, 0, 0, 0, 0);
}

static NSString *tb_remote_stringish_to_utf8(uint64_t obj, uint64_t selResponds, uint64_t selUTF8)
{
    if (!tb_obj_responds(obj, selResponds, selUTF8)) return nil;
    return tb_trimmed_name(tb_remote_nsstring_to_utf8(obj, selUTF8));
}

static NSString *tb_string_from_selector(uint64_t obj,
                                         uint64_t selResponds,
                                         uint64_t selUTF8,
                                         uint64_t sel)
{
    uint64_t value = tb_msg0_if_responds(obj, selResponds, sel);
    return tb_remote_stringish_to_utf8(value, selResponds, selUTF8);
}

static NSString *tb_remote_class_name(uint64_t obj)
{
    if (!r_is_objc_ptr(obj)) return nil;
    uint64_t cls = r_dlsym_call(R_TIMEOUT, "object_getClass",
                                obj, 0, 0, 0, 0, 0, 0, 0);
    if (!r_is_objc_ptr(cls)) return nil;
    uint64_t name = r_dlsym_call(R_TIMEOUT, "NSStringFromClass",
                                 cls, 0, 0, 0, 0, 0, 0, 0);
    return tb_remote_nsstring_to_utf8(name, 0);
}

static NSString *tb_remote_description(uint64_t obj,
                                       uint64_t selResponds,
                                       uint64_t selUTF8)
{
    NSString *desc = tb_string_from_selector(obj, selResponds, selUTF8, r_sel("description"));
    if (desc.length > 180) {
        desc = [[desc substringToIndex:180] stringByAppendingString:@"…"];
    }
    return desc;
}

static NSString *tb_contact_display_name(uint64_t contact,
                                         uint64_t selResponds,
                                         uint64_t selUTF8)
{
    if (!r_is_objc_ptr(contact)) return nil;

    uint64_t CNContactFormatter = r_class("CNContactFormatter");
    if (!r_is_objc_ptr(CNContactFormatter)) return nil;

    uint64_t selStringFromContact = r_sel("stringFromContact:style:");
    if (!tb_obj_responds(CNContactFormatter, selResponds, selStringFromContact)) return nil;

    uint64_t name = r_msg(CNContactFormatter, selStringFromContact, contact, 0, 0, 0);
    return tb_remote_stringish_to_utf8(name, selResponds, selUTF8);
}

static NSString *tb_display_name_for_address_object(uint64_t address,
                                                    uint64_t selResponds,
                                                    uint64_t selUTF8)
{
    if (!r_is_objc_ptr(address)) return nil;

    uint64_t selDisplayForAddress = r_sel("displayNameForAddress:");
    uint64_t selDisplayWithRawAddress = r_sel("displayNameWithRawAddress:isSpamFilteringEnabled:");
    const char *classes[] = { "IMDHandle", "IMHandle", "IMPerson", "IMChat", "IMChatRegistry" };
    for (size_t i = 0; i < sizeof(classes) / sizeof(classes[0]); i++) {
        uint64_t cls = r_class(classes[i]);
        if (!r_is_objc_ptr(cls)) continue;

        if (tb_obj_responds(cls, selResponds, selDisplayForAddress)) {
            NSString *name = tb_remote_stringish_to_utf8(r_msg(cls, selDisplayForAddress, address, 0, 0, 0),
                                                         selResponds,
                                                         selUTF8);
            if (name.length > 0) return name;
        }
        if (tb_obj_responds(cls, selResponds, selDisplayWithRawAddress)) {
            NSString *name = tb_remote_stringish_to_utf8(r_msg(cls, selDisplayWithRawAddress, address, 0, 0, 0),
                                                         selResponds,
                                                         selUTF8);
            if (name.length > 0) return name;
        }
    }
    return nil;
}

static NSString *tb_name_from_handle_collection(uint64_t collection,
                                                uint64_t selResponds,
                                                uint64_t selUTF8,
                                                bool allowRawID);

static NSString *tb_name_from_handle(uint64_t handle,
                                     uint64_t selResponds,
                                     uint64_t selUTF8,
                                     bool allowRawID)
{
    if (!r_is_objc_ptr(handle)) return nil;

    if (tb_obj_responds(handle, selResponds, selUTF8)) {
        NSString *direct = tb_remote_stringish_to_utf8(handle, selResponds, selUTF8);
        if (direct.length > 0) return direct;
    }

    uint64_t selIsMe = r_sel("isMe");
    if (tb_obj_responds(handle, selResponds, selIsMe) &&
        (r_msg(handle, selIsMe, 0, 0, 0, 0) & 0xff) != 0) {
        return nil;
    }

    const char *contactSelectors[] = { "cnContact", "contact" };
    for (size_t i = 0; i < sizeof(contactSelectors) / sizeof(contactSelectors[0]); i++) {
        uint64_t contact = tb_msg0_if_responds(handle, selResponds, r_sel(contactSelectors[i]));
        NSString *name = tb_contact_display_name(contact, selResponds, selUTF8);
        if (name.length > 0) return name;
    }

    const char *nameSelectors[] = {
        "displayName",
        "fullName",
        "name",
        "senderName",
        "firstName",
        "businessName",
        "shortName",
    };
    for (size_t i = 0; i < sizeof(nameSelectors) / sizeof(nameSelectors[0]); i++) {
        NSString *name = tb_string_from_selector(handle, selResponds, selUTF8, r_sel(nameSelectors[i]));
        if (name.length > 0) return name;
    }

    const char *rawSelectors[] = {
        "senderIdentifiers",
        "displayID",
        "IDWithoutResource",
        "unformattedID",
        "ID",
        "handleID",
        "normalizedID",
    };
    for (size_t i = 0; i < sizeof(rawSelectors) / sizeof(rawSelectors[0]); i++) {
        uint64_t raw = tb_msg0_if_responds(handle, selResponds, r_sel(rawSelectors[i]));
        NSString *resolved = tb_display_name_for_address_object(raw, selResponds, selUTF8);
        if (resolved.length > 0) return resolved;

        NSString *collectionName = tb_name_from_handle_collection(raw, selResponds, selUTF8, allowRawID);
        if (collectionName.length > 0) return collectionName;

        if (allowRawID) {
            NSString *rawName = tb_remote_stringish_to_utf8(raw, selResponds, selUTF8);
            if (rawName.length > 0) return rawName;
        }
    }

    return nil;
}

static NSString *tb_name_from_handle_collection(uint64_t collection,
                                                uint64_t selResponds,
                                                uint64_t selUTF8,
                                                bool allowRawID)
{
    if (!r_is_objc_ptr(collection)) return nil;

    uint64_t selCount = r_sel("count");
    uint64_t selObjAt = r_sel("objectAtIndex:");
    uint64_t selAllObjects = r_sel("allObjects");
    uint64_t selAnyObject = r_sel("anyObject");

    if (tb_obj_responds(collection, selResponds, selObjAt)) {
        uint64_t count = tb_msg0_if_responds(collection, selResponds, selCount);
        if (count > 16) count = 16;
        for (uint64_t i = 0; i < count; i++) {
            NSString *name = tb_name_from_handle(r_msg(collection, selObjAt, i, 0, 0, 0),
                                                 selResponds,
                                                 selUTF8,
                                                 allowRawID);
            if (name.length > 0) return name;
        }
        return nil;
    }

    if (tb_obj_responds(collection, selResponds, selAllObjects)) {
        NSString *name = tb_name_from_handle_collection(r_msg(collection, selAllObjects, 0, 0, 0, 0),
                                                        selResponds,
                                                        selUTF8,
                                                        allowRawID);
        if (name.length > 0) return name;
    }

    if (tb_obj_responds(collection, selResponds, selAnyObject)) {
        NSString *name = tb_name_from_handle(r_msg(collection, selAnyObject, 0, 0, 0, 0),
                                             selResponds,
                                             selUTF8,
                                             allowRawID);
        if (name.length > 0) return name;
    }

    return tb_name_from_handle(collection, selResponds, selUTF8, allowRawID);
}

static NSString *tb_name_from_last_typing_message(uint64_t chat,
                                                  uint64_t selResponds,
                                                  uint64_t selUTF8)
{
    uint64_t selLastMessage = r_sel("lastMessage");
    uint64_t message = tb_msg0_if_responds(chat, selResponds, selLastMessage);
    if (!r_is_objc_ptr(message)) return nil;

    uint64_t selIncomingTyping = r_sel("isIncomingTypingMessage");
    if (tb_obj_responds(message, selResponds, selIncomingTyping) &&
        (r_msg(message, selIncomingTyping, 0, 0, 0, 0) & 0xff) == 0) {
        return nil;
    }

    const char *handleSelectors[] = { "sender", "handle" };
    for (size_t i = 0; i < sizeof(handleSelectors) / sizeof(handleSelectors[0]); i++) {
        uint64_t handle = tb_msg0_if_responds(message, selResponds, r_sel(handleSelectors[i]));
        NSString *name = tb_name_from_handle(handle, selResponds, selUTF8, false);
        if (name.length > 0) return name;
    }

    const char *rawSelectors[] = { "senderID", "handleID" };
    for (size_t i = 0; i < sizeof(rawSelectors) / sizeof(rawSelectors[0]); i++) {
        uint64_t raw = tb_msg0_if_responds(message, selResponds, r_sel(rawSelectors[i]));
        NSString *resolved = tb_display_name_for_address_object(raw, selResponds, selUTF8);
        if (resolved.length > 0) return resolved;
        NSString *rawName = tb_remote_stringish_to_utf8(raw, selResponds, selUTF8);
        if (rawName.length > 0) return rawName;
    }

    return nil;
}

static NSString *tb_name_for_typing_chat(uint64_t chat,
                                         uint64_t selResponds,
                                         uint64_t selUTF8,
                                         uint64_t selDisplay,
                                         uint64_t selChatId)
{
    const char *typingCollectionSelectors[] = { "currentTypingHandles", "typingHandles" };
    for (size_t i = 0; i < sizeof(typingCollectionSelectors) / sizeof(typingCollectionSelectors[0]); i++) {
        uint64_t handles = tb_msg0_if_responds(chat, selResponds, r_sel(typingCollectionSelectors[i]));
        NSString *name = tb_name_from_handle_collection(handles, selResponds, selUTF8, true);
        if (name.length > 0) return name;
    }

    uint64_t typingIndicators = tb_msg0_if_responds(chat, selResponds, r_sel("typingIndicators"));
    NSString *typingIndicatorName = tb_name_from_handle_collection(typingIndicators, selResponds, selUTF8, true);
    if (typingIndicatorName.length > 0) return typingIndicatorName;

    uint64_t trackingController = tb_msg0_if_responds(chat, selResponds, r_sel("typingTrackingController"));
    for (size_t i = 0; i < sizeof(typingCollectionSelectors) / sizeof(typingCollectionSelectors[0]); i++) {
        uint64_t handles = tb_msg0_if_responds(trackingController, selResponds, r_sel(typingCollectionSelectors[i]));
        NSString *name = tb_name_from_handle_collection(handles, selResponds, selUTF8, true);
        if (name.length > 0) return name;
    }

    NSString *lastMessageName = tb_name_from_last_typing_message(chat, selResponds, selUTF8);
    if (lastMessageName.length > 0) return lastMessageName;

    const char *chatHandleSelectors[] = {
        "lastAddressedHandle",
        "recipient",
        "recipients",
        "participants",
        "handles",
    };
    for (size_t i = 0; i < sizeof(chatHandleSelectors) / sizeof(chatHandleSelectors[0]); i++) {
        uint64_t obj = tb_msg0_if_responds(chat, selResponds, r_sel(chatHandleSelectors[i]));
        NSString *name = tb_name_from_handle_collection(obj, selResponds, selUTF8, true);
        if (name.length > 0) return name;
    }

    NSString *display = tb_string_from_selector(chat, selResponds, selUTF8, selDisplay);
    if (display.length > 0) return display;

    uint64_t rawChatId = tb_msg0_if_responds(chat, selResponds, selChatId);
    NSString *resolved = tb_display_name_for_address_object(rawChatId, selResponds, selUTF8);
    if (resolved.length > 0) return resolved;

    return tb_remote_stringish_to_utf8(rawChatId, selResponds, selUTF8);
}

static NSString *tb_name_for_daemon_typing_message(uint64_t message,
                                                   uint64_t chat,
                                                   uint64_t selResponds,
                                                   uint64_t selUTF8,
                                                   uint64_t selDisplay,
                                                   uint64_t selChatId)
{
    const char *messageNameSelectors[] = {
        "senderName",
        "displayName",
        "name",
    };
    for (size_t i = 0; i < sizeof(messageNameSelectors) / sizeof(messageNameSelectors[0]); i++) {
        NSString *name = tb_string_from_selector(message,
                                                 selResponds,
                                                 selUTF8,
                                                 r_sel(messageNameSelectors[i]));
        if (name.length > 0) return name;
    }

    const char *messageHandleSelectors[] = {
        "senderHandle",
        "sender",
        "handle",
    };
    for (size_t i = 0; i < sizeof(messageHandleSelectors) / sizeof(messageHandleSelectors[0]); i++) {
        uint64_t handle = tb_msg0_if_responds(message, selResponds, r_sel(messageHandleSelectors[i]));
        NSString *name = tb_name_from_handle(handle, selResponds, selUTF8, true);
        if (name.length > 0) return name;
    }

    const char *messageRawSelectors[] = {
        "fromIdentifier",
        "senderIdentifiers",
        "handleID",
        "unformattedID",
    };
    for (size_t i = 0; i < sizeof(messageRawSelectors) / sizeof(messageRawSelectors[0]); i++) {
        uint64_t raw = tb_msg0_if_responds(message, selResponds, r_sel(messageRawSelectors[i]));
        NSString *name = tb_name_from_handle_collection(raw, selResponds, selUTF8, true);
        if (name.length > 0) return name;

        NSString *resolved = tb_display_name_for_address_object(raw, selResponds, selUTF8);
        if (resolved.length > 0) return resolved;

        NSString *rawName = tb_remote_stringish_to_utf8(raw, selResponds, selUTF8);
        if (rawName.length > 0) return rawName;
    }

    NSString *display = tb_string_from_selector(chat, selResponds, selUTF8, selDisplay);
    if (display.length > 0) return display;

    uint64_t rawChatId = tb_msg0_if_responds(chat, selResponds, selChatId);
    NSString *resolved = tb_display_name_for_address_object(rawChatId, selResponds, selUTF8);
    if (resolved.length > 0) return resolved;

    return tb_remote_stringish_to_utf8(rawChatId, selResponds, selUTF8);
}

static uint64_t tb_imagent_recents_controller(uint64_t registry, uint64_t selResponds)
{
    uint64_t recents = tb_msg0_if_responds(registry, selResponds, r_sel("recentsController"));
    if (r_is_objc_ptr(recents)) return recents;

    uint64_t IMDRecentsController = r_class("IMDRecentsController");
    if (!r_is_objc_ptr(IMDRecentsController)) return 0;

    const char *singletonSelectors[] = {
        "sharedInstance",
        "sharedController",
        "sharedRecentsController",
    };
    for (size_t i = 0; i < sizeof(singletonSelectors) / sizeof(singletonSelectors[0]); i++) {
        recents = tb_msg0_if_responds(IMDRecentsController, selResponds, r_sel(singletonSelectors[i]));
        if (r_is_objc_ptr(recents)) return recents;
    }

    return 0;
}

static uint64_t tb_typing_context_from_recents(uint64_t recents,
                                               uint64_t selResponds,
                                               const char **nameOut)
{
    if (!r_is_objc_ptr(recents)) return 0;

    const char *contextNames[] = {
        "_incomingMessagesTypingContext",
        "_typingContext",
        "incomingMessagesTypingContext",
        "typingContext",
    };
    for (size_t i = 0; i < sizeof(contextNames) / sizeof(contextNames[0]); i++) {
        uint64_t ctx = tb_msg0_if_responds(recents, selResponds, r_sel(contextNames[i]));
        if (!r_is_objc_ptr(ctx) && contextNames[i][0] == '_') {
            ctx = r_ivar_value(recents, contextNames[i]);
        }
        if (r_is_objc_ptr(ctx)) {
            if (nameOut) *nameOut = contextNames[i];
            return ctx;
        }
    }

    return 0;
}

static NSString *tb_name_from_typing_context_object(uint64_t obj,
                                                    uint64_t fallbackKey,
                                                    uint64_t selResponds,
                                                    uint64_t selUTF8,
                                                    uint64_t selDisplay,
                                                    uint64_t selChatId,
                                                    bool *activeKnownOut)
{
    if (activeKnownOut) *activeKnownOut = false;
    if (!r_is_objc_ptr(obj)) return nil;

    uint64_t selIsFromMe = r_sel("isFromMe");
    if (tb_obj_responds(obj, selResponds, selIsFromMe) &&
        (r_msg(obj, selIsFromMe, 0, 0, 0, 0) & 0xff) != 0) {
        if (activeKnownOut) *activeKnownOut = true;
        return nil;
    }

    bool activeKnown = false;
    bool active = false;

    uint64_t selIsFinished = r_sel("isFinished");
    if (tb_obj_responds(obj, selResponds, selIsFinished)) {
        activeKnown = true;
        active = ((r_msg(obj, selIsFinished, 0, 0, 0, 0) & 0xff) == 0);
    }

    uint64_t selIncomingTyping = r_sel("isIncomingTypingMessage");
    if (tb_obj_responds(obj, selResponds, selIncomingTyping)) {
        activeKnown = true;
        active = ((r_msg(obj, selIncomingTyping, 0, 0, 0, 0) & 0xff) != 0);
    }

    uint64_t selTypingMessage = r_sel("isTypingMessage");
    if (tb_obj_responds(obj, selResponds, selTypingMessage)) {
        activeKnown = true;
        active = ((r_msg(obj, selTypingMessage, 0, 0, 0, 0) & 0xff) != 0);
    }

    uint64_t selCancelTyping = r_sel("isCancelTypingMessage");
    if (tb_obj_responds(obj, selResponds, selCancelTyping) &&
        (r_msg(obj, selCancelTyping, 0, 0, 0, 0) & 0xff) != 0) {
        activeKnown = true;
        active = false;
    }

    if (activeKnownOut) *activeKnownOut = activeKnown;
    if (!activeKnown || !active) return nil;

    uint64_t chat = tb_msg0_if_responds(obj, selResponds, r_sel("chat"));
    NSString *name = tb_name_for_daemon_typing_message(obj,
                                                       chat,
                                                       selResponds,
                                                       selUTF8,
                                                       selDisplay,
                                                       selChatId);
    if (name.length > 0) return name;

    name = tb_name_from_handle(fallbackKey, selResponds, selUTF8, true);
    if (name.length > 0) return name;

    return @"<unknown>";
}

static NSString *tb_name_from_imagent_typing_context(uint64_t registry,
                                                     uint64_t selResponds,
                                                     uint64_t selUTF8,
                                                     uint64_t selDisplay,
                                                     uint64_t selChatId,
                                                     int *hitsOut)
{
    if (hitsOut) *hitsOut = 0;

    uint64_t recents = tb_imagent_recents_controller(registry, selResponds);
    if (!r_is_objc_ptr(recents)) return nil;

    const char *contextName = NULL;
    uint64_t context = tb_typing_context_from_recents(recents, selResponds, &contextName);
    if (!r_is_objc_ptr(context)) return nil;

    uint64_t selCount = r_sel("count");
    uint64_t selAllKeys = r_sel("allKeys");
    uint64_t selObjAt = r_sel("objectAtIndex:");
    uint64_t selObjectForKey = r_sel("objectForKey:");
    uint64_t keys = tb_msg0_if_responds(context, selResponds, selAllKeys);
    if (!r_is_objc_ptr(keys) || !selCount || !selObjAt || !selObjectForKey) return nil;

    uint64_t rawCount = r_msg(keys, selCount, 0, 0, 0, 0);
    uint64_t count = rawCount;
    if (count > 32) count = 32;

    static bool s_loggedContextShape = false;
    bool logContextShape = (!s_loggedContextShape && rawCount > 0);
    if (!s_loggedContextShape) {
        printf("[TYPEBANNER] imagent recents: context=%s recents=0x%llx dict=0x%llx count=%llu\n",
               contextName ?: "(unknown)",
               recents,
               context,
               rawCount);
    }

    int hits = 0;
    NSString *firstName = nil;
    for (uint64_t i = 0; i < count; i++) {
        uint64_t key = r_msg(keys, selObjAt, i, 0, 0, 0);
        if (!r_is_objc_ptr(key)) continue;
        uint64_t value = r_msg(context, selObjectForKey, key, 0, 0, 0);
        if (!r_is_objc_ptr(value)) continue;

        if (logContextShape && i < 3) {
            NSString *keyClass = tb_remote_class_name(key);
            NSString *valueClass = tb_remote_class_name(value);
            NSString *keyDesc = tb_remote_description(key, selResponds, selUTF8);
            NSString *valueDesc = tb_remote_description(value, selResponds, selUTF8);
            printf("[TYPEBANNER] imagent recents: sample[%llu] keyClass=%s valueClass=%s key='%s' value='%s'\n",
                   i,
                   keyClass.UTF8String ?: "(nil)",
                   valueClass.UTF8String ?: "(nil)",
                   keyDesc.UTF8String ?: "(nil)",
                   valueDesc.UTF8String ?: "(nil)");
        }

        bool activeKnown = false;
        NSString *name = tb_name_from_typing_context_object(value,
                                                            key,
                                                            selResponds,
                                                            selUTF8,
                                                            selDisplay,
                                                            selChatId,
                                                            &activeKnown);
        if (!activeKnown) continue;
        if (name == nil) continue;

        hits++;
        if (hits == 1) firstName = name;
        if (hits >= 2) break;
    }
    if (rawCount > 0) s_loggedContextShape = true;

    if (hitsOut) *hitsOut = hits;
    if (hits >= 2) return @"__SEVERAL_PEOPLE__";
    if (hits == 1) return firstName.length ? firstName : @"";
    return nil;
}

static NSString *typebanner_poll_in_imagent_session(void)
{
    static bool s_announcedFirstDaemonPoll = false;
    bool announceThisPoll = !s_announcedFirstDaemonPoll;
    s_announcedFirstDaemonPoll = true;
    if (announceThisPoll) {
        printf("[TYPEBANNER] poll: entry (imagent original-thread-only)\n");
    }
    gTypeBannerImagentPollRemoteHealthy = true;
    int oldStableTimeoutFloorMS = remote_call_set_stable_timeout_floor_ms(1000);
#define TB_IMAGENT_POLL_RETURN(value) do { \
    remote_call_set_stable_timeout_floor_ms(oldStableTimeoutFloorMS); \
    return (value); \
} while (0)

    uint64_t IMDChatRegistry = r_class("IMDChatRegistry");
    if (!r_is_objc_ptr(IMDChatRegistry) || !remote_call_current_success()) {
        printf("[TYPEBANNER] imagent poll: IMDChatRegistry class not resolvable\n");
        gTypeBannerImagentPollRemoteHealthy = false;
        TB_IMAGENT_POLL_RETURN(nil);
    }

    uint64_t registry = r_msg2(IMDChatRegistry, "sharedInstance", 0, 0, 0, 0);
    if (!r_is_objc_ptr(registry) || !remote_call_current_success()) {
        printf("[TYPEBANNER] imagent poll: sharedInstance nil\n");
        gTypeBannerImagentPollRemoteHealthy = false;
        TB_IMAGENT_POLL_RETURN(nil);
    }

    uint64_t selResponds = r_sel("respondsToSelector:");
    uint64_t selUTF8 = r_sel("UTF8String");
    uint64_t selCount = r_sel("count");
    uint64_t selObjAt = r_sel("objectAtIndex:");
    uint64_t selLastMessage = r_sel("lastMessage");
    uint64_t selIncomingTyping = r_sel("isIncomingTypingMessage");
    uint64_t selDisplay = r_sel("displayName");
    uint64_t selChatId = r_sel("chatIdentifier");
    if (!selResponds || !selUTF8 || !selCount || !selObjAt || !selLastMessage || !selIncomingTyping) {
        printf("[TYPEBANNER] imagent poll: required selectors missing\n");
        gTypeBannerImagentPollRemoteHealthy = false;
        TB_IMAGENT_POLL_RETURN(nil);
    }

    int recentsHits = 0;
    NSString *recentsName = tb_name_from_imagent_typing_context(registry,
                                                                selResponds,
                                                                selUTF8,
                                                                selDisplay,
                                                                selChatId,
                                                                &recentsHits);
    if (!remote_call_current_success()) {
        printf("[TYPEBANNER] imagent poll: stopped replying while reading typing context\n");
        gTypeBannerImagentPollRemoteHealthy = false;
        TB_IMAGENT_POLL_RETURN(nil);
    }
    if (recentsHits > 0) {
        printf("[TYPEBANNER] imagent poll: recents typing=%d name='%s'\n",
               recentsHits,
               recentsName.length ? recentsName.UTF8String : "(none)");
        TB_IMAGENT_POLL_RETURN(recentsName ?: @"");
    }

    uint64_t allChats = 0;
    const char *chatCollectionSelectors[] = { "allChats", "chats", "allExistingChats" };
    for (size_t i = 0; i < sizeof(chatCollectionSelectors) / sizeof(chatCollectionSelectors[0]); i++) {
        allChats = tb_msg0_if_responds(registry, selResponds, r_sel(chatCollectionSelectors[i]));
        if (r_is_objc_ptr(allChats)) break;
    }
    if (!r_is_objc_ptr(allChats) || !remote_call_current_success()) {
        printf("[TYPEBANNER] imagent poll: no chat collection\n");
        gTypeBannerImagentPollRemoteHealthy = false;
        TB_IMAGENT_POLL_RETURN(nil);
    }

    uint64_t count = r_msg(allChats, selCount, 0, 0, 0, 0);
    if (!remote_call_current_success()) {
        printf("[TYPEBANNER] imagent poll: stopped replying while reading chat count\n");
        gTypeBannerImagentPollRemoteHealthy = false;
        TB_IMAGENT_POLL_RETURN(nil);
    }
    if (count > kTbMaxChatsPerPoll) {
        printf("[TYPEBANNER] imagent poll: chat count=%llu exceeds cap=%llu; truncating\n",
               count, kTbMaxChatsPerPoll);
        count = kTbMaxChatsPerPoll;
    }

    int hits = 0;
    NSString *firstName = nil;
    for (uint64_t i = 0; i < count; i++) {
        uint64_t chat = r_msg(allChats, selObjAt, i, 0, 0, 0);
        if (!remote_call_current_success()) {
            printf("[TYPEBANNER] imagent poll: stopped replying while reading chat[%llu]\n", i);
            gTypeBannerImagentPollRemoteHealthy = false;
            TB_IMAGENT_POLL_RETURN(nil);
        }
        if (!r_is_objc_ptr(chat)) continue;

        uint64_t message = tb_msg0_if_responds(chat, selResponds, selLastMessage);
        if (!remote_call_current_success()) {
            printf("[TYPEBANNER] imagent poll: stopped replying while reading lastMessage chat[%llu]\n", i);
            gTypeBannerImagentPollRemoteHealthy = false;
            TB_IMAGENT_POLL_RETURN(nil);
        }
        if (!r_is_objc_ptr(message)) continue;

        if (!tb_obj_responds(message, selResponds, selIncomingTyping)) continue;
        uint64_t isTyping = r_msg(message, selIncomingTyping, 0, 0, 0, 0);
        if (!remote_call_current_success()) {
            printf("[TYPEBANNER] imagent poll: stopped replying while checking typing message chat[%llu]\n", i);
            gTypeBannerImagentPollRemoteHealthy = false;
            TB_IMAGENT_POLL_RETURN(nil);
        }
        if ((isTyping & 0xff) == 0) continue;

        hits++;
        if (hits == 1) {
            NSString *name = tb_name_for_daemon_typing_message(message,
                                                               chat,
                                                               selResponds,
                                                               selUTF8,
                                                               selDisplay,
                                                               selChatId);
            if (!remote_call_current_success()) {
                printf("[TYPEBANNER] imagent poll: stopped replying while resolving typing name\n");
                gTypeBannerImagentPollRemoteHealthy = false;
                TB_IMAGENT_POLL_RETURN(nil);
            }
            firstName = name.length > 0 ? name : @"<unknown>";
        }
        if (hits >= 2) break;
    }

    NSString *result = nil;
    if (hits >= 2)      result = @"__SEVERAL_PEOPLE__";
    else if (hits == 1) result = firstName.length ? firstName : @"";

    static int s_lastHits = -1;
    static NSString *s_lastName = nil;
    BOOL nameChanged = (result || s_lastName) && ![result ?: @"" isEqualToString:s_lastName ?: @""];
    if (hits != s_lastHits || nameChanged) {
        printf("[TYPEBANNER] imagent poll: chats=%llu typing=%d name='%s'\n",
               count,
               hits,
               result.length ? result.UTF8String : "(none)");
        s_lastHits = hits;
        s_lastName = [result copy];
    }

    TB_IMAGENT_POLL_RETURN(result);
#undef TB_IMAGENT_POLL_RETURN
}

NSString *typebanner_poll_in_imagent_remote_session(RemoteCallSession *session)
{
    __block NSString *result = nil;
    remote_call_with_session(session, ^{
        result = typebanner_poll_in_imagent_session();
    });
    return result;
}

// On iOS 26 MobileSMS uses IMCore's IMChatRegistry as the source of truth
// for chat state. IMChat.isLastMessageTypingIndicator is the BOOL that
// drives both CKConversationListStandardCell.showTypingIndicator and the
// transcript-side CKTranscriptTypingIndicatorCell. Iterating allExistingChats
// and checking that flag works whether the user is on the conversation list,
// inside an open chat, or just has Messages resident in the background.
//
// The live loop no longer uses this path by default. Crash logs on iOS 26.0.1
// show MobileSMS dying at pc/lr=0x401 or PAC-failing in objc_msgSend after a
// synthetic RemoteCall thread is created, especially once the app suspends.
// Keep the poller around for manual diagnostics/fallback only.
NSString *typebanner_poll_in_mobilesms_session(void)
{
    static bool s_announcedFirstPoll = false;
    bool announceThisPoll = !s_announcedFirstPoll;
    s_announcedFirstPoll = true;
    if (announceThisPoll) {
        printf("[TYPEBANNER] poll: entry (MobileSMS)\n");
    }
    gTypeBannerPollRemoteHealthy = true;
    int oldStableTimeoutFloorMS = remote_call_set_stable_timeout_floor_ms(1000);
#define TB_POLL_RETURN(value) do { \
    remote_call_set_stable_timeout_floor_ms(oldStableTimeoutFloorMS); \
    return (value); \
} while (0)

    uint64_t IMChatRegistry = r_class("IMChatRegistry");
    if (!r_is_objc_ptr(IMChatRegistry) || !remote_call_current_success()) {
        // r_class calls objc_getClass remotely. If it returns nil, the
        // trojan isn't responding (MobileSMS suspended). Mark unhealthy so
        // the orchestrator drops the session.
        printf("[TYPEBANNER] poll: IMChatRegistry class not resolvable (session broken?)\n");
        gTypeBannerPollRemoteHealthy = false;
        TB_POLL_RETURN(nil);
    }

    uint64_t registry = r_msg2(IMChatRegistry, "sharedInstance", 0, 0, 0, 0);
    if (!r_is_objc_ptr(registry) || !remote_call_current_success()) {
        printf("[TYPEBANNER] poll: IMChatRegistry sharedInstance nil\n");
        gTypeBannerPollRemoteHealthy = false;
        TB_POLL_RETURN(nil);
    }

    uint64_t allChats = r_msg2(registry, "allExistingChats", 0, 0, 0, 0);
    if (!r_is_objc_ptr(allChats) || !remote_call_current_success()) {
        printf("[TYPEBANNER] poll: allExistingChats nil\n");
        gTypeBannerPollRemoteHealthy = false;
        TB_POLL_RETURN(nil);
    }

    uint64_t selCount    = r_sel("count");
    uint64_t selObjAt    = r_sel("objectAtIndex:");
    uint64_t selTyping   = r_sel("isLastMessageTypingIndicator");
    uint64_t selDisplay  = r_sel("displayName");
    uint64_t selChatId   = r_sel("chatIdentifier");
    uint64_t selResponds = r_sel("respondsToSelector:");
    uint64_t selUTF8     = r_sel("UTF8String");
    if (!selCount || !selObjAt || !selTyping ||
        (kTypeBannerResolveMobileSMSNames && (!selResponds || !selUTF8))) {
        printf("[TYPEBANNER] poll: required selectors missing\n");
        gTypeBannerPollRemoteHealthy = false;
        TB_POLL_RETURN(nil);
    }

    uint64_t count = r_msg(allChats, selCount, 0, 0, 0, 0);
    if (!remote_call_current_success()) {
        printf("[TYPEBANNER] poll: MobileSMS session stopped replying while reading chat count\n");
        gTypeBannerPollRemoteHealthy = false;
        TB_POLL_RETURN(nil);
    }
    if (count > kTbMaxChatsPerPoll) {
        printf("[TYPEBANNER] poll: chat count=%llu exceeds cap=%llu; truncating\n",
               count, kTbMaxChatsPerPoll);
        count = kTbMaxChatsPerPoll;
    }

    int hits = 0;
    NSString *firstName = nil;
    for (uint64_t i = 0; i < count; i++) {
        uint64_t chat = r_msg(allChats, selObjAt, i, 0, 0, 0);
        if (!remote_call_current_success()) {
            printf("[TYPEBANNER] poll: MobileSMS session stopped replying while reading chat[%llu]\n", i);
            gTypeBannerPollRemoteHealthy = false;
            TB_POLL_RETURN(nil);
        }
        if (!r_is_objc_ptr(chat)) continue;

        uint64_t isTyping = r_msg(chat, selTyping, 0, 0, 0, 0);
        if (!remote_call_current_success()) {
            printf("[TYPEBANNER] poll: MobileSMS session stopped replying while checking typing chat[%llu]\n", i);
            gTypeBannerPollRemoteHealthy = false;
            TB_POLL_RETURN(nil);
        }
        if ((isTyping & 0xff) == 0) continue;

        hits++;
        if (hits == 1) {
            if (kTypeBannerResolveMobileSMSNames) {
                NSString *name = tb_name_for_typing_chat(chat,
                                                         selResponds,
                                                         selUTF8,
                                                         selDisplay,
                                                         selChatId);
                if (!remote_call_current_success()) {
                    printf("[TYPEBANNER] poll: MobileSMS session stopped replying while resolving typing name\n");
                    gTypeBannerPollRemoteHealthy = false;
                    TB_POLL_RETURN(nil);
                }
                firstName = name.length > 0 ? name : @"<unknown>";
            } else {
                firstName = @"<unknown>";
            }
        }
        if (hits >= 2) break;
    }

    NSString *result = nil;
    if (hits >= 2)             result = @"__SEVERAL_PEOPLE__";
    else if (hits == 1)        result = firstName.length ? firstName : @"";

    // State-change detection: nil vs non-nil controls show vs hide; within
    // the shown state, log any display-name change too.
    BOOL hadBanner = (gTypeBannerLastName != nil);
    BOOL hasBanner = (result != nil);
    bool stateChanged = (hadBanner != hasBanner);
    if (!stateChanged && hasBanner &&
        ![result isEqualToString:gTypeBannerLastName ?: @""]) {
        stateChanged = true;
    }
    if (announceThisPoll || stateChanged) {
        printf("[TYPEBANNER] poll: chats=%llu typing=%d name='%s'\n",
               count, hits, result.UTF8String ?: "(none)");
    }
    TB_POLL_RETURN(result);
#undef TB_POLL_RETURN
}

NSString *typebanner_poll_in_mobilesms_remote_session(RemoteCallSession *session)
{
    __block NSString *result = nil;
    remote_call_with_session(session, ^{
        result = typebanner_poll_in_mobilesms_session();
    });
    return result;
}

#pragma mark - Diagnostic dump (MobileSMS side)

// Dump every IMChat in the registry with its typing/identifier state. Use
// to verify isLastMessageTypingIndicator is firing when someone is actively
// typing and the banner refuses to show.
void typebanner_diagnose_in_mobilesms_session(void)
{
    printf("[TYPEBANNER] diag: entry (MobileSMS)\n");

    uint64_t IMChatRegistry = r_class("IMChatRegistry");
    printf("[TYPEBANNER] diag: IMChatRegistry class=0x%llx\n", IMChatRegistry);
    if (!r_is_objc_ptr(IMChatRegistry)) return;

    uint64_t registry = r_msg2(IMChatRegistry, "sharedInstance", 0, 0, 0, 0);
    printf("[TYPEBANNER] diag: registry=0x%llx\n", registry);
    if (!r_is_objc_ptr(registry)) return;

    uint64_t allChats = r_msg2(registry, "allExistingChats", 0, 0, 0, 0);
    if (!r_is_objc_ptr(allChats)) {
        printf("[TYPEBANNER] diag: allExistingChats nil\n");
        return;
    }

    uint64_t selCount      = r_sel("count");
    uint64_t selObjAt      = r_sel("objectAtIndex:");
    uint64_t selTyping     = r_sel("isLastMessageTypingIndicator");
    uint64_t selLocalType  = r_sel("localUserIsTyping");
    uint64_t selDisplay    = r_sel("displayName");
    uint64_t selChatId     = r_sel("chatIdentifier");
    uint64_t selTypingGUID = r_sel("typingGUID");
    uint64_t selUTF8       = r_sel("UTF8String");

    uint64_t count = selCount ? r_msg(allChats, selCount, 0, 0, 0, 0) : 0;
    printf("[TYPEBANNER] diag: allExistingChats count=%llu\n", count);
    if (count == 0 || count > kTbMaxChatsPerPoll) return;

    uint64_t maxLog = count > 32 ? 32 : count;
    for (uint64_t i = 0; i < maxLog; i++) {
        uint64_t chat = r_msg(allChats, selObjAt, i, 0, 0, 0);
        if (!r_is_objc_ptr(chat)) continue;

        uint64_t isTyping = selTyping ? r_msg(chat, selTyping, 0, 0, 0, 0) : 0;
        uint64_t isLocal  = selLocalType ? r_msg(chat, selLocalType, 0, 0, 0, 0) : 0;
        NSString *name = selDisplay
            ? tb_remote_nsstring_to_utf8(r_msg(chat, selDisplay, 0, 0, 0, 0), selUTF8)
            : nil;
        NSString *cid = selChatId
            ? tb_remote_nsstring_to_utf8(r_msg(chat, selChatId, 0, 0, 0, 0), selUTF8)
            : nil;
        NSString *guid = selTypingGUID
            ? tb_remote_nsstring_to_utf8(r_msg(chat, selTypingGUID, 0, 0, 0, 0), selUTF8)
            : nil;

        printf("[TYPEBANNER] diag: chat[%llu] remoteTyping=%d localTyping=%d name='%s' id='%s' typingGUID='%s'\n",
               i,
               (int)(isTyping & 1), (int)(isLocal & 1),
               name.UTF8String ?: "(nil)",
               cid.UTF8String ?: "(nil)",
               guid.UTF8String ?: "(nil)");
    }

    printf("[TYPEBANNER] diag: done logged=%llu of %llu\n", maxLog, count);
}

void typebanner_diagnose_in_mobilesms_remote_session(RemoteCallSession *session)
{
    remote_call_with_session(session, ^{
        typebanner_diagnose_in_mobilesms_session();
    });
}

#pragma mark - Orchestrators

static void tb_note_mobilesms_init_ok(void)
{
    gTypeBannerLastMobileInitFailure = RemoteCallInitFailureNone;
    gTypeBannerLastMobileInitFailurePid = 0;
    gTypeBannerMobileBootstrapCooldownPid = 0;
    gTypeBannerMobileBootstrapCooldownUntilUS = 0;
    gTypeBannerMobileBootstrapCooldownLogged = false;
}

static void tb_defer_mobilesms_bootstrap(uint32_t pid, const char *reason)
{
    if (pid == 0) return;
    gTypeBannerMobileBootstrapCooldownPid = pid;
    gTypeBannerMobileBootstrapCooldownUntilUS = tb_now_us() + kTypeBannerMobileBootstrapCooldownUS;
    gTypeBannerMobileBootstrapCooldownLogged = false;
    if (reason && reason[0]) {
        printf("[TYPEBANNER] MobileSMS pid=%u bootstrap deferred: %s\n", pid, reason);
    }
}

static bool tb_mobilesms_bootstrap_deferred(uint32_t *pidOut)
{
    uint64_t until = gTypeBannerMobileBootstrapCooldownUntilUS;
    if (until == 0) return false;

    uint64_t now = tb_now_us();
    if (now >= until) {
        gTypeBannerMobileBootstrapCooldownPid = 0;
        gTypeBannerMobileBootstrapCooldownUntilUS = 0;
        gTypeBannerMobileBootstrapCooldownLogged = false;
        return false;
    }

    if (pidOut) *pidOut = gTypeBannerMobileBootstrapCooldownPid;
    if (!gTypeBannerMobileBootstrapCooldownLogged) {
        uint64_t remainingUS = until - now;
        printf("[TYPEBANNER] MobileSMS pid=%u bootstrap cooldown %.1fs; live loop still ticking\n",
               gTypeBannerMobileBootstrapCooldownPid,
               (double)remainingUS / 1000000.0);
        gTypeBannerMobileBootstrapCooldownLogged = true;
    }
    return true;
}

static void tb_log_mobilesms_unavailable(void)
{
    RemoteCallInitFailure failure = remote_call_last_init_failure();
    uint32_t pid = remote_call_last_init_failure_pid();
    if (failure == gTypeBannerLastMobileInitFailure &&
        pid == gTypeBannerLastMobileInitFailurePid) {
        return;
    }
    gTypeBannerLastMobileInitFailure = failure;
    gTypeBannerLastMobileInitFailurePid = pid;

    if (failure == RemoteCallInitFailureProcessMissing) {
        printf("[TYPEBANNER] MobileSMS process not found — open Messages.app once to spawn it.\n");
        return;
    }

    if (failure == RemoteCallInitFailureFirstExceptionTimeout && pid != 0) {
        printf("[TYPEBANNER] MobileSMS pid=%u is running but did not deliver the RemoteCall bootstrap exception; it is probably suspended in the background. Open Messages in the foreground for this poller.\n",
               pid);
        tb_defer_mobilesms_bootstrap(pid, NULL);
        return;
    }

    if (pid != 0) {
        printf("[TYPEBANNER] MobileSMS pid=%u RemoteCall init failed: %s\n",
               pid, remote_call_init_failure_description(failure));
        return;
    }

    printf("[TYPEBANNER] MobileSMS RemoteCall init failed: %s\n",
           remote_call_init_failure_description(failure));
}

static bool tb_imagent_probe_deferred(void)
{
    uint64_t now = tb_now_us();
    if (gTypeBannerImagentProbeCooldownUntilUS == 0 ||
        now >= gTypeBannerImagentProbeCooldownUntilUS) {
        gTypeBannerImagentProbeCooldownUntilUS = 0;
        gTypeBannerImagentProbeCooldownLogged = false;
        return false;
    }

    if (!gTypeBannerImagentProbeCooldownLogged) {
        double seconds = (double)(gTypeBannerImagentProbeCooldownUntilUS - now) / 1000000.0;
        printf("[TYPEBANNER] imagent safe probe cooldown %.1fs; daemon path still ticks\n",
               seconds);
        gTypeBannerImagentProbeCooldownLogged = true;
    }
    return true;
}

static void tb_defer_imagent_probe(const char *reason)
{
    gTypeBannerImagentProbeCooldownUntilUS = tb_now_us() + kTypeBannerImagentProbeCooldownUS;
    gTypeBannerImagentProbeCooldownLogged = false;
    if (reason) {
        printf("[TYPEBANNER] imagent safe probe deferred: %s\n", reason);
    }
}

static NSString *tb_try_imagent_original_thread_only_poll(RemoteCallSession **sessionRef)
{
    gTypeBannerImagentReachableLastTick = false;
    if (tb_imagent_probe_deferred()) return nil;

    RemoteCallSession *session = sessionRef ? *sessionRef : nil;
    bool ownsSession = false;
    if (!session) {
        printf("[TYPEBANNER] imagent safe probe: original-thread-only bootstrap\n");
        session = [[RemoteCallSession alloc] initWithProcess:@"imagent"
                                           useMigFilterBypass:NO
                                      firstExceptionTimeoutMS:TYPEBANNER_RC_MOBILESMS_FIRST_EXCEPTION_TIMEOUT_MS
                                           originalThreadOnly:YES];
        if (sessionRef) {
            *sessionRef = session;
        } else {
            ownsSession = true;
        }
    }
    if (!session) {
        RemoteCallInitFailure failure = remote_call_last_init_failure();
        uint32_t pid = remote_call_last_init_failure_pid();
        if (failure != gTypeBannerLastImagentInitFailure ||
            pid != gTypeBannerLastImagentInitFailurePid) {
            printf("[TYPEBANNER] imagent original-thread-only init failed pid=%u: %s\n",
                   pid,
                   remote_call_init_failure_description(failure));
            gTypeBannerLastImagentInitFailure = failure;
            gTypeBannerLastImagentInitFailurePid = pid;
        }
        tb_defer_imagent_probe("init failed");
        return nil;
    }

    __block NSString *detected = nil;
    @try {
        remote_call_with_session(session, ^{
            remote_call_set_stable_timeout_floor_ms(1000);
            detected = typebanner_poll_in_imagent_session();
        });
    } @catch (NSException *e) {
        printf("[TYPEBANNER] imagent poll exception: %s\n", e.reason.UTF8String);
        gTypeBannerImagentPollRemoteHealthy = false;
    }

    if (!gTypeBannerImagentPollRemoteHealthy) {
        if (sessionRef && *sessionRef == session) {
            [session abandonRemoteCall];
            *sessionRef = nil;
        } else if (ownsSession) {
            @try {
                [session destroyRemoteCall];
            } @catch (NSException *e) {
                printf("[TYPEBANNER] imagent original-thread-only destroy exception: %s\n",
                       e.reason.UTF8String);
            }
        }
        tb_defer_imagent_probe("poll stopped replying");
        return nil;
    }

    if (ownsSession) {
        @try {
            [session destroyRemoteCall];
        } @catch (NSException *e) {
            printf("[TYPEBANNER] imagent original-thread-only destroy exception: %s\n",
                   e.reason.UTF8String);
        }
    }

    gTypeBannerLastImagentInitFailure = RemoteCallInitFailureNone;
    gTypeBannerLastImagentInitFailurePid = 0;
    gTypeBannerImagentReachableLastTick = true;
    return detected;
}

bool typebanner_run_once_with_mobile_session_and_current_springboard(RemoteCallSession **mobileSessionRef,
                                                                    bool currentSpringBoardReady)
{
    return typebanner_run_once_with_cached_sessions(mobileSessionRef, NULL, currentSpringBoardReady);
}

bool typebanner_run_once_with_cached_sessions(RemoteCallSession **mobileSessionRef,
                                              RemoteCallSession **daemonSessionRef,
                                              bool currentSpringBoardReady)
{
    if (!mobileSessionRef) return typebanner_run_once();

    // Phase 1: poll imagent for typing state. The MobileSMS path below is
    // retained behind a kill switch for diagnostics/fallback only.
    NSString *currentName = nil;
    bool mobileSMSRunning = false;
    uint32_t mobilePidForKeepAlive = 0;
    RemoteCallSession *mobileSession = *mobileSessionRef;
    if (kTypeBannerDaemonOnlyDetection) {
        static bool s_loggedDaemonOnly = false;
        if (!s_loggedDaemonOnly) {
            printf("[TYPEBANNER] daemon-only detection enabled; MobileSMS RemoteCall polling disabled\n");
            s_loggedDaemonOnly = true;
        }
        if (mobileSession) {
            [mobileSession abandonRemoteCall];
            *mobileSessionRef = nil;
            mobileSession = nil;
        }
        gTypeBannerMobileUnreachableLastTick = true;
        currentName = tb_try_imagent_original_thread_only_poll(daemonSessionRef);
        if (!gTypeBannerImagentReachableLastTick) {
            return true;
        }
    } else if (!mobileSession) {
        uint32_t deferredPid = 0;
        if (tb_mobilesms_bootstrap_deferred(&deferredPid)) {
            mobilePidForKeepAlive = deferredPid;
        } else {
            // The live loop still ticks every second, but a suspended same-PID
            // MobileSMS does not get a full EXC_GUARD bootstrap attempt every
            // tick. That path is expensive, noisy, and leaves extra guarded
            // threads behind when the target is not dispatching exceptions.
            mobileSession = [[RemoteCallSession alloc] initWithProcess:kTypeBannerHostProcessName
                                                     useMigFilterBypass:NO
                                                firstExceptionTimeoutMS:TYPEBANNER_RC_MOBILESMS_FIRST_EXCEPTION_TIMEOUT_MS];
            *mobileSessionRef = mobileSession;
        }
    }
    if (!kTypeBannerDaemonOnlyDetection && mobileSession) {
        tb_note_mobilesms_init_ok();
        mobileSMSRunning = true;
        mobilePidForKeepAlive = (uint32_t)mobileSession.pid;
        @try {
            currentName = typebanner_poll_in_mobilesms_remote_session(mobileSession);
        } @catch (NSException *e) {
            printf("[TYPEBANNER] MobileSMS poll exception: %s\n", e.reason.UTF8String);
            gTypeBannerPollRemoteHealthy = false;
        }
        if (!gTypeBannerPollRemoteHealthy) {
            uint32_t unhealthyPid = (uint32_t)mobileSession.pid;
            printf("[TYPEBANNER] MobileSMS RemoteCall session unhealthy; abandoning cached session\n");
            [mobileSession abandonRemoteCall];
            *mobileSessionRef = nil;
            mobileSMSRunning = false;
            tb_defer_mobilesms_bootstrap(unhealthyPid, "cached session stopped replying");
        }
    } else if (!kTypeBannerDaemonOnlyDetection) {
        if (mobilePidForKeepAlive == 0) {
            tb_log_mobilesms_unavailable();
            mobilePidForKeepAlive = remote_call_last_init_failure_pid();
        }
    }
    if (!kTypeBannerDaemonOnlyDetection) {
        gTypeBannerMobileUnreachableLastTick = !mobileSMSRunning;
    }

    if (!kTypeBannerDaemonOnlyDetection && !mobileSMSRunning) {
        NSString *daemonName = tb_try_imagent_original_thread_only_poll(daemonSessionRef);
        if (daemonName != nil) {
            currentName = daemonName;
        }
    }

    // Phase 2: update SpringBoard banner if state changed. nil currentName
    // means "no typing → hide"; any non-nil value (including @"") means
    // "show banner" — empty string flows through show() as the unnamed
    // "Someone is typing…" fallback.
    BOOL hadBanner = (gTypeBannerLastName != nil);
    BOOL hasBanner = (currentName != nil);
    BOOL stateChanged = (hadBanner != hasBanner);
    if (!stateChanged && hasBanner &&
        ![currentName isEqualToString:gTypeBannerLastName ?: @""]) {
        stateChanged = YES;
    }

    if (!stateChanged && !hasBanner && !mobileSMSRunning && hadBanner) {
        // Detection host reported no active typing -> drop banner.
        stateChanged = YES;
        currentName = nil;
    }

    bool needKeepAlive = (kTypeBannerSpringBoardRBSKeepAliveEnabled &&
                          mobilePidForKeepAlive != 0 &&
                          (gTypeBannerMobileKeepAlivePid != mobilePidForKeepAlive ||
                           !mobileSMSRunning));
    if (!stateChanged && !needKeepAlive) return true;

    bool ok = true;
    @try {
        if (currentSpringBoardReady) {
            if (needKeepAlive) {
                typebanner_ensure_mobilesms_keepalive_in_springboard_session(mobilePidForKeepAlive);
            }
            if (stateChanged) {
                if (currentName != nil) {
                    ok = typebanner_show_in_springboard_session(currentName);
                } else {
                    ok = typebanner_hide_in_springboard_session();
                }
            }
        } else {
            RemoteCallSession *springboardSession = [[RemoteCallSession alloc] initWithProcess:@"SpringBoard"
                                                                             useMigFilterBypass:NO
                                                                        firstExceptionTimeoutMS:TYPEBANNER_RC_FIRST_EXCEPTION_TIMEOUT_MS];
            if (!springboardSession) {
                printf("[TYPEBANNER] SpringBoard not reachable\n");
                ok = !stateChanged;
            } else {
                @try {
                    if (needKeepAlive) {
                        typebanner_ensure_mobilesms_keepalive_in_springboard_remote_session(springboardSession,
                                                                                            mobilePidForKeepAlive);
                    }
                    if (stateChanged) {
                        if (currentName != nil) {
                            ok = typebanner_show_in_springboard_remote_session(springboardSession, currentName);
                        } else {
                            ok = typebanner_hide_in_springboard_remote_session(springboardSession);
                        }
                    }
                } @finally {
                    [springboardSession destroyRemoteCall];
                }
            }
        }
    } @catch (NSException *e) {
        printf("[TYPEBANNER] SpringBoard update exception: %s\n", e.reason.UTF8String);
        ok = !stateChanged;
    }

    if (stateChanged && ok) {
        gTypeBannerLastName = currentName ? [currentName copy] : nil;
    }
    return ok;
}

bool typebanner_run_once_with_mobile_session(RemoteCallSession **mobileSessionRef)
{
    return typebanner_run_once_with_mobile_session_and_current_springboard(mobileSessionRef, false);
}

bool typebanner_run_once(void)
{
    RemoteCallSession *mobileSession = nil;
    bool ok = typebanner_run_once_with_mobile_session(&mobileSession);
    if (mobileSession) {
        [mobileSession destroyRemoteCall];
    }
    return ok;
}
