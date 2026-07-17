//
//  fastlockx_lite.m
//  Cyanide
//
//  RemoteCall-only port of the recoverable FastLockX primitives:
//  - SBUIBiometricResource noteScreenDidTurnOff/WillTurnOn retry pulse.
//  - SBLockScreenManager unlockUIFromSource:17 withOptions:@{}.
//  - iOS 26 SBLockScreenBiometricAuthenticationCoordinator unlock intent path.
//
//  The original iOS 15 tweak used Substrate hooks around Face ID success and
//  Pearl failure. Cyanide does not inject arbitrary hook code here, so this is
//  intentionally a manual/test action.
//

#import "fastlockx_lite.h"
#import "../remote_objc.h"
#import "../../LogTextView.h"
#import <math.h>
#import <stdio.h>
#import <string.h>
#import <unistd.h>

static const uint64_t kFastLockXUnlockSource = 17;
static const uint64_t kFastLockXBiometricUnlockIntentDismiss = 3;
static const char *kFastLockXOffTimerKey = "cyanideFastLockXOffTimer";
static const char *kFastLockXOnTimerKey = "cyanideFastLockXOnTimer";
static const char *kFastLockXUnlockTimerKey = "cyanideFastLockXUnlockTimer";
static const char *kFastLockXOnInvocationKey = "cyanideFastLockXOnInvocation";
static const char *kFastLockXUnlockInvocationKey = "cyanideFastLockXUnlockInvocation";
static const char *kFastLockXPauseOffObserverKey = "cyanideFastLockXPauseOffObserver";
static const char *kFastLockXPauseOnObserverKey = "cyanideFastLockXPauseOnObserver";
static const char *kFastLockXPauseUnlockObserverKey = "cyanideFastLockXPauseUnlockObserver";
static const char *kFastLockXResumeOffObserverKey = "cyanideFastLockXResumeOffObserver";
static const char *kFastLockXResumeOnObserverKey = "cyanideFastLockXResumeOnObserver";
static const char *kFastLockXResumeUnlockObserverKey = "cyanideFastLockXResumeUnlockObserver";
static const char *kFastLockXCancelOnObserverKey = "cyanideFastLockXCancelOnObserver";
static const char *kFastLockXCancelUnlockObserverKey = "cyanideFastLockXCancelUnlockObserver";

static const char *kFastLockXPauseNotifications[] = {
    "_UISystemApplicationDidUnlockNotification",
    "__UISystemApplicationDidUnlockNotification",
    "SBLockScreenManagerUnlockAnimationDidFinish",
    "CLBLockScreenDidUnlockNotification",
};

static const char *kFastLockXResumeNotifications[] = {
    "_UISystemApplicationWillLockNotification",
    "__UISystemApplicationWillLockNotification",
    "SBLockScreenUIWillLockNotification",
    "SBLockScreenUIDidLockNotification",
};

static bool gFastLockXAlwaysOnApplied = false;

typedef struct {
    const void *data;
    size_t size;
} FastLockXInvocationArg;

static uint64_t flx_shared_instance(const char *className)
{
    uint64_t cls = r_class(className);
    if (!r_is_objc_ptr(cls)) return 0;
    return r_msg2(cls, "sharedInstance", 0, 0, 0, 0);
}

static bool flx_bool_message(uint64_t obj, const char *selName, bool *outValue)
{
    if (outValue) *outValue = false;
    if (!r_is_objc_ptr(obj) || !r_responds(obj, selName)) return false;
    uint64_t value = r_msg2(obj, selName, 0, 0, 0, 0);
    if (outValue) *outValue = (value != 0);
    return true;
}

static bool flx_bool_message_main(uint64_t obj, const char *selName, bool *outValue)
{
    if (outValue) *outValue = false;
    if (!r_is_objc_ptr(obj) || !r_responds(obj, selName)) return false;
    uint64_t value = r_msg2_main(obj, selName, 0, 0, 0, 0);
    if (outValue) *outValue = (value != 0);
    return true;
}

static uint64_t flx_uint_message_main(uint64_t obj, const char *selName, bool *outHave)
{
    if (outHave) *outHave = false;
    if (!r_is_objc_ptr(obj) || !r_responds(obj, selName)) return 0;
    if (outHave) *outHave = true;
    return r_msg2_main(obj, selName, 0, 0, 0, 0);
}

static uint64_t flx_number_with_bool(bool value)
{
    uint64_t cls = r_class("NSNumber");
    if (!r_is_objc_ptr(cls)) return 0;
    return r_msg2(cls, "numberWithBool:", value ? 1 : 0, 0, 0, 0);
}

static bool flx_set_bool_option(uint64_t dict, const char *keyName, bool value)
{
    if (!r_is_objc_ptr(dict) || !keyName) return false;

    uint64_t key = r_cfstr(keyName);
    uint64_t number = flx_number_with_bool(value);
    bool ok = false;
    if (r_is_objc_ptr(key) && r_is_objc_ptr(number) && r_responds(dict, "setObject:forKey:")) {
        r_msg2(dict, "setObject:forKey:", number, key, 0, 0);
        ok = true;
    }
    if (r_is_objc_ptr(key)) {
        r_dlsym_call(R_TIMEOUT, "CFRelease", key, 0, 0, 0, 0, 0, 0, 0);
    }
    return ok;
}

static uint64_t flx_unlock_options(bool turnOnScreenFirst, bool wakeOnly, bool simulateSwipe)
{
    uint64_t dictCls = r_class("NSMutableDictionary");
    uint64_t options = r_is_objc_ptr(dictCls) ? r_msg2(dictCls, "dictionary", 0, 0, 0, 0) : 0;
    if (!r_is_objc_ptr(options)) return 0;

    if (turnOnScreenFirst) {
        flx_set_bool_option(options, "SBUIUnlockOptionsTurnOnScreenFirstKey", true);
        flx_set_bool_option(options, "SBUIUnlockOptionsStartFadeInAnimation", true);
    }
    if (wakeOnly) {
        flx_set_bool_option(options, "SBUIUnlockOptionsOnlyWakeToActionsKey", true);
    }
    if (simulateSwipe) {
        flx_set_bool_option(options, "SBUIUnlockOptionsSimulateSwipeToUnlock", true);
    }
    return options;
}

