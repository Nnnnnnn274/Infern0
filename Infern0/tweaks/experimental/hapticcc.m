#import "hapticcc.h"
#import "../remote_objc.h"
#import "../sb_walk.h"
#import "../../TaskRop/RemoteCall.h"

#import <Foundation/Foundation.h>
#import <string.h>

static bool gHapticCCApplied = false;
static int gHapticCCFeedbackStyle = 1;
static uint64_t gHapticCCControls[64] = {0};
static uint8_t gHapticCCStates[64] = {0};
static int gHapticCCControlCount = 0;

static void hapticcc_class_name(uint64_t obj, char *out, size_t outLen)
{
    if (!out || outLen == 0) return;
    out[0] = '\0';
    uint64_t cls = r_is_objc_ptr(obj) ?
        r_dlsym_call(R_TIMEOUT, "object_getClass", obj, 0, 0, 0, 0, 0, 0, 0) : 0;
    uint64_t name = r_is_objc_ptr(cls) ?
        r_dlsym_call(R_TIMEOUT, "class_getName", cls, 0, 0, 0, 0, 0, 0, 0) : 0;
    if (!name) return;
    uint64_t copy = r_dlsym_call(R_TIMEOUT, "strdup", name, 0, 0, 0, 0, 0, 0, 0);
    if (!copy) return;
    remote_read(copy, out, outLen - 1);
    out[outLen - 1] = '\0';
    r_free(copy);
}

static void hapticcc_fire(void)
{
    uint64_t Generator = r_class("UIImpactFeedbackGenerator");
    uint64_t gen = r_is_objc_ptr(Generator) ? r_msg2_main(Generator, "alloc", 0, 0, 0, 0) : 0;
    gen = r_is_objc_ptr(gen) ? r_msg2_main(gen, "initWithStyle:", (uint64_t)gHapticCCFeedbackStyle, 0, 0, 0) : 0;
    if (!r_is_objc_ptr(gen)) return;
    r_msg2_main(gen, "prepare", 0, 0, 0, 0);
    r_msg2_main(gen, "impactOccurred", 0, 0, 0, 0);
    r_msg2_main(gen, "release", 0, 0, 0, 0);
}

static void hapticcc_scan(uint64_t view, int depth, int *hits, bool *fired)
{
    if (!r_is_objc_ptr(view) || depth > 14) return;
    char cls[160] = {0};
    hapticcc_class_name(view, cls, sizeof(cls));
    bool ccView = strstr(cls, "CCUI") || strstr(cls, "ControlCenter");
    const char *stateSelector = r_responds_main(view, "isSelected") ? "isSelected" :
                                (r_responds_main(view, "isOn") ? "isOn" : NULL);
    if (ccView && stateSelector) {
        uint8_t state = (uint8_t)(r_msg2_main(view, stateSelector, 0, 0, 0, 0) & 0xff);
        int index = -1;
        for (int i = 0; i < gHapticCCControlCount; i++) {
            if (gHapticCCControls[i] == view) { index = i; break; }
        }
        if (index < 0 && gHapticCCControlCount < 64) {
            index = gHapticCCControlCount++;
            gHapticCCControls[index] = view;
            gHapticCCStates[index] = state;
        } else if (index >= 0 && gHapticCCStates[index] != state) {
            gHapticCCStates[index] = state;
            if (fired && !*fired) { hapticcc_fire(); *fired = true; }
        }
        if (hits) (*hits)++;
    }
    uint64_t subviews = r_msg2_main(view, "subviews", 0, 0, 0, 0);
    uint64_t count = r_is_objc_ptr(subviews) ? r_msg2_main(subviews, "count", 0, 0, 0, 0) : 0;
    if (count > 160) count = 160;
    for (uint64_t i = 0; i < count; i++)
        hapticcc_scan(r_msg2_main(subviews, "objectAtIndex:", i, 0, 0, 0), depth + 1, hits, fired);
}

bool hapticcc_apply_in_session(void)
{
    uint64_t win = sb_frontmost_window();
    if (!r_is_objc_ptr(win)) return false;
    int hits = 0;
    bool fired = false;
    hapticcc_scan(win, 0, &hits, &fired);
    if (hits == 0) {
        memset(gHapticCCControls, 0, sizeof(gHapticCCControls));
        memset(gHapticCCStates, 0, sizeof(gHapticCCStates));
        gHapticCCControlCount = 0;
    }
    gHapticCCApplied = hits > 0;
    return gHapticCCApplied;
}

bool hapticcc_stop_in_session(void)
{
    printf("[HAPTICCC] stop\n");
    memset(gHapticCCControls, 0, sizeof(gHapticCCControls));
    memset(gHapticCCStates, 0, sizeof(gHapticCCStates));
    gHapticCCControlCount = 0;
    gHapticCCApplied = false;
    return true;
}

void hapticcc_configure(int feedbackStyle)
{
    if (feedbackStyle < 0) feedbackStyle = 0;
    if (feedbackStyle > 4) feedbackStyle = 4;
    gHapticCCFeedbackStyle = feedbackStyle;
}

void hapticcc_forget_remote_state(void)
{
    memset(gHapticCCControls, 0, sizeof(gHapticCCControls));
    memset(gHapticCCStates, 0, sizeof(gHapticCCStates));
    gHapticCCControlCount = 0;
    gHapticCCApplied = false;
}
