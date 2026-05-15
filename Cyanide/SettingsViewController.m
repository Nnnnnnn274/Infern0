//
//  SettingsViewController.m
//  Cyanide
//

#import "SettingsViewController.h"
#import "kexploit/kexploit_opa334.h"
#import "tweaks/sbcustomizer.h"
#import "tweaks/powercuff.h"
#import "tweaks/statbar.h"
#import "tweaks/rssidisplay.h"
#import "tweaks/axonlite.h"
#import "tweaks/darksword_tweaks.h"
#import "tweaks/darksword_ota.h"
#import "DSKeepAlive.h"
#import "TaskRop/RemoteCall.h"
#import "kexploit/kutils.h"
#import "installer/InstallProgressViewController.h"
#import "installer/Package.h"
#import "installer/PackageCatalog.h"
#import "installer/PackageQueue.h"
#import <WebKit/WebKit.h>
#import <notify.h>
#import <sys/utsname.h>
#import <time.h>
#import <unistd.h>

@interface DSRespringViewController : UIViewController <WKNavigationDelegate>
@property (nonatomic, strong) WKWebView *webView;
@end

@implementation DSRespringViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.043 green:0.043 blue:0.063 alpha:1.0];
    self.title = @"Respring";

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                      target:self
                                                      action:@selector(dismissSelf)];

    WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
    cfg.allowsInlineMediaPlayback = YES;
    self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:cfg];
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    self.webView.navigationDelegate = self;
    self.webView.opaque = NO;
    self.webView.backgroundColor = self.view.backgroundColor;
    self.webView.scrollView.backgroundColor = self.view.backgroundColor;
    [self.view addSubview:self.webView];
    [NSLayoutConstraint activateConstraints:@[
        [self.webView.topAnchor      constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.webView.bottomAnchor   constraintEqualToAnchor:self.view.bottomAnchor],
        [self.webView.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor],
        [self.webView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];

    NSURL *url = [NSURL URLWithString:@"https://zeroxjf.github.io/lightsaber/respring.html"];
    [self.webView loadRequest:[NSURLRequest requestWithURL:url
                                              cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData
                                          timeoutInterval:10]];
}

- (void)dismissSelf {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    printf("[RESPRING] navigation failed: %s\n", error.localizedDescription.UTF8String);
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    printf("[RESPRING] provisional navigation failed: %s\n", error.localizedDescription.UTF8String);
}

@end

NSString * const kSettingsAutoRunKexploit    = @"AutoRunKexploit";
NSString * const kSettingsRunSandboxEscape   = @"RunSandboxEscape";
NSString * const kSettingsRunPatchSandboxExt = @"RunPatchSandboxExt";
NSString * const kSettingsKeepAlive          = @"KeepAlive";

NSString * const kSettingsSBCEnabled    = @"SBCEnabled";
NSString * const kSettingsSBCDockIcons  = @"SBCDockIcons";
NSString * const kSettingsSBCCols       = @"SBCCols";
NSString * const kSettingsSBCRows       = @"SBCRows";
NSString * const kSettingsSBCHideLabels = @"SBCHideLabels";

NSString * const kSettingsPowercuffEnabled = @"PowercuffEnabled";
NSString * const kSettingsPowercuffLevel   = @"PowercuffLevel";

NSString * const kSettingsDSDisableAppLibrary = @"DSDisableAppLibrary";
NSString * const kSettingsDSDisableIconFlyIn  = @"DSDisableIconFlyIn";
NSString * const kSettingsDSZeroWakeAnimation = @"DSZeroWakeAnimation";
NSString * const kSettingsDSZeroBacklightFade = @"DSZeroBacklightFade";
NSString * const kSettingsDSDoubleTapToLock   = @"DSDoubleTapToLock";

NSString * const kSettingsStatBarEnabled = @"StatBarEnabled";
NSString * const kSettingsStatBarCelsius = @"StatBarCelsius";
NSString * const kSettingsStatBarHideNet = @"StatBarHideNet";

NSString * const kSettingsRSSIDisplayEnabled = @"RSSIDisplayEnabled";
NSString * const kSettingsRSSIDisplayWifi    = @"RSSIDisplayWifi";
NSString * const kSettingsRSSIDisplayCell    = @"RSSIDisplayCell";

NSString * const kSettingsAxonLiteEnabled = @"AxonLiteEnabled";

NSString * const kSettingsLogUploadEnabled = @"LogUploadEnabled";

static void cyanide_upload_log_if_enabled(void);

extern int  escape_sbx_demo2(void);
extern int  escape_sbx_demo2_in_session(void);
extern int  escape_sbx_demo3(void);

static BOOL g_kexploit_done = NO;
static volatile int g_settings_actions_running = 0;
static volatile int g_settings_actions_rerun_requested = 0;
static volatile int g_springboard_rc_ready = 0;
static volatile int g_springboard_sandbox_escaped = 0;
static volatile int g_statbar_live_running = 0;
static volatile int g_statbar_live_stop_requested = 0;
static volatile int g_rssi_live_running = 0;
static volatile int g_rssi_live_stop_requested = 0;
static volatile int g_axonlite_live_running = 0;
static volatile int g_axonlite_live_stop_requested = 0;
static volatile int g_app_in_background = 0;
static volatile int g_screen_awake = 1;
static volatile int g_settings_termination_cleanup_started = 0;
static volatile int g_settings_cleanup_running = 0;
static volatile uint64_t g_sbc_live_apply_generation = 0;
static UIBackgroundTaskIdentifier g_statbar_bg_task = (UIBackgroundTaskIdentifier)-1;
static int g_springboard_blanked_notify_token = NOTIFY_TOKEN_INVALID;
static int g_display_status_notify_token = NOTIFY_TOKEN_INVALID;
static int g_springboard_finished_startup_notify_token = NOTIFY_TOKEN_INVALID;
static const NSInteger kSBCDefaultDockIcons = 4;
static const NSInteger kSBCDefaultCols = 4;
static const NSInteger kSBCDefaultRows = 6;
static const BOOL kSBCDefaultHideLabels = NO;
static const useconds_t kStatBarLiveIntervalUS = 1000000;
static const useconds_t kStatBarLiveBackgroundIntervalUS = 1000000;
static const NSUInteger kStatBarLiveMaxTicks = 43200;
static const int64_t kLiveBackgroundTaskGraceSeconds = 10;
static const useconds_t kRSSILiveIntervalUS = 1000000;
static const useconds_t kRSSILiveBackgroundIntervalUS = 1000000;
static const NSUInteger kRSSILiveMaxTicks = 43200;
static const useconds_t kAxonLiteLiveIntervalUS = 1200000;
static const useconds_t kAxonLiteLiveBackgroundIntervalUS = 1200000;
static const NSUInteger kAxonLiteLiveMaxTicks = 43200;
static NSString * const kSettingsRemoteCallStateDidChangeNotification = @"SettingsRemoteCallStateDidChangeNotification";
NSString * const kSettingsActionsDidCompleteNotification = @"SettingsActionsDidCompleteNotification";
static NSArray<NSString *> * const kPowercuffLevels = nil;

// Session-scoped record of which tweaks were actually applied since launch.
// Distinct from the persisted NSUserDefaults enable flag — these are wiped on
// app launch and whenever the SpringBoard RemoteCall session is torn down, so
// the UI can show accurate "Installed" state rather than a stale toggle.
static NSMutableSet<NSString *> *g_applied_tweak_keys = nil;

static NSMutableSet<NSString *> *settings_applied_keys_set(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        g_applied_tweak_keys = [NSMutableSet set];
    });
    return g_applied_tweak_keys;
}

static void settings_mark_tweak_applied(NSString *key, BOOL applied)
{
    if (!key) return;
    NSMutableSet *set = settings_applied_keys_set();
    @synchronized (set) {
        if (applied) [set addObject:key];
        else         [set removeObject:key];
    }
}

BOOL settings_tweak_is_applied(NSString *key)
{
    if (!key) return NO;
    NSMutableSet *set = settings_applied_keys_set();
    @synchronized (set) {
        return [set containsObject:key];
    }
}

static BOOL settings_clear_all_applied_locked(void)
{
    NSMutableSet *set = settings_applied_keys_set();
    BOOL changed = NO;
    @synchronized (set) {
        if (set.count > 0) {
            [set removeAllObjects];
            changed = YES;
        }
    }
    return changed;
}

static NSArray<NSString *> *settings_rc_backed_tweak_keys(void)
{
    static NSArray<NSString *> *keys = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = @[
            kSettingsSBCEnabled,
            kSettingsStatBarEnabled,
            kSettingsRSSIDisplayEnabled,
            kSettingsAxonLiteEnabled,
            kSettingsPowercuffEnabled,
            kSettingsDSDisableAppLibrary,
            kSettingsDSDisableIconFlyIn,
            kSettingsDSZeroWakeAnimation,
            kSettingsDSZeroBacklightFade,
            kSettingsDSDoubleTapToLock,
        ];
    });
    return keys;
}

static void settings_reconcile_applied_from_defaults(void)
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    for (NSString *key in settings_rc_backed_tweak_keys()) {
        if (![d boolForKey:key]) settings_mark_tweak_applied(key, NO);
    }
}

static void settings_notify_package_queue_changed_async(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:PackageQueueDidChangeNotification
                                                            object:[PackageQueue sharedQueue]];
    });
}

static NSObject *settings_rc_lock(void) {
    static NSObject *lock = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        lock = [NSObject new];
    });
    return lock;
}

static NSObject *settings_bg_lock(void) {
    static NSObject *lock = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        lock = [NSObject new];
    });
    return lock;
}

static uint64_t settings_now_us(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 0;
    return ((uint64_t)ts.tv_sec * 1000000ULL) + ((uint64_t)ts.tv_nsec / 1000ULL);
}

static void settings_apply_statbar_once_async(const char *reason);
static void settings_apply_rssi_once_async(const char *reason);
static void settings_start_rssi_live_loop(void);
static void settings_notify_remote_call_state_changed(void);
static void settings_request_all_live_loops_stop(const char *reason);

static BOOL settings_should_log_statbar_tick(NSUInteger tick) {
    // One-shot: log the very first tick so the user can see the loop took
    // off, then go silent forever. The polling continues; we just stop
    // narrating it.
    return tick == 0;
}

static useconds_t settings_live_interval(useconds_t foregroundUS, useconds_t backgroundUS)
{
    return (g_app_in_background != 0) ? backgroundUS : foregroundUS;
}

static const char *settings_live_context(void)
{
    return (g_app_in_background != 0) ? "background" : "foreground";
}

static BOOL settings_app_state_is_foreground(void)
{
    UIApplicationState state = [UIApplication sharedApplication].applicationState;
    return state == UIApplicationStateActive || state == UIApplicationStateInactive;
}

static NSUInteger settings_live_failure_limit(NSUInteger foregroundLimit)
{
    return (g_app_in_background != 0 || g_screen_awake == 0) ? 1 : foregroundLimit;
}

static BOOL settings_rssi_install_allowed(void)
{
    return NO;
}

static BOOL settings_read_screen_awake(void)
{
    BOOL haveState = NO;
    BOOL awake = YES;

    if (g_springboard_blanked_notify_token != NOTIFY_TOKEN_INVALID) {
        uint64_t state = 0;
        if (notify_get_state(g_springboard_blanked_notify_token, &state) == NOTIFY_STATUS_OK) {
            haveState = YES;
            awake = (state == 0);
        }
    }

    if (!haveState && g_display_status_notify_token != NOTIFY_TOKEN_INVALID) {
        uint64_t state = 0;
        if (notify_get_state(g_display_status_notify_token, &state) == NOTIFY_STATUS_OK) {
            awake = (state != 0);
        }
    }

    return awake;
}

static BOOL settings_screen_awake_cached(void)
{
    return g_screen_awake != 0;
}

static BOOL settings_refresh_screen_awake_state(const char *reason)
{
    BOOL awake = settings_read_screen_awake();
    int newValue = awake ? 1 : 0;
    int old = __sync_lock_test_and_set(&g_screen_awake, newValue);
    if (old != newValue) {
        printf("[SETTINGS] screen state=%s%s%s\n",
               awake ? "awake" : "asleep",
               reason ? " via " : "",
               reason ?: "");
    }
    return old == 0 && newValue != 0;
}

static BOOL settings_statbar_screen_awake(void)
{
    (void)settings_refresh_screen_awake_state(NULL);
    return settings_screen_awake_cached();
}

static void settings_handle_springboard_restart(void)
{
    // SpringBoard just (re)started. Every pointer we cached from the previous
    // SB incarnation — class addresses, selector slots, retained objects,
    // ivar offsets, the trojan thread, our shmem map — is stale. Calling
    // through any of them under SB-2 hands a wild signed function pointer to
    // BLRAA and PAC-faults us. Drop everything before the next loop tick.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL hadSession = NO;
        @synchronized (settings_rc_lock()) {
            hadSession = (g_springboard_rc_ready != 0);
            // Tell live loops to bail at their next interval check.
            settings_request_all_live_loops_stop("SpringBoard restart");
            g_springboard_rc_ready = 0;
            g_springboard_sandbox_escaped = 0;

            statbar_forget_remote_state();
            rssidisplay_forget_remote_state();
            axonlite_forget_remote_state();
            if (hadSession) {
                abandon_remote_call();
            }
        }
        printf("[SETTINGS] SpringBoard restart observed; dropped RemoteCall state (hadSession=%d)\n",
               (int)hadSession);
        if (hadSession) {
            log_user("[APP] SpringBoard restarted; tweak sessions cleared. Hit Run to rebuild.\n");
        }
        settings_notify_remote_call_state_changed();
    });
}

static void settings_install_screen_awake_observers(void)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        int status = notify_register_dispatch("com.apple.springboard.hasBlankedScreen",
                                              &g_springboard_blanked_notify_token,
                                              dispatch_get_main_queue(), ^(int token) {
            (void)token;
            if (settings_refresh_screen_awake_state("springboard.hasBlankedScreen")) {
                settings_apply_statbar_once_async("screen awake");
            }
        });
        if (status != NOTIFY_STATUS_OK) {
            g_springboard_blanked_notify_token = NOTIFY_TOKEN_INVALID;
        }

        status = notify_register_dispatch("com.apple.iokit.hid.displayStatus",
                                          &g_display_status_notify_token,
                                          dispatch_get_main_queue(), ^(int token) {
            (void)token;
            if (settings_refresh_screen_awake_state("iokit.displayStatus")) {
                settings_apply_statbar_once_async("screen awake");
            }
        });
        if (status != NOTIFY_STATUS_OK) {
            g_display_status_notify_token = NOTIFY_TOKEN_INVALID;
        }

        // Darwin notify fires when SpringBoard finishes its boot/respawn.
        // Either we just launched and SB is fine (cleanup is a no-op against
        // already-zero state) or SB crashed under us and we MUST drop every
        // cached pointer before the live loops fire again into SB-2.
        status = notify_register_dispatch("com.apple.springboard.finishedstartup",
                                          &g_springboard_finished_startup_notify_token,
                                          dispatch_get_main_queue(), ^(int token) {
            (void)token;
            settings_handle_springboard_restart();
        });
        if (status != NOTIFY_STATUS_OK) {
            g_springboard_finished_startup_notify_token = NOTIFY_TOKEN_INVALID;
        }

        // If the live loop tripped its 3-failure exit during a background
        // window, the screen-wake darwin notifications won't fire (the screen
        // never blanked) and the loop stays dead. Re-arm on app foreground.
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
            (void)note;
            (void)settings_refresh_screen_awake_state("app became active");
            settings_apply_statbar_once_async("app became active");
        }];

        (void)settings_refresh_screen_awake_state("startup");
    });
}

