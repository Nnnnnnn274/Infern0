//
//  upsidedown.h
//  Cyanide
//

#ifndef upsidedown_h
#define upsidedown_h

#import <stdbool.h>

bool upsidedown_apply_in_session(void);
bool upsidedown_stop_in_session(void);
void upsidedown_forget_remote_state(void);

#endif /* upsidedown_h */
