#pragma once

#include <stdbool.h>

// Declarations retained only so stale UI code can compile while retired tweak
// implementations remain physically deleted. All functions resolve to safe no-ops.

void roundedicons_configure(int cornerRadius);
bool roundedicons_apply_in_session(void);
bool roundedicons_stop_in_session(void);
void roundedicons_forget_remote_state(void);
void freeplacement_configure(int horizontalStep, int verticalStep, int staggerPercent);
bool freeplacement_apply_in_session(void);
bool freeplacement_stop_in_session(void);
void freeplacement_forget_remote_state(void);
void applibrarystudio_configure(int iconScalePercent, int horizontalSpacing,
                                int verticalSpacing, bool hideLabels, bool disableTodayView);
bool applibrarystudio_apply_in_session(void);
bool applibrarystudio_stop_in_session(void);
void applibrarystudio_forget_remote_state(void);
bool darksword_drag_coefficient_apply(double coefficient);

//
//  QuickLoader.h
//

#ifndef QuickLoader_h
#define QuickLoader_h

#import <stdbool.h>
#import <Foundation/Foundation.h>

bool quickloader_apply_in_session();

bool quickloader_run_js_string(NSString *jsCode);

bool quickloader_stop_in_session(void);

bool quickloader_save_repo_tweak(NSString *repoURL,
                                 NSString *tweakID,
                                 NSString *displayName,
                                 NSString *rawScript,
                                 NSDictionary *values);
bool quickloader_is_repo_tweak_installed(NSString *repoURL, NSString *tweakID);
void quickloader_clear_repo_tweak_if_matches(NSString *repoURL, NSString *tweakID);
bool quickloader_refresh_active_repo_tweak(void);
bool quickloader_is_driven_by_repo_tweak(void);

#endif /* QuickLoader_h */
//
//  RepoTweaks.h
//

#ifndef RepoTweaks_h
#define RepoTweaks_h

#import <stdbool.h>
#import <Foundation/Foundation.h>

// Runs all enabled tweaks during the RUN 4/4 sequence
bool repotweaks_apply_in_session(void);

// Fetches the JSON from the given URL and caches it
void repotweaks_refresh_repo(NSString *repoURL, void (^completion)(BOOL success, NSString *message));
void repotweaks_seed_default_repos(void);
BOOL repotweaks_is_builtin_repo(NSString *repoURL);
NSString *repotweaks_builtin_repo_display_name(NSString *repoURL);

NSString *repotweaks_storage_key(NSString *repoURL, NSString *tweakId);
NSString *repotweaks_enabled_defaults_key(NSString *repoURL, NSString *tweakId);
NSString *repotweaks_script_defaults_key(NSString *repoURL, NSString *tweakId);
NSString *repotweaks_values_defaults_key(NSString *repoURL, NSString *tweakId);

// Downloads the raw .js code for a specific repository tweak
void repotweaks_download_script(NSString *repoURL, NSString *tweakId, NSString *scriptURL, void (^completion)(BOOL success));
BOOL repotweaks_download_script_sync(NSString *repoURL,
                                     NSString *tweakId,
                                     NSString *scriptURL,
                                     NSTimeInterval timeout,
                                     NSString **message);
void repotweaks_cancel_tweak(NSString *repoURL, NSString *tweakId);

bool repotweaks_stop_in_session(void);

void repotweaks_refresh_all_sources(void (^completion)(void));
NSUInteger repotweaks_available_update_count(void);
NSString *repotweaks_installed_version_key(NSString *repoURL, NSString *tweakId);
NSTimeInterval repotweaks_seen_timestamp(NSString *repoURL, NSString *tweakId);
NSComparisonResult repotweaks_compare_versions(NSString *a, NSString *b);
NSString *repotweaks_compatibility_note(NSDictionary *tweak);
NSString *repotweaks_unsupported_reason(NSDictionary *tweak);

extern NSString * const RepoTweaksDidRefreshNotification;

#endif /* RepoTweaks_h */
//
//  appswitchergrid.h
//  Cyanide
//

#ifndef appswitchergrid_h
#define appswitchergrid_h

#import <stdbool.h>

bool appswitchergrid_apply_in_session(void);
bool appswitchergrid_stop_in_session(void);
void appswitchergrid_forget_remote_state(void);

#endif /* appswitchergrid_h */
//
//  call_recording_sound.h
//  Cyanide
//

