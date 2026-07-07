#import "betterccicons.h"
#import "../remote_objc.h"
#import "../../TaskRop/RemoteCall.h"

#import <Foundation/Foundation.h>
#import <string.h>

static bool gBetterCCIconsApplied = false;

static uint64_t betterccicons_key_window(void)
{
    uint64_t UIApplication = r_class("UIApplication");
    if (!r_is_objc_ptr(UIApplication)) return 0;
    uint64_t app = r_msg2_main(UIApplication, "sharedApplication", 0, 0, 0, 0);
    return r_is_objc_ptr(app) ? r_msg2_main(app, "keyWindow", 0, 0, 0, 0) : 0;
}

static void betterccicons_scan(uint64_t parent, double radius, int depth, int *hits)
{
    if (!r_is_objc_ptr(parent) || depth > 12) return;
    uint64_t layer = r_msg2_main(parent, "layer", 0, 0, 0, 0);
    if (r_is_objc_ptr(layer)) {
        r_msg2_main_raw(layer, "setCornerRadius:", &radius, sizeof(radius), NULL, 0, NULL, 0, NULL, 0);
        r_msg2_main(layer, "setMasksToBounds:", 1, 0, 0, 0);
        if (hits) (*hits)++;
    }
    uint64_t subviews = r_msg2_main(parent, "subviews", 0, 0, 0, 0);
    if (!r_is_objc_ptr(subviews)) return;
    uint64_t count = r_msg2_main(subviews, "count", 0, 0, 0, 0);
    if (count > 120) count = 120;
    for (uint64_t i = 0; i < count; i++) betterccicons_scan(r_msg2_main(subviews, "objectAtIndex:", i, 0, 0, 0), radius, depth + 1, hits);
}

bool betterccicons_apply_in_session(void)
{
    printf("[BETTERCCICONS] apply\n");
    uint64_t win = betterccicons_key_window();
    if (!r_is_objc_ptr(win)) return false;
    int hits = 0;
    betterccicons_scan(win, 22.0, 0, &hits);
    gBetterCCIconsApplied = hits > 0;
    return gBetterCCIconsApplied;
}

bool betterccicons_stop_in_session(void)
{
    printf("[BETTERCCICONS] stop\n");
    uint64_t win = betterccicons_key_window();
    int hits = 0;
    if (r_is_objc_ptr(win)) betterccicons_scan(win, 12.0, 0, &hits);
    gBetterCCIconsApplied = false;
    return true;
}

void betterccicons_forget_remote_state(void) { gBetterCCIconsApplied = false; }
