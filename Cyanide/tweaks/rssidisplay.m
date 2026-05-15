//
//  rssidisplay.m
//
//  Cover the SpringBoard status-bar signal icons with live dBm readouts.
//
//  Approach: STUIStatusBarWifiSignalView / STUIStatusBarCellularSignalView
//  render their bars as CALayer sublayers on the view's own layer (verified
//  in StatusKitUI's -layoutSubviews on iOS 18). So for each instance we:
//    1. Add a tagged UILabel as a subview of the signal view itself,
//       sized to its bounds. The label's CALayer ends up as the last
//       sublayer, so it renders on top of every bar layer.
//    2. setHidden:1 on every other sublayer (the bars) so the icon goes
//       blank, leaving only our label visible.
//
//  This avoids the cross-scene/cross-window coordinate problems of putting
//  the readout in a separate UIWindow: the label lives inside the signal
//  view's own hierarchy, so positioning is automatic and z-order is local.
//

#import "rssidisplay.h"
#import "remote_objc.h"
#import "../TaskRop/RemoteCall.h"
#import "../LogTextView.h"

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>
#import <math.h>
#import <stdio.h>
#import <string.h>
#import <unistd.h>

typedef struct {
    double x;
    double y;
    double width;
    double height;
} RDGRect64;

typedef struct {
    uint64_t signalView;
    uint64_t label;
    double lastWidth;
    double lastHeight;
    bool configured;
} RSSIInstance;

static const uint64_t kRSSIWifiLabelTag = 99422;
static const uint64_t kRSSICellLabelTag = 99423;
static const double   kRSSIFontPt = 9.0;
static const double   kRSSIHorizontalPad = 6.0;  // widen label past icon so 3 digits fit

#define kRSSIMaxInstances 8
static RSSIInstance gRSSIWifi[kRSSIMaxInstances];
static int          gRSSIWifiCount = 0;
static RSSIInstance gRSSICell[kRSSIMaxInstances];
static int          gRSSICellCount = 0;

static uint64_t gRSSIApplyTick = 0;

// Cached classes / sels.
static uint64_t gClsSTUIWifi = 0;
static uint64_t gClsSTUICell = 0;
static uint64_t gClsUILabel = 0;
static uint64_t gClsUIApplication = 0;
static uint64_t gClsUIWindowScene = 0;
static uint64_t gClsUIColor = 0;
static uint64_t gClsUIFont = 0;
static uint64_t gClsNSString = 0;
static uint64_t gSelIsKindOfClass = 0;
static uint64_t gSelSubviews = 0;
static uint64_t gSelCount = 0;
static uint64_t gSelObjectAtIndex = 0;
static uint64_t gSelSetText = 0;
static uint64_t gSelPerformMain = 0;
static uint64_t gSelAlloc = 0;
static uint64_t gSelInitUTF8 = 0;
static uint64_t gSelNumberOfActiveBars = 0;

static uint64_t gClsSBWiFiManager = 0;
static uint64_t gSBWiFiManager = 0;
static uint64_t gClsSBTelephonyManager = 0;
static uint64_t gSBTelephonyMgr = 0;
static uint64_t gCoreTelephonyClient = 0;
static int gWifiRssiFallback = 0;
static int gCellRsrpFallback = 0;

static bool rssidisplay_first_tick(void) { return gRSSIApplyTick == 1; }

