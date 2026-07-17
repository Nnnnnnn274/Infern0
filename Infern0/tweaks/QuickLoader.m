//
//  QuickLoader.m
//

#import <JavaScriptCore/JavaScriptCore.h>

#import "QuickLoader.h"
#import "RepoTweaks.h"
#import "remote_objc.h"
#import "../TaskRop/RemoteCall.h"
#import "../utils/file.h"
#import "../SettingsViewController.h"
#import <stdio.h>
#import <unistd.h>
#import <string.h>
#import <pthread.h>
#import <math.h>
#import <Foundation/Foundation.h>
#import "../LogTextView.h"


extern uint64_t r_nsstr_retained(const char *str);

static NSString * const kQuickLoaderHideHomeBarMaterialKitAssets =
    @"/System/Library/PrivateFrameworks/MaterialKit.framework/Assets.car";

// ==========================================
// 1: 64-Bit Pointer Translation Helpers
// ==========================================
static uint64_t js_to_uint64(JSValue *val) {
    if ([val isString]) {
        return strtoull([[val toString] UTF8String], NULL, 16);
    }
    return (uint64_t)[val toDouble];
}

static NSString* uint64_to_js(uint64_t val) {
    return [NSString stringWithFormat:@"0x%llx", val];
}

static NSMutableDictionary *quickloader_string_values_dictionary(id raw) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    if (![raw isKindOfClass:NSDictionary.class]) return out;
    [(NSDictionary *)raw enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        (void)stop;
        if ([key isKindOfClass:NSString.class] && [obj isKindOfClass:NSString.class]) {
            out[key] = obj;
        }
    }];
    return out;
}

static NSString *quickloader_pref_string(NSDictionary *prefs, NSString *key) {
    if (![prefs isKindOfClass:NSDictionary.class] || ![key isKindOfClass:NSString.class]) return @"";
    id value = prefs[key];
    return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSString *quickloader_string_or_empty(id value) {
    return [value isKindOfClass:NSString.class] ? (NSString *)value : @"";
}

static BOOL quickloader_valid_identifier(NSString *name) {
    if (![name isKindOfClass:NSString.class] || name.length == 0) return NO;
    unichar first = [name characterAtIndex:0];
    if (![[NSCharacterSet letterCharacterSet] characterIsMember:first] && first != '_' && first != '$') return NO;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_$"];
    return [name rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound;
}

static NSString *quickloader_js_string_literal(NSString *value) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[value ?: @""]
                                                   options:0
                                                     error:nil];
    NSString *arrayLiteral = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    if (arrayLiteral.length >= 2 && [arrayLiteral hasPrefix:@"["] && [arrayLiteral hasSuffix:@"]"]) {
        return [arrayLiteral substringWithRange:NSMakeRange(1, arrayLiteral.length - 2)];
    }
    return @"\"\"";
}

static NSString *quickloader_js_number_literal(NSString *value) {
    double number = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0.0;
    if (!isfinite(number)) number = 0.0;
    return [NSString stringWithFormat:@"%.12g", number];
}

static NSString * const kQuickLoaderSourceRepoURLKey = @"QuickLoaderSourceRepoURL";
static NSString * const kQuickLoaderSourceTweakIDKey = @"QuickLoaderSourceTweakID";

