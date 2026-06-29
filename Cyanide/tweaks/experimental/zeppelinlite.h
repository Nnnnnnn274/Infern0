#ifndef zeppelinlite_h
#define zeppelinlite_h

#include <stdbool.h>

bool zeppelinlite_apply_in_session(const char *carrierText);
bool zeppelinlite_stop_in_session(void);
void zeppelinlite_forget_remote_state(void);

#endif
