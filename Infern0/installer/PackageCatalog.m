//
//  PackageCatalog.m
//  infern0
//

#import "PackageCatalog.h"
#import "../SettingsViewController.h"
#import "../tweaks/retired_tweak_compat.h"
#import "../tweaks/experimental_tweaks.h"

@interface Package ()
@property (nonatomic, readwrite, copy) NSString *symbolName;
@property (nonatomic, readwrite, copy) NSString *author;
@end

@implementation PackageCatalog

static NSString *catalog_string_or_empty(id value)
{
    return [value isKindOfClass:NSString.class] ? (NSString *)value : @"";
}

static NSArray<NSString *> *catalog_repotweaks_urls(NSUserDefaults *d)
{
    id raw = [d objectForKey:@"RepoTweaksURLs"];
    if (![raw isKindOfClass:NSArray.class]) return @[];
    NSMutableArray<NSString *> *urls = [NSMutableArray array];
    for (id value in (NSArray *)raw) {
        if ([value isKindOfClass:NSString.class]) [urls addObject:value];
    }
    return urls;
}

static NSDictionary *catalog_repotweaks_caches(NSUserDefaults *d)
{
    id raw = [d objectForKey:@"RepoTweaksCaches"];
    return [raw isKindOfClass:NSDictionary.class] ? (NSDictionary *)raw : @{};
}

static BOOL catalog_repo_script_requires_native_bridge(NSString *rawScript)
{
    if (![rawScript isKindOfClass:NSString.class] || rawScript.length == 0) return NO;
    return [rawScript containsString:@"nativeCallBuff"] ||
           [rawScript containsString:@"runOnMainEvaluate"] ||
           [rawScript containsString:@"Native.callSymbol"];
}

