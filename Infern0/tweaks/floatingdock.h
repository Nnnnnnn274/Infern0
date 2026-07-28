//
//  floatingdock.h
//  Cyanide
//

#ifndef floatingdock_h
#define floatingdock_h

#import <stdbool.h>

bool floatingdock_apply_in_session(void);
bool floatingdock_stop_in_session(void);
void floatingdock_forget_remote_state(void);

#endif /* floatingdock_h */
