#ifndef magma_h
#define magma_h

#include <stdbool.h>

bool magma_apply_in_session(void);
bool magma_stop_in_session(void);
void magma_configure(int red, int green, int blue, int alpha,
                     bool colorToggles, bool colorSliders, bool colorMedia, bool colorBackground);
void magma_forget_remote_state(void);

#endif