static void flx_log_state(const char *stage)
{
    uint64_t manager = flx_shared_instance("SBLockScreenManager");
    if (!r_is_objc_ptr(manager)) {
        printf("[FLX] state %s manager=missing\n", stage ? stage : "?");
        return;
    }

    bool locked = false;
    bool visible = false;
    bool active = false;
    bool unlocking = false;
    bool unlockDisabled = false;
    flx_bool_message_main(manager, "isUILocked", &locked);
    flx_bool_message_main(manager, "isLockScreenVisible", &visible);
    flx_bool_message_main(manager, "isLockScreenActive", &active);
    flx_bool_message_main(manager, "isUIUnlocking", &unlocking);
    flx_bool_message_main(manager, "_isUnlockDisabled", &unlockDisabled);

    uint64_t userAuth = r_ivar_value(manager, "_userAuthController");
    bool userAuthenticated = false;
    bool hasPasscode = false;
    flx_bool_message_main(userAuth, "isAuthenticated", &userAuthenticated);
    flx_bool_message_main(userAuth, "hasPasscodeSet", &hasPasscode);

    uint64_t coordinator = r_responds(manager, "biometricAuthenticationCoordinator") ?
        r_msg2_main(manager, "biometricAuthenticationCoordinator", 0, 0, 0, 0) : 0;
    bool coordinatorAuthenticated = false;
    bool coordinatorEnabled = false;
    bool coordinatorUnlockingDisabled = false;
    bool coordinatorAutoUnlockingDisabled = false;
    bool haveCoordinatorState = false;
    uint64_t coordinatorState = 0;
    flx_bool_message_main(coordinator, "isAuthenticated", &coordinatorAuthenticated);
    flx_bool_message_main(coordinator, "isEnabled", &coordinatorEnabled);
    flx_bool_message_main(coordinator, "isUnlockingDisabled", &coordinatorUnlockingDisabled);
    flx_bool_message_main(coordinator, "isAutoUnlockingDisabled", &coordinatorAutoUnlockingDisabled);
    coordinatorState = flx_uint_message_main(coordinator, "_state", &haveCoordinatorState);

    uint64_t env = r_responds(manager, "lockScreenEnvironment") ?
        r_msg2_main(manager, "lockScreenEnvironment", 0, 0, 0, 0) : 0;
    bool envAuthenticated = false;
    bool envScreenOff = false;
    bool envAutoUnlock = false;
    flx_bool_message_main(env, "isAuthenticated", &envAuthenticated);
    flx_bool_message_main(env, "isInScreenOffMode", &envScreenOff);
    if (r_is_objc_ptr(env) && r_responds(env, "shouldAutoUnlockForSource:")) {
        envAutoUnlock = r_msg2_main(env, "shouldAutoUnlockForSource:", kFastLockXUnlockSource, 0, 0, 0) != 0;
    }

    uint64_t cover = r_responds(manager, "coverSheetViewController") ?
        r_msg2_main(manager, "coverSheetViewController", 0, 0, 0, 0) : 0;
    bool coverAuthenticated = false;
    bool coverPasscodeVisible = false;
    flx_bool_message_main(cover, "isAuthenticated", &coverAuthenticated);
    flx_bool_message_main(cover, "isPasscodeLockVisible", &coverPasscodeVisible);

    uint64_t resource = flx_shared_instance("SBUIBiometricResource");
    bool matching = false;
    bool matchingAllowed = false;
    bool haveLockout = false;
    uint64_t lockout = 0;
    flx_bool_message_main(resource, "isMatchingEnabled", &matching);
    flx_bool_message_main(resource, "isMatchingAllowed", &matchingAllowed);
    lockout = flx_uint_message_main(resource, "biometricLockoutState", &haveLockout);

    printf("[FLX] state %s locked=%d visible=%d active=%d unlocking=%d disabled=%d "
           "userAuth=%d passcode=%d coordAuth=%d coordEnabled=%d coordUnlockDisabled=%d "
           "coordAutoDisabled=%d coordState=%llu%s envAuth=%d envScreenOff=%d envAuto=%d "
           "coverAuth=%d passcodeVisible=%d matching=%d matchingAllowed=%d lockout=%llu%s\n",
           stage ? stage : "?",
           locked,
           visible,
           active,
           unlocking,
           unlockDisabled,
           userAuthenticated,
           hasPasscode,
           coordinatorAuthenticated,
           coordinatorEnabled,
           coordinatorUnlockingDisabled,
           coordinatorAutoUnlockingDisabled,
           (unsigned long long)coordinatorState,
           haveCoordinatorState ? "" : "?",
           envAuthenticated,
           envScreenOff,
           envAutoUnlock,
           coverAuthenticated,
           coverPasscodeVisible,
           matching,
           matchingAllowed,
           (unsigned long long)lockout,
           haveLockout ? "" : "?");
}

static bool flx_blocked_by_music(void)
{
    uint64_t media = flx_shared_instance("SBMediaController");
    if (!r_is_objc_ptr(media)) {
        printf("[FLX] SBMediaController unavailable; music blocker skipped\n");
        return false;
    }

    bool playing = false;
    bool paused = false;
    bool havePlaying = flx_bool_message(media, "isPlaying", &playing);
    bool havePaused = flx_bool_message(media, "isPaused", &paused);

    printf("[FLX] media state playing=%d(%d) paused=%d(%d)\n",
           havePlaying, playing, havePaused, paused);
    if ((havePlaying && playing) || (havePaused && paused)) {
        log_user("[FLX] Blocked: media is active or paused.\n");
        return true;
    }
    return false;
}

static bool flx_flashlight_level(float *outLevel)
{
    if (outLevel) *outLevel = 0.0f;

    uint64_t cls = r_class("AVFlashlight");
    if (!r_is_objc_ptr(cls)) {
        printf("[FLX] AVFlashlight unavailable; flashlight blocker skipped\n");
        return false;
    }

    uint64_t flash = r_msg2(cls, "new", 0, 0, 0, 0);
    if (!r_is_objc_ptr(flash)) {
        printf("[FLX] AVFlashlight new failed; flashlight blocker skipped\n");
        return false;
    }

    uint64_t bits = r_msg2_main_raw(flash,
                                    "flashlightLevel",
                                    NULL, 0,
                                    NULL, 0,
                                    NULL, 0,
                                    NULL, 0);
    float level = 0.0f;
    uint32_t low = (uint32_t)(bits & 0xffffffffu);
    memcpy(&level, &low, sizeof(level));
    if (outLevel) *outLevel = level;

    if (r_responds(flash, "release")) {
        r_msg2(flash, "release", 0, 0, 0, 0);
    }
    return true;
}

static bool flx_blocked_by_flashlight(void)
{
    float level = 0.0f;
    if (!flx_flashlight_level(&level)) return false;
    printf("[FLX] flashlightLevel=%f\n", level);
    if (level > 0.0f) {
        log_user("[FLX] Blocked: flashlight is on.\n");
        return true;
    }
    return false;
}

static bool flx_blocked_by_low_power(void)
{
    uint64_t cls = r_class("NSProcessInfo");
    uint64_t info = r_is_objc_ptr(cls) ? r_msg2(cls, "processInfo", 0, 0, 0, 0) : 0;
    if (!r_is_objc_ptr(info)) {
        printf("[FLX] NSProcessInfo unavailable; Low Power blocker skipped\n");
        return false;
    }

    bool lowPower = false;
    if (!flx_bool_message(info, "isLowPowerModeEnabled", &lowPower)) {
        printf("[FLX] isLowPowerModeEnabled unavailable; Low Power blocker skipped\n");
        return false;
    }
    printf("[FLX] lowPower=%d\n", lowPower);
    if (lowPower) {
        log_user("[FLX] Blocked: Low Power Mode is enabled.\n");
        return true;
    }
    return false;
}