static NSString *quickloader_compiled_script_for_raw_script(NSString *rawScript,
                                                            NSMutableDictionary *values) {
    if (![rawScript isKindOfClass:NSString.class] || rawScript.length == 0) return nil;
    if (![values isKindOfClass:NSMutableDictionary.class]) values = [NSMutableDictionary dictionary];

    NSMutableString *finalScript = [NSMutableString stringWithString:@"// Variables injected by Infern0\n"];
    NSArray *lines = [rawScript componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        if (![line containsString:@"@param:"]) continue;
        NSArray *parts = [line componentsSeparatedByString:@"|"];
        if (parts.count < 4) continue;

        NSArray *typeParts = [parts[0] componentsSeparatedByString:@"@param:"];
        if (typeParts.count < 2) continue;
        NSString *type = [quickloader_string_or_empty(typeParts[1]) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSString *varName = [quickloader_string_or_empty(parts[1]) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSString *defValue = [quickloader_string_or_empty(parts[3]) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (!quickloader_valid_identifier(varName)) continue;

        NSString *currentValue = quickloader_string_or_empty(values[varName]);
        if (currentValue.length == 0) {
            currentValue = defValue;
            values[varName] = defValue ?: @"";
        }

        if ([type isEqualToString:@"switch"]) {
            [finalScript appendFormat:@"var %@ = %@;\n", varName, [currentValue boolValue] ? @"true" : @"false"];
        } else if ([type isEqualToString:@"text"] || [type isEqualToString:@"color"]) {
            [finalScript appendFormat:@"var %@ = %@;\n", varName, quickloader_js_string_literal(currentValue)];
        } else if ([type isEqualToString:@"slider"] || [type isEqualToString:@"number"]) {
            [finalScript appendFormat:@"var %@ = %@;\n", varName, quickloader_js_number_literal(currentValue)];
        }
    }

    [finalScript appendString:@"// --------------------------------------\n\n"];
    [finalScript appendString:rawScript];
    return finalScript;
}

static bool quickloader_save_repo_tweak_internal(NSString *repoURL,
                                                 NSString *tweakID,
                                                 NSString *displayName,
                                                 NSString *rawScript,
                                                 NSDictionary *values,
                                                 BOOL logQueued) {
    NSString *safeRepo = quickloader_string_or_empty(repoURL);
    NSString *safeID = quickloader_string_or_empty(tweakID);
    NSString *safeName = quickloader_string_or_empty(displayName);
    if (safeRepo.length == 0 || safeID.length == 0 || rawScript.length == 0) return false;

    NSMutableDictionary *mutableValues = quickloader_string_values_dictionary(values);
    NSString *compiled = quickloader_compiled_script_for_raw_script(rawScript, mutableValues);
    if (compiled.length == 0) return false;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d removeObjectForKey:@"QuickLoaderSourceScriptNames"];
    [d setObject:safeName.length ? safeName : safeID forKey:@"QuickLoaderSourceScriptName"];
    [d setObject:rawScript forKey:@"QuickLoaderSourceRawJS"];
    [d setObject:mutableValues forKey:@"QuickLoaderSourceValues"];
    [d setObject:safeRepo forKey:kQuickLoaderSourceRepoURLKey];
    [d setObject:safeID forKey:kQuickLoaderSourceTweakIDKey];
    [d setObject:compiled forKey:@"QuickLoaderSavedJS"];
    [d setObject:mutableValues forKey:repotweaks_values_defaults_key(safeRepo, safeID)];
    [d synchronize];
    if (logQueued) {
        log_user("[QuickLoader] Queued repo package: %s\n", (safeName.length ? safeName : safeID).UTF8String);
    }
    return true;
}

bool quickloader_save_repo_tweak(NSString *repoURL,
                                 NSString *tweakID,
                                 NSString *displayName,
                                 NSString *rawScript,
                                 NSDictionary *values) {
    return quickloader_save_repo_tweak_internal(repoURL,
                                                tweakID,
                                                displayName,
                                                rawScript,
                                                values,
                                                YES);
}

bool quickloader_is_repo_tweak_installed(NSString *repoURL, NSString *tweakID) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *safeRepo = quickloader_string_or_empty(repoURL);
    NSString *safeID = quickloader_string_or_empty(tweakID);
    if (safeRepo.length == 0 || safeID.length == 0) return false;
    return [[d stringForKey:kQuickLoaderSourceRepoURLKey] isEqualToString:safeRepo] &&
           [[d stringForKey:kQuickLoaderSourceTweakIDKey] isEqualToString:safeID] &&
           [[d stringForKey:@"QuickLoaderSavedJS"] length] > 0;
}

void quickloader_clear_repo_tweak_if_matches(NSString *repoURL, NSString *tweakID) {
    if (!quickloader_is_repo_tweak_installed(repoURL, tweakID)) return;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d removeObjectForKey:@"QuickLoaderSourceScriptName"];
    [d removeObjectForKey:@"QuickLoaderSourceScriptNames"];
    [d removeObjectForKey:@"QuickLoaderSourceRawJS"];
    [d removeObjectForKey:@"QuickLoaderSourceValues"];
    [d removeObjectForKey:kQuickLoaderSourceRepoURLKey];
    [d removeObjectForKey:kQuickLoaderSourceTweakIDKey];
    [d removeObjectForKey:@"QuickLoaderSavedJS"];
    [d synchronize];
}

