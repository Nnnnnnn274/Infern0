//
//  killallapps.h
//  Iterates SBApplicationController's running applications inside SpringBoard
//  and asks SpringBoard to terminate each one except Cyanide / SpringBoard /
//  PineBoard via the same SBWorkspaceKillApplication path the App Switcher
//  uses on swipe-up.
//

#ifndef killallapps_h
#define killallapps_h

#import <stdbool.h>

// Soft-kills every running user app except Cyanide and a small system
// denylist. Mirrors App Switcher swipe-up (BKS exit reason 5).
//
// Must be called under settings_rc_lock() with a SpringBoard RemoteCall
// session already open (g_springboard_rc_ready). Returns true if the
// SpringBoard enumeration ran cleanly. outKilled gets the count of apps
// we asked SpringBoard to terminate.
bool killallapps_apply_in_session(int *outKilled);

// Drop cached SpringBoard-side state (function-slide cache). Call when the
// SpringBoard RemoteCall session is abandoned (e.g. SpringBoard restarted).
void killallapps_forget_remote_state(void);

#endif
