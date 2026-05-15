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

// Flat list, in display order.
+ (NSArray<Package *> *)allPackages;

// Section header order, derived from allPackages.
+ (NSArray<NSString *> *)categoriesInOrder;

// Packages bucketed by category in section order.
+ (NSDictionary<NSString *, NSArray<Package *> *> *)packagesByCategory;

@end

NS_ASSUME_NONNULL_END
