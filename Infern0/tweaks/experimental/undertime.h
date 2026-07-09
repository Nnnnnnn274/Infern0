#ifndef undertime_h
#define undertime_h

#include <stdbool.h>

bool undertime_apply_in_session(void);
bool undertime_stop_in_session(void);
void undertime_forget_remote_state(void);

#endif
