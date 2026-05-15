//
//  PackageCatalog.m
//  Cyanide
//

#import "PackageCatalog.h"
#import "../SettingsViewController.h"

@implementation PackageCatalog

// Mirrors of the private SettingsSection enum values in SettingsViewController.m
// (kept in sync — must match the underlying section indices used for the
// detail-mode SettingsViewController push).
static const NSInteger kSecSBC       = 4;
static const NSInteger kSecStatBar   = 5;
static const NSInteger kSecRSSI      = 6;
static const NSInteger kSecPowercuff = 8;

+ (NSArray<Package *> *)allPackages
{
    static NSArray<Package *> *list;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *version = @"1.0";

        Package *statBar = [[Package alloc] initWithIdentifier:@"com.darksword.statbar"
                                           name:@"StatBar"
                               shortDescription:@"Battery temperature + free RAM overlay"
                                longDescription:@"Installs an overlay window in SpringBoard that shows live battery temperature and free RAM next to the system status bar. Refreshes about once per second while the RemoteCall session is alive.\n\nConfigure Celsius/Fahrenheit and network speed visibility in the Settings tab."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"Status Bar"
                                     symbolName:@"thermometer.medium"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsStatBarEnabled
                                          isNew:NO];
        statBar.settingsSection = kSecStatBar;

        Package *signal = [[Package alloc] initWithIdentifier:@"com.darksword.rssidisplay"
                                           name:@"Signal Readouts"
                               shortDescription:@"RSRP dBm on cellular, bar count on WiFi"
                                longDescription:@"Replaces the signal-strength glyphs in the status bar with live numeric readouts: RSRP in dBm for cellular, and the active bar count for WiFi. Updates roughly once per second.\n\nToggle WiFi-only or cellular-only in the Settings tab."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"Beta"
                                     symbolName:@"antenna.radiowaves.left.and.right"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsRSSIDisplayEnabled
                                          isNew:YES];
        signal.settingsSection = kSecRSSI;

        Package *sbc = [[Package alloc] initWithIdentifier:@"com.darksword.sbcustomizer"
                                           name:@"SBCustomizer"
                               shortDescription:@"Custom dock count and home screen grid"
                                longDescription:@"Customizes the dock icon count and the home screen icon grid (columns and rows). Optionally hides icon labels.\n\nAdjust the per-axis counts and the label-hide switch in the Settings tab."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"Home Screen Layout"
                                     symbolName:@"square.grid.3x3.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsSBCEnabled
                                          isNew:NO];
        sbc.settingsSection = kSecSBC;

        Package *powercuff = [[Package alloc] initWithIdentifier:@"com.darksword.powercuff"
                                           name:@"Powercuff"
                               shortDescription:@"Underclock the CPU/GPU thermal pressure"
                                longDescription:@"Drives thermalmonitord with synthetic thermal pressure to underclock the CPU and GPU. Useful for cooling-sensitive workloads or extending runtime under load. Effects persist until reboot.\n\nPick a level (nominal/light/moderate/heavy) in the Settings tab."
                                        version:version
                                         author:@"rpetrich"
                                       category:@"Performance"
                                     symbolName:@"bolt.slash.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsPowercuffEnabled
                                          isNew:NO];
        powercuff.settingsSection = kSecPowercuff;

        Package *axon = [[Package alloc] initWithIdentifier:@"com.darksword.axonlite"
                                           name:@"Axon Lite"
                               shortDescription:@"Group Notification Center requests by app"
                                longDescription:@"Groups visible Notification Center requests by app in a SpringBoard overlay and filters duplicates while Cyanide keeps the RemoteCall session alive.\n\nNo extra configuration."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"Beta"
                                     symbolName:@"bell.badge.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsAxonLiteEnabled
                                          isNew:YES];

        list = @[
            statBar,
            sbc,
            powercuff,

            [[Package alloc] initWithIdentifier:@"com.darksword.disable-app-library"
                                           name:@"Disable App Library"
                               shortDescription:@"Remove the App Library page"
                                longDescription:@"Removes the App Library page that sits past your last home-screen page. Swiping past the last page becomes a no-op."
                                        version:version
                                         author:@"kolbicz"
                                       category:@"SpringBoard Tweaks"
                                     symbolName:@"square.grid.2x2.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsDSDisableAppLibrary
                                          isNew:NO],

            [[Package alloc] initWithIdentifier:@"com.darksword.disable-icon-flyin"
                                           name:@"Disable Icon Fly-In"
                               shortDescription:@"Skip the icon spring animation"
                                longDescription:@"Skips the spring animation that plays when home screen icons appear after unlock or app switch. Icons just appear in their final position."
                                        version:version
                                         author:@"kolbicz"
                                       category:@"SpringBoard Tweaks"
                                     symbolName:@"sparkles"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsDSDisableIconFlyIn
                                          isNew:NO],

            [[Package alloc] initWithIdentifier:@"com.darksword.zero-wake-animation"
                                           name:@"Zero Wake Animation"
                               shortDescription:@"Snap on instantly when waking"
                                longDescription:@"Removes the fade-in animation when waking the display. The screen pops on at full brightness immediately."
                                        version:version
                                         author:@"kolbicz"
                                       category:@"SpringBoard Tweaks"
                                     symbolName:@"moon.zzz.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsDSZeroWakeAnimation
                                          isNew:NO],

            [[Package alloc] initWithIdentifier:@"com.darksword.zero-backlight-fade"
                                           name:@"Zero Backlight Fade"
                               shortDescription:@"Instant lock/unlock backlight"
                                longDescription:@"Cuts the backlight fade duration to zero so the display switches on or off instantly on lock and unlock."
                                        version:version
                                         author:@"kolbicz"
                                       category:@"SpringBoard Tweaks"
                                     symbolName:@"sun.max.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsDSZeroBacklightFade
                                          isNew:NO],

            [[Package alloc] initWithIdentifier:@"com.darksword.double-tap-to-lock"
                                           name:@"Double-Tap to Lock"
                               shortDescription:@"Lock with a wallpaper double-tap"
                                longDescription:@"Double-tap an empty area of the wallpaper to lock the device. No more reaching for the side button."
                                        version:version
                                         author:@"kolbicz"
                                       category:@"SpringBoard Tweaks"
                                     symbolName:@"hand.tap.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsDSDoubleTapToLock
                                          isNew:NO],

            [[Package alloc] initWithIdentifier:@"com.darksword.ota-block"
                                           name:@"Disable OTA Updates"
                               shortDescription:@"Block over-the-air system updates"
                                longDescription:@"Disables the launchd jobs responsible for over-the-air system updates by editing disabled.plist. State persists across reboots. Uninstall to re-enable the jobs.\n\nNo Run/Apply step required — the change takes effect immediately."
                                        version:version
                                         author:@"kolbicz"
                                       category:@"System Updates"
                                     symbolName:@"icloud.slash.fill"
                                           kind:PackageInstallKindOTA
                                     enabledKey:nil
                                          isNew:NO],

            // Beta last so the warning sits at the bottom of the Installer.
            signal,
            axon,
        ];
    });
    return list;
}

+ (NSArray<NSString *> *)categoriesInOrder
{
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    for (Package *p in [self allPackages]) {
        if (![order containsObject:p.category]) {
            [order addObject:p.category];
        }
    }
    return order;
}

+ (NSDictionary<NSString *, NSArray<Package *> *> *)packagesByCategory
{
    NSMutableDictionary<NSString *, NSMutableArray<Package *> *> *buckets = [NSMutableDictionary dictionary];
    for (Package *p in [self allPackages]) {
        NSMutableArray<Package *> *bucket = buckets[p.category];
        if (!bucket) {
            bucket = [NSMutableArray array];
            buckets[p.category] = bucket;
        }
        [bucket addObject:p];
    }
    return buckets;
}

@end
