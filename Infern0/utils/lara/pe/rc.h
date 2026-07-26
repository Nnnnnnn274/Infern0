//
//  rc.h
//  lara
//
//  Created by ruter on 21.04.26.
//

#ifndef rc_h
#define rc_h

#import "../TaskRop/RemoteCall.h"

#define status_bar_time_format lara_status_bar_time_format
#define hide_icon_labels lara_hide_icon_labels
#define enable_jit lara_enable_jit
#define set_dock_icon_count lara_set_dock_icon_count
#define five_icon_dock lara_five_icon_dock
#define enable_upside_down lara_enable_upside_down
#define enable_floating_dock lara_enable_floating_dock
#define enable_grid_app_switcher lara_enable_grid_app_switcher
#define enable_debug_overlay lara_enable_debug_overlay
#define enable_freaky_dog_overlay lara_enable_freaky_dog_overlay
#define move_freaky_dog_overlay lara_move_freaky_dog_overlay
#define disable_freaky_dog_overlay lara_disable_freaky_dog_overlay
#define get_performance_hud lara_get_performance_hud
#define set_performance_hud lara_set_performance_hud
#define wake_up_daemon lara_wake_up_daemon
#define euenabler_overwrite_eligibility lara_euenabler_overwrite_eligibility
#define euenabler_override_country_code lara_euenabler_override_country_code
#define patch_homescreen_grid lara_patch_homescreen_grid
#define youtube_tweak lara_youtube_tweak

typedef void (^rc_euenabler_callback_t)(double progress);

void status_bar_time_format(RemoteCall *proc, const char *dateFormat);
int hide_icon_labels(RemoteCall *proc);
int enable_jit(RemoteCall *proc, const char *bundleID);
int set_dock_icon_count(RemoteCall *proc, int count);
int five_icon_dock(RemoteCall *proc);
int enable_upside_down(RemoteCall *proc);
int enable_floating_dock(RemoteCall *proc);
int enable_grid_app_switcher(RemoteCall *proc);
int enable_debug_overlay(RemoteCall *proc);
uint64_t enable_freaky_dog_overlay(RemoteCall *proc);
int move_freaky_dog_overlay(RemoteCall *proc, uint64_t imageView, int x, int y, int width, int height);
int disable_freaky_dog_overlay(RemoteCall *proc);
int get_performance_hud(RemoteCall *proc);
int set_performance_hud(RemoteCall *proc, int selection);
void wake_up_daemon(RemoteCall *sb, NSString *daemon, NSString *frameworkContainingXPCSerice);
int euenabler_overwrite_eligibility(RemoteCall *proc);
void euenabler_override_country_code(RemoteCall *proc, rc_euenabler_callback_t callback);
bool patch_homescreen_grid(RemoteCall *proc, int cols, int rows);
void youtube_tweak(RemoteCall *proc);

#endif /* rc_h */