bool quickloader_is_driven_by_repo_tweak(void) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *repoURL = quickloader_string_or_empty([d stringForKey:kQuickLoaderSourceRepoURLKey]);
    return repoURL.length > 0;
}

bool quickloader_refresh_active_repo_tweak(void) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *repoURL = quickloader_string_or_empty([d stringForKey:kQuickLoaderSourceRepoURLKey]);
    NSString *tweakID = quickloader_string_or_empty([d stringForKey:kQuickLoaderSourceTweakIDKey]);
    if (repoURL.length == 0 || tweakID.length == 0) return false;

    NSString *rawScript = [d stringForKey:repotweaks_script_defaults_key(repoURL, tweakID)];
    if (rawScript.length == 0) {
        log_user("[QuickLoader] Selected repo package script is missing; refresh its source first.\n");
        return false;
    }

    NSDictionary *values = [d dictionaryForKey:repotweaks_values_defaults_key(repoURL, tweakID)] ?: @{};
    NSString *displayName = [d stringForKey:@"QuickLoaderSourceScriptName"];
    return quickloader_save_repo_tweak_internal(repoURL,
                                                tweakID,
                                                displayName.length ? displayName : tweakID,
                                                rawScript,
                                                values,
                                                NO);
}


// ==========================================
// Global variables for js daemon and kill switch
// ==========================================
static JSContext *g_quickloader_context = nil;
static NSMutableDictionary *g_quickloader_timers = nil;
static NSMutableSet<NSNumber *> *g_quickloader_allocated_objects = nil;
static NSMutableSet<NSNumber *> *g_quickloader_owned_views = nil;
static int g_quickloader_timer_id = 0;

static int g_quickloader_shutting_down = 0;
static char g_quickloader_queue_key;
static pthread_mutex_t g_quickloader_queue_lock = PTHREAD_MUTEX_INITIALIZER;
static dispatch_queue_t g_quickloader_queue = nil;
static uint64_t g_quickloader_generation = 1;

static BOOL quickloader_selector_requires_main(NSString *selector) {
    if (![selector isKindOfClass:NSString.class]) return NO;
    static NSArray<NSString *> *exact;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        exact = @[@"addSubview:", @"bringSubviewToFront:", @"sendSubviewToBack:",
                  @"addSublayer:", @"removeFromSuperlayer", @"removeAllAnimations",
                  @"removeFromSuperview", @"setFrame:", @"setBounds:", @"setCenter:",
                  @"setTransform:", @"setAlpha:", @"setHidden:", @"setText:",
                  @"setTextColor:", @"setBackgroundColor:", @"setImage:",
                  @"setNeedsLayout", @"layoutIfNeeded", @"setNeedsDisplay"];
    });
    if ([exact containsObject:selector] || [selector isEqualToString:@"alloc"] ||
        [selector isEqualToString:@"new"] || [selector hasPrefix:@"init"]) return YES;
    return [selector hasPrefix:@"set"] || [selector hasPrefix:@"insertSubview:"] ||
           [selector hasPrefix:@"insertSublayer:"] || [selector hasPrefix:@"addAnimation:"] ||
           [selector hasPrefix:@"removeAnimation"];
}

static void quickloader_track_remote_call(uint64_t target, NSString *selector, uint64_t firstArg, uint64_t result) {
    if (!g_quickloader_allocated_objects) g_quickloader_allocated_objects = [NSMutableSet set];
    if (!g_quickloader_owned_views) g_quickloader_owned_views = [NSMutableSet set];
    if (([selector isEqualToString:@"alloc"] || [selector isEqualToString:@"new"]) && result) {
        [g_quickloader_allocated_objects addObject:@(result)];
    } else if ([selector hasPrefix:@"init"] &&
               [g_quickloader_allocated_objects containsObject:@(target)] && result) {
        [g_quickloader_allocated_objects addObject:@(result)];
    }
    if (([selector isEqualToString:@"addSubview:"] || [selector hasPrefix:@"insertSubview:"]) &&
        firstArg && [g_quickloader_allocated_objects containsObject:@(firstArg)]) {
        [g_quickloader_owned_views addObject:@(firstArg)];
    } else if ([selector isEqualToString:@"removeFromSuperview"] && target) {
        [g_quickloader_owned_views removeObject:@(target)];
    }
}