static void settings_end_statbar_background_task_async(const char *reason)
{
    void (^endTask)(void) = ^{
        @synchronized (settings_bg_lock()) {
            if (g_statbar_bg_task == UIBackgroundTaskInvalid) return;
            UIBackgroundTaskIdentifier task = g_statbar_bg_task;
            g_statbar_bg_task = UIBackgroundTaskInvalid;
            [[UIApplication sharedApplication] endBackgroundTask:task];
            printf("[SETTINGS] StatBar background task ended%s%s\n",
                   reason ? ": " : "", reason ?: "");
        }
    };

    if ([NSThread isMainThread]) {
        endTask();
    } else {
        dispatch_async(dispatch_get_main_queue(), endTask);
    }
}

// Bridge the foreground -> background transition with a short explicit
// UIBackgroundTask. DSKeepAlive's audio background mode carries the ongoing
// live feed; holding a UIBackgroundTask indefinitely trips UIKit's 30s watchdog
// warning and can get the app terminated.
static void settings_begin_statbar_background_task_async(const char *reason)
{
    void (^beginTask)(void) = ^{
        @synchronized (settings_bg_lock()) {
            if (g_statbar_bg_task != UIBackgroundTaskInvalid) return;
            UIApplication *app = [UIApplication sharedApplication];
            __block UIBackgroundTaskIdentifier task = UIBackgroundTaskInvalid;
            task = [app beginBackgroundTaskWithName:@"cyanide.statbar.live"
                                  expirationHandler:^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    @synchronized (settings_bg_lock()) {
                        if (g_statbar_bg_task != task) return;
                        g_statbar_bg_task = UIBackgroundTaskInvalid;
                        [[UIApplication sharedApplication] endBackgroundTask:task];
                        printf("[SETTINGS] StatBar background task expired by iOS; live loop may pause\n");
                    }
                });
            }];
            if (task == UIBackgroundTaskInvalid) {
                printf("[SETTINGS] StatBar background task could not be acquired%s%s\n",
                       reason ? ": " : "", reason ?: "");
                return;
            }
            g_statbar_bg_task = task;
            printf("[SETTINGS] StatBar background task acquired id=%lu%s%s\n",
                   (unsigned long)task,
                   reason ? ": " : "", reason ?: "");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                         kLiveBackgroundTaskGraceSeconds * NSEC_PER_SEC),
                           dispatch_get_main_queue(), ^{
                @synchronized (settings_bg_lock()) {
                    if (g_statbar_bg_task != task) return;
                    g_statbar_bg_task = UIBackgroundTaskInvalid;
                    [[UIApplication sharedApplication] endBackgroundTask:task];
                    printf("[SETTINGS] StatBar background task ended: transition grace elapsed; keepAlive=%d\n",
                           ds_keepalive_is_running());
                }
            });
        }
    };

    if ([NSThread isMainThread]) {
        beginTask();
    } else {
        dispatch_sync(dispatch_get_main_queue(), beginTask);
    }
}

static void settings_notify_remote_call_state_changed(void)
{
    BOOL ready = (g_springboard_rc_ready != 0);
    BOOL cleared = NO;
    if (!ready) {
        cleared = settings_clear_all_applied_locked();
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:kSettingsRemoteCallStateDidChangeNotification
                                                            object:nil];
        if (cleared) {
            [[NSNotificationCenter defaultCenter] postNotificationName:PackageQueueDidChangeNotification
                                                                object:[PackageQueue sharedQueue]];
            [[NSNotificationCenter defaultCenter] postNotificationName:kSettingsActionsDidCompleteNotification
                                                                object:nil];
        }
    });
}

static BOOL settings_cleanup_in_progress(void)
{
    return g_settings_cleanup_running != 0;
}

static void settings_request_all_live_loops_stop(const char *reason)
{
    g_statbar_live_stop_requested = 1;
    g_rssi_live_stop_requested = 1;
    g_axonlite_live_stop_requested = 1;
    if (reason) {
        printf("[SETTINGS] requested all live RemoteCall loops stop: %s\n", reason);
    }
}

static void settings_live_loop_sleep_interruptible(uint64_t targetUS,
                                                  useconds_t fallbackUS,
                                                  volatile int *stopFlag)
{
    uint64_t sleptFallbackUS = 0;
    while (!settings_cleanup_in_progress() && (!stopFlag || *stopFlag == 0)) {
        uint64_t nowUS = settings_now_us();
        uint64_t remainingUS = 0;
        if (targetUS != 0 && nowUS != 0 && nowUS < targetUS) {
            remainingUS = targetUS - nowUS;
        } else if (targetUS == 0 && sleptFallbackUS < fallbackUS) {
            remainingUS = (uint64_t)fallbackUS - sleptFallbackUS;
        } else {
            break;
        }

        useconds_t chunkUS = (useconds_t)(remainingUS < 100000ULL ? remainingUS : 100000ULL);
        if (chunkUS == 0) break;
        usleep(chunkUS);
        if (targetUS == 0) sleptFallbackUS += chunkUS;
    }
}

static UIViewController *settings_top_view_controller(UIViewController *vc)
{
    while (vc.presentedViewController) vc = vc.presentedViewController;
    if ([vc isKindOfClass:UINavigationController.class]) {
        return settings_top_view_controller(((UINavigationController *)vc).visibleViewController);
    }
    if ([vc isKindOfClass:UITabBarController.class]) {
        return settings_top_view_controller(((UITabBarController *)vc).selectedViewController);
    }
    return vc;
}

static UIViewController *settings_active_presenter(UIViewController *fallback)
{
    if (fallback.view.window) return settings_top_view_controller(fallback);

    UIWindow *candidate = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        if (ws.activationState != UISceneActivationStateForegroundActive &&
            ws.activationState != UISceneActivationStateForegroundInactive) {
            continue;
        }
        for (UIWindow *window in ws.windows) {
            if (window.isKeyWindow) {
                candidate = window;
                break;
            }
            if (!candidate && !window.hidden && window.rootViewController) {
                candidate = window;
            }
        }
        if (candidate) break;
    }

    return settings_top_view_controller(candidate.rootViewController ?: fallback);
}

static void settings_present_controller(UIViewController *controller, UIViewController *fallback)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presenter = settings_active_presenter(fallback);
        if (!presenter) {
            printf("[SETTINGS] presentation skipped: no attached presenter\n");
            return;
        }
        [presenter presentViewController:controller animated:YES completion:nil];
    });
}

static NSArray<NSString *> *powercuff_levels(void) {
    return @[ @"off", @"nominal", @"light", @"moderate", @"heavy" ];
}

static NSComparisonResult settings_compare_system_version(NSString *target)
{
    NSString *version = UIDevice.currentDevice.systemVersion ?: @"0";
    return [version compare:target options:NSNumericSearch];
}

BOOL settings_device_supported(void)
{
    BOOL ios17to18 =
        settings_compare_system_version(@"17.0") != NSOrderedAscending &&
        settings_compare_system_version(@"18.7.1") != NSOrderedDescending;

    BOOL ios26 =
        settings_compare_system_version(@"26.0") != NSOrderedAscending &&
        settings_compare_system_version(@"26.0.1") != NSOrderedDescending;

    return ios17to18 || ios26;
}

static NSString *settings_unsupported_message(void)
{
    NSString *version = UIDevice.currentDevice.systemVersion ?: @"unknown";
    return [NSString stringWithFormat:@"Not supported on iOS %@. Supported: iOS/iPadOS 17.0-18.7.1 or 26.0-26.0.1.", version];
}

static void settings_progress(NSUInteger *step, NSUInteger total, const char *message)
{
    if (!step || !message) return;
    (*step)++;
    log_user("[RUN %lu/%lu] %s\n",
             (unsigned long)*step,
             (unsigned long)total,
             message);
}

static void settings_log_run_context(void)
{
    struct utsname u = {0};
    const char *machine = "unknown";
    if (uname(&u) == 0 && u.machine[0]) machine = u.machine;

    NSString *version = UIDevice.currentDevice.systemVersion ?: @"unknown";
    const char *krwState = g_kexploit_done
        ? "cached app KRW present; validating before use"
        : "no live app KRW; recovery or fresh chain will be attempted";

    log_user("[BOOT] Cyanide pid=%d running on %s, iOS/iPadOS %s.\n",
             getpid(), machine, version.UTF8String);
    log_user("[BOOT] Initializing settings, device support, action planner, and KRW gate.\n");
    log_user("[BOOT] KRW state: %s.\n", krwState);
}

static BOOL settings_ensure_kexploit(void)
{
    if (!settings_device_supported()) {
        printf("[SETTINGS] unsupported device: %s\n", settings_unsupported_message().UTF8String);
        return NO;
    }

    if (g_kexploit_done) {
        if (kexploit_krw_ready()) {
            log_user("[KRW] Reusing the live app KRW session; no exploit rerun needed.\n");
            return YES;
        }
        printf("[SETTINGS] cached KRW is stale; clearing RemoteCall state and recovering\n");
        log_user("[KRW] Cached app KRW failed validation; clearing RemoteCall state and trying recovery.\n");
        g_kexploit_done = NO;
        g_springboard_rc_ready = 0;
        g_springboard_sandbox_escaped = 0;
        kutils_reset_self_cache();
        settings_notify_remote_call_state_changed();
    }

    printf("[SETTINGS] kexploit preflight cleanup\n");
    log_user("[KRW] Preflight cleanup: closing app-owned leftovers before KRW setup.\n");
    kexploit_preflight_cleanup();
    int res = kexploit_opa334();
    if (res != 0) {
        printf("[SETTINGS] kexploit_opa334 failed: %d\n", res);
        return NO;
    }
    g_kexploit_done = YES;
    settings_notify_remote_call_state_changed();
    return YES;
}

static BOOL settings_ensure_springboard_remote_call_locked(void)
{
    if (g_springboard_rc_ready) {
        printf("[SETTINGS] reusing SpringBoard RemoteCall session\n");
        return YES;
    }

    printf("[SETTINGS] initializing SpringBoard RemoteCall session\n");
    if (init_remote_call("SpringBoard", false) != 0) {
        printf("[SETTINGS] init_remote_call(SpringBoard) failed\n");
        return NO;
    }

    g_springboard_rc_ready = 1;
    g_springboard_sandbox_escaped = 0;
    printf("[SETTINGS] SpringBoard RemoteCall session ready\n");
    settings_notify_remote_call_state_changed();
    return YES;
}

static void settings_destroy_springboard_remote_call_locked(const char *reason)
{
    if (!g_springboard_rc_ready) return;

    printf("[SETTINGS] destroying SpringBoard RemoteCall session%s%s\n",
           reason ? ": " : "", reason ?: "");
    destroy_remote_call();
    g_springboard_rc_ready = 0;
    g_springboard_sandbox_escaped = 0;
    settings_notify_remote_call_state_changed();
}

static void settings_prepare_for_respring_sync(void)
{
    log_user("[RESPRING] Stopping live sessions before respring.\n");
    printf("[SETTINGS] preparing for respring cleanup rcReady=%d\n", g_springboard_rc_ready);
    settings_request_all_live_loops_stop("pre-respring cleanup");
    settings_end_statbar_background_task_async("pre-respring cleanup");

    @synchronized (settings_rc_lock()) {
        if (g_springboard_rc_ready) {
            bool axonStopped = axonlite_stop_in_session();
            printf("[SETTINGS] pre-respring Axon Lite stop result=%d\n", axonStopped);
            bool stopped = statbar_stop_in_session();
            printf("[SETTINGS] pre-respring StatBar stop result=%d\n", stopped);
            bool rssiStopped = rssidisplay_stop_in_session();
            printf("[SETTINGS] pre-respring RSSI stop result=%d\n", rssiStopped);
            settings_destroy_springboard_remote_call_locked("pre-respring cleanup");
        }
    }

    if (g_kexploit_done) {
        bool parked = kexploit_terminal_cleanup();
        printf("[SETTINGS] pre-respring terminal KRW cleanup parked=%d\n", parked);
        g_kexploit_done = NO;
        g_springboard_rc_ready = 0;
        g_springboard_sandbox_escaped = 0;
        kutils_reset_self_cache();
        settings_notify_remote_call_state_changed();
    }

    log_user("[RESPRING] Cleanup complete. Opening respring flow.\n");
    usleep(300000);
}

static void settings_terminal_kexploit_cleanup_sync_internal(const char *reason)
{
    log_user("[CLEANUP] Stopping live sessions and cleaning local KRW state.\n");
    printf("[SETTINGS] terminal KRW cleanup requested%s%s done=%d rcReady=%d\n",
           reason ? ": " : "", reason ?: "",
           g_kexploit_done, g_springboard_rc_ready);
    settings_request_all_live_loops_stop("terminal KRW cleanup");
    settings_end_statbar_background_task_async("terminal KRW cleanup");

    @synchronized (settings_rc_lock()) {
        if (g_springboard_rc_ready) {
            bool axonStopped = axonlite_stop_in_session();
            printf("[SETTINGS] terminal cleanup Axon Lite stop result=%d\n", axonStopped);
            bool stopped = statbar_stop_in_session();
            printf("[SETTINGS] terminal cleanup StatBar stop result=%d\n", stopped);
            bool rssiStopped = rssidisplay_stop_in_session();
            printf("[SETTINGS] terminal cleanup RSSI stop result=%d\n", rssiStopped);
            settings_destroy_springboard_remote_call_locked(reason ?: "terminal KRW cleanup");
        }
    }

    if (!g_kexploit_done) {
        printf("[SETTINGS] terminal KRW cleanup skipped: no local KRW session\n");
        log_user("[CLEANUP] No local KRW session is active.\n");
        return;
    }

    bool parked = kexploit_terminal_cleanup();
    printf("[SETTINGS] terminal KRW cleanup result parked=%d\n", parked);
    log_user("%s Clean Up finished. Next Run will try persisted KRW recovery first.\n",
             parked ? "[OK]" : "[WARN]");
    g_kexploit_done = NO;
    g_springboard_rc_ready = 0;
    g_springboard_sandbox_escaped = 0;
    kutils_reset_self_cache();
    settings_notify_remote_call_state_changed();
}

static void settings_terminal_kexploit_cleanup_sync(const char *reason)
{
    settings_terminal_kexploit_cleanup_sync_internal(reason);
}

static BOOL settings_acquire_actions_lock_wait(const char *owner, uint64_t timeoutUS)
{
    uint64_t startUS = settings_now_us();
    BOOL loggedWait = NO;

    while (__sync_lock_test_and_set(&g_settings_actions_running, 1)) {
        if (!loggedWait) {
            printf("[SETTINGS] %s waiting for active action before cleanup\n",
                   owner ?: "cleanup");
            log_user("[CLEANUP] Current operation is active; cleanup is queued.\n");
            loggedWait = YES;
        }

        if (timeoutUS != 0) {
            uint64_t nowUS = settings_now_us();
            if (startUS != 0 && nowUS >= startUS && nowUS - startUS >= timeoutUS) {
                printf("[SETTINGS] %s timed out waiting for action lock\n",
                       owner ?: "cleanup");
                log_user("[CLEANUP] Timed out waiting for the current operation to finish.\n");
                return NO;
            }
        }

        usleep(100000);
    }

    if (loggedWait) {
        uint64_t nowUS = settings_now_us();
        uint64_t waitedUS = (startUS != 0 && nowUS >= startUS) ? nowUS - startUS : 0;
        printf("[SETTINGS] %s acquired action lock after %lluus\n",
               owner ?: "cleanup", waitedUS);
    }
    return YES;
}

static void settings_queue_terminal_kexploit_cleanup(const char *reason)
{
    if (__sync_lock_test_and_set(&g_settings_cleanup_running, 1)) {
        printf("[SETTINGS] terminal cleanup already queued/running%s%s\n",
               reason ? ": " : "", reason ?: "");
        log_user("[CLEANUP] Clean Up is already queued.\n");
        return;
    }

    settings_request_all_live_loops_stop("queued terminal cleanup");
    settings_end_statbar_background_task_async("queued terminal cleanup");

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        BOOL locked = settings_acquire_actions_lock_wait("terminal cleanup", 0);
        @try {
            settings_terminal_kexploit_cleanup_sync_internal(reason ?: "manual action");
        } @finally {
            if (locked) __sync_lock_release(&g_settings_actions_running);
            __sync_lock_release(&g_settings_cleanup_running);
        }
    });
}

