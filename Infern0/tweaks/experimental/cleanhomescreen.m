#import "cleanhomescreen.h"
#import "../remote_objc.h"
#import "../../TaskRop/RemoteCall.h"
#import "../../LogTextView.h"

#import <Foundation/Foundation.h>
#import <math.h>

static bool gChsApplied = false;
static bool gChsBadgeHidden = false;
static bool gChsDotHidden = false;
static bool gChsLabelHidden = false;

static void chs_set_alpha(uint64_t view, double alpha)
{
    if (!r_is_objc_ptr(view)) return;
    r_msg2_main_raw(view, "setAlpha:", &alpha, sizeof(alpha), NULL, 0, NULL, 0, NULL, 0);
}

static void chs_scan_views(uint64_t parent, int depth)
{
    if (!r_is_objc_ptr(parent) || depth > 12) return;

    uint64_t subviews = r_msg2_main(parent, "subviews", 0, 0, 0, 0);
    if (!r_is_objc_ptr(subviews)) return;
    uint64_t count = r_msg2_main(subviews, "count", 0, 0, 0, 0);
    if (count > 128) count = 128;

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

        if (strstr(cls, "Badge") && !strstr(cls, "Label")) {
            chs_set_alpha(sv, gChsBadgeHidden ? 0.0 : 1.0);
            printf("[CHS] hid badge: 0x%llx\n", sv);
        }

        if (strstr(cls, "PageControl") || strstr(cls, "PageDot") ||
            strstr(cls, "PageIndicator")) {
            r_msg2_main(sv, "setHidden:", gChsDotHidden ? 1 : 0, 0, 0, 0);
            printf("[CHS] hid page dot: 0x%llx\n", sv);
        }

        if (strstr(cls, "Label") || strstr(cls, "label")) {
            chs_set_alpha(sv, gChsLabelHidden ? 0.0 : 1.0);
            printf("[CHS] hid label: 0x%llx\n", sv);
        }

        chs_scan_views(sv, depth + 1);
    }
}

bool cleanhomescreen_apply_in_session(bool hideBadges, bool hidePageDots, bool hideLabels)
{
    printf("[CHS] apply badges=%d dots=%d labels=%d\n", hideBadges, hidePageDots, hideLabels);

    gChsBadgeHidden = hideBadges;
    gChsDotHidden = hidePageDots;
    gChsLabelHidden = hideLabels;

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
        chs_scan_views(win, 0);

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
            strstr(cls, "SBIconListView") || strstr(cls, "SBFolderView") ||
            strstr(cls, "SBHomeScreen")) {
            uint64_t rootView = r_msg2_main(root, "view", 0, 0, 0, 0);
            if (r_is_objc_ptr(rootView)) chs_scan_views(rootView, 0);
        }
    }

    gChsApplied = true;
    return true;
}

bool cleanhomescreen_stop_in_session(void)
{
    printf("[CHS] stop\n");
    gChsBadgeHidden = false;
    gChsDotHidden = false;
    gChsLabelHidden = false;
    cleanhomescreen_apply_in_session(false, false, false);
    gChsApplied = false;
    return true;
}

void cleanhomescreen_forget_remote_state(void)
{
    gChsApplied = false;
}
