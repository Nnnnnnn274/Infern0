//
//  Package.m
//  Cyanide
//

#import "Package.h"
#import "PackageQueue.h"
#import "../SettingsViewController.h"
#import "../tweaks/darksword_ota.h"

NSString * const kInstallerOTADisabledIntent = @"installer.ota.disabledIntent";

@implementation Package

- (instancetype)initWithIdentifier:(NSString *)identifier
                              name:(NSString *)name
                  shortDescription:(NSString *)shortDescription
                   longDescription:(NSString *)longDescription
                           version:(NSString *)version
                            author:(NSString *)author
                          category:(NSString *)category
                        symbolName:(NSString *)symbolName
                              kind:(PackageInstallKind)kind
                        enabledKey:(NSString *)enabledKey
                             isNew:(BOOL)isNew
{
    if ((self = [super init])) {
        _identifier       = [identifier copy];
        _name             = [name copy];
        _shortDescription = [shortDescription copy];
        _longDescription  = [longDescription copy];
        _version          = [version copy];
        _author           = [author copy];
        _category         = [category copy];
        _symbolName       = [symbolName copy];
        _kind             = kind;
        _enabledKey       = [enabledKey copy];
        _isNew            = isNew;
        _settingsSection  = NSIntegerMax;
    }
    return self;
}

- (BOOL)isInstalled
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    switch (self.kind) {
        case PackageInstallKindToggle:
            // Both the user's persisted intent AND a successful apply in the
            // current session — otherwise "Installed" lies after a restart.
            if (!self.enabledKey) return NO;
            if (![d boolForKey:self.enabledKey]) return NO;
            return settings_tweak_is_applied(self.enabledKey);
        case PackageInstallKindOTA:
            // OTA edits launchd disabled.plist which persists across reboots,
            // so the intent flag IS the actual state.
            return [d boolForKey:kInstallerOTADisabledIntent];
    }
}

- (void)install   { [[PackageQueue sharedQueue] toggleForPackage:self]; }
- (void)uninstall { [[PackageQueue sharedQueue] toggleForPackage:self]; }

// Called by PackageQueue.commit — writes the persisted state without
// triggering settings_run_actions itself (the queue does that once).
- (void)applyCommittedState:(BOOL)installed
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    switch (self.kind) {
        case PackageInstallKindToggle:
            if (self.enabledKey) {
                [d setBool:installed forKey:self.enabledKey];
                [d synchronize];
            }
            return;
        case PackageInstallKindOTA:
            darksword_ota_set_disabled(installed ? true : false);
            [d setBool:installed forKey:kInstallerOTADisabledIntent];
            [d synchronize];
            return;
    }
}

@end
