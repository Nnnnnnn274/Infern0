//
//  macaronlite.h
//  infern0
//
//  Session-only Home Screen chrome customizer inspired by Macaron.
//

#ifndef macaronlite_h
#define macaronlite_h

#import <stdbool.h>

typedef enum {
    MacaronLiteModeSolid = 0,
    MacaronLiteModeGradient = 1,
    MacaronLiteModePhoto = 2,
    MacaronLiteModeTransparent = 3,
} MacaronLiteMode;

void macaronlite_configure(MacaronLiteMode mode,
                           int opacityPct,
                           bool keepBlur,
                           bool styleDock,
                           bool styleFolders,
                           bool stylePageDots,
                           bool styleSearchPill,
                           const char *primaryHex,
                           const char *secondaryHex,
                           const char *photoPath);
bool macaronlite_apply_in_session(void);
bool macaronlite_stop_in_session(void);
void macaronlite_forget_remote_state(void);

#endif /* macaronlite_h */
