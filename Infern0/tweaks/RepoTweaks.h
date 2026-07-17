//
//  RepoTweaks.h
//

#ifndef RepoTweaks_h
#define RepoTweaks_h

#import <stdbool.h>
#import <Foundation/Foundation.h>

// Runs all enabled tweaks during the RUN 4/4 sequence
bool repotweaks_apply_in_session(void);

// Fetches the JSON from the given URL and caches it
void repotweaks_refresh_repo(NSString *repoURL, void (^completion)(BOOL success, NSString *message));
void repotweaks_seed_default_repos(void);
BOOL repotweaks_is_builtin_repo(NSString *repoURL);
NSString *repotweaks_builtin_repo_display_name(NSString *repoURL);

NSString *repotweaks_storage_key(NSString *repoURL, NSString *tweakId);
NSString *repotweaks_enabled_defaults_key(NSString *repoURL, NSString *tweakId);
NSString *repotweaks_script_defaults_key(NSString *repoURL, NSString *tweakId);
NSString *repotweaks_values_defaults_key(NSString *repoURL, NSString *tweakId);

// Downloads the raw .js code for a specific repository tweak
void repotweaks_download_script(NSString *repoURL, NSString *tweakId, NSString *scriptURL, void (^completion)(BOOL success));
BOOL repotweaks_download_script_sync(NSString *repoURL,
                                     NSString *tweakId,
                                     NSString *scriptURL,
                                     NSTimeInterval timeout,
                                     NSString **message);
void repotweaks_cancel_tweak(NSString *repoURL, NSString *tweakId);

bool repotweaks_stop_in_session(void);

void repotweaks_refresh_all_sources(void (^completion)(void));
NSUInteger repotweaks_available_update_count(void);
NSString *repotweaks_installed_version_key(NSString *repoURL, NSString *tweakId);
NSTimeInterval repotweaks_seen_timestamp(NSString *repoURL, NSString *tweakId);
NSComparisonResult repotweaks_compare_versions(NSString *a, NSString *b);
NSString *repotweaks_compatibility_note(NSDictionary *tweak);
NSString *repotweaks_unsupported_reason(NSDictionary *tweak);

extern NSString * const RepoTweaksDidRefreshNotification;

#endif /* RepoTweaks_h */
