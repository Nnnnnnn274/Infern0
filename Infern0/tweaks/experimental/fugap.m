#import "fugap.h"
#import "../remote_objc.h"
#import "../../TaskRop/RemoteCall.h"

#import <Foundation/Foundation.h>
#import <string.h>

typedef struct { double a; double b; double c; double d; double tx; double ty; } FUGapAffineTransform;

static bool gFUGapApplied = false;
static int gFUGapYOffset = -24;

static uint64_t fugap_key_window(void)
{
    uint64_t UIApplication = r_class("UIApplication");
    if (!r_is_objc_ptr(UIApplication)) return 0;
    uint64_t app = r_msg2_main(UIApplication, "sharedApplication", 0, 0, 0, 0);
    return r_is_objc_ptr(app) ? r_msg2_main(app, "keyWindow", 0, 0, 0, 0) : 0;
}

static void fugap_class_name(uint64_t obj, char *out, size_t outLen)
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

static void fugap_scan(uint64_t parent, double offset, int depth, int *hits)
{
    if (!r_is_objc_ptr(parent) || depth > 10) return;
    char cls[160] = {0};
    fugap_class_name(parent, cls, sizeof(cls));
    if (strstr(cls, "ControlCenter") && !strstr(cls, "Glyph") && !strstr(cls, "Button")) {
        FUGapAffineTransform t = { 1, 0, 0, 1, 0, offset };
        r_msg2_main_raw(parent, "setTransform:", &t, sizeof(t), NULL, 0, NULL, 0, NULL, 0);
        if (hits) (*hits)++;
        if (depth > 1) return;
    }
    uint64_t subviews = r_msg2_main(parent, "subviews", 0, 0, 0, 0);
    if (!r_is_objc_ptr(subviews)) return;
    uint64_t count = r_msg2_main(subviews, "count", 0, 0, 0, 0);
    if (count > 120) count = 120;
    for (uint64_t i = 0; i < count; i++) {
        fugap_scan(r_msg2_main(subviews, "objectAtIndex:", i, 0, 0, 0), offset, depth + 1, hits);
    }
}

bool fugap_apply_in_session(void)
{
    printf("[FUGAP] apply\n");
    uint64_t win = fugap_key_window();
    if (!r_is_objc_ptr(win)) return false;
    int hits = 0;
    fugap_scan(win, (double)gFUGapYOffset, 0, &hits);
    gFUGapApplied = hits > 0;
    return gFUGapApplied;
}

bool fugap_stop_in_session(void)
{
    printf("[FUGAP] stop\n");
    uint64_t win = fugap_key_window();
    int hits = 0;
    if (r_is_objc_ptr(win)) fugap_scan(win, 0.0, 0, &hits);
    gFUGapApplied = false;
    return true;
}

void fugap_configure(int yOffset)
{
    if (yOffset < -80) yOffset = -80;
    if (yOffset > 40) yOffset = 40;
    gFUGapYOffset = yOffset;
}

void fugap_forget_remote_state(void) { gFUGapApplied = false; }
