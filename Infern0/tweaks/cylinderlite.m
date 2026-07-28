//
//  cylinderlite.m
//  Cyanide
//

#import "cylinderlite.h"
#import "remote_objc.h"
#import "sb_walk.h"
#import "../LogTextView.h"

#import <Foundation/Foundation.h>
#import <float.h>
#import <math.h>
#import <stdio.h>
#import <string.h>

typedef struct { double x, y; } CLPoint;
typedef struct { double width, height; } CLSize;
typedef struct { double x, y, width, height; } CLRect;
typedef struct { double a, b, c, d, tx, ty; } CLTransform;

static bool s_cylinderlite_active = false;
static CylinderLiteEffect s_cylinderlite_effect = CylinderLiteEffectZoomFadeOut;
static int s_cylinderlite_intensity_pct = 100;
static int s_cylinderlite_opacity_pct = 100;
static bool s_cylinderlite_follow_gesture = true;
static int s_cylinderlite_one_shot_duration_ms = 520;
static int s_cylinderlite_last_page = -9999;
static uint64_t s_cylinderlite_last_list = 0;
static uint64_t s_cylinderlite_scroll = 0;
static uint64_t s_cylinderlite_pan = 0;
static uint64_t s_cylinderlite_lists[16] = {0};
static double s_cylinderlite_list_x[16] = {0};
static int s_cylinderlite_list_count = 0;
static double s_cylinderlite_page_width = 0.0;
static uint64_t s_cylinderlite_enter_animations[2] = {0};
static uint64_t s_cylinderlite_exit_animations[2] = {0};
static uint64_t s_cylinderlite_animation_key = 0;
static bool s_cylinderlite_gesture_animating = false;
static int s_cylinderlite_gesture_from_page = -1;
static int s_cylinderlite_gesture_to_page = -1;
static bool s_cylinderlite_finish_animating = false;
static int s_cylinderlite_finish_from_page = -1;
static int s_cylinderlite_finish_to_page = -1;
static double s_cylinderlite_finish_progress = 0.0;
static double s_cylinderlite_finish_target = 0.0;
static unsigned int s_cylinderlite_idle_ticks = 0;
static uint64_t s_cylinderlite_one_shot_cleanup_from_list = 0;
static uint64_t s_cylinderlite_one_shot_cleanup_to_list = 0;
static unsigned int s_cylinderlite_one_shot_cleanup_ticks = 0;

static NSString * const kCylinderLiteAnimationKey = @"com.darksword.cylinderlite.page";

static int cl_clamp_int(int value, int minValue, int maxValue)
{
    if (value < minValue) return minValue;
    if (value > maxValue) return maxValue;
    return value;
}

static double cl_fraction_from_pct(int pct, double minValue, double maxValue)
{
    double value = (double)cl_clamp_int(pct, 0, 100) / 100.0;
    if (value < minValue) value = minValue;
    if (value > maxValue) value = maxValue;
    return value;
}

static uint64_t cl_safe_msg(uint64_t object, const char *selector,
                            uint64_t a0, uint64_t a1, uint64_t a2, uint64_t a3)
{
    if (!r_is_objc_ptr(object) || !selector || !r_responds_main(object, selector)) return 0;
    return r_msg2_main(object, selector, a0, a1, a2, a3);
}

static bool cl_get_point(uint64_t object, const char *selector, CLPoint *out)
{
    if (!r_is_objc_ptr(object) || !selector || !out ||
        !r_responds_main(object, selector)) return false;
    memset(out, 0, sizeof(*out));
    return r_msg2_main_struct_ret(object, selector, out, sizeof(*out),
                                  NULL, 0, NULL, 0, NULL, 0, NULL, 0);
}

static bool cl_get_point_fast(uint64_t object, const char *selector, CLPoint *out)
{
    if (!object || !selector || !out) return false;
    memset(out, 0, sizeof(*out));
    return r_msg2_main_struct_ret(object, selector, out, sizeof(*out),
                                  NULL, 0, NULL, 0, NULL, 0, NULL, 0);
}

static bool cl_get_size(uint64_t object, const char *selector, CLSize *out)
{
    if (!r_is_objc_ptr(object) || !selector || !out ||
        !r_responds_main(object, selector)) return false;
    memset(out, 0, sizeof(*out));
    return r_msg2_main_struct_ret(object, selector, out, sizeof(*out),
                                  NULL, 0, NULL, 0, NULL, 0, NULL, 0);
}

static bool cl_get_rect(uint64_t object, const char *selector, CLRect *out)
{
    if (!r_is_objc_ptr(object) || !selector || !out ||
        !r_responds_main(object, selector)) return false;
    memset(out, 0, sizeof(*out));
    return r_msg2_main_struct_ret(object, selector, out, sizeof(*out),
                                  NULL, 0, NULL, 0, NULL, 0, NULL, 0);
}

static bool cl_get_bool(uint64_t object, const char *selector)
{
    if (!r_is_objc_ptr(object) || !selector ||
        !r_responds_main(object, selector)) return false;
    return r_msg2_main(object, selector, 0, 0, 0, 0) != 0;
}

static uint64_t cl_nsnumber_double(double value)
{
    uint64_t numberClass = r_class("NSNumber");
    if (!r_is_objc_ptr(numberClass)) return 0;
    return r_msg2_main_raw(numberClass, "numberWithDouble:",
                           &value, sizeof(value),
                           NULL, 0, NULL, 0, NULL, 0);
}

