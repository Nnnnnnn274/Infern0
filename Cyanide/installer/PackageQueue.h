//
//  PackageQueue.h
//  Cyanide
//
//  Sileo-style install/uninstall queue. User taps Install/Uninstall in a
//  package detail page; nothing applies until commit() is called from the
//  Queue review screen.
//

#import <Foundation/Foundation.h>
#import "Package.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString * const PackageQueueDidChangeNotification;

// Intent stored per package once enqueued.
typedef NS_ENUM(NSInteger, PackageQueueIntent) {
    PackageQueueIntentNone = 0,
    PackageQueueIntentInstall,
    PackageQueueIntentUninstall,
};

@interface PackageQueue : NSObject

+ (instancetype)sharedQueue;

@property (nonatomic, readonly) NSArray<Package *> *queuedInstalls;
@property (nonatomic, readonly) NSArray<Package *> *queuedUninstalls;
@property (nonatomic, readonly) NSInteger pendingCount;

- (PackageQueueIntent)intentForPackage:(Package *)package;

// Sileo-style "tap toggles queue":
//   not installed + not queued  → queue install
//   not installed + queued      → cancel queue
//   installed     + not queued  → queue uninstall
//   installed     + queued      → cancel queue
- (void)toggleForPackage:(Package *)package;

- (void)removePackage:(Package *)package;
- (void)clear;

// Writes the persisted state for every queued package, then triggers
// settings_run_actions() once. Clears the queue afterwards.
- (void)commit;

@end

NS_ASSUME_NONNULL_END
