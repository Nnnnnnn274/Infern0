#import "securecc.h"
#import "../remote_objc.h"
#import "../../TaskRop/RemoteCall.h"

#import <Foundation/Foundation.h>

typedef struct { double x; double y; double width; double height; } SecureCCRect;

static uint64_t gSecureCCBanner = 0;

static uint64_t securecc_key_window(void)
{
    uint64_t UIApplication = r_class("UIApplication");
    if (!r_is_objc_ptr(UIApplication)) return 0;
    uint64_t app = r_msg2_main(UIApplication, "sharedApplication", 0, 0, 0, 0);
    return r_is_objc_ptr(app) ? r_msg2_main(app, "keyWindow", 0, 0, 0, 0) : 0;
}

bool securecc_apply_in_session(void)
{
    printf("[SECURECC] apply\n");
    if (r_is_objc_ptr(gSecureCCBanner)) return true;
    uint64_t win = securecc_key_window();
    uint64_t UILabel = r_class("UILabel");
    if (!r_is_objc_ptr(win) || !r_is_objc_ptr(UILabel)) return false;
    uint64_t label = r_msg2_main(UILabel, "alloc", 0, 0, 0, 0);
    SecureCCRect frame = { 24, 96, 220, 28 };
    label = r_msg2_main_raw(label, "initWithFrame:", &frame, sizeof(frame), NULL, 0, NULL, 0, NULL, 0);
    if (!r_is_objc_ptr(label)) return false;
    uint64_t str = r_nsstr_retained("SecureCC armed");
    if (r_is_objc_ptr(str)) {
        r_msg2_main(label, "setText:", str, 0, 0, 0);
        r_msg2_main(str, "release", 0, 0, 0, 0);
    }
    r_msg2_main(win, "addSubview:", label, 0, 0, 0);
    gSecureCCBanner = label;
    return true;
}

bool securecc_stop_in_session(void)
{
    printf("[SECURECC] stop\n");
    if (r_is_objc_ptr(gSecureCCBanner)) r_msg2_main(gSecureCCBanner, "removeFromSuperview", 0, 0, 0, 0);
    gSecureCCBanner = 0;
    return true;
}

void securecc_forget_remote_state(void) { gSecureCCBanner = 0; }