static uint64_t cl_basic_animation(const char *keyPath,
                                   double fromValue,
                                   double toValue,
                                   double duration)
{
    uint64_t animationClass = r_class("CABasicAnimation");
    if (!r_is_objc_ptr(animationClass)) return 0;

    uint64_t keyPathString = r_nsstr_retained(keyPath);
    if (!r_is_objc_ptr(keyPathString)) return 0;
    uint64_t animation = r_msg2_main(animationClass, "animationWithKeyPath:",
                                     keyPathString, 0, 0, 0);
    r_msg2(keyPathString, "release", 0, 0, 0, 0);
    if (!r_is_objc_ptr(animation)) return 0;

    uint64_t fromNumber = cl_nsnumber_double(fromValue);
    uint64_t toNumber = cl_nsnumber_double(toValue);
    if (r_is_objc_ptr(fromNumber)) r_msg2_main(animation, "setFromValue:", fromNumber, 0, 0, 0);
    if (r_is_objc_ptr(toNumber)) r_msg2_main(animation, "setToValue:", toNumber, 0, 0, 0);
    r_msg2_main_raw(animation, "setDuration:",
                    &duration, sizeof(duration),
                    NULL, 0, NULL, 0, NULL, 0);
    return animation;
}

static void cl_add_basic_animation(uint64_t animations,
                                   const char *keyPath,
                                   double fromValue,
                                   double toValue,
                                   double duration)
{
    if (!r_is_objc_ptr(animations) || !keyPath) return;
    uint64_t animation = cl_basic_animation(keyPath, fromValue, toValue, duration);
    if (r_is_objc_ptr(animation)) r_msg2_main(animations, "addObject:", animation, 0, 0, 0);
}

static void cl_add_effect_animation(uint64_t animations,
                                    const char *keyPath,
                                    double amount,
                                    double duration,
                                    bool entering)
{
    if (entering) {
        cl_add_basic_animation(animations, keyPath, amount, 0.0, duration);
    } else {
        cl_add_basic_animation(animations, keyPath, 0.0, -amount, duration);
    }
}

static void cl_add_opacity_animation(uint64_t animations,
                                     double minOpacity,
                                     double duration,
                                     bool entering)
{
    cl_add_basic_animation(animations, "opacity",
                           entering ? minOpacity : 1.0,
                           entering ? 1.0 : minOpacity,
                           duration);
}

static bool cl_effect_uses_scale_controls(CylinderLiteEffect effect)
{
    return effect == CylinderLiteEffectZoomFadeOut ||
           effect == CylinderLiteEffectZoomFadeIn;
}

static bool cl_effect_uses_opacity_controls(CylinderLiteEffect effect)
{
    switch (effect) {
        case CylinderLiteEffectSlide:
        case CylinderLiteEffectFlip:
        case CylinderLiteEffectVerticalScroll:
        case CylinderLiteEffectCubeOutside:
        case CylinderLiteEffectCardHorizontal:
        case CylinderLiteEffectHinge:
        case CylinderLiteEffectZoomFadeOut:
        case CylinderLiteEffectZoomFadeIn:
            return true;
        default:
            return false;
    }
}

