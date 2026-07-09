//
//  PackageCatalog.h
//  Cyanide
//
//  Static catalog of installable packages (one per user-facing tweak).
//

#import <Foundation/Foundation.h>
#import "Package.h"

NS_ASSUME_NONNULL_BEGIN

@interface PackageCatalog : NSObject

// Flat list, in display order. In-development packages can appear here with an
// installDisabledReason; packages with `experimental == YES` are omitted unless
// kSettingsExperimentalTweaksEnabled is on.
+ (NSArray<Package *> *)allPackages;

// Full list, ignoring the experimental gate. Use only for internal lookups
// (e.g. translating an identifier the user previously installed back into a
// Package even after they flip the master switch off). Never render this
// list directly.
+ (NSArray<Package *> *)allPackagesIncludingExperimental;

// Section header order, derived from allPackages.
+ (NSArray<NSString *> *)categoriesInOrder;

// Packages bucketed by category in section order.
+ (NSDictionary<NSString *, NSArray<Package *> *> *)packagesByCategory;

@end

NS_ASSUME_NONNULL_END
