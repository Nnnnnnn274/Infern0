//
//  PackageQueue.m
//  Cyanide
//

#import "PackageQueue.h"
#import "../SettingsViewController.h"

NSString * const PackageQueueDidChangeNotification = @"PackageQueueDidChangeNotification";

@interface Package (PackageQueueInternal)
- (void)applyCommittedState:(BOOL)installed;
@end

@interface PackageQueue ()
@property (nonatomic, strong) NSMutableArray<Package *> *installs;
@property (nonatomic, strong) NSMutableArray<Package *> *uninstalls;
@end

@implementation PackageQueue

+ (instancetype)sharedQueue
{
    static PackageQueue *q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ q = [[PackageQueue alloc] init]; });
    return q;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _installs   = [NSMutableArray array];
        _uninstalls = [NSMutableArray array];
    }
    return self;
}

- (NSArray<Package *> *)queuedInstalls   { return [self.installs copy]; }
- (NSArray<Package *> *)queuedUninstalls { return [self.uninstalls copy]; }
- (NSInteger)pendingCount                { return (NSInteger)(self.installs.count + self.uninstalls.count); }

- (PackageQueueIntent)intentForPackage:(Package *)package
{
    if ([self packageInArray:self.installs matching:package])   return PackageQueueIntentInstall;
    if ([self packageInArray:self.uninstalls matching:package]) return PackageQueueIntentUninstall;
    return PackageQueueIntentNone;
}

- (Package *)packageInArray:(NSArray<Package *> *)array matching:(Package *)package
{
    for (Package *p in array) {
        if ([p.identifier isEqualToString:package.identifier]) return p;
    }
    return nil;
}

- (void)toggleForPackage:(Package *)package
{
    PackageQueueIntent current = [self intentForPackage:package];
    if (current != PackageQueueIntentNone) {
        [self removePackage:package];
        return;
    }
    if (package.isInstalled) {
        [self.uninstalls addObject:package];
    } else {
        [self.installs addObject:package];
    }
    [self notifyChange];
}

- (void)removePackage:(Package *)package
{
    Package *match = [self packageInArray:self.installs matching:package];
    if (match) [self.installs removeObject:match];
    match = [self packageInArray:self.uninstalls matching:package];
    if (match) [self.uninstalls removeObject:match];
    [self notifyChange];
}

- (void)clear
{
    if (self.installs.count == 0 && self.uninstalls.count == 0) return;
    [self.installs removeAllObjects];
    [self.uninstalls removeAllObjects];
    [self notifyChange];
}

- (void)commit
{
    NSArray<Package *> *toInstall   = [self.installs copy];
    NSArray<Package *> *toUninstall = [self.uninstalls copy];

    for (Package *pkg in toInstall)   [pkg applyCommittedState:YES];
    for (Package *pkg in toUninstall) [pkg applyCommittedState:NO];

    [self.installs removeAllObjects];
    [self.uninstalls removeAllObjects];
    [self notifyChange];

    settings_run_actions();
}

- (void)notifyChange
{
    [[NSNotificationCenter defaultCenter] postNotificationName:PackageQueueDidChangeNotification
                                                        object:self];
}

@end
