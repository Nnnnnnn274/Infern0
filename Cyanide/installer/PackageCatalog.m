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
static const NSInteger kSecSBC          = 4;
static const NSInteger kSecStatBar      = 5;
static const NSInteger kSecRSSI         = 6;
static const NSInteger kSecPowercuff    = 9;
static const NSInteger kSecLayoutExtras = 11;
static const NSInteger kSecNanoRegistry = 12;
static const NSInteger kSecThemer       = 13;

+ (NSArray<Package *> *)allPackages
{
    NSArray<Package *> *full = [self allPackagesIncludingExperimental];
    BOOL experimentalOn = [[NSUserDefaults standardUserDefaults]
                            boolForKey:kSettingsExperimentalTweaksEnabled];
    if (experimentalOn) return full;

    NSMutableArray<Package *> *out = [NSMutableArray arrayWithCapacity:full.count];
    for (Package *p in full) {
        if (p.experimental) continue;
        [out addObject:p];
    }
    return out;
}

+ (NSArray<Package *> *)allPackagesIncludingExperimental
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
                                longDescription:@"Replaces the signal-strength glyphs in the status bar with live numeric readouts: RSRP in dBm for cellular, and the active bar count for WiFi. Updates roughly once per second.\n\nToggle WiFi-only or cellular-only in the Settings tab.\n\nIn development: the live RemoteCall refresh interferes with other SpringBoard tweaks and the readouts may not even render reliably. Only available while Experimental Tweaks is enabled in Settings."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"Experimental"
                                     symbolName:@"antenna.radiowaves.left.and.right"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsRSSIDisplayEnabled
                                          isNew:NO];
        signal.settingsSection = kSecRSSI;
        signal.experimental = YES;
        signal.unstableWarning = @"⚠️ Experimental: in-development and may not work at all. The live status-bar refresh interferes with other SpringBoard tweaks and can drop readouts entirely. Turning this on adds risk with no guaranteed feature in return.";

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
                                longDescription:@"Drives thermalmonitord with synthetic thermal pressure to underclock the CPU and GPU. Useful for cooling-sensitive workloads or extending runtime under load. Effects persist until reboot.\n\nNominal is the daily-use default. Light, Moderate, and Heavy intentionally underclock the CPU more, so lag and slower app launches mean it is working as intended. Those levels can be too slow for comfortable day-to-day use, especially on older devices.\n\nPick a level in the Settings tab."
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
        axon.unstableWarning = @"⚠️ Experimental: work-in-progress. Expect SpringBoard crashes, dropped notifications, layout glitches, and breakage between Cyanide builds. Don't rely on it for anything important.";

        Package *typeBanner = [[Package alloc] initWithIdentifier:@"com.darksword.typebanner"
                                           name:@"TypeBanner"
                               shortDescription:@"iMessage typing banner under the Dynamic Island"
                                longDescription:@"Port of TypeMillennium. Shows a pill banner just below the Dynamic Island whenever the active Messages conversation list shows a typing indicator.\n\nv1 limitation: detection runs against the Messages app's own view hierarchy via RemoteCall, so it only fires while Messages.app is running. The original tweak's system-wide imagent hook requires code injection, which is not available in this sandboxed environment without a code-signing bypass.\n\nNo extra configuration."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"Experimental"
                                     symbolName:@"ellipsis.bubble.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsTypeBannerEnabled
                                          isNew:YES];
        typeBanner.experimental = YES;
        typeBanner.unstableWarning = @"⚠️ Experimental: extremely unstable and risky. Polls MobileSMS over RemoteCall every ~1.5s, opens SpringBoard sessions on state change, and is known to crash SpringBoard. Detection only fires while Messages.app is running. Battery cost is non-trivial.";

        Package *themer = [[Package alloc] initWithIdentifier:@"com.darksword.themer"
                                           name:@"Cyanide Themer"
                               shortDescription:@"Per-bundle icon theme engine"
                                longDescription:@"Replaces stock app icons by walking SpringBoard's SBIconView hierarchy and swapping each icon's image with a PNG matched on the app's bundle identifier.\n\nPick a theme in Settings > Cyanide Themer. Cyanide ships with iOS 6 Theme, using icons from zagnut531/iOS-6-Icons: https://github.com/zagnut531/iOS-6-Icons. You can also import a custom folder of <bundleID>.png files or a binary plist mapping bundle IDs to PNG data.\n\nApplied at Run; not persisted across respring. The current build also seeds SpringBoard's icon cache and rounds imported PNGs before upload so icons survive common home-screen relayouts more cleanly."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"Experimental"
                                     symbolName:@"paintpalette.fill"
                                          kind:PackageInstallKindToggle
                                     enabledKey:kSettingsThemerEnabled
                                          isNew:YES];
        themer.experimental = YES;
        themer.settingsSection = kSecThemer;
        themer.unstableWarning = @"⚠️ Experimental: icon theming is still in development. Pick a theme in Settings > Cyanide Themer; RemoteCall-backed changes may need re-applying after a respring or SpringBoard restart.";

        Package *layoutExtras = [[Package alloc] initWithIdentifier:@"com.darksword.layoutextras"
                                           name:@"Home Layout Extras"
                               shortDescription:@"Extra home/dock padding and per-icon scaling"
                                longDescription:@"Adds extra padding around the home grid and the dock, and scales icons up or down. Stacks on top of SBCustomizer.\n\nDial in left/right/top/bottom padding for the home screen, horizontal padding for the dock, and home/dock icon scale in the Settings tab. Defaults match stock (zero padding, 100% scale).\n\nApplied at Run; not persisted across respring.\n\niOS 18: mutates the SBIconController layout configuration directly (upstream kolbicz path).\niOS 26: walks the live SBIconListView/SBIconView hierarchy and adjusts frames + iconImageInfo per icon (the iOS 26 layout class is read-only). One-shot at Run on iOS 26 — rotation/page swipe may force iOS 26's auto-layout to re-fit, so re-Run if that happens."
                                        version:version
                                         author:@"kolbicz"
                                       category:@"Home Screen Layout"
                                     symbolName:@"square.dashed.inset.filled"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsLayoutExtrasEnabled
                                          isNew:YES];
        layoutExtras.settingsSection = kSecLayoutExtras;

        Package *nanoRegistry = [[Package alloc] initWithIdentifier:@"com.darksword.nanoregistry"
                                           name:@"Watch Pairing Override"
                               shortDescription:@"Pair a newer watch or revive an older one"
                                longDescription:@"Changes the watchOS pairing range saved on this iPhone.\n\nMost people should use watchOS Range 99/23/10/6 in Settings, then apply the override. These are pairing protocol generations, not Apple Watch model numbers. 99 raises the watchOS pairing ceiling. 23 keeps the generation-23 setup protocol accepted. 10 and 6 leave the legacy chip and multi-watch floors at their normal values.\n\nApple Watch Ultra 3 cannot pair on iOS versions below 26 at this time.\n\nRespring or reboot after installing or removing the override before trying to pair."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"Beta"
                                     symbolName:@"applewatch.radiowaves.left.and.right"
                                           kind:PackageInstallKindNanoRegistry
                                     enabledKey:nil
                                          isNew:YES];
        nanoRegistry.settingsSection = kSecNanoRegistry;

        list = @[
            statBar,
            sbc,
            layoutExtras,
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
                                           name:@"OTA Updates"
                               shortDescription:@"Enable or disable over-the-air system updates"
                                longDescription:@"Disables or enables the launchd jobs responsible for over-the-air system updates by editing disabled.plist. State persists across reboots.\n\nNo Run/Apply step required for this package. Use Disable to block OTA updates, or Enable to restore them."
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
            nanoRegistry,
            typeBanner,
            themer,
        ];
    });
    return list;
}

+ (NSArray<NSString *> *)categoriesInOrder
{
    NSArray<NSString *> *preferred = @[
        @"Experimental",
        @"Beta",
        @"Status Bar",
        @"Home Screen Layout",
        @"Performance",
        @"System Updates",
        @"System",
        @"SpringBoard Tweaks",
    ];
    NSMutableArray<NSString *> *all = [NSMutableArray array];
    for (Package *p in [self allPackages]) {
        if (![all containsObject:p.category]) [all addObject:p.category];
    }
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    for (NSString *cat in preferred) {
        if ([all containsObject:cat]) [order addObject:cat];
    }
    for (NSString *cat in all) {
        if (![order containsObject:cat]) [order addObject:cat];
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
