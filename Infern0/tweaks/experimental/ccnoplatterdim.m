#import "ccnoplatterdim.h"
#import "../remote_objc.h"
#import "../sb_walk.h"
#import "../../TaskRop/RemoteCall.h"

#import <Foundation/Foundation.h>
#import <string.h>

static bool gCCNoPlatterDimApplied = false;
static int gCCNoPlatterDimVisibleAlphaPercent = 96;

static uint64_t ccnoplatterdim_key_window(void)
{
    uint64_t UIApplication = r_class("UIApplication");
    if (!r_is_objc_ptr(UIApplication)) return 0;
    uint64_t app = r_msg2_main(UIApplication, "sharedApplication", 0, 0, 0, 0);
    return r_is_objc_ptr(app) ? r_msg2_main(app, "keyWindow", 0, 0, 0, 0) : 0;
}

static void ccnoplatterdim_class_name(uint64_t obj, char *out, size_t outLen)
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

static void ccnoplatterdim_scan(uint64_t parent, double alpha, int depth, int *hits)
{
    if (!r_is_objc_ptr(parent) || depth > 12) return;
    char cls[160] = {0};
    ccnoplatterdim_class_name(parent, cls, sizeof(cls));
    bool dimTarget = strstr(cls, "Platter") || strstr(cls, "Backdrop") ||
                     strstr(cls, "Dimming") || strstr(cls, "Overlay");
    if (dimTarget) {
        r_msg2_main_raw(parent, "setAlpha:", &alpha, sizeof(alpha), NULL, 0, NULL, 0, NULL, 0);
        if (hits) (*hits)++;
    }
    uint64_t subviews = r_msg2_main(parent, "subviews", 0, 0, 0, 0);
    if (!r_is_objc_ptr(subviews)) return;
    uint64_t count = r_msg2_main(subviews, "count", 0, 0, 0, 0);
    if (count > 80) count = 80;
    for (uint64_t i = 0; i < count; i++) ccnoplatterdim_scan(r_msg2_main(subviews, "objectAtIndex:", i, 0, 0, 0), alpha, depth + 1, hits);
}

bool ccnoplatterdim_apply_in_session(void)
{
    printf("[CCNOPLATTERDIM] apply\n");
    uint64_t win = sb_frontmost_window();
    if (!r_is_objc_ptr(win)) return false;
    int hits = 0;
    ccnoplatterdim_scan(win, (double)gCCNoPlatterDimVisibleAlphaPercent / 100.0, 0, &hits);
    gCCNoPlatterDimApplied = hits > 0;
    return gCCNoPlatterDimApplied;
}

bool ccnoplatterdim_stop_in_session(void)
{
    printf("[CCNOPLATTERDIM] stop\n");
    uint64_t win = sb_frontmost_window();
    int hits = 0;
    if (r_is_objc_ptr(win)) ccnoplatterdim_scan(win, 1.0, 0, &hits);
    gCCNoPlatterDimApplied = false;
    return true;
}

void ccnoplatterdim_configure(int visibleAlphaPercent)
{
    if (visibleAlphaPercent < 40) visibleAlphaPercent = 40;
    if (visibleAlphaPercent > 100) visibleAlphaPercent = 100;
    gCCNoPlatterDimVisibleAlphaPercent = visibleAlphaPercent;
}

void ccnoplatterdim_forget_remote_state(void) { gCCNoPlatterDimApplied = false; }
