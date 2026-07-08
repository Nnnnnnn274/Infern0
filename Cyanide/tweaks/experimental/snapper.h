#ifndef snapper_h
#define snapper_h

#include <stdbool.h>

bool snapper_apply_in_session(void);
bool snapper_stop_in_session(void);
void snapper_configure(int x, int y, int width, int height, int borderWidth, int cornerRadius);
void snapper_forget_remote_state(void);

#endif