static bool rssidisplay_ensure_classes(void)
{
    if (!gClsSTUIWifi) gClsSTUIWifi = r_class("STUIStatusBarWifiSignalView");
    if (!gClsSTUICell) gClsSTUICell = r_class("STUIStatusBarCellularSignalView");
    if (!gClsUILabel)  gClsUILabel = r_class("UILabel");
    if (!gClsUIApplication) gClsUIApplication = r_class("UIApplication");
    if (!gClsUIWindowScene) gClsUIWindowScene = r_class("UIWindowScene");
    if (!gClsUIColor) gClsUIColor = r_class("UIColor");
    if (!gClsUIFont)  gClsUIFont = r_class("UIFont");
    if (!gClsNSString) gClsNSString = r_class("NSString");

    if (!gSelIsKindOfClass) gSelIsKindOfClass = r_sel("isKindOfClass:");
    if (!gSelSubviews)      gSelSubviews = r_sel("subviews");
    if (!gSelCount)         gSelCount = r_sel("count");
    if (!gSelObjectAtIndex) gSelObjectAtIndex = r_sel("objectAtIndex:");
    if (!gSelSetText)       gSelSetText = r_sel("setText:");
    if (!gSelPerformMain)   gSelPerformMain = r_sel("performSelectorOnMainThread:withObject:waitUntilDone:");
    if (!gSelAlloc)         gSelAlloc = r_sel("alloc");
    if (!gSelInitUTF8)      gSelInitUTF8 = r_sel("initWithUTF8String:");
    if (!gSelNumberOfActiveBars) gSelNumberOfActiveBars = r_sel("numberOfActiveBars");

    return r_is_objc_ptr(gClsUILabel) && r_is_objc_ptr(gClsUIApplication);
}

static int rssidisplay_read_bars(uint64_t signalView)
{
    if (!r_is_objc_ptr(signalView) || !gSelNumberOfActiveBars) return -1;
    int64_t bars = (int64_t)r_msg(signalView, gSelNumberOfActiveBars, 0, 0, 0, 0);
    if (bars < 0 || bars > 9) return -1;
    return (int)bars;
}

// WiFi RSSI in dBm via SpringBoard's own SBWiFiManager singleton.
static int rssidisplay_read_wifi_rssi_dbm(void)
{
    if (gWifiRssiFallback) return 0;

    if (!r_is_objc_ptr(gClsSBWiFiManager)) {
        gClsSBWiFiManager = r_class("SBWiFiManager");
        if (!r_is_objc_ptr(gClsSBWiFiManager)) {
            printf("[RSSI] SBWiFiManager class not found; falling back to bars\n");
            gWifiRssiFallback = 1;
            return 0;
        }
    }
    if (!r_is_objc_ptr(gSBWiFiManager)) {
        gSBWiFiManager = r_msg2(gClsSBWiFiManager, "sharedInstance", 0, 0, 0, 0);
        if (!r_is_objc_ptr(gSBWiFiManager)) {
            printf("[RSSI] SBWiFiManager sharedInstance nil; falling back to bars\n");
            gWifiRssiFallback = 1;
            return 0;
        }
    }
    if (!r_responds(gSBWiFiManager, "signalStrengthRSSI")) {
        printf("[RSSI] SBWiFiManager missing signalStrengthRSSI; falling back\n");
        gWifiRssiFallback = 1;
        return 0;
    }
    // signalStrengthRSSI returns int (32-bit). AAPCS64 leaves upper 32 bits
    // of x0 undefined for sub-register returns, so a real -50 dBm can read as
    // 0xFFFFFFCE and fail our range check unless we mask + sign-extend.
    int32_t rssi = (int32_t)(r_msg2(gSBWiFiManager, "signalStrengthRSSI", 0, 0, 0, 0) & 0xFFFFFFFFu);
    if (rssi >= 0 || rssi < -120) return 0;
    return (int)rssi;
}

