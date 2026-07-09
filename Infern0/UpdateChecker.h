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
// Throttled by two gates (either firing triggers a check):
//   1. A per-process flag — guarantees one check per cold launch.
//   2. A persisted "last checked" timestamp with a 24-hour window — re-arms
//      within a long-resident process after the window elapses.
// Both gates are only burned on a *completed* HTTP response, so network
// failures don't squelch the next attempt.
- (void)checkForUpdatesIfNeededFrom:(UIViewController *)presenter;

// User-initiated check. Ignores the per-launch dedupe, the skipped-version
// flag, and the snooze window. Always shows feedback: "Up to Date",
// "Update Available", or "Check Failed".
- (void)checkForUpdatesManuallyFrom:(UIViewController *)presenter;

@end

NS_ASSUME_NONNULL_END