static bool flx_pulse_biometric_retry(double intervalSeconds)
{
    if (!isfinite(intervalSeconds) || intervalSeconds <= 0.0) intervalSeconds = 0.75;
    if (intervalSeconds < 0.75) intervalSeconds = 0.75;
    if (intervalSeconds > 2.0) intervalSeconds = 2.0;

    uint64_t resource = flx_shared_instance("SBUIBiometricResource");
    if (!r_is_objc_ptr(resource)) {
        log_user("[FLX] SBUIBiometricResource is unavailable on this SpringBoard.\n");
        return false;
    }

    bool didOff = false;
    bool didOn = false;
    if (r_responds(resource, "noteScreenDidTurnOff")) {
        r_msg2_main(resource, "noteScreenDidTurnOff", 0, 0, 0, 0);
        didOff = true;
    }
    usleep((useconds_t)(intervalSeconds * 1000000.0));
    if (r_responds(resource, "noteScreenWillTurnOn")) {
        r_msg2_main(resource, "noteScreenWillTurnOn", 0, 0, 0, 0);
        didOn = true;
    }

    printf("[FLX] biometric retry pulse off=%d on=%d interval=%.2f\n",
           didOff, didOn, intervalSeconds);
    if (didOff && didOn) {
        log_user("[FLX] Face ID retry pulse sent (%.1fs interval).\n", intervalSeconds);
    } else {
        log_user("[FLX] Face ID retry pulse incomplete: off=%d on=%d.\n", didOff, didOn);
    }
    return didOff && didOn;
}

static bool flx_prime_unlock_attempt(bool turnOnScreenFirst)
{
    uint64_t manager = flx_shared_instance("SBLockScreenManager");
    if (!r_is_objc_ptr(manager)) {
        log_user("[FLX] SBLockScreenManager is unavailable on this SpringBoard.\n");
        return false;
    }
    if (!r_responds(manager, "unlockUIFromSource:withOptions:")) {
        log_user("[FLX] unlockUIFromSource:withOptions: is unavailable on this SpringBoard.\n");
        return false;
    }

    uint64_t options = flx_unlock_options(turnOnScreenFirst, true, false);
    if (!r_is_objc_ptr(options)) {
        log_user("[FLX] Could not create unlock options dictionary.\n");
        return false;
    }

    uint64_t ret = r_msg2_main(manager,
                               "unlockUIFromSource:withOptions:",
                               kFastLockXUnlockSource,
                               options,
                               0,
                               0);
    printf("[FLX] prime unlockUIFromSource:%llu returned=%llu options=%s\n",
           (unsigned long long)kFastLockXUnlockSource,
           (unsigned long long)(ret & 0xff),
           turnOnScreenFirst ? "turnOnScreen+onlyWake" : "onlyWake");
    return true;
}

static bool flx_wake_for_unlock_attempt(void)
{
    return flx_prime_unlock_attempt(true);
}

static bool flx_prime_unlock_attempt_no_wake(void)
{
    return flx_prime_unlock_attempt(false);
}

static bool flx_attempt_biometric_unlock(void)
{
    uint64_t manager = flx_shared_instance("SBLockScreenManager");
    if (!r_is_objc_ptr(manager)) {
        log_user("[FLX] SBLockScreenManager is unavailable on this SpringBoard.\n");
        return false;
    }

    bool any = false;
    uint64_t coordinator = r_responds(manager, "biometricAuthenticationCoordinator") ?
        r_msg2_main(manager, "biometricAuthenticationCoordinator", 0, 0, 0, 0) : 0;
    if (r_is_objc_ptr(coordinator) &&
        r_responds(manager, "biometricAuthenticationCoordinator:requestsUnlockWithIntent:")) {
        any = true;
        uint64_t ret = r_msg2_main(manager,
                                   "biometricAuthenticationCoordinator:requestsUnlockWithIntent:",
                                   coordinator,
                                   kFastLockXBiometricUnlockIntentDismiss,
                                   0,
                                   0);
        printf("[FLX] biometric coordinator unlock intent=%llu returned=%llu\n",
               (unsigned long long)kFastLockXBiometricUnlockIntentDismiss,
               (unsigned long long)(ret & 0xff));
        if ((ret & 0xff) != 0) {
            log_user("[FLX] Biometric unlock request accepted by SpringBoard coordinator.\n");
            return true;
        }
    }

    if (r_responds(manager, "_attemptUnlockWithPasscode:mesa:finishUIUnlock:")) {
        any = true;
        uint64_t ret = r_msg2_main(manager,
                                   "_attemptUnlockWithPasscode:mesa:finishUIUnlock:",
                                   0,
                                   1,
                                   1,
                                   0);
        printf("[FLX] _attemptUnlockWithPasscode:nil mesa=1 finish=1 returned=%llu\n",
               (unsigned long long)(ret & 0xff));
        if ((ret & 0xff) != 0) {
            log_user("[FLX] Biometric auth pipeline started.\n");
            return true;
        }
    }

    if (r_responds(manager, "attemptUnlockWithMesa")) {
        any = true;
        r_msg2_main(manager, "attemptUnlockWithMesa", 0, 0, 0, 0);
        printf("[FLX] attemptUnlockWithMesa sent (void return)\n");
        log_user("[FLX] Legacy biometric unlock attempt sent.\n");
        return true;
    }

    if (!any) {
        log_user("[FLX] No biometric unlock request method was available.\n");
    }
    return false;
}

static bool flx_attempt_unlock_with_screen_option(bool turnOnScreenFirst)
{
    uint64_t manager = flx_shared_instance("SBLockScreenManager");
    if (!r_is_objc_ptr(manager)) {
        log_user("[FLX] SBLockScreenManager is unavailable on this SpringBoard.\n");
        return false;
    }
    if (!r_responds(manager, "unlockUIFromSource:withOptions:")) {
        log_user("[FLX] unlockUIFromSource:withOptions: is unavailable on this SpringBoard.\n");
        return false;
    }

    uint64_t options = flx_unlock_options(turnOnScreenFirst, false, true);
    if (!r_is_objc_ptr(options)) {
        log_user("[FLX] Could not create unlock options dictionary.\n");
        return false;
    }

    uint64_t ret = r_msg2_main(manager,
                               "unlockUIFromSource:withOptions:",
                               kFastLockXUnlockSource,
                               options,
                               0,
                               0);
    bool accepted = (ret & 0xff) != 0;
    printf("[FLX] unlockUIFromSource:%llu returned=%d options=%s\n",
           (unsigned long long)kFastLockXUnlockSource,
           accepted,
           turnOnScreenFirst ? "turnOnScreen+simulateSwipe" : "simulateSwipe");
    if (accepted) {
        log_user("[FLX] Unlock request accepted by SpringBoard.\n");
    } else {
        log_user("[FLX] Unlock request returned 0; waiting for biometric auth or lock-screen visibility.\n");
    }
    return accepted;
}

static bool flx_attempt_unlock(void)
{
    return flx_attempt_unlock_with_screen_option(true);
}

static bool flx_attempt_unlock_no_wake(void)
{
    return flx_attempt_unlock_with_screen_option(false);
}