// Cellular RSRP in dBm via SBTelephonyManager's existing CoreTelephonyClient.
static int rssidisplay_read_cell_rsrp_dbm(void)
{
    if (gCellRsrpFallback) return 0;

    if (!r_is_objc_ptr(gClsSBTelephonyManager)) {
        gClsSBTelephonyManager = r_class("SBTelephonyManager");
        if (!r_is_objc_ptr(gClsSBTelephonyManager)) {
            printf("[RSSI] SBTelephonyManager class not found; falling back to bars\n");
            gCellRsrpFallback = 1;
            return 0;
        }
    }
    if (!r_is_objc_ptr(gSBTelephonyMgr)) {
        gSBTelephonyMgr = r_msg2(gClsSBTelephonyManager, "sharedTelephonyManager", 0, 0, 0, 0);
        if (!r_is_objc_ptr(gSBTelephonyMgr)) {
            printf("[RSSI] sharedTelephonyManager nil; falling back to bars\n");
            gCellRsrpFallback = 1;
            return 0;
        }
    }
    if (!r_is_objc_ptr(gCoreTelephonyClient)) {
        gCoreTelephonyClient = r_msg2(gSBTelephonyMgr, "coreTelephonyClient", 0, 0, 0, 0);
        if (!r_is_objc_ptr(gCoreTelephonyClient)) {
            printf("[RSSI] coreTelephonyClient nil; falling back to bars\n");
            gCellRsrpFallback = 1;
            return 0;
        }
    }
    if (!r_responds(gCoreTelephonyClient, "getSignalStrengthMeasurements:error:")) {
        printf("[RSSI] CT client missing getSignalStrengthMeasurements; falling back\n");
        gCellRsrpFallback = 1;
        return 0;
    }
    uint64_t measurements = r_msg2(gCoreTelephonyClient,
                                   "getSignalStrengthMeasurements:error:",
                                   0, 0, 0, 0);
    if (!r_is_objc_ptr(measurements)) return 0;

    uint64_t rsrp = r_msg2(measurements, "rsrp", 0, 0, 0, 0);
    if (!r_is_objc_ptr(rsrp)) return 0;
    int64_t dbm = (int64_t)r_msg2(rsrp, "integerValue", 0, 0, 0, 0);
    if (dbm >= 0 || dbm < -160) return 0;
    return (int)dbm;
}

// === Discovery ============================================================

#define kRSSIMaxFound 16
static uint64_t gFoundWifi[kRSSIMaxFound];
static int      gFoundWifiCount = 0;
static uint64_t gFoundCell[kRSSIMaxFound];
static int      gFoundCellCount = 0;

static void rssidisplay_record_found(uint64_t *list, int *count, uint64_t view)
{
    if (!list || !count || !r_is_objc_ptr(view)) return;
    for (int i = 0; i < *count; i++) {
        if (list[i] == view) return;
    }
    if (*count >= kRSSIMaxFound) return;
    list[*count] = view;
    (*count)++;
}

static void rssidisplay_walk(uint64_t view, int depth)
{
    if (!r_is_objc_ptr(view) || depth > 12) return;

    if (r_is_objc_ptr(gClsSTUIWifi) &&
        (r_msg(view, gSelIsKindOfClass, gClsSTUIWifi, 0, 0, 0) & 0xff) != 0) {
        rssidisplay_record_found(gFoundWifi, &gFoundWifiCount, view);
    }
    if (r_is_objc_ptr(gClsSTUICell) &&
        (r_msg(view, gSelIsKindOfClass, gClsSTUICell, 0, 0, 0) & 0xff) != 0) {
        rssidisplay_record_found(gFoundCell, &gFoundCellCount, view);
    }

    uint64_t subs = r_msg(view, gSelSubviews, 0, 0, 0, 0);
    if (!r_is_objc_ptr(subs)) return;
    uint64_t cnt = r_msg(subs, gSelCount, 0, 0, 0, 0);
    if (cnt == 0 || cnt > 128) return;
    for (uint64_t i = 0; i < cnt; i++) {
        uint64_t sub = r_msg(subs, gSelObjectAtIndex, i, 0, 0, 0);
        rssidisplay_walk(sub, depth + 1);
    }
}

