//
//  metal_lock_light.h
//  Cyanide
//
//  Experimental Metal light overlay for the lock screen.
//

#ifndef metal_lock_light_h
#define metal_lock_light_h

#include <stdbool.h>

bool metal_lock_light_apply_in_session(double colorIntensity, double reflectIntensity,
                                       int mode, const char *imagePath);
bool metal_lock_light_update_in_session(double colorIntensity, double reflectIntensity,
                                        double lightX, double lightY, int mode);
bool metal_lock_light_retry_wallpaper_source_in_session(void);
bool metal_lock_light_probe_wallpaper_layers_in_session(void);
bool metal_lock_light_stop_in_session(void);
void metal_lock_light_forget_remote_state(void);

#endif /* metal_lock_light_h */