static bool flx_set_invocation_arg(uint64_t invocation,
                                   uint64_t index,
                                   const void *arg,
                                   size_t argSize)
{
    if (!r_is_objc_ptr(invocation)) return false;

    size_t argBufLen = (argSize > 8) ? argSize : 8;
    uint64_t argBuf = r_dlsym_call(R_TIMEOUT, "malloc",
                                   argBufLen, 0, 0, 0, 0, 0, 0, 0);
    if (!argBuf) return false;

    bool ok = false;
    if (argSize <= 8) {
        uint64_t value = 0;
        if (arg && argSize) memcpy(&value, arg, argSize);
        ok = remote_write64(argBuf, value);
    } else {
        ok = arg && remote_write(argBuf, arg, argSize);
    }
    if (ok) {
        r_msg2_main(invocation, "setArgument:atIndex:", argBuf, index, 0, 0);
    }
    r_free(argBuf);
    return ok;
}

static uint64_t flx_invocation(uint64_t target,
                               const char *selectorName,
                               const FastLockXInvocationArg *args,
                               size_t argCount)
{
    if (!r_is_objc_ptr(target) || !selectorName) return 0;

    uint64_t selector = r_sel(selectorName);
    if (!selector || !r_responds(target, selectorName)) return 0;

    uint64_t signature = r_msg2_main(target, "methodSignatureForSelector:",
                                     selector, 0, 0, 0);
    if (!r_is_objc_ptr(signature)) return 0;

    uint64_t reportedArgCount = r_msg2_main(signature,
                                            "numberOfArguments",
                                            0,
                                            0,
                                            0,
                                            0);
    if (reportedArgCount < argCount + 2) return 0;

    uint64_t NSInvocation = r_class("NSInvocation");
    uint64_t invocation = r_is_objc_ptr(NSInvocation)
        ? r_msg2_main(NSInvocation, "invocationWithMethodSignature:",
                      signature, 0, 0, 0)
        : 0;
    if (!r_is_objc_ptr(invocation)) return 0;

    uint64_t retainedInvocation = r_msg2_main(invocation, "retain", 0, 0, 0, 0);
    if (r_is_objc_ptr(retainedInvocation)) invocation = retainedInvocation;

    r_msg2_main(invocation, "setTarget:", target, 0, 0, 0);
    r_msg2_main(invocation, "setSelector:", selector, 0, 0, 0);

    bool ok = true;
    for (size_t i = 0; i < argCount; i++) {
        ok = flx_set_invocation_arg(invocation,
                                    (uint64_t)i + 2,
                                    args[i].data,
                                    args[i].size);
        if (!ok) break;
    }
    if (!ok) {
        if (r_responds(invocation, "release")) {
            r_msg2_main(invocation, "release", 0, 0, 0, 0);
        }
        return 0;
    }

    r_msg2_main(invocation, "retainArguments", 0, 0, 0, 0);
    return invocation;
}

static void flx_release_remote_object(uint64_t object)
{
    if (r_is_objc_ptr(object) && r_responds(object, "release")) {
        r_msg2_main(object, "release", 0, 0, 0, 0);
    }
}

static uint64_t flx_assoc_object(uint64_t owner, const char *keyName)
{
    if (!r_is_objc_ptr(owner) || !keyName) return 0;
    uint64_t key = r_sel(keyName);
    if (!key) return 0;
    return r_dlsym_call(R_TIMEOUT, "objc_getAssociatedObject",
                        owner, key, 0, 0, 0, 0, 0, 0);
}

static bool flx_set_assoc_object(uint64_t owner, const char *keyName, uint64_t object)
{
    if (!r_is_objc_ptr(owner) || !keyName) return false;
    uint64_t key = r_sel(keyName);
    if (!key) return false;
    r_dlsym_call(R_TIMEOUT, "objc_setAssociatedObject",
                 owner, key, object, 1 /* RETAIN_NONATOMIC */,
                 0, 0, 0, 0);
    return true;
}

static void flx_invoke_now(uint64_t invocation)
{
    if (r_is_objc_ptr(invocation) && r_responds(invocation, "invoke")) {
        r_msg2_main(invocation, "invoke", 0, 0, 0, 0);
    }
}

static bool flx_lock_gate_active(uint64_t manager)
{
    if (!r_is_objc_ptr(manager)) return false;

    bool locked = false;
    bool visible = false;
    bool active = false;
    bool unlocking = false;
    bool haveLocked = flx_bool_message_main(manager, "isUILocked", &locked);
    bool haveVisible = flx_bool_message_main(manager, "isLockScreenVisible", &visible);
    bool haveActive = flx_bool_message_main(manager, "isLockScreenActive", &active);
    flx_bool_message_main(manager, "isUIUnlocking", &unlocking);

    uint64_t env = r_responds(manager, "lockScreenEnvironment") ?
        r_msg2_main(manager, "lockScreenEnvironment", 0, 0, 0, 0) : 0;
    bool envScreenOff = false;
    flx_bool_message_main(env, "isInScreenOffMode", &envScreenOff);

    return (haveLocked && locked) ||
           (haveVisible && visible) ||
           (haveActive && active) ||
           unlocking ||
           envScreenOff;
}

static bool flx_invalidate_assoc_timer(uint64_t owner, const char *keyName)
{
    if (!r_is_objc_ptr(owner) || !keyName) return false;

    uint64_t timer = flx_assoc_object(owner, keyName);
    if (r_is_objc_ptr(timer) && r_responds(timer, "invalidate")) {
        r_msg2_main(timer, "invalidate", 0, 0, 0, 0);
    }

    return flx_set_assoc_object(owner, keyName, 0);
}

static bool flx_schedule_invocation_timer(uint64_t owner,
                                          const char *keyName,
                                          double interval,
                                          double tolerance,
                                          uint64_t invocation,
                                          uint64_t *outTimer)
{
    if (outTimer) *outTimer = 0;
    if (!r_is_objc_ptr(owner) || !keyName || !r_is_objc_ptr(invocation)) return false;
    if (!isfinite(interval) || interval <= 0.0) return false;

    uint64_t key = r_sel(keyName);
    if (!key) return false;

    flx_invalidate_assoc_timer(owner, keyName);

    uint64_t NSTimer = r_class("NSTimer");
    if (!r_is_objc_ptr(NSTimer) ||
        !r_responds(NSTimer, "scheduledTimerWithTimeInterval:invocation:repeats:")) {
        return false;
    }

    uint8_t repeats = 1;
    uint64_t timer = r_msg2_main_raw(NSTimer,
        "scheduledTimerWithTimeInterval:invocation:repeats:",
        &interval,   sizeof(interval),
        &invocation, sizeof(invocation),
        &repeats,   sizeof(repeats),
        NULL,        0);
    if (!r_is_objc_ptr(timer)) return false;

    if (isfinite(tolerance) && tolerance >= 0.0 && r_responds(timer, "setTolerance:")) {
        r_msg2_main_raw(timer, "setTolerance:",
                        &tolerance, sizeof(tolerance),
                        NULL, 0, NULL, 0, NULL, 0);
    }

    uint64_t NSRunLoop = r_class("NSRunLoop");
    uint64_t loop = r_is_objc_ptr(NSRunLoop) && r_responds(NSRunLoop, "mainRunLoop")
        ? r_msg2_main(NSRunLoop, "mainRunLoop", 0, 0, 0, 0)
        : 0;
    uint64_t commonMode = r_nsstr_retained("kCFRunLoopCommonModes");
    if (r_is_objc_ptr(loop) &&
        r_is_objc_ptr(commonMode) &&
        r_responds(loop, "addTimer:forMode:")) {
        r_msg2_main(loop, "addTimer:forMode:", timer, commonMode, 0, 0);
    }
    if (r_is_objc_ptr(commonMode)) {
        r_msg2_main(commonMode, "release", 0, 0, 0, 0);
    }

    flx_set_assoc_object(owner, keyName, timer);
    if (outTimer) *outTimer = timer;
    return true;
}

