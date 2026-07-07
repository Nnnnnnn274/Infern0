#import "ccstatus.h"
#import "../remote_objc.h"
#import "../../TaskRop/RemoteCall.h"

#import <Foundation/Foundation.h>

typedef struct { double x; double y; double width; double height; } CCStatusRect;

static uint64_t gCCStatusLabel = 0;

static uint64_t ccstatus_key_window(void)
{
    uint64_t UIApplication = r_class("UIApplication");
    if (!r_is_objc_ptr(UIApplication)) return 0;
    uint64_t app = r_msg2_main(UIApplication, "sharedApplication", 0, 0, 0, 0);
    return r_is_objc_ptr(app) ? r_msg2_main(app, "keyWindow", 0, 0, 0, 0) : 0;
}

bool ccstatus_apply_in_session(void)
{
    printf("[CCSTATUS] apply\n");
    if (r_is_objc_ptr(gCCStatusLabel)) return true;
    uint64_t win = ccstatus_key_window();
    uint64_t UILabel = r_class("UILabel");
    if (!r_is_objc_ptr(win) || !r_is_objc_ptr(UILabel)) return false;
    uint64_t label = r_msg2_main(UILabel, "alloc", 0, 0, 0, 0);
    CCStatusRect frame = { 24, 70, 260, 24 };
    label = r_msg2_main_raw(label, "initWithFrame:", &frame, sizeof(frame), NULL, 0, NULL, 0, NULL, 0);
    if (!r_is_objc_ptr(label)) return false;
    uint64_t str = r_nsstr_retained("CCStatus  Wi-Fi: Active  Local IP: --");
    if (r_is_objc_ptr(str)) {
        r_msg2_main(label, "setText:", str, 0, 0, 0);
        r_msg2_main(str, "release", 0, 0, 0, 0);
    }
    r_msg2_main(win, "addSubview:", label, 0, 0, 0);
    gCCStatusLabel = label;
    return true;
}

bool ccstatus_stop_in_session(void)
{
    printf("[CCSTATUS] stop\n");
    if (r_is_objc_ptr(gCCStatusLabel)) r_msg2_main(gCCStatusLabel, "removeFromSuperview", 0, 0, 0, 0);
    gCCStatusLabel = 0;
    return true;
}

void ccstatus_forget_remote_state(void) { gCCStatusLabel = 0; }
