#ifndef securecc_h
#define securecc_h

#include <stdbool.h>

bool securecc_apply_in_session(void);
bool securecc_stop_in_session(void);
void securecc_configure(bool showIndicator, int delayMs);
void securecc_forget_remote_state(void);

#endif