+ (NSArray<Package *> *)repoPackages
{
    repotweaks_seed_default_repos();

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSDictionary *caches = catalog_repotweaks_caches(d);
    NSMutableArray<Package *> *packages = [NSMutableArray array];

    for (NSString *url in catalog_repotweaks_urls(d)) {
        id repoRaw = caches[url];
        if (![repoRaw isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *repo = (NSDictionary *)repoRaw;
        NSString *repoName = catalog_string_or_empty(repo[@"repoName"]);
        NSString *author = catalog_string_or_empty(repo[@"author"]);
        id tweaksRaw = repo[@"tweaks"];
        if (![tweaksRaw isKindOfClass:NSArray.class]) continue;

        for (id tweakRaw in (NSArray *)tweaksRaw) {
            if (![tweakRaw isKindOfClass:NSDictionary.class]) continue;
            NSDictionary *tweak = (NSDictionary *)tweakRaw;
            NSString *tweakID = catalog_string_or_empty(tweak[@"id"]);
            NSString *name = catalog_string_or_empty(tweak[@"name"]);
            NSString *scriptURL = catalog_string_or_empty(tweak[@"scriptURL"]);
            if (tweakID.length == 0 || name.length == 0 || scriptURL.length == 0) continue;

            NSString *identifier = [NSString stringWithFormat:@"repo.%@", repotweaks_storage_key(url, tweakID)];
            Package *pkg = [[Package alloc] initRepoTweakWithIdentifier:identifier
                                                                   name:name
                                                       shortDescription:catalog_string_or_empty(tweak[@"description"])
                                                                version:catalog_string_or_empty(tweak[@"version"])
                                                                 author:author
                                                               repoName:repoName
                                                                repoURL:url
                                                            repoTweakID:tweakID
                                                           repoScriptURL:scriptURL];
            NSString *symbol = catalog_string_or_empty(tweak[@"symbol"]);
            if (symbol.length > 0) pkg.symbolName = symbol;
            NSString *tweakAuthor = catalog_string_or_empty(tweak[@"author"]);
            if (tweakAuthor.length > 0) pkg.author = tweakAuthor;
            NSString *rawScript = [d stringForKey:repotweaks_script_defaults_key(url, tweakID)];
            NSString *unsupportedReason = repotweaks_unsupported_reason(tweak);
            if (unsupportedReason.length > 0) {
                pkg.installDisabledReason = unsupportedReason;
                pkg.unstableWarning = unsupportedReason;
            } else if (rawScript.length == 0) {
                pkg.installDisabledReason = @"Refresh this source from the Sources tab before installing.";
            } else if (pkg.repoTweakUsesQuickLoader && catalog_repo_script_requires_native_bridge(rawScript)) {
                pkg.installDisabledReason = @"This repo tweak needs a dedicated infern0 native backend before it can install.";
            }
            [packages addObject:pkg];
        }
    }

    return [packages sortedArrayUsingComparator:^NSComparisonResult(Package *a, Package *b) {
        return [a.name caseInsensitiveCompare:b.name];
    }];
}

// Mirrors of the private SettingsSection enum values in SettingsViewController.m
// (kept in sync — must match the underlying section indices used for the
// detail-mode SettingsViewController push).
static const NSInteger kSecOTA              = 3;
static const NSInteger kSecSBC              = 4;
static const NSInteger kSecStatBar          = 5;
static const NSInteger kSecNSBar            = 6;
static const NSInteger kSecNiceBarLite      = 7;
static const NSInteger kSecRSSI             = 8;
static const NSInteger kSecAxonLite         = 9;
static const NSInteger kSecTypeBanner       = 10;
static const NSInteger kSecNotificationIsland = 11;
static const NSInteger kSecPowercuff        = 12;
static const NSInteger kSecDragCoefficient  = 14;
static const NSInteger kSecLayoutExtras     = 15;
static const NSInteger kSecNanoRegistry     = 16;
static const NSInteger kSecThemer           = 17;
static const NSInteger kSecSnowBoardLite    = 18;
static const NSInteger kSecLiveWP           = 19;
static const NSInteger kSecLocationSim      = 20;
static const NSInteger kSecGravityLite      = 21;
static const NSInteger kSecAppSwitcherGrid  = 22;
static const NSInteger kSecIPADecryptor     = 23;
static const NSInteger kSecFastLockXLite    = 24;
static const NSInteger kSecVelvet           = 25;
static const NSInteger kSecCleanNC          = 26;
static const NSInteger kSecUnderTime        = 27;
static const NSInteger kSecZeppelinLite     = 28;
static const NSInteger kSecCleanHomeScreen  = 29;
static const NSInteger kSecRealCC           = 30;
static const NSInteger kSecCleanCC          = 31;
static const NSInteger kSecFUGap            = 32;
static const NSInteger kSecModuleSpacing    = 33;
static const NSInteger kSecSugarCane        = 34;
static const NSInteger kSecBetterCCXI       = 35;
static const NSInteger kSecMagma            = 36;
static const NSInteger kSecBetterCCIcons    = 37;
static const NSInteger kSecCCNoPlatterDim   = 38;
static const NSInteger kSecCCStatus         = 39;
static const NSInteger kSecHapticCC         = 40;
static const NSInteger kSecSecureCC         = 41;
static const NSInteger kSecHideLabels       = 42;
static const NSInteger kSecFakeClockUp      = 43;
static const NSInteger kSecPancake          = 44;
static const NSInteger kSecCylinderLite     = 45;
static const NSInteger kSecBarmoji          = 46;
static const NSInteger kSecBlurryBadges     = 47;
static const NSInteger kSecSnapper          = 48;
static const NSInteger kSecPullOver         = 49;
static const NSInteger kSecAlkaline         = 50;
static const NSInteger kSecTweakLoader      = 51;
static const NSInteger kSecQuickLoader      = 52;
static const NSInteger kSecRepoTweaks       = 53;
static const NSInteger kSecStageStrip       = 54;
static const NSInteger kSecCallRecordingSound = 55;
static const NSInteger kSecHideHomeBar      = 56;
static const NSInteger kSecRoundedIcons     = 57;
static const NSInteger kSecWatchLayout      = 58;
static const NSInteger kSecLockCustomizer   = 59;
static const NSInteger kSecFreePlacement    = 60;
static const NSInteger kSecCopypastaLite    = 61;
static const NSInteger kSecAppLibraryStudio = 62;
static const NSInteger kSecDarkSwordTweaks  = 13;

+ (NSArray<Package *> *)allPackages
{
    NSArray<Package *> *full = [self allPackagesIncludingExperimental];
    BOOL experimentalOn = [[NSUserDefaults standardUserDefaults]
                            boolForKey:kSettingsExperimentalTweaksEnabled];

    NSMutableArray<Package *> *out = [NSMutableArray arrayWithCapacity:full.count];
    for (Package *p in full) {
        if (p.creatorOnly) continue;
        if (p.experimental && !experimentalOn) continue;
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
        NSString *inDevelopmentDisabledReason =
            @"In development — install is disabled because this tweak does not work yet. The code is left in the app/source tree for anyone who wants to pick it up.";

        Package *statBar = [[Package alloc] initWithIdentifier:@"com.darksword.statbar"
                                           name:@"StatBar"
                               shortDescription:@"Battery temperature + free RAM overlay"
                                longDescription:@"Installs an overlay window in SpringBoard that shows live battery temperature and free RAM next to the system status bar. Refresh timing is adjustable so you can trade live updates for battery life.\n\nConfigure units, visible metrics, and refresh speed in the Settings tab."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"Status Bar"
                                     symbolName:@"thermometer.medium"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsStatBarEnabled
                                          isNew:NO];
        statBar.settingsSection = kSecStatBar;

        Package *nsBar = [[Package alloc] initWithIdentifier:@"com.darksword.nsbar"
                                           name:@"NSBar"
                               shortDescription:@"Network speed overlay in the status bar"
                                longDescription:@"Displays real-time download and upload speed in a compact SpringBoard status-bar overlay. Pick its corner or center position in Settings.\n\nPorted from d1y/cyanide-ios."
                                        version:version
                                         author:@"d1y"
                                       category:@"Status Bar"
                                     symbolName:@"network"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsNSBarEnabled
                                          isNew:NO];
        nsBar.settingsSection = kSecNSBar;

        Package *niceBarLite = [[Package alloc] initWithIdentifier:@"com.darksword.nicebarlite"
                                           name:@"NiceBar Lite"
                               shortDescription:@"NiceBar-style status labels"
                                longDescription:@"Adds configurable text labels around the status bar. Slots can show custom text, date/time formats, and system values such as battery, memory, network speed, uptime, IP address, disk space, thermal state, and traffic counters.\n\nPorted from d1y/cyanide-ios."
                                        version:version
                                         author:@"d1y"
                                       category:@"Status Bar"
                                     symbolName:@"textformat.size"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsNiceBarLiteEnabled
                                          isNew:NO];
        niceBarLite.settingsSection = kSecNiceBarLite;

#if CYANIDE_EXPERIMENTAL_TWEAKS_AVAILABLE
        Package *signal = [[Package alloc] initWithIdentifier:@"com.darksword.rssidisplay"
                                           name:@"Signal Readouts"
                               shortDescription:@"RSRP dBm on cellular, bar count on WiFi"
                                longDescription:@"Replaces the signal-strength glyphs in the status bar with live numeric readouts: RSRP in dBm for cellular, and the active bar count for WiFi. Updates roughly once per second.\n\nToggle WiFi-only or cellular-only in the Settings tab."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"Status Bar"
                                     symbolName:@"antenna.radiowaves.left.and.right"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsRSSIDisplayEnabled
                                          isNew:NO];
        signal.settingsSection = kSecRSSI;
        signal.unstableWarning = @"⚠️ Beta: The live status-bar refresh may interfere with other SpringBoard tweaks and can occasionally drop readouts.";
#endif

        Package *sbc = [[Package alloc] initWithIdentifier:@"com.darksword.sbcustomizer"
                                           name:@"SBCustomizer"
                               shortDescription:@"iPad-style Dock, App Library access, and home grid"
                                longDescription:@"Customizes the dock icon count and Home Screen grid, optionally hides labels, and adds an iPad-style floating Dock mode. Supported iOS builds can expose recent apps and App Library access directly from the Dock. Live icon views remain pressable, and every selector path is recorded in the activity log."
                                        version:version
                                         author:@"Nnnnnnn274"
                                       category:@"Home Screen"
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
                                       category:@"System"
                                     symbolName:@"bolt.slash.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsPowercuffEnabled
                                          isNew:NO];
        powercuff.settingsSection = kSecPowercuff;

        Package *axon = [[Package alloc] initWithIdentifier:@"com.darksword.axonlite"
                                           name:@"Axon Lite"
                               shortDescription:@"Group Notification Center requests by app"
                                longDescription:@"Groups visible Notification Center requests by app in a SpringBoard overlay and filters duplicates while infern0 keeps the RemoteCall session alive.\n\nNo extra configuration."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"SpringBoard"
                                     symbolName:@"bell.badge.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsAxonLiteEnabled
                                          isNew:NO];
        axon.settingsSection = kSecAxonLite;
        axon.unstableWarning = @"Beta: the live loop pauses while the screen is unavailable, serializes RemoteCall access, and stops after three consecutive failures. Notification internals still vary by iOS build, so review the detailed Axon log after first apply.";

#if CYANIDE_EXPERIMENTAL_TWEAKS_AVAILABLE
        Package *typeBanner = [[Package alloc] initWithIdentifier:@"com.darksword.typebanner"
                                           name:@"TypeBanner"
                               shortDescription:@"iMessage typing banner under the Dynamic Island"
                                longDescription:@"Port of TypeMillennium. Shows a pill banner just below the Dynamic Island when imagent reports an active iMessage typing indicator.\n\nNo extra configuration."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"Beta"
                                     symbolName:@"ellipsis.bubble.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsTypeBannerEnabled
                                          isNew:NO];
        typeBanner.settingsSection = kSecTypeBanner;
        typeBanner.unstableWarning = @"Beta: Uses a short-lived imagent probe every five seconds and restores the daemon thread after every poll. Disable it and report the [TYPEBANNER] log if a probe or restore fails.";

        Package *notificationIsland = [[Package alloc] initWithIdentifier:@"com.darksword.notificationisland"
                                           name:@"Notification Island"
                               shortDescription:@"Mirror incoming banners into the Dynamic Island"
                                longDescription:@"Experimental Dynamic Island notification route. Watches SpringBoard's active banner request over the shared RemoteCall session, then mirrors the title/body into infern0's ActivityKit Live Activity.\n\nNo extra configuration."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"Beta"
                                     symbolName:@"bell.and.waves.left.and.right.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsNotificationIslandEnabled
                                          isNew:NO];
        notificationIsland.settingsSection = kSecNotificationIsland;
        notificationIsland.unstableWarning = @"⚠️ Beta: Polls SpringBoard notification state over RemoteCall and may occasionally miss banners or duplicate activity updates.";

        Package *ipaDecryptor = [[Package alloc] initWithIdentifier:@"com.darksword.ipadecryptor"
                                           name:@"IPA Decryptor (Beta)"
                               shortDescription:@"Probe encryption and export verified unencrypted apps"
                                 longDescription:@"Select an installed app or resolve an App Store link, download an encrypted IPA, and inspect the main Mach-O FairPlay encryption command. The current beta exports an IPA only when the installed executable is already unencrypted. If cryptid is nonzero it stops with a clear diagnostic instead of copying encrypted bytes into a falsely labeled decrypted archive. In-memory executable dumping remains under development."
                                        version:version
                                         author:@"londek / zeroxjf"
                                       category:@"System"
                                     symbolName:@"lock.open.fill"
                                           kind:PackageInstallKindDirectTool
                                     enabledKey:nil
                                          isNew:NO];
        ipaDecryptor.settingsSection = kSecIPADecryptor;
        ipaDecryptor.unstableWarning = @"Beta: encrypted App Store executables are detected but not decrypted yet. No output IPA is created unless the executable is verified unencrypted.";

        Package *stageStrip = [[Package alloc] initWithIdentifier:@"com.darksword.stagestrip"
                                           name:@"MilkyWay Lite / Dynamic Stage"
                               shortDescription:@"One or two floating app windows, including system apps"
                                longDescription:
            @"Run one or two apps as floating, resizable windows on top of SpringBoard. Settings controls the concurrent-window limit and whether Safari, Photos, and Camera are explicitly included in the picker.\n\n"
            @"Based on Dynamic Stage by tomt000 — the original Stage Manager-for-iPhone tweak. Dynamic Stage Lite is an independent, RemoteCall-only re-implementation of the split-view + scene-hosting design; no original tweak code or assets are reused. Go check out tomt000's full version on Havoc.\n\n"
            @"How to use:\n"
            @"• Tap the dot in the bottom-right corner of the screen to open the picker.\n"
            @"• Tap one or two apps, according to the configured window limit.\n"
            @"• Drag the top bar to move; drag any corner to resize.\n"
            @"• X in the top-left of a window closes it.\n"
            @"• Gear in the picker tray jumps back to infern0 settings.\n\n"
            @"First Run is slow. The picker has to enumerate every installed app over RemoteCall and build a tile per app — expect 1-2 minutes on a fresh install. Re-Runs reuse the cache and are fast.\n\n"
            @"Interaction notes:\n"
            @"• Hosted scenes opt into hit testing, disable touch pass-through, and reserve only the title strip and corner handles for window gestures. Some app scenes may still reject remote hosting on particular iOS builds.\n"
            @"• Auto-close on full-screen launch is not yet hooked up; close manually with the X.\n"
            @"• Gestures may stutter while the App Library is still filling in."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"Beta"
                                     symbolName:@"sidebar.left"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsStageStripEnabled
                                          isNew:NO];
        stageStrip.settingsSection = kSecStageStrip;
        stageStrip.unstableWarning = @"Beta / unstable: First Run takes 1-2 minutes while the picker is built. Touch routing is enabled on scene hosts, but individual apps or iOS builds may still reject scrolling, keyboard focus, or remote scene interaction.";
#endif

        Package *locationSim = [[Package alloc] initWithIdentifier:@"com.darksword.locationsim"
                                           name:@"Location Simulator"
                               shortDescription:@"CoreLocation static point simulation"
                                longDescription:@"Spoofs the device's GPS location via Apple's CLSimulationManager. Requires Apple Maps installed and set up — Maps is the RemoteCall host process that drives the simulation.\n\nThis is a manual tool, not an installable package. Open Controls, choose a target, then use Simulate Current Target or Restore Real Location. Each run opens the activity log and marks completion when the request returns. Reset may take a few minutes and may require a reboot plus extra wait time.\n\nSettings exposes the current target plus altitude and accuracy. v1 is static-point only; route playback and alternate daemon hosts are next.\n\nNot all apps respect the simulated location. Apps that use their own location validation or additional signals may ignore it.\n\nCredits: kolbicz provided the GPS spoofer RemoteCall/CLSimulationManager prototype this is based on. ezzuldinSt's LSpoof provided the app-side CLLocationManager spoofing, picker, bookmarks, and route-simulation reference.\n\nSystem-behavior warning: simulated locations can affect more than maps. Features tied to location, including time zone, date/time behavior, weather, automation, reminders, and service checks, may behave unexpectedly. Only use this if you know what you're doing.\n\nLegal and service-use note: simulated locations may violate app terms, platform rules, game rules, ride-share or delivery policies, or local law depending on how they are used. Use only where you have permission. You are responsible for your use and apply or restore this tweak at your own risk."
                                        version:version
                                         author:@"zeroxjf, kolbicz, ezzuldinSt"
                                       category:@"System"
                                     symbolName:@"location.fill"
                                           kind:PackageInstallKindDirectTool
                                     enabledKey:nil
                                          isNew:NO];
        locationSim.settingsSection = kSecLocationSim;
        locationSim.experimental = NO;
        locationSim.unstableWarning = @"Beta: requires Apple Maps installed and set up. Changes CoreLocation's active simulation state — may affect time zone, date/time, and other location-tied behavior. Some apps and services prohibit or detect simulated locations. Only use this if you know what you're doing.";

        Package *snowboardLite = [[Package alloc] initWithIdentifier:@"com.darksword.snowboardlite"
                                           name:@"SnowBoard Lite"
                               shortDescription:@"Local SnowBoard-style icon themes"
                                longDescription:@"Imports SnowBoard/IconBundles themes into a local library and applies the selected theme through infern0's icon replacement pipeline. Supports the bundled iOS 6 theme and local folder imports.\n\nSnowBoard Lite is the main icon-theme entry point in infern0.\n\nPorted from d1y/cyanide-ios."
                                        version:version
                                         author:@"d1y"
                                       category:@"Theming"
                                     symbolName:@"square.stack.3d.up.fill"
                                          kind:PackageInstallKindToggle
                                     enabledKey:kSettingsSnowBoardLiteEnabled
                                          isNew:NO];
        snowboardLite.settingsSection = kSecSnowBoardLite;
        snowboardLite.unstableWarning = @"Preview: import or select a SnowBoard Lite theme before applying.";

        Package *liveWP = [[Package alloc] initWithIdentifier:@"com.darksword.livewp"
                                           name:@"LiveWP"
                               shortDescription:@"Video or eight-image Mood Wallpaper"
                                longDescription:@"Plays a selected MP4/MOV/M4V video behind SpringBoard's Home and Lock Screen windows, or crossfades and tilts through up to eight selected Mood Wallpaper images. Both modes are session-only and are removed during cleanup.\n\nVideo mode is ported from d1y/cyanide-ios; Mood Wallpaper uses the same reversible live-layer engine."
                                        version:version
                                         author:@"d1y"
                                       category:@"Theming"
                                     symbolName:@"play.rectangle.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsLiveWPEnabled
                                          isNew:NO];
        liveWP.settingsSection = kSecLiveWP;

        Package *themer = [[Package alloc] initWithIdentifier:@"com.darksword.themer"
                                             name:@"Infern0 Themer"
                                 shortDescription:@"Per-bundle icon theme engine"
                                  longDescription:@"Replaces stock app icons with a selected local icon theme. Choose a theme in Settings before applying. Changes are session-based and may need re-applying after SpringBoard restarts."
                                          version:version
                                           author:@"zeroxjf"
                                         category:@"Beta"
                                       symbolName:@"paintpalette.fill"
                                             kind:PackageInstallKindToggle
                                       enabledKey:kSettingsThemerEnabled
                                            isNew:NO];
        themer.experimental = NO;
        themer.settingsSection = kSecThemer;

        Package *layoutExtras = [[Package alloc] initWithIdentifier:@"com.darksword.layoutextras"
                                           name:@"Home Layout Extras"
                               shortDescription:@"Extra home/dock padding and per-icon scaling"
                                longDescription:@"Adds extra padding around the home grid and the dock, and scales icons up or down. Stacks on top of SBCustomizer.\n\nDial in left/right/top/bottom padding for the home screen, horizontal padding for the dock, and home/dock icon scale in the Settings tab. Defaults match stock (zero padding, 100% scale).\n\nApplied at Run; not persisted across respring.\n\niOS 18: mutates the SBIconController layout configuration directly using the upstream kolbicz path. iOS 26: applies captured live SBIconListView transforms, discovers pages loaded during swipes, and restores their exact original transforms during cleanup. App Library and Today View grids remain excluded."
                                        version:version
                                         author:@"kolbicz"
                                      category:@"Home Screen"
                                     symbolName:@"square.dashed.inset.filled"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsLayoutExtrasEnabled
                                          isNew:NO];
        layoutExtras.settingsSection = kSecLayoutExtras;
        NSInteger iosMajor = [[NSProcessInfo processInfo] operatingSystemVersion].majorVersion;
        if (iosMajor >= 26) {
            layoutExtras.knownIssues = @[
                @"Major SpringBoard relayouts can briefly reset a page before the live refresh pass reapplies its captured transform.",
            ];
        }

        Package *gravityLite = [[Package alloc] initWithIdentifier:@"com.darksword.gravitylite"
                                           name:@"Gravity Lite"
                               shortDescription:@"Make home-screen icons fall with physics"
                                longDescription:@"Core RemoteCall-only port of Julio Verne's classic Gravity tweak for iOS 26. Every Home Screen page owns a separate overlay, animator, collision boundary, and saved icon layout, so icons remain attached to their original page instead of merging or disappearing during page swipes. Lazy pages are detected while swiping, and the App Library receives its own isolated physics group when SpringBoard loads it. The dock uses its own optional simulation. Live icons remain pressable while gravity, bounce, friction, resistance, accelerometer steering, shake pulses, restore, and explosion pulses are active.\n\nThis is not a full Substrate-style port. Activator/Home-button hooks, drag gestures, and preference-daemon notifications are intentionally left out. Use Settings to tune the core physics and the Restore button to reset every captured page and App Library item to its saved layout."
                                        version:version
                                         author:@"Julio Verne / zeroxjf"
                                       category:@"Home Screen"
                                     symbolName:@"arrow.down.circle.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsGravityLiteEnabled
                                          isNew:NO];
        gravityLite.settingsSection = kSecGravityLite;
        gravityLite.unstableWarning = @"Beta: each page is isolated during normal page swipes, but larger SpringBoard relayouts such as rotation, folder transitions, or resprings can still reset live RemoteCall physics. Use Restore Icon Layout if icons stay displaced.";
        gravityLite.knownIssues = @[
            @"Use Restore Icon Layout or disable Gravity Lite from Settings to stop every active page, Dock, and App Library physics group cleanly.",
            @"The iOS 26 per-icon path reparents live icon views and keeps them interactive. Older fallback paths still animate snapshots, so displaced snapshot icons cannot receive taps.",
            @"The first run can take a moment because infern0 captures each loaded icon group before starting physics; lazy pages attach later in the background.",
            @"Rotation, folder transitions, or a SpringBoard relayout may stop the effect. Home pages and App Library views created during a swipe are attached by the live refresh scan.",
        ];

        Package *appSwitcherGrid = [[Package alloc] initWithIdentifier:@"com.darksword.appswitchergrid"
                                           name:@"App Switcher Grid"
                               shortDescription:@"Deck and multi-size Grid switcher with spring animations"
                                longDescription:@"Changes SpringBoard's live app-switcher settings without writing system files. Choose Automatic, Classic Deck, Compact Grid, Balanced Grid, or Large Grid, then pair it with System, Snappy, Smooth, or Bouncy switcher animations.\n\nThe tweak captures the original layout, spacing, scale, response, and damping values before changing them, so Restore Stock Switcher can put the active session back exactly. A respring also restores stock behavior.\n\nInspired by d1y/cyanide-ios, iPadSwitcher, and NewGridSwitcherBig."
                                        version:version
                                         author:@"rooootdev"
                                       category:@"SpringBoard"
                                     symbolName:@"square.grid.2x2.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsAppSwitcherGridEnabled
                                          isNew:NO];
        appSwitcherGrid.settingsSection = kSecAppSwitcherGrid;
        appSwitcherGrid.knownIssues = @[
            @"SpringBoard may cache an already-open switcher. Close it fully and reopen it after changing a layout preset.",
            @"Animation presets gracefully fall back to System when the current iOS build does not expose compatible fluid-animation settings.",
        ];
        appSwitcherGrid.unstableWarning = @"Beta: changes private SpringBoard switcher settings in memory. Unsupported iOS builds are rejected before mutation; Restore Stock Switcher or a respring returns to stock.";

        Package *quickLoader = [[Package alloc] initWithIdentifier:@"com.darksword.quickloader"
                                           name:@"QuickLoader"
                               shortDescription:@"Executes custom .js code"
                                longDescription:@"Select a local JavaScript file from Files, configure any declared parameters, and run it through infern0's SpringBoard RemoteCall bridge.\n\nOnly run scripts you trust. JavaScript tweaks can send private SpringBoard messages and destabilize the device if the script is buggy."
                                        version:@"1.0"
                                         author:@"Iggy05"
                                       category:@"SpringBoard"
                                     symbolName:@"bolt.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsQuickLoaderEnabled
                                          isNew:NO];
        quickLoader.settingsSection = kSecQuickLoader;
        quickLoader.unstableWarning = @"Runs user-selected JavaScript with access to infern0's RemoteCall helpers. Only use scripts you trust; bad scripts can crash SpringBoard.";

        Package *copypastaLite = [[Package alloc] initWithIdentifier:@"com.darksword.copypastalite"
                                           name:@"Copypasta Lite"
                               shortDescription:@"Editable system clipboard shelf"
                                longDescription:@"Stores three editable text snippets inside infern0. One tap writes the selected snippet to UIPasteboard, and a capture action can save the current text clipboard back into any slot. Every app can then accept the text through its normal Paste command. This safe build intentionally uses the infern0 settings panel because RemoteCall cannot attach a new snippet-specific callback inside third-party keyboard hosts."
                                        version:version
                                         author:@"Nnnnnnn274"
                                       category:@"Productivity"
                                     symbolName:@"doc.on.clipboard"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsCopypastaLiteEnabled
                                          isNew:YES];
        copypastaLite.settingsSection = kSecCopypastaLite;

#if CYANIDE_EXPERIMENTAL_TWEAKS_AVAILABLE
        Package *fastLockXLite = [[Package alloc] initWithIdentifier:@"com.darksword.fastlockx-lite"
                                           name:@"FastLockX Lite"
                               shortDescription:@"Face ID retry + unlock controls"
                                longDescription:@"RemoteCall-only port of the usable FastLockX primitives recovered from the iOS 15 tweak by Artem Kasper.\n\nCredits: original FastLockX by Artem Kasper; infern0 FastLockX Lite port by zeroxjf.\n\nIt can pulse SpringBoard's biometric retry path, ask the iOS 26 biometric coordinator to start a Mesa/Face ID unlock, and send the original Lock Screen unlock request as a fallback. Installing it through Apply Tweaks keeps those retry/unlock requests armed with SpringBoard timers so pickup-to-unlock can work after infern0 closes. The pulse loop pauses again after unlock.\n\nUse Disable, Clean Up, or a respring to stop the timers."
                                        version:version
                                         author:@"Artem Kasper / zeroxjf"
                                       category:@"Beta"
                                     symbolName:@"lock.open.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsFastLockXLiteEnabled
                                          isNew:NO];
        fastLockXLite.settingsSection = kSecFastLockXLite;
        fastLockXLite.unstableWarning = @"Beta / unstable: sends private SpringBoard lock-screen and biometric-resource messages. Always On runs SpringBoard timers while the device is locked, so disable it or respring if Face ID feels noisy or unstable.";

        Package *velvet = [[Package alloc] initWithIdentifier:@"com.darksword.velvet"
                                           name:@"Velvet + Edge Glow"
                               shortDescription:@"Compact banners and notification edge lighting"
                                longDescription:@"Combines Velvet/TinyBanners styling with the community-requested Edge and Notchification visual. It applies custom banner and Notification Center colors, borders, corner radius, compact scale, and opacity. An optional non-interactive outline appears only while an incoming SpringBoard banner is active, with full-screen edge and compact top-only modes. The live scanner reapplies settings while infern0 is active and cleanup removes the glow overlay and restores banner geometry."
                                        version:version
                                         author:@"Nnnnnnn274"
                                       category:@"SpringBoard"
                                     symbolName:@"rectangle.3.group.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsVelvetEnabled
                                          isNew:YES];
        velvet.settingsSection = kSecVelvet;
        velvet.unstableWarning = @"Beta: live notification styling depends on SpringBoard view hierarchy names and may need reapply after respring or OS updates.";

        Package *cleanNC = [[Package alloc] initWithIdentifier:@"com.darksword.cleannc"
                                           name:@"CleanNC"
                               shortDescription:@"Hide Notification Center clutter"
                                longDescription:@"Hides the search bar, 'No Older Notifications' text, and background grid views from Notification Center."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"SpringBoard"
                                     symbolName:@"rectangle.3.group.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsCleanNCEnabled
                                          isNew:NO];
        cleanNC.settingsSection = kSecCleanNC;

        Package *underTime = [[Package alloc] initWithIdentifier:@"com.darksword.undertime"
                                           name:@"UnderTime"
                               shortDescription:@"Double-line clock in the status bar"
                                longDescription:@"Sets the status bar time to a double-line format (hour on top, minutes below) using SpringBoard's internal time-item formatting API."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"Beta"
                                     symbolName:@"clock.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsUnderTimeEnabled
                                          isNew:NO];
        underTime.settingsSection = kSecUnderTime;

        Package *zeppelinLite = [[Package alloc] initWithIdentifier:@"com.darksword.zeppelinlite"
                                           name:@"Zeppelin Lite"
                               shortDescription:@"Custom carrier text in the status bar"
                                longDescription:@"Replaces the carrier name in the status bar with custom text using SpringBoard's carrier-item text API. Set your text in Settings."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"SpringBoard"
                                     symbolName:@"textformat.alt"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsZeppelinLiteEnabled
                                          isNew:NO];
        zeppelinLite.settingsSection = kSecZeppelinLite;

        Package *cleanHomeScreen = [[Package alloc] initWithIdentifier:@"com.darksword.cleanhomescreen"
                                           name:@"CleanHomeScreen"
                               shortDescription:@"Hide home screen badges, dots, and labels"
                                longDescription:@"Hides notification badges, page dots, and icon labels on the home screen. Each element can be toggled individually in Settings."
                                        version:version
                                         author:@"Nnnnnnn274"
                                       category:@"Home Screen"
                                     symbolName:@"square.dashed"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsCleanHomeScreenEnabled
                                          isNew:NO];
        cleanHomeScreen.settingsSection = kSecCleanHomeScreen;

        Package *realCC = [[Package alloc] initWithIdentifier:@"com.darksword.realcc"
                                           name:@"RealCC"
                               shortDescription:@"Disable Control Center toggles for WiFi and Bluetooth"
                                longDescription:@"Writes system preference plists to disable WiFi and Bluetooth toggles in Control Center, then kills the associated daemons. Configure which radios to disable in Settings."
                                        version:version
                                         author:@"Nnnnnnn274"
                                       category:@"System"
                                     symbolName:@"wifi.slash"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsRealCCEnabled
                                          isNew:NO];
        realCC.settingsSection = kSecRealCC;

        Package *cleanCC = [[Package alloc] initWithIdentifier:@"com.darksword.cleancc"
                                           name:@"CleanCC"
                               shortDescription:@"Cleaner Control Center material"
                                longDescription:@"First-pass CleanCC/Glacier-style port. Adjusts visible Control Center material alpha and background tint while infern0 is active."
                                        version:version
                                         author:@"Nnnnnnn274"
                                       category:@"Control Center"
                                     symbolName:@"square.stack.3d.down.right.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsCleanCCEnabled
                                          isNew:YES];
        cleanCC.settingsSection = kSecCleanCC;

        Package *fuGap = [[Package alloc] initWithIdentifier:@"com.darksword.fugap"
                                           name:@"FUGap"
                               shortDescription:@"Reduce Control Center top gap"
                                longDescription:@"First-pass FUGap-style port. Applies an upward transform to visible Control Center containers to reduce the top presentation gap."
                                        version:version
                                         author:@"Nnnnnnn274"
                                       category:@"Control Center"
                                     symbolName:@"arrow.up.to.line.compact"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsFUGapEnabled
                                          isNew:YES];
        fuGap.settingsSection = kSecFUGap;

        Package *moduleSpacing = [[Package alloc] initWithIdentifier:@"com.darksword.modulespacing"
                                           name:@"ModuleSpacing"
                               shortDescription:@"Compact Control Center modules"
                                longDescription:@"First-pass ModuleSpacing port. Applies a compact styling pass to visible Control Center module layers."
                                        version:version
                                         author:@"Nnnnnnn274"
                                       category:@"Control Center"
                                     symbolName:@"rectangle.grid.2x2"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsModuleSpacingEnabled
                                          isNew:YES];
        moduleSpacing.settingsSection = kSecModuleSpacing;

        Package *sugarCane = [[Package alloc] initWithIdentifier:@"com.darksword.sugarcane"
                                           name:@"SugarCane"
                               shortDescription:@"Brightness and volume percentages"
                                longDescription:@"First-pass SugarCane-style port. Adds a lightweight numeric percentage overlay for Control Center brightness and volume style modules."
                                        version:version
                                         author:@"Nnnnnnn274"
                                       category:@"Control Center"
                                     symbolName:@"percent"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsSugarCaneEnabled
                                          isNew:YES];
        sugarCane.settingsSection = kSecSugarCane;

        Package *betterCCXI = [[Package alloc] initWithIdentifier:@"com.darksword.betterccxi"
                                           name:@"BetterCCXI / Prysm Lite"
                               shortDescription:@"Larger Control Center module emphasis"
                                longDescription:@"Applies a cohesive, configurable scale and depth treatment to Control Center module, media, and Now Playing containers while infern0 is active. It does not rewrite persistent Control Center layout preferences."
                                        version:version
                                         author:@"Nnnnnnn274"
                                       category:@"Control Center"
                                     symbolName:@"rectangle.grid.3x2.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsBetterCCXIEnabled
                                          isNew:YES];
        betterCCXI.settingsSection = kSecBetterCCXI;

        Package *magma = [[Package alloc] initWithIdentifier:@"com.darksword.magma"
                                           name:@"Magma 2"
                               shortDescription:@"Safe, contrast-aware Control Center colors"
                                longDescription:@"A rewritten live-session Control Center color customizer. Magma 2 colors verified toggle accents, contrast-aware selected glyphs, brightness and volume fills, media controls, and optional module backgrounds.\n\nUnlike the retired implementation, it scans only the visible Control Center window, recognizes specialized color properties, and enforces strict view, depth, child, and property limits. It never mutates controllers, gesture handling, layout geometry, slider values, or material recipes. Every owned property is captured for exact restoration, with detailed per-pass logs."
                                        version:version
                                         author:@"Nnnnnnn274"
                                       category:@"Control Center"
                                     symbolName:@"flame.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsMagmaEnabled
                                          isNew:YES];
        magma.settingsSection = kSecMagma;
        magma.unstableWarning = @"Beta: module background tinting is the broadest visual option and remains off by default. Toggle, slider, and media coloring use narrower verified targets.";
        magma.knownIssues = @[
            @"Open Control Center after applying; Magma 2 waits without mutation while Control Center is closed.",
            @"Apple may replace some media-control classes between iOS releases. Unsupported media leaves are skipped and reported in the detailed log.",
        ];

        Package *betterCCIcons = [[Package alloc] initWithIdentifier:@"com.darksword.betterccicons"
                                           name:@"BetterCCIcons"
                               shortDescription:@"Round Control Center module icons"
                                longDescription:@"First-pass BetterCCIcons/Polus-style port. Applies rounded corner styling to visible Control Center module and icon layers."
                                        version:version
                                         author:@"Nnnnnnn274"
                                       category:@"Control Center"
                                     symbolName:@"circle.grid.2x2.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsBetterCCIconsEnabled
                                          isNew:YES];
        betterCCIcons.settingsSection = kSecBetterCCIcons;

        Package *ccNoPlatterDim = [[Package alloc] initWithIdentifier:@"com.darksword.ccnoplatterdim"
                                           name:@"CCNoPlatterDim"
                               shortDescription:@"Keep expanded Control Center bright"
                                longDescription:@"First-pass CCNoPlatterDim port. Reduces visible Control Center dimming so expanded modules keep the background clearer."
                                        version:version
                                         author:@"Nnnnnnn274"
                                       category:@"Control Center"
                                     symbolName:@"sun.max.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsCCNoPlatterDimEnabled
                                          isNew:YES];
        ccNoPlatterDim.settingsSection = kSecCCNoPlatterDim;

        Package *ccStatus = [[Package alloc] initWithIdentifier:@"com.darksword.ccstatus"
                                           name:@"CCStatus"
                               shortDescription:@"Control Center status header"
                                longDescription:@"First-pass CCStatus port. Adds a lightweight status text overlay near the Control Center header while infern0 is active."
                                        version:version
                                         author:@"Nnnnnnn274"
                                       category:@"Control Center"
                                     symbolName:@"info.circle.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsCCStatusEnabled
                                          isNew:YES];
        ccStatus.settingsSection = kSecCCStatus;

        Package *hapticCC = [[Package alloc] initWithIdentifier:@"com.darksword.hapticcc"
                                           name:@"HapticCC"
                               shortDescription:@"Control Center haptic feedback"
                                longDescription:@"First-pass HapticCC port. Primes native haptic feedback for Control Center interactions during the active infern0 session."
                                        version:version
                                         author:@"Nnnnnnn274"
                                       category:@"Control Center"
                                     symbolName:@"waveform.path"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsHapticCCEnabled
                                          isNew:YES];
        hapticCC.settingsSection = kSecHapticCC;

        Package *secureCC = [[Package alloc] initWithIdentifier:@"com.darksword.securecc"
                                           name:@"SecureCC"
                               shortDescription:@"Control Center lockscreen guard"
                                longDescription:@"First-pass SecureCC/CCDelay port. Adds an active-session SecureCC indicator as groundwork for locked-screen Control Center protections."
                                        version:version
                                         author:@"Nnnnnnn274"
                                       category:@"Control Center"
                                     symbolName:@"lock.shield.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsSecureCCEnabled
                                          isNew:YES];
        secureCC.settingsSection = kSecSecureCC;

        Package *hideLabels = [[Package alloc] initWithIdentifier:@"com.darksword.hidellabels"
                                           name:@"HideLabels"
                               shortDescription:@"Hide all icon labels on the home screen"
                                longDescription:@"Zeros the alpha of all UILabel subviews inside home screen icon views, effectively hiding all icon labels."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"Home Screen"
                                     symbolName:@"eye.slash"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsHideLabelsEnabled
                                          isNew:NO];
        hideLabels.settingsSection = kSecHideLabels;

        Package *fakeClockUp = [[Package alloc] initWithIdentifier:@"com.darksword.fakeclockup"
                                           name:@"FakeClockUp"
                               shortDescription:@"Tune live SpringBoard window animation speed"
                                longDescription:@"Applies a configurable CALayer speed multiplier to active SpringBoard window layers. It captures every original layer speed and restores it exactly when disabled; it does not patch the Clock app or write persistent system files."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"SpringBoard"
                                     symbolName:@"forward.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsFakeClockUpEnabled
                                          isNew:NO];
        fakeClockUp.settingsSection = kSecFakeClockUp;

        Package *pancake = [[Package alloc] initWithIdentifier:@"com.darksword.pancake"
                                           name:@"Pancake"
                               shortDescription:@"Reliable native edge-back gesture controls"
                                longDescription:@"Configures the active navigation controller's native interactive-pop gesture instead of attaching a synthetic gesture to every window. Touch limits and cancellation behavior are configurable, and all native values are restored exactly when disabled."
                                        version:version
                                         author:@"Nnnnnnn274"
                                       category:@"Home Screen"
                                     symbolName:@"hand.point.left.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsPancakeEnabled
                                          isNew:NO];
        pancake.settingsSection = kSecPancake;

        Package *cylinderLite = [[Package alloc] initWithIdentifier:@"com.darksword.cylinderlite"
                                           name:@"Cylinder Lite"
                               shortDescription:@"Low-traffic cylindrical page-swipe animations"
                                longDescription:@"Transforms loaded Home Screen pages as whole layers instead of scanning and mutating hundreds of individual icons. A one-time baseline records page positions; steady-state refreshes read one anchor page and derive the shared scroll offset for every page. Centered pages settle at their captured stock transform, icon taps keep their native behavior, and Dock and App Library lists remain untouched. A two-failure circuit breaker stops remote calls if the VM transport becomes unhealthy."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"Home Screen"
                                     symbolName:@"perspective"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsCylinderLiteEnabled
                                          isNew:NO];
        cylinderLite.settingsSection = kSecCylinderLite;

        Package *barmoji = [[Package alloc] initWithIdentifier:@"com.darksword.barmoji"
                                           name:@"Barmoji"
                               shortDescription:@"Pressable emoji button strip"
                                longDescription:@"Adds eight real emoji buttons near the bottom of SpringBoard. Each button highlights and produces selection feedback when pressed. The enabled preference survives reboot, and infern0 recreates the live overlay when its SpringBoard session starts.\n\nCross-process insertion into arbitrary app text fields is not part of this SpringBoard overlay build."
                                        version:version
                                         author:@"Nnnnnnn274"
                                       category:@"SpringBoard"
                                     symbolName:@"face.smiling.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsBarmojiEnabled
                                          isNew:YES];
        barmoji.settingsSection = kSecBarmoji;
        barmoji.unstableWarning = @"Beta: press feedback works in the SpringBoard overlay, but this build does not inject text into arbitrary app keyboard hosts.";

        Package *roundedIcons = [[Package alloc] initWithIdentifier:@"com.darksword.roundedicons"
                                           name:@"Rounded Icons"
                               shortDescription:@"Smooth corners for every Home Screen icon"
                                longDescription:@"Applies a configurable continuous corner radius directly to every discovered live Home Screen icon. No icon theme is required, all pages are scanned, and the original icon views remain tappable."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"Home Screen"
                                     symbolName:@"app.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsRoundedIconsEnabled
                                          isNew:YES];
        roundedIcons.settingsSection = kSecRoundedIcons;

        Package *watchLayout = [[Package alloc] initWithIdentifier:@"com.darksword.watchlayout"
                                           name:@"Watch Layout"
                               shortDescription:@"Staggered Apple Watch-style beehive icon grid"
                                longDescription:@"Replaces the page grid for the current SpringBoard session with a vertically scrolling Apple Watch-style honeycomb. It builds alternating five- and four-icon rows from native SBIconViews, keeps every tile pressable, includes system apps, and leaves the Dock untouched. Compactness and icon size are configurable. The stock page views are hidden rather than rewritten, then restored when the tweak stops. App discovery is bounded, repeated failures back off for 30 seconds, and detailed logs report catalog, geometry, interaction, fallback, and cleanup results."
                                        version:version
                                         author:@"hxhlb + infern0"
                                       category:@"Home Screen"
                                     symbolName:@"circle.grid.3x3.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsWatchLayoutEnabled
                                          isNew:YES];
        watchLayout.settingsSection = kSecWatchLayout;

        Package *lockCustomizer = [[Package alloc] initWithIdentifier:@"com.darksword.lockcustomizer"
                                           name:@"Lock Screen Customizer"
                               shortDescription:@"Move, resize, and clean up the Lock Screen"
                                longDescription:@"A configurable Lock Screen customizer that resizes and repositions the live clock, adjusts opacity, hides camera, flashlight, or page-dot views, and includes Kumquat Lite scaling for live MediaControls. Metal Lock Light adds an adjustable ice, violet, or gold edge glow without intercepting touch input. Every matched change is logged and uninstall restores stock transforms and visibility."
                                        version:version
                                         author:@"Nnnnnnn274"
                                       category:@"Lock Screen"
                                     symbolName:@"lock.rectangle"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsLockCustomizerEnabled
                                          isNew:YES];
        lockCustomizer.settingsSection = kSecLockCustomizer;

        Package *freePlacement = [[Package alloc] initWithIdentifier:@"com.darksword.freeplacementlite"
                                           name:@"Free Placement Lite"
                               shortDescription:@"Configurable free-form icon offsets"
                                longDescription:@"Creates a configurable staggered, free-form layout across every discovered live Home Screen icon while keeping icons pressable. Page-local offsets are clamped to visible bounds so icons cannot disappear, newly loaded pages are picked up by the live refresh loop, and cleanup restores every captured frame. This RemoteCall port provides global placement controls; per-icon dragging is not included yet."
                                        version:version
                                         author:@"Nnnnnnn274"
                                       category:@"Home Screen"
                                     symbolName:@"move.3d"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsFreePlacementEnabled
                                          isNew:YES];
        freePlacement.settingsSection = kSecFreePlacement;

        Package *appLibraryStudio = [[Package alloc] initWithIdentifier:@"com.darksword.applibrarystudio"
                                           name:@"App Library Studio"
                               shortDescription:@"Custom App Library layout and no Today View"
                                longDescription:@"Adds separate size, horizontal-spacing, vertical-spacing, and label controls for live App Library icons and category pods while keeping them pressable. Its Disable Today View option removes SpringBoard's leading page controller so left swipes do not land on a hidden blank page. App Library geometry restores during cleanup; rebuilding Today View after disabling it requires a respring. Every apply, restore, match count, and selected value is written to the detailed activity log."
                                        version:version
                                         author:@"Nnnnnnn274"
                                       category:@"Home Screen"
                                     symbolName:@"square.grid.3x3.square"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsAppLibraryStudioEnabled
                                          isNew:YES];
        appLibraryStudio.settingsSection = kSecAppLibraryStudio;
        appLibraryStudio.unstableWarning = @"Beta: App Library class names and page-controller internals can change between iOS builds. Icon layout is session-only; disabling Today View is restored by respring.";

        Package *blurryBadges = [[Package alloc] initWithIdentifier:@"com.darksword.blurrybadges"
                                           name:@"Badge Studio"
                               shortDescription:@"Colorized badges that grow with the count"
                                longDescription:@"Combines the BlurryBadges tint pass with Growing Badges+ behavior. It scans every discovered SpringBoard window, reads live badge values, and scales larger counts toward a configurable maximum. Tint, opacity, growth, and maximum size all have settings and detailed logs."
                                        version:version
                                         author:@"Nnnnnnn274"
                                       category:@"Home Screen"
                                     symbolName:@"app.badge.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsBlurryBadgesEnabled
                                          isNew:YES];
        blurryBadges.settingsSection = kSecBlurryBadges;

        Package *snapper = [[Package alloc] initWithIdentifier:@"com.darksword.snapper"
                                           name:@"Snapper"
                               shortDescription:@"Capture and pin cropped screen regions"
                                longDescription:@"Shows a configurable crop frame, captures the selected live SpringBoard region, and pins up to eight touch-through snapshots above the current interface. Capture and Clear controls live in Settings. Cleanup removes every selection and pin with detailed activity logs."
                                        version:version
                                         author:@"Nnnnnnn274"
                                       category:@"SpringBoard"
                                     symbolName:@"crop"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsSnapperEnabled
                                          isNew:YES];
        snapper.settingsSection = kSecSnapper;
        snapper.unstableWarning = @"Session implementation: pinned captures live in SpringBoard memory and disappear on cleanup, respring, or reboot.";

        Package *pullOver = [[Package alloc] initWithIdentifier:@"com.darksword.pullover"
                                           name:@"PullOver"
                               shortDescription:@"Live-icon slide-over launcher"
                                longDescription:@"Adds a configurable slide-over launcher populated with live SpringBoard icon views. Borrowed icons stay pressable and are returned to their exact original parents and frames during reapply or cleanup. If no eligible icons are visible, the tray remains available and reports the fallback in the detailed log."
                                        version:version
                                         author:@"Nnnnnnn274"
                                       category:@"SpringBoard"
                                     symbolName:@"sidebar.right"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsPullOverEnabled
                                          isNew:YES];
        pullOver.settingsSection = kSecPullOver;
        pullOver.unstableWarning = @"Session launcher: this safely hosts live icons, not arbitrary third-party app scenes. Use Dynamic Stage for floating application scenes.";

        Package *alkaline = [[Package alloc] initWithIdentifier:@"com.darksword.alkaline"
                                           name:@"Alkaline"
                               shortDescription:@"Battery tint theme"
                                longDescription:@"First-pass Alkaline/Lithium Ion-style battery theming. Tints visible battery views in SpringBoard while infern0 is active.\n\nCustom image themes are planned; this version starts with a stable color pass."
                                        version:version
                                         author:@"Nnnnnnn274"
                                       category:@"Status Bar"
                                     symbolName:@"battery.100.bolt"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsAlkalineEnabled
                                          isNew:YES];
        alkaline.settingsSection = kSecAlkaline;

        Package *tweakLoader = [[Package alloc] initWithIdentifier:@"com.darksword.tweakloader"
                                           name:@"TweakLoader"
                               shortDescription:@"Registration-based precompiled .m/.h tweaks"
                                longDescription:@"Hosts built-in RemoteCall-based tweaks compiled into the binary. Add new tweaks by registering them in tweakloader_register_builtins(). Supports dynamic dylib loading when AMFI+kPAC bypass is available."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"System"
                                     symbolName:@"arrow.down.circle.dotted"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsTweakLoaderEnabled
                                          isNew:NO];
        tweakLoader.settingsSection = kSecTweakLoader;

#endif

        Package *nanoRegistry = [[Package alloc] initWithIdentifier:@"com.darksword.nanoregistry"
                                           name:@"Watch Pairing Override"
                               shortDescription:@"Pair a newer watch or revive an older one"
                                longDescription:@"Changes the watchOS pairing range saved on this iPhone.\n\nMost people should use watchOS Range 99/23/10/6 in Settings, then apply the override. These are pairing protocol generations, not Apple Watch model numbers. 99 raises the watchOS pairing ceiling. 23 keeps the generation-23 setup protocol accepted. 10 and 6 leave the legacy chip and multi-watch floors at their normal values.\n\nApple Watch Ultra 3 cannot pair on iOS versions below 26 at this time.\n\nSystem-file warning: this modifies the local NanoRegistry compatibility-index MobileAsset and saves a .cyanide.bak backup beside the original file. Pairing-asset edits can fail, partially apply, require a respring or reboot to settle, or leave pairing state inconsistent. You apply or remove this override at your own risk.\n\nRespring or reboot after installing or removing the override before trying to pair."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"System"
                                     symbolName:@"applewatch.radiowaves.left.and.right"
                                           kind:PackageInstallKindNanoRegistry
                                     enabledKey:nil
                                          isNew:NO];
        nanoRegistry.settingsSection = kSecNanoRegistry;
        nanoRegistry.unstableWarning = @"Warning: modifies a local NanoRegistry MobileAsset. infern0 saves a .cyanide.bak backup beside the original, but system-file edits can fail or require a respring/reboot. Apply or remove this override at your own risk.";

        Package *callRecordingSound = [[Package alloc] initWithIdentifier:@"com.darksword.callrecording-sound"
                                           name:@"Call Recording Sound"
                               shortDescription:@"Silence disclosure start/stop sounds"
                                longDescription:@"Replaces the CallServices StartDisclosureWithTone and StopDisclosure audio files with infern0's bundled silent payloads.\n\nCredits: YangJiiii (@duongduong0908) for the EnsWilde and Disable Call Recording BookRestore reference tools. @Little_34306 is credited by the original projects for the Disable Call Recording concept. infern0 port, KRW-backed implementation, and generated replacement silent audio assets by zeroxjf.\n\nSystem-file warning: this modifies files under /var/mobile/Library/CallServices/Greetings/default. infern0 backs up the first originals into its app container, but system file replacement can fail, partially apply, or require a respring/reboot to settle.\n\nLegal note: call-recording disclosure sounds may exist to satisfy consent, notification, or privacy-law requirements in some places. You are responsible for understanding and following the laws that apply to you.\n\nThis port does not use the old Books/BookRestore/sparserestore path. infern0 runs KRW, unlocks local /private/var write access, then writes directly to the CallServices files.\n\nUse Restore Original Sounds to write infern0's backups back when present. You apply or restore this tweak at your own risk."
                                        version:version
                                         author:@"YangJiiii (@duongduong0908) / zeroxjf"
                                       category:@"System"
                                     symbolName:@"speaker.slash.fill"
                                           kind:PackageInstallKindCallRecordingSound
                                     enabledKey:nil
                                          isNew:NO];
        callRecordingSound.settingsSection = kSecCallRecordingSound;
        callRecordingSound.experimental = NO;
        callRecordingSound.unstableWarning = @"Beta: persistent CallServices system-file replacement. Disclosure sounds may be legally required where you live; you are responsible for your use and apply this at your own risk. Use Restore Original Sounds before removing infern0 if you want infern0's backups written back.";

        Package *hideHomeBar = [[Package alloc] initWithIdentifier:@"com.darksword.hide-home-bar"
                                           name:@"Hide Home Bar"
                               shortDescription:@"Hide the bottom home indicator"
                                longDescription:@"Zeros the first page of /System/Library/PrivateFrameworks/MaterialKit.framework/Assets.car using infern0's stable file-page zero path, which hides the bottom home indicator after SpringBoard reloads assets.\n\nRun Hide Home Bar by itself, then respring so SpringBoard refreshes the asset cache. To bring the home indicator back, choose Restore Home Bar and respring again. Other live SpringBoard tweaks, such as App Switcher Grid, should be applied in a separate run after the respring.\n\nCredits: C4ndyF1sh/ZeroCalories for the Home Bar target and jailbreakdotparty/dirtyZero for the original page-zeroing idea. infern0 port by zeroxjf."
                                        version:version
                                         author:@"C4ndyF1sh / jailbreakdotparty / zeroxjf"
                                       category:@"Home Screen"
                                     symbolName:@"line.3.horizontal"
                                           kind:PackageInstallKindHideHomeBar
                                     enabledKey:nil
                                          isNew:NO];
        hideHomeBar.settingsSection = kSecHideHomeBar;
        hideHomeBar.unstableWarning = @"Beta: system asset page zeroing. Run by itself, then respring after hiding. To restore the home indicator, choose Restore Home Bar and respring.";

        Package *otaBlock = [[Package alloc] initWithIdentifier:@"com.darksword.ota-block"
                                           name:@"OTA Updates"
                               shortDescription:@"Enable or disable over-the-air system updates"
                                longDescription:@"Disables or enables the launchd jobs responsible for over-the-air system updates by editing disabled.plist. State persists across reboots.\n\nSystem-file warning: this edits /private/var/db/com.apple.xpc.launchd/disabled.plist. Incorrect or partial writes can affect launchd job state across boot. You disable or re-enable OTA updates at your own risk.\n\nNo Run/Apply step required for this package. Use Disable to block OTA updates, or Enable to restore them."
                                        version:version
                                         author:@"kolbicz"
                                       category:@"System"
                                     symbolName:@"icloud.slash.fill"
                                          kind:PackageInstallKindOTA
                                    enabledKey:nil
                                         isNew:NO];
        otaBlock.settingsSection = kSecOTA;
        otaBlock.unstableWarning = @"Warning: persistent system-file edit. This package modifies launchd disabled.plist to change OTA job state across reboot. Disable or re-enable OTA updates at your own risk.";

        Package *disableAppLibrary = [[Package alloc] initWithIdentifier:@"com.darksword.disable-app-library"
                                           name:@"Disable App Library"
                               shortDescription:@"Remove the App Library page"
                                longDescription:@"Removes the App Library page that sits past your last home-screen page. Swiping past the last page becomes a no-op."
                                        version:version
                                         author:@"kolbicz"
                                       category:@"SpringBoard"
                                     symbolName:@"square.grid.2x2.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsDSDisableAppLibrary
                                          isNew:NO];

        list = @[
            statBar,
            nsBar,
            niceBarLite,
            sbc,
            layoutExtras,
            gravityLite,
            powercuff,
            themer,

            disableAppLibrary,

            [[Package alloc] initWithIdentifier:@"com.darksword.disable-icon-flyin"
                                           name:@"Disable Icon Fly-In"
                               shortDescription:@"Skip the icon spring animation"
                                longDescription:@"Skips the spring animation that plays when home screen icons appear after unlock or app switch. Icons just appear in their final position."
                                        version:version
                                         author:@"kolbicz"
                                       category:@"SpringBoard"
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
                                       category:@"SpringBoard"
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
                                       category:@"SpringBoard"
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
                                       category:@"SpringBoard"
                                     symbolName:@"hand.tap.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsDSDoubleTapToLock
                                          isNew:NO],

            ({
                Package *drag = [[Package alloc] initWithIdentifier:@"com.darksword.drag-coefficient"
                                                               name:@"Drag Coefficient"
                                                   shortDescription:@"Custom SpringBoard animation speed multiplier"
                                                    longDescription:@"Overrides _UIAnimationDragCoefficient in SpringBoard to make all UIKit spring animations faster or slower.\n\nSet the coefficient in the Drag Coefficient settings panel. 50% = 0.50× (2× faster), 25% = 0.25× (4× faster), 100% = stock.\n\nImported from kolbicz/DarkSword-Tweaks."
                                                            version:version
                                                             author:@"kolbicz"
                                                           category:@"SpringBoard"
                                                         symbolName:@"dial.medium.fill"
                                                               kind:PackageInstallKindToggle
                                                         enabledKey:kSettingsDSDragCoefficientEnabled
                                                              isNew:NO];
                drag.settingsSection = kSecDragCoefficient;
                drag;
            }),

            otaBlock,

            // Higher-risk/manual packages last so their warnings sit below core tweaks.
#if CYANIDE_EXPERIMENTAL_TWEAKS_AVAILABLE
            signal,
#endif
            axon,
            nanoRegistry,
            callRecordingSound,
            hideHomeBar,
#if CYANIDE_EXPERIMENTAL_TWEAKS_AVAILABLE
            typeBanner,
            notificationIsland,
            ipaDecryptor,
            stageStrip,
            fastLockXLite,
            velvet,
            cleanNC,
            underTime,
            zeppelinLite,
            cleanHomeScreen,
            realCC,
            cleanCC,
            fuGap,
            moduleSpacing,
            sugarCane,
            betterCCXI,
            magma,
            betterCCIcons,
            ccNoPlatterDim,
            ccStatus,
            hapticCC,
            secureCC,
            hideLabels,
            fakeClockUp,
            pancake,
            cylinderLite,
            barmoji,
            roundedIcons,
            watchLayout,
            lockCustomizer,
            freePlacement,
            appLibraryStudio,
            blurryBadges,
            snapper,
            pullOver,
            alkaline,
            tweakLoader,
#endif
            locationSim,
            snowboardLite,
            liveWP,
            appSwitcherGrid,
            quickLoader,
            copypastaLite,
        ];
        NSSet<NSString *> *retainedPackageIDs = [NSSet setWithArray:@[
            @"com.darksword.statbar",
            @"com.darksword.nsbar",
            @"com.darksword.nicebarlite",
            @"com.darksword.rssidisplay",
            @"com.darksword.sbcustomizer",
            @"com.darksword.powercuff",
            @"com.darksword.axonlite",
            @"com.darksword.typebanner",
            @"com.darksword.notificationisland",
            @"com.darksword.ipadecryptor",
            @"com.darksword.stagestrip",
            @"com.darksword.themer",
            @"com.darksword.locationsim",
            @"com.darksword.snowboardlite",
            @"com.darksword.livewp",
            @"com.darksword.layoutextras",
            @"com.darksword.gravitylite",
            @"com.darksword.appswitchergrid",
            @"com.darksword.quickloader",
            @"com.darksword.fastlockx-lite",
            @"com.darksword.nanoregistry",
            @"com.darksword.callrecording-sound",
            @"com.darksword.hide-home-bar",
            @"com.darksword.drag-coefficient",
            @"com.darksword.ota-block",
            @"com.darksword.disable-app-library",
            @"com.darksword.disable-icon-flyin",
            @"com.darksword.zero-wake-animation",
            @"com.darksword.zero-backlight-fade",
            @"com.darksword.double-tap-to-lock",
            @"com.darksword.cylinderlite",
            @"com.darksword.barmoji",
            @"com.darksword.watchlayout",
            @"com.darksword.lockcustomizer",
        ]];
        list = [list filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(Package *package, NSDictionary *bindings) {
            (void)bindings;
            return [retainedPackageIDs containsObject:package.identifier];
        }]];
        NSSet<NSString *> *darkSwordIDs = [NSSet setWithArray:@[
            @"com.darksword.disable-app-library",
            @"com.darksword.disable-icon-flyin",
            @"com.darksword.zero-wake-animation",
            @"com.darksword.zero-backlight-fade",
            @"com.darksword.double-tap-to-lock",
        ]];
        for (Package *package in list) {
            if ([darkSwordIDs containsObject:package.identifier]) {
                package.settingsSection = kSecDarkSwordTweaks;
            }
        }
    });
    return list;
}

+ (NSArray<NSString *> *)categoriesInOrder
{
    NSArray<NSString *> *preferred = @[
        @"Beta",
        @"Experimental",
        @"Status Bar",
        @"Home Screen",
        @"Theming",
        @"SpringBoard",
        @"System",
        @"JavaScript Tweaks",
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