#ifndef call_recording_sound_h
#define call_recording_sound_h

#include <stdbool.h>

bool call_recording_sound_set_disabled(bool disabled);

#endif /* call_recording_sound_h */
#ifndef alkaline_h
#define alkaline_h

#include <stdbool.h>

bool alkaline_apply_in_session(void);
bool alkaline_stop_in_session(void);
void alkaline_configure(int red, int green, int blue, int alphaPercent);
void alkaline_forget_remote_state(void);

#endif
#ifndef betterccicons_h
#define betterccicons_h

#include <stdbool.h>

bool betterccicons_apply_in_session(void);
bool betterccicons_stop_in_session(void);
void betterccicons_configure(int cornerRadius);
void betterccicons_forget_remote_state(void);

#endif
#ifndef betterccxi_h
#define betterccxi_h

#include <stdbool.h>

bool betterccxi_apply_in_session(void);
bool betterccxi_stop_in_session(void);
void betterccxi_configure(int zLift, int depthLimit, int moduleScalePercent);
void betterccxi_forget_remote_state(void);

#endif
#ifndef blurrybadges_h
#define blurrybadges_h

#include <stdbool.h>

bool blurrybadges_apply_in_session(void);
bool blurrybadges_stop_in_session(void);
void blurrybadges_configure(int red, int green, int blue, int alphaPercent,
                            bool growEnabled, int maxScalePercent);
void blurrybadges_forget_remote_state(void);

#endif
#ifndef ccnoplatterdim_h
#define ccnoplatterdim_h

#include <stdbool.h>

bool ccnoplatterdim_apply_in_session(void);
bool ccnoplatterdim_stop_in_session(void);
void ccnoplatterdim_configure(int visibleAlphaPercent);
void ccnoplatterdim_forget_remote_state(void);

#endif
#ifndef ccstatus_h
#define ccstatus_h

#include <stdbool.h>

bool ccstatus_apply_in_session(void);
bool ccstatus_stop_in_session(void);
void ccstatus_configure(bool showWifi, bool showIP, int yOffset);
void ccstatus_forget_remote_state(void);

#endif
#ifndef cleancc_h
#define cleancc_h

#include <stdbool.h>

bool cleancc_apply_in_session(void);
bool cleancc_stop_in_session(void);
void cleancc_configure(int materialAlphaPercent, int glassTintPercent);
void cleancc_forget_remote_state(void);

#endif
#ifndef cleanhomescreen_h
#define cleanhomescreen_h

#include <stdbool.h>

bool cleanhomescreen_apply_in_session(bool hideBadges, bool hidePageDots, bool hideLabels);
bool cleanhomescreen_stop_in_session(void);
void cleanhomescreen_forget_remote_state(void);

#endif
#ifndef cleannc_h
#define cleannc_h

#include <stdbool.h>

bool cleannc_apply_in_session(void);
bool cleannc_stop_in_session(void);
void cleannc_forget_remote_state(void);

#endif
#ifndef fakeclockup_h
#define fakeclockup_h

#include <stdbool.h>

bool fakeclockup_apply_in_session(double speedMultiplier);
bool fakeclockup_stop_in_session(void);
void fakeclockup_forget_remote_state(void);

#endif
//
//  fastlockx_lite.h
//  Cyanide
//

#ifndef fastlockx_lite_h
#define fastlockx_lite_h

#import <stdbool.h>

typedef struct {
    bool pulseBiometricRetry;
    bool attemptUnlock;
    bool blockOnMusic;
    bool blockOnFlashlight;
    bool blockOnLowPowerMode;
    bool diagnosticLogging;
    double retryIntervalSeconds;
} FastLockXLiteConfig;

bool fastlockx_lite_probe_in_session(void);
bool fastlockx_lite_run_in_session(FastLockXLiteConfig config);
bool fastlockx_lite_enable_always_on_in_session(FastLockXLiteConfig config);
bool fastlockx_lite_set_always_on_active_in_session(bool active);
bool fastlockx_lite_attempt_unlock_in_session(bool diagnosticLogging);
bool fastlockx_lite_disable_always_on_in_session(void);
void fastlockx_lite_forget_remote_state(void);

#endif /* fastlockx_lite_h */
#ifndef fugap_h
#define fugap_h

#include <stdbool.h>