// Walk every window in every connected UIWindowScene. iOS 16+ deprecated
// -[UIApplication windows] to "windows of the active foreground scene", so a
// pure [app windows] walk misses the lock-screen status bar, the
// per-app status-bar host, etc. SpringBoard runs many scenes simultaneously.
static void rssidisplay_discover(void)
{
    gFoundWifiCount = 0;
    gFoundCellCount = 0;
    if (!rssidisplay_ensure_classes()) return;

    uint64_t app = r_msg2_main(gClsUIApplication, "sharedApplication", 0, 0, 0, 0);
    if (!r_is_objc_ptr(app)) return;

    // Path A: connectedScenes — catches every UIWindowScene the process owns.
    uint64_t scenes = r_msg2_main(app, "connectedScenes", 0, 0, 0, 0);
    if (r_is_objc_ptr(scenes)) {
        uint64_t allScenes = r_msg2_main(scenes, "allObjects", 0, 0, 0, 0);
        if (r_is_objc_ptr(allScenes)) {
            uint64_t scnt = r_msg(allScenes, gSelCount, 0, 0, 0, 0);
            if (scnt > 0 && scnt < 64) {
                for (uint64_t i = 0; i < scnt; i++) {
                    uint64_t scene = r_msg(allScenes, gSelObjectAtIndex, i, 0, 0, 0);
                    if (!r_is_objc_ptr(scene)) continue;
                    if (r_is_objc_ptr(gClsUIWindowScene) &&
                        (r_msg(scene, gSelIsKindOfClass, gClsUIWindowScene, 0, 0, 0) & 0xff) == 0) {
                        continue;
                    }
                    uint64_t sceneWins = r_msg2_main(scene, "windows", 0, 0, 0, 0);
                    if (!r_is_objc_ptr(sceneWins)) continue;
                    uint64_t wcnt = r_msg(sceneWins, gSelCount, 0, 0, 0, 0);
                    if (wcnt == 0 || wcnt > 64) continue;
                    for (uint64_t j = 0; j < wcnt; j++) {
                        uint64_t win = r_msg(sceneWins, gSelObjectAtIndex, j, 0, 0, 0);
                        rssidisplay_walk(win, 0);
                    }
                }
            }
        }
    }

    // Path B: legacy [app windows] — belt + braces, in case the platform
    // exposes status-bar windows here but not via connectedScenes.
    uint64_t windows = r_msg2_main(app, "windows", 0, 0, 0, 0);
    if (r_is_objc_ptr(windows)) {
        uint64_t cnt = r_msg(windows, gSelCount, 0, 0, 0, 0);
        if (cnt > 0 && cnt < 64) {
            for (uint64_t i = 0; i < cnt; i++) {
                uint64_t win = r_msg(windows, gSelObjectAtIndex, i, 0, 0, 0);
                rssidisplay_walk(win, 0);
            }
        }
    }

    if (rssidisplay_first_tick()) {
        printf("[RSSI] discovered wifi=%d cell=%d signal views\n",
               gFoundWifiCount, gFoundCellCount);
    }
}

// === Text helpers =========================================================

static uint64_t rssidisplay_nsstring(const char *cstr)
{
    if (!cstr) cstr = "--";
    if (!r_is_objc_ptr(gClsNSString)) {
        gClsNSString = r_class("NSString");
        if (!r_is_objc_ptr(gClsNSString)) return 0;
    }
    uint64_t buf = r_alloc_str(cstr);
    if (!buf) return 0;
    uint64_t allocated = r_msg(gClsNSString, gSelAlloc, 0, 0, 0, 0);
    uint64_t ns = r_is_objc_ptr(allocated) ? r_msg(allocated, gSelInitUTF8, buf, 0, 0, 0) : 0;
    r_free(buf);
    return ns;
}

static void rssidisplay_set_label_text(uint64_t label, const char *cstr)
{
    if (!r_is_objc_ptr(label)) return;
    uint64_t textObj = rssidisplay_nsstring(cstr);
    if (!r_is_objc_ptr(textObj)) return;
    r_msg(label, gSelPerformMain, gSelSetText, textObj, 1, 0);
    r_dlsym_call(R_TIMEOUT, "CFRelease", textObj, 0, 0, 0, 0, 0, 0, 0);
}

static bool r_send_double_main_rd(uint64_t obj, const char *selName, double value)
{
    if (!r_is_objc_ptr(obj)) return false;
    r_msg2_main_raw(obj, selName, &value, sizeof(value),
                    NULL, 0, NULL, 0, NULL, 0);
    return true;
}

static bool r_send_rect_main_rd(uint64_t obj, const char *selName, RDGRect64 rect)
{
    if (!r_is_objc_ptr(obj)) return false;
    r_msg2_main_raw(obj, selName, &rect, sizeof(rect),
                    NULL, 0, NULL, 0, NULL, 0);
    return true;
}

