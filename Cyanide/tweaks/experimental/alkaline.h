#ifndef alkaline_h
#define alkaline_h

#include <stdbool.h>

bool alkaline_apply_in_session(void);
bool alkaline_stop_in_session(void);
void alkaline_configure(int red, int green, int blue, int alphaPercent);
void alkaline_forget_remote_state(void);

#endif