bool fugap_apply_in_session(void);
bool fugap_stop_in_session(void);
void fugap_configure(int yOffset);
void fugap_forget_remote_state(void);

#endif
#ifndef hapticcc_h
#define hapticcc_h

#include <stdbool.h>

bool hapticcc_apply_in_session(void);
bool hapticcc_stop_in_session(void);
void hapticcc_configure(int feedbackStyle);
void hapticcc_forget_remote_state(void);

#endif
#ifndef hidellabels_h
#define hidellabels_h

#include <stdbool.h>

bool hidellabels_apply_in_session(void);
bool hidellabels_stop_in_session(void);
void hidellabels_forget_remote_state(void);

#endif
//
//  ipadecryptor.h
//  Cyanide private/in-dev IPA decryptor scaffold.
//
//  Goal: keep the core "decrypt an installed FairPlay IPA" flow local to the
//  device. v0 wires app discovery + Mach-O encryption probing first; task-port
//  minting, mach_vm dumping, and IPA zip writing land behind the same API.
//

#ifndef ipadecryptor_h
#define ipadecryptor_h

#import <stdbool.h>

#ifdef __OBJC__
#import <Foundation/Foundation.h>

NSArray<NSDictionary<NSString *, NSString *> *> *ipadecryptor_installed_apps(void);
NSString *ipadecryptor_display_name_for_bundle(NSString *bundleID);
NSString *ipadecryptor_default_output_directory(void);
NSString *ipadecryptor_app_store_account_summary(void);
bool ipadecryptor_has_app_store_account(void);
bool ipadecryptor_login_app_store(NSString *email,
                                  NSString *password,
                                  NSString *authCode,
                                  NSString **messageOut);
void ipadecryptor_clear_app_store_account(void);

NSDictionary<NSString *, NSString *> *ipadecryptor_resolve_app_store_input(NSString *input,
                                                                           NSString **messageOut);
bool ipadecryptor_download_app_store_ipa(NSString *input,
                                         NSString **downloadedPathOut,
                                         NSString **messageOut);

bool ipadecryptor_probe_installed_app(NSString *bundleID, NSString **messageOut);
bool ipadecryptor_start_decrypt_installed_app(NSString *bundleID, NSString **messageOut);

#endif /* __OBJC__ */

#endif /* ipadecryptor_h */
#ifndef modulespacing_h
#define modulespacing_h

#include <stdbool.h>

bool modulespacing_apply_in_session(void);
bool modulespacing_stop_in_session(void);
void modulespacing_configure(int cornerRadius);
void modulespacing_forget_remote_state(void);

#endif
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
#ifndef pancake_h
#define pancake_h

#include <stdbool.h>

bool pancake_apply_in_session(void);
bool pancake_stop_in_session(void);
void pancake_configure(int minimumTouches, int maximumTouches, bool cancelsTouches);
void pancake_forget_remote_state(void);

#endif
#ifndef pullover_h
#define pullover_h

#include <stdbool.h>

bool pullover_apply_in_session(void);
bool pullover_stop_in_session(void);
void pullover_configure(int width, int yOffset, int maxHeight, int cornerRadius, int backgroundAlphaPercent);
void pullover_forget_remote_state(void);

#endif
#ifndef realcc_h
#define realcc_h

#include <stdbool.h>

bool realcc_apply(bool disableWifi, bool disableBt);
bool realcc_restore(void);

#endif
#ifndef securecc_h
#define securecc_h

#include <stdbool.h>

bool securecc_apply_in_session(void);
bool securecc_stop_in_session(void);
void securecc_configure(bool showIndicator, int delayMs);
void securecc_forget_remote_state(void);

#endif
#ifndef snapper_h
#define snapper_h

#include <stdbool.h>

bool snapper_apply_in_session(void);
bool snapper_capture_in_session(void);
bool snapper_clear_pins_in_session(void);
bool snapper_stop_in_session(void);
void snapper_configure(int x, int y, int width, int height, int borderWidth, int cornerRadius);
void snapper_forget_remote_state(void);

#endif
#ifndef sugarcane_h
#define sugarcane_h

#include <stdbool.h>

bool sugarcane_apply_in_session(void);
bool sugarcane_stop_in_session(void);
void sugarcane_configure(bool showBrightness, bool showVolume, int fontSize);
void sugarcane_forget_remote_state(void);

#endif
#ifndef tweakloader_h
#define tweakloader_h

#include <stdbool.h>

