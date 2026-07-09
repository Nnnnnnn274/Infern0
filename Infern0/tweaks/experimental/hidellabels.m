#import "hidellabels.h"
#import "../remote_objc.h"
#import "../../TaskRop/RemoteCall.h"
#import "../../LogTextView.h"

#import <Foundation/Foundation.h>
#import <math.h>

static bool gHllApplied = false;

static void hll_scan_icon_views(uint64_t parent, int depth)
{
    if (!r_is_objc_ptr(parent) || depth > 10) return;

    uint64_t subviews = r_msg2_main(parent, "subviews", 0, 0, 0, 0);
    if (!r_is_objc_ptr(subviews)) return;
    uint64_t count = r_msg2_main(subviews, "count", 0, 0, 0, 0);
    if (count > 64) count = 64;

    for (uint64_t i = 0; i < count; i++) {
        uint64_t sv = r_msg2_main(subviews, "objectAtIndex:", i, 0, 0, 0);
        if (!r_is_objc_ptr(sv)) continue;

        char cls[128] = {0};
        uint64_t rCls = r_dlsym_call(R_TIMEOUT, "object_getClass", sv, 0, 0, 0, 0, 0, 0, 0);
        if (r_is_objc_ptr(rCls)) {
            uint64_t name = r_dlsym_call(R_TIMEOUT, "class_getName", rCls, 0, 0, 0, 0, 0, 0, 0);
            if (name) {
                uint64_t buf = r_dlsym_call(R_TIMEOUT, "strdup", name, 0, 0, 0, 0, 0, 0, 0);
                if (buf) {
                    remote_read(buf, cls, sizeof(cls) - 1);
                    r_free(buf);
                }
            }
        }

        if (strstr(cls, "SBIconView") && !strstr(cls, "Label")) {
            hll_scan_icon_views(sv, depth + 1);
            continue;
        }

        if (strstr(cls, "Label") || strstr(cls, "label")) {
            uint64_t UILabel = r_class("UILabel");
            if (r_is_objc_ptr(UILabel)) {
                uint64_t isLabel = r_msg2_main(sv, "isKindOfClass:", UILabel, 0, 0, 0);
                if (isLabel & 0xff) {
                    double zero = 0.0;
                    r_msg2_main_raw(sv, "setAlpha:", &zero, sizeof(zero), NULL, 0, NULL, 0, NULL, 0);
                    printf("[HLL] hid label 0x%llx\n", sv);
                }
            }
        }

        hll_scan_icon_views(sv, depth + 1);
    }
}

bool hidellabels_apply_in_session(void)
{
    printf("[HLL] apply\n");

    uint64_t UIApplication = r_class("UIApplication");
    if (!r_is_objc_ptr(UIApplication)) return false;
    uint64_t app = r_msg2_main(UIApplication, "sharedApplication", 0, 0, 0, 0);
    if (!r_is_objc_ptr(app)) return false;

    uint64_t windows = r_msg2_main(app, "windows", 0, 0, 0, 0);
    if (!r_is_objc_ptr(windows)) return false;
    uint64_t winCount = r_msg2_main(windows, "count", 0, 0, 0, 0);
    if (winCount > 64) winCount = 64;

    for (uint64_t i = 0; i < winCount; i++) {
        uint64_t win = r_msg2_main(windows, "objectAtIndex:", i, 0, 0, 0);
        if (!r_is_objc_ptr(win)) continue;
        uint64_t root = r_msg2_main(win, "rootViewController", 0, 0, 0, 0);
        if (!r_is_objc_ptr(root)) continue;

        char cls[128] = {0};
        uint64_t rCls = r_dlsym_call(R_TIMEOUT, "object_getClass", root, 0, 0, 0, 0, 0, 0, 0);
        if (r_is_objc_ptr(rCls)) {
            uint64_t name = r_dlsym_call(R_TIMEOUT, "class_getName", rCls, 0, 0, 0, 0, 0, 0, 0);
            if (name) {
                uint64_t buf = r_dlsym_call(R_TIMEOUT, "strdup", name, 0, 0, 0, 0, 0, 0, 0);
                if (buf) {
                    remote_read(buf, cls, sizeof(cls) - 1);
                    r_free(buf);
                }
            }
        }

        if (strstr(cls, "SBIconController") || strstr(cls, "SBRootFolder") ||
            strstr(cls, "SBIconListView") || strstr(cls, "SBFolderView")) {
            hll_scan_icon_views(root, 0);
        }
    }

    gHllApplied = true;
    return true;
}

bool hidellabels_stop_in_session(void)
{
    printf("[HLL] stop\n");
    gHllApplied = false;
    return true;
}

void hidellabels_forget_remote_state(void)
{
    gHllApplied = false;
}
