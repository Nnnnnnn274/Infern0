#import "hapticcc.h"
#import "../remote_objc.h"
#import "../../TaskRop/RemoteCall.h"

#import <Foundation/Foundation.h>

static bool gHapticCCApplied = false;

bool hapticcc_apply_in_session(void)
{
    printf("[HAPTICCC] apply\n");
    uint64_t Generator = r_class("UIImpactFeedbackGenerator");
    if (!r_is_objc_ptr(Generator)) return false;
    uint64_t gen = r_msg2_main(Generator, "alloc", 0, 0, 0, 0);
    uint64_t style = 1;
    gen = r_msg2_main(gen, "initWithStyle:", style, 0, 0, 0);
    if (!r_is_objc_ptr(gen)) return false;
    r_msg2_main(gen, "prepare", 0, 0, 0, 0);
    r_msg2_main(gen, "impactOccurred", 0, 0, 0, 0);
    r_msg2_main(gen, "release", 0, 0, 0, 0);
    gHapticCCApplied = true;
    return true;
}

bool hapticcc_stop_in_session(void)
{
    printf("[HAPTICCC] stop\n");
    gHapticCCApplied = false;
    return true;
}

void hapticcc_forget_remote_state(void) { gHapticCCApplied = false; }
