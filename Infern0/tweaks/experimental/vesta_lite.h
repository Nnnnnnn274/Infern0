#ifndef vesta_lite_h
#define vesta_lite_h

#include <stdbool.h>

// Uses the historical PullOver preference keys so existing installs migrate
// to the community-requested Vesta Lite drawer without orphaned settings.
void pullover_configure(int width, int yOffset, int maxHeight,
                        int cornerRadius, int backgroundAlphaPercent);
bool pullover_apply_in_session(void);
bool pullover_stop_in_session(void);
void pullover_forget_remote_state(void);

#endif