static uint64_t cl_build_page_animation(CylinderLiteEffect effect,
                                        int direction,
                                        bool entering)
{
    uint64_t animationGroupClass = r_class("CAAnimationGroup");
    uint64_t arrayClass = r_class("NSMutableArray");
    if (!r_is_objc_ptr(animationGroupClass) || !r_is_objc_ptr(arrayClass)) return 0;

    uint64_t group = r_msg2_main(animationGroupClass, "animation", 0, 0, 0, 0);
    uint64_t animations = r_msg2_main(arrayClass, "array", 0, 0, 0, 0);
    if (!r_is_objc_ptr(group) || !r_is_objc_ptr(animations)) return 0;

    bool usesScaleControls = cl_effect_uses_scale_controls(effect);
    double minScale = usesScaleControls
        ? cl_fraction_from_pct(s_cylinderlite_intensity_pct, 0.70, 1.0)
        : 0.80;
    double minOpacity = cl_effect_uses_opacity_controls(effect)
        ? cl_fraction_from_pct(s_cylinderlite_opacity_pct, 0.10, 1.0)
        : 0.35;
    double scaleDrop = 1.0 - minScale;
    double effectAmount = usesScaleControls
        ? (scaleDrop / 0.20)
        : ((double)cl_clamp_int(s_cylinderlite_intensity_pct, 70, 100) / 90.0);
    if (effectAmount < 0.05) effectAmount = 0.05;
    if (effectAmount > 1.50) effectAmount = 1.50;
    double duration = s_cylinderlite_follow_gesture
        ? 0.32
        : ((double)s_cylinderlite_one_shot_duration_ms / 1000.0);
    double width = s_cylinderlite_page_width > 1.0 ? s_cylinderlite_page_width : 428.0;
    double height = width * 1.90;
    double dir = direction < 0 ? -1.0 : 1.0;
    double pi = 3.14159265358979323846;

    switch (effect) {
        case CylinderLiteEffectSlide:
            cl_add_effect_animation(animations, "transform.translation.x",
                                    dir * 54.0 * effectAmount, duration, entering);
            cl_add_opacity_animation(animations, minOpacity, duration, entering);
            break;
        case CylinderLiteEffectFlip:
            cl_add_effect_animation(animations, "transform.rotation.y",
                                    dir * 0.72 * effectAmount, duration, entering);
            cl_add_opacity_animation(animations, minOpacity, duration, entering);
            break;
        case CylinderLiteEffectPageSpin:
            cl_add_effect_animation(animations, "transform.rotation.z",
                                    dir * pi * 2.0 * effectAmount, duration, entering);
            break;
        case CylinderLiteEffectPageFlip:
            cl_add_effect_animation(animations, "transform.rotation.y",
                                    dir * pi * effectAmount, duration, entering);
            break;
        case CylinderLiteEffectPageTwist:
            cl_add_effect_animation(animations, "transform.rotation.x",
                                    -dir * pi * 0.72 * effectAmount, duration, entering);
            break;
        case CylinderLiteEffectVerticalScroll:
            cl_add_effect_animation(animations, "transform.translation.y",
                                    -dir * height * 0.42 * effectAmount, duration, entering);
            cl_add_opacity_animation(animations, minOpacity, duration, entering);
            break;
        case CylinderLiteEffectBackwards:
            cl_add_effect_animation(animations, "transform.translation.x",
                                    dir * width * 0.72 * effectAmount, duration, entering);
            break;
        case CylinderLiteEffectHellaFar:
            cl_add_effect_animation(animations, "transform.translation.x",
                                    -dir * width * 0.90 * effectAmount, duration, entering);
            break;
        case CylinderLiteEffectCubeInside:
            cl_add_effect_animation(animations, "transform.translation.x",
                                    dir * width * 0.28 * effectAmount, duration, entering);
            cl_add_effect_animation(animations, "transform.translation.z",
                                    width * 0.16 * effectAmount, duration, entering);
            cl_add_effect_animation(animations, "transform.rotation.y",
                                    -dir * pi * 0.50 * effectAmount, duration, entering);
            break;
        case CylinderLiteEffectCubeOutside:
            cl_add_effect_animation(animations, "transform.translation.x",
                                    -dir * width * 0.28 * effectAmount, duration, entering);
            cl_add_effect_animation(animations, "transform.translation.z",
                                    -width * 0.16 * effectAmount, duration, entering);
            cl_add_effect_animation(animations, "transform.rotation.y",
                                    dir * pi * 0.50 * effectAmount, duration, entering);
            cl_add_opacity_animation(animations, minOpacity, duration, entering);
            break;
        case CylinderLiteEffectCardHorizontal:
            cl_add_effect_animation(animations, "transform.rotation.y",
                                    dir * pi * effectAmount, duration, entering);
            cl_add_opacity_animation(animations, minOpacity, duration, entering);
            break;
        case CylinderLiteEffectCardVertical:
            cl_add_effect_animation(animations, "transform.rotation.x",
                                    -dir * pi * effectAmount, duration, entering);
            break;
        case CylinderLiteEffectWheel:
            cl_add_effect_animation(animations, "transform.translation.y",
                                    height * 0.38 * effectAmount, duration, entering);
            cl_add_effect_animation(animations, "transform.rotation.z",
                                    -dir * pi * 0.35 * effectAmount, duration, entering);
            break;
        case CylinderLiteEffectHinge:
            cl_add_effect_animation(animations, "transform.translation.x",
                                    dir * width * 0.22 * effectAmount, duration, entering);
            cl_add_effect_animation(animations, "transform.rotation.y",
                                    dir * pi * 0.82 * effectAmount, duration, entering);
            cl_add_opacity_animation(animations, minOpacity, duration, entering);
            break;
        case CylinderLiteEffectTurn:
            cl_add_effect_animation(animations, "transform.translation.x",
                                    dir * width * 0.18 * effectAmount, duration, entering);
            cl_add_effect_animation(animations, "transform.rotation.y",
                                    -dir * pi * 0.58 * effectAmount, duration, entering);
            break;
        case CylinderLiteEffectZoomFadeOut:
        default:
            cl_add_basic_animation(animations, "transform.scale",
                                   entering ? minScale : 1.0,
                                   entering ? 1.0 : minScale,
                                   duration);
            cl_add_opacity_animation(animations, minOpacity, duration, entering);
            break;
        case CylinderLiteEffectZoomFadeIn: {
            double maxScale = 1.0 + (1.0 - minScale) * 1.55;
            cl_add_basic_animation(animations, "transform.scale",
                                   entering ? maxScale : 1.0,
                                   entering ? 1.0 : maxScale,
                                   duration);
            cl_add_opacity_animation(animations, minOpacity, duration, entering);
            break;
        }
    }

    if (r_msg2_main(animations, "count", 0, 0, 0, 0) == 0) return 0;

    r_msg2_main(group, "setAnimations:", animations, 0, 0, 0);
    r_msg2_main_raw(group, "setDuration:",
                    &duration, sizeof(duration),
                    NULL, 0, NULL, 0, NULL, 0);
    uint64_t fillMode = r_nsstr_retained("both");
    if (r_is_objc_ptr(fillMode)) {
        r_msg2_main(group, "setFillMode:", fillMode, 0, 0, 0);
        r_msg2(fillMode, "release", 0, 0, 0, 0);
    }
    BOOL removed = NO;
    r_msg2_main_raw(group, "setRemovedOnCompletion:",
                    &removed, sizeof(removed),
                    NULL, 0, NULL, 0, NULL, 0);

    uint64_t retained = r_msg2_main(group, "retain", 0, 0, 0, 0);
    return r_is_objc_ptr(retained) ? retained : 0;
}

