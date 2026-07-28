//
//  debugoverlay.m
//  Cyanide
//

#import "debugoverlay.h"
#import "remote_objc.h"
#import "../LogTextView.h"
#import <stdio.h>

static const char *kDebugOriginalInitKey = "cyanideDebugOverlayOriginalInitIMP";
static const char *kDebugGestureKey = "cyanideDebugOverlayGesture";
static const char *kDebugStatusBarKey = "cyanideDebugOverlayStatusBar";
static bool gDebugOverlayApplied = false;

static uint64_t debug_instance_method(uint64_t cls, uint64_t sel)
{
    if (!r_is_objc_ptr(cls) || !sel) return 0;
    return r_dlsym_call(R_TIMEOUT, "class_getInstanceMethod",
                        cls, sel, 0, 0, 0, 0, 0, 0);
}

static uint64_t debug_method_imp(uint64_t method)
{
    return method
        ? r_dlsym_call(R_TIMEOUT, "method_getImplementation",
                       method, 0, 0, 0, 0, 0, 0, 0)
        : 0;
}

static uint64_t debug_associated(uint64_t object, uint64_t key)
{
    if (!r_is_objc_ptr(object) || !key) return 0;
    return r_dlsym_call(R_TIMEOUT, "objc_getAssociatedObject",
                        object, key, 0, 0, 0, 0, 0, 0);
}

static void debug_set_associated(uint64_t object, uint64_t key, uint64_t value)
{
    if (!r_is_objc_ptr(object) || !key) return;
    r_dlsym_call(R_TIMEOUT, "objc_setAssociatedObject",
                 object, key, value, 1 /* RETAIN_NONATOMIC */, 0, 0, 0, 0);
}

static uint64_t debug_boxed_u64(uint64_t value)
{
    uint64_t numberCls = r_class("NSNumber");
    return r_is_objc_ptr(numberCls)
        ? r_msg2(numberCls, "numberWithUnsignedLongLong:", value, 0, 0, 0)
        : 0;
}

static uint64_t debug_unbox_u64(uint64_t number)
{
    return r_is_objc_ptr(number)
        ? r_msg2(number, "unsignedLongLongValue", 0, 0, 0, 0)
        : 0;
}

bool debugoverlay_apply_in_session(void)
{
    uint64_t overlayCls = r_class("UIDebuggingInformationOverlay");
    uint64_t handlerCls = r_class("UIDebuggingInformationOverlayInvokeGestureHandler");
    uint64_t windowCls = r_class("UIWindow");
    uint64_t tapCls = r_class("UITapGestureRecognizer");
    uint64_t workspaceCls = r_class("SBMainWorkspace");
    uint64_t appCls = r_class("UIApplication");
    uint64_t initSel = r_sel("init");
    uint64_t handleSel = r_sel("_handleActivationGesture:");
    uint64_t originalKey = r_sel(kDebugOriginalInitKey);
    uint64_t gestureKey = r_sel(kDebugGestureKey);
    uint64_t statusBarKey = r_sel(kDebugStatusBarKey);

    if (!r_is_objc_ptr(overlayCls) || !r_is_objc_ptr(handlerCls) ||
        !r_is_objc_ptr(windowCls) || !r_is_objc_ptr(tapCls) ||
        !r_is_objc_ptr(workspaceCls) || !r_is_objc_ptr(appCls) ||
        !initSel || !handleSel || !originalKey || !gestureKey || !statusBarKey) {
        log_user("[DEBUG-OVERLAY] Required SpringBoard/UIKit classes are unavailable.\n");
        return false;
    }

    uint64_t overlayInit = debug_instance_method(overlayCls, initSel);
    uint64_t windowInit = debug_instance_method(windowCls, initSel);
    uint64_t windowInitImp = debug_method_imp(windowInit);
    uint64_t currentImp = debug_method_imp(overlayInit);
    uint64_t originalImp = debug_unbox_u64(debug_associated(overlayCls, originalKey));
    if (!overlayInit || !windowInitImp || !currentImp) {
        log_user("[DEBUG-OVERLAY] Could not resolve the overlay initialization methods.\n");
        return false;
    }

    bool createdOriginal = false;
    if (!originalImp) {
        if (currentImp == windowInitImp) {
            log_user("[DEBUG-OVERLAY] The overlay initializer is already patched. Respring before Cyanide takes ownership.\n");
            return false;
        }
        originalImp = currentImp;
        uint64_t originalBox = debug_boxed_u64(originalImp);
        if (!r_is_objc_ptr(originalBox)) return false;
        debug_set_associated(overlayCls, originalKey, originalBox);
        if (debug_unbox_u64(debug_associated(overlayCls, originalKey)) != originalImp) {
            log_user("[DEBUG-OVERLAY] Could not save the original overlay initializer.\n");
            return false;
        }
        createdOriginal = true;
    } else if (currentImp != originalImp && currentImp != windowInitImp) {
        log_user("[DEBUG-OVERLAY] The overlay initializer changed after Cyanide applied it. Respring and try again.\n");
        return false;
    }

    bool patchedThisApply = currentImp != windowInitImp;
    if (patchedThisApply) {
        uint64_t oldImp = r_dlsym_call(R_TIMEOUT, "method_setImplementation",
                                       overlayInit, windowInitImp, 0, 0, 0, 0, 0, 0);
        if (!oldImp) {
            if (createdOriginal) debug_set_associated(overlayCls, originalKey, 0);
            log_user("[DEBUG-OVERLAY] Failed to patch the overlay initializer.\n");
            return false;
        }
    }

    uint64_t workspace = r_msg2_main(workspaceCls, "sharedInstance", 0, 0, 0, 0);
    uint64_t scene = r_is_objc_ptr(workspace)
        ? r_msg2_main(workspace, "mainWindowScene", 0, 0, 0, 0)
        : 0;
    uint64_t overlay = r_msg2_main(overlayCls, "overlay", 0, 0, 0, 0);
    uint64_t handler = r_msg2_main(handlerCls, "mainHandler", 0, 0, 0, 0);
    uint64_t app = r_msg2_main(appCls, "sharedApplication", 0, 0, 0, 0);
    uint64_t statusBar = r_is_objc_ptr(app)
        ? r_msg2_main(app, "statusBarForEmbeddedDisplay", 0, 0, 0, 0)
        : 0;
    if (!r_is_objc_ptr(scene) || !r_is_objc_ptr(overlay) ||
        !r_is_objc_ptr(handler) || !r_is_objc_ptr(statusBar)) {
        if (createdOriginal && patchedThisApply) {
            r_dlsym_call(R_TIMEOUT, "method_setImplementation",
                         overlayInit, originalImp, 0, 0, 0, 0, 0, 0);
            debug_set_associated(overlayCls, originalKey, 0);
        }
        log_user("[DEBUG-OVERLAY] SpringBoard did not expose the overlay scene or status bar.\n");
        return false;
    }

    r_msg2_main(overlay, "setWindowScene:", scene, 0, 0, 0);
    uint64_t gesture = debug_associated(overlayCls, gestureKey);
    uint64_t savedStatusBar = debug_associated(overlayCls, statusBarKey);
    if (r_is_objc_ptr(gesture) && savedStatusBar != statusBar) {
        if (r_is_objc_ptr(savedStatusBar)) {
            r_msg2_main(savedStatusBar, "removeGestureRecognizer:", gesture, 0, 0, 0);
        }
        debug_set_associated(overlayCls, gestureKey, 0);
        debug_set_associated(overlayCls, statusBarKey, 0);
        gesture = 0;
    }

    if (!r_is_objc_ptr(gesture)) {
        uint64_t alloc = r_msg2_main(tapCls, "alloc", 0, 0, 0, 0);
        gesture = r_is_objc_ptr(alloc)
            ? r_msg2_main(alloc, "initWithTarget:action:", handler, handleSel, 0, 0)
            : 0;
        if (!r_is_objc_ptr(gesture)) {
            if (createdOriginal && patchedThisApply) {
                r_dlsym_call(R_TIMEOUT, "method_setImplementation",
                             overlayInit, originalImp, 0, 0, 0, 0, 0, 0);
                debug_set_associated(overlayCls, originalKey, 0);
            }
            log_user("[DEBUG-OVERLAY] Could not create the status-bar gesture.\n");
            return false;
        }
        r_msg2_main(gesture, "setNumberOfTapsRequired:", 2, 0, 0, 0);
        r_msg2_main(statusBar, "addGestureRecognizer:", gesture, 0, 0, 0);
        debug_set_associated(overlayCls, gestureKey, gesture);
        debug_set_associated(overlayCls, statusBarKey, statusBar);
        r_msg2_main(gesture, "release", 0, 0, 0, 0);
    }

    gDebugOverlayApplied = true;
    printf("[DEBUG-OVERLAY] enabled overlay=0x%llx statusBar=0x%llx gesture=0x%llx\n",
           overlay, statusBar, gesture);
    log_user("[DEBUG-OVERLAY] Enabled. Double-tap the status bar to open it.\n");
    return true;
}

