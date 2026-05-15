//
//  statbar.h
//  StatBar port: reads battery temp + free RAM in our app process, then
//  installs/updates a dedicated SpringBoard overlay UIWindow via the
//  remote-call bridge.
//

#ifndef statbar_h
#define statbar_h

#import <stdbool.h>

bool statbar_apply(bool celsius, bool hideNet);
bool statbar_apply_in_session(bool celsius, bool hideNet);
bool statbar_stop_in_session(void);
void statbar_forget_remote_state(void);
bool statbar_resident_agent_active(void);

#endif
