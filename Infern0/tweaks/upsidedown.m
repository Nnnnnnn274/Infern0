//
//  upsidedown.m
//  Cyanide
//

#import "upsidedown.h"
#import "remote_objc.h"
#import "../LogTextView.h"
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

static const UpsideDownTarget kUpsideDownTargets[] = {
    { "SBHomeScreenViewController", "supportedInterfaceOrientations", "cyanideUpsideDownOriginalHomeIMP", UpsideDownReturn6 },
    { "SBCoverSheetPrimarySlidingViewController", "supportedInterfaceOrientations", "cyanideUpsideDownOriginalLockIMP", UpsideDownReturn6 },
    { "SBTraitsSceneParticipantDelegate", "_isAllowedToHavePortraitUpsideDown", "cyanideUpsideDownOriginalAllowedIMP", UpsideDownReturn1 },
    { "SBTraitsSceneParticipantDelegate", "_orientationMode", "cyanideUpsideDownOriginalModeIMP", UpsideDownReturn0x1E },
    { "SBTraitsSceneParticipantDelegate", "_supportedOrientations", "cyanideUpsideDownOriginalSupportedIMP", UpsideDownReturn0x1E },
};

static bool gUpsideDownApplied = false;

static uint64_t upside_instance_method(uint64_t cls, const char *selectorName)
{
    uint64_t sel = r_sel(selectorName);
    if (!r_is_objc_ptr(cls) || !sel) return 0;
    return r_dlsym_call(R_TIMEOUT, "class_getInstanceMethod",
                        cls, sel, 0, 0, 0, 0, 0, 0);
}

static uint64_t upside_method_imp(uint64_t method)
{
    return method
        ? r_dlsym_call(R_TIMEOUT, "method_getImplementation",
                       method, 0, 0, 0, 0, 0, 0, 0)
        : 0;
}

static uint64_t upside_associated(uint64_t object, uint64_t key)
{
    if (!r_is_objc_ptr(object) || !key) return 0;
    return r_dlsym_call(R_TIMEOUT, "objc_getAssociatedObject",
                        object, key, 0, 0, 0, 0, 0, 0);
}

static void upside_set_associated(uint64_t object, uint64_t key, uint64_t value)
{
    if (!r_is_objc_ptr(object) || !key) return;
    r_dlsym_call(R_TIMEOUT, "objc_setAssociatedObject",
                 object, key, value, 1 /* RETAIN_NONATOMIC */, 0, 0, 0, 0);
}

static uint64_t upside_boxed_u64(uint64_t value)
{
    uint64_t numberCls = r_class("NSNumber");
    return r_is_objc_ptr(numberCls)
        ? r_msg2(numberCls, "numberWithUnsignedLongLong:", value, 0, 0, 0)
        : 0;
}

static uint64_t upside_unbox_u64(uint64_t number)
{
    return r_is_objc_ptr(number)
        ? r_msg2(number, "unsignedLongLongValue", 0, 0, 0, 0)
        : 0;
}

static bool upside_replacement_imps(uint64_t out[UpsideDownReplacementCount])
{
    uint64_t shelfCls = r_class("SBShelfExpansionSwitcherModifier");
    uint64_t coverCls = r_class("SBCoverSheetPrimarySlidingViewController");
    uint64_t alertCls = r_class("SBAlertItemRootViewController");
    uint64_t return6Method = upside_instance_method(shelfCls, "transactionCompletionOptions");
    uint64_t return1Method = upside_instance_method(coverCls, "_canShowWhileLocked");
    uint64_t return0x1EMethod = upside_instance_method(alertCls, "supportedInterfaceOrientations");
    if (!return6Method || !return1Method || !return0x1EMethod) return false;

    out[UpsideDownReturn6] = upside_method_imp(return6Method);
    out[UpsideDownReturn1] = upside_method_imp(return1Method);
    out[UpsideDownReturn0x1E] = upside_method_imp(return0x1EMethod);
    return out[0] && out[1] && out[2];
}

