//
//  SettingsViewController.h
//  Cyanide
//

#import <UIKit/UIKit.h>

extern NSString * const kSettingsAutoRunKexploit;
extern NSString * const kSettingsRunSandboxEscape;
extern NSString * const kSettingsRunPatchSandboxExt;
extern NSString * const kSettingsKeepAlive;

extern NSString * const kSettingsSBCEnabled;
extern NSString * const kSettingsSBCDockIcons;
extern NSString * const kSettingsSBCCols;
extern NSString * const kSettingsSBCRows;
extern NSString * const kSettingsSBCHideLabels;

extern NSString * const kSettingsPowercuffEnabled;
extern NSString * const kSettingsPowercuffLevel;

extern NSString * const kSettingsDSDisableAppLibrary;
extern NSString * const kSettingsDSDisableIconFlyIn;
extern NSString * const kSettingsDSZeroWakeAnimation;
extern NSString * const kSettingsDSZeroBacklightFade;
extern NSString * const kSettingsDSDoubleTapToLock;

extern NSString * const kSettingsDSDragCoefficientEnabled;
extern NSString * const kSettingsDSDragCoefficientValue;

extern NSString * const kSettingsLayoutExtrasEnabled;
extern NSString * const kSettingsLayoutHomeExtraLeft;
extern NSString * const kSettingsLayoutHomeExtraRight;
extern NSString * const kSettingsLayoutHomeExtraTop;
extern NSString * const kSettingsLayoutHomeExtraBottom;
extern NSString * const kSettingsLayoutDockExtraHorizontal;
extern NSString * const kSettingsLayoutHomeScalePct;
extern NSString * const kSettingsLayoutDockScalePct;

extern NSString * const kSettingsStatBarEnabled;
extern NSString * const kSettingsStatBarCelsius;
extern NSString * const kSettingsStatBarShowNet;
extern NSString * const kSettingsStatBarShowCPU;
extern NSString * const kSettingsStatBarShowLabels;
extern NSString * const kSettingsStatBarNetworkOnly;
extern NSString * const kSettingsStatBarRefreshRateSec;

extern NSString * const kSettingsNSBarEnabled;
extern NSString * const kSettingsNSBarPosition;

extern NSString * const kSettingsNiceBarLiteEnabled;

extern NSString * const kSettingsRSSIDisplayEnabled;
extern NSString * const kSettingsRSSIDisplayWifi;
extern NSString * const kSettingsRSSIDisplayCell;

extern NSString * const kSettingsAxonLiteEnabled;

extern NSString * const kSettingsTypeBannerEnabled;
extern NSString * const kSettingsNotificationIslandEnabled;
extern NSString * const kSettingsAppSwitcherGridEnabled;
extern NSString * const kSettingsFastLockXLiteEnabled;

extern NSString * const kSettingsVelvetEnabled;
extern NSString * const kSettingsVelvetBgColor;
extern NSString * const kSettingsVelvetBorderColor;
extern NSString * const kSettingsVelvetBorderWidth;
extern NSString * const kSettingsVelvetTitleColor;
extern NSString * const kSettingsVelvetMessageColor;
extern NSString * const kSettingsVelvetDateColor;
extern NSString * const kSettingsVelvetCornerRadius;

extern NSString * const kSettingsCleanNCEnabled;
extern NSString * const kSettingsUnderTimeEnabled;
extern NSString * const kSettingsZeppelinLiteEnabled;
extern NSString * const kSettingsZeppelinLiteText;
extern NSString * const kSettingsCleanHomeScreenEnabled;
extern NSString * const kSettingsCleanHomeScreenHideBadges;
extern NSString * const kSettingsCleanHomeScreenHidePageDots;
extern NSString * const kSettingsCleanHomeScreenHideLabels;
extern NSString * const kSettingsRealCCEnabled;
extern NSString * const kSettingsRealCCDisableWiFi;
extern NSString * const kSettingsRealCCDisableBT;
extern NSString * const kSettingsCleanCCEnabled;
extern NSString * const kSettingsFUGapEnabled;
extern NSString * const kSettingsModuleSpacingEnabled;
extern NSString * const kSettingsSugarCaneEnabled;
extern NSString * const kSettingsBetterCCXIEnabled;
extern NSString * const kSettingsMagmaEnabled;
extern NSString * const kSettingsBetterCCIconsEnabled;
extern NSString * const kSettingsCCNoPlatterDimEnabled;
extern NSString * const kSettingsCCStatusEnabled;
extern NSString * const kSettingsHapticCCEnabled;
extern NSString * const kSettingsSecureCCEnabled;
extern NSString * const kSettingsHideLabelsEnabled;
extern NSString * const kSettingsFakeClockUpEnabled;
extern NSString * const kSettingsFakeClockUpSpeed;
extern NSString * const kSettingsPancakeEnabled;
extern NSString * const kSettingsCylinderLiteEnabled;
extern NSString * const kSettingsBarmojiEnabled;
extern NSString * const kSettingsRoundedIconsEnabled;
extern NSString * const kSettingsWatchLayoutEnabled;
extern NSString * const kSettingsBlurryBadgesEnabled;
extern NSString * const kSettingsSnapperEnabled;
extern NSString * const kSettingsPullOverEnabled;
extern NSString * const kSettingsAlkalineEnabled;
extern NSString * const kSettingsTweakLoaderEnabled;

