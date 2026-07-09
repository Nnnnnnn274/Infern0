#import "tweakloader.h"
#import "../remote_objc.h"

#import <Foundation/Foundation.h>

#define MAX_TWEAKS 64

typedef struct {
    char name[128];
    tweakloader_func_t apply;
    tweakloader_func_t stop;
} TLRegisteredTweak;

static TLRegisteredTweak gTlTweaks[MAX_TWEAKS];
static unsigned int gTlCount = 0;
static bool gTlApplied = false;

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------

void tweakloader_register(const char *name, tweakloader_func_t apply, tweakloader_func_t stop)
{
    if (!name || !apply || gTlCount >= MAX_TWEAKS) return;
    TLRegisteredTweak *t = &gTlTweaks[gTlCount++];
    snprintf(t->name, sizeof(t->name), "%s", name);
    t->apply = apply;
    t->stop = stop;
}

void tweakloader_reload_list(void)
{
    gTlCount = 0;
    memset(gTlTweaks, 0, sizeof(gTlTweaks));
    // Built-in demos register themselves here (or via +load).
    // If you add a new .m/.h tweak, register it here.
    extern void tweakloader_register_builtins(void);
    tweakloader_register_builtins();
    printf("[TWEAKLOADER] reloaded: %u registered tweak(s)\n", gTlCount);
}

// ---------------------------------------------------------------------------
// Per-tweak apply / stop
// ---------------------------------------------------------------------------

bool tweakloader_apply_at(unsigned int index)
{
    if (index >= gTlCount || !gTlTweaks[index].apply) return false;
    return gTlTweaks[index].apply();
}

bool tweakloader_stop_at(unsigned int index)
{
    if (index >= gTlCount || !gTlTweaks[index].stop) return false;
    return gTlTweaks[index].stop();
}

// ---------------------------------------------------------------------------
// All-at-once apply / stop (used by SettingsViewController toggle)
// ---------------------------------------------------------------------------

bool tweakloader_apply_in_session(void)
{
    printf("[TWEAKLOADER] apply all\n");
    if (gTlCount == 0) {
        tweakloader_reload_list();
    }
    bool allOk = true;
    for (unsigned int i = 0; i < gTlCount; i++) {
        if (!tweakloader_apply_at(i)) {
            printf("[TWEAKLOADER] apply failed for %s\n", gTlTweaks[i].name);
            allOk = false;
        }
    }
    gTlApplied = allOk;
    return allOk;
}

bool tweakloader_stop_in_session(void)
{
    printf("[TWEAKLOADER] stop all\n");
    bool allOk = true;
    for (unsigned int i = 0; i < gTlCount; i++) {
        if (!tweakloader_stop_at(i)) {
            printf("[TWEAKLOADER] stop failed for %s\n", gTlTweaks[i].name);
            allOk = false;
        }
    }
    gTlApplied = false;
    return allOk;
}

void tweakloader_forget_remote_state(void)
{
    gTlApplied = false;
}

unsigned int tweakloader_loaded_count(void)
{
    return gTlCount;
}

const char *tweakloader_name_at(unsigned int index)
{
    if (index >= gTlCount) return NULL;
    return gTlTweaks[index].name;
}

// ---------------------------------------------------------------------------
// Built-in demo tweaks
// ---------------------------------------------------------------------------

static bool demo_hello_apply(void)
{
    printf("[TWEAKLOADER] demo_hello: creating NSString in SpringBoard\n");
    uint64_t str = r_nsstr_retained("[TweakLoader] Hello from RemoteCall!");
    if (r_is_objc_ptr(str)) {
        printf("[TWEAKLOADER] demo_hello: RemoteCall OK\n");
        r_free(str);
        return true;
    }
    printf("[TWEAKLOADER] demo_hello: RemoteCall failed\n");
    return false;
}

static bool demo_hello_stop(void)
{
    return true;
}

static bool demo_log_apply(void)
{
    printf("[TWEAKLOADER] demo_log: enumerating SpringBoard windows\n");
    uint64_t app = r_msg2_main(r_class("UIApplication"), "sharedApplication", 0, 0, 0, 0);
    if (r_is_objc_ptr(app)) {
        uint64_t windows = r_msg2_main(app, "windows", 0, 0, 0, 0);
        if (r_is_objc_ptr(windows)) {
            printf("[TWEAKLOADER] demo_log: got windows array\n");
            return true;
        }
    }
    printf("[TWEAKLOADER] demo_log: no windows\n");
    return false;
}

static bool demo_log_stop(void)
{
    return true;
}

void tweakloader_register_builtins(void)
{
    static bool registered = false;
    if (registered) return;
    registered = true;

    tweakloader_register("Hello RemoteCall", demo_hello_apply, demo_hello_stop);
    tweakloader_register("Log SpringBoard Windows", demo_log_apply, demo_log_stop);
    printf("[TWEAKLOADER] built-in tweaks registered\n");
}