void settings_best_effort_termination_cleanup(const char *reason)
{
    if (__sync_lock_test_and_set(&g_settings_termination_cleanup_started, 1)) {
        printf("[SETTINGS] termination cleanup already attempted%s%s\n",
               reason ? ": " : "", reason ?: "");
        return;
    }

    const char *why = reason ?: "app termination";
    log_user("[CLEANUP] App termination requested (%s); attempting last-chance cleanup.\n", why);
    printf("[SETTINGS] best-effort termination cleanup requested: %s\n", why);

    settings_request_all_live_loops_stop("termination cleanup");

    BOOL locked = settings_acquire_actions_lock_wait("termination cleanup", 1500000);
    if (!locked) {
        log_user("[CLEANUP] Last-chance cleanup skipped because another operation is still active.\n");
        return;
    }

    @try {
        settings_terminal_kexploit_cleanup_sync_internal(why);
    } @finally {
        __sync_lock_release(&g_settings_actions_running);
    }
}

void settings_destroy_springboard_remote_call_sync(void)
{
    settings_request_all_live_loops_stop("remote call sync cleanup");
    settings_end_statbar_background_task_async("remote call sync cleanup");
    @synchronized (settings_rc_lock()) {
        if (g_springboard_rc_ready) {
            axonlite_stop_in_session();
            rssidisplay_stop_in_session();
        }
        settings_destroy_springboard_remote_call_locked("manual/sync cleanup");
    }
}

void settings_destroy_springboard_remote_call(void)
{
    settings_request_all_live_loops_stop("remote call cleanup");
    settings_end_statbar_background_task_async("remote call cleanup");
    log_user("[SESSION] Disconnecting from SpringBoard.\n");
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        @synchronized (settings_rc_lock()) {
            BOOL hadSession = g_springboard_rc_ready != 0;
            if (g_springboard_rc_ready) {
                axonlite_stop_in_session();
                rssidisplay_stop_in_session();
            }
            settings_destroy_springboard_remote_call_locked("manual cleanup");
            log_user(hadSession ? "[OK] SpringBoard session disconnected.\n" :
                                  "[SESSION] No active SpringBoard session.\n");
        }
    });
}

static bool settings_apply_sbc_from_defaults_locked(NSUserDefaults *d)
{
    if (![d boolForKey:kSettingsSBCEnabled]) return false;

    return sbcustomizer_apply_in_session((int)[d integerForKey:kSettingsSBCDockIcons],
                                         (int)[d integerForKey:kSettingsSBCCols],
                                         (int)[d integerForKey:kSettingsSBCRows],
                                         [d boolForKey:kSettingsSBCHideLabels]);
}

static BOOL settings_dark_tweaks_any_enabled(NSUserDefaults *d)
{
    return [d boolForKey:kSettingsDSDisableAppLibrary] ||
           [d boolForKey:kSettingsDSDisableIconFlyIn] ||
           [d boolForKey:kSettingsDSZeroWakeAnimation] ||
           [d boolForKey:kSettingsDSZeroBacklightFade] ||
           [d boolForKey:kSettingsDSDoubleTapToLock];
}

static bool settings_apply_dark_tweaks_from_defaults_locked(NSUserDefaults *d)
{
    if (!settings_dark_tweaks_any_enabled(d)) return false;

    return darksword_tweaks_apply_in_session([d boolForKey:kSettingsDSDisableAppLibrary],
                                             [d boolForKey:kSettingsDSDisableIconFlyIn],
                                             [d boolForKey:kSettingsDSZeroWakeAnimation],
                                             [d boolForKey:kSettingsDSZeroBacklightFade],
                                             [d boolForKey:kSettingsDSDoubleTapToLock]);
}

static void settings_reset_sbc_defaults(void)
{
    if (!settings_device_supported()) {
        printf("[SETTINGS] SBC reset blocked: %s\n", settings_unsupported_message().UTF8String);
        return;
    }

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:YES forKey:kSettingsSBCEnabled];
    [d setInteger:kSBCDefaultDockIcons forKey:kSettingsSBCDockIcons];
    [d setInteger:kSBCDefaultCols forKey:kSettingsSBCCols];
    [d setInteger:kSBCDefaultRows forKey:kSettingsSBCRows];
    [d setBool:kSBCDefaultHideLabels forKey:kSettingsSBCHideLabels];
    [d synchronize];

    printf("[SETTINGS] SBC reset defaults dock=%ld hs=%ldx%ld hideLabels=%d rcReady=%d\n",
           (long)kSBCDefaultDockIcons,
           (long)kSBCDefaultCols,
           (long)kSBCDefaultRows,
           kSBCDefaultHideLabels,
           g_springboard_rc_ready);

    if (!g_springboard_rc_ready) return;

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        @synchronized (settings_rc_lock()) {
            if (!g_springboard_rc_ready) return;
            bool ok = settings_apply_sbc_from_defaults_locked(d);
            settings_mark_tweak_applied(kSettingsSBCEnabled,
                                        ok && [d boolForKey:kSettingsSBCEnabled]);
            printf("[SETTINGS] SBC reset apply result=%d\n", ok);
        }
        settings_notify_package_queue_changed_async();
    });
}

static void settings_run_ota_action(BOOL disable)
{
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        if (__sync_lock_test_and_set(&g_settings_actions_running, 1)) {
            printf("[SETTINGS] actions already running; ignoring OTA request\n");
            log_user("[OTA] Another action is already running.\n");
            return;
        }
        @try {
            log_user("[OTA] %s OTA updates.\n", disable ? "Disabling" : "Enabling");
            if (!settings_ensure_kexploit()) {
                log_user("[OTA] Failed: kernel primitives were not acquired.\n");
                return;
            }

            settings_request_all_live_loops_stop("switching to launchd for OTA");
            settings_end_statbar_background_task_async("switching to launchd for OTA");

            @synchronized (settings_rc_lock()) {
                if (g_springboard_rc_ready) {
                    axonlite_stop_in_session();
                    rssidisplay_stop_in_session();
                }
                settings_destroy_springboard_remote_call_locked(disable ? "switching to launchd for OTA disable" :
                                                                         "switching to launchd for OTA enable");
                bool ok = darksword_ota_set_disabled(disable);
                printf("[SETTINGS] OTA %s result=%d\n", disable ? "disable" : "enable", ok);
                log_user("%s OTA updates %s. Reboot or userspace restart is still required.\n",
                         ok ? "[OK]" : "[WARN]",
                         disable ? "disabled" : "enabled");
            }
        } @finally {
            __sync_lock_release(&g_settings_actions_running);
        }
    });
}

static void settings_start_statbar_live_loop(void)
{
    if (!settings_device_supported()) return;
    if (settings_cleanup_in_progress()) return;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d boolForKey:kSettingsStatBarEnabled]) return;

    if (__sync_lock_test_and_set(&g_statbar_live_running, 1)) {
        // Log-once for the process lifetime; further "already running" hits
        // during foreground/background lifecycle churn are pure noise.
        static volatile int loggedAlready = 0;
        if (__sync_bool_compare_and_swap(&loggedAlready, 0, 1)) {
            printf("[SETTINGS] StatBar live loop already running\n");
        }
        return;
    }

    if (settings_cleanup_in_progress()) {
        __sync_lock_release(&g_statbar_live_running);
        return;
    }

    g_statbar_live_stop_requested = 0;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSUInteger tick = 0;
        NSUInteger failures = 0;
        uint64_t nextTickUS = settings_now_us();
        BOOL pausedForSleep = NO;

        printf("[SETTINGS] StatBar live loop started interval=%uus background=%uus max=%lu\n",
               kStatBarLiveIntervalUS,
               kStatBarLiveBackgroundIntervalUS,
               (unsigned long)kStatBarLiveMaxTicks);

        @try {
            while ([d boolForKey:kSettingsStatBarEnabled] &&
                   !settings_cleanup_in_progress() &&
                   !g_statbar_live_stop_requested &&
                   tick < kStatBarLiveMaxTicks) {
                useconds_t intervalUS = settings_live_interval(kStatBarLiveIntervalUS,
                                                               kStatBarLiveBackgroundIntervalUS);
                if (!settings_statbar_screen_awake()) {
                    if (!pausedForSleep) {
                        pausedForSleep = YES;
                        printf("[SETTINGS] StatBar paused while screen is asleep\n");
                    }
                    settings_live_loop_sleep_interruptible(0,
                                                           intervalUS,
                                                           &g_statbar_live_stop_requested);
                    nextTickUS = settings_now_us();
                    continue;
                }
                if (pausedForSleep) {
                    pausedForSleep = NO;
                    printf("[SETTINGS] StatBar resumed after screen wake\n");
                }

                uint64_t tickStartUS = settings_now_us();
                bool ok = false;

                @synchronized (settings_rc_lock()) {
                    if (!g_springboard_rc_ready) {
                        printf("[SETTINGS] StatBar loop has no SpringBoard RemoteCall session\n");
                        failures++;
                        break;
                    }
                    ok = statbar_apply_in_session([d boolForKey:kSettingsStatBarCelsius],
                                                  [d boolForKey:kSettingsStatBarHideNet]);
                }

                if (tick == 0) printf("[SETTINGS] StatBar result=%d\n", ok);
                if (ok) {
                    failures = 0;
                } else {
                    failures++;
                    printf("[SETTINGS] StatBar tick failed tick=%lu failures=%lu\n",
                           (unsigned long)tick, (unsigned long)failures);
                    if (failures >= settings_live_failure_limit(3)) break;
                }

                tick++;
                if (![d boolForKey:kSettingsStatBarEnabled] ||
                    g_statbar_live_stop_requested ||
                    tick >= kStatBarLiveMaxTicks) break;

                uint64_t nowUS = settings_now_us();
                uint64_t elapsedUS = (tickStartUS != 0 && nowUS >= tickStartUS) ? (nowUS - tickStartUS) : 0;
                if (nextTickUS != 0) {
                    intervalUS = settings_live_interval(kStatBarLiveIntervalUS,
                                                        kStatBarLiveBackgroundIntervalUS);
                    nextTickUS += intervalUS;
                    if (nowUS < nextTickUS) {
                        uint64_t sleepUS = nextTickUS - nowUS;
                        if (settings_should_log_statbar_tick(tick - 1)) {
                            printf("[SETTINGS] StatBar tick=%lu elapsed=%lluus sleep=%lluus mode=%s\n",
                                   (unsigned long)(tick - 1),
                                   elapsedUS,
                                   sleepUS,
                                   settings_live_context());
                        }
                        settings_live_loop_sleep_interruptible(nextTickUS,
                                                               (useconds_t)sleepUS,
                                                               &g_statbar_live_stop_requested);
                    } else {
                        uint64_t overrunUS = nowUS - nextTickUS;
                        if (settings_should_log_statbar_tick(tick - 1)) {
                            printf("[SETTINGS] StatBar tick=%lu elapsed=%lluus overrun=%lluus mode=%s\n",
                                   (unsigned long)(tick - 1),
                                   elapsedUS,
                                   overrunUS,
                                   settings_live_context());
                        }
                        nextTickUS = nowUS;
                    }
                } else {
                    settings_live_loop_sleep_interruptible(0,
                                                           settings_live_interval(kStatBarLiveIntervalUS,
                                                                                  kStatBarLiveBackgroundIntervalUS),
                                                           &g_statbar_live_stop_requested);
                }
            }
        } @finally {
            printf("[SETTINGS] StatBar live loop exited ticks=%lu enabled=%d failures=%lu stop=%d\n",
                   (unsigned long)tick,
                   [d boolForKey:kSettingsStatBarEnabled],
                   (unsigned long)failures,
                   g_statbar_live_stop_requested);
            if (![d boolForKey:kSettingsStatBarEnabled] || g_statbar_live_stop_requested || failures > 0) {
                settings_end_statbar_background_task_async("live loop exited");
            }
            __sync_lock_release(&g_statbar_live_running);
        }
    });
}

static void settings_apply_statbar_once_async(const char *reason)
{
    if (!settings_device_supported()) return;
    if (settings_cleanup_in_progress()) return;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d boolForKey:kSettingsStatBarEnabled] || !g_springboard_rc_ready) return;
    if (g_statbar_live_running) return;

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        if (settings_cleanup_in_progress()) return;
        bool ok = false;
        (void)settings_refresh_screen_awake_state(reason ?: "statbar apply");
        if (!settings_screen_awake_cached()) {
            printf("[SETTINGS] StatBar lifecycle apply%s%s skipped: screen asleep\n",
                   reason ? ": " : "", reason ?: "");
            settings_start_statbar_live_loop();
            return;
        }
        @synchronized (settings_rc_lock()) {
            if (settings_cleanup_in_progress() ||
                ![d boolForKey:kSettingsStatBarEnabled] ||
                !g_springboard_rc_ready) return;
            ok = statbar_apply_in_session([d boolForKey:kSettingsStatBarCelsius],
                                          [d boolForKey:kSettingsStatBarHideNet]);
        }
        // Only log lifecycle applies that change result; a clean success on
        // every foreground/background flip is noise.
        static volatile int lastResult = -1;
        int now = ok ? 1 : 0;
        if (now != lastResult) {
            lastResult = now;
            printf("[SETTINGS] StatBar lifecycle apply%s%s result=%d\n",
                   reason ? ": " : "", reason ?: "", ok);
        }
        settings_start_statbar_live_loop();
    });
}

