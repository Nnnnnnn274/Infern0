//
//  stagestrip.h
//  StageStrip: a remote-call-only "lite" port of StageDuo / Stage Manager.
//  Installs a persistent UIWindow on the left edge of SpringBoard, populated
//  with thumbnails of the most-recent running apps. Tapping a thumbnail asks
//  SpringBoard to launch that bundle id via a hijacked NSString method whose
//  IMP points at SBSLaunchApplicationWithIdentifier (so we never inject any
//  new code into SpringBoard).
//
//  Limitations vs. the dylib version:
//   - No event-driven hooks. The strip is rebuilt only when the user re-runs
//     stagestrip_apply; it does not auto-refresh when the user opens an app
//     from outside the strip.
//   - Tap dispatch passes `suspended=YES` to SBSLaunchApplicationWithIdentifier
//     because the gesture-action SEL register (x1) is always non-zero. The
//     target app launches, but may come up backgrounded depending on iOS
//     version. Foreground-activation needs a different SpringBoard entry
//     point that has not been wired yet.
//

#ifndef stagestrip_h
#define stagestrip_h

#import <stdbool.h>

bool stagestrip_apply(int maxSlots);
bool stagestrip_apply_in_session(int maxSlots);
void stagestrip_set_deferred_library_build_enabled(bool enabled);
bool stagestrip_stop_in_session(void);
void stagestrip_start_control_loop(void);
void stagestrip_stop_control_loop(void);
void stagestrip_forget_remote_state(void);

#endif
