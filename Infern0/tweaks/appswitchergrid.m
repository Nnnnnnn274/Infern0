//
//  appswitchergrid.m
//  Cyanide
//

#import "appswitchergrid.h"
#import "remote_objc.h"
#import "../LogTextView.h"
#import <stdio.h>
#import <string.h>

typedef struct {
    uint64_t object;
    uint64_t responseNumber;
    uint64_t dampingNumber;
} ASGBehaviorSnapshot;

static uint64_t gASGSettings = 0;
static int64_t gASGOriginalStyle = 0;
static bool gASGOriginalStyleValid = false;
static uint64_t gASGOriginalGridValues[5] = {0};
static ASGBehaviorSnapshot gASGBehaviors[3] = {0};
static size_t gASGBehaviorCount = 0;

static const char *kASGGridKeys[] = {
    "gridSwitcherPageScale",
    "gridSwitcherHorizontalInterpageSpacingPortrait",
    "gridSwitcherVerticalNaturalSpacingPortrait",
    "gridSwitcherHorizontalInterpageSpacingLandscape",
    "gridSwitcherVerticalNaturalSpacingLandscape",
};

static void asg_release(uint64_t object)
{
    if (r_is_objc_ptr(object)) r_msg2_main(object, "release", 0, 0, 0, 0);
}

static uint64_t asg_value_for_key(uint64_t object, const char *key)
{
    if (!r_is_objc_ptr(object) || !key || !r_responds_main(object, key) ||
        !r_responds_main(object, "valueForKey:")) return 0;
    uint64_t keyString = r_nsstr_retained(key);
    if (!r_is_objc_ptr(keyString)) return 0;
    uint64_t value = r_msg2_main(object, "valueForKey:", keyString, 0, 0, 0);
    asg_release(keyString);
    return value;
}

static uint64_t asg_retained_value_for_key(uint64_t object, const char *key)
{
    uint64_t value = asg_value_for_key(object, key);
    if (r_is_objc_ptr(value)) r_msg2_main(value, "retain", 0, 0, 0, 0);
    return value;
}

static bool asg_set_value_for_key(uint64_t object, const char *key, uint64_t value)
{
    if (!r_is_objc_ptr(object) || !r_is_objc_ptr(value) || !key ||
        !r_responds_main(object, key) || !r_responds_main(object, "setValue:forKey:")) return false;
    uint64_t keyString = r_nsstr_retained(key);
    if (!r_is_objc_ptr(keyString)) return false;
    r_msg2_main(object, "setValue:forKey:", value, keyString, 0, 0);
    asg_release(keyString);
    return true;
}

static uint64_t asg_number_with_double(double value)
{
    uint64_t cls = r_class("NSNumber");
    if (!r_is_objc_ptr(cls)) return 0;
    return r_msg2_main_raw(cls, "numberWithDouble:",
                           &value, sizeof(value), NULL, 0, NULL, 0, NULL, 0);
}

static bool asg_set_double(uint64_t object, const char *key, double value)
{
    uint64_t number = asg_number_with_double(value);
    return r_is_objc_ptr(number) && asg_set_value_for_key(object, key, number);
}

static uint64_t asg_direct_or_ivar(uint64_t object, const char *selector, const char *ivar)
{
    if (!r_is_objc_ptr(object)) return 0;
    uint64_t value = r_responds_main(object, selector)
        ? r_msg2_main(object, selector, 0, 0, 0, 0) : 0;
    if (!r_is_objc_ptr(value) && ivar) value = r_ivar_value(object, ivar);
    return r_is_objc_ptr(value) ? value : 0;
}

static uint64_t asg_find_settings(void)
{
    const char *classes[] = {
        "SBUIController",
        "SBMainSwitcherControllerCoordinator",
        "SBAppSwitcherController",
    };
    const char *ivars[] = { "_switcherSettings", "_settings", "_switcherSettings" };
    uint64_t settingsClass = r_class("SBAppSwitcherSettings");

    for (size_t i = 0; i < sizeof(classes) / sizeof(classes[0]); i++) {
        uint64_t cls = r_class(classes[i]);
        if (!r_is_objc_ptr(cls) || !r_responds_main(cls, "sharedInstance")) continue;
        uint64_t owner = r_msg2_main(cls, "sharedInstance", 0, 0, 0, 0);
        uint64_t candidate = asg_direct_or_ivar(owner, "switcherSettings", ivars[i]);
        if (!r_is_objc_ptr(candidate)) continue;
        if (r_is_objc_ptr(settingsClass) &&
            !(r_msg2_main(candidate, "isKindOfClass:", settingsClass, 0, 0, 0) & 0xff)) continue;
        printf("[ASG] settings resolved through %s object=0x%llx\n", classes[i], candidate);
        return candidate;
    }
    return 0;
}