static void quickloader_remove_owned_views_locked(const char *reason) {
    NSArray<NSNumber *> *views = g_quickloader_owned_views.allObjects;
    for (NSNumber *pointer in [views reverseObjectEnumerator]) {
        uint64_t view = pointer.unsignedLongLongValue;
        if (view) r_msg2_main(view, "removeFromSuperview", 0, 0, 0, 0);
    }
    if (views.count > 0) {
        log_user("[QuickLoader][OVERLAY] Removed %lu stale script-owned view%s before %s.\n",
                 (unsigned long)views.count, views.count == 1 ? "" : "s", reason ?: "cleanup");
    }
    [g_quickloader_owned_views removeAllObjects];
    [g_quickloader_allocated_objects removeAllObjects];
}

static dispatch_queue_t quickloader_create_js_queue_locked(void) {
    NSString *label = [NSString stringWithFormat:@"com.zeroxjf.cyanide.quickloader.js.%llu",
                       (unsigned long long)g_quickloader_generation];
    dispatch_queue_t q = dispatch_queue_create(label.UTF8String, DISPATCH_QUEUE_SERIAL);
    dispatch_queue_set_specific(q, &g_quickloader_queue_key, &g_quickloader_queue_key, NULL);
    return q;
}

static dispatch_queue_t quickloader_js_queue(void) {
    pthread_mutex_lock(&g_quickloader_queue_lock);
    if (!g_quickloader_queue) {
        g_quickloader_queue = quickloader_create_js_queue_locked();
    }
    dispatch_queue_t q = g_quickloader_queue;
    pthread_mutex_unlock(&g_quickloader_queue_lock);
    return q;
}

static uint64_t quickloader_current_generation(void) {
    pthread_mutex_lock(&g_quickloader_queue_lock);
    uint64_t generation = g_quickloader_generation;
    pthread_mutex_unlock(&g_quickloader_queue_lock);
    return generation;
}

static void quickloader_set_shutting_down(BOOL shuttingDown) {
    pthread_mutex_lock(&g_quickloader_queue_lock);
    g_quickloader_shutting_down = shuttingDown ? 1 : 0;
    pthread_mutex_unlock(&g_quickloader_queue_lock);
}

static uint64_t quickloader_begin_run_generation(void) {
    pthread_mutex_lock(&g_quickloader_queue_lock);
    g_quickloader_generation++;
    if (g_quickloader_generation == 0) g_quickloader_generation = 1;
    g_quickloader_shutting_down = 0;
    if (!g_quickloader_queue) {
        g_quickloader_queue = quickloader_create_js_queue_locked();
    }
    uint64_t generation = g_quickloader_generation;
    pthread_mutex_unlock(&g_quickloader_queue_lock);
    return generation;
}

static BOOL quickloader_generation_is_current(uint64_t generation) {
    pthread_mutex_lock(&g_quickloader_queue_lock);
    BOOL current = (generation == g_quickloader_generation);
    pthread_mutex_unlock(&g_quickloader_queue_lock);
    return current;
}

static BOOL quickloader_generation_is_active(uint64_t generation) {
    pthread_mutex_lock(&g_quickloader_queue_lock);
    BOOL active = !g_quickloader_shutting_down && generation == g_quickloader_generation;
    pthread_mutex_unlock(&g_quickloader_queue_lock);
    return active;
}

static void quickloader_abandon_js_queue_after_timeout(const char *reason, BOOL shuttingDown) {
    pthread_mutex_lock(&g_quickloader_queue_lock);
    g_quickloader_generation++;
    if (g_quickloader_generation == 0) g_quickloader_generation = 1;
    g_quickloader_shutting_down = shuttingDown ? 1 : 0;
    g_quickloader_queue = quickloader_create_js_queue_locked();
    g_quickloader_context = nil;
    g_quickloader_timers = nil;
    pthread_mutex_unlock(&g_quickloader_queue_lock);
    log_user("[QuickLoader] Abandoned wedged JS queue after %s; future runs will use a fresh queue.\n",
             reason ? reason : "timeout");
}

