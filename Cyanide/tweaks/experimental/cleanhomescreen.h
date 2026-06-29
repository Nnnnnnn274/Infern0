#ifndef cleanhomescreen_h
#define cleanhomescreen_h

#include <stdbool.h>

bool cleanhomescreen_apply_in_session(bool hideBadges, bool hidePageDots, bool hideLabels);
bool cleanhomescreen_stop_in_session(void);
void cleanhomescreen_forget_remote_state(void);

#endif
