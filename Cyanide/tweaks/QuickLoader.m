//
//  QuickLoader.m
//

#import <JavaScriptCore/JavaScriptCore.h>

#import "QuickLoader.h"
#import "remote_objc.h"
#import "../TaskRop/RemoteCall.h"
#import <stdio.h>
#import <unistd.h>
#import <string.h>
#import <Foundation/Foundation.h>
#import "../LogTextView.h"


extern uint64_t r_nsstr_retained(const char *str);

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


// ==========================================
// Global variables for js daemon and kill switch
// ==========================================
static JSContext *g_quickloader_context = nil;
static NSMutableDictionary *g_quickloader_timers = nil;
static int g_quickloader_timer_id = 0;

static volatile int g_quickloader_shutting_down = 0;
static NSLock *g_quickloader_ipc_lock = nil;


// ==========================================
// Session init with auto-load default settings
// ==========================================
bool quickloader_apply_in_session() {
    __sync_lock_test_and_set(&g_quickloader_shutting_down, 0);

    log_user("[QuickLoader] Active session detected. Checking for JS Tweak...\n");
    
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *savedJS = [d stringForKey:@"QuickLoaderSavedJS"];
    
    if (savedJS && savedJS.length > 0) {
        
        // ===============================================================
        // auto-loading default settings
        // ===============================================================
        NSMutableDictionary *savedValues = [[d dictionaryForKey:@"QuickLoaderSourceValues"] mutableCopy] ?: [NSMutableDictionary dictionary];
        BOOL didUpdateDefaults = NO;

        NSArray *lines = [savedJS componentsSeparatedByString:@"\n"];
        for (NSString *line in lines) {
            if ([line containsString:@"@param:"]) {
                NSArray *parts = [line componentsSeparatedByString:@"|"];
                if (parts.count >= 4) {
                    //extracting variable name and default
                    NSString *varName = [parts[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    NSString *defValue = [parts[3] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

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
        
        log_user("[QuickLoader] Executing user-provided JS file...\n");
        quickloader_run_js_string(savedJS);
    } else {
        log_user("[QuickLoader] No JS file loaded.\n");
    }
    
    return true; 
}

// ==========================================
// Javascript interpreter engine
// ==========================================
bool quickloader_run_js_string(NSString *jsCode) {
    if (!jsCode || jsCode.length == 0) return false;
    
    log_user("[JS Engine] Initializing long-living environment...\n");
    
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
    
    g_quickloader_context = [[JSContext alloc] init];
    JSContext *context = g_quickloader_context;
    
    context.exceptionHandler = ^(JSContext *ctx, JSValue *exception) {
        log_user("[JS ERROR] %s\n", [[exception toString] UTF8String]);
    };
    
    //asynchronous multithread timers
    context[@"setInterval"] = ^JSValue*(JSValue *func, JSValue *delay) {
        int tId = ++g_quickloader_timer_id;
        uint64_t ms = [delay toUInt32];
        if (ms < 16) ms = 16;
        
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0));
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, ms * NSEC_PER_MSEC), ms * NSEC_PER_MSEC, (ms / 10) * NSEC_PER_MSEC);
        dispatch_source_set_event_handler(timer, ^{
            if (!g_quickloader_shutting_down) {
                [func callWithArguments:@[]];
            }
        });
        
        g_quickloader_timers[@(tId)] = timer;
        dispatch_resume(timer);
        return [JSValue valueWithInt32:tId inContext:[JSContext currentContext]];
    };

    context[@"clearInterval"] = ^(JSValue *timerId) {
        int tId = [timerId toInt32];
        dispatch_source_t timer = g_quickloader_timers[@(tId)];
        if (timer) {
            dispatch_source_cancel(timer);
            [g_quickloader_timers removeObjectForKey:@(tId)];
        }
    };
    
    context[@"setTimeout"] = ^JSValue*(JSValue *func, JSValue *delay) {
        int tId = ++g_quickloader_timer_id;
        uint64_t ms = [delay toUInt32];
        
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0));
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, ms * NSEC_PER_MSEC), DISPATCH_TIME_FOREVER, 0);
        dispatch_source_set_event_handler(timer, ^{
            if (!g_quickloader_shutting_down) {
                [func callWithArguments:@[]];
            }
            dispatch_source_cancel(timer);
            [g_quickloader_timers removeObjectForKey:@(tId)];
        });
        
        g_quickloader_timers[@(tId)] = timer;
        dispatch_resume(timer);
        return [JSValue valueWithInt32:tId inContext:[JSContext currentContext]];
    };

    context[@"clearTimeout"] = ^(JSValue *timerId) {
        int tId = [timerId toInt32];
        dispatch_source_t timer = g_quickloader_timers[@(tId)];
        if (timer) {
            dispatch_source_cancel(timer);
            [g_quickloader_timers removeObjectForKey:@(tId)];
        }
    };
    
    //Bridge ipc core (safe with kill-switch)
    context[@"log"] = ^(NSString *msg) {
        if (g_quickloader_shutting_down) return;
        log_user("[JS] %s\n", [msg UTF8String]);
    };

    context[@"r_pref_num"] = ^NSNumber*(NSString *key) {
        if (g_quickloader_shutting_down) return @(0);
        NSDictionary *prefs = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"QuickLoaderSourceValues"];
        return @([prefs[key] doubleValue]);
    };
    
    context[@"r_pref_str"] = ^NSString*(NSString *key) {
        if (g_quickloader_shutting_down) return @"";
        NSDictionary *prefs = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"QuickLoaderSourceValues"];
        return prefs[key] ?: @"";
    };
    
    context[@"r_pref_bool"] = ^NSNumber*(NSString *key) {
        if (g_quickloader_shutting_down) return @(0);
        NSDictionary *prefs = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"QuickLoaderSourceValues"];
        return @([prefs[key] boolValue]);
    };
    
    context[@"r_class"] = ^(NSString *className) {
        if (g_quickloader_shutting_down) return uint64_to_js(0);
        uint64_t cls = r_class([className UTF8String]);
        return uint64_to_js(cls);
    };
    
    context[@"r_responds"] = ^() {
        if (g_quickloader_shutting_down) return @(0);
        NSArray *args = [JSContext currentArguments];
        if (args.count < 2) return @(0);
        
        uint64_t target = js_to_uint64(args[0]);
        NSString *selector = [args[1] toString];
        return @(r_responds(target, [selector UTF8String]));
    };
    
    context[@"r_sel"] = ^NSString*(NSString *selName) {
        if (g_quickloader_shutting_down) return uint64_to_js(0);
        uint64_t selPtr = (uint64_t)sel_registerName([selName UTF8String]);
        return uint64_to_js(selPtr);
    };

    context[@"r_msg2"] = ^() {
        if (g_quickloader_shutting_down) return uint64_to_js(0);
        NSArray *args = [JSContext currentArguments];
        if (args.count < 2) return uint64_to_js(0);
        uint64_t target = js_to_uint64(args[0]);
        NSString *selector = [args[1] toString];
        
        uint64_t a1 = args.count > 2 ? js_to_uint64(args[2]) : 0;
        uint64_t a2 = args.count > 3 ? js_to_uint64(args[3]) : 0;
        uint64_t a3 = args.count > 4 ? js_to_uint64(args[4]) : 0;
        uint64_t a4 = args.count > 5 ? js_to_uint64(args[5]) : 0;
        
        uint64_t res = r_msg2(target, [selector UTF8String], a1, a2, a3, a4);
        return uint64_to_js(res);
    };
    
    context[@"r_msg2_main"] = ^() {
        if (g_quickloader_shutting_down) return uint64_to_js(0);
        NSArray *args = [JSContext currentArguments];
        if (args.count < 2) return uint64_to_js(0);
        uint64_t target = js_to_uint64(args[0]);
        NSString *selector = [args[1] toString];
        
        uint64_t a1 = args.count > 2 ? js_to_uint64(args[2]) : 0;
        uint64_t a2 = args.count > 3 ? js_to_uint64(args[3]) : 0;
        uint64_t a3 = args.count > 4 ? js_to_uint64(args[4]) : 0;
        uint64_t a4 = args.count > 5 ? js_to_uint64(args[5]) : 0;
        
        uint64_t res = r_msg2_main(target, [selector UTF8String], a1, a2, a3, a4);
        return uint64_to_js(res);
    };

    context[@"r_nsstr"] = ^NSString*(NSString *str) {
        if (g_quickloader_shutting_down) return uint64_to_js(0);
        if (!str) return uint64_to_js(0);
        uint64_t ptr = r_nsstr_retained([str UTF8String]);
        return uint64_to_js(ptr);
    };

    // ... (Keep your r_set_icon_radius bridge here) ...

    log_user("[JS Engine] Executing user script...\n");
    [context evaluateScript:jsCode];
    
    log_user("[JS Engine] Execution complete.\n");
    return true;
}

// ==========================================
// Teardown engine
// ==========================================
bool quickloader_stop_in_session(void) {
    //Order timers to stop
    __sync_lock_test_and_set(&g_quickloader_shutting_down, 1);
    
    if (!g_quickloader_ipc_lock) g_quickloader_ipc_lock = [[NSLock alloc] init];
    
    //if timer is still running, wait (to prevent respring)
    [g_quickloader_ipc_lock lock];
    
    log_user("[QuickLoader] Clean Up: Green light, safely stopping JS timer...\n");
    
    if (g_quickloader_timers) {
        for (id key in g_quickloader_timers) {
            dispatch_source_t timer = (dispatch_source_t)g_quickloader_timers[key];
            if (dispatch_testcancel(timer) == 0) {
                dispatch_source_cancel(timer);
            }
        }
        [g_quickloader_timers removeAllObjects];
    }
    
    g_quickloader_context = nil; 
    
    [g_quickloader_ipc_lock unlock];
    return true; 
}
