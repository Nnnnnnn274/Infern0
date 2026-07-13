#import "modulespacing.h"
#import "../remote_objc.h"
#import "../sb_walk.h"
#import "../../TaskRop/RemoteCall.h"

#import <Foundation/Foundation.h>
#import <string.h>

static bool gModuleSpacingApplied = false;
static int gModuleSpacingCornerRadius = 8;

static uint64_t modulespacing_key_window(void)
{
    uint64_t UIApplication = r_class("UIApplication");
    if (!r_is_objc_ptr(UIApplication)) return 0;
    uint64_t app = r_msg2_main(UIApplication, "sharedApplication", 0, 0, 0, 0);
    return r_is_objc_ptr(app) ? r_msg2_main(app, "keyWindow", 0, 0, 0, 0) : 0;
}

static void modulespacing_class_name(uint64_t obj, char *out, size_t outLen)
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

static void modulespacing_scan(uint64_t parent, double radius, int depth, int *hits)
{
    if (!r_is_objc_ptr(parent) || depth > 12) return;
    char cls[160] = {0};
    modulespacing_class_name(parent, cls, sizeof(cls));
    if (strstr(cls, "CCUIModule") || strstr(cls, "ControlCenter")) {
        uint64_t layer = r_msg2_main(parent, "layer", 0, 0, 0, 0);
        if (r_is_objc_ptr(layer)) {
            r_msg2_main_raw(layer, "setCornerRadius:", &radius, sizeof(radius), NULL, 0, NULL, 0, NULL, 0);
            r_msg2_main(layer, "setMasksToBounds:", 1, 0, 0, 0);
            if (hits) (*hits)++;
        }
    }
    uint64_t subviews = r_msg2_main(parent, "subviews", 0, 0, 0, 0);
    if (!r_is_objc_ptr(subviews)) return;
    uint64_t count = r_msg2_main(subviews, "count", 0, 0, 0, 0);
    if (count > 160) count = 160;
    for (uint64_t i = 0; i < count; i++) {
        modulespacing_scan(r_msg2_main(subviews, "objectAtIndex:", i, 0, 0, 0), radius, depth + 1, hits);
    }
}

bool modulespacing_apply_in_session(void)
{
    printf("[MODULESPACING] apply\n");
    uint64_t win = sb_frontmost_window();
    if (!r_is_objc_ptr(win)) return false;
    int hits = 0;
    modulespacing_scan(win, (double)gModuleSpacingCornerRadius, 0, &hits);
    gModuleSpacingApplied = hits > 0;
    return gModuleSpacingApplied;
}

bool modulespacing_stop_in_session(void)
{
    printf("[MODULESPACING] stop\n");
    uint64_t win = sb_frontmost_window();
    int hits = 0;
    if (r_is_objc_ptr(win)) modulespacing_scan(win, 18.0, 0, &hits);
    gModuleSpacingApplied = false;
    return true;
}

void modulespacing_configure(int cornerRadius)
{
    if (cornerRadius < 0) cornerRadius = 0;
    if (cornerRadius > 40) cornerRadius = 40;
    gModuleSpacingCornerRadius = cornerRadius;
}

void modulespacing_forget_remote_state(void) { gModuleSpacingApplied = false; }