static void cl_release_animation_templates(void)
{
    for (int i = 0; i < 2; i++) {
        if (r_is_objc_ptr(s_cylinderlite_enter_animations[i]))
            r_msg2_main(s_cylinderlite_enter_animations[i], "release", 0, 0, 0, 0);
        if (r_is_objc_ptr(s_cylinderlite_exit_animations[i]))
            r_msg2_main(s_cylinderlite_exit_animations[i], "release", 0, 0, 0, 0);
        s_cylinderlite_enter_animations[i] = 0;
        s_cylinderlite_exit_animations[i] = 0;
    }
    if (r_is_objc_ptr(s_cylinderlite_animation_key))
        r_msg2(s_cylinderlite_animation_key, "release", 0, 0, 0, 0);
    s_cylinderlite_animation_key = 0;
}

static bool cl_prepare_animation_templates(CylinderLiteEffect effect)
{
    printf("[CYLINDERLITE] preparing animation templates effect=%d\n", (int)effect);
    cl_release_animation_templates();
    s_cylinderlite_animation_key = r_nsstr_retained(kCylinderLiteAnimationKey.UTF8String);
    if (!r_is_objc_ptr(s_cylinderlite_animation_key)) {
        printf("[CYLINDERLITE] preparing animation templates failed: missing key\n");
        return false;
    }

    for (int i = 0; i < 2; i++) {
        int direction = i == 0 ? -1 : 1;
        printf("[CYLINDERLITE] preparing template direction=%d enter\n", direction);
        s_cylinderlite_enter_animations[i] = cl_build_page_animation(effect, direction, true);
        printf("[CYLINDERLITE] preparing template direction=%d exit\n", direction);
        s_cylinderlite_exit_animations[i] = cl_build_page_animation(effect, direction, false);
        if (!r_is_objc_ptr(s_cylinderlite_enter_animations[i]) ||
            !r_is_objc_ptr(s_cylinderlite_exit_animations[i])) {
            cl_release_animation_templates();
            printf("[CYLINDERLITE] preparing animation templates failed direction=%d\n", direction);
            return false;
        }
    }
    printf("[CYLINDERLITE] preparing animation templates done\n");
    return true;
}

static bool cl_add_prepared_animation(uint64_t listView, uint64_t animation)
{
    if (!r_is_objc_ptr(animation) || !r_is_objc_ptr(s_cylinderlite_animation_key)) return false;
    uint64_t layer = cl_safe_msg(listView, "layer", 0, 0, 0, 0);
    if (!r_is_objc_ptr(layer)) return false;

    r_msg2_main(layer, "removeAnimationForKey:", s_cylinderlite_animation_key, 0, 0, 0);
    r_msg2_main(layer, "addAnimation:forKey:", animation, s_cylinderlite_animation_key, 0, 0);
    return true;
}

static void cl_set_animation_progress(uint64_t listView, double progress)
{
    (void)listView;
    (void)progress;
}

static void cl_set_view_alpha(uint64_t view, double alpha)
{
    if (!r_is_objc_ptr(view) || !r_responds_main(view, "setAlpha:")) return;
    if (alpha < 0.0) alpha = 0.0;
    if (alpha > 1.0) alpha = 1.0;
    r_msg2_main_raw(view, "setAlpha:",
                    &alpha, sizeof(alpha),
                    NULL, 0, NULL, 0, NULL, 0);
}

static void cl_set_view_transform(uint64_t view, double scale, double tx)
{
    if (!r_is_objc_ptr(view) || !r_responds_main(view, "setTransform:")) return;
    CLTransform t = { scale, 0.0, 0.0, scale, tx, 0.0 };
    r_msg2_main_raw(view, "setTransform:",
                    &t, sizeof(t),
                    NULL, 0, NULL, 0, NULL, 0);
}

static void cl_reset_view_visual(uint64_t view)
{
    cl_set_view_alpha(view, 1.0);
    cl_set_view_transform(view, 1.0, 0.0);
}

static void cl_remove_prepared_animation(uint64_t listView)
{
    if (!r_is_objc_ptr(listView) || !r_is_objc_ptr(s_cylinderlite_animation_key)) return;
    uint64_t layer = cl_safe_msg(listView, "layer", 0, 0, 0, 0);
    if (!r_is_objc_ptr(layer)) return;
    r_msg2_main(layer, "removeAnimationForKey:", s_cylinderlite_animation_key, 0, 0, 0);
    cl_reset_view_visual(listView);
}

static void cl_clear_one_shot_cleanup(bool removeAnimations)
{
    if (removeAnimations) {
        cl_remove_prepared_animation(s_cylinderlite_one_shot_cleanup_from_list);
        cl_remove_prepared_animation(s_cylinderlite_one_shot_cleanup_to_list);
    }
    s_cylinderlite_one_shot_cleanup_from_list = 0;
    s_cylinderlite_one_shot_cleanup_to_list = 0;
    s_cylinderlite_one_shot_cleanup_ticks = 0;
}

static void cl_schedule_one_shot_cleanup(uint64_t fromList, uint64_t toList)
{
    cl_clear_one_shot_cleanup(true);
    s_cylinderlite_one_shot_cleanup_from_list = fromList;
    s_cylinderlite_one_shot_cleanup_to_list = toList;
    unsigned int ticks = (unsigned int)((s_cylinderlite_one_shot_duration_ms + 79) / 80) + 2;
    if (ticks < 3) ticks = 3;
    if (ticks > 16) ticks = 16;
    s_cylinderlite_one_shot_cleanup_ticks = ticks;
}

