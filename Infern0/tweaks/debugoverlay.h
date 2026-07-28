//
//  debugoverlay.h
//  Cyanide
//

#ifndef debugoverlay_h
#define debugoverlay_h

#import <stdbool.h>

bool debugoverlay_apply_in_session(void);
bool debugoverlay_stop_in_session(void);
void debugoverlay_forget_remote_state(void);

#endif /* debugoverlay_h */
