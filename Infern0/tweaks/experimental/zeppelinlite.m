#import "zeppelinlite.h"
#import "../remote_objc.h"
#import "../../TaskRop/RemoteCall.h"
#import "../../LogTextView.h"

#import <Foundation/Foundation.h>
#import <math.h>

static bool gZepApplied = false;

bool zeppelinlite_apply_in_session(const char *carrierText)
{
    printf("[ZEPPELIN] apply text=%s\n", carrierText ?: "nil");

    uint64_t UIApplication = r_class("UIApplication");
    if (!r_is_objc_ptr(UIApplication)) return false;
    uint64_t app = r_msg2_main(UIApplication, "sharedApplication", 0, 0, 0, 0);
    if (!r_is_objc_ptr(app)) return false;

    uint64_t statusBar = r_msg2_main(app, "statusBar", 0, 0, 0, 0);
    if (!r_is_objc_ptr(statusBar)) {
        statusBar = r_ivar_value(app, "_statusBar");
    }
    if (!r_is_objc_ptr(statusBar)) return false;

    uint64_t carrierItem = r_msg2_main(statusBar, "carrierItem", 0, 0, 0, 0);
    if (!r_is_objc_ptr(carrierItem)) {
        carrierItem = r_ivar_value(statusBar, "_carrierItem");
    }
    if (!r_is_objc_ptr(carrierItem)) return false;

    if (carrierText && carrierText[0]) {
        uint64_t textStr = r_alloc_str(carrierText);
        if (!textStr) return false;
        uint64_t nsStr = r_msg2_main(r_class("NSString"), "stringWithUTF8String:", textStr, 0, 0, 0);
        r_free(textStr);
        if (!r_is_objc_ptr(nsStr)) return false;
        r_msg2_main(carrierItem, "setText:", nsStr, 0, 0, 0);
        printf("[ZEPPELIN] set carrier text\n");
    }

    gZepApplied = true;
    return true;
}

bool zeppelinlite_stop_in_session(void)
{
    printf("[ZEPPELIN] stop\n");
    gZepApplied = false;
    return true;
}

void zeppelinlite_forget_remote_state(void)
{
    gZepApplied = false;
}
