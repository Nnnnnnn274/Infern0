#import "betterccxi.h"
#import "../remote_objc.h"
#import "../../TaskRop/RemoteCall.h"

#import <Foundation/Foundation.h>
#import <string.h>

static bool gBetterCCXIApplied = false;

static uint64_t betterccxi_key_window(void)
{
    uint64_t UIApplication = r_class("UIApplication");
    if (!r_is_objc_ptr(UIApplication)) return 0;
    uint64_t app = r_msg2_main(UIApplication, "sharedApplication", 0, 0, 0, 0);
    return r_is_objc_ptr(app) ? r_msg2_main(app, "keyWindow", 0, 0, 0, 0) : 0;
}

static void betterccxi_scan(uint64_t parent, double scale, int depth, int *hits)
{
    if (!r_is_objc_ptr(parent) || depth > 12) return;
    uint64_t layer = r_msg2_main(parent, "layer", 0, 0, 0, 0);
    if (r_is_objc_ptr(layer)) {
        double z = scale > 1.0 ? 4.0 : 0.0;
        r_msg2_main_raw(layer, "setZPosition:", &z, sizeof(z), NULL, 0, NULL, 0, NULL, 0);
    }
    uint64_t subviews = r_msg2_main(parent, "subviews", 0, 0, 0, 0);
    if (!r_is_objc_ptr(subviews)) return;
    uint64_t count = r_msg2_main(subviews, "count", 0, 0, 0, 0);
    if (count > 80) count = 80;
    for (uint64_t i = 0; i < count; i++) {
        betterccxi_scan(r_msg2_main(subviews, "objectAtIndex:", i, 0, 0, 0), scale, depth + 1, hits);
    }
    if (hits) (*hits)++;
}

bool betterccxi_apply_in_session(void)
{
    printf("[BETTERCCXI] apply\n");
    uint64_t win = betterccxi_key_window();
    if (!r_is_objc_ptr(win)) return false;
    int hits = 0;
    betterccxi_scan(win, 1.0, 0, &hits);
    gBetterCCXIApplied = hits > 0;
    return gBetterCCXIApplied;
}

bool betterccxi_stop_in_session(void)
{
    printf("[BETTERCCXI] stop\n");
    gBetterCCXIApplied = false;
    return true;
}

void betterccxi_forget_remote_state(void) { gBetterCCXIApplied = false; }