static uint64_t rssidisplay_make_font(void)
{
    if (!r_is_objc_ptr(gClsUIFont)) gClsUIFont = r_class("UIFont");
    if (!r_is_objc_ptr(gClsUIFont)) return 0;

    // UIFontWeightSemibold (~0.3) matches the iOS status bar weight.
    double size = kRSSIFontPt;
    double weight = 0.3;
    uint64_t font = r_msg2_main_raw(gClsUIFont, "monospacedDigitSystemFontOfSize:weight:",
                                    &size, sizeof(size),
                                    &weight, sizeof(weight),
                                    NULL, 0, NULL, 0);
    if (r_is_objc_ptr(font)) return font;
    return r_msg2_main_raw(gClsUIFont, "systemFontOfSize:",
                           &size, sizeof(size),
                           NULL, 0, NULL, 0, NULL, 0);
}

// === Per-instance overlay management ======================================

static RSSIInstance *rssidisplay_find_or_create_instance(RSSIInstance *list, int *count,
                                                          uint64_t signalView)
{
    for (int i = 0; i < *count; i++) {
        if (list[i].signalView == signalView) return &list[i];
    }
    if (*count >= kRSSIMaxInstances) return NULL;
    RSSIInstance *inst = &list[(*count)++];
    memset(inst, 0, sizeof(*inst));
    inst->signalView = signalView;
    return inst;
}

// Hide every CALayer sublayer of the signal view EXCEPT the one belonging
// to our overlay label. The bars are CALayers on the view's own layer —
// hiding them blanks the icon while leaving our label visible.
static void rssidisplay_hide_bar_sublayers(uint64_t signalView, uint64_t labelLayer)
{
    if (!r_is_objc_ptr(signalView)) return;
    uint64_t hostLayer = r_msg2_main(signalView, "layer", 0, 0, 0, 0);
    if (!r_is_objc_ptr(hostLayer)) return;
    uint64_t sublayers = r_msg2_main(hostLayer, "sublayers", 0, 0, 0, 0);
    if (!r_is_objc_ptr(sublayers)) return;
    uint64_t cnt = r_msg(sublayers, gSelCount, 0, 0, 0, 0);
    if (cnt == 0 || cnt > 64) return;

    for (uint64_t i = 0; i < cnt; i++) {
        uint64_t layer = r_msg(sublayers, gSelObjectAtIndex, i, 0, 0, 0);
        if (!r_is_objc_ptr(layer)) continue;
        if (labelLayer && layer == labelLayer) continue;
        r_msg2_main(layer, "setHidden:", 1, 0, 0, 0);
    }
}

static void rssidisplay_unhide_bar_sublayers(uint64_t signalView)
{
    if (!r_is_objc_ptr(signalView)) return;
    uint64_t hostLayer = r_msg2_main(signalView, "layer", 0, 0, 0, 0);
    if (!r_is_objc_ptr(hostLayer)) return;
    uint64_t sublayers = r_msg2_main(hostLayer, "sublayers", 0, 0, 0, 0);
    if (!r_is_objc_ptr(sublayers)) return;
    uint64_t cnt = r_msg(sublayers, gSelCount, 0, 0, 0, 0);
    if (cnt == 0 || cnt > 64) return;
    for (uint64_t i = 0; i < cnt; i++) {
        uint64_t layer = r_msg(sublayers, gSelObjectAtIndex, i, 0, 0, 0);
        if (!r_is_objc_ptr(layer)) continue;
        r_msg2_main(layer, "setHidden:", 0, 0, 0, 0);
    }
}

