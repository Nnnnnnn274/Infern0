//
//  powercuff.m
//

#import "powercuff.h"
#import "remote_objc.h"
#import "../TaskRop/RemoteCall.h"
#import <stdio.h>
#import <string.h>
#import <unistd.h>
#import "../LogTextView.h"

static bool valid_level(const char *level) {
    if (!level) return false;
    return (!strcmp(level, "off") || !strcmp(level, "nominal") ||
            !strcmp(level, "light") || !strcmp(level, "moderate") ||
            !strcmp(level, "heavy"));
}

bool powercuff_apply(const char *level)
{
    if (!valid_level(level)) {
        printf("[POWERCUFF] invalid level '%s', defaulting to heavy\n", level ? level : "(null)");
        level = "heavy";
    }
    printf("[POWERCUFF] === entry === target=%s\n", level);

    if (init_remote_call("thermalmonitord", false) != 0) {
        printf("[POWERCUFF] init_remote_call(thermalmonitord) failed\n");
        return false;
    }

    bool ok = false;
    do {
        uint64_t cls = r_class("CPMSHelper");
        if (!cls) { printf("[POWERCUFF] CPMSHelper class missing - wrong process?\n"); break; }
        printf("[POWERCUFF] CPMSHelper=0x%llx\n", cls);
        usleep(50000);

        uint64_t helper = r_msg2(cls, "sharedInstance", 0, 0, 0, 0);
        if (!helper) { printf("[POWERCUFF] +sharedInstance returned nil\n"); break; }
        printf("[POWERCUFF] helper=0x%llx\n", helper);
        usleep(50000);

        uint64_t product = r_ivar_value(helper, "productObj");
        if (!product) { printf("[POWERCUFF] productObj ivar is nil - daemon not done with initProduct: yet\n"); break; }
        printf("[POWERCUFF] product=0x%llx\n", product);
        usleep(50000);

        if (!r_responds(product, "putDeviceInThermalSimulationMode:")) {
            printf("[POWERCUFF] product does not respond to putDeviceInThermalSimulationMode:\n");
            break;
        }
        usleep(50000);

        uint64_t modeStr = r_cfstr(level);
        if (!modeStr) { printf("[POWERCUFF] CFString create failed\n"); break; }

        printf("[POWERCUFF] -[CommonProduct putDeviceInThermalSimulationMode:'%s']\n", level);
        r_msg2(product, "putDeviceInThermalSimulationMode:", modeStr, 0, 0, 0);
        printf("[POWERCUFF] applied: %s\n", level);
        ok = true;
    } while (0);

    destroy_remote_call();
    return ok;
}
