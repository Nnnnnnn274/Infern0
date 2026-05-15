//
//  axonlite.h
//  RemoteCall-only notification grouping overlay.
//

#ifndef axonlite_h
#define axonlite_h

#import <stdbool.h>

bool axonlite_apply_in_session(void);
bool axonlite_stop_in_session(void);
void axonlite_forget_remote_state(void);
bool axonlite_reset_selection_in_session(void);

#endif /* axonlite_h */