static void asg_capture_originals(uint64_t settings)
{
    if (gASGSettings == settings && gASGOriginalStyleValid) return;
    appswitchergrid_forget_remote_state();
    gASGSettings = settings;
    gASGOriginalStyle = (int64_t)r_msg2_main(settings, "switcherStyle", 0, 0, 0, 0);
    gASGOriginalStyleValid = true;
    for (size_t i = 0; i < sizeof(kASGGridKeys) / sizeof(kASGGridKeys[0]); i++) {
        gASGOriginalGridValues[i] = asg_retained_value_for_key(settings, kASGGridKeys[i]);
    }

    uint64_t animations = asg_direct_or_ivar(settings, "animationSettings", "_animationSettings");
    const char *behaviorSelectors[] = {
        "toggleAppSwitcherSettings",
        "launchAppFromSwitcherSettings",
        "switcherToHomeSettings",
    };
    for (size_t i = 0; i < sizeof(behaviorSelectors) / sizeof(behaviorSelectors[0]); i++) {
        uint64_t behavior = asg_direct_or_ivar(animations, behaviorSelectors[i], NULL);
        if (!r_is_objc_ptr(behavior)) continue;
        ASGBehaviorSnapshot *snapshot = &gASGBehaviors[gASGBehaviorCount++];
        snapshot->object = behavior;
        snapshot->responseNumber = asg_retained_value_for_key(behavior, "response");
        snapshot->dampingNumber = asg_retained_value_for_key(behavior, "dampingRatio");
    }
    printf("[ASG] captured stock style=%lld gridValues=%d animationBehaviors=%zu\n",
           gASGOriginalStyle, 5, gASGBehaviorCount);
}

static void asg_restore_animations(void)
{
    for (size_t i = 0; i < gASGBehaviorCount; i++) {
        ASGBehaviorSnapshot *snapshot = &gASGBehaviors[i];
        if (r_is_objc_ptr(snapshot->responseNumber))
            asg_set_value_for_key(snapshot->object, "response", snapshot->responseNumber);
        if (r_is_objc_ptr(snapshot->dampingNumber))
            asg_set_value_for_key(snapshot->object, "dampingRatio", snapshot->dampingNumber);
    }
}

static void asg_animation_values(AppSwitcherAnimationMode mode, double *response, double *damping)
{
    switch (mode) {
        case AppSwitcherAnimationSnappy: *response = 0.22; *damping = 1.00; break;
        case AppSwitcherAnimationSmooth: *response = 0.46; *damping = 1.00; break;
        case AppSwitcherAnimationBouncy: *response = 0.38; *damping = 0.72; break;
        default: *response = 0.0; *damping = 0.0; break;
    }
}

static bool asg_apply_animation(AppSwitcherAnimationMode mode)
{
    asg_restore_animations();
    if (mode == AppSwitcherAnimationSystem) return true;
    if (gASGBehaviorCount == 0) {
        log_user("[ASG] Animation settings are unavailable on this iOS build; layout was left active with System animation.\n");
        return false;
    }
    double response = 0.0, damping = 0.0;
    asg_animation_values(mode, &response, &damping);
    size_t changed = 0;
    for (size_t i = 0; i < gASGBehaviorCount; i++) {
        bool responseOK = asg_set_double(gASGBehaviors[i].object, "response", response);
        bool dampingOK = asg_set_double(gASGBehaviors[i].object, "dampingRatio", damping);
        if (responseOK && dampingOK) changed++;
    }
    printf("[ASG] animation preset=%d response=%.2f damping=%.2f changed=%zu/%zu\n",
           mode, response, damping, changed, gASGBehaviorCount);
    return changed == gASGBehaviorCount;
}

