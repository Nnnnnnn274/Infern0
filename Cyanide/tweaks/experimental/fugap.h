#ifndef fugap_h
#define fugap_h

#include <stdbool.h>

bool fugap_apply_in_session(void);
bool fugap_stop_in_session(void);
void fugap_forget_remote_state(void);

#endif
