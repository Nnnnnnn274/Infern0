//
//  darksword_tweaks.h
//

#ifndef darksword_tweaks_h
#define darksword_tweaks_h

#import <stdbool.h>

bool darksword_tweak_disable_app_library_in_session(void);
bool darksword_tweak_disable_icon_fly_in_in_session(void);
bool darksword_tweak_zero_wake_animation_in_session(void);
bool darksword_tweak_zero_backlight_fade_in_session(void);
bool darksword_tweak_double_tap_to_lock_in_session(void);

bool darksword_tweaks_apply_in_session(bool disableAppLibrary,
                                       bool disableIconFlyIn,
                                       bool zeroWakeAnimation,
                                       bool zeroBacklightFade,
                                       bool doubleTapToLock);

#endif