static void cl_tick_one_shot_cleanup(void)
{
    if (s_cylinderlite_one_shot_cleanup_ticks == 0) return;
    s_cylinderlite_one_shot_cleanup_ticks--;
    if (s_cylinderlite_one_shot_cleanup_ticks == 0) {
        cl_clear_one_shot_cleanup(true);
        printf("[CYLINDERLITE] one-shot animations cleaned after commit\n");
    }
}

static void cl_remove_cached_page_animations(void)
{
    for (int i = 0; i < s_cylinderlite_list_count; i++) {
        cl_remove_prepared_animation(s_cylinderlite_lists[i]);
    }
    cl_remove_prepared_animation(s_cylinderlite_last_list);
    cl_remove_prepared_animation(s_cylinderlite_one_shot_cleanup_from_list);
    cl_remove_prepared_animation(s_cylinderlite_one_shot_cleanup_to_list);
}

static void cl_clear_page_cache(void)
{
    s_cylinderlite_scroll = 0;
    s_cylinderlite_pan = 0;
    memset(s_cylinderlite_lists, 0, sizeof(s_cylinderlite_lists));
    memset(s_cylinderlite_list_x, 0, sizeof(s_cylinderlite_list_x));
    s_cylinderlite_list_count = 0;
    s_cylinderlite_page_width = 0.0;
    s_cylinderlite_gesture_animating = false;
    s_cylinderlite_gesture_from_page = -1;
    s_cylinderlite_gesture_to_page = -1;
    s_cylinderlite_finish_animating = false;
    s_cylinderlite_finish_from_page = -1;
    s_cylinderlite_finish_to_page = -1;
    s_cylinderlite_finish_progress = 0.0;
    s_cylinderlite_finish_target = 0.0;
    s_cylinderlite_idle_ticks = 0;
    cl_clear_one_shot_cleanup(false);
}

static bool cl_refresh_page_cache(void)
{
    cl_clear_page_cache();

    uint64_t scrollClass = r_class("SBIconScrollView");
    uint64_t listClass = r_class("SBIconListView");
    if (!r_is_objc_ptr(scrollClass) || !r_is_objc_ptr(listClass)) return false;

    uint64_t scrolls[16] = {0};
    int scrollCount = sb_collect_views_in_windows(scrollClass, scrolls, 16);
    uint32_t oldSettle = r_settle_us(0);

    uint64_t bestScroll = 0;
    uint64_t bestLists[16] = {0};
    double bestListX[16] = {0};
    int bestCount = 0;
    double bestWidth = 0.0;
    double bestPageWidth = 0.0;

    for (int i = 0; i < scrollCount; i++) {
        uint64_t scroll = scrolls[i];
        CLRect bounds = {0};
        CLSize content = {0};
        if (!cl_get_rect(scroll, "bounds", &bounds) ||
            !cl_get_size(scroll, "contentSize", &content) ||
            bounds.width <= 1.0 ||
            content.width <= bounds.width + 1.0) {
            continue;
        }

        uint64_t lists[16] = {0};
        int listCount = sb_collect_views(scroll, listClass, lists, 16);
        if (listCount <= 0) continue;
        double listX[16] = {0};
        int usableCount = 0;
        for (int j = 0; j < listCount; j++) {
            CLRect frame = {0};
            if (!cl_get_rect(lists[j], "frame", &frame)) continue;
            lists[usableCount] = lists[j];
            listX[usableCount] = frame.x;
            usableCount++;
        }
        if (usableCount <= 0) continue;
        if (content.width > bestWidth) {
            bestScroll = scroll;
            bestWidth = content.width;
            bestPageWidth = bounds.width;
            bestCount = usableCount;
            memset(bestLists, 0, sizeof(bestLists));
            memset(bestListX, 0, sizeof(bestListX));
            memcpy(bestLists, lists, sizeof(uint64_t) * (size_t)usableCount);
            memcpy(bestListX, listX, sizeof(double) * (size_t)usableCount);
        }
    }

    r_settle_us(oldSettle);
    if (!bestScroll || bestCount <= 0) return false;

    s_cylinderlite_scroll = bestScroll;
    s_cylinderlite_pan = cl_safe_msg(bestScroll, "panGestureRecognizer", 0, 0, 0, 0);
    s_cylinderlite_list_count = bestCount;
    s_cylinderlite_page_width = bestPageWidth;
    memcpy(s_cylinderlite_lists, bestLists, sizeof(uint64_t) * (size_t)bestCount);
    memcpy(s_cylinderlite_list_x, bestListX, sizeof(double) * (size_t)bestCount);
    printf("[CYLINDERLITE] cached scroll=0x%llx pan=0x%llx lists=%d pageWidth=%.1f\n",
           (unsigned long long)s_cylinderlite_scroll,
           (unsigned long long)s_cylinderlite_pan,
           s_cylinderlite_list_count,
           s_cylinderlite_page_width);
    return r_is_objc_ptr(s_cylinderlite_pan);
}

