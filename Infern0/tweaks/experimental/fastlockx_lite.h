//
//  fastlockx_lite.h
//  Cyanide
//

#ifndef fastlockx_lite_h
#define fastlockx_lite_h

#import <stdbool.h>

typedef struct {
    bool pulseBiometricRetry;
    bool attemptUnlock;
    bool blockOnMusic;
    bool blockOnFlashlight;
    bool blockOnLowPowerMode;
    bool diagnosticLogging;
    double retryIntervalSeconds;
} FastLockXLiteConfig;

bool fastlockx_lite_probe_in_session(void);
bool fastlockx_lite_run_in_session(FastLockXLiteConfig config);
bool fastlockx_lite_enable_always_on_in_session(FastLockXLiteConfig config);
bool fastlockx_lite_set_always_on_active_in_session(bool active);
bool fastlockx_lite_attempt_unlock_in_session(bool diagnosticLogging);
bool fastlockx_lite_disable_always_on_in_session(void);
void fastlockx_lite_forget_remote_state(void);

#endif /* fastlockx_lite_h */
