#ifndef cleannc_h
#define cleannc_h

#include <stdbool.h>

bool cleannc_apply_in_session(void);
bool cleannc_stop_in_session(void);
void cleannc_forget_remote_state(void);

#endif
