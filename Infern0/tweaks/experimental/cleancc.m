#import "cleancc.h"
#import "../remote_objc.h"
#import "../sb_walk.h"
#import "../../TaskRop/RemoteCall.h"

#import <Foundation/Foundation.h>
#import <string.h>

static uint64_t gCleanCCTint = 0;
static int gCleanCCMaterialAlphaPercent = 78;
static int gCleanCCGlassTintPercent = 10;

static uint64_t cleancc_color(double red, double green, double blue, double alpha)
{
    uint64_t UIColor = r_class("UIColor");
    if (!r_is_objc_ptr(UIColor)) return 0;
    return r_msg2_main_raw(UIColor, "colorWithRed:green:blue:alpha:",
                           &red, sizeof(red), &green, sizeof(green),
                           &blue, sizeof(blue), &alpha, sizeof(alpha));
}

static uint64_t cleancc_key_window(void)
{
    uint64_t UIApplication = r_class("UIApplication");
    if (!r_is_objc_ptr(UIApplication)) return 0;
    uint64_t app = r_msg2_main(UIApplication, "sharedApplication", 0, 0, 0, 0);
    return r_is_objc_ptr(app) ? r_msg2_main(app, "keyWindow", 0, 0, 0, 0) : 0;
}

static void cleancc_class_name(uint64_t obj, char *out, size_t outLen)
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

static void cleancc_scan(uint64_t parent, uint64_t color, double alpha, int depth, int *hits)
{
    if (!r_is_objc_ptr(parent) || depth > 12) return;
    char cls[160] = {0};
    cleancc_class_name(parent, cls, sizeof(cls));
    if (strstr(cls, "CCUI") || strstr(cls, "ControlCenter")) {
        if (r_is_objc_ptr(color) && r_responds_main(parent, "setBackgroundColor:")) {
            r_msg2_main(parent, "setBackgroundColor:", color, 0, 0, 0);
        }
        if (r_responds_main(parent, "setAlpha:")) {
            r_msg2_main_raw(parent, "setAlpha:", &alpha, sizeof(alpha), NULL, 0, NULL, 0, NULL, 0);
        }
        if (hits) (*hits)++;
    }
    uint64_t subviews = r_msg2_main(parent, "subviews", 0, 0, 0, 0);
    if (!r_is_objc_ptr(subviews)) return;
    uint64_t count = r_msg2_main(subviews, "count", 0, 0, 0, 0);
    if (count > 160) count = 160;
    for (uint64_t i = 0; i < count; i++) {
        cleancc_scan(r_msg2_main(subviews, "objectAtIndex:", i, 0, 0, 0), color, alpha, depth + 1, hits);
    }
}

bool cleancc_apply_in_session(void)
{
    printf("[CLEANCC] apply\n");
    uint64_t win = sb_frontmost_window();
    if (!r_is_objc_ptr(win)) return false;
    double tintAlpha = (double)gCleanCCGlassTintPercent / 100.0;
    double materialAlpha = (double)gCleanCCMaterialAlphaPercent / 100.0;
    if (materialAlpha < 0.05) materialAlpha = 0.05;
    if (materialAlpha > 1.0) materialAlpha = 1.0;
    gCleanCCTint = cleancc_color(1, 1, 1, tintAlpha);
    int hits = 0;
    cleancc_scan(win, gCleanCCTint, materialAlpha, 0, &hits);
    printf("[CLEANCC] adjusted %d CC views\n", hits);
    return hits > 0;
}

bool cleancc_stop_in_session(void)
{
    printf("[CLEANCC] stop\n");
    uint64_t win = sb_frontmost_window();
    uint64_t clear = cleancc_color(0, 0, 0, 0);
    int hits = 0;
    if (r_is_objc_ptr(win)) cleancc_scan(win, clear, 1.0, 0, &hits);
    gCleanCCTint = 0;
    return true;
}

void cleancc_configure(int materialAlphaPercent, int glassTintPercent)
{
    if (materialAlphaPercent < 5) materialAlphaPercent = 5;
    if (materialAlphaPercent > 100) materialAlphaPercent = 100;
    if (glassTintPercent < 0) glassTintPercent = 0;
    if (glassTintPercent > 80) glassTintPercent = 80;
    gCleanCCMaterialAlphaPercent = materialAlphaPercent;
    gCleanCCGlassTintPercent = glassTintPercent;
}

void cleancc_forget_remote_state(void) { gCleanCCTint = 0; }