extern NSString * const kSettingsGravityLiteEnabled;
extern NSString * const kSettingsGravityLiteDockEnabled;
extern NSString * const kSettingsGravityLiteMagnitudePct;
extern NSString * const kSettingsGravityLiteBouncePct;
extern NSString * const kSettingsGravityLiteFrictionPct;
extern NSString * const kSettingsGravityLiteResistancePct;

extern NSString * const kSettingsStageStripEnabled;

extern NSString * const kSettingsLocationSimLatitude;
extern NSString * const kSettingsLocationSimLongitude;
extern NSString * const kSettingsLocationSimAltitude;
extern NSString * const kSettingsLocationSimHorizontalAccuracy;
extern NSString * const kSettingsLocationSimHostProcess;

extern NSString * const kSettingsThemerEnabled;
extern NSString * const kSettingsThemerThemeID;
extern NSString * const kSettingsThemerCustomThemePath;
extern NSString * const kSettingsThemerCustomThemeName;

extern NSString * const kSettingsSnowBoardLiteEnabled;
extern NSString * const kSettingsSnowBoardLiteSelectedThemeID;

extern NSString * const kSettingsLiveWPEnabled;
extern NSString * const kSettingsLiveWPVideoPath;

extern NSString * const kSettingsQuickLoaderEnabled;

extern NSString * const kSettingsRepoTweaksEnabled;

extern NSString * const kSettingsExperimentalTweaksEnabled;

extern NSString * const kSettingsLogUploadEnabled;

extern NSString * const kSettingsActionsDidCompleteNotification;
extern NSString * const kSettingsActionsDidCompleteSuccessKey;
extern NSString * const kSettingsActionsDidCompleteMessageKey;

// Returns YES if the tweak whose master enable lives at `key` was successfully
// applied in this app session. Cleared on launch, on cleanup, and whenever the
// SpringBoard RemoteCall session goes away.
BOOL settings_tweak_is_applied(NSString *key);
void settings_mark_tweak_needs_apply(NSString *key);

void settings_register_defaults(void);
BOOL settings_device_supported(void);
// Opens the Contact email composer (MFMailComposeViewController if Mail is
// configured, else mailto: fallback) prefilled with the latest diagnostic log
// inline. Presented from `host`.
void cyanide_present_contact(UIViewController *host);
BOOL settings_apply_ota_disabled(BOOL disabled);
BOOL settings_themer_has_selected_theme(void);
NSString *settings_themer_selected_theme_display_name(void);
BOOL settings_snowboardlite_has_selected_theme(void);
NSString *settings_snowboardlite_selected_theme_display_name(void);

// Synchronously runs kexploit and writes/clears the NanoRegistry pairing-
// compatibility override using the four numbers currently in NSUserDefaults
// (kSettingsNanoMaxPairing, etc.). Returns YES on success.
BOOL settings_apply_nano_registry_now(BOOL apply);
BOOL settings_apply_call_recording_sound_disabled(BOOL disabled);
BOOL settings_apply_hide_home_bar_hidden(BOOL hidden);
BOOL settings_hide_home_bar_hidden(void);
void settings_note_hide_home_bar_respring_pending(void);
BOOL settings_hide_home_bar_respring_pending(void);
void settings_present_hide_home_bar_respring_prompt(UIViewController *host);

void settings_run_actions(void);
void settings_run_pending_actions(void);
void settings_destroy_springboard_remote_call(void);
void settings_destroy_springboard_remote_call_sync(void);
void settings_best_effort_termination_cleanup(const char *reason);
void settings_application_did_enter_background(void);
void settings_application_will_enter_foreground(void);
void settings_application_did_become_active(void);

@interface SettingsViewController : UITableViewController

// Detail-mode init: renders a single underlying section (one tweak bundle).
// Pass underlyingSection == NSIntegerMax for root-mode (default storyboard path).
- (instancetype)initWithUnderlyingSection:(NSInteger)underlyingSection
                              bundleTitle:(nullable NSString *)bundleTitle NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithStyle:(UITableViewStyle)style NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;

// When set on a bundle-detail SettingsViewController launched from the
// Packages' "Customize" row, the nav bar shows a left-side back button
// ("← <package name>") that pops Settings to root and switches the user
// back to the Packages tab — so the install action stays one tap away
// after customizing.
@property (nonatomic, copy, nullable) NSString *installerReturnPackageName;
@property (nonatomic, assign) BOOL quickLoaderStandalone;

// Current values for each configurable row in a settings section.
// Each entry: @{@"title": <label string>, @"value": <current value string>}.
// Returns empty array when the section has no configurable rows.
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)settingsSummaryForSection:(NSInteger)section;
+ (BOOL)liveWPHasSelectedVideo;

@end
