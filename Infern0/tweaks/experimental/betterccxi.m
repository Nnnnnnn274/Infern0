#import "betterccxi.h"
#import "../remote_objc.h"
#import "../sb_walk.h"
#import "../../TaskRop/RemoteCall.h"

#import <Foundation/Foundation.h>
#import <string.h>

static bool gBetterCCXIApplied = false;
static int gBetterCCXIZLift = 4;
static int gBetterCCXIDepthLimit = 12;

static uint64_t betterccxi_key_window(void)
{
    uint64_t UIApplication = r_class("UIApplication");
    if (!r_is_objc_ptr(UIApplication)) return 0;
    uint64_t app = r_msg2_main(UIApplication, "sharedApplication", 0, 0, 0, 0);
    return r_is_objc_ptr(app) ? r_msg2_main(app, "keyWindow", 0, 0, 0, 0) : 0;
}

static void betterccxi_class_name(uint64_t obj, char *out, size_t outLen)
{
    if (!out || outLen == 0) return;
    out[0] = '\0';
    if (!r_is_objc_ptr(obj)) return;
    uint64_t cls = r_dlsym_call(R_TIMEOUT, "object_getClass", obj, 0, 0, 0, 0, 0, 0, 0);
    uint64_t name = r_is_objc_ptr(cls) ? r_dlsym_call(R_TIMEOUT, "class_getName", cls, 0, 0, 0, 0, 0, 0, 0) : 0;
    if (!name) return;
    uint64_t buf = r_dlsym_call(R_TIMEOUT, "strdup", name, 0, 0, 0, 0, 0, 0, 0);
    if (!buf) return;
    remote_read(buf, out, outLen - 1);
    out[outLen - 1] = '\0';
    r_free(buf);
}

static void betterccxi_scan(uint64_t parent, double scale, int depth, int *hits)
{
    if (!r_is_objc_ptr(parent) || depth > gBetterCCXIDepthLimit) return;
    char cls[160] = {0};
    betterccxi_class_name(parent, cls, sizeof(cls));
    bool target = strstr(cls, "CCUIModule") || strstr(cls, "MediaControls") ||
                  strstr(cls, "NowPlaying") || strstr(cls, "ControlCenter");
    uint64_t layer = target ? r_msg2_main(parent, "layer", 0, 0, 0, 0) : 0;
    if (r_is_objc_ptr(layer)) {
        double z = (double)gBetterCCXIZLift;
        r_msg2_main_raw(layer, "setZPosition:", &z, sizeof(z), NULL, 0, NULL, 0, NULL, 0);
        if (hits) (*hits)++;
    }
    uint64_t subviews = r_msg2_main(parent, "subviews", 0, 0, 0, 0);
    if (!r_is_objc_ptr(subviews)) return;
    uint64_t count = r_msg2_main(subviews, "count", 0, 0, 0, 0);
    if (count > 80) count = 80;
    for (uint64_t i = 0; i < count; i++) {
        betterccxi_scan(r_msg2_main(subviews, "objectAtIndex:", i, 0, 0, 0), scale, depth + 1, hits);
    }
}

bool betterccxi_apply_in_session(void)
{
    printf("[BETTERCCXI] apply\n");
    uint64_t win = sb_frontmost_window();
    if (!r_is_objc_ptr(win)) return false;
    int hits = 0;
    betterccxi_scan(win, 1.0, 0, &hits);
    gBetterCCXIApplied = hits > 0;
    return gBetterCCXIApplied;
}

bool betterccxi_stop_in_session(void)
{
    printf("[BETTERCCXI] stop\n");
    uint64_t win = sb_frontmost_window();
    int hits = 0;
    int old = gBetterCCXIZLift;
    gBetterCCXIZLift = 0;
    if (r_is_objc_ptr(win)) betterccxi_scan(win, 1.0, 0, &hits);
    gBetterCCXIZLift = old;
    gBetterCCXIApplied = false;
    return true;
}

void betterccxi_configure(int zLift, int depthLimit)
{
    if (zLift < 0) zLift = 0;
    if (zLift > 20) zLift = 20;
    if (depthLimit < 4) depthLimit = 4;
    if (depthLimit > 16) depthLimit = 16;
    gBetterCCXIZLift = zLift;
    gBetterCCXIDepthLimit = depthLimit;
}

void betterccxi_forget_remote_state(void) { gBetterCCXIApplied = false; }
