#ifndef magsafe_enabler_h
#define magsafe_enabler_h

#include <stdbool.h>

void magsafe_enabler_configure(int size,
                               int yPosition,
                               int ringWidth,
                               int animationDurationMs,
                               int backgroundAlphaPercent,
                               int accentStyle);
bool magsafe_enabler_apply_in_session(void);
bool magsafe_enabler_show(double batteryLevel);
bool magsafe_enabler_hide(void);
bool magsafe_enabler_stop_in_session(void);
void magsafe_enabler_forget_remote_state(void);

#endif
