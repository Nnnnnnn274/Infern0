#ifndef sugarcane_h
#define sugarcane_h

#include <stdbool.h>

bool sugarcane_apply_in_session(void);
bool sugarcane_stop_in_session(void);
void sugarcane_forget_remote_state(void);

#endif