static void asg_grid_values(AppSwitcherLayoutMode layout, double values[5])
{
    switch (layout) {
        case AppSwitcherLayoutGridCompact:
            values[0] = 0.30; values[1] = 14.0; values[2] = 18.0; values[3] = 18.0; values[4] = 14.0; break;
        case AppSwitcherLayoutGridLarge:
            values[0] = 0.46; values[1] = 24.0; values[2] = 28.0; values[3] = 28.0; values[4] = 20.0; break;
        default:
            values[0] = 0.38; values[1] = 18.0; values[2] = 22.0; values[3] = 22.0; values[4] = 18.0; break;
    }
}

bool appswitchergrid_apply_config_in_session(AppSwitcherGridConfig config)
{
    if (config.layout < AppSwitcherLayoutAutomatic || config.layout > AppSwitcherLayoutGridLarge)
        config.layout = AppSwitcherLayoutGridBalanced;
    if (config.animation < AppSwitcherAnimationSystem || config.animation > AppSwitcherAnimationBouncy)
        config.animation = AppSwitcherAnimationSystem;

    uint64_t settings = asg_find_settings();
    if (!r_is_objc_ptr(settings) || !r_responds_main(settings, "switcherStyle") ||
        !r_responds_main(settings, "setSwitcherStyle:")) {
        printf("[ASG] compatible SBAppSwitcherSettings object was not found\n");
        log_user("[ASG] This iOS build did not expose a compatible live App Switcher settings object. Nothing was changed.\n");
        return false;
    }

    asg_capture_originals(settings);
    int64_t style = config.layout == AppSwitcherLayoutDeck ? 1 :
                    config.layout == AppSwitcherLayoutAutomatic ? 0 : 2;
    r_msg2_main(settings, "setSwitcherStyle:", (uint64_t)style, 0, 0, 0);

    bool layoutOK = true;
    if (style == 2) {
        double values[5] = {0};
        asg_grid_values(config.layout, values);
        for (size_t i = 0; i < 5; i++) {
            bool valueOK = asg_set_double(settings, kASGGridKeys[i], values[i]);
            printf("[ASG] layout key=%s value=%.2f result=%d\n", kASGGridKeys[i], values[i], valueOK);
            layoutOK = valueOK && layoutOK;
        }
    }

    bool animationOK = asg_apply_animation(config.animation);
    printf("[ASG] apply layout=%d style=%lld animation=%d layoutOK=%d animationOK=%d\n",
           config.layout, style, config.animation, layoutOK, animationOK);
    log_user("[ASG] Applied layout mode %d (SpringBoard style %lld) and animation mode %d. Layout=%s animation=%s.\n",
             config.layout, style, config.animation,
             layoutOK ? "OK" : "partial", animationOK ? "OK" : "System fallback");
    return layoutOK;
}

bool appswitchergrid_apply_in_session(void)
{
    AppSwitcherGridConfig config = {
        .layout = AppSwitcherLayoutGridBalanced,
        .animation = AppSwitcherAnimationSystem,
    };
    return appswitchergrid_apply_config_in_session(config);
}

bool appswitchergrid_stop_in_session(void)
{
    if (!r_is_objc_ptr(gASGSettings) || !gASGOriginalStyleValid) {
        return false;
    }
    r_msg2_main(gASGSettings, "setSwitcherStyle:", (uint64_t)gASGOriginalStyle, 0, 0, 0);
    size_t restored = 0;
    for (size_t i = 0; i < 5; i++) {
        if (r_is_objc_ptr(gASGOriginalGridValues[i]) &&
            asg_set_value_for_key(gASGSettings, kASGGridKeys[i], gASGOriginalGridValues[i])) restored++;
    }
    asg_restore_animations();
    printf("[ASG] restored stock style=%lld gridValues=%zu/5 animationBehaviors=%zu\n",
           gASGOriginalStyle, restored, gASGBehaviorCount);
    log_user("[ASG] Restored the stock App Switcher layout and animation values for this SpringBoard session.\n");
    return true;
}

void appswitchergrid_forget_remote_state(void)
{
    // This function is also called after SpringBoard exits. Never message or
    // release cached remote objects here: their addresses may belong to the
    // dead task and touching them can produce an invalid-VM retry loop. The
    // handful of retained NSNumber snapshots die with their SpringBoard task.
    for (size_t i = 0; i < 5; i++) {
        gASGOriginalGridValues[i] = 0;
    }
    memset(gASGBehaviors, 0, sizeof(gASGBehaviors));
    gASGBehaviorCount = 0;
    gASGSettings = 0;
    gASGOriginalStyle = 0;
    gASGOriginalStyleValid = false;
}
