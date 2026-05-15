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

extern NSString * const kSettingsStatBarEnabled;
extern NSString * const kSettingsStatBarCelsius;
extern NSString * const kSettingsStatBarHideNet;

extern NSString * const kSettingsRSSIDisplayEnabled;
extern NSString * const kSettingsRSSIDisplayWifi;
extern NSString * const kSettingsRSSIDisplayCell;

extern NSString * const kSettingsAxonLiteEnabled;

extern NSString * const kSettingsLogUploadEnabled;

extern NSString * const kSettingsActionsDidCompleteNotification;

// Returns YES if the tweak whose master enable lives at `key` was successfully
// applied in this app session. Cleared on launch, on cleanup, and whenever the
// SpringBoard RemoteCall session goes away.
BOOL settings_tweak_is_applied(NSString *key);

void settings_register_defaults(void);
BOOL settings_device_supported(void);
void settings_run_actions(void);
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
// Installer's "Customize" row, the nav bar shows a left-side back button
// ("← <package name>") that pops Settings to root and switches the user
// back to the Installer tab — so the install action stays one tap away
// after customizing.
@property (nonatomic, copy, nullable) NSString *installerReturnPackageName;

// Current values for each configurable row in a settings section.
// Each entry: @{@"title": <label string>, @"value": <current value string>}.
// Returns empty array when the section has no configurable rows.
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)settingsSummaryForSection:(NSInteger)section;

@end
