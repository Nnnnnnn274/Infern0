#ifndef cylinderlite_h
#define cylinderlite_h

#include <stdbool.h>

bool cylinderlite_apply_in_session(void);
bool cylinderlite_stop_in_session(void);
void cylinderlite_configure(int depth, int perspectiveDistance, int maxIcons);
void cylinderlite_forget_remote_state(void);

#endif
