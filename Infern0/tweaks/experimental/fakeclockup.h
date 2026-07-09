#ifndef fakeclockup_h
#define fakeclockup_h

#include <stdbool.h>

bool fakeclockup_apply_in_session(double speedMultiplier);
bool fakeclockup_stop_in_session(void);
void fakeclockup_forget_remote_state(void);

#endif
