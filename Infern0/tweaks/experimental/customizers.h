#ifndef customizers_h
#define customizers_h

#include <stdbool.h>

void lockcustomizer_configure(int clockScalePercent, int horizontalOffset, int verticalOffset,
                              bool hideQuickActions, bool hidePageDots, int contentAlphaPercent,
                              int mediaScalePercent, bool hideMediaArtwork,
                              bool metalLightEnabled, int metalLightIntensityPercent,
                              int metalLightThickness, int metalLightStyle);
bool lockcustomizer_apply_in_session(void);
bool lockcustomizer_stop_in_session(void);
void lockcustomizer_forget_remote_state(void);

#endif
