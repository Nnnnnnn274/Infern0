// Upside Down — session-only SpringBoard orientation port.
// Based on hxhlb/cyanide's lara/Banana implementation, with transactional
// preflight, per-target verification, rollback, and detailed infern0 logs.

#import "upsidedown.h"
#import "../remote_objc.h"
#import "../../LogTextView.h"

#import <stdio.h>

typedef struct {
    const char *className;
    const char *selectorName;
    const char *originalKeyName;
    int replacementIndex;
} UpsideDownTarget;

enum {
    UpsideDownReturn6 = 0,
    UpsideDownReturn1,
    UpsideDownReturn0x1E,
    UpsideDownReplacementCount,
    UpsideDownTargetCount = 5,
};

static const UpsideDownTarget kTargets[UpsideDownTargetCount] = {
    { "SBHomeScreenViewController", "supportedInterfaceOrientations", "infern0UpsideOriginalHomeIMP", UpsideDownReturn6 },
    { "SBCoverSheetPrimarySlidingViewController", "supportedInterfaceOrientations", "infern0UpsideOriginalLockIMP", UpsideDownReturn6 },
    { "SBTraitsSceneParticipantDelegate", "_isAllowedToHavePortraitUpsideDown", "infern0UpsideOriginalAllowedIMP", UpsideDownReturn1 },
    { "SBTraitsSceneParticipantDelegate", "_orientationMode", "infern0UpsideOriginalModeIMP", UpsideDownReturn0x1E },
    { "SBTraitsSceneParticipantDelegate", "_supportedOrientations", "infern0UpsideOriginalSupportedIMP", UpsideDownReturn0x1E },
};

static bool s_applied = false;
static unsigned long long s_apply_count = 0;
static unsigned long long s_restore_count = 0;

static uint64_t upside_method(uint64_t cls, const char *selector)
{
    uint64_t sel = r_sel(selector);
    return r_is_objc_ptr(cls) && sel
        ? r_dlsym_call(R_TIMEOUT, "class_getInstanceMethod", cls, sel, 0, 0, 0, 0, 0, 0)
        : 0;
}

static uint64_t upside_imp(uint64_t method)
{
    return method
        ? r_dlsym_call(R_TIMEOUT, "method_getImplementation", method, 0, 0, 0, 0, 0, 0, 0)
        : 0;
}

static uint64_t upside_associated(uint64_t object, uint64_t key)
{
    return r_is_objc_ptr(object) && key
        ? r_dlsym_call(R_TIMEOUT, "objc_getAssociatedObject", object, key, 0, 0, 0, 0, 0, 0)
        : 0;
}

static void upside_set_associated(uint64_t object, uint64_t key, uint64_t value)
{
    if (!r_is_objc_ptr(object) || !key) return;
    r_dlsym_call(R_TIMEOUT, "objc_setAssociatedObject",
                 object, key, value, 1, 0, 0, 0, 0);
}

static uint64_t upside_box(uint64_t value)
{
    uint64_t cls = r_class("NSNumber");
    return r_is_objc_ptr(cls)
        ? r_msg2(cls, "numberWithUnsignedLongLong:", value, 0, 0, 0)
        : 0;
}

static uint64_t upside_unbox(uint64_t number)
{
    return r_is_objc_ptr(number)
        ? r_msg2(number, "unsignedLongLongValue", 0, 0, 0, 0)
        : 0;
}