typedef bool (*tweakloader_func_t)(void);

void tweakloader_register(const char *name, tweakloader_func_t apply, tweakloader_func_t stop);
void tweakloader_reload_list(void);
unsigned int tweakloader_loaded_count(void);
const char *tweakloader_name_at(unsigned int index);
bool tweakloader_apply_at(unsigned int index);
bool tweakloader_stop_at(unsigned int index);
bool tweakloader_apply_in_session(void);
bool tweakloader_stop_in_session(void);
void tweakloader_forget_remote_state(void);

#endif
#ifndef undertime_h
#define undertime_h

#include <stdbool.h>

bool undertime_apply_in_session(void);
bool undertime_stop_in_session(void);
void undertime_forget_remote_state(void);

#endif
#ifndef velvet_h
#define velvet_h

#import <stdbool.h>

typedef struct {
    bool  hasValue;
    double r, g, b, a;
} VelvetRGBA;

typedef struct {
    VelvetRGBA bgColor;
    VelvetRGBA borderColor;
    double    borderWidth;
    VelvetRGBA titleColor;
    VelvetRGBA messageColor;
    VelvetRGBA dateColor;
    double    cornerRadius;
    bool      hasCornerRadius;
    double    bannerScale;
    double    bannerAlpha;
    bool      edgeGlowEnabled;
    bool      edgeGlowTopOnly;
    VelvetRGBA edgeGlowColor;
    double    edgeGlowThickness;
} VelvetStyle;

bool velvet_apply_in_session(void);
bool velvet_tick_in_session(void);
bool velvet_stop_in_session(void);
void velvet_forget_remote_state(void);
bool velvet_has_remote_state(void);

void velvet_set_global_style(const VelvetStyle *style);

#endif
#ifndef zeppelinlite_h
#define zeppelinlite_h

#include <stdbool.h>

bool zeppelinlite_apply_in_session(const char *carrierText);
bool zeppelinlite_stop_in_session(void);
void zeppelinlite_forget_remote_state(void);

#endif
//
//  hide_home_bar.h
//  Cyanide
//

#ifndef hide_home_bar_h
#define hide_home_bar_h

#include <stdbool.h>

bool hide_home_bar_apply(void);
bool hide_home_bar_restore(void);

#endif /* hide_home_bar_h */
//
//  livewp.h
//  LiveWP (Live Wallpaper): plays a user-selected video as a dynamic wallpaper
//  on the lock screen and home screen via RemoteCall.
//  Adapted from https://github.com/d1y/cyanide-ios (AGPL-3.0).
//

#ifndef livewp_h
#define livewp_h

#import <stdbool.h>
#import <Foundation/Foundation.h>

// 标准 Tweak 入口点
bool livewp_apply_in_session(void);
bool livewp_repair_in_session(void);
bool livewp_pause_in_session(void);
bool livewp_resume_in_session(void);
bool livewp_stop_in_session(void);
void livewp_forget_remote_state(void);
bool livewp_swap_video_in_session(NSString *videoPath);
NSString *livewp_absolute_path(void);
NSArray<NSString *> *livewp_mood_absolute_paths(void);

#endif
//
//  location_sim.h
//  Cyanide
//
//  CoreLocation simulation driver.
//

#ifndef location_sim_h
#define location_sim_h

#include <stdbool.h>

typedef struct {
    double latitude;
    double longitude;
    double altitude;
    double horizontalAccuracy;
    double verticalAccuracy;
    const char *hostProcess;
    bool launchHost;
} LocationSimConfig;

bool locationsim_apply_static(const LocationSimConfig *config);
bool locationsim_apply_strict_hosts(const LocationSimConfig *config);
bool locationsim_stop(const char *hostProcess, bool launchHost);
bool locationsim_stop_strict_hosts(const char *hostProcess, bool launchHost);

#endif /* location_sim_h */
//
//  nicebarlite.h
//  NiceBar Lite: status-bar text slots.
//  Adapted from https://github.com/d1y/cyanide-ios (AGPL-3.0).
//

#ifndef nicebarlite_h
#define nicebarlite_h

#import <stdbool.h>
#import <stdint.h>
#ifdef __OBJC__
#import <Foundation/Foundation.h>
#endif

