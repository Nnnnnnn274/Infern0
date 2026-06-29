#ifndef pancake_h
#define pancake_h

#include <stdbool.h>

bool pancake_apply_in_session(void);
bool pancake_stop_in_session(void);
void pancake_forget_remote_state(void);

#endif