bool debugoverlay_stop_in_session(void)
{
    bool found = false;
    bool ok = true;
    uint64_t overlayCls = r_class("UIDebuggingInformationOverlay");
    uint64_t originalKey = r_sel(kDebugOriginalInitKey);
    uint64_t gestureKey = r_sel(kDebugGestureKey);
    uint64_t statusBarKey = r_sel(kDebugStatusBarKey);
    uint64_t initSel = r_sel("init");

    uint64_t gesture = debug_associated(overlayCls, gestureKey);
    uint64_t statusBar = debug_associated(overlayCls, statusBarKey);
    if (r_is_objc_ptr(gesture)) {
        found = true;
        if (r_is_objc_ptr(statusBar)) {
            r_msg2_main(statusBar, "removeGestureRecognizer:", gesture, 0, 0, 0);
        }
        debug_set_associated(overlayCls, gestureKey, 0);
        debug_set_associated(overlayCls, statusBarKey, 0);
    }

    uint64_t overlayInit = debug_instance_method(overlayCls, initSel);
    uint64_t originalImp = debug_unbox_u64(debug_associated(overlayCls, originalKey));
    if (overlayInit && originalImp) {
        found = true;
        uint64_t currentImp = debug_method_imp(overlayInit);
        if (currentImp != originalImp) {
            uint64_t oldImp = r_dlsym_call(R_TIMEOUT, "method_setImplementation",
                                           overlayInit, originalImp,
                                           0, 0, 0, 0, 0, 0);
            ok = oldImp != 0;
        }
        if (ok) debug_set_associated(overlayCls, originalKey, 0);
    } else if (gDebugOverlayApplied) {
        ok = false;
    }

    if (!found && !gDebugOverlayApplied) return true;
    uint64_t overlay = r_is_objc_ptr(overlayCls)
        ? r_msg2_main(overlayCls, "overlay", 0, 0, 0, 0)
        : 0;
    if (r_is_objc_ptr(overlay)) {
        r_msg2_main(overlay, "setHidden:", 1, 0, 0, 0);
    }

    gDebugOverlayApplied = false;
    log_user(ok
        ? "[DEBUG-OVERLAY] Disabled for this SpringBoard session.\n"
        : "[DEBUG-OVERLAY] Cleanup was incomplete; respring restores stock.\n");
    return ok;
}

void debugoverlay_forget_remote_state(void)
{
    gDebugOverlayApplied = false;
}