static uint64_t flx_date(bool distantFuture)
{
    uint64_t NSDate = r_class("NSDate");
    if (!r_is_objc_ptr(NSDate)) return 0;
    return r_msg2_main(NSDate,
                       distantFuture ? "distantFuture" : "distantPast",
                       0, 0, 0, 0);
}

static uint64_t flx_timer_firedate_invocation(uint64_t timer, uint64_t date)
{
    if (!r_is_objc_ptr(timer) || !r_is_objc_ptr(date)) return 0;
    FastLockXInvocationArg args[] = {
        { &date, sizeof(date) },
    };
    return flx_invocation(timer,
                          "setFireDate:",
                          args,
                          sizeof(args) / sizeof(args[0]));
}

static bool flx_set_timer_firedate_now(uint64_t timer, uint64_t date)
{
    if (!r_is_objc_ptr(timer) || !r_is_objc_ptr(date) ||
        !r_responds(timer, "setFireDate:")) {
        return false;
    }
    r_msg2_main(timer, "setFireDate:", date, 0, 0, 0);
    return true;
}

static uint64_t flx_delayed_invoke_scheduler(uint64_t invocation, double delay)
{
    if (!r_is_objc_ptr(invocation)) return 0;
    if (!isfinite(delay) || delay < 0.0) delay = 0.0;

    uint64_t invokeSel = r_sel("invoke");
    uint64_t nilObject = 0;
    FastLockXInvocationArg args[] = {
        { &invokeSel,  sizeof(invokeSel) },
        { &nilObject,  sizeof(nilObject) },
        { &delay,      sizeof(delay) },
    };
    return flx_invocation(invocation,
                          "performSelector:withObject:afterDelay:",
                          args,
                          sizeof(args) / sizeof(args[0]));
}

static uint64_t flx_cancel_delayed_invoke_invocation(uint64_t invocation)
{
    if (!r_is_objc_ptr(invocation)) return 0;

    uint64_t NSObject = r_class("NSObject");
    uint64_t invokeSel = r_sel("invoke");
    uint64_t nilObject = 0;
    FastLockXInvocationArg args[] = {
        { &invocation, sizeof(invocation) },
        { &invokeSel,  sizeof(invokeSel) },
        { &nilObject,  sizeof(nilObject) },
    };
    return flx_invocation(NSObject,
                          "cancelPreviousPerformRequestsWithTarget:selector:object:",
                          args,
                          sizeof(args) / sizeof(args[0]));
}

static bool flx_remove_assoc_observer(uint64_t owner, const char *keyName)
{
    uint64_t observer = flx_assoc_object(owner, keyName);
    if (!r_is_objc_ptr(observer)) return flx_set_assoc_object(owner, keyName, 0);

    uint64_t centerCls = r_class("NSNotificationCenter");
    uint64_t center = r_is_objc_ptr(centerCls) ?
        r_msg2_main(centerCls, "defaultCenter", 0, 0, 0, 0) : 0;
    if (r_is_objc_ptr(center) && r_responds(center, "removeObserver:")) {
        r_msg2_main(center, "removeObserver:", observer, 0, 0, 0);
    }
    return flx_set_assoc_object(owner, keyName, 0);
}

static bool flx_register_assoc_observer(uint64_t owner,
                                        const char *keyName,
                                        uint64_t observer,
                                        const char *const *names,
                                        size_t nameCount)
{
    if (!r_is_objc_ptr(owner) || !keyName || !r_is_objc_ptr(observer) || !names || nameCount == 0) {
        return false;
    }

    flx_remove_assoc_observer(owner, keyName);

    uint64_t centerCls = r_class("NSNotificationCenter");
    uint64_t center = r_is_objc_ptr(centerCls) ?
        r_msg2_main(centerCls, "defaultCenter", 0, 0, 0, 0) : 0;
    uint64_t invokeSel = r_sel("invoke");
    if (!r_is_objc_ptr(center) || !invokeSel ||
        !r_responds(center, "addObserver:selector:name:object:")) {
        return false;
    }

    bool ok = true;
    for (size_t i = 0; i < nameCount; i++) {
        if (!names[i] || !names[i][0]) continue;
        uint64_t name = r_nsstr_retained(names[i]);
        if (!r_is_objc_ptr(name)) {
            ok = false;
            continue;
        }
        r_msg2_main(center,
                    "addObserver:selector:name:object:",
                    observer,
                    invokeSel,
                    name,
                    0);
        flx_release_remote_object(name);
    }
    ok &= flx_set_assoc_object(owner, keyName, observer);
    return ok;
}

static uint64_t flx_unlock_timer_invocation(uint64_t manager)
{
    if (!r_is_objc_ptr(manager)) return 0;

    if (r_responds(manager, "_attemptUnlockWithPasscode:mesa:finishUIUnlock:")) {
        uint64_t passcode = 0;
        uint8_t mesa = 1;
        uint8_t finish = 1;
        FastLockXInvocationArg args[] = {
            { &passcode, sizeof(passcode) },
            { &mesa,     sizeof(mesa) },
            { &finish,   sizeof(finish) },
        };
        uint64_t invocation = flx_invocation(manager,
                                             "_attemptUnlockWithPasscode:mesa:finishUIUnlock:",
                                             args,
                                             sizeof(args) / sizeof(args[0]));
        if (r_is_objc_ptr(invocation)) return invocation;
    }

    if (r_responds(manager, "attemptUnlockWithMesa")) {
        uint64_t invocation = flx_invocation(manager, "attemptUnlockWithMesa", NULL, 0);
        if (r_is_objc_ptr(invocation)) return invocation;
    }

    uint64_t coordinator = r_responds(manager, "biometricAuthenticationCoordinator") ?
        r_msg2_main(manager, "biometricAuthenticationCoordinator", 0, 0, 0, 0) : 0;
    if (r_is_objc_ptr(coordinator) &&
        r_responds(manager, "biometricAuthenticationCoordinator:requestsUnlockWithIntent:")) {
        uint64_t intent = kFastLockXBiometricUnlockIntentDismiss;
        FastLockXInvocationArg args[] = {
            { &coordinator, sizeof(coordinator) },
            { &intent,      sizeof(intent) },
        };
        uint64_t invocation = flx_invocation(manager,
                                             "biometricAuthenticationCoordinator:requestsUnlockWithIntent:",
                                             args,
                                             sizeof(args) / sizeof(args[0]));
        if (r_is_objc_ptr(invocation)) return invocation;
    }

    if (r_responds(manager, "unlockUIFromSource:withOptions:")) {
        uint64_t options = flx_unlock_options(false, false, true);
        if (r_is_objc_ptr(options)) {
            uint64_t source = kFastLockXUnlockSource;
            FastLockXInvocationArg args[] = {
                { &source,  sizeof(source) },
                { &options, sizeof(options) },
            };
            uint64_t invocation = flx_invocation(manager,
                                                 "unlockUIFromSource:withOptions:",
                                                 args,
                                                 sizeof(args) / sizeof(args[0]));
            flx_release_remote_object(options);
            if (r_is_objc_ptr(invocation)) return invocation;
        }
    }
    return 0;
}