static void settings_start_rssi_live_loop(void)
{
    if (!settings_device_supported()) return;
    if (settings_cleanup_in_progress()) return;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (!settings_rssi_install_allowed()) return;
    if (![d boolForKey:kSettingsRSSIDisplayEnabled]) return;
    if (!g_springboard_rc_ready) return;

    if (__sync_lock_test_and_set(&g_rssi_live_running, 1)) {
        static volatile int loggedAlready = 0;
        if (__sync_bool_compare_and_swap(&loggedAlready, 0, 1)) {
            printf("[SETTINGS] RSSI live loop already running\n");
        }
        return;
    }

    if (settings_cleanup_in_progress()) {
        __sync_lock_release(&g_rssi_live_running);
        return;
    }

    g_rssi_live_stop_requested = 0;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSUInteger tick = 0;
        NSUInteger failures = 0;
        uint64_t nextTickUS = settings_now_us();
        BOOL pausedForSleep = NO;

        printf("[SETTINGS] RSSI live loop started interval=%uus background=%uus max=%lu\n",
               kRSSILiveIntervalUS,
               kRSSILiveBackgroundIntervalUS,
               (unsigned long)kRSSILiveMaxTicks);

        @try {
            while ([d boolForKey:kSettingsRSSIDisplayEnabled] &&
                   !settings_cleanup_in_progress() &&
                   !g_rssi_live_stop_requested &&
                   tick < kRSSILiveMaxTicks) {
                useconds_t intervalUS = settings_live_interval(kRSSILiveIntervalUS,
                                                               kRSSILiveBackgroundIntervalUS);
                if (!settings_statbar_screen_awake()) {
                    if (!pausedForSleep) {
                        pausedForSleep = YES;
                        printf("[SETTINGS] RSSI paused while screen is asleep\n");
                    }
                    settings_live_loop_sleep_interruptible(0,
                                                           intervalUS,
                                                           &g_rssi_live_stop_requested);
                    nextTickUS = settings_now_us();
                    continue;
                }
                if (pausedForSleep) {
                    pausedForSleep = NO;
                    printf("[SETTINGS] RSSI resumed after screen wake\n");
                }

                uint64_t tickStartUS = settings_now_us();
                bool ok = false;

                @synchronized (settings_rc_lock()) {
                    if (!g_springboard_rc_ready) {
                        printf("[SETTINGS] RSSI loop has no SpringBoard RemoteCall session\n");
                        failures++;
                        break;
                    }
                    ok = rssidisplay_apply_in_session([d boolForKey:kSettingsRSSIDisplayWifi],
                                                      [d boolForKey:kSettingsRSSIDisplayCell]);
                }

                uint64_t tickEndUS = settings_now_us();
                if (tick == 0) {
                    uint64_t elapsedUS = tickEndUS >= tickStartUS ? tickEndUS - tickStartUS : 0;
                    printf("[SETTINGS] RSSI first tick result=%d elapsed=%lluus\n",
                           ok,
                           (unsigned long long)elapsedUS);
                }
                if (ok) {
                    failures = 0;
                } else {
                    failures++;
                    printf("[SETTINGS] RSSI tick failed tick=%lu failures=%lu\n",
                           (unsigned long)tick, (unsigned long)failures);
                    if (failures >= settings_live_failure_limit(5)) break;
                }

                tick++;
                if (![d boolForKey:kSettingsRSSIDisplayEnabled] ||
                    g_rssi_live_stop_requested ||
                    tick >= kRSSILiveMaxTicks) break;

                uint64_t nowUS = tickEndUS;
                if (nextTickUS != 0) {
                    intervalUS = settings_live_interval(kRSSILiveIntervalUS,
                                                        kRSSILiveBackgroundIntervalUS);
                    nextTickUS += intervalUS;
                    if (nowUS < nextTickUS) {
                        settings_live_loop_sleep_interruptible(nextTickUS,
                                                               (useconds_t)(nextTickUS - nowUS),
                                                               &g_rssi_live_stop_requested);
                    } else {
                        nextTickUS = nowUS;
                    }
                } else {
                    settings_live_loop_sleep_interruptible(0,
                                                           settings_live_interval(kRSSILiveIntervalUS,
                                                                                  kRSSILiveBackgroundIntervalUS),
                                                           &g_rssi_live_stop_requested);
                }
            }
        } @finally {
            printf("[SETTINGS] RSSI live loop exited ticks=%lu enabled=%d failures=%lu stop=%d\n",
                   (unsigned long)tick,
                   [d boolForKey:kSettingsRSSIDisplayEnabled],
                   (unsigned long)failures,
                   g_rssi_live_stop_requested);
            __sync_lock_release(&g_rssi_live_running);
        }
    });
}

static void settings_apply_rssi_once_async(const char *reason)
{
    if (!settings_device_supported()) return;
    if (settings_cleanup_in_progress()) return;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (!settings_rssi_install_allowed()) return;
    if (![d boolForKey:kSettingsRSSIDisplayEnabled] || !g_springboard_rc_ready) return;
    if (g_rssi_live_running) return;

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        if (settings_cleanup_in_progress()) return;
        bool ok = false;
        (void)settings_refresh_screen_awake_state(reason ?: "rssi apply");
        if (!settings_screen_awake_cached()) {
            printf("[SETTINGS] RSSI lifecycle apply%s%s skipped: screen asleep\n",
                   reason ? ": " : "", reason ?: "");
            settings_start_rssi_live_loop();
            return;
        }
        @synchronized (settings_rc_lock()) {
            if (settings_cleanup_in_progress() ||
                ![d boolForKey:kSettingsRSSIDisplayEnabled] ||
                !g_springboard_rc_ready) return;
            ok = rssidisplay_apply_in_session([d boolForKey:kSettingsRSSIDisplayWifi],
                                              [d boolForKey:kSettingsRSSIDisplayCell]);
        }
        printf("[SETTINGS] RSSI lifecycle apply%s%s result=%d\n",
               reason ? ": " : "", reason ?: "", ok);
        settings_start_rssi_live_loop();
    });
}

static void settings_start_axonlite_live_loop(void)
{
    if (!settings_device_supported()) return;
    if (settings_cleanup_in_progress()) return;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d boolForKey:kSettingsAxonLiteEnabled]) return;
    if (!g_springboard_rc_ready) return;

    if (__sync_lock_test_and_set(&g_axonlite_live_running, 1)) {
        static volatile int loggedAlready = 0;
        if (__sync_bool_compare_and_swap(&loggedAlready, 0, 1)) {
            printf("[SETTINGS] Axon Lite live loop already running\n");
        }
        return;
    }

    if (settings_cleanup_in_progress()) {
        __sync_lock_release(&g_axonlite_live_running);
        return;
    }

    g_axonlite_live_stop_requested = 0;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSUInteger tick = 0;
        NSUInteger failures = 0;
        uint64_t nextTickUS = settings_now_us();
        BOOL pausedForSleep = NO;

        printf("[SETTINGS] Axon Lite live loop started interval=%uus background=%uus max=%lu\n",
               kAxonLiteLiveIntervalUS,
               kAxonLiteLiveBackgroundIntervalUS,
               (unsigned long)kAxonLiteLiveMaxTicks);

        @try {
            while ([d boolForKey:kSettingsAxonLiteEnabled] &&
                   !settings_cleanup_in_progress() &&
                   !g_axonlite_live_stop_requested &&
                   tick < kAxonLiteLiveMaxTicks) {
                useconds_t intervalUS = settings_live_interval(kAxonLiteLiveIntervalUS,
                                                               kAxonLiteLiveBackgroundIntervalUS);
                // While the screen is blank, SB tears down cover-sheet view
                // controllers to free memory. Calling into our cached
                // gAxonCLVC etc during that window risks dereferencing freed
                // objects (the PAC-fault path we keep hitting). Pause until
                // the screen wakes; on wake the loop re-finds CLVC fresh.
                if (!settings_statbar_screen_awake()) {
                    if (!pausedForSleep) {
                        pausedForSleep = YES;
                        printf("[SETTINGS] Axon Lite paused while screen is asleep\n");
                    }
                    settings_live_loop_sleep_interruptible(0,
                                                           intervalUS,
                                                           &g_axonlite_live_stop_requested);
                    nextTickUS = settings_now_us();
                    continue;
                }
                if (pausedForSleep) {
                    pausedForSleep = NO;
                    printf("[SETTINGS] Axon Lite resumed after screen wake\n");
                    // SB likely rebuilt the cover sheet during the blank
                    // window; the cached CLVC we held is stale. Drop it so
                    // the next tick walks the windows again.
                    axonlite_forget_remote_state();
                }

                uint64_t tickStartUS = settings_now_us();
                bool ok = false;

                @synchronized (settings_rc_lock()) {
                    if (!g_springboard_rc_ready) {
                        printf("[SETTINGS] Axon Lite loop has no SpringBoard RemoteCall session\n");
                        failures++;
                        break;
                    }
                    ok = axonlite_apply_in_session();
                }

                if (tick == 0) printf("[SETTINGS] Axon Lite result=%d\n", ok);
                if (ok) {
                    failures = 0;
                } else {
                    failures++;
                    printf("[SETTINGS] Axon Lite tick failed tick=%lu failures=%lu\n",
                           (unsigned long)tick, (unsigned long)failures);
                    if (failures >= settings_live_failure_limit(3)) break;
                }

                tick++;
                if (![d boolForKey:kSettingsAxonLiteEnabled] ||
                    g_axonlite_live_stop_requested ||
                    tick >= kAxonLiteLiveMaxTicks) break;

                uint64_t nowUS = settings_now_us();
                if (nextTickUS != 0) {
                    intervalUS = settings_live_interval(kAxonLiteLiveIntervalUS,
                                                        kAxonLiteLiveBackgroundIntervalUS);
                    nextTickUS += intervalUS;
                    if (nowUS < nextTickUS) {
                        settings_live_loop_sleep_interruptible(nextTickUS,
                                                               (useconds_t)(nextTickUS - nowUS),
                                                               &g_axonlite_live_stop_requested);
                    } else {
                        nextTickUS = nowUS;
                    }
                } else {
                    settings_live_loop_sleep_interruptible(0,
                                                           settings_live_interval(kAxonLiteLiveIntervalUS,
                                                                                  kAxonLiteLiveBackgroundIntervalUS),
                                                           &g_axonlite_live_stop_requested);
                }

                uint64_t elapsedUS = tickStartUS != 0 && nowUS >= tickStartUS ? nowUS - tickStartUS : 0;
                if (tick == 1) {
                    printf("[SETTINGS] Axon Lite tick=0 elapsed=%lluus\n", elapsedUS);
                }
            }
        } @finally {
            printf("[SETTINGS] Axon Lite live loop exited ticks=%lu enabled=%d failures=%lu stop=%d\n",
                   (unsigned long)tick,
                   [d boolForKey:kSettingsAxonLiteEnabled],
                   (unsigned long)failures,
                   g_axonlite_live_stop_requested);
            __sync_lock_release(&g_axonlite_live_running);
        }
    });
}

static void settings_apply_axonlite_once_async(const char *reason)
{
    if (!settings_device_supported()) return;
    if (settings_cleanup_in_progress()) return;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d boolForKey:kSettingsAxonLiteEnabled] || !g_springboard_rc_ready) return;

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        if (settings_cleanup_in_progress()) return;
        bool ok = false;
        @synchronized (settings_rc_lock()) {
            if (settings_cleanup_in_progress() ||
                ![d boolForKey:kSettingsAxonLiteEnabled] ||
                !g_springboard_rc_ready) return;
            ok = axonlite_apply_in_session();
        }
        printf("[SETTINGS] Axon Lite lifecycle apply%s%s result=%d\n",
               reason ? ": " : "", reason ?: "", ok);
        settings_start_axonlite_live_loop();
    });
}

void settings_application_did_enter_background(void)
{
    if (__sync_lock_test_and_set(&g_app_in_background, 1)) return;
    if (settings_cleanup_in_progress()) return;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    BOOL anyLiveLoopNeeded =
        ([d boolForKey:kSettingsAxonLiteEnabled]    && g_springboard_rc_ready) ||
        (settings_rssi_install_allowed() && [d boolForKey:kSettingsRSSIDisplayEnabled] && g_springboard_rc_ready) ||
        ([d boolForKey:kSettingsStatBarEnabled]     && g_springboard_rc_ready);
    if (anyLiveLoopNeeded) {
        if ([d boolForKey:kSettingsKeepAlive]) {
            ds_keepalive_apply_enabled(YES);
        }
        settings_begin_statbar_background_task_async("entered background");
        printf("[SETTINGS] background live-loop support keepAlive=%d bgTask=%lu\n",
               ds_keepalive_is_running(),
               (unsigned long)g_statbar_bg_task);
    }

    if ([d boolForKey:kSettingsAxonLiteEnabled] && g_springboard_rc_ready) {
        settings_apply_axonlite_once_async("entered background");
    }
    if (settings_rssi_install_allowed() && [d boolForKey:kSettingsRSSIDisplayEnabled] && g_springboard_rc_ready) {
        settings_apply_rssi_once_async("entered background");
    }
    if (![d boolForKey:kSettingsStatBarEnabled] || !g_springboard_rc_ready) {
        return;
    }

    printf("[SETTINGS] app entered background with app-side StatBar loop\n");
    settings_apply_statbar_once_async("entered background");
}

void settings_application_will_enter_foreground(void)
{
    if (!settings_app_state_is_foreground()) return;
    g_app_in_background = 0;
    settings_end_statbar_background_task_async("foreground");
    if (settings_cleanup_in_progress()) return;
    settings_apply_statbar_once_async("will enter foreground");
    settings_apply_rssi_once_async("will enter foreground");
    settings_apply_axonlite_once_async("will enter foreground");
}

void settings_application_did_become_active(void)
{
    if (!settings_app_state_is_foreground()) return;
    g_app_in_background = 0;
    if (settings_cleanup_in_progress()) return;
    settings_apply_statbar_once_async("became active");
    settings_apply_rssi_once_async("became active");
    settings_apply_axonlite_once_async("became active");
}

static BOOL settings_key_is_sbc(NSString *key)
{
    return [key isEqualToString:kSettingsSBCEnabled] ||
           [key isEqualToString:kSettingsSBCDockIcons] ||
           [key isEqualToString:kSettingsSBCCols] ||
           [key isEqualToString:kSettingsSBCRows] ||
           [key isEqualToString:kSettingsSBCHideLabels];
}

static BOOL settings_key_is_statbar(NSString *key)
{
    return [key isEqualToString:kSettingsStatBarEnabled] ||
           [key isEqualToString:kSettingsStatBarCelsius] ||
           [key isEqualToString:kSettingsStatBarHideNet];
}

static BOOL settings_key_is_rssi(NSString *key)
{
    return [key isEqualToString:kSettingsRSSIDisplayEnabled] ||
           [key isEqualToString:kSettingsRSSIDisplayWifi] ||
           [key isEqualToString:kSettingsRSSIDisplayCell];
}

static BOOL settings_key_is_axonlite(NSString *key)
{
    return [key isEqualToString:kSettingsAxonLiteEnabled];
}

static BOOL settings_key_is_dark_tweak(NSString *key)
{
    return [key isEqualToString:kSettingsDSDisableAppLibrary] ||
           [key isEqualToString:kSettingsDSDisableIconFlyIn] ||
           [key isEqualToString:kSettingsDSZeroWakeAnimation] ||
           [key isEqualToString:kSettingsDSZeroBacklightFade] ||
           [key isEqualToString:kSettingsDSDoubleTapToLock];
}

static BOOL settings_key_affects_package_state(NSString *key)
{
    return [key isEqualToString:kSettingsSBCEnabled] ||
           [key isEqualToString:kSettingsPowercuffEnabled] ||
           [key isEqualToString:kSettingsStatBarEnabled] ||
           [key isEqualToString:kSettingsRSSIDisplayEnabled] ||
           [key isEqualToString:kSettingsAxonLiteEnabled] ||
           settings_key_is_dark_tweak(key);
}

