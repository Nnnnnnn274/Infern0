#ifndef hapticcc_h
#define hapticcc_h

#include <stdbool.h>

bool hapticcc_apply_in_session(void);
bool hapticcc_stop_in_session(void);
void hapticcc_forget_remote_state(void);

#endif