typedef enum {
    FastLockXDisableLogUserDisable = 0,
    FastLockXDisableLogPreparingEnable,
    FastLockXDisableLogFailedEnableCleanup,
} FastLockXDisableLogMode;

static bool flx_disable_always_on_in_session(FastLockXDisableLogMode logMode)
{
    uint64_t manager = flx_shared_instance("SBLockScreenManager");
    if (!r_is_objc_ptr(manager)) {
        gFastLockXAlwaysOnApplied = false;
        if (logMode == FastLockXDisableLogPreparingEnable) {
            log_user("[FLX] Preparing Always On: SpringBoard manager missing; setup may fail.\n");
        } else if (logMode == FastLockXDisableLogFailedEnableCleanup) {
            log_user("[FLX] Always On setup cleanup skipped: SBLockScreenManager missing.\n");
        } else if (logMode == FastLockXDisableLogUserDisable) {
            log_user("[FLX] Always On disable skipped: SBLockScreenManager missing.\n");
        }
        return false;
    }

    bool ok = true;
    ok &= flx_remove_assoc_observer(manager, kFastLockXPauseOffObserverKey);
    ok &= flx_remove_assoc_observer(manager, kFastLockXPauseOnObserverKey);
    ok &= flx_remove_assoc_observer(manager, kFastLockXPauseUnlockObserverKey);
    ok &= flx_remove_assoc_observer(manager, kFastLockXResumeOffObserverKey);
    ok &= flx_remove_assoc_observer(manager, kFastLockXResumeOnObserverKey);
    ok &= flx_remove_assoc_observer(manager, kFastLockXResumeUnlockObserverKey);
    ok &= flx_remove_assoc_observer(manager, kFastLockXCancelOnObserverKey);
    ok &= flx_remove_assoc_observer(manager, kFastLockXCancelUnlockObserverKey);

    uint64_t onInvocation = flx_assoc_object(manager, kFastLockXOnInvocationKey);
    uint64_t unlockInvocation = flx_assoc_object(manager, kFastLockXUnlockInvocationKey);
    uint64_t cancelOn = flx_cancel_delayed_invoke_invocation(onInvocation);
    uint64_t cancelUnlock = flx_cancel_delayed_invoke_invocation(unlockInvocation);
    flx_invoke_now(cancelOn);
    flx_invoke_now(cancelUnlock);
    flx_release_remote_object(cancelOn);
    flx_release_remote_object(cancelUnlock);
    ok &= flx_set_assoc_object(manager, kFastLockXOnInvocationKey, 0);
    ok &= flx_set_assoc_object(manager, kFastLockXUnlockInvocationKey, 0);

    ok &= flx_invalidate_assoc_timer(manager, kFastLockXOffTimerKey);
    ok &= flx_invalidate_assoc_timer(manager, kFastLockXOnTimerKey);
    ok &= flx_invalidate_assoc_timer(manager, kFastLockXUnlockTimerKey);
    gFastLockXAlwaysOnApplied = false;

    if (logMode == FastLockXDisableLogPreparingEnable) {
        printf("[FLX] Always On setup cleared old timers ok=%d\n", ok);
        log_user("[FLX] Preparing Always On: cleared old timers, enabling new timers now.\n");
    } else if (logMode == FastLockXDisableLogFailedEnableCleanup) {
        printf("[FLX] Always On setup cleanup ok=%d\n", ok);
        log_user("[FLX] Always On setup failed; cleaned up partial timers.\n");
    } else if (logMode == FastLockXDisableLogUserDisable) {
        printf("[FLX] Always On timers disabled ok=%d\n", ok);
        log_user("[FLX] Always On timers disabled.\n");
    }
    return ok;
}

bool fastlockx_lite_disable_always_on_in_session(void)
{
    return flx_disable_always_on_in_session(FastLockXDisableLogUserDisable);
}

bool fastlockx_lite_attempt_unlock_in_session(bool diagnosticLogging)
{
    if (diagnosticLogging) {
        flx_log_state("host-unlock-pre");
    }

    bool primeOK = flx_prime_unlock_attempt_no_wake();
    usleep(120000);
    bool modernOK = flx_attempt_biometric_unlock();
    usleep(150000);
    bool directOK = flx_attempt_unlock_no_wake();

    if (diagnosticLogging) {
        flx_log_state("host-unlock-post");
    }
    printf("[FLX] host unlock nudge primeNoWake=%d modern=%d directNoWake=%d\n",
           primeOK,
           modernOK,
           directOK);
    return primeOK || modernOK || directOK;
}

bool fastlockx_lite_set_always_on_active_in_session(bool active)
{
    uint64_t manager = flx_shared_instance("SBLockScreenManager");
    if (!r_is_objc_ptr(manager)) {
        printf("[FLX] Always On host sync skipped: SBLockScreenManager missing\n");
        return false;
    }

    uint64_t offTimer = flx_assoc_object(manager, kFastLockXOffTimerKey);
    uint64_t onTimer = flx_assoc_object(manager, kFastLockXOnTimerKey);
    uint64_t unlockTimer = flx_assoc_object(manager, kFastLockXUnlockTimerKey);
    uint64_t date = flx_date(!active);
    if (!r_is_objc_ptr(date)) {
        printf("[FLX] Always On host sync skipped: date unavailable active=%d\n", active);
        return false;
    }

    bool offOK = flx_set_timer_firedate_now(offTimer, date);
    bool onOK = flx_set_timer_firedate_now(onTimer, date);
    bool unlockOK = r_is_objc_ptr(unlockTimer)
        ? flx_set_timer_firedate_now(unlockTimer, date)
        : true;

    bool cancelOK = true;
    if (!active) {
        uint64_t onInvocation = flx_assoc_object(manager, kFastLockXOnInvocationKey);
        uint64_t unlockInvocation = flx_assoc_object(manager, kFastLockXUnlockInvocationKey);
        uint64_t cancelOn = flx_cancel_delayed_invoke_invocation(onInvocation);
        uint64_t cancelUnlock = flx_cancel_delayed_invoke_invocation(unlockInvocation);
        flx_invoke_now(cancelOn);
        flx_invoke_now(cancelUnlock);
        cancelOK = r_is_objc_ptr(cancelOn) &&
                   (!r_is_objc_ptr(unlockInvocation) || r_is_objc_ptr(cancelUnlock));
        flx_release_remote_object(cancelOn);
        flx_release_remote_object(cancelUnlock);
    }

    bool ok = offOK && onOK && unlockOK && cancelOK;
    printf("[FLX] Always On host sync active=%d off=%#llx(%d) on=%#llx(%d) unlock=%#llx(%d) cancel=%d ok=%d\n",
           active,
           (unsigned long long)offTimer, offOK,
           (unsigned long long)onTimer, onOK,
           (unsigned long long)unlockTimer, unlockOK,
           cancelOK,
           ok);
    return ok;
}