static bool upside_replacements(uint64_t out[UpsideDownReplacementCount])
{
    uint64_t return6 = upside_method(r_class("SBShelfExpansionSwitcherModifier"),
                                     "transactionCompletionOptions");
    uint64_t return1 = upside_method(r_class("SBCoverSheetPrimarySlidingViewController"),
                                     "_canShowWhileLocked");
    uint64_t return1E = upside_method(r_class("SBAlertItemRootViewController"),
                                      "supportedInterfaceOrientations");
    out[UpsideDownReturn6] = upside_imp(return6);
    out[UpsideDownReturn1] = upside_imp(return1);
    out[UpsideDownReturn0x1E] = upside_imp(return1E);
    bool ok = out[0] && out[1] && out[2] &&
              out[0] != out[1] && out[0] != out[2] && out[1] != out[2];
    log_user("[UPSIDE][PREFLIGHT] donors return6=%s return1=%s return0x1e=%s distinct=%d.\n",
             out[0] ? "found" : "missing", out[1] ? "found" : "missing",
             out[2] ? "found" : "missing", ok);
    return ok;
}

bool upsidedown_apply_in_session(void)
{
    log_user("[UPSIDE][1/4] Resolving three verified constant-return donor methods.\n");
    uint64_t replacements[UpsideDownReplacementCount] = {0};
    if (!upside_replacements(replacements)) {
        log_user("[UPSIDE][FAIL] Required donor methods are unavailable or ambiguous; no target was changed.\n");
        return false;
    }

    uint64_t classes[UpsideDownTargetCount] = {0};
    uint64_t methods[UpsideDownTargetCount] = {0};
    uint64_t keys[UpsideDownTargetCount] = {0};
    uint64_t originals[UpsideDownTargetCount] = {0};
    bool newOriginal[UpsideDownTargetCount] = {false};

    log_user("[UPSIDE][2/4] Preflighting all five targets before the first runtime mutation.\n");
    for (size_t i = 0; i < UpsideDownTargetCount; i++) {
        const UpsideDownTarget *target = &kTargets[i];
        classes[i] = r_class(target->className);
        methods[i] = upside_method(classes[i], target->selectorName);
        keys[i] = r_sel(target->originalKeyName);
        uint64_t current = upside_imp(methods[i]);
        uint64_t replacement = replacements[target->replacementIndex];
        if (!r_is_objc_ptr(classes[i]) || !methods[i] || !keys[i] || !current) {
            log_user("[UPSIDE][FAIL] target=%zu class=%s selector=%s missing; patched=0.\n",
                     i + 1, target->className, target->selectorName);
            return false;
        }
        originals[i] = upside_unbox(upside_associated(classes[i], keys[i]));
        if (originals[i]) {
            if (current != originals[i] && current != replacement) {
                log_user("[UPSIDE][CONFLICT] target=%zu %s::%s changed by another owner; respring required.\n",
                         i + 1, target->className, target->selectorName);
                return false;
            }
        } else {
            if (current == replacement) {
                log_user("[UPSIDE][CONFLICT] target=%zu already uses donor without infern0 ownership; respring required.\n", i + 1);
                return false;
            }
            originals[i] = current;
            newOriginal[i] = true;
        }
        log_user("[UPSIDE][TARGET] %zu/5 class=%s selector=%s state=%s.\n",
                 i + 1, target->className, target->selectorName,
                 current == replacement ? "already-owned" : "ready");
    }

    log_user("[UPSIDE][3/4] Saving exact original IMPs on their owning classes.\n");
    for (size_t i = 0; i < UpsideDownTargetCount; i++) {
        if (!newOriginal[i]) continue;
        uint64_t box = upside_box(originals[i]);
        if (!r_is_objc_ptr(box)) goto storage_failed;
        upside_set_associated(classes[i], keys[i], box);
        if (upside_unbox(upside_associated(classes[i], keys[i])) != originals[i])
            goto storage_failed;
    }

    log_user("[UPSIDE][4/4] Applying the five-method transaction with immediate verification.\n");
    uint64_t previous[UpsideDownTargetCount] = {0};
    bool changed[UpsideDownTargetCount] = {false};
    size_t patched = 0;
    for (; patched < UpsideDownTargetCount; patched++) {
        uint64_t replacement = replacements[kTargets[patched].replacementIndex];
        previous[patched] = upside_imp(methods[patched]);
        if (previous[patched] == replacement) continue;
        uint64_t old = r_dlsym_call(R_TIMEOUT, "method_setImplementation",
                                    methods[patched], replacement, 0, 0, 0, 0, 0, 0);
        if (!old) break;
        changed[patched] = true;
        if (old != previous[patched] || upside_imp(methods[patched]) != replacement)
            break;
    }
    if (patched != UpsideDownTargetCount) {
        for (size_t i = 0; i <= patched && i < UpsideDownTargetCount; i++) {
            if (changed[i]) r_dlsym_call(R_TIMEOUT, "method_setImplementation",
                                         methods[i], previous[i], 0, 0, 0, 0, 0, 0);
        }
        for (size_t i = 0; i < UpsideDownTargetCount; i++)
            if (newOriginal[i]) upside_set_associated(classes[i], keys[i], 0);
        log_user("[UPSIDE][ROLLBACK] target=%zu failed verification; every changed method was restored.\n", patched + 1);
        return false;
    }

    s_applied = true;
    s_apply_count++;
    log_user("[UPSIDE][ACTIVE] apply=%llu targets=5 home=1 lock=1 rotationLockMustBeOff=1 persistentWrites=0.\n",
             s_apply_count);
    return true;

storage_failed:
    for (size_t i = 0; i < UpsideDownTargetCount; i++)
        if (newOriginal[i]) upside_set_associated(classes[i], keys[i], 0);
    log_user("[UPSIDE][FAIL] Original IMP storage verification failed; patched=0.\n");
    return false;
}