static void settings_schedule_live_apply_for_key(NSString *key)
{
    if (settings_cleanup_in_progress()) {
        printf("[SETTINGS] live apply skipped during cleanup for %s\n", key.UTF8String);
        return;
    }

    if (!settings_device_supported()) {
        printf("[SETTINGS] live apply blocked for %s: %s\n",
               key.UTF8String, settings_unsupported_message().UTF8String);
        return;
    }

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];

    if (settings_key_is_axonlite(key)) {
        if ([d boolForKey:kSettingsAxonLiteEnabled] && g_springboard_rc_ready) {
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                @synchronized (settings_rc_lock()) {
                    if (settings_cleanup_in_progress() || !g_springboard_rc_ready) return;
                    bool ok = axonlite_apply_in_session();
                    settings_mark_tweak_applied(kSettingsAxonLiteEnabled,
                                                ok && [d boolForKey:kSettingsAxonLiteEnabled]);
                    printf("[SETTINGS] live Axon Lite apply result=%d\n", ok);
                }
                settings_start_axonlite_live_loop();
                settings_notify_package_queue_changed_async();
            });
        } else if (![d boolForKey:kSettingsAxonLiteEnabled]) {
            g_axonlite_live_stop_requested = 1;
            settings_mark_tweak_applied(kSettingsAxonLiteEnabled, NO);
            settings_notify_package_queue_changed_async();
            if (g_springboard_rc_ready) {
                dispatch_async(dispatch_get_global_queue(0, 0), ^{
                    @synchronized (settings_rc_lock()) {
                        if (g_springboard_rc_ready) axonlite_stop_in_session();
                    }
                });
            }
        }
        return;
    }

    if (settings_key_is_statbar(key)) {
        if ([d boolForKey:kSettingsStatBarEnabled] && g_springboard_rc_ready) {
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                @synchronized (settings_rc_lock()) {
                    if (settings_cleanup_in_progress() || !g_springboard_rc_ready) return;
                    bool ok = statbar_apply_in_session([d boolForKey:kSettingsStatBarCelsius],
                                                       [d boolForKey:kSettingsStatBarHideNet]);
                    settings_mark_tweak_applied(kSettingsStatBarEnabled,
                                                ok && [d boolForKey:kSettingsStatBarEnabled]);
                    printf("[SETTINGS] live StatBar apply result=%d\n", ok);
                }
                settings_start_statbar_live_loop();
                settings_notify_package_queue_changed_async();
            });
        } else if (![d boolForKey:kSettingsStatBarEnabled]) {
            g_statbar_live_stop_requested = 1;
            settings_mark_tweak_applied(kSettingsStatBarEnabled, NO);
            settings_notify_package_queue_changed_async();
            settings_end_statbar_background_task_async("StatBar disabled");
            if (g_springboard_rc_ready) {
                dispatch_async(dispatch_get_global_queue(0, 0), ^{
                    @synchronized (settings_rc_lock()) {
                        if (g_springboard_rc_ready) statbar_stop_in_session();
                    }
                });
            }
        }
    }

    if (settings_key_is_rssi(key)) {
        if (!settings_rssi_install_allowed()) {
            if ([d boolForKey:kSettingsRSSIDisplayEnabled]) {
                [d setBool:NO forKey:kSettingsRSSIDisplayEnabled];
                [d synchronize];
            }
            g_rssi_live_stop_requested = 1;
            settings_mark_tweak_applied(kSettingsRSSIDisplayEnabled, NO);
            settings_notify_package_queue_changed_async();
            if (g_springboard_rc_ready) {
                dispatch_async(dispatch_get_global_queue(0, 0), ^{
                    @synchronized (settings_rc_lock()) {
                        if (g_springboard_rc_ready) rssidisplay_stop_in_session();
                    }
                });
            }
            return;
        }
        if ([d boolForKey:kSettingsRSSIDisplayEnabled] && g_springboard_rc_ready) {
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                @synchronized (settings_rc_lock()) {
                    if (settings_cleanup_in_progress() || !g_springboard_rc_ready) return;
                    bool ok = rssidisplay_apply_in_session([d boolForKey:kSettingsRSSIDisplayWifi],
                                                           [d boolForKey:kSettingsRSSIDisplayCell]);
                    settings_mark_tweak_applied(kSettingsRSSIDisplayEnabled,
                                                ok && [d boolForKey:kSettingsRSSIDisplayEnabled]);
                    printf("[SETTINGS] live RSSI apply result=%d\n", ok);
                }
                settings_start_rssi_live_loop();
                settings_notify_package_queue_changed_async();
            });
        } else if (![d boolForKey:kSettingsRSSIDisplayEnabled]) {
            g_rssi_live_stop_requested = 1;
            settings_mark_tweak_applied(kSettingsRSSIDisplayEnabled, NO);
            settings_notify_package_queue_changed_async();
            if (g_springboard_rc_ready) {
                dispatch_async(dispatch_get_global_queue(0, 0), ^{
                    @synchronized (settings_rc_lock()) {
                        if (g_springboard_rc_ready) rssidisplay_stop_in_session();
                    }
                });
            }
        }
        return;
    }

    if (settings_key_is_dark_tweak(key)) {
        if (!g_springboard_rc_ready || ![d boolForKey:key]) return;
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            @synchronized (settings_rc_lock()) {
                if (settings_cleanup_in_progress() || !g_springboard_rc_ready) return;
                bool ok = settings_apply_dark_tweaks_from_defaults_locked(d);
                for (NSString *darkKey in @[
                    kSettingsDSDisableAppLibrary,
                    kSettingsDSDisableIconFlyIn,
                    kSettingsDSZeroWakeAnimation,
                    kSettingsDSZeroBacklightFade,
                    kSettingsDSDoubleTapToLock,
                ]) {
                    if ([d boolForKey:darkKey]) settings_mark_tweak_applied(darkKey, ok);
                }
                printf("[SETTINGS] live DarkSword tweaks apply result=%d\n", ok);
            }
            settings_notify_package_queue_changed_async();
        });
        return;
    }

    if (!settings_key_is_sbc(key) || !g_springboard_rc_ready) return;

    uint64_t generation = __sync_add_and_fetch(&g_sbc_live_apply_generation, 1);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(250 * NSEC_PER_MSEC)),
                   dispatch_get_global_queue(0, 0), ^{
        if (generation != g_sbc_live_apply_generation) return;
        if (settings_cleanup_in_progress()) return;

        @synchronized (settings_rc_lock()) {
            if (settings_cleanup_in_progress() || !g_springboard_rc_ready) return;
            bool ok = settings_apply_sbc_from_defaults_locked(d);
            settings_mark_tweak_applied(kSettingsSBCEnabled,
                                        ok && [d boolForKey:kSettingsSBCEnabled]);
            printf("[SETTINGS] live SBC apply result=%d\n", ok);
        }
        settings_notify_package_queue_changed_async();
    });
}

void settings_register_defaults(void)
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults registerDefaults:@{
        kSettingsAutoRunKexploit:    @NO,
        kSettingsRunSandboxEscape:   @YES,
        kSettingsRunPatchSandboxExt: @NO,
        kSettingsKeepAlive:          @YES,

        kSettingsSBCEnabled:    @NO,
        kSettingsSBCDockIcons:  @(kSBCDefaultDockIcons),
        kSettingsSBCCols:       @(kSBCDefaultCols),
        kSettingsSBCRows:       @(kSBCDefaultRows),
        kSettingsSBCHideLabels: @(kSBCDefaultHideLabels),

        kSettingsPowercuffEnabled: @NO,
        kSettingsPowercuffLevel:   @"heavy",

        kSettingsDSDisableAppLibrary: @NO,
        kSettingsDSDisableIconFlyIn:  @NO,
        kSettingsDSZeroWakeAnimation: @NO,
        kSettingsDSZeroBacklightFade: @NO,
        kSettingsDSDoubleTapToLock:   @NO,

        kSettingsStatBarEnabled: @NO,
        kSettingsStatBarCelsius: @NO,
        kSettingsStatBarHideNet: @NO,

        kSettingsRSSIDisplayEnabled: @NO,
        kSettingsRSSIDisplayWifi:    @YES,
        kSettingsRSSIDisplayCell:    @YES,

        kSettingsAxonLiteEnabled: @NO,
    }];
    // Signal Readouts is temporarily blocked from installation because its
    // live RemoteCall refresh still interferes with other SpringBoard tweaks.
    if ([defaults boolForKey:kSettingsRSSIDisplayEnabled]) {
        [defaults setBool:NO forKey:kSettingsRSSIDisplayEnabled];
        [defaults synchronize];
    }
    settings_install_screen_awake_observers();
}

void settings_run_actions(void)
{
    if (!settings_device_supported()) {
        printf("[SETTINGS] run blocked: %s\n", settings_unsupported_message().UTF8String);
        log_user("[RUN] %s\n", settings_unsupported_message().UTF8String);
        return;
    }

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        if (__sync_lock_test_and_set(&g_settings_actions_running, 1)) {
            __sync_lock_test_and_set(&g_settings_actions_rerun_requested, 1);
            printf("[SETTINGS] actions already running; queued one follow-up run\n");
            log_user("[RUN] Already running. Queued one follow-up run for the latest package state.\n");
            return;
        }
        log_session_begin();
        @try {
            BOOL patchSandboxExt = [d boolForKey:kSettingsRunPatchSandboxExt];
            BOOL runPowercuff = [d boolForKey:kSettingsPowercuffEnabled];
            BOOL runSandboxEscape = [d boolForKey:kSettingsRunSandboxEscape];
            BOOL runSBC = [d boolForKey:kSettingsSBCEnabled];
            BOOL runDarkTweaks = settings_dark_tweaks_any_enabled(d);
            BOOL runStatBar = [d boolForKey:kSettingsStatBarEnabled];
            BOOL runRSSI = settings_rssi_install_allowed() && [d boolForKey:kSettingsRSSIDisplayEnabled];
            BOOL runAxonLite = [d boolForKey:kSettingsAxonLiteEnabled];
            BOOL needsSpringBoard = runSandboxEscape || runSBC || runDarkTweaks || runStatBar || runRSSI || runAxonLite;

            NSUInteger total = 1;
            if (patchSandboxExt) total++;
            if (runPowercuff) total++;
            if (needsSpringBoard) total++;
            if (runSandboxEscape) total++;
            if (runSBC) total++;
            if (runDarkTweaks) total++;
            if (runStatBar) total++;
            if (runRSSI) total++;
            if (runAxonLite) total++;
            NSUInteger step = 0;

            settings_log_run_context();
            log_user("[RUN] Verbose trace active; raw debug stream is mirrored into the app log.\n");
            log_user("[PLAN] stages=%lu springboard=%s sbc=%s dark=%s statbar=%s rssi=%s axon=%s power=%s\n",
                     (unsigned long)total,
                     needsSpringBoard ? "yes" : "no",
                     runSBC ? "yes" : "no",
                     runDarkTweaks ? "yes" : "no",
                     runStatBar ? "yes" : "no",
                     runRSSI ? "yes" : "no",
                     runAxonLite ? "yes" : "no",
                     runPowercuff ? "yes" : "no");
            if (runSBC) {
                log_user("[PLAN] Home layout target: dock=%ld home=%ldx%ld labels=%s\n",
                         (long)[d integerForKey:kSettingsSBCDockIcons],
                         (long)[d integerForKey:kSettingsSBCCols],
                         (long)[d integerForKey:kSettingsSBCRows],
                         [d boolForKey:kSettingsSBCHideLabels] ? "hidden" : "shown");
            }
            if (runStatBar) {
                log_user("[PLAN] StatBar target: temp=%s network=%s refresh=1s\n",
                         [d boolForKey:kSettingsStatBarCelsius] ? "C" : "F",
                         [d boolForKey:kSettingsStatBarHideNet] ? "hidden" : "shown");
            }
            if (runRSSI) {
                log_user("[PLAN] RSSI display target: wifi=%s cell=%s refresh=1s\n",
                         [d boolForKey:kSettingsRSSIDisplayWifi] ? "on" : "off",
                         [d boolForKey:kSettingsRSSIDisplayCell] ? "on" : "off");
            }
            if (runAxonLite) {
                log_user("[PLAN] Axon Lite target: segmented notification hub refresh=1.2s\n");
            }
            if (runPowercuff) {
                NSString *lvl = [d stringForKey:kSettingsPowercuffLevel] ?: @"heavy";
                log_user("[PLAN] Powercuff target: thermalmonitord level=%s\n", lvl.UTF8String);
            }

            settings_progress(&step, total, "Preparing KRW primitives (socket/IOSurface path)");
            if (!settings_ensure_kexploit()) {
                log_user("[RUN] Failed: kernel primitives were not acquired.\n");
                return;
            }
            log_user("[OK] Kernel primitives ready; RemoteCall can be staged.\n");

            if (patchSandboxExt) {
                settings_progress(&step, total, "Patching sandbox-extension issue path");
                escape_sbx_demo3();
                log_user("[OK] Sandbox-extension patch stage finished.\n");
            }
            printf("[SETTINGS] actions escape=%d patch=%d sbc=%d dock=%ld hs=%ldx%ld hideLabels=%d dark=%d power=%d level=%s statbar=%d celsius=%d hideNet=%d rssi=%d rssiWifi=%d rssiCell=%d axon=%d rcReady=%d\n",
                   runSandboxEscape,
                   patchSandboxExt,
                   runSBC,
                   (long)[d integerForKey:kSettingsSBCDockIcons],
                   (long)[d integerForKey:kSettingsSBCCols],
                   (long)[d integerForKey:kSettingsSBCRows],
                   [d boolForKey:kSettingsSBCHideLabels],
                   runDarkTweaks,
                   runPowercuff,
                   ([d stringForKey:kSettingsPowercuffLevel] ?: @"").UTF8String,
                   runStatBar,
                   [d boolForKey:kSettingsStatBarCelsius],
                   [d boolForKey:kSettingsStatBarHideNet],
                   runRSSI,
                   [d boolForKey:kSettingsRSSIDisplayWifi],
                   [d boolForKey:kSettingsRSSIDisplayCell],
                   runAxonLite,
                   g_springboard_rc_ready);

            if (runPowercuff) {
                settings_progress(&step, total, "Applying Powercuff via thermalmonitord");
                @synchronized (settings_rc_lock()) {
                    if (g_springboard_rc_ready) {
                        axonlite_stop_in_session();
                        rssidisplay_stop_in_session();
                    }
                    settings_destroy_springboard_remote_call_locked("switching to thermalmonitord");
                    NSString *lvl = [d stringForKey:kSettingsPowercuffLevel] ?: @"heavy";
                    bool ok = powercuff_apply(lvl.UTF8String);
                    settings_mark_tweak_applied(kSettingsPowercuffEnabled,
                                                ok && [d boolForKey:kSettingsPowercuffEnabled]);
                    log_user("%s Powercuff %s through thermalmonitord.\n",
                             ok ? "[OK]" : "[WARN]",
                             ok ? "applied" : "did not apply cleanly");
                }
            }

            if (needsSpringBoard) {
                @synchronized (settings_rc_lock()) {
                    settings_progress(&step, total, "Opening SpringBoard RemoteCall session");
                    if (!settings_ensure_springboard_remote_call_locked()) {
                        log_user("[RUN] Failed: could not open the SpringBoard control session.\n");
                        return;
                    }
                    log_user("[OK] SpringBoard RemoteCall ready.\n");

                    if (runSandboxEscape && !g_springboard_sandbox_escaped) {
                        settings_progress(&step, total, "Consuming SpringBoard sandbox extension");
                        int sbx = escape_sbx_demo2_in_session();
                        g_springboard_sandbox_escaped = (sbx == 0);
                        printf("[SETTINGS] sandbox escape in session result=%d\n", sbx);
                        log_user("%s SpringBoard filesystem token %s.\n",
                                 sbx == 0 ? "[OK]" : "[WARN]",
                                 sbx == 0 ? "consumed" : "returned a warning");
                    } else if (runSandboxEscape) {
                        printf("[SETTINGS] sandbox escape already consumed for this SpringBoard session\n");
                        settings_progress(&step, total, "Reusing SpringBoard sandbox token");
                        log_user("[OK] SpringBoard filesystem token already consumed.\n");
                    }

                    if (runSBC) {
                        settings_progress(&step, total, "Applying icon layout caches");
                        bool ok = settings_apply_sbc_from_defaults_locked(d);
                        settings_mark_tweak_applied(kSettingsSBCEnabled,
                                                    ok && [d boolForKey:kSettingsSBCEnabled]);
                        printf("[SETTINGS] SBC result=%d\n", ok);
                        log_user("%s Home screen layout %s; dock=%ld home=%ldx%ld.\n",
                                 ok ? "[OK]" : "[WARN]",
                                 ok ? "applied" : "may need a refresh",
                                 (long)[d integerForKey:kSettingsSBCDockIcons],
                                 (long)[d integerForKey:kSettingsSBCCols],
                                 (long)[d integerForKey:kSettingsSBCRows]);
                    }

                    if (runDarkTweaks) {
                        settings_progress(&step, total, "Applying DarkSword runtime hooks");
                        bool ok = settings_apply_dark_tweaks_from_defaults_locked(d);
                        for (NSString *key in @[
                            kSettingsDSDisableAppLibrary,
                            kSettingsDSDisableIconFlyIn,
                            kSettingsDSZeroWakeAnimation,
                            kSettingsDSZeroBacklightFade,
                            kSettingsDSDoubleTapToLock,
                        ]) {
                            if ([d boolForKey:key]) settings_mark_tweak_applied(key, ok);
                        }
                        printf("[SETTINGS] DarkSword tweaks result=%d\n", ok);
                        log_user("%s DarkSword hooks %s.\n",
                                 ok ? "[OK]" : "[WARN]",
                                 ok ? "applied" : "may need a refresh");
                    }

                    if (runStatBar) {
                        settings_progress(&step, total, "Starting StatBar overlay and 1s feed");
                        bool ok = statbar_apply_in_session([d boolForKey:kSettingsStatBarCelsius],
                                                           [d boolForKey:kSettingsStatBarHideNet]);
                        settings_mark_tweak_applied(kSettingsStatBarEnabled,
                                                    ok && [d boolForKey:kSettingsStatBarEnabled]);
                        printf("[SETTINGS] StatBar result=%d\n", ok);
                        log_user("%s StatBar %s.\n",
                                 ok ? "[OK]" : "[WARN]",
                                 ok ? "receiving live data" : "did not start cleanly");
                    }

                    if (runRSSI) {
                        settings_progress(&step, total, "Starting RSSI dBm signal overlays");
                        bool ok = rssidisplay_apply_in_session([d boolForKey:kSettingsRSSIDisplayWifi],
                                                               [d boolForKey:kSettingsRSSIDisplayCell]);
                        settings_mark_tweak_applied(kSettingsRSSIDisplayEnabled,
                                                    ok && [d boolForKey:kSettingsRSSIDisplayEnabled]);
                        printf("[SETTINGS] RSSI result=%d\n", ok);
                        log_user("%s RSSI signal overlays %s.\n",
                                 ok ? "[OK]" : "[WARN]",
                                 ok ? "live" : "did not start cleanly");
                    }

                    if (runAxonLite) {
                        settings_progress(&step, total, "Starting Axon Lite notification hub");
                        // First call: force the cover-sheet chain to
                        // materialize and bind data sources.
                        // Subsequent calls: let the now-populated CLVC
                        // settle through the model → cache → bundles
                        // pipeline before the user opens the lock screen.
                        bool ok = false;
                        for (int i = 0; i < 3; i++) {
                            bool tickOK = axonlite_apply_in_session();
                            if (tickOK) ok = true;
                            if (i + 1 < 3) usleep(250000);
                        }
                        settings_mark_tweak_applied(kSettingsAxonLiteEnabled,
                                                    ok && [d boolForKey:kSettingsAxonLiteEnabled]);
                        printf("[SETTINGS] Axon Lite result=%d\n", ok);
                        log_user("%s Axon Lite %s.\n",
                                 ok ? "[OK]" : "[WARN]",
                                 ok ? "overlay is live" : "did not start cleanly");
                    }
                }

                if (runStatBar) {
                    settings_start_statbar_live_loop();
                } else {
                    g_statbar_live_stop_requested = 1;
                }
                if (runRSSI) {
                    settings_start_rssi_live_loop();
                } else {
                    g_rssi_live_stop_requested = 1;
                }
                if (runAxonLite) {
                    settings_start_axonlite_live_loop();
                } else {
                    g_axonlite_live_stop_requested = 1;
                }
            }

            log_user("[DONE] Run complete. Verbose trace captured the raw call stream.\n");
        } @finally {
            log_session_end();
            __sync_lock_release(&g_settings_actions_running);
            settings_reconcile_applied_from_defaults();
            if (__sync_bool_compare_and_swap(&g_settings_actions_rerun_requested, 1, 0)) {
                log_user("[RUN] Applying queued follow-up run.\n");
                settings_run_actions();
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:PackageQueueDidChangeNotification
                                                                    object:[PackageQueue sharedQueue]];
                [[NSNotificationCenter defaultCenter] postNotificationName:kSettingsActionsDidCompleteNotification
                                                                    object:nil];
                cyanide_upload_log_if_enabled();
            });
        }
    });
}