void fastlockx_lite_forget_remote_state(void)
{
    gFastLockXAlwaysOnApplied = false;
}

bool fastlockx_lite_enable_always_on_in_session(FastLockXLiteConfig config)
{
    double retry = config.retryIntervalSeconds;
    // Repeated biometric off/on calls are unusually sensitive to timing.
    // Sub-second repeating timers can overlap SpringBoard lock transitions and
    // have caused watchdog resprings on slower devices. Keep the one-shot
    // action configurable, but make the persistent mode deliberately calm.
    if (!isfinite(retry) || retry <= 0.0) retry = 0.75;
    if (retry < 0.75) retry = 0.75;
    if (retry > 2.0) retry = 2.0;

    double unlockDelay = retry + 0.45;
    if (unlockDelay < 0.75) unlockDelay = 0.75;
    if (unlockDelay > 1.8) unlockDelay = 1.8;

    double cycle = unlockDelay + 1.0;
    if (cycle < 2.5) cycle = 2.5;
    if (cycle > 4.0) cycle = 4.0;

    uint64_t manager = flx_shared_instance("SBLockScreenManager");
    uint64_t resource = flx_shared_instance("SBUIBiometricResource");
    if (!r_is_objc_ptr(manager)) {
        log_user("[FLX] Always On unavailable: SBLockScreenManager missing.\n");
        return false;
    }
    if (!r_is_objc_ptr(resource)) {
        log_user("[FLX] Always On unavailable: SBUIBiometricResource missing.\n");
        return false;
    }
    if (!r_responds(resource, "noteScreenDidTurnOff") ||
        !r_responds(resource, "noteScreenWillTurnOn")) {
        log_user("[FLX] Always On unavailable: biometric retry methods missing.\n");
        return false;
    }

    flx_disable_always_on_in_session(FastLockXDisableLogPreparingEnable);

    bool activeNow = flx_lock_gate_active(manager);
    uint64_t offInvocation = flx_invocation(resource, "noteScreenDidTurnOff", NULL, 0);
    uint64_t onInvocation = flx_invocation(resource, "noteScreenWillTurnOn", NULL, 0);
    uint64_t unlockInvocation = config.attemptUnlock ? flx_unlock_timer_invocation(manager) : 0;
    uint64_t scheduleOnInvocation = flx_delayed_invoke_scheduler(onInvocation, retry);
    uint64_t scheduleUnlockInvocation = config.attemptUnlock ?
        flx_delayed_invoke_scheduler(unlockInvocation, unlockDelay) : 0;

    bool ok = r_is_objc_ptr(offInvocation) &&
              r_is_objc_ptr(onInvocation) &&
              r_is_objc_ptr(scheduleOnInvocation);
    if (config.attemptUnlock) {
        ok &= r_is_objc_ptr(unlockInvocation) &&
              r_is_objc_ptr(scheduleUnlockInvocation);
    }
    if (!ok) {
        flx_release_remote_object(offInvocation);
        flx_release_remote_object(onInvocation);
        flx_release_remote_object(unlockInvocation);
        flx_release_remote_object(scheduleOnInvocation);
        flx_release_remote_object(scheduleUnlockInvocation);
        log_user("[FLX] Always On unavailable: could not build SpringBoard timer invocations.\n");
        return false;
    }
    flx_set_assoc_object(manager, kFastLockXOnInvocationKey, onInvocation);
    flx_set_assoc_object(manager, kFastLockXUnlockInvocationKey, unlockInvocation);

    double tolerance = 0.05;
    uint64_t offTimer = 0;
    uint64_t onTimer = 0;
    uint64_t unlockTimer = 0;
    bool scheduledOff = flx_schedule_invocation_timer(manager,
                                                      kFastLockXOffTimerKey,
                                                      cycle,
                                                      tolerance,
                                                      offInvocation,
                                                      &offTimer);
    bool scheduledOn = flx_schedule_invocation_timer(manager,
                                                     kFastLockXOnTimerKey,
                                                     cycle,
                                                     tolerance,
                                                     scheduleOnInvocation,
                                                     &onTimer);

    bool scheduledUnlock = true;
    if (config.attemptUnlock) {
        scheduledUnlock = flx_schedule_invocation_timer(manager,
                                                        kFastLockXUnlockTimerKey,
                                                        cycle,
                                                        tolerance,
                                                        scheduleUnlockInvocation,
                                                        &unlockTimer);
    }

    uint64_t activeDate = flx_date(false);
    uint64_t pausedDate = flx_date(true);
    uint64_t pauseOff = flx_timer_firedate_invocation(offTimer, pausedDate);
    uint64_t pauseOn = flx_timer_firedate_invocation(onTimer, pausedDate);
    uint64_t pauseUnlock = config.attemptUnlock ? flx_timer_firedate_invocation(unlockTimer, pausedDate) : 0;
    uint64_t resumeOff = flx_timer_firedate_invocation(offTimer, activeDate);
    uint64_t resumeOn = flx_timer_firedate_invocation(onTimer, activeDate);
    uint64_t resumeUnlock = config.attemptUnlock ? flx_timer_firedate_invocation(unlockTimer, activeDate) : 0;
    uint64_t cancelOn = flx_cancel_delayed_invoke_invocation(onInvocation);
    uint64_t cancelUnlock = config.attemptUnlock ? flx_cancel_delayed_invoke_invocation(unlockInvocation) : 0;

    size_t pauseCount = sizeof(kFastLockXPauseNotifications) / sizeof(kFastLockXPauseNotifications[0]);
    size_t resumeCount = sizeof(kFastLockXResumeNotifications) / sizeof(kFastLockXResumeNotifications[0]);
    bool observersOK = r_is_objc_ptr(pauseOff) &&
                       r_is_objc_ptr(pauseOn) &&
                       r_is_objc_ptr(resumeOff) &&
                       r_is_objc_ptr(resumeOn) &&
                       r_is_objc_ptr(cancelOn);
    if (config.attemptUnlock) {
        observersOK &= r_is_objc_ptr(pauseUnlock) &&
                       r_is_objc_ptr(resumeUnlock) &&
                       r_is_objc_ptr(cancelUnlock);
    }
    observersOK &=
        flx_register_assoc_observer(manager, kFastLockXPauseOffObserverKey,
                                    pauseOff, kFastLockXPauseNotifications, pauseCount) &&
        flx_register_assoc_observer(manager, kFastLockXPauseOnObserverKey,
                                    pauseOn, kFastLockXPauseNotifications, pauseCount) &&
        flx_register_assoc_observer(manager, kFastLockXResumeOffObserverKey,
                                    resumeOff, kFastLockXResumeNotifications, resumeCount) &&
        flx_register_assoc_observer(manager, kFastLockXResumeOnObserverKey,
                                    resumeOn, kFastLockXResumeNotifications, resumeCount) &&
        flx_register_assoc_observer(manager, kFastLockXCancelOnObserverKey,
                                    cancelOn, kFastLockXPauseNotifications, pauseCount);
    if (config.attemptUnlock) {
        observersOK &=
            flx_register_assoc_observer(manager, kFastLockXPauseUnlockObserverKey,
                                        pauseUnlock, kFastLockXPauseNotifications, pauseCount) &&
            flx_register_assoc_observer(manager, kFastLockXResumeUnlockObserverKey,
                                        resumeUnlock, kFastLockXResumeNotifications, resumeCount) &&
            flx_register_assoc_observer(manager, kFastLockXCancelUnlockObserverKey,
                                        cancelUnlock, kFastLockXPauseNotifications, pauseCount);
    }

    if (activeNow) {
        flx_invoke_now(resumeOff);
        flx_invoke_now(resumeOn);
        flx_invoke_now(resumeUnlock);
    } else {
        flx_invoke_now(pauseOff);
        flx_invoke_now(pauseOn);
        flx_invoke_now(pauseUnlock);
        flx_invoke_now(cancelOn);
        flx_invoke_now(cancelUnlock);
    }

    ok = scheduledOff && scheduledOn && scheduledUnlock && observersOK;
    flx_release_remote_object(offInvocation);
    flx_release_remote_object(onInvocation);
    flx_release_remote_object(unlockInvocation);
    flx_release_remote_object(scheduleOnInvocation);
    flx_release_remote_object(scheduleUnlockInvocation);
    flx_release_remote_object(pauseOff);
    flx_release_remote_object(pauseOn);
    flx_release_remote_object(pauseUnlock);
    flx_release_remote_object(resumeOff);
    flx_release_remote_object(resumeOn);
    flx_release_remote_object(resumeUnlock);
    flx_release_remote_object(cancelOn);
    flx_release_remote_object(cancelUnlock);
    if (!ok) {
        flx_disable_always_on_in_session(FastLockXDisableLogFailedEnableCleanup);
        log_user("[FLX] Always On failed to schedule all timers.\n");
        return false;
    }

    gFastLockXAlwaysOnApplied = true;
    printf("[FLX] Always On timers enabled cycle=%.2f retry=%.2f unlockDelay=%.2f unlock=%d activeNow=%d localApplied=%d\n",
           cycle,
           retry,
           unlockDelay,
           config.attemptUnlock,
           activeNow,
           gFastLockXAlwaysOnApplied);
    log_user("[FLX] Always On timers enabled (cycle %.1fs, retry %.1fs); pulses pause after unlock. Disable or respring to stop.\n",
             cycle,
             retry);
    return true;
}

