//
//  axonlite.h
//  RemoteCall-only notification grouping overlay.
//

#ifndef axonlite_h
#define axonlite_h

#import <stdbool.h>

bool axonlite_apply_in_session(void);
bool axonlite_stop_in_session(void);
// Fast cleanup used when SpringBoard is about to die (respring, OTA toggle,
// terminal KRW cleanup). Skips the per-request _insertNotificationRequest:
// restore loop and the per-object release loop since SB will discard all of
// it. Reduces stop time from ~3 s to effectively zero RemoteCall traffic.
bool axonlite_stop_in_session_fast(void);
void axonlite_forget_remote_state(void);
bool axonlite_reset_selection_in_session(void);
bool axonlite_initial_cache_ready(void);

#endif /* axonlite_h */
