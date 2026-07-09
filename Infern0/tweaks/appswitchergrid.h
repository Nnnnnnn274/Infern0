//
//  appswitchergrid.h
//  Cyanide
//

#ifndef appswitchergrid_h
#define appswitchergrid_h

#import <stdbool.h>

bool appswitchergrid_apply_in_session(void);
bool appswitchergrid_stop_in_session(void);
void appswitchergrid_forget_remote_state(void);

#endif /* appswitchergrid_h */