bool fastlockx_lite_probe_in_session(void)
{
    uint64_t bioUnlock = r_class("SBDashBoardBiometricUnlockController");
    uint64_t pearl = r_class("SBDashBoardPearlUnlockBehavior");
    uint64_t lockManagerCls = r_class("SBLockScreenManager");
    uint64_t biometricCls = r_class("SBUIBiometricResource");

    uint64_t lockManager = flx_shared_instance("SBLockScreenManager");
    uint64_t biometric = flx_shared_instance("SBUIBiometricResource");
    uint64_t coordinator = r_is_objc_ptr(lockManager) && r_responds(lockManager, "biometricAuthenticationCoordinator") ?
        r_msg2_main(lockManager, "biometricAuthenticationCoordinator", 0, 0, 0, 0) : 0;

    bool hasUnlock = r_is_objc_ptr(lockManager) &&
                     r_responds(lockManager, "unlockUIFromSource:withOptions:");
    bool hasRetryOff = r_is_objc_ptr(biometric) &&
                       r_responds(biometric, "noteScreenDidTurnOff");
    bool hasRetryOn = r_is_objc_ptr(biometric) &&
                      r_responds(biometric, "noteScreenWillTurnOn");
    bool hasCoordinatorIntent = r_is_objc_ptr(lockManager) &&
                                r_is_objc_ptr(coordinator) &&
                                r_responds(lockManager, "biometricAuthenticationCoordinator:requestsUnlockWithIntent:");
    bool hasMesaAttempt = r_is_objc_ptr(lockManager) &&
                          r_responds(lockManager, "_attemptUnlockWithPasscode:mesa:finishUIUnlock:");

    printf("[FLX] probe classes bioUnlock=0x%llx pearl=0x%llx lock=0x%llx biometric=0x%llx coordinator=0x%llx\n",
           bioUnlock, pearl, lockManagerCls, biometricCls, coordinator);
    log_user("[FLX] Probe: hook classes %s/%s, unlock=%d, retry off/on=%d/%d, coordinator=%d, mesaAttempt=%d.\n",
             r_is_objc_ptr(bioUnlock) ? "present" : "missing",
             r_is_objc_ptr(pearl) ? "present" : "missing",
             hasUnlock,
             hasRetryOff,
             hasRetryOn,
             hasCoordinatorIntent,
             hasMesaAttempt);
    flx_log_state("probe");
    return hasUnlock || hasCoordinatorIntent || hasMesaAttempt || (hasRetryOff && hasRetryOn);
}

bool fastlockx_lite_run_in_session(FastLockXLiteConfig config)
{
    printf("[FLX] run pulse=%d unlock=%d music=%d flash=%d lpm=%d diag=%d interval=%.2f\n",
           config.pulseBiometricRetry,
           config.attemptUnlock,
           config.blockOnMusic,
           config.blockOnFlashlight,
           config.blockOnLowPowerMode,
           config.diagnosticLogging,
           config.retryIntervalSeconds);

    if (config.blockOnMusic && flx_blocked_by_music()) return false;
    if (config.blockOnFlashlight && flx_blocked_by_flashlight()) return false;
    if (config.blockOnLowPowerMode && flx_blocked_by_low_power()) return false;

    bool any = false;
    bool ok = true;
    if (config.diagnosticLogging && (config.pulseBiometricRetry || config.attemptUnlock)) {
        flx_log_state("pre");
    }
    if (config.attemptUnlock) {
        any = true;
        ok &= flx_wake_for_unlock_attempt();
    }
    if (config.pulseBiometricRetry) {
        any = true;
        ok &= flx_pulse_biometric_retry(config.retryIntervalSeconds);
    }
    if (config.attemptUnlock) {
        any = true;
        bool modernOK = flx_attempt_biometric_unlock();
        bool directOK = false;
        if (!modernOK || config.diagnosticLogging) {
            if (modernOK) usleep(150000);
            directOK = flx_attempt_unlock();
        }
        if (config.diagnosticLogging) {
            flx_log_state("post");
        }
        ok &= (modernOK || directOK);
    }
    return any && ok;
}
