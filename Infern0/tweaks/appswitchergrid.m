//
//  appswitchergrid.m
//  Cyanide
//

#import "appswitchergrid.h"
#import "remote_objc.h"
#import "../TaskRop/RemoteCall.h"
#import "../LogTextView.h"
#import <stdio.h>
#import <string.h>

// Manually flip to true when collecting detailed App Switcher Grid logs.
static const bool kAppSwitcherGridDebugLogging = false;

#define ASG_DEBUG_LOG(fmt, ...) do { \
    if (kAppSwitcherGridDebugLogging) log_user(fmt, ##__VA_ARGS__); \
} while (0)

static uint64_t gASGSwitcherStyleMethod = 0;
static uint64_t gASGOriginalSwitcherStyleImp = 0;
static bool gASGApplied = false;

static uint64_t asg_instance_method(uint64_t cls, uint64_t sel)
{
    if (!r_is_objc_ptr(cls) || sel == 0) return 0;
    return r_dlsym_call(R_TIMEOUT, "class_getInstanceMethod",
                        cls, sel, 0, 0, 0, 0, 0, 0);
}

static bool asg_methods_have_matching_types(uint64_t first, uint64_t second)
{
    char firstType[64] = {0};
    char secondType[64] = {0};
    uint64_t firstPtr = r_dlsym_call(R_TIMEOUT, "method_getTypeEncoding",
                                     first, 0, 0, 0, 0, 0, 0, 0);
    uint64_t secondPtr = r_dlsym_call(R_TIMEOUT, "method_getTypeEncoding",
                                      second, 0, 0, 0, 0, 0, 0, 0);
    if (!firstPtr || !secondPtr ||
        !remote_read(firstPtr, firstType, sizeof(firstType) - 1) ||
        !remote_read(secondPtr, secondType, sizeof(secondType) - 1)) {
        return false;
    }
    return strcmp(firstType, secondType) == 0;
}

bool appswitchergrid_apply_in_session(void)
{
    uint64_t settingsCls = r_class("SBAppSwitcherSettings");
    uint64_t deckModifierCls = r_class("SBDeckSwitcherModifier");
    uint64_t switcherStyleSel = r_sel("switcherStyle");
    uint64_t dockUpdateModeSel = r_sel("dockUpdateMode");

    if (!r_is_objc_ptr(settingsCls) ||
        !r_is_objc_ptr(deckModifierCls) ||
        switcherStyleSel == 0 ||
        dockUpdateModeSel == 0) {
        printf("[ASG] missing classes/selectors settings=0x%llx deck=0x%llx switcherStyle=0x%llx dockUpdateMode=0x%llx\n",
               settingsCls, deckModifierCls, switcherStyleSel, dockUpdateModeSel);
        log_user("[ASG] Grid App Switcher is not available on this SpringBoard build.\n");
        return false;
    }

    uint64_t switcherStyleMethod = asg_instance_method(settingsCls, switcherStyleSel);
    uint64_t dockUpdateModeMethod = asg_instance_method(deckModifierCls, dockUpdateModeSel);
    if (!switcherStyleMethod || !dockUpdateModeMethod) {
        printf("[ASG] missing methods switcherStyle=0x%llx dockUpdateMode=0x%llx\n",
               switcherStyleMethod, dockUpdateModeMethod);
        log_user("[ASG] Grid App Switcher methods were not found.\n");
        return false;
    }

    // Reusing another method's IMP is only ABI-safe when both Objective-C
    // methods have exactly the same return/argument encoding.
    if (!asg_methods_have_matching_types(switcherStyleMethod, dockUpdateModeMethod)) {
        printf("[ASG] incompatible switcherStyle/dockUpdateMode signatures\n");
        log_user("[ASG] This iOS build uses incompatible App Switcher method signatures; no runtime method was changed.\n");
        return false;
    }

    uint64_t return2Imp = r_dlsym_call(R_TIMEOUT, "method_getImplementation",
                                       dockUpdateModeMethod, 0, 0, 0, 0, 0, 0, 0);
    if (!return2Imp) {
        printf("[ASG] dockUpdateMode IMP unavailable\n");
        log_user("[ASG] Could not resolve the grid switcher implementation.\n");
        return false;
    }

    if (!gASGOriginalSwitcherStyleImp || gASGSwitcherStyleMethod != switcherStyleMethod) {
        gASGOriginalSwitcherStyleImp = r_dlsym_call(R_TIMEOUT, "method_getImplementation",
                                                   switcherStyleMethod, 0, 0, 0, 0, 0, 0, 0);
        gASGSwitcherStyleMethod = switcherStyleMethod;
    }
    if (!gASGOriginalSwitcherStyleImp) {
        printf("[ASG] original switcherStyle IMP unavailable\n");
        log_user("[ASG] Could not save the original App Switcher style.\n");
        return false;
    }

    uint64_t oldImp = r_dlsym_call(R_TIMEOUT, "method_setImplementation",
                                   switcherStyleMethod, return2Imp, 0, 0, 0, 0, 0, 0);
    if (!oldImp) {
        printf("[ASG] method_setImplementation failed\n");
        log_user("[ASG] Failed to enable Grid App Switcher.\n");
        return false;
    }

    gASGApplied = true;
    printf("[ASG] switcherStyle method=0x%llx original=0x%llx grid=0x%llx old=0x%llx\n",
           switcherStyleMethod, gASGOriginalSwitcherStyleImp, return2Imp, oldImp);
    ASG_DEBUG_LOG("[ASG][DEBUG] switcherStyle method=0x%llx original=0x%llx grid=0x%llx old=0x%llx\n",
                  switcherStyleMethod, gASGOriginalSwitcherStyleImp, return2Imp, oldImp);
    log_user("[ASG] Grid App Switcher enabled. Respring restores stock.\n");
    return true;
}

bool appswitchergrid_stop_in_session(void)
{
    if (!gASGSwitcherStyleMethod || !gASGOriginalSwitcherStyleImp) {
        gASGApplied = false;
        return false;
    }

    uint64_t oldImp = r_dlsym_call(R_TIMEOUT, "method_setImplementation",
                                   gASGSwitcherStyleMethod,
                                   gASGOriginalSwitcherStyleImp,
                                   0, 0, 0, 0, 0, 0);
    bool ok = oldImp != 0;
    printf("[ASG] restore switcherStyle method=0x%llx original=0x%llx old=0x%llx ok=%d\n",
           gASGSwitcherStyleMethod, gASGOriginalSwitcherStyleImp, oldImp, ok);
    gASGApplied = false;
    if (ok) {
        log_user("[ASG] Stock App Switcher style restored for this SpringBoard session.\n");
    } else {
        log_user("[ASG] Restore did not complete; respring will restore stock App Switcher.\n");
    }
    return ok;
}

void appswitchergrid_forget_remote_state(void)
{
    gASGSwitcherStyleMethod = 0;
    gASGOriginalSwitcherStyleImp = 0;
    gASGApplied = false;
}
