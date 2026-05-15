//
//  Package.h
//  Cyanide
//
//  Model object representing one tweak in the Installer-style packages tab.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PackageInstallKind) {
    // Master enable is a BOOL in NSUserDefaults under enabledKey. Installing
    // sets it to YES; uninstalling sets NO. settings_run_actions() applies.
    PackageInstallKindToggle = 0,

    // Persistent system tweak that does not use settings_run_actions().
    // Installing calls darksword_ota_set_disabled(true); uninstalling calls
    // darksword_ota_set_disabled(false). State tracked in a defaults intent key.
    PackageInstallKindOTA = 1,
};

@interface Package : NSObject

@property (nonatomic, readonly, copy)     NSString *identifier;
@property (nonatomic, readonly, copy)     NSString *name;
@property (nonatomic, readonly, copy)     NSString *shortDescription;
@property (nonatomic, readonly, copy)     NSString *longDescription;
@property (nonatomic, readonly, copy)     NSString *version;
@property (nonatomic, readonly, copy)     NSString *author;
@property (nonatomic, readonly, copy)     NSString *category;
@property (nonatomic, readonly, copy)     NSString *symbolName;
@property (nonatomic, readonly, assign)   PackageInstallKind kind;
@property (nonatomic, readonly, copy, nullable) NSString *enabledKey;
@property (nonatomic, readonly, assign)   BOOL isNew;

// SettingsSection enum value that corresponds to this package's bundle in the
// Settings tab. NSIntegerMax means the package has no Settings bundle
// (install/uninstall is its only operation).
@property (nonatomic, assign) NSInteger settingsSection;

@property (nonatomic, readonly, assign) BOOL isInstalled;

- (instancetype)initWithIdentifier:(NSString *)identifier
                              name:(NSString *)name
                  shortDescription:(NSString *)shortDescription
                   longDescription:(NSString *)longDescription
                           version:(NSString *)version
                            author:(NSString *)author
                          category:(NSString *)category
                        symbolName:(NSString *)symbolName
                              kind:(PackageInstallKind)kind
                        enabledKey:(nullable NSString *)enabledKey
                             isNew:(BOOL)isNew NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

- (void)install;
- (void)uninstall;

@end

NS_ASSUME_NONNULL_END
