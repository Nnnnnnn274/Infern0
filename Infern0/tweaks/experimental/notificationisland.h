//
//  notificationisland.h
//  Cyanide
//

#ifndef notificationisland_h
#define notificationisland_h

#import <stdbool.h>

bool notificationisland_apply_in_session(void);
bool notificationisland_tick_in_session(void);
bool notificationisland_show_sample_in_session(const char *title, const char *body);
bool notificationisland_stop_in_session(void);
void notificationisland_forget_remote_state(void);
bool notificationisland_has_remote_state(void);

#endif /* notificationisland_h */
