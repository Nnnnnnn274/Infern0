#ifndef lockscreenoverlay_h
#define lockscreenoverlay_h

#include <stdbool.h>

void lockscreenoverlay_configure(int verticalOffset,
                                 int widthPercent,
                                 int accentStyle,
                                 int glassAlphaPercent,
                                 bool hideQuickActions,
                                 bool hidePageDots);
bool lockscreenoverlay_apply_in_session(void);
bool lockscreenoverlay_stop_in_session(void);
void lockscreenoverlay_forget_remote_state(void);

#endif /* lockscreenoverlay_h */