bool upsidedown_stop_in_session(void)
{
    bool found = false;
    bool ok = true;
    size_t restored = 0;
    uint64_t replacements[UpsideDownReplacementCount] = {0};
    bool donorsAvailable = upside_replacements(replacements);
    log_user("[UPSIDE][RESTORE] Checking all five owned orientation targets.\n");
    for (size_t i = 0; i < UpsideDownTargetCount; i++) {
        uint64_t cls = r_class(kTargets[i].className);
        uint64_t method = upside_method(cls, kTargets[i].selectorName);
        uint64_t key = r_sel(kTargets[i].originalKeyName);
        uint64_t original = upside_unbox(upside_associated(cls, key));
        if (!original) continue;
        found = true;
        uint64_t current = upside_imp(method);
        if (!method || !current) { ok = false; continue; }
        if (current != original) {
            uint64_t expected = donorsAvailable
                ? replacements[kTargets[i].replacementIndex] : 0;
            if (!expected || current != expected) {
                ok = false;
                log_user("[UPSIDE][CONFLICT] restore target=%zu has a foreign current IMP; leaving it untouched and requiring respring.\n", i + 1);
                continue;
            }
            uint64_t old = r_dlsym_call(R_TIMEOUT, "method_setImplementation",
                                        method, original, 0, 0, 0, 0, 0, 0);
            if (!old || upside_imp(method) != original) { ok = false; continue; }
        }
        upside_set_associated(cls, key, 0);
        if (upside_associated(cls, key)) { ok = false; continue; }
        restored++;
        log_user("[UPSIDE][RESTORE] target=%zu/5 %s::%s exact=1.\n",
                 i + 1, kTargets[i].className, kTargets[i].selectorName);
    }
    if (!found && !s_applied) {
        log_user("[UPSIDE][RESTORE] No owned orientation patch was active.\n");
        return true;
    }
    s_applied = false;
    if (ok) s_restore_count++;
    log_user("[UPSIDE][RESTORE] restored=%zu/5 result=%s restoreEvents=%llu; respring is the fallback.\n",
             restored, ok ? "success" : "incomplete", s_restore_count);
    return ok;
}

void upsidedown_forget_remote_state(void)
{
    s_applied = false;
    log_user("[UPSIDE][FORGET] Cleared app-side ownership state after SpringBoard session loss.\n");
}
