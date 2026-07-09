#import "undertime.h"
#import "../remote_objc.h"
#import "../../TaskRop/RemoteCall.h"
#import "../../LogTextView.h"

#import <Foundation/Foundation.h>
#import <math.h>

static bool gUtApplied = false;

bool undertime_apply_in_session(void)
{
    printf("[UNDERTIME] apply\n");

    uint64_t UIApplication = r_class("UIApplication");
    if (!r_is_objc_ptr(UIApplication)) return false;
    uint64_t app = r_msg2_main(UIApplication, "sharedApplication", 0, 0, 0, 0);
    if (!r_is_objc_ptr(app)) return false;

    uint64_t statusBar = r_msg2_main(app, "statusBar", 0, 0, 0, 0);
    if (!r_is_objc_ptr(statusBar)) {
        statusBar = r_ivar_value(app, "_statusBar");
    }
    if (!r_is_objc_ptr(statusBar)) {
        statusBar = r_ivar_value(app, "_statusBarWindow");
        if (r_is_objc_ptr(statusBar)) {
            statusBar = r_msg2_main(statusBar, "statusBar", 0, 0, 0, 0);
        }
    }
    if (!r_is_objc_ptr(statusBar)) return false;

    uint64_t timeItem = r_msg2_main(statusBar, "timeItem", 0, 0, 0, 0);
    if (!r_is_objc_ptr(timeItem)) {
        timeItem = r_ivar_value(statusBar, "_timeItem");
    }
    if (!r_is_objc_ptr(timeItem)) {
        uint64_t items = r_msg2_main(statusBar, "items", 0, 0, 0, 0);
        if (!r_is_objc_ptr(items)) {
            items = r_ivar_value(statusBar, "_items");
        }
        if (r_is_objc_ptr(items)) {
            uint64_t count = r_msg2_main(items, "count", 0, 0, 0, 0);
            for (uint64_t j = 0; j < count && j < 32; j++) {
                uint64_t item = r_msg2_main(items, "objectAtIndex:", j, 0, 0, 0);
                if (!r_is_objc_ptr(item)) continue;
                char itemCls[128] = {0};
                uint64_t icls = r_dlsym_call(R_TIMEOUT, "object_getClass", item, 0, 0, 0, 0, 0, 0, 0);
                if (r_is_objc_ptr(icls)) {
                    uint64_t iname = r_dlsym_call(R_TIMEOUT, "class_getName", icls, 0, 0, 0, 0, 0, 0, 0);
                    if (iname) {
                        uint64_t ibuf = r_dlsym_call(R_TIMEOUT, "strdup", iname, 0, 0, 0, 0, 0, 0, 0);
                        if (ibuf) {
                            remote_read(ibuf, itemCls, sizeof(itemCls) - 1);
                            r_free(ibuf);
                        }
                    }
                }
                if (strstr(itemCls, "Time") || strstr(itemCls, "Clock")) {
                    timeItem = item;
                    break;
                }
            }
        }
    }
    if (!r_is_objc_ptr(timeItem)) return false;

    uint64_t stringClass = r_class("NSString");
    if (!r_is_objc_ptr(stringClass)) return false;

    const char *fmt = "HH:mm\n%.1f GB";
    uint64_t fmtStr = r_alloc_str(fmt);
    if (!fmtStr) return false;

    uint64_t formatStr = r_msg2_main(stringClass, "stringWithUTF8String:", fmtStr, 0, 0, 0);
    r_free(fmtStr);
    if (!r_is_objc_ptr(formatStr)) return false;

    r_msg2_main(timeItem, "setFormat:", formatStr, 0, 0, 0);
    printf("[UNDERTIME] set double-line clock format\n");

    gUtApplied = true;
    return true;
}

bool undertime_stop_in_session(void)
{
    printf("[UNDERTIME] stop\n");
    gUtApplied = false;
    return true;
}

void undertime_forget_remote_state(void)
{
    gUtApplied = false;
}
