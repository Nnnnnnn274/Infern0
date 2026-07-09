//
//  AppDelegate.m
//  Cyanide
//
//  Created by seo on 3/24/26.
//

#import "AppDelegate.h"
#import "SettingsViewController.h"
#import "DSKeepAlive.h"
#import "LogTextView.h"
#import <signal.h>
#import <sys/stat.h>
#import <sys/utsname.h>
#import <unistd.h>

@interface AppDelegate ()

@end

static dispatch_source_t g_sigterm_source;

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [self logBootIdentity];
    settings_register_defaults();
    log_set_verbose(YES);
    ds_keepalive_apply_enabled([[NSUserDefaults standardUserDefaults] boolForKey:kSettingsKeepAlive]);
    [self installTerminationHandlers];
    [self installBarAppearances];
    return YES;
}

- (void)logBootIdentity {
    NSBundle *b = [NSBundle mainBundle];
    NSDictionary *info = b.infoDictionary;
    NSString *shortVer = info[@"CFBundleShortVersionString"] ?: @"?";
    NSString *build    = info[@"CFBundleVersion"] ?: @"?";

    struct utsname u = {0};
    const char *machine = "device";
    if (uname(&u) == 0 && u.machine[0])
        machine = u.machine;
    NSString *ios = UIDevice.currentDevice.systemVersion ?: @"?";

    fprintf(stdout,
        "\n"
        "     ╭───────────╮\n"
        "     │ ▄▄▄▄▄▄▄▄▄ │\n"
        "     ├───────────┤\n"
        "     │ ░░░░░░░░░ │   C Y A N I D E\n"
        "     │ ░░░ C ░░░ │   %s (%s)\n"
        "     │ ░░░░░░░░░ │   %s • iOS %s\n"
        "     │ ░░░░░░░░░ │\n"
        "     ╰───────────╯\n"
        "\n",
        shortVer.UTF8String, build.UTF8String,
        machine, ios.UTF8String);
}

- (void)installTerminationHandlers {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationWillTerminateNotification:)
                                                     name:UIApplicationWillTerminateNotification
                                                   object:nil];

        signal(SIGTERM, SIG_IGN);
        g_sigterm_source = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL,
                                                  SIGTERM,
                                                  0,
                                                  dispatch_get_main_queue());
        dispatch_source_set_event_handler(g_sigterm_source, ^{
            log_user("[CLEANUP] SIGTERM received; starting best-effort termination cleanup.\n");
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                settings_best_effort_termination_cleanup("SIGTERM");
                _Exit(0);
            });
        });
        dispatch_resume(g_sigterm_source);
    });
}

- (void)applicationWillTerminateNotification:(NSNotification *)note {
    settings_best_effort_termination_cleanup("UIApplicationWillTerminateNotification");
}

- (void)installBarAppearances {
    // Use the system's default glass material for ALL appearance states so the
    // bar never crossfades between transparent and blurred when content
    // scrolls past the edge. This is what UIKit's own apps do post-iOS 15.
    UINavigationBarAppearance *nav = [[UINavigationBarAppearance alloc] init];
    [nav configureWithDefaultBackground];
    UINavigationBar.appearance.standardAppearance = nav;
    UINavigationBar.appearance.scrollEdgeAppearance = nav;
    UINavigationBar.appearance.compactAppearance = nav;
    UINavigationBar.appearance.compactScrollEdgeAppearance = nav;

    UITabBarAppearance *tab = [[UITabBarAppearance alloc] init];
    [tab configureWithDefaultBackground];
    UITabBar.appearance.standardAppearance = tab;
    UITabBar.appearance.scrollEdgeAppearance = tab;
}


#pragma mark - UISceneSession lifecycle


- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options {
    // Called when a new scene session is being created.
    // Use this method to select a configuration to create the new scene with.
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
}


- (void)application:(UIApplication *)application didDiscardSceneSessions:(NSSet<UISceneSession *> *)sceneSessions {
    // Called when the user discards a scene session.
    // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
    // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
}

- (void)applicationWillTerminate:(UIApplication *)application {
    settings_best_effort_termination_cleanup("applicationWillTerminate");
}

@end
