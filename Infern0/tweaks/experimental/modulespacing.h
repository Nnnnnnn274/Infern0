#ifndef modulespacing_h
#define modulespacing_h

#include <stdbool.h>

bool modulespacing_apply_in_session(void);
bool modulespacing_stop_in_session(void);
void modulespacing_configure(int cornerRadius);
void modulespacing_forget_remote_state(void);

#endif
