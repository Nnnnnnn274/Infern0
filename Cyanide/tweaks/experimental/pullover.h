#ifndef pullover_h
#define pullover_h

#include <stdbool.h>

bool pullover_apply_in_session(void);
bool pullover_stop_in_session(void);
void pullover_forget_remote_state(void);

#endif