static uint64_t cl_list_for_page(int page)
{
    if (page < 0 || s_cylinderlite_page_width <= 1.0) return 0;
    double targetX = (double)page * s_cylinderlite_page_width;
    uint64_t bestList = 0;
    double bestDistance = DBL_MAX;
    for (int i = 0; i < s_cylinderlite_list_count; i++) {
        double distance = fabs(s_cylinderlite_list_x[i] - targetX);
        if (distance < bestDistance) {
            bestDistance = distance;
            bestList = s_cylinderlite_lists[i];
        }
    }
    return bestDistance <= s_cylinderlite_page_width * 0.55 ? bestList : 0;
}

static uint64_t cl_find_current_page_list(int *pageOut, int *directionOut)
{
    if (pageOut) *pageOut = -1;
    if (directionOut) *directionOut = 1;

    if (!s_cylinderlite_scroll || s_cylinderlite_list_count <= 0) {
        if (!cl_refresh_page_cache()) return 0;
    }

    CLPoint offset = {0};
    if (s_cylinderlite_page_width <= 1.0 ||
        !cl_get_point_fast(s_cylinderlite_scroll, "contentOffset", &offset)) {
        if (!cl_refresh_page_cache()) return 0;
        if (s_cylinderlite_page_width <= 1.0 ||
            !cl_get_point_fast(s_cylinderlite_scroll, "contentOffset", &offset)) {
            return 0;
        }
    }

    int page = (int)llround(offset.x / s_cylinderlite_page_width);
    uint64_t bestList = cl_list_for_page(page);

    if (!bestList) return 0;

    if (pageOut) *pageOut = page;
    if (directionOut) {
        if (s_cylinderlite_last_page != -9999 && page != s_cylinderlite_last_page) {
            *directionOut = page < s_cylinderlite_last_page ? -1 : 1;
        } else {
            *directionOut = 1;
        }
    }
    return bestList;
}