static bool quickloader_perform_sync_timeout(dispatch_block_t block, int64_t timeoutNsec) {
    if (!block) return true;
    if (dispatch_get_specific(&g_quickloader_queue_key)) {
        block();
        return true;
    }

    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    dispatch_async(quickloader_js_queue(), ^{
        block();
        dispatch_semaphore_signal(sema);
    });
    dispatch_time_t deadline = timeoutNsec < 0
        ? DISPATCH_TIME_FOREVER
        : dispatch_time(DISPATCH_TIME_NOW, timeoutNsec);
    return dispatch_semaphore_wait(sema, deadline) == 0;
}


// ==========================================
// Session init with auto-load default settings
// ==========================================
bool quickloader_apply_in_session() {
    quickloader_set_shutting_down(NO);

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *activeRepoURL = quickloader_string_or_empty([d stringForKey:kQuickLoaderSourceRepoURLKey]);
    NSString *activeTweakID = quickloader_string_or_empty([d stringForKey:kQuickLoaderSourceTweakIDKey]);
    NSString *activeName = quickloader_string_or_empty([d stringForKey:@"QuickLoaderSourceScriptName"]);
    BOOL hasRepoPackage = activeRepoURL.length > 0 && activeTweakID.length > 0;

    if (hasRepoPackage) {
        log_user("[QuickLoader] Active session detected. Checking selected repo package: %s...\n",
                 (activeName.length ? activeName : activeTweakID).UTF8String);
        if (!quickloader_refresh_active_repo_tweak()) {
            return false;
        }
    } else {
        NSArray *localNames = [d arrayForKey:@"QuickLoaderSourceScriptNames"];
        log_user("[QuickLoader] Active session detected. Checking %lu local JS module%s...\n",
                 (unsigned long)MAX(localNames.count, (NSUInteger)1), localNames.count == 1 ? "" : "s");
    }

    NSString *savedJS = [d stringForKey:@"QuickLoaderSavedJS"];

    if (savedJS && savedJS.length > 0) {

        // ===============================================================
        // auto-loading default settings
        // ===============================================================
        NSMutableDictionary *savedValues = quickloader_string_values_dictionary([d dictionaryForKey:@"QuickLoaderSourceValues"]);
        BOOL didUpdateDefaults = NO;

        NSArray *lines = [savedJS componentsSeparatedByString:@"\n"];
        for (NSString *line in lines) {
            if ([line containsString:@"@param:"]) {
                NSArray *parts = [line componentsSeparatedByString:@"|"];
                if (parts.count >= 4) {
                    //extracting variable name and default
                    NSString *varName = [parts[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    NSString *defValue = [parts[3] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    if (!quickloader_valid_identifier(varName)) {
                        log_user("[QuickLoader] Skipping invalid parameter name: %s\n", varName.UTF8String);
                        continue;
                    }

                    //if new, use .js default values
                    if (!savedValues[varName]) {
                        savedValues[varName] = defValue;
                        didUpdateDefaults = YES;
                    }
                }
            }
        }

        //if defaults found, saves them in memory
        if (didUpdateDefaults) {
            [d setObject:savedValues forKey:@"QuickLoaderSourceValues"];
            [d synchronize];
        }
        // ===============================================================

        if (hasRepoPackage) {
            log_user("[QuickLoader] Executing repo package: %s\n",
                     (activeName.length ? activeName : activeTweakID).UTF8String);
        } else {
            NSArray *localNames = [d arrayForKey:@"QuickLoaderSourceScriptNames"];
            log_user("[QuickLoader] Executing %lu local JS module%s in an isolated wrapper set...\n",
                     (unsigned long)MAX(localNames.count, (NSUInteger)1), localNames.count == 1 ? "" : "s");
        }
        return quickloader_run_js_string(savedJS);
    } else {
        log_user("[QuickLoader] No JS file loaded.\n");
    }

    return false;
}

// ==========================================
// Javascript interpreter engine
// ==========================================
bool quickloader_run_js_string(NSString *jsCode) {
    if (!jsCode || jsCode.length == 0) return false;

    __block bool ok = true;
    uint64_t runGeneration = quickloader_begin_run_generation();
    bool completed = quickloader_perform_sync_timeout(^{
        if (!quickloader_generation_is_current(runGeneration)) return;
        log_user("[JS Engine] Initializing long-living environment...\n");
        quickloader_remove_owned_views_locked("rerun");

        if (g_quickloader_timers == nil) {
            g_quickloader_timers = [[NSMutableDictionary alloc] init];
        } else {
            for (dispatch_source_t t in g_quickloader_timers.allValues) {
                if (dispatch_testcancel(t) == 0) {
                    dispatch_source_cancel(t);
                }
            }
            [g_quickloader_timers removeAllObjects];
        }
        NSMutableDictionary *timers = g_quickloader_timers;

        g_quickloader_context = [[JSContext alloc] init];
        JSContext *context = g_quickloader_context;
        __block BOOL scriptFaulted = NO;

        context.exceptionHandler = ^(JSContext *ctx, JSValue *exception) {
            if (scriptFaulted) return;
            scriptFaulted = YES;
            log_user("[JS ERROR] %s\n", [[exception toString] UTF8String]);
            log_user("[QuickLoader][SAFETY] Script timers stopped after the first unhandled exception. Fix the script and Run again.\n");
            for (dispatch_source_t timer in timers.allValues) {
                if (dispatch_testcancel(timer) == 0) dispatch_source_cancel(timer);
            }
            [timers removeAllObjects];
        };

        // Timers target the same serial queue as the JSContext. JavaScriptCore
        // contexts are not safe to touch concurrently, and SpringBoard
        // RemoteCall state is single-session by design.
        context[@"setInterval"] = ^JSValue*(JSValue *func, JSValue *delay) {
            if (!quickloader_generation_is_active(runGeneration)) return [JSValue valueWithInt32:0 inContext:[JSContext currentContext]];
            if (timers.count >= 32) {
                log_user("[QuickLoader][SAFETY] Refused setInterval: 32 active timers is the limit.\n");
                return [JSValue valueWithInt32:0 inContext:[JSContext currentContext]];
            }
            int tId = ++g_quickloader_timer_id;
            uint64_t ms = [delay toUInt32];
            // Remote UIKit calls cannot safely sustain browser-style 60 Hz JS
            // loops. A 50 ms floor prevents timer pile-ups and SpringBoard
            // watchdog resprings while remaining responsive for overlays.
            if (ms < 50) ms = 50;

            dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, quickloader_js_queue());
            dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, ms * NSEC_PER_MSEC), ms * NSEC_PER_MSEC, (ms / 10) * NSEC_PER_MSEC);
            dispatch_source_set_event_handler(timer, ^{
                if (quickloader_generation_is_active(runGeneration)) {
                    [func callWithArguments:@[]];
                }
            });

            timers[@(tId)] = timer;
            dispatch_resume(timer);
            return [JSValue valueWithInt32:tId inContext:[JSContext currentContext]];
        };

        context[@"clearInterval"] = ^(JSValue *timerId) {
            if (!quickloader_generation_is_active(runGeneration)) return;
            int tId = [timerId toInt32];
            dispatch_source_t timer = timers[@(tId)];
            if (timer) {
                dispatch_source_cancel(timer);
                [timers removeObjectForKey:@(tId)];
            }
        };

        context[@"setTimeout"] = ^JSValue*(JSValue *func, JSValue *delay) {
            if (!quickloader_generation_is_active(runGeneration)) return [JSValue valueWithInt32:0 inContext:[JSContext currentContext]];
            if (timers.count >= 32) {
                log_user("[QuickLoader][SAFETY] Refused setTimeout: 32 active timers is the limit.\n");
                return [JSValue valueWithInt32:0 inContext:[JSContext currentContext]];
            }
            int tId = ++g_quickloader_timer_id;
            uint64_t ms = [delay toUInt32];
            if (ms < 16) ms = 16;

            dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, quickloader_js_queue());
            dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, ms * NSEC_PER_MSEC), DISPATCH_TIME_FOREVER, 0);
            dispatch_source_set_event_handler(timer, ^{
                if (quickloader_generation_is_active(runGeneration)) {
                    [func callWithArguments:@[]];
                }
                dispatch_source_cancel(timer);
                [timers removeObjectForKey:@(tId)];
            });

            timers[@(tId)] = timer;
            dispatch_resume(timer);
            return [JSValue valueWithInt32:tId inContext:[JSContext currentContext]];
        };

        context[@"clearTimeout"] = ^(JSValue *timerId) {
            if (!quickloader_generation_is_active(runGeneration)) return;
            int tId = [timerId toInt32];
            dispatch_source_t timer = timers[@(tId)];
            if (timer) {
                dispatch_source_cancel(timer);
                [timers removeObjectForKey:@(tId)];
            }
        };

        //Bridge ipc core (safe with kill-switch)
        context[@"log"] = ^(NSString *msg) {
            if (!quickloader_generation_is_active(runGeneration)) return;
            log_user("[JS] %s\n", [msg UTF8String]);
        };

        context[@"dz_zero_system_file_page"] = ^NSNumber*(NSString *path, JSValue *offsetValue) {
            if (!quickloader_generation_is_active(runGeneration)) return @(NO);
            if (![path isKindOfClass:NSString.class] || path.length == 0) {
                log_user("[QuickLoader] dz_zero_system_file_page missing path.\n");
                return @(NO);
            }
            uint64_t offset = offsetValue ? js_to_uint64(offsetValue) : 0;
            log_user("[QuickLoader] Stable page-zero request: %s offset=%llu\n",
                     path.UTF8String,
                     (unsigned long long)offset);
            int rc = zero_system_file_page(path.UTF8String, (off_t)offset);
            if (rc == 0 &&
                offset == 0 &&
                [path isEqualToString:kQuickLoaderHideHomeBarMaterialKitAssets]) {
                settings_note_hide_home_bar_respring_pending();
            }
            return @(rc == 0);
        };

        context[@"r_pref_num"] = ^NSNumber*(NSString *key) {
            if (!quickloader_generation_is_active(runGeneration)) return @(0);
            NSDictionary *prefs = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"QuickLoaderSourceValues"];
            return @([quickloader_pref_string(prefs, key) doubleValue]);
        };

        context[@"r_pref_str"] = ^NSString*(NSString *key) {
            if (!quickloader_generation_is_active(runGeneration)) return @"";
            NSDictionary *prefs = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"QuickLoaderSourceValues"];
            return quickloader_pref_string(prefs, key);
        };

        context[@"r_pref_bool"] = ^NSNumber*(NSString *key) {
            if (!quickloader_generation_is_active(runGeneration)) return @(0);
            NSDictionary *prefs = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"QuickLoaderSourceValues"];
            return @([quickloader_pref_string(prefs, key) boolValue]);
        };

        context[@"r_class"] = ^(NSString *className) {
            if (!quickloader_generation_is_active(runGeneration)) return uint64_to_js(0);
            uint64_t cls = r_class([className UTF8String]);
            return uint64_to_js(cls);
        };

        context[@"r_responds"] = ^() {
            if (!quickloader_generation_is_active(runGeneration)) return @(0);
            NSArray *args = [JSContext currentArguments];
            if (args.count < 2) return @(0);

            uint64_t target = js_to_uint64(args[0]);
            NSString *selector = [args[1] toString];
            return @(r_responds(target, [selector UTF8String]));
        };

        context[@"r_sel"] = ^NSString*(NSString *selName) {
            if (!quickloader_generation_is_active(runGeneration)) return uint64_to_js(0);
            if (![selName isKindOfClass:NSString.class]) return uint64_to_js(0);
            uint64_t selPtr = r_sel([selName UTF8String]);
            return uint64_to_js(selPtr);
        };

        context[@"r_msg2"] = ^() {
            if (!quickloader_generation_is_active(runGeneration)) return uint64_to_js(0);
            NSArray *args = [JSContext currentArguments];
            if (args.count < 2) return uint64_to_js(0);
            uint64_t target = js_to_uint64(args[0]);
            NSString *selector = [args[1] toString];

            uint64_t a1 = args.count > 2 ? js_to_uint64(args[2]) : 0;
            uint64_t a2 = args.count > 3 ? js_to_uint64(args[3]) : 0;
            uint64_t a3 = args.count > 4 ? js_to_uint64(args[4]) : 0;
            uint64_t a4 = args.count > 5 ? js_to_uint64(args[5]) : 0;

            BOOL onMain = quickloader_selector_requires_main(selector);
            uint64_t res = onMain
                ? r_msg2_main(target, [selector UTF8String], a1, a2, a3, a4)
                : r_msg2(target, [selector UTF8String], a1, a2, a3, a4);
            quickloader_track_remote_call(target, selector, a1, res);
            return uint64_to_js(res);
        };

        context[@"r_msg2_main"] = ^() {
            if (!quickloader_generation_is_active(runGeneration)) return uint64_to_js(0);
            NSArray *args = [JSContext currentArguments];
            if (args.count < 2) return uint64_to_js(0);
            uint64_t target = js_to_uint64(args[0]);
            NSString *selector = [args[1] toString];

            uint64_t a1 = args.count > 2 ? js_to_uint64(args[2]) : 0;
            uint64_t a2 = args.count > 3 ? js_to_uint64(args[3]) : 0;
            uint64_t a3 = args.count > 4 ? js_to_uint64(args[4]) : 0;
            uint64_t a4 = args.count > 5 ? js_to_uint64(args[5]) : 0;

            uint64_t res = r_msg2_main(target, [selector UTF8String], a1, a2, a3, a4);
            quickloader_track_remote_call(target, selector, a1, res);
            return uint64_to_js(res);
        };

        context[@"r_overlay_claim"] = ^NSNumber*(JSValue *viewValue) {
            uint64_t view = js_to_uint64(viewValue);
            if (!view || !quickloader_generation_is_active(runGeneration)) return @(NO);
            if (!g_quickloader_owned_views) g_quickloader_owned_views = [NSMutableSet set];
            [g_quickloader_owned_views addObject:@(view)];
            log_user("[QuickLoader][OVERLAY] Claimed remote view 0x%llx.\n", (unsigned long long)view);
            return @(YES);
        };

        context[@"r_overlay_release"] = ^NSNumber*(JSValue *viewValue) {
            uint64_t view = js_to_uint64(viewValue);
            if (!view || !quickloader_generation_is_active(runGeneration)) return @(NO);
            r_msg2_main(view, "removeFromSuperview", 0, 0, 0, 0);
            [g_quickloader_owned_views removeObject:@(view)];
            log_user("[QuickLoader][OVERLAY] Released remote view 0x%llx.\n", (unsigned long long)view);
            return @(YES);
        };

        context[@"r_nsstr"] = ^NSString*(NSString *str) {
            if (!quickloader_generation_is_active(runGeneration)) return uint64_to_js(0);
            if (!str) return uint64_to_js(0);
            uint64_t ptr = r_nsstr_retained([str UTF8String]);
            return uint64_to_js(ptr);
        };

        log_user("[JS Engine] Executing user script...\n");
        [context evaluateScript:jsCode];
        if (context.exception) {
            ok = false;
        } else {
            log_user("[JS Engine] Execution complete.\n");
        }
    }, 15 * NSEC_PER_SEC);

    if (!completed) {
        ok = false;
        quickloader_abandon_js_queue_after_timeout("run timeout", NO);
    }

    return ok;
}

// ==========================================
// Teardown engine
// ==========================================
bool quickloader_stop_in_session(void) {
    //Order timers to stop
    quickloader_set_shutting_down(YES);
    uint64_t stopGeneration = quickloader_current_generation();

    bool stopped = quickloader_perform_sync_timeout(^{
        if (!quickloader_generation_is_current(stopGeneration)) return;
        log_user("[QuickLoader] Clean Up: Green light, safely stopping JS timer...\n");

        if (g_quickloader_timers) {
            for (id key in [g_quickloader_timers allKeys]) {
                dispatch_source_t timer = (dispatch_source_t)g_quickloader_timers[key];
                if (dispatch_testcancel(timer) == 0) {
                    dispatch_source_cancel(timer);
                }
            }
            [g_quickloader_timers removeAllObjects];
        }

        quickloader_remove_owned_views_locked("cleanup");

        g_quickloader_context = nil;
    }, 2 * NSEC_PER_SEC);

    if (!stopped) {
        log_user("[QuickLoader] Clean Up timed out; the script may be stuck in a long-running loop.\n");
        quickloader_abandon_js_queue_after_timeout("cleanup timeout", YES);
    }

    return stopped;
}
