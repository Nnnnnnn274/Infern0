#import "fakeclockup.h"
#import "../remote_objc.h"
#import "../../TaskRop/RemoteCall.h"
#import "../../LogTextView.h"

#import <Foundation/Foundation.h>
#import <math.h>

static bool gFcuApplied = false;
static double gFcuMultiplier = 1.0;

bool fakeclockup_apply_in_session(double speedMultiplier)
{
    printf("[FAKECLOCKUP] apply multiplier=%.2f\n", speedMultiplier);

    if (speedMultiplier <= 0.0) speedMultiplier = 1.0;

    uint64_t CALayer = r_class("CALayer");
    if (!r_is_objc_ptr(CALayer)) return false;

    uint64_t animDuration = r_sel("animationDuration");
    uint64_t cls = r_dlsym_call(R_TIMEOUT, "object_getClass", CALayer, 0, 0, 0, 0, 0, 0, 0);
    if (!r_is_objc_ptr(cls)) return false;

    double newDuration = 1.0 / speedMultiplier;
    double zero = 0.0;

    r_msg2_main_raw(CALayer, "setValue:forKey:",
                    &newDuration, sizeof(newDuration),
                    NULL, 0, NULL, 0, NULL, 0);

    uint64_t CAAnimation = r_class("CAAnimation");
    if (r_is_objc_ptr(CAAnimation)) {
        double duration = 1.0 / speedMultiplier;
        r_msg2_main_raw(CAAnimation, "setValue:forKey:",
                        &duration, sizeof(duration),
                        NULL, 0, NULL, 0, NULL, 0);
    }

    gFcuMultiplier = speedMultiplier;
    gFcuApplied = true;
    printf("[FAKECLOCKUP] set speed multiplier %.2f\n", speedMultiplier);
    return true;
}

bool fakeclockup_stop_in_session(void)
{
    printf("[FAKECLOCKUP] stop\n");

    uint64_t CALayer = r_class("CALayer");
    if (r_is_objc_ptr(CALayer)) {
        double one = 1.0;
        r_msg2_main_raw(CALayer, "setValue:forKey:",
                        &one, sizeof(one), NULL, 0, NULL, 0, NULL, 0);
    }

    gFcuApplied = false;
    gFcuMultiplier = 1.0;
    return true;
}

void fakeclockup_forget_remote_state(void)
{
    gFcuApplied = false;
    gFcuMultiplier = 1.0;
}