bool cylinderlite_tick_in_session(void)
{
    if (!s_cylinderlite_active) return false;
    if (!r_is_objc_ptr(s_cylinderlite_pan) || s_cylinderlite_page_width <= 1.0) {
        if (!cl_refresh_page_cache()) return false;
    }

    uint32_t oldSettle = r_settle_us(0);
    uint64_t state = r_msg2_main(s_cylinderlite_pan, "state", 0, 0, 0, 0);
    bool gestureActive = state == 1 || state == 2;
    bool scrollSettling = !gestureActive &&
                          s_cylinderlite_gesture_animating &&
                          (cl_get_bool(s_cylinderlite_scroll, "isTracking") ||
                           cl_get_bool(s_cylinderlite_scroll, "isDragging") ||
                           cl_get_bool(s_cylinderlite_scroll, "isDecelerating"));

    CLPoint offset = {0};
    bool haveOffset = false;
    if (gestureActive || s_cylinderlite_gesture_animating) {
        haveOffset = cl_get_point_fast(s_cylinderlite_scroll, "contentOffset", &offset);
        if (!haveOffset) {
            r_settle_us(oldSettle);
            return false;
        }
    }

    if (gestureActive && s_cylinderlite_finish_animating) {
        cl_remove_prepared_animation(cl_list_for_page(s_cylinderlite_finish_from_page));
        cl_remove_prepared_animation(cl_list_for_page(s_cylinderlite_finish_to_page));
        s_cylinderlite_finish_animating = false;
        s_cylinderlite_finish_from_page = -1;
        s_cylinderlite_finish_to_page = -1;
        s_cylinderlite_finish_progress = 0.0;
        s_cylinderlite_finish_target = 0.0;
    }
    if (gestureActive && s_cylinderlite_one_shot_cleanup_ticks > 0) {
        cl_clear_one_shot_cleanup(true);
    }

    if (!gestureActive && s_cylinderlite_finish_animating) {
        double delta = s_cylinderlite_finish_target - s_cylinderlite_finish_progress;
        double step = fabs(delta) < 0.34 ? delta : (delta < 0.0 ? -0.34 : 0.34);
        s_cylinderlite_finish_progress += step;
        if (s_cylinderlite_finish_progress < 0.0) s_cylinderlite_finish_progress = 0.0;
        if (s_cylinderlite_finish_progress > 1.0) s_cylinderlite_finish_progress = 1.0;

        uint64_t fromList = cl_list_for_page(s_cylinderlite_finish_from_page);
        uint64_t toList = cl_list_for_page(s_cylinderlite_finish_to_page);
        cl_set_animation_progress(fromList, s_cylinderlite_finish_progress);
        cl_set_animation_progress(toList, s_cylinderlite_finish_progress);

        if (fabs(s_cylinderlite_finish_progress - s_cylinderlite_finish_target) <= 0.001) {
            cl_remove_prepared_animation(fromList);
            cl_remove_prepared_animation(toList);
            printf("[CYLINDERLITE] finish complete target=%.2f\n",
                   s_cylinderlite_finish_target);
            s_cylinderlite_finish_animating = false;
            s_cylinderlite_finish_from_page = -1;
            s_cylinderlite_finish_to_page = -1;
            s_cylinderlite_finish_progress = 0.0;
            s_cylinderlite_finish_target = 0.0;
        }

        s_cylinderlite_idle_ticks = 0;
        r_settle_us(oldSettle);
        return true;
    }

    if (gestureActive && !s_cylinderlite_gesture_animating) {

        double originX = (double)s_cylinderlite_last_page * s_cylinderlite_page_width;
        double delta = offset.x - originX;
        double threshold = fmax(3.0, s_cylinderlite_page_width * 0.008);
        if (fabs(delta) >= threshold) {
            int direction = delta < 0.0 ? -1 : 1;
            int targetPage = s_cylinderlite_last_page + direction;
            uint64_t fromList = cl_list_for_page(s_cylinderlite_last_page);
            uint64_t toList = cl_list_for_page(targetPage);
            int templateIndex = direction < 0 ? 0 : 1;
            bool outgoingOK = false;
            bool incomingOK = false;
            if (r_is_objc_ptr(fromList) && r_is_objc_ptr(toList)) {
                outgoingOK = cl_add_prepared_animation(
                    fromList, s_cylinderlite_exit_animations[templateIndex]);
                incomingOK = cl_add_prepared_animation(
                    toList, s_cylinderlite_enter_animations[templateIndex]);
            }

            if (outgoingOK && incomingOK) {
                s_cylinderlite_gesture_animating = true;
                s_cylinderlite_gesture_from_page = s_cylinderlite_last_page;
                s_cylinderlite_gesture_to_page = targetPage;
                double progress = fabs(delta) / s_cylinderlite_page_width;
                cl_set_animation_progress(fromList, progress);
                cl_set_animation_progress(toList, progress);
                printf("[CYLINDERLITE] gesture start state=%llu from=%d to=%d direction=%d effect=%d\n",
                       (unsigned long long)state,
                       s_cylinderlite_gesture_from_page,
                       s_cylinderlite_gesture_to_page,
                       direction,
                       (int)s_cylinderlite_effect);
            }
        }
        s_cylinderlite_idle_ticks = 0;
        r_settle_us(oldSettle);
        return true;
    }

    if (gestureActive && s_cylinderlite_gesture_animating) {
        double originX = (double)s_cylinderlite_gesture_from_page * s_cylinderlite_page_width;
        double progress = fabs(offset.x - originX) / s_cylinderlite_page_width;
        uint64_t fromList = cl_list_for_page(s_cylinderlite_gesture_from_page);
        uint64_t toList = cl_list_for_page(s_cylinderlite_gesture_to_page);
        cl_set_animation_progress(fromList, progress);
        cl_set_animation_progress(toList, progress);
        s_cylinderlite_idle_ticks = 0;
        r_settle_us(oldSettle);
        return true;
    }

    if (scrollSettling) {
        s_cylinderlite_idle_ticks = 0;
        r_settle_us(oldSettle);
        return true;
    }

    if (!gestureActive && s_cylinderlite_gesture_animating) {
        int settledPage = s_cylinderlite_gesture_from_page;
        if (haveOffset) {
            settledPage = (int)llround(offset.x / s_cylinderlite_page_width);
        }
        bool committed = settledPage == s_cylinderlite_gesture_to_page;
        double currentProgress = fabs(offset.x - (double)s_cylinderlite_gesture_from_page * s_cylinderlite_page_width) / s_cylinderlite_page_width;
        if (currentProgress < 0.0) currentProgress = 0.0;
        if (currentProgress > 1.0) currentProgress = 1.0;
        s_cylinderlite_finish_animating = false;
        s_cylinderlite_finish_from_page = s_cylinderlite_gesture_from_page;
        s_cylinderlite_finish_to_page = s_cylinderlite_gesture_to_page;
        s_cylinderlite_finish_progress = currentProgress;
        s_cylinderlite_finish_target = committed ? 1.0 : 0.0;
        uint64_t fromList = cl_list_for_page(s_cylinderlite_gesture_from_page);
        uint64_t toList = cl_list_for_page(s_cylinderlite_gesture_to_page);
        if (!committed) {
            cl_remove_prepared_animation(fromList);
            cl_remove_prepared_animation(toList);
        } else {
            cl_schedule_one_shot_cleanup(fromList, toList);
        }
        uint64_t settledList = cl_list_for_page(settledPage);
        if (r_is_objc_ptr(settledList)) {
            s_cylinderlite_last_page = settledPage;
            s_cylinderlite_last_list = settledList;
        }
        printf("[CYLINDERLITE] gesture end state=%llu settled=%d finish=%s progress=%.2f\n",
               (unsigned long long)state,
               settledPage,
               committed ? "commit" : "rollback",
               currentProgress);
        s_cylinderlite_gesture_animating = false;
        s_cylinderlite_gesture_from_page = -1;
        s_cylinderlite_gesture_to_page = -1;
        s_cylinderlite_idle_ticks = 0;
        r_settle_us(oldSettle);
        return true;
    }

    if (!gestureActive && !s_cylinderlite_gesture_animating &&
        !s_cylinderlite_finish_animating &&
        s_cylinderlite_one_shot_cleanup_ticks > 0) {
        cl_tick_one_shot_cleanup();
        s_cylinderlite_idle_ticks = 0;
        r_settle_us(oldSettle);
        return true;
    }

    // Recover the settled page if background scheduling missed the short gesture states.
    if (!gestureActive && ++s_cylinderlite_idle_ticks >= 6) {
        s_cylinderlite_idle_ticks = 0;
        CLPoint offset = {0};
        if (cl_get_point_fast(s_cylinderlite_scroll, "contentOffset", &offset)) {
            int settledPage = (int)llround(offset.x / s_cylinderlite_page_width);
            uint64_t settledList = cl_list_for_page(settledPage);
            if (r_is_objc_ptr(settledList) && settledPage != s_cylinderlite_last_page) {
                printf("[CYLINDERLITE] gesture states missed; settled page %d -> %d\n",
                       s_cylinderlite_last_page, settledPage);
                s_cylinderlite_last_page = settledPage;
                s_cylinderlite_last_list = settledList;
            }
        }
    }

    r_settle_us(oldSettle);
    return true;
}