typedef enum {
    NiceBarLiteSlotTopLeft = 0,
    NiceBarLiteSlotTopRight = 1,
    NiceBarLiteSlotBottomLeft = 2,
    NiceBarLiteSlotBottomRight = 3,
    NiceBarLiteSlotBottomCenter = 4,
    NiceBarLiteSlotCount = 5
} NiceBarLiteSlot;

typedef enum {
    NiceBarLiteContentOff = 0,
    NiceBarLiteContentCustomText = 1,
    NiceBarLiteContentSystem = 2,
    NiceBarLiteContentTimeFormat = 3,
    NiceBarLiteContentWeather = 4
} NiceBarLiteContentKind;

typedef enum {
    NiceBarLiteSystemBatteryTemp = 0,
    NiceBarLiteSystemFreeRAM = 1,
    NiceBarLiteSystemBatteryPercent = 2,
    NiceBarLiteSystemNetworkSpeed = 3,
    NiceBarLiteSystemUptime = 4,
    NiceBarLiteSystemDate = 5,
    NiceBarLiteSystemLunarDate = 6,
    NiceBarLiteSystemTodayTraffic = 7,
    NiceBarLiteSystemCurrentIP = 8,
    NiceBarLiteSystemFreeDisk = 9,
    NiceBarLiteSystemThermalState = 10,
    NiceBarLiteSystemLast = NiceBarLiteSystemThermalState
} NiceBarLiteSystemItem;

typedef struct {
    int kind;
    int systemItem;
    const char *customText;
    const char *timeFormat;
    const char *weatherText;
    const char *systemLanguage;
} NiceBarLiteSlotConfig;

typedef struct {
    NiceBarLiteSlotConfig slots[NiceBarLiteSlotCount];
    bool celsius;
    uint32_t updateMask;
    double topSideInsetOffset;
    double bottomSideInsetOffset;
    double topYOffset;
    double bottomYOffset;
    double centerXOffset;
} NiceBarLiteConfig;

bool nicebarlite_apply_in_session(NiceBarLiteConfig config);
bool nicebarlite_stop_in_session(void);
void nicebarlite_forget_remote_state(void);

#ifdef __OBJC__
NSString *nicebarlite_format_traffic_bytes(uint64_t bytes);
NSString *nicebarlite_traffic_store_path(void);
NSDictionary<NSString *, NSString *> *nicebarlite_traffic_history_snapshot(void);
#endif

#endif /* nicebarlite_h */
//
//  nsbar.h
//  NSBar: Network Speed Bar - displays real-time network speed in status bar area
//  Adapted from https://github.com/d1y/cyanide-ios (AGPL-3.0).
//

#ifndef nsbar_h
#define nsbar_h

#import <stdbool.h>

typedef enum {
    NSBarPositionTopLeft = 0,
    NSBarPositionBottomLeft = 1,
    NSBarPositionTopRight = 2,
    NSBarPositionBottomRight = 3,
    NSBarPositionCenter = 4
} NSBarPosition;

bool nsbar_apply_in_session(NSBarPosition position);
bool nsbar_stop_in_session(void);
void nsbar_forget_remote_state(void);

#endif
//
//  snowboardlite.h
//  Cyanide
//  Adapted from https://github.com/d1y/cyanide-ios (AGPL-3.0).
//

#ifndef snowboardlite_h
#define snowboardlite_h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <stdbool.h>

extern NSString * const kSnowBoardLiteThemeBuiltinIOS6;

NSArray<NSDictionary *> *settings_sbl_load_manifest(void);
BOOL settings_sbl_save_manifest(NSArray<NSDictionary *> *themes);
NSDictionary *settings_sbl_selected_theme(void);
BOOL settings_sbl_selected_builtin_ios6(void);
NSString *settings_sbl_resolved_icons_path_for_theme(NSDictionary *theme);
NSArray<UIImage *> *settings_sbl_preview_images_for_theme(NSDictionary *theme,
                                                          BOOL builtIn,
                                                          NSUInteger limit);
BOOL settings_sbl_import_folder_theme_named(NSURL *url,
                                            NSString *displayName,
                                            NSString *sourceType,
                                            NSError **error);
BOOL settings_sbl_import_folder_theme(NSURL *url, NSError **error);
bool settings_apply_snowboardlite_from_defaults_locked(NSUserDefaults *d);

BOOL settings_snowboardlite_has_selected_theme(void);
NSString *settings_snowboardlite_selected_theme_display_name(void);

#endif /* snowboardlite_h */
