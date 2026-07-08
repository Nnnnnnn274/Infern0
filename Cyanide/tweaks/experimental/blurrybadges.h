#ifndef blurrybadges_h
#define blurrybadges_h

#include <stdbool.h>

bool blurrybadges_apply_in_session(void);
bool blurrybadges_stop_in_session(void);
void blurrybadges_configure(int red, int green, int blue, int alphaPercent);
void blurrybadges_forget_remote_state(void);

#endif
