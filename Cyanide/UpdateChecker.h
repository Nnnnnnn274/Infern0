//
//  UpdateChecker.h
//  Cyanide
//
//  Sparkle-style update prompt: on launch, queries the GitHub releases API for
//  the latest tag and offers View Release / Remind Me Later / Skip This Version
//  if a newer version is available.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UpdateChecker : NSObject

+ (instancetype)shared;

// Async check; presents an alert from `presenter` if a newer release exists
// and the user hasn't skipped that version or snoozed within the last 24h.
// No-op if already checked this app process lifetime, or on network failure.
- (void)checkForUpdatesIfNeededFrom:(UIViewController *)presenter;

@end

NS_ASSUME_NONNULL_END
