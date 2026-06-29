#import "pancake.h"
#import "../remote_objc.h"
#import "../../TaskRop/RemoteCall.h"
#import "../../LogTextView.h"

#import <Foundation/Foundation.h>
#import <math.h>

static bool gPcApplied = false;

bool pancake_apply_in_session(void)
{
    printf("[PANCAKE] apply\n");

    uint64_t UIApplication = r_class("UIApplication");
    if (!r_is_objc_ptr(UIApplication)) return false;
    uint64_t app = r_msg2_main(UIApplication, "sharedApplication", 0, 0, 0, 0);
    if (!r_is_objc_ptr(app)) return false;

    uint64_t windows = r_msg2_main(app, "windows", 0, 0, 0, 0);
    if (!r_is_objc_ptr(windows)) return false;
    uint64_t winCount = r_msg2_main(windows, "count", 0, 0, 0, 0);
    if (winCount > 32) winCount = 32;

    uint64_t keyWindow = 0;
    for (uint64_t i = 0; i < winCount; i++) {
        uint64_t win = r_msg2_main(windows, "objectAtIndex:", i, 0, 0, 0);
        if (!r_is_objc_ptr(win)) continue;
        uint64_t isKey = r_msg2_main(win, "isKeyWindow", 0, 0, 0, 0);
        if (isKey & 0xff) {
            keyWindow = win;
            break;
        }
    }
    if (!r_is_objc_ptr(keyWindow)) {
        keyWindow = r_msg2_main(app, "keyWindow", 0, 0, 0, 0);
    }
    if (!r_is_objc_ptr(keyWindow)) return false;

    uint64_t UIScreenEdgePanGestureRecognizer = r_class("UIScreenEdgePanGestureRecognizer");
    if (!r_is_objc_ptr(UIScreenEdgePanGestureRecognizer)) return false;

    uint64_t edgeGesture = r_msg2_main(UIScreenEdgePanGestureRecognizer, "alloc", 0, 0, 0, 0);
    if (!r_is_objc_ptr(edgeGesture)) return false;
    edgeGesture = r_msg2_main(edgeGesture, "init", 0, 0, 0, 0);
    if (!r_is_objc_ptr(edgeGesture)) return false;

    uint64_t target = app;
    uint64_t backSel = r_sel("_handleBackNavigationFromEdgeGesture:");
    if (!backSel) return false;

    r_msg2_main(edgeGesture, "addTarget:action:", target, backSel, 0, 0);

    uint64_t edges = 0; // UIRectEdgeAll
    edges = 0xF;
    r_msg2_main(edgeGesture, "setEdges:", edges, 0, 0, 0);

    r_msg2_main(keyWindow, "addGestureRecognizer:", edgeGesture, 0, 0, 0);
    printf("[PANCAKE] added edge pan gesture to keyWindow 0x%llx\n", keyWindow);

    gPcApplied = true;
    return true;
}

bool pancake_stop_in_session(void)
{
    printf("[PANCAKE] stop\n");
    gPcApplied = false;
    return true;
}

void pancake_forget_remote_state(void)
{
    gPcApplied = false;
}