bool upsidedown_apply_in_session(void)
{
    uint64_t replacements[UpsideDownReplacementCount] = {0};
    if (!upside_replacement_imps(replacements)) {
        log_user("[UPSIDE-DOWN] Required SpringBoard orientation methods are unavailable.\n");
        return false;
    }

    const size_t count = sizeof(kUpsideDownTargets) / sizeof(kUpsideDownTargets[0]);
    uint64_t classes[UpsideDownTargetCount] = {0};
    uint64_t methods[UpsideDownTargetCount] = {0};
    uint64_t keys[UpsideDownTargetCount] = {0};
    uint64_t originals[UpsideDownTargetCount] = {0};
    bool createdOriginal[UpsideDownTargetCount] = {false};
    for (size_t i = 0; i < count; i++) {
        classes[i] = r_class(kUpsideDownTargets[i].className);
        methods[i] = upside_instance_method(classes[i], kUpsideDownTargets[i].selectorName);
        keys[i] = r_sel(kUpsideDownTargets[i].originalKeyName);
        uint64_t current = upside_method_imp(methods[i]);
        uint64_t replacement = replacements[kUpsideDownTargets[i].replacementIndex];
        if (!r_is_objc_ptr(classes[i]) || !methods[i] || !keys[i] || !current) {
            log_user("[UPSIDE-DOWN] SpringBoard is missing a required orientation target.\n");
            return false;
        }

        originals[i] = upside_unbox_u64(upside_associated(classes[i], keys[i]));
        if (originals[i]) {
            if (current != originals[i] && current != replacement) {
                log_user("[UPSIDE-DOWN] An orientation method changed after Cyanide applied it. Respring and try again.\n");
                return false;
            }
        } else {
            if (current == replacement) {
                log_user("[UPSIDE-DOWN] Orientation methods are already patched. Respring before Cyanide takes ownership.\n");
                return false;
            }
            originals[i] = current;
            createdOriginal[i] = true;
        }
    }

    for (size_t i = 0; i < count; i++) {
        if (!createdOriginal[i]) continue;
        uint64_t box = upside_boxed_u64(originals[i]);
        if (!r_is_objc_ptr(box)) {
            for (size_t j = 0; j < count; j++) {
                if (createdOriginal[j]) upside_set_associated(classes[j], keys[j], 0);
            }
            return false;
        }
        upside_set_associated(classes[i], keys[i], box);
        if (upside_unbox_u64(upside_associated(classes[i], keys[i])) != originals[i]) {
            for (size_t j = 0; j < count; j++) {
                if (createdOriginal[j]) upside_set_associated(classes[j], keys[j], 0);
            }
            return false;
        }
    }

    uint64_t previous[UpsideDownTargetCount] = {0};
    bool changed[UpsideDownTargetCount] = {false};
    size_t patched = 0;
    for (; patched < count; patched++) {
        uint64_t replacement = replacements[kUpsideDownTargets[patched].replacementIndex];
        previous[patched] = upside_method_imp(methods[patched]);
        if (previous[patched] == replacement) continue;
        uint64_t oldImp = r_dlsym_call(R_TIMEOUT, "method_setImplementation",
                                       methods[patched], replacement, 0, 0, 0, 0, 0, 0);
        if (!oldImp) break;
        changed[patched] = true;
    }
    if (patched != count) {
        for (size_t i = 0; i < patched; i++) {
            if (!changed[i]) continue;
            r_dlsym_call(R_TIMEOUT, "method_setImplementation",
                         methods[i], previous[i], 0, 0, 0, 0, 0, 0);
        }
        for (size_t i = 0; i < count; i++) {
            if (createdOriginal[i]) upside_set_associated(classes[i], keys[i], 0);
        }
        log_user("[UPSIDE-DOWN] Runtime patch failed and was rolled back.\n");
        return false;
    }

    gUpsideDownApplied = true;
    printf("[UPSIDE-DOWN] patched %zu SpringBoard orientation methods\n", count);
    log_user("[UPSIDE-DOWN] Enabled for this SpringBoard session.\n");
    return true;
}

bool upsidedown_stop_in_session(void)
{
    const size_t count = sizeof(kUpsideDownTargets) / sizeof(kUpsideDownTargets[0]);
    bool found = false;
    bool ok = true;
    for (size_t i = 0; i < count; i++) {
        uint64_t cls = r_class(kUpsideDownTargets[i].className);
        uint64_t method = upside_instance_method(cls, kUpsideDownTargets[i].selectorName);
        uint64_t key = r_sel(kUpsideDownTargets[i].originalKeyName);
        uint64_t original = upside_unbox_u64(upside_associated(cls, key));
        if (!original) continue;
        found = true;
        uint64_t current = upside_method_imp(method);
        if (!method || !current) {
            ok = false;
            continue;
        }
        if (current != original) {
            uint64_t oldImp = r_dlsym_call(R_TIMEOUT, "method_setImplementation",
                                           method, original, 0, 0, 0, 0, 0, 0);
            if (!oldImp) {
                ok = false;
                continue;
            }
        }
        upside_set_associated(cls, key, 0);
    }

    if (!found && !gUpsideDownApplied) return true;
    gUpsideDownApplied = false;
    log_user(ok
        ? "[UPSIDE-DOWN] Stock SpringBoard orientation behavior restored.\n"
        : "[UPSIDE-DOWN] Cleanup was incomplete; respring restores stock.\n");
    return ok;
}

void upsidedown_forget_remote_state(void)
{
    gUpsideDownApplied = false;
}
