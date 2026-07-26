//
//  watchlayout.h
//  Pressable, vertically scrolling Apple Watch-style Home Screen overlay.
//

#ifndef watchlayout_h
#define watchlayout_h

#include <stdbool.h>

void watchlayout_configure(int compactPercent, int iconScalePercent);
bool watchlayout_apply_in_session(void);
bool watchlayout_stop_in_session(void);
bool watchlayout_has_cached_state(void);
void watchlayout_forget_remote_state(void);

#endif