typedef NS_ENUM(NSInteger, SettingsSection) {
    SectionWarning = 0,
    SectionLaunch,
    SectionActions,
    SectionOTA,
    SectionSBC,
    SectionStatBar,
    SectionRSSI,
    SectionAxonLite,
    SectionPowercuff,
    SectionDarkSwordTweaks,
    SectionCount,
};

typedef NS_ENUM(NSInteger, RootSection) {
    RootSectionWarning = 0,
    RootSectionActions,
    RootSectionTweakBundles,
    RootSectionSystemBundles,
    RootSectionAbout,
    RootSectionCount,
};

@interface SettingsViewController ()
@property (nonatomic, strong) UISegmentedControl *powercuffSegmented;
@property (nonatomic, assign) BOOL pendingManualActionsReload;
@property (nonatomic, assign) BOOL detailMode;
@property (nonatomic, assign) NSInteger underlyingSection;
@property (nonatomic, copy)   NSString *bundleTitle;
@end

@implementation SettingsViewController

- (instancetype)initWithCoder:(NSCoder *)coder
{
    // Calling [super initWithCoder:] (not initWithStyle:) so UIViewController's
    // unarchiving runs: that's what wires up the parentViewController and
    // navigationController relationships established by the storyboard's
    // rootViewController segue. Going through initWithStyle leaves nav nil.
    if ((self = [super initWithCoder:coder])) {
        _underlyingSection = NSIntegerMax;
    }
    return self;
}

- (instancetype)initWithUnderlyingSection:(NSInteger)underlyingSection
                              bundleTitle:(NSString *)bundleTitle
{
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _detailMode = YES;
        _underlyingSection = underlyingSection;
        _bundleTitle = [bundleTitle copy];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = self.detailMode ? (self.bundleTitle ?: @"Settings") : @"Settings";
    self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAlways;
    self.tableView.rowHeight                      = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight             = 44.0;
    self.tableView.sectionHeaderHeight            = UITableViewAutomaticDimension;
    self.tableView.estimatedSectionHeaderHeight   = 20.0;
    self.tableView.sectionFooterHeight            = UITableViewAutomaticDimension;
    self.tableView.estimatedSectionFooterHeight   = 10.0;
    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 0.0;
    }
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"toggle"];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"stepper"];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"segmented"];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"action"];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"button"];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"warning"];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"bundle"];
    [self installInstallerReturnButtonIfNeeded];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(remoteCallStateDidChange:)
                                                 name:kSettingsRemoteCallStateDidChangeNotification
                                               object:nil];
}

- (void)installInstallerReturnButtonIfNeeded
{
    if (!self.installerReturnPackageName) return;

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:17.0 weight:UIImageSymbolWeightSemibold];
    UIImage *chevron = [UIImage systemImageNamed:@"chevron.backward" withConfiguration:cfg];
    [btn setImage:chevron forState:UIControlStateNormal];
    [btn setTitle:[@" " stringByAppendingString:self.installerReturnPackageName] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightRegular];
    btn.tintColor = self.view.tintColor;
    btn.contentEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 4);
    [btn addTarget:self action:@selector(returnToInstaller) forControlEvents:UIControlEventTouchUpInside];
    [btn sizeToFit];

    UIBarButtonItem *backItem = [[UIBarButtonItem alloc] initWithCustomView:btn];
    self.navigationItem.leftBarButtonItem = backItem;
    self.navigationItem.hidesBackButton = YES;
}

- (void)returnToInstaller
{
    UITabBarController *tab = self.tabBarController;
    UINavigationController *settingsNav = self.navigationController;
    NSUInteger installerIdx = NSNotFound;
    for (NSUInteger i = 0; i < tab.viewControllers.count; i++) {
        UIViewController *vc = tab.viewControllers[i];
        if ([vc.tabBarItem.title isEqualToString:@"Installer"]) {
            installerIdx = i;
            break;
        }
    }
    [settingsNav popToRootViewControllerAnimated:NO];
    if (installerIdx != NSNotFound) {
        tab.selectedIndex = installerIdx;
    }
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self reloadManualActions];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if (!self.pendingManualActionsReload) return;
    self.pendingManualActionsReload = NO;
    [self reloadManualActions];
}

- (void)remoteCallStateDidChange:(NSNotification *)notification
{
    [self reloadManualActions];
}

- (void)reloadManualActions
{
    if (!self.isViewLoaded) return;
    if (self.detailMode) return;
    if (!self.tableView.window) {
        self.pendingManualActionsReload = YES;
        return;
    }
    NSIndexSet *sections = [NSIndexSet indexSetWithIndex:RootSectionActions];
    [self.tableView reloadSections:sections withRowAnimation:UITableViewRowAnimationNone];
}

- (UITableViewCell *)buildWarningCell:(UITableViewCell *)cell
{
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.text = nil;
    for (UIView *v in [cell.contentView.subviews copy]) [v removeFromSuperview];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"info.circle.fill"]];
    icon.tintColor = UIColor.systemOrangeColor;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [icon setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [icon setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UILabel *label = [[UILabel alloc] init];
    label.text = @"Not a traditional jailbreak: tweaks apply in real time over RemoteCall — no respring needed. Whenever a change kicks off an operation, a live log opens automatically; you can hide it any time. Force-quitting this app from the App Switcher stops live tweaks like StatBar and Axon Lite.";
    label.textColor = UIColor.labelColor;
    label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    label.numberOfLines = 0;
    label.translatesAutoresizingMaskIntoConstraints = NO;

    [cell.contentView addSubview:icon];
    [cell.contentView addSubview:label];
    UILayoutGuide *m = cell.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor   constraintEqualToAnchor:m.leadingAnchor],
        [icon.centerYAnchor   constraintEqualToAnchor:label.centerYAnchor],
        [icon.widthAnchor     constraintEqualToConstant:22],
        [icon.heightAnchor    constraintEqualToConstant:22],
        [label.leadingAnchor  constraintEqualToAnchor:icon.trailingAnchor constant:10],
        [label.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
        [label.topAnchor      constraintEqualToAnchor:m.topAnchor constant:4],
        [label.bottomAnchor   constraintEqualToAnchor:m.bottomAnchor constant:-4],
    ]];
    return cell;
}

#pragma mark - Row models

- (NSArray<NSDictionary *> *)launchRows
{
    return @[
        @{ @"key": kSettingsAutoRunKexploit,    @"title": @"Auto-run kexploit on launch" },
        @{ @"key": kSettingsRunSandboxEscape,   @"title": @"Sandbox escape (escape_sbx_demo2)" },
        @{ @"key": kSettingsKeepAlive,          @"title": @"Keep app alive in background",
           @"subtitle": @"Required for app-driven live tweaks to persist while minimized, including StatBar receiving fresh live data." },
    ];
}

// The master enable / install-equivalent rows have been removed from each
// tweak's row list — install/uninstall is handled by the Installer tab's
// Install button. Settings only shows configuration knobs.

- (NSArray<NSDictionary *> *)sbcRows
{
    return @[
        @{ @"kind": @"stepper", @"key": kSettingsSBCDockIcons,  @"title": @"Dock icons", @"min": @4, @"max": @7, @"default": @(kSBCDefaultDockIcons) },
        @{ @"kind": @"stepper", @"key": kSettingsSBCCols,       @"title": @"Home columns", @"min": @3, @"max": @7, @"default": @(kSBCDefaultCols) },
        @{ @"kind": @"stepper", @"key": kSettingsSBCRows,       @"title": @"Home rows", @"min": @4, @"max": @8, @"default": @(kSBCDefaultRows) },
        @{ @"kind": @"toggle",  @"key": kSettingsSBCHideLabels, @"title": @"Hide icon labels" },
        @{ @"kind": @"button",  @"title": @"Reset to Defaults" },
    ];
}

- (NSArray<NSDictionary *> *)powercuffRows
{
    return @[
        @{ @"kind": @"segmented", @"key": kSettingsPowercuffLevel,   @"title": @"Level" },
    ];
}

- (NSArray<NSDictionary *> *)otaRows
{
    return @[];
}

- (NSArray<NSDictionary *> *)darkSwordTweakRows
{
    return @[];
}

- (NSArray<NSDictionary *> *)statbarRows
{
    return @[
        @{ @"kind": @"toggle", @"key": kSettingsStatBarCelsius, @"title": @"Celsius" },
        @{ @"kind": @"toggle", @"key": kSettingsStatBarHideNet, @"title": @"Hide network speed" },
    ];
}

- (NSArray<NSDictionary *> *)rssiRows
{
    return @[
        @{ @"kind": @"toggle", @"key": kSettingsRSSIDisplayWifi, @"title": @"WiFi (bar count)" },
        @{ @"kind": @"toggle", @"key": kSettingsRSSIDisplayCell, @"title": @"Cellular (dBm)" },
    ];
}

- (NSArray<NSDictionary *> *)axonLiteRows
{
    return @[];
}

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)settingsSummaryForSection:(NSInteger)section
{
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSMutableArray *out = [NSMutableArray array];
    if (section == SectionSBC) {
        [out addObject:@{@"title": @"Dock icons",       @"value": [@([d integerForKey:kSettingsSBCDockIcons])  stringValue]}];
        [out addObject:@{@"title": @"Home columns",     @"value": [@([d integerForKey:kSettingsSBCCols])        stringValue]}];
        [out addObject:@{@"title": @"Home rows",        @"value": [@([d integerForKey:kSettingsSBCRows])        stringValue]}];
        [out addObject:@{@"title": @"Hide icon labels", @"value": [d boolForKey:kSettingsSBCHideLabels] ? @"On" : @"Off"}];
    } else if (section == SectionStatBar) {
        [out addObject:@{@"title": @"Celsius",          @"value": [d boolForKey:kSettingsStatBarCelsius] ? @"On" : @"Off"}];
        [out addObject:@{@"title": @"Hide net speed",   @"value": [d boolForKey:kSettingsStatBarHideNet]  ? @"On" : @"Off"}];
    } else if (section == SectionRSSI) {
        [out addObject:@{@"title": @"WiFi (bar count)", @"value": [d boolForKey:kSettingsRSSIDisplayWifi] ? @"On" : @"Off"}];
        [out addObject:@{@"title": @"Cellular (dBm)",   @"value": [d boolForKey:kSettingsRSSIDisplayCell] ? @"On" : @"Off"}];
    } else if (section == SectionPowercuff) {
        NSString *lvl = [d stringForKey:kSettingsPowercuffLevel] ?: @"heavy";
        [out addObject:@{@"title": @"Level", @"value": lvl}];
    }
    return out;
}

- (NSArray<NSDictionary *> *)rowsForSection:(NSInteger)s
{
    switch (s) {
        case SectionLaunch:    return self.launchRows;
        case SectionSBC:       return self.sbcRows;
        case SectionDarkSwordTweaks: return self.darkSwordTweakRows;
        case SectionOTA:       return self.otaRows;
        case SectionPowercuff: return self.powercuffRows;
        case SectionStatBar:   return self.statbarRows;
        case SectionRSSI:      return self.rssiRows;
        case SectionAxonLite:  return self.axonLiteRows;
        default: return @[];
    }
}

#pragma mark - Bundle rows (root mode)

// Bundles whose underlying section has zero configuration rows are filtered
// out — install/uninstall is the only operation those tweaks expose, and
// that's already in the Installer tab.

- (NSArray<NSDictionary *> *)allTweakBundleRows
{
    return @[
        @{ @"title": @"Launch Options",     @"icon": @"bolt.fill",                          @"color": [UIColor systemRedColor],    @"section": @(SectionLaunch) },
        @{ @"title": @"SBCustomizer",       @"icon": @"square.grid.3x3.fill",                @"color": [UIColor systemBlueColor],   @"section": @(SectionSBC) },
        @{ @"title": @"StatBar",            @"icon": @"thermometer.medium",                  @"color": [UIColor systemRedColor],    @"section": @(SectionStatBar) },
        @{ @"title": @"Signal Display",     @"icon": @"antenna.radiowaves.left.and.right",   @"color": [UIColor systemBlueColor],   @"section": @(SectionRSSI) },
        @{ @"title": @"Axon Lite",          @"icon": @"bell.badge.fill",                     @"color": [UIColor systemRedColor],    @"section": @(SectionAxonLite) },
        @{ @"title": @"Powercuff",          @"icon": @"bolt.slash.fill",                     @"color": [UIColor systemOrangeColor], @"section": @(SectionPowercuff) },
        @{ @"title": @"SpringBoard Tweaks", @"icon": @"apps.iphone",                         @"color": [UIColor systemIndigoColor], @"section": @(SectionDarkSwordTweaks) },
    ];
}