// Install/refresh one overlay label as a subview of the signal view itself.
// Geometry: label spans the icon plus a small horizontal pad on each side so
// three-digit dBm magnitudes fit. The signal view's own clipsToBounds is set
// to NO so the wider label doesn't get clipped at the icon's natural edges.
static bool rssidisplay_apply_one(RSSIInstance *inst, uint64_t signalView,
                                  uint64_t tag, const char *text)
{
    if (!inst || !r_is_objc_ptr(signalView)) return false;

    RDGRect64 bounds = {0};
    if (!r_msg2_main_struct_ret(signalView, "bounds",
                                &bounds, sizeof(bounds),
                                NULL, 0, NULL, 0, NULL, 0, NULL, 0)) {
        if (rssidisplay_first_tick())
            printf("[RSSI] tag=%llu: bounds read failed\n", tag);
        return false;
    }
    if (!isfinite(bounds.width) || !isfinite(bounds.height) ||
        bounds.width <= 0 || bounds.height <= 0) {
        if (rssidisplay_first_tick())
            printf("[RSSI] tag=%llu: bad bounds %.1fx%.1f\n",
                   tag, bounds.width, bounds.height);
        return false;
    }

    r_msg2_main(signalView, "setClipsToBounds:", 0, 0, 0, 0);

    // Try to find an existing label we previously added (across respawns this
    // works even when our in-process pointer is stale, because the label
    // persists as a tagged subview of the signal view).
    uint64_t label = inst->label;
    if (!r_is_objc_ptr(label)) {
        label = r_msg2_main(signalView, "viewWithTag:", tag, 0, 0, 0);
    }

    RDGRect64 frame = {
        -kRSSIHorizontalPad,
        0,
        bounds.width + (kRSSIHorizontalPad * 2.0),
        bounds.height
    };

    if (!r_is_objc_ptr(label)) {
        uint64_t alloc = r_msg2_main(gClsUILabel, "alloc", 0, 0, 0, 0);
        label = r_is_objc_ptr(alloc) ?
                r_msg2_main(alloc, "init", 0, 0, 0, 0) : 0;
        if (!r_is_objc_ptr(label)) {
            printf("[RSSI] tag=%llu: UILabel init failed\n", tag);
            return false;
        }

        r_msg2_main(label, "setTag:", tag, 0, 0, 0);
        r_msg2_main(label, "setTextAlignment:", 1 /* NSTextAlignmentCenter */, 0, 0, 0);
        r_msg2_main(label, "setNumberOfLines:", 1, 0, 0, 0);
        r_msg2_main(label, "setAdjustsFontSizeToFitWidth:", 1, 0, 0, 0);
        r_send_double_main_rd(label, "setMinimumScaleFactor:", 0.55);
        r_msg2_main(label, "setUserInteractionEnabled:", 0, 0, 0, 0);
        r_msg2_main(label, "setClipsToBounds:", 0, 0, 0, 0);

        uint64_t font = rssidisplay_make_font();
        if (r_is_objc_ptr(font)) r_msg2_main(label, "setFont:", font, 0, 0, 0);

        if (r_is_objc_ptr(gClsUIColor)) {
            uint64_t clear = r_msg2_main(gClsUIColor, "clearColor", 0, 0, 0, 0);
            uint64_t white = r_msg2_main(gClsUIColor, "whiteColor", 0, 0, 0, 0);
            if (r_is_objc_ptr(clear)) r_msg2_main(label, "setBackgroundColor:", clear, 0, 0, 0);
            if (r_is_objc_ptr(white)) r_msg2_main(label, "setTextColor:", white, 0, 0, 0);
        }

        r_send_rect_main_rd(label, "setFrame:", frame);
        r_msg2_main(signalView, "addSubview:", label, 0, 0, 0);
        inst->lastWidth = bounds.width;
        inst->lastHeight = bounds.height;
        inst->configured = true;

        if (rssidisplay_first_tick())
            printf("[RSSI] tag=%llu: installed label=0x%llx on signal=0x%llx (icon %.1fx%.1f)\n",
                   tag, label, signalView, bounds.width, bounds.height);
    } else {
        bool sizeChanged = !inst->configured ||
            fabs(inst->lastWidth - bounds.width) > 0.5 ||
            fabs(inst->lastHeight - bounds.height) > 0.5;
        if (sizeChanged) {
            r_send_rect_main_rd(label, "setFrame:", frame);
            inst->lastWidth = bounds.width;
            inst->lastHeight = bounds.height;
            inst->configured = true;
        }
        // Make sure the label is on top of every bar layer (later additions
        // by the status bar's own layoutSubviews could shuffle order).
        r_msg2_main(signalView, "bringSubviewToFront:", label, 0, 0, 0);
    }

    inst->signalView = signalView;
    inst->label = label;

    uint64_t labelLayer = r_msg2_main(label, "layer", 0, 0, 0, 0);
    rssidisplay_hide_bar_sublayers(signalView, labelLayer);

    rssidisplay_set_label_text(label, text);
    return true;
}

