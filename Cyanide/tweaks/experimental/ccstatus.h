#ifndef ccstatus_h
#define ccstatus_h

#include <stdbool.h>

bool ccstatus_apply_in_session(void);
bool ccstatus_stop_in_session(void);
void ccstatus_forget_remote_state(void);

#endif