- (NSArray<NSDictionary *> *)allSystemBundleRows
{
    return @[
        @{ @"title": @"OTA Updates", @"icon": @"icloud.slash.fill", @"color": [UIColor systemGrayColor], @"section": @(SectionOTA) },
    ];
}

- (NSArray<NSDictionary *> *)filterBundles:(NSArray<NSDictionary *> *)bundles
{
    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    for (NSDictionary *bundle in bundles) {
        NSInteger sec = [bundle[@"section"] integerValue];
        if ([self rowsForSection:sec].count > 0) {
            [out addObject:bundle];
        }
    }
    return out;
}

- (NSArray<NSDictionary *> *)tweakBundleRows
{
    return [self filterBundles:[self allTweakBundleRows]];
}

- (NSArray<NSDictionary *> *)systemBundleRows
{
    return [self filterBundles:[self allSystemBundleRows]];
}

- (NSArray<NSDictionary *> *)bundleRowsForRootSection:(RootSection)section
{
    if (section == RootSectionTweakBundles)  return self.tweakBundleRows;
    if (section == RootSectionSystemBundles) return self.systemBundleRows;
    return @[];
}

#pragma mark - Table data

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return self.detailMode ? 1 : RootSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (self.detailMode) {
        return (NSInteger)[self rowsForSection:self.underlyingSection].count;
    }
    switch ((RootSection)section) {
        case RootSectionWarning:        return 1;
        case RootSectionActions:        return 4;
        case RootSectionTweakBundles:   return (NSInteger)self.tweakBundleRows.count;
        case RootSectionSystemBundles:  return (NSInteger)self.systemBundleRows.count;
        case RootSectionAbout:          return 4;
        case RootSectionCount:          return 0;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (self.detailMode) return nil;
    switch ((RootSection)section) {
        case RootSectionActions:        return @"Quick Actions";
        case RootSectionTweakBundles:   return self.tweakBundleRows.count   > 0 ? @"Tweaks" : nil;
        case RootSectionSystemBundles:  return self.systemBundleRows.count  > 0 ? @"System" : nil;
        case RootSectionAbout:          return @"About";
        default:                        return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (!self.detailMode) return nil;
    NSInteger s = self.underlyingSection;
    if (s == SectionLaunch) {
        return @"kexploit_opa334 runs once per app lifetime. Keep Alive applies only while Cyanide is minimized; an App Switcher kill still terminates the process.";
    }
    if (s == SectionSBC) {
        return [NSString stringWithFormat:@"Stock iOS defaults: dock %ld, columns %ld, rows %ld.",
                (long)kSBCDefaultDockIcons, (long)kSBCDefaultCols, (long)kSBCDefaultRows];
    }
    if (s == SectionDarkSwordTweaks) {
        return @"Imported from DarkSword-Tweaks. These are SpringBoard runtime patches; turning one off only skips future applies.";
    }
    if (s == SectionOTA) {
        return @"Edits launchd disabled.plist. A reboot or userspace restart is required for changes to take effect.";
    }
    if (s == SectionPowercuff) {
        return @"Underclocks the CPU/GPU via thermalmonitord by simulating a thermal pressure level. Lasts until reboot. Heavier levels save battery at the cost of responsiveness.";
    }
    if (s == SectionStatBar) {
        return @"Live overlay. When enabled, StatBar keeps a SpringBoard RemoteCall session open and refreshes once per second until toggled off.";
    }
    if (s == SectionRSSI) {
        return @"Adds a UILabel as a sibling of each STUI signal view (no new UIWindow), refreshed every second. Cellular shows live RSRP dBm (sign implicit). WiFi shows the bar count (0-4); the wifid XPC dBm path crashed SpringBoard in prior tests.";
    }
    if (s == SectionAxonLite) {
        return @"RemoteCall-only Axon port. It uses a live app-side loop rather than substrate hooks, so it lasts for the active Cyanide SpringBoard session.";
    }
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    if (!self.detailMode) {
        if (section == RootSectionWarning) return 18.0; // breathing room above warning
        if ((RootSection)section == RootSectionTweakBundles  && self.tweakBundleRows.count  == 0) return CGFLOAT_MIN;
        if ((RootSection)section == RootSectionSystemBundles && self.systemBundleRows.count == 0) return CGFLOAT_MIN;
    }
    return UITableViewAutomaticDimension;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{
    if ([self tableView:tableView titleForFooterInSection:section].length > 0)
        return UITableViewAutomaticDimension;
    return 6.0;
}

#pragma mark - Icon badge

+ (UIImage *)iconBadgeWithSymbol:(NSString *)symbol color:(UIColor *)color size:(CGFloat)size
{
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size, size) format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGFloat radius = size * (7.0 / 29.0);
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size, size) cornerRadius:radius];
        [color setFill];
        [path fill];

        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:size * 0.58 weight:UIImageSymbolWeightSemibold];
        UIImage *symbolImage = [UIImage systemImageNamed:symbol withConfiguration:cfg];
        if (symbolImage) {
            UIImage *whiteIcon = [symbolImage imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
            CGFloat x = (size - whiteIcon.size.width) / 2.0;
            CGFloat y = (size - whiteIcon.size.height) / 2.0;
            [whiteIcon drawAtPoint:CGPointMake(x, y)];
        }
    }];
}

#pragma mark - Cells

- (UITableViewCell *)buildBundleCellWithRow:(NSDictionary *)row tableView:(UITableView *)tableView
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"bundle"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"bundle"];
    }
    cell.imageView.image = [SettingsViewController iconBadgeWithSymbol:row[@"icon"] color:row[@"color"] size:29.0];
    cell.textLabel.text = row[@"title"];
    cell.textLabel.font = [UIFont systemFontOfSize:17.0];
    cell.textLabel.textColor = UIColor.labelColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (UITableViewCell *)buildAboutCellAtRow:(NSInteger)row tableView:(UITableView *)tableView
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"about"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"about"];
    }
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.textLabel.font = [UIFont systemFontOfSize:17.0];
    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.detailTextLabel.text = nil;

    if (row == 0) {
        cell.imageView.image = [SettingsViewController iconBadgeWithSymbol:@"at" color:UIColor.systemBlueColor size:29.0];
        cell.textLabel.text = @"Twitter";
        cell.detailTextLabel.text = @"@zeroxjf";
    } else if (row == 1) {
        cell.imageView.image = [SettingsViewController iconBadgeWithSymbol:@"doc.text.magnifyingglass" color:UIColor.systemGrayColor size:29.0];
        cell.textLabel.text = @"View Log";
    } else if (row == 2) {
        cell.imageView.image = [SettingsViewController iconBadgeWithSymbol:@"square.and.arrow.up" color:UIColor.systemGreenColor size:29.0];
        cell.textLabel.text = @"Share Log";
    } else {
        cell.imageView.image = [SettingsViewController iconBadgeWithSymbol:@"icloud.and.arrow.up" color:UIColor.systemIndigoColor size:29.0];
        cell.textLabel.text = @"Auto-Upload Logs";
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = [[NSUserDefaults standardUserDefaults] boolForKey:kSettingsLogUploadEnabled];
        [sw addTarget:self action:@selector(logUploadSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    }
    return cell;
}

- (void)logUploadSwitchChanged:(UISwitch *)sw {
    [[NSUserDefaults standardUserDefaults] setBool:sw.isOn forKey:kSettingsLogUploadEnabled];
}

- (void)openTwitter
{
    NSURL *url = [NSURL URLWithString:@"https://twitter.com/zeroxjf"];
    if (url) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

- (void)openViewLog
{
    NSString *logPath = log_most_recent_session_path();
    NSString *text;
    if (!logPath) {
        text = @"No log yet. Run a chain at least once.";
    } else {
        NSError *err = nil;
        text = [NSString stringWithContentsOfFile:logPath encoding:NSUTF8StringEncoding error:&err];
        if (!text) text = [NSString stringWithFormat:@"Failed to read log: %@", err.localizedDescription];
    }

    UIViewController *vc = [[UIViewController alloc] init];
    vc.title = @"Log";
    vc.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    UITextView *tv = [[UITextView alloc] init];
    tv.translatesAutoresizingMaskIntoConstraints = NO;
    tv.editable = NO;
    tv.font = [UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightRegular];
    tv.textColor = UIColor.labelColor;
    tv.backgroundColor = UIColor.systemGroupedBackgroundColor;
    tv.text = text;
    [vc.view addSubview:tv];
    [NSLayoutConstraint activateConstraints:@[
        [tv.topAnchor      constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.topAnchor],
        [tv.bottomAnchor   constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.bottomAnchor],
        [tv.leadingAnchor  constraintEqualToAnchor:vc.view.leadingAnchor constant:16.0],
        [tv.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor constant:-16.0],
    ]];

    [self.navigationController pushViewController:vc animated:YES];
}

static void cyanide_upload_log_if_enabled(void) {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:kSettingsLogUploadEnabled]) return;
    NSString *path = log_most_recent_session_path();
    if (!path) return;
    NSString *rawLog = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!rawLog.length) return;

    NSString *appVersion = [NSBundle mainBundle].infoDictionary[@"CFBundleShortVersionString"] ?: @"unknown";
    NSString *iosVersion = [UIDevice currentDevice].systemVersion;

    struct utsname sysInfo;
    uname(&sysInfo);
    NSString *machine = [NSString stringWithUTF8String:sysInfo.machine];

    // Prepend a diagnostic header so each uploaded log is self-contained.
    NSString *header = [NSString stringWithFormat:
        @"=== Cyanide Diagnostic Log ===\n"
        @"app_version : %@\n"
        @"ios_version : %@\n"
        @"device      : %@\n"
        @"log_file    : %@\n"
        @"==============================\n\n",
        appVersion, iosVersion, machine, path.lastPathComponent];

    NSDictionary *body = @{
        @"log": [header stringByAppendingString:rawLog],
        @"meta": @{
            @"build":  [NSString stringWithFormat:@"cyanide-%@", appVersion],
            @"source": @"cyanide",
            @"ios":    iosVersion,
            @"device": machine,
        }
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    if (!data) return;
    NSURL *url = [NSURL URLWithString:@"https://brokenblade-weblogs.hackerboii.workers.dev/log"];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = data;
    printf("[LOG] uploading diagnostic log (%zu bytes) to R2...\n", (size_t)data.length);
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        if (e) {
            printf("[LOG] upload failed: %s\n", e.localizedDescription.UTF8String);
        } else {
            NSHTTPURLResponse *http = (NSHTTPURLResponse *)r;
            printf("[LOG] upload ok: HTTP %ld\n", (long)http.statusCode);
        }
    }] resume];
}

