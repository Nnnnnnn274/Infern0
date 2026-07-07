#ifndef cleancc_h
#define cleancc_h

#include <stdbool.h>

bool cleancc_apply_in_session(void);
bool cleancc_stop_in_session(void);
void cleancc_forget_remote_state(void);

#endif