// Remove our label and unhide everything we touched on a single instance.
static void rssidisplay_clear_one(RSSIInstance *inst)
{
    if (!inst) return;
    if (r_is_objc_ptr(inst->label)) {
        r_msg2_main(inst->label, "removeFromSuperview", 0, 0, 0, 0);
    }
    if (r_is_objc_ptr(inst->signalView)) {
        rssidisplay_unhide_bar_sublayers(inst->signalView);
    }
    inst->signalView = 0;
    inst->label = 0;
    inst->lastWidth = 0;
    inst->lastHeight = 0;
    inst->configured = false;
}

// Drop tracked instances whose signal view didn't show up in this tick's
// discovery. Those views may have been deallocated or replaced; their labels
// are gone with them.
static void rssidisplay_compact(RSSIInstance *list, int *count,
                                const uint64_t *seen, int seenCount)
{
    int write = 0;
    for (int i = 0; i < *count; i++) {
        bool keep = false;
        for (int j = 0; j < seenCount; j++) {
            if (seen[j] == list[i].signalView) { keep = true; break; }
        }
        if (keep) {
            if (write != i) list[write] = list[i];
            write++;
        }
    }
    *count = write;
}

// === Formatting ===========================================================

static void rssidisplay_format_bars(int bars, char *out, size_t outSize)
{
    if (!out || outSize == 0) return;
    if (bars < 0) snprintf(out, outSize, "--");
    else          snprintf(out, outSize, "%d", bars);
}

// dBm is always negative on a real signal — show magnitude only so 2-3 chars
// fit in the narrow icon slot: -67 -> "67", -115 -> "115".
static void rssidisplay_format_dbm(int dbm, char *out, size_t outSize)
{
    if (!out || outSize == 0) return;
    if (dbm == 0) {
        snprintf(out, outSize, "--");
    } else {
        int mag = dbm < 0 ? -dbm : dbm;
        if (mag > 999) mag = 999;
        snprintf(out, outSize, "%d", mag);
    }
}

// === Public entry points ==================================================

