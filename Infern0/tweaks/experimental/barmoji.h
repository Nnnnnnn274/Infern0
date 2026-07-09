#ifndef barmoji_h
#define barmoji_h

#include <stdbool.h>

bool barmoji_apply_in_session(void);
bool barmoji_stop_in_session(void);
void barmoji_configure(int yOffset, int widthPercent, int fontSize, int backgroundAlphaPercent);
void barmoji_forget_remote_state(void);

#endif