- (void)openFeedbackEmail
{
    NSString *logPath = log_most_recent_session_path();
    if (!logPath) {
        UIAlertController *ac = [UIAlertController
            alertControllerWithTitle:@"No Log Yet"
                             message:@"Run a chain at least once to capture a log, then come back here to share it. Logs are also visible in Files app → On My iPhone → Cyanide."
                      preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:ac animated:YES completion:nil];
        return;
    }

    // Stage the log under NSTemporaryDirectory with a .txt extension so the
    // share sheet treats it as plain text in every target app.
    NSURL *src = [NSURL fileURLWithPath:logPath];
    NSString *stem = src.lastPathComponent.stringByDeletingPathExtension;
    NSString *txtName = [stem stringByAppendingPathExtension:@"txt"];
    NSURL *dst = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:txtName]];
    [[NSFileManager defaultManager] removeItemAtURL:dst error:nil];
    NSError *copyErr = nil;
    if (![[NSFileManager defaultManager] copyItemAtURL:src toURL:dst error:&copyErr]) {
        UIAlertController *ac = [UIAlertController
            alertControllerWithTitle:@"Couldn't Stage Log"
                             message:copyErr.localizedDescription ?: @"Failed to prepare the log for sharing."
                      preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:ac animated:YES completion:nil];
        return;
    }

    NSString *logText = [NSString stringWithContentsOfURL:dst encoding:NSUTF8StringEncoding error:nil]
                        ?: @"(empty log)";
    UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:@[logText]
                                                                     applicationActivities:nil];
    // iPad needs a popover anchor; iPhone ignores these properties.
    if (vc.popoverPresentationController) {
        vc.popoverPresentationController.sourceView = self.view;
        vc.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2.0,
                                                                  self.view.bounds.size.height / 2.0,
                                                                  0, 0);
        vc.popoverPresentationController.permittedArrowDirections = 0;
    }
    [self presentViewController:vc animated:YES completion:nil];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Preserve the table view's actual indexPath for dequeue calls (which
    // expect a path that exists in the current data source). `indexPath`
    // is remapped to the underlying SettingsSection for content lookup.
    NSIndexPath *dequeuePath = indexPath;

    if (!self.detailMode) {
        switch ((RootSection)indexPath.section) {
            case RootSectionWarning:
                break; // fall through to legacy SectionWarning rendering below
            case RootSectionActions:
                indexPath = [NSIndexPath indexPathForRow:indexPath.row inSection:SectionActions];
                break;
            case RootSectionTweakBundles:
                return [self buildBundleCellWithRow:self.tweakBundleRows[indexPath.row] tableView:tableView];
            case RootSectionSystemBundles:
                return [self buildBundleCellWithRow:self.systemBundleRows[indexPath.row] tableView:tableView];
            case RootSectionAbout:
                return [self buildAboutCellAtRow:indexPath.row tableView:tableView];
            case RootSectionCount:
                return [[UITableViewCell alloc] init];
        }
    } else {
        indexPath = [NSIndexPath indexPathForRow:indexPath.row inSection:self.underlyingSection];
    }

    if (indexPath.section == SectionWarning) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"warning" forIndexPath:dequeuePath];
        return [self buildWarningCell:cell];
    }
    if (indexPath.section == SectionActions) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"action" forIndexPath:dequeuePath];
        cell.textLabel.text = nil;
        for (UIView *v in [cell.contentView.subviews copy]) [v removeFromSuperview];

        BOOL supported = settings_device_supported();
        BOOL cleanupEnabled = supported && (g_kexploit_done ||
                                            g_springboard_rc_ready ||
                                            remote_call_has_local_state());
        BOOL anyInstalledOrQueued = NO;
        for (Package *p in [PackageCatalog allPackages]) {
            if (p.isInstalled || p.isQueuedForApply) { anyInstalledOrQueued = YES; break; }
        }
        if (!anyInstalledOrQueued) {
            anyInstalledOrQueued = [[PackageQueue sharedQueue] pendingCount] > 0;
        }
        BOOL rowEnabled = supported;
        if (indexPath.row == 1) rowEnabled = cleanupEnabled;
        if (indexPath.row == 3) rowEnabled = anyInstalledOrQueued;

        UILabel *primary = [[UILabel alloc] init];
        primary.translatesAutoresizingMaskIntoConstraints = NO;
        primary.textAlignment = NSTextAlignmentCenter;
        if (indexPath.row == 0) {
            primary.text = @"Run / Apply Tweaks";
            primary.textColor = supported ? self.view.tintColor : UIColor.tertiaryLabelColor;
            primary.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
        } else if (indexPath.row == 1) {
            primary.text = @"Clean Up";
            primary.textColor = cleanupEnabled ? UIColor.systemRedColor : UIColor.tertiaryLabelColor;
            primary.font = [UIFont systemFontOfSize:17];
        } else if (indexPath.row == 2) {
            primary.text = @"Respring";
            primary.textColor = supported ? UIColor.systemOrangeColor : UIColor.tertiaryLabelColor;
            primary.font = [UIFont systemFontOfSize:17];
        } else {
            primary.text = @"Reset All Packages";
            primary.textColor = anyInstalledOrQueued ? UIColor.systemRedColor : UIColor.tertiaryLabelColor;
            primary.font = [UIFont systemFontOfSize:17];
        }
        [cell.contentView addSubview:primary];
        if (!rowEnabled) {
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.userInteractionEnabled = NO;
        } else {
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.userInteractionEnabled = YES;
        }

        UILayoutGuide *m = cell.contentView.layoutMarginsGuide;
        NSString *detailText = nil;
        UIColor *detailColor = UIColor.secondaryLabelColor;
        if (indexPath.row == 0 && !supported) {
            detailText = settings_unsupported_message();
            detailColor = UIColor.systemRedColor;
        } else if (indexPath.row == 1) {
            detailText = cleanupEnabled
                ? @"Stops live SpringBoard sessions, parks the KRW socket state, and closes this app's local KRW fds. Next run tries launchd recovery first."
                : @"No local KRW session.";
            detailColor = cleanupEnabled ? UIColor.secondaryLabelColor : UIColor.tertiaryLabelColor;
        } else if (indexPath.row == 2) {
            detailText = @"Clean up is auto run prior to respring to ensure a clean state.";
            detailColor = supported ? UIColor.secondaryLabelColor : UIColor.tertiaryLabelColor;
        } else if (indexPath.row == 3) {
            detailText = anyInstalledOrQueued
                ? @"Uninstall every package and clear the pending queue. SpringBoard patches already applied this session stay until respring/reboot."
                : @"Nothing installed or queued.";
            detailColor = anyInstalledOrQueued ? UIColor.secondaryLabelColor : UIColor.tertiaryLabelColor;
        }
        if (detailText) {
            UILabel *detail = [[UILabel alloc] init];
            detail.translatesAutoresizingMaskIntoConstraints = NO;
            detail.text = detailText;
            detail.textColor = detailColor;
            detail.font = [UIFont systemFontOfSize:12];
            detail.textAlignment = NSTextAlignmentCenter;
            detail.numberOfLines = 0;
            [cell.contentView addSubview:detail];
            [NSLayoutConstraint activateConstraints:@[
                [primary.leadingAnchor  constraintEqualToAnchor:m.leadingAnchor],
                [primary.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
                [primary.topAnchor      constraintEqualToAnchor:m.topAnchor constant:2],
                [detail.leadingAnchor   constraintEqualToAnchor:m.leadingAnchor],
                [detail.trailingAnchor  constraintEqualToAnchor:m.trailingAnchor],
                [detail.topAnchor       constraintEqualToAnchor:primary.bottomAnchor constant:2],
                [detail.bottomAnchor    constraintEqualToAnchor:m.bottomAnchor constant:-2],
            ]];
        } else {
            [NSLayoutConstraint activateConstraints:@[
                [primary.leadingAnchor  constraintEqualToAnchor:m.leadingAnchor],
                [primary.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
                [primary.topAnchor      constraintEqualToAnchor:m.topAnchor],
                [primary.bottomAnchor   constraintEqualToAnchor:m.bottomAnchor],
            ]];
        }
        return cell;
    }

    NSDictionary *row = [self rowsForSection:indexPath.section][indexPath.row];
    NSString *kind = row[@"kind"] ?: @"toggle";
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    BOOL supported = settings_device_supported();

    if ([kind isEqualToString:@"button"]) {
        BOOL rowSupported = supported || indexPath.section == SectionOTA;
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"button" forIndexPath:dequeuePath];
        cell.selectionStyle = rowSupported ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
        cell.userInteractionEnabled = rowSupported;
        cell.accessoryView = nil;
        cell.textLabel.text = row[@"title"];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = rowSupported
            ? ([row[@"destructive"] boolValue] ? UIColor.systemRedColor : self.view.tintColor)
            : UIColor.tertiaryLabelColor;
        return cell;
    }

    if ([kind isEqualToString:@"stepper"]) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"stepper" forIndexPath:dequeuePath];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.textAlignment = NSTextAlignmentNatural;
        cell.textLabel.textColor = supported ? UIColor.labelColor : UIColor.tertiaryLabelColor;
        NSInteger value = [d integerForKey:row[@"key"]];
        cell.textLabel.text = [NSString stringWithFormat:@"%@: %ld", row[@"title"], (long)value];
        UIStepper *stp = [[UIStepper alloc] init];
        stp.minimumValue = [row[@"min"] doubleValue];
        stp.maximumValue = [row[@"max"] doubleValue];
        stp.stepValue = 1;
        stp.value = (double)value;
        stp.enabled = supported;
        stp.tag = (indexPath.section << 16) | indexPath.row;
        [stp addTarget:self action:@selector(stepperChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = stp;
        return cell;
    }

    if ([kind isEqualToString:@"segmented"]) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"segmented" forIndexPath:dequeuePath];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = nil;
        for (UIView *v in [cell.contentView.subviews copy]) [v removeFromSuperview];
        UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:powercuff_levels()];
        seg.translatesAutoresizingMaskIntoConstraints = NO;
        NSString *cur = [d stringForKey:row[@"key"]] ?: @"heavy";
        NSUInteger idx = [powercuff_levels() indexOfObject:cur];
        if (idx == NSNotFound) idx = 4;
        seg.selectedSegmentIndex = (NSInteger)idx;
        seg.enabled = supported;
        [seg addTarget:self action:@selector(powercuffSegChanged:) forControlEvents:UIControlEventValueChanged];
        [cell.contentView addSubview:seg];
        [NSLayoutConstraint activateConstraints:@[
            [seg.leadingAnchor  constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
            [seg.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
            [seg.topAnchor      constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.topAnchor],
            [seg.bottomAnchor   constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.bottomAnchor],
        ]];
        return cell;
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"toggle" forIndexPath:dequeuePath];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    NSString *subtitle = row[@"subtitle"];
    if (subtitle.length > 0) {
        UIListContentConfiguration *config = [UIListContentConfiguration cellConfiguration];
        config.text = row[@"title"];
        config.secondaryText = subtitle;
        config.textToSecondaryTextVerticalPadding = 3;
        config.textProperties.color = supported ? UIColor.labelColor : UIColor.tertiaryLabelColor;
        config.secondaryTextProperties.color = supported ? UIColor.secondaryLabelColor : UIColor.tertiaryLabelColor;
        config.secondaryTextProperties.font = [UIFont systemFontOfSize:12];
        config.secondaryTextProperties.numberOfLines = 0;
        cell.contentConfiguration = config;
    } else {
        cell.contentConfiguration = nil;
        cell.textLabel.text = row[@"title"];
        cell.textLabel.textAlignment = NSTextAlignmentNatural;
        cell.textLabel.textColor = supported ? UIColor.labelColor : UIColor.tertiaryLabelColor;
    }
    UISwitch *sw = [[UISwitch alloc] init];
    sw.on = [d boolForKey:row[@"key"]];
    sw.enabled = supported;
    sw.tag = (indexPath.section << 16) | indexPath.row;
    [sw addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    return cell;
}

#pragma mark - Actions

- (NSDictionary *)rowForTag:(NSInteger)tag
{
    NSInteger section = (tag >> 16) & 0xFFFF;
    NSInteger row = tag & 0xFFFF;
    return [self rowsForSection:section][row];
}

- (void)presentApplyLogIfRunning
{
    // Skip if a modal is already up (e.g. the user just toggled a different
    // switch and the log is already visible).
    if (self.presentedViewController) return;
    // Skip if there's no live SpringBoard session — the change won't fire any
    // RemoteCall until the user runs the chain, so there's nothing to watch.
    if (!g_springboard_rc_ready) return;

    InstallProgressViewController *vc = [[InstallProgressViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationAutomatic;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)toggleChanged:(UISwitch *)sender
{
    if (!settings_device_supported()) {
        sender.on = !sender.isOn;
        printf("[SETTINGS] toggle blocked: %s\n", settings_unsupported_message().UTF8String);
        return;
    }

    NSDictionary *row = [self rowForTag:sender.tag];
    NSString *key = row[@"key"];
    [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:key];
    printf("[SETTINGS] toggle %s=%d\n", key.UTF8String, sender.isOn);
    if ([key isEqualToString:kSettingsKeepAlive]) {
        ds_keepalive_apply_enabled(sender.isOn);
        return;
    }
    if (settings_key_affects_package_state(key)) {
        if (!sender.isOn) settings_mark_tweak_applied(key, NO);
        settings_notify_package_queue_changed_async();
    }
    settings_schedule_live_apply_for_key(key);
    [self presentApplyLogIfRunning];
}

- (void)stepperChanged:(UIStepper *)sender
{
    if (!settings_device_supported()) {
        printf("[SETTINGS] stepper blocked: %s\n", settings_unsupported_message().UTF8String);
        return;
    }

    NSDictionary *row = [self rowForTag:sender.tag];
    NSInteger value = (NSInteger)sender.value;
    [[NSUserDefaults standardUserDefaults] setInteger:value forKey:row[@"key"]];
    settings_schedule_live_apply_for_key(row[@"key"]);
    [self presentApplyLogIfRunning];

    UIView *v = sender.superview;
    while (v && ![v isKindOfClass:UITableViewCell.class]) v = v.superview;
    UITableViewCell *cell = (UITableViewCell *)v;
    if (cell) {
        cell.textLabel.text = [NSString stringWithFormat:@"%@: %ld", row[@"title"], (long)value];
    }
}

- (void)powercuffSegChanged:(UISegmentedControl *)sender
{
    if (!settings_device_supported()) {
        printf("[SETTINGS] powercuff level blocked: %s\n", settings_unsupported_message().UTF8String);
        return;
    }

    NSArray<NSString *> *levels = powercuff_levels();
    if (sender.selectedSegmentIndex < 0 || sender.selectedSegmentIndex >= (NSInteger)levels.count) return;
    [[NSUserDefaults standardUserDefaults] setObject:levels[sender.selectedSegmentIndex]
                                              forKey:kSettingsPowercuffLevel];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (!self.detailMode) {
        switch ((RootSection)indexPath.section) {
            case RootSectionWarning:
                return;
            case RootSectionActions:
                indexPath = [NSIndexPath indexPathForRow:indexPath.row inSection:SectionActions];
                break;
            case RootSectionTweakBundles:
            case RootSectionSystemBundles: {
                NSArray<NSDictionary *> *bundles = (RootSection)indexPath.section == RootSectionTweakBundles
                    ? self.tweakBundleRows : self.systemBundleRows;
                NSDictionary *bundle = bundles[indexPath.row];
                NSInteger underlying = [bundle[@"section"] integerValue];
                NSString *pushTitle = bundle[@"title"];
                SettingsViewController *detail = [[SettingsViewController alloc] initWithUnderlyingSection:underlying
                                                                                              bundleTitle:pushTitle];
                [self.navigationController pushViewController:detail animated:YES];
                return;
            }
            case RootSectionAbout:
                if (indexPath.row == 0)      [self openTwitter];
                else if (indexPath.row == 1) [self openViewLog];
                else if (indexPath.row == 2) [self openFeedbackEmail];
                // row 3: toggle — handled by UISwitch target, no action here
                return;
            case RootSectionCount:
                return;
        }
    } else {
        indexPath = [NSIndexPath indexPathForRow:indexPath.row inSection:self.underlyingSection];
    }

    if (!settings_device_supported() &&
        indexPath.section != SectionWarning &&
        indexPath.section != SectionOTA) {
        printf("[SETTINGS] tap blocked: %s\n", settings_unsupported_message().UTF8String);
        return;
    }

    if (indexPath.section == SectionActions) {
        if (indexPath.row == 0) {
            // Present the live log first, then trigger the apply. The modal
            // listens for kSettingsActionsDidCompleteNotification and is
            // dismissable any time via the Hide/Done button or swipe-down.
            InstallProgressViewController *logVC = [[InstallProgressViewController alloc] init];
            UINavigationController *logNav = [[UINavigationController alloc] initWithRootViewController:logVC];
            logNav.modalPresentationStyle = UIModalPresentationAutomatic;
            [self presentViewController:logNav animated:YES completion:^{
                settings_run_actions();
            }];
        } else if (indexPath.row == 1) {
            UIAlertController *ac = [UIAlertController
                alertControllerWithTitle:@"Clean Up?"
                                 message:@"This is a terminal cleanup for the current app-side KRW session. It stops live SpringBoard tweak sessions, parks the KRW socket state, closes Cyanide's local KRW file descriptors, and clears the in-app exploit cache. The next Run will try launchd KRW recovery first; if that is unavailable, it will run the full chain again."
                          preferredStyle:UIAlertControllerStyleAlert];
            [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                   style:UIAlertActionStyleCancel
                                                 handler:nil]];
            [ac addAction:[UIAlertAction actionWithTitle:@"Clean Up"
                                                   style:UIAlertActionStyleDestructive
                                                 handler:^(UIAlertAction *_) {
                settings_queue_terminal_kexploit_cleanup("manual action");
            }]];
            settings_present_controller(ac, self);
        } else if (indexPath.row == 2) {
            UIAlertController *ac = [UIAlertController
                alertControllerWithTitle:@"Respring?"
                                 message:@"Are you sure you want to respring? SpringBoard will restart."
                          preferredStyle:UIAlertControllerStyleAlert];
            [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                   style:UIAlertActionStyleCancel
                                                 handler:nil]];
            __weak typeof(self) weakSelf = self;
            [ac addAction:[UIAlertAction actionWithTitle:@"Respring"
                                                   style:UIAlertActionStyleDestructive
                                                 handler:^(UIAlertAction *_) {
                dispatch_async(dispatch_get_global_queue(0, 0), ^{
                    if (__sync_lock_test_and_set(&g_settings_actions_running, 1)) {
                        printf("[SETTINGS] respring blocked: actions already running\n");
                        return;
                    }

                    @try {
                        settings_prepare_for_respring_sync();
                    } @finally {
                        __sync_lock_release(&g_settings_actions_running);
                    }

                    dispatch_async(dispatch_get_main_queue(), ^{
                        __strong typeof(weakSelf) strongSelf = weakSelf;
                        if (!strongSelf) return;
                        DSRespringViewController *vc = [[DSRespringViewController alloc] init];
                        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
                        nav.modalPresentationStyle = UIModalPresentationFullScreen;
                        settings_present_controller(nav, strongSelf);
                    });
                });
            }]];
            settings_present_controller(ac, self);
        } else if (indexPath.row == 3) {
            UIAlertController *ac = [UIAlertController
                alertControllerWithTitle:@"Reset All Packages?"
                                 message:@"This uninstalls every package and clears the pending queue. The next chain run will start fresh from a clean slate. SpringBoard patches already live in this session stay until you respring or reboot.\n\nThis does not touch your Run options, Powercuff level, SBCustomizer grid, or other per-tweak settings — only install state."
                          preferredStyle:UIAlertControllerStyleAlert];
            [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                   style:UIAlertActionStyleCancel
                                                 handler:nil]];
            [ac addAction:[UIAlertAction actionWithTitle:@"Reset"
                                                   style:UIAlertActionStyleDestructive
                                                 handler:^(UIAlertAction *_) {
                NSUInteger uninstalled = 0;
                for (Package *p in [PackageCatalog allPackages]) {
                    if (p.isInstalled || p.isQueuedForApply) {
                        [p applyCommittedState:NO];
                        uninstalled++;
                    }
                }
                NSInteger cleared = [[PackageQueue sharedQueue] pendingCount];
                [[PackageQueue sharedQueue] clear];
                log_user("[INSTALLER] Reset: uninstalled %lu package(s), cleared %ld queued change(s).\n",
                         (unsigned long)uninstalled, (long)cleared);
                [self.tableView reloadData];
            }]];
            settings_present_controller(ac, self);
        }
    }

    if (indexPath.section == SectionOTA) {
        settings_run_ota_action(indexPath.row == 0);
        return;
    }

    if (indexPath.section == SectionSBC) {
        NSDictionary *row = [self rowsForSection:indexPath.section][indexPath.row];
        if ([row[@"kind"] isEqualToString:@"button"]) {
            settings_reset_sbc_defaults();
            // In detail mode, SBC sits at table-view section 0.
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                          withRowAnimation:UITableViewRowAnimationNone];
        }
    }
}

@end