bool rssidisplay_apply_in_session(bool showWifi, bool showCell)
{
    gRSSIApplyTick++;
    if (rssidisplay_first_tick()) {
        printf("[RSSI] === apply tick=1 showWifi=%d showCell=%d ===\n",
               (int)showWifi, (int)showCell);
    }

    if (!rssidisplay_ensure_classes()) {
        printf("[RSSI] classes not ready (tick=%llu)\n", gRSSIApplyTick);
        return false;
    }

    rssidisplay_discover();

    bool any = false;

    if (showWifi) {
        char text[8];
        int dbm = rssidisplay_read_wifi_rssi_dbm();
        if (rssidisplay_first_tick())
            printf("[RSSI] wifi dbm=%d instances=%d\n", dbm, gFoundWifiCount);
        for (int i = 0; i < gFoundWifiCount; i++) {
            uint64_t view = gFoundWifi[i];
            int displayDbm = dbm;
            if (displayDbm < 0) {
                rssidisplay_format_dbm(displayDbm, text, sizeof(text));
            } else {
                int bars = rssidisplay_read_bars(view);
                rssidisplay_format_bars(bars, text, sizeof(text));
            }
            RSSIInstance *inst = rssidisplay_find_or_create_instance(
                gRSSIWifi, &gRSSIWifiCount, view);
            if (inst && rssidisplay_apply_one(inst, view, kRSSIWifiLabelTag, text)) {
                any = true;
            }
        }
        rssidisplay_compact(gRSSIWifi, &gRSSIWifiCount, gFoundWifi, gFoundWifiCount);
    } else {
        for (int i = 0; i < gRSSIWifiCount; i++) rssidisplay_clear_one(&gRSSIWifi[i]);
        gRSSIWifiCount = 0;
    }

    if (showCell) {
        char text[8];
        int dbm = rssidisplay_read_cell_rsrp_dbm();
        if (rssidisplay_first_tick())
            printf("[RSSI] cell dbm=%d instances=%d\n", dbm, gFoundCellCount);
        for (int i = 0; i < gFoundCellCount; i++) {
            uint64_t view = gFoundCell[i];
            int bars = rssidisplay_read_bars(view);
            // bars==0 with no dBm means "no service / SOS" — let Apple's
            // native indicator render uncovered so the user sees the state.
            if (dbm == 0 && bars <= 0) {
                for (int k = 0; k < gRSSICellCount; k++) {
                    if (gRSSICell[k].signalView == view) {
                        rssidisplay_clear_one(&gRSSICell[k]);
                        break;
                    }
                }
                continue;
            }
            if (dbm < 0) rssidisplay_format_dbm(dbm, text, sizeof(text));
            else         rssidisplay_format_bars(bars, text, sizeof(text));
            RSSIInstance *inst = rssidisplay_find_or_create_instance(
                gRSSICell, &gRSSICellCount, view);
            if (inst && rssidisplay_apply_one(inst, view, kRSSICellLabelTag, text)) {
                any = true;
            }
        }
        rssidisplay_compact(gRSSICell, &gRSSICellCount, gFoundCell, gFoundCellCount);
    } else {
        for (int i = 0; i < gRSSICellCount; i++) rssidisplay_clear_one(&gRSSICell[i]);
        gRSSICellCount = 0;
    }

    return any;
}

bool rssidisplay_stop_in_session(void)
{
    for (int i = 0; i < gRSSIWifiCount; i++) rssidisplay_clear_one(&gRSSIWifi[i]);
    gRSSIWifiCount = 0;
    for (int i = 0; i < gRSSICellCount; i++) rssidisplay_clear_one(&gRSSICell[i]);
    gRSSICellCount = 0;

    // The signal views found this tick may not match anything we still track,
    // so also unhide any leftover hidden bar sublayers on currently-visible
    // signal views — defensive cleanup against partial state from earlier
    // sessions.
    rssidisplay_discover();
    for (int i = 0; i < gFoundWifiCount; i++) rssidisplay_unhide_bar_sublayers(gFoundWifi[i]);
    for (int i = 0; i < gFoundCellCount; i++) rssidisplay_unhide_bar_sublayers(gFoundCell[i]);

    printf("[RSSI] stop_in_session\n");
    return true;
}

void rssidisplay_forget_remote_state(void)
{
    memset(gRSSIWifi, 0, sizeof(gRSSIWifi));
    gRSSIWifiCount = 0;
    memset(gRSSICell, 0, sizeof(gRSSICell));
    gRSSICellCount = 0;
    gFoundWifiCount = 0;
    gFoundCellCount = 0;
    gClsSTUIWifi = 0;
    gClsSTUICell = 0;
    gClsUILabel = 0;
    gClsUIApplication = 0;
    gClsUIWindowScene = 0;
    gClsUIColor = 0;
    gClsUIFont = 0;
    gClsNSString = 0;
    gSelIsKindOfClass = 0;
    gSelSubviews = 0;
    gSelCount = 0;
    gSelObjectAtIndex = 0;
    gSelSetText = 0;
    gSelPerformMain = 0;
    gSelAlloc = 0;
    gSelInitUTF8 = 0;
    gSelNumberOfActiveBars = 0;
    gClsSBWiFiManager = 0;
    gSBWiFiManager = 0;
    gClsSBTelephonyManager = 0;
    gSBTelephonyMgr = 0;
    gCoreTelephonyClient = 0;
    gWifiRssiFallback = 0;
    gCellRsrpFallback = 0;
    gRSSIApplyTick = 0;
    printf("[RSSI] forgot remote state\n");
}
