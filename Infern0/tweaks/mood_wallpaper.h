//
//  mood_wallpaper.h
//  Cyanide
//
//  Mood Wallpaper: switches between two still wallpapers based on left/right
//  device gravity while the SpringBoard RemoteCall session stays alive.
//

#ifndef mood_wallpaper_h
#define mood_wallpaper_h

#include <stdbool.h>
#import <Foundation/Foundation.h>

bool mood_wallpaper_apply_in_session(void);
bool mood_wallpaper_update_index_in_session(int targetIndex);
bool mood_wallpaper_stop_in_session(void);
void mood_wallpaper_forget_remote_state(void);
NSString *mood_wallpaper_absolute_path(NSString *relativePath);

#endif /* mood_wallpaper_h */