bool cylinderlite_apply_in_session_with_options(CylinderLiteEffect effect,
                                                int intensityPct,
                                                int opacityPct,
                                                bool followGesture,
                                                int oneShotDurationMs)
{
    if (effect < CylinderLiteEffectSlide || effect > CylinderLiteEffectLast) {
        effect = CylinderLiteEffectZoomFadeOut;
    }
    s_cylinderlite_effect = effect;
    s_cylinderlite_intensity_pct = cl_clamp_int(intensityPct, 70, 100);
    s_cylinderlite_opacity_pct = cl_clamp_int(opacityPct, 10, 100);
    s_cylinderlite_follow_gesture = followGesture;
    s_cylinderlite_one_shot_duration_ms = cl_clamp_int(oneShotDurationMs, 250, 800);
    s_cylinderlite_active = true;
    cl_remove_cached_page_animations();
    s_cylinderlite_last_page = -9999;
    s_cylinderlite_last_list = 0;
    cl_clear_one_shot_cleanup(false);
    cl_clear_page_cache();
    bool cacheOK = cl_refresh_page_cache();
    printf("[CYLINDERLITE] page cache result=%d; preparing templates next\n", cacheOK);
    bool templatesOK = cacheOK && cl_prepare_animation_templates(effect);
    printf("[CYLINDERLITE] templates result=%d; locating current page next\n", templatesOK);
    int page = -1;
    int direction = 1;
    uint64_t list = templatesOK ? cl_find_current_page_list(&page, &direction) : 0;
    printf("[CYLINDERLITE] current page lookup list=0x%llx page=%d direction=%d\n",
           (unsigned long long)list,
           page,
           direction);
    bool ok = templatesOK && r_is_objc_ptr(list) && page >= 0;
    if (ok) {
        s_cylinderlite_last_page = page;
        s_cylinderlite_last_list = list;
        printf("[CYLINDERLITE] armed %s monitor page=%d list=0x%llx pan=0x%llx effect=%d minScale=%d minOpacity=%d durationMs=%d templates=4\n",
               s_cylinderlite_follow_gesture ? "progress" : "one-shot",
               page,
               (unsigned long long)list,
               (unsigned long long)s_cylinderlite_pan,
               (int)s_cylinderlite_effect,
               s_cylinderlite_intensity_pct,
               s_cylinderlite_opacity_pct,
               s_cylinderlite_one_shot_duration_ms);
    }
    log_user(ok
        ? "[CYLINDERLITE] Page animation monitor armed. Swipe between Home Screen pages to test it.\n"
        : "[CYLINDERLITE] Could not locate the current Home Screen page.\n");
    return ok;
}

bool cylinderlite_apply_in_session(CylinderLiteEffect effect)
{
    return cylinderlite_apply_in_session_with_options(effect, 100, 100, true, 520);
}

bool cylinderlite_stop_in_session(void)
{
    s_cylinderlite_active = false;
    uint64_t listClass = r_class("SBIconListView");
    uint64_t key = r_nsstr_retained(kCylinderLiteAnimationKey.UTF8String);
    if (!r_is_objc_ptr(listClass) || !r_is_objc_ptr(key)) {
        if (key) r_msg2(key, "release", 0, 0, 0, 0);
        cl_release_animation_templates();
        s_cylinderlite_last_page = -9999;
        s_cylinderlite_last_list = 0;
        cl_clear_page_cache();
        return false;
    }

    uint64_t lists[32] = {0};
    int count = sb_collect_views_in_windows(listClass, lists, 32);
    for (int i = 0; i < count; i++) {
        uint64_t layer = cl_safe_msg(lists[i], "layer", 0, 0, 0, 0);
        if (r_is_objc_ptr(layer)) {
            r_msg2_main(layer, "removeAnimationForKey:", key, 0, 0, 0);
        }
    }
    if (r_is_objc_ptr(s_cylinderlite_last_list)) {
        uint64_t layer = cl_safe_msg(s_cylinderlite_last_list, "layer", 0, 0, 0, 0);
        if (r_is_objc_ptr(layer)) {
            r_msg2_main(layer, "removeAnimationForKey:", key, 0, 0, 0);
        }
    }
    r_msg2(key, "release", 0, 0, 0, 0);
    cl_release_animation_templates();
    printf("[CYLINDERLITE] stopped removedAnimations=%d\n", count);
    log_user("[CYLINDERLITE] Page animations stopped for this SpringBoard session.\n");
    s_cylinderlite_last_page = -9999;
    s_cylinderlite_last_list = 0;
    cl_clear_page_cache();
    return true;
}

void cylinderlite_forget_remote_state(void)
{
    s_cylinderlite_active = false;
    s_cylinderlite_effect = CylinderLiteEffectZoomFadeOut;
    s_cylinderlite_follow_gesture = true;
    s_cylinderlite_one_shot_duration_ms = 520;
    s_cylinderlite_last_page = -9999;
    s_cylinderlite_last_list = 0;
    memset(s_cylinderlite_enter_animations, 0, sizeof(s_cylinderlite_enter_animations));
    memset(s_cylinderlite_exit_animations, 0, sizeof(s_cylinderlite_exit_animations));
    s_cylinderlite_animation_key = 0;
    cl_clear_page_cache();
}
