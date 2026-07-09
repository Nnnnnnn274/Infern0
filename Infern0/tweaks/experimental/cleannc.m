#import "cleannc.h"
#import "../remote_objc.h"
#import "../../TaskRop/RemoteCall.h"
#import "../../LogTextView.h"

#import <Foundation/Foundation.h>
#import <math.h>

static bool gCleanncApplied = false;

bool cleannc_apply_in_session(void)
{
    printf("[CLEANNC] apply\n");

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

        uint64_t rCls = r_dlsym_call(R_TIMEOUT, "object_getClass", root, 0, 0, 0, 0, 0, 0, 0);
        if (!r_is_objc_ptr(rCls)) continue;
        uint64_t name = r_dlsym_call(R_TIMEOUT, "class_getName", rCls, 0, 0, 0, 0, 0, 0, 0);
        if (!name) continue;
        uint64_t buf = r_dlsym_call(R_TIMEOUT, "strdup", name, 0, 0, 0, 0, 0, 0, 0);
        if (!buf) continue;
        char cls[128] = {0};
        remote_read(buf, cls, sizeof(cls) - 1);
        r_free(buf);

        if (strstr(cls, "CoverSheet") || strstr(cls, "NCNotification")) {
            uint64_t listView = r_ivar_value(root, "_listView");
            if (!r_is_objc_ptr(listView)) listView = r_msg2_main(root, "listView", 0, 0, 0, 0);
            if (!r_is_objc_ptr(listView)) continue;

            uint64_t subviews = r_msg2_main(listView, "subviews", 0, 0, 0, 0);
            if (!r_is_objc_ptr(subviews)) continue;
            uint64_t count = r_msg2_main(subviews, "count", 0, 0, 0, 0);
            if (count > 128) count = 128;

            for (uint64_t j = 0; j < count; j++) {
                uint64_t sv = r_msg2_main(subviews, "objectAtIndex:", j, 0, 0, 0);
                if (!r_is_objc_ptr(sv)) continue;

                char svCls[128] = {0};
                uint64_t svRCls = r_dlsym_call(R_TIMEOUT, "object_getClass", sv, 0, 0, 0, 0, 0, 0, 0);
                if (r_is_objc_ptr(svRCls)) {
                    uint64_t svName = r_dlsym_call(R_TIMEOUT, "class_getName", svRCls, 0, 0, 0, 0, 0, 0, 0);
                    if (svName) {
                        uint64_t svBuf = r_dlsym_call(R_TIMEOUT, "strdup", svName, 0, 0, 0, 0, 0, 0, 0);
                        if (svBuf) {
                            remote_read(svBuf, svCls, sizeof(svCls) - 1);
                            r_free(svBuf);
                        }
                    }
                }

                if (strstr(svCls, "Search") || strstr(svCls, "search")) {
                    r_msg2_main(sv, "setHidden:", 1, 0, 0, 0);
                    printf("[CLEANNC] hid search bar: 0x%llx\n", sv);
                }
                if (strstr(svCls, "NoNotifications") || strstr(svCls, "no_notifications")) {
                    r_msg2_main(sv, "setHidden:", 1, 0, 0, 0);
                    printf("[CLEANNC] hid 'No Older Notifications': 0x%llx\n", sv);
                }
            }

            uint64_t bgView = r_ivar_value(root, "_backgroundView");
            if (r_is_objc_ptr(bgView)) {
                r_msg2_main(bgView, "setHidden:", 1, 0, 0, 0);
                printf("[CLEANNC] hid grid background: 0x%llx\n", bgView);
            }
        }
    }

    gCleanncApplied = true;
    return true;
}

bool cleannc_stop_in_session(void)
{
    printf("[CLEANNC] stop\n");
    gCleanncApplied = false;
    return true;
}

void cleannc_forget_remote_state(void)
{
    gCleanncApplied = false;
}
