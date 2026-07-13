#ifndef iconstyles_h
#define iconstyles_h

#include <stdbool.h>

void roundedicons_configure(int cornerRadius);
bool roundedicons_apply_in_session(void);
bool roundedicons_stop_in_session(void);
void roundedicons_forget_remote_state(void);

void watchlayout_configure(int compactPercent, int iconScalePercent);
bool watchlayout_apply_in_session(void);
bool watchlayout_stop_in_session(void);
void watchlayout_forget_remote_state(void);

#endif
