//
//  watchlayout.m
//  RemoteCall-only vertically scrolling Apple Watch icon layout.
//
//  Architecture adapted from hxhlb/cyanide (AGPL-3.0), then hardened for
//  bounded SpringBoard enumeration, configurable geometry, and quiet failure.
//

#import "watchlayout.h"
#import "remote_objc.h"
#import "sb_walk.h"
#import "../LogTextView.h"

#import <Foundation/Foundation.h>
#import <math.h>
#import <stdio.h>
#import <string.h>

typedef struct { double x, y; } WLPoint;
typedef struct { double x, y, width, height; } WLRect;
typedef struct { double width, height; } WLSize;
typedef struct { double top, left, bottom, right; } WLInsets;
typedef struct { double a, b, c, d, tx, ty; } WLAffineTransform;

typedef struct {
    uint64_t listView;
    double originalAlpha;
} WLListState;

typedef struct {
    uint64_t recognizer;
    bool originalEnabled;
} WLGestureState;

typedef struct {
    uint64_t imageClass;
    uint64_t iconModel;
    bool privateImageAPI;
    bool applicationIconForBundle;
    bool expectedIconForDisplay;
    bool iconImage;
    bool getIconImage;
    bool generateIconImage;
} WLIconSource;

typedef struct {
    // Borrowed NSString owned by SBApplication. Keeping this as a remote
    // object avoids copying every bundle identifier through remote_read(),
    // which can stall the first Watch Layout pass on some devices.
    uint64_t bundleID;
} WLAppEntry;

enum {
    WL_MAX_APPS = 1024,
    WL_MAX_LISTS = 64,
    WL_MAX_GESTURE_GUARDS = 8,
};

static WLListState s_lists[WL_MAX_LISTS];
static int s_list_count = 0;
static WLGestureState s_gesture_guards[WL_MAX_GESTURE_GUARDS];
static int s_gesture_guard_count = 0;
static uint64_t s_root_view = 0;
static uint64_t s_scroll_view = 0;
static bool s_active = false;
static int s_compact_percent = 82;
static int s_icon_scale_percent = 88;
static bool s_configuration_dirty = true;
static NSTimeInterval s_retry_after = 0.0;
static int s_suppressed_retries = 0;

static uint64_t wl_safe_msg(uint64_t object, const char *selector,
                            uint64_t a0, uint64_t a1, uint64_t a2, uint64_t a3)
{
    if (!r_is_objc_ptr(object) || !selector || !r_responds_main(object, selector)) return 0;
    return r_msg2_main(object, selector, a0, a1, a2, a3);
}

static bool wl_get_rect(uint64_t object, const char *selector, WLRect *out)
{
    if (!r_is_objc_ptr(object) || !selector || !out ||
        !r_responds_main(object, selector)) return false;
    memset(out, 0, sizeof(*out));
    return r_msg2_main_struct_ret(object, selector, out, sizeof(*out),
                                  NULL, 0, NULL, 0, NULL, 0, NULL, 0);
}

static void wl_set_rect(uint64_t object, const char *selector, WLRect value)
{
    if (!r_is_objc_ptr(object) || !r_responds_main(object, selector)) return;
    r_msg2_main_raw(object, selector,
                    &value, sizeof(value),
                    NULL, 0, NULL, 0, NULL, 0);
}

static void wl_set_point(uint64_t object, const char *selector, WLPoint value)
{
    if (!r_is_objc_ptr(object) || !r_responds_main(object, selector)) return;
    r_msg2_main_raw(object, selector,
                    &value, sizeof(value),
                    NULL, 0, NULL, 0, NULL, 0);
}

static bool wl_get_double(uint64_t object, const char *selector, double *out)
{
    if (!r_is_objc_ptr(object) || !selector || !out ||
        !r_responds_main(object, selector)) return false;
    memset(out, 0, sizeof(*out));
    return r_msg2_main_struct_ret(object, selector, out, sizeof(*out),
                                  NULL, 0, NULL, 0, NULL, 0, NULL, 0);
}

static bool wl_get_insets(uint64_t object, const char *selector, WLInsets *out)
{
    if (!r_is_objc_ptr(object) || !selector || !out ||
        !r_responds_main(object, selector)) return false;
    memset(out, 0, sizeof(*out));
    return r_msg2_main_struct_ret(object, selector, out, sizeof(*out),
                                  NULL, 0, NULL, 0, NULL, 0, NULL, 0);
}

static void wl_set_double(uint64_t object, const char *selector, double value)
{
    if (!r_is_objc_ptr(object) || !r_responds_main(object, selector)) return;
    r_msg2_main_raw(object, selector,
                    &value, sizeof(value),
                    NULL, 0, NULL, 0, NULL, 0);
}

static bool wl_pointer_seen(const uint64_t *values, int count, uint64_t value)
{
    for (int i = 0; i < count; i++) {
        if (values[i] == value) return true;
    }
    return false;
}

static int wl_copy_array(uint64_t array, uint64_t *out, int cap)
{
    if (!r_is_objc_ptr(array) || !out || cap <= 0) return 0;
    uint64_t count = r_msg2_main(array, "count", 0, 0, 0, 0);
    if (count > (uint64_t)cap) count = (uint64_t)cap;

    int copied = 0;
    for (uint64_t i = 0; i < count && copied < cap; i++) {
        uint64_t value = r_msg2_main(array, "objectAtIndex:", i, 0, 0, 0);
        if (r_is_objc_ptr(value) && !wl_pointer_seen(out, copied, value)) {
            out[copied++] = value;
        }
    }
    return copied;
}

static int wl_disable_ancestor_editing_gestures(uint64_t scroll,
                                                uint64_t iconController)
{
    if (!r_is_objc_ptr(scroll) || !r_is_objc_ptr(iconController)) return 0;
    uint64_t longPressClass = r_class("UILongPressGestureRecognizer");
    uint64_t windowClass = r_class("UIWindow");
    if (!r_is_objc_ptr(longPressClass)) return 0;

    uint32_t oldSettle = r_settle_us(0);
    uint64_t current = wl_safe_msg(scroll, "superview", 0, 0, 0, 0);
    for (int depth = 0;
         depth < 16 && r_is_objc_ptr(current) &&
         s_gesture_guard_count < WL_MAX_GESTURE_GUARDS;
         depth++) {
        uint64_t gesturesArray = wl_safe_msg(current, "gestureRecognizers",
                                             0, 0, 0, 0);
        uint64_t gestures[32] = {0};
        int gestureCount = wl_copy_array(gesturesArray, gestures, 32);
        for (int i = 0; i < gestureCount &&
                        s_gesture_guard_count < WL_MAX_GESTURE_GUARDS; i++) {
            uint64_t gesture = gestures[i];
            if (!r_msg2_main(gesture, "isKindOfClass:",
                             longPressClass, 0, 0, 0)) continue;
            uint64_t delegate = wl_safe_msg(gesture, "delegate", 0, 0, 0, 0);
            if (delegate != iconController) continue;

            bool originalEnabled = wl_safe_msg(
                gesture, "isEnabled", 0, 0, 0, 0) != 0;
            r_msg2_main(gesture, "retain", 0, 0, 0, 0);
            s_gesture_guards[s_gesture_guard_count++] = (WLGestureState) {
                .recognizer = gesture,
                .originalEnabled = originalEnabled,
            };
            if (originalEnabled)
                r_msg2_main(gesture, "setEnabled:", 0, 0, 0, 0);
            printf("[WATCHLAYOUT][GESTURE-GUARD] disabled SBIconController long press ptr=0x%llx depth=%d originalEnabled=%d\n",
                   (unsigned long long)gesture, depth, originalEnabled);
        }

        if (r_is_objc_ptr(windowClass) &&
            r_msg2_main(current, "isKindOfClass:", windowClass, 0, 0, 0))
            break;
        current = wl_safe_msg(current, "superview", 0, 0, 0, 0);
    }
    r_settle_us(oldSettle);
    return s_gesture_guard_count;
}

static int wl_restore_ancestor_editing_gestures(void)
{
    int restored = 0;
    for (int i = 0; i < s_gesture_guard_count; i++) {
        WLGestureState *state = &s_gesture_guards[i];
        if (!r_is_objc_ptr(state->recognizer)) continue;
        r_msg2_main(state->recognizer, "setEnabled:",
                    state->originalEnabled ? 1 : 0, 0, 0, 0);
        restored++;
    }
    if (restored > 0)
        printf("[WATCHLAYOUT][GESTURE-GUARD] restored=%d\n", restored);
    return restored;
}

static int wl_installed_apps(WLAppEntry *out, int cap)
{
    if (!out || cap <= 0) return 0;
    memset(out, 0, sizeof(*out) * (size_t)cap);

    uint64_t controllerClass = r_class("SBApplicationController");
    uint64_t controller = r_is_objc_ptr(controllerClass)
        ? wl_safe_msg(controllerClass, "sharedInstance", 0, 0, 0, 0) : 0;
    if (!r_is_objc_ptr(controller))
        controller = r_is_objc_ptr(controllerClass)
            ? wl_safe_msg(controllerClass, "sharedInstanceIfExists", 0, 0, 0, 0) : 0;
    uint64_t applications = r_is_objc_ptr(controller)
        ? wl_safe_msg(controller, "allApplications", 0, 0, 0, 0) : 0;
    if (!r_is_objc_ptr(applications))
        applications = r_is_objc_ptr(controller)
            ? wl_safe_msg(controller, "applications", 0, 0, 0, 0) : 0;
    if (r_is_objc_ptr(applications) &&
        r_responds_main(applications, "allObjects"))
        applications = wl_safe_msg(applications, "allObjects", 0, 0, 0, 0);
    else if (r_is_objc_ptr(applications) &&
             r_responds_main(applications, "allValues"))
        applications = wl_safe_msg(applications, "allValues", 0, 0, 0, 0);
    if (!r_is_objc_ptr(applications)) {
        log_user("[WATCHLAYOUT][CATALOG] SBApplicationController did not expose an application array.\n");
        return 0;
    }
    if (!r_responds_main(applications, "objectAtIndex:")) {
        log_user("[WATCHLAYOUT][CATALOG] Application collection is not indexable; stopped before scanning.\n");
        return 0;
    }

    uint64_t count = wl_safe_msg(applications, "count", 0, 0, 0, 0);
    if (count > (uint64_t)cap) count = (uint64_t)cap;
    int accepted = 0, skippedHidden = 0, invalidIdentifiers = 0;
    uint32_t oldSettle = r_settle_us(0);
    for (uint64_t i = 0; i < count; i++) {
        uint64_t app = wl_safe_msg(applications, "objectAtIndex:", i, 0, 0, 0);
        if (!r_is_objc_ptr(app)) continue;
        if (r_responds_main(app, "isHidden") &&
            wl_safe_msg(app, "isHidden", 0, 0, 0, 0)) {
            skippedHidden++;
            continue;
        }

        uint64_t bundle = wl_safe_msg(app, "bundleIdentifier", 0, 0, 0, 0);
        if (!r_is_objc_ptr(bundle))
            bundle = wl_safe_msg(app, "displayIdentifier", 0, 0, 0, 0);
        if (!r_is_objc_ptr(bundle)) {
            invalidIdentifiers++;
            continue;
        }

        bool duplicate = false;
        for (int j = 0; j < accepted; j++) {
            if (out[j].bundleID == bundle) { duplicate = true; break; }
        }
        if (duplicate) continue;
        out[accepted++].bundleID = bundle;
    }
    r_settle_us(oldSettle);
    log_user("[WATCHLAYOUT][CATALOG] scanned=%llu accepted=%d hidden=%d invalid=%d remoteStringReads=0.\n",
             (unsigned long long)count, accepted, skippedHidden,
             invalidIdentifiers);
    return accepted;
}

static bool wl_class_has_instance_method(uint64_t cls, const char *selector)
{
    uint64_t sel = r_sel(selector);
    return r_is_objc_ptr(cls) && sel &&
        r_dlsym_call(R_TIMEOUT, "class_getInstanceMethod",
                     cls, sel, 0, 0, 0, 0, 0, 0) != 0;
}

static uint64_t wl_fetch_icon_model(uint64_t bundleID,
                                    const WLIconSource *source)
{
    if (!r_is_objc_ptr(bundleID) || !source ||
        !r_is_objc_ptr(source->iconModel)) return 0;

    uint64_t icon = source->applicationIconForBundle
        ? r_msg2_main(source->iconModel, "applicationIconForBundleIdentifier:",
                      bundleID, 0, 0, 0)
        : 0;
    if (!r_is_objc_ptr(icon) && source->expectedIconForDisplay)
        icon = r_msg2_main(source->iconModel,
                           "expectedIconForDisplayIdentifier:",
                           bundleID, 0, 0, 0);
    return icon;
}

static uint64_t wl_fetch_icon_image(uint64_t bundleID,
                                    const WLIconSource *source)
{
    if (!r_is_objc_ptr(bundleID) || !source) return 0;

    uint64_t image = 0;
    if (r_is_objc_ptr(source->imageClass) && source->privateImageAPI) {
        int64_t format = 2;
        double scale = 2.0;
        image = r_msg2_main_raw(source->imageClass,
            "_applicationIconImageForBundleIdentifier:format:scale:",
            &bundleID, sizeof(bundleID),
            &format, sizeof(format),
            &scale, sizeof(scale),
            NULL, 0);
    }
    if (r_is_objc_ptr(image)) return image;

    uint64_t icon = wl_fetch_icon_model(bundleID, source);
    if (!r_is_objc_ptr(icon)) return 0;

    if (source->iconImage)
        image = r_msg2_main(icon, "iconImage", 0, 0, 0, 0);
    if (!r_is_objc_ptr(image) && source->getIconImage)
        image = r_msg2_main(icon, "getIconImage:", 2, 0, 0, 0);
    if (!r_is_objc_ptr(image) && source->generateIconImage)
        image = r_msg2_main(icon, "generateIconImage:", 2, 0, 0, 0);
    return image;
}

static uint64_t wl_make_open_invocation(uint64_t workspace, uint64_t bundleID)
{
    if (!r_is_objc_ptr(workspace) || !r_is_objc_ptr(bundleID)) return 0;
    uint64_t selector = r_sel("openApplicationWithBundleID:");
    uint64_t signature = selector
        ? r_msg2_main(workspace, "methodSignatureForSelector:",
                      selector, 0, 0, 0)
        : 0;
    uint64_t invocationClass = r_class("NSInvocation");
    uint64_t invocation = r_is_objc_ptr(invocationClass) &&
                          r_is_objc_ptr(signature)
        ? r_msg2_main(invocationClass, "invocationWithMethodSignature:",
                      signature, 0, 0, 0)
        : 0;
    if (!r_is_objc_ptr(invocation)) return 0;

    r_msg2_main(invocation, "setTarget:", workspace, 0, 0, 0);
    r_msg2_main(invocation, "setSelector:", selector, 0, 0, 0);
    uint64_t argument = r_dlsym_call(R_TIMEOUT, "malloc", sizeof(bundleID),
                                     0, 0, 0, 0, 0, 0, 0);
    if (!argument) return 0;
    remote_write(argument, &bundleID, sizeof(bundleID));
    r_msg2_main(invocation, "setArgument:atIndex:", argument, 2, 0, 0);
    r_free(argument);
    r_msg2_main(invocation, "retainArguments", 0, 0, 0, 0);
    return invocation;
}

static bool wl_bind_open_action(uint64_t view,
                                uint64_t workspace,
                                uint64_t bundleID)
{
    if (!r_is_objc_ptr(view) || !r_is_objc_ptr(bundleID)) return false;
    uint64_t openInvocation = wl_make_open_invocation(workspace, bundleID);
    if (!r_is_objc_ptr(openInvocation)) return false;

    uint64_t invokeSelector = r_sel("invoke");
    uint64_t tapClass = r_class("UITapGestureRecognizer");
    uint64_t tapAlloc = r_is_objc_ptr(tapClass)
        ? r_msg2_main(tapClass, "alloc", 0, 0, 0, 0)
        : 0;
    uint64_t tap = r_is_objc_ptr(tapAlloc)
        ? r_msg2_main(tapAlloc, "initWithTarget:action:",
                      openInvocation, invokeSelector, 0, 0)
        : 0;
    if (!r_is_objc_ptr(tap)) return false;
    r_msg2_main(tap, "setCancelsTouchesInView:", 0, 0, 0, 0);
    r_msg2_main(view, "addGestureRecognizer:", tap, 0, 0, 0);
    uint64_t associationKey = r_sel("cyanideWatchLayoutOpenInvocation");
    r_dlsym_call(R_TIMEOUT, "objc_setAssociatedObject",
                 view, associationKey, openInvocation,
                 1 /* OBJC_ASSOCIATION_RETAIN_NONATOMIC */, 0, 0, 0, 0);
    r_msg2_main(tap, "release", 0, 0, 0, 0);
    return true;
}

static bool wl_install_long_press_guard(uint64_t view)
{
    if (!r_is_objc_ptr(view)) return false;
    uint64_t selector = r_sel("setNeedsLayout");
    uint64_t signature = selector
        ? r_msg2_main(view, "methodSignatureForSelector:", selector, 0, 0, 0)
        : 0;
    uint64_t invocationClass = r_class("NSInvocation");
    uint64_t invocation = r_is_objc_ptr(invocationClass) &&
                          r_is_objc_ptr(signature)
        ? r_msg2_main(invocationClass, "invocationWithMethodSignature:",
                      signature, 0, 0, 0)
        : 0;
    if (!r_is_objc_ptr(invocation)) return false;
    r_msg2_main(invocation, "setTarget:", view, 0, 0, 0);
    r_msg2_main(invocation, "setSelector:", selector, 0, 0, 0);

    uint64_t longPressClass = r_class("UILongPressGestureRecognizer");
    uint64_t longPressAlloc = r_is_objc_ptr(longPressClass)
        ? r_msg2_main(longPressClass, "alloc", 0, 0, 0, 0)
        : 0;
    uint64_t invokeSelector = r_sel("invoke");
    uint64_t longPress = r_is_objc_ptr(longPressAlloc)
        ? r_msg2_main(longPressAlloc, "initWithTarget:action:",
                      invocation, invokeSelector, 0, 0)
        : 0;
    if (!r_is_objc_ptr(longPress)) return false;
    double duration = 0.20;
    r_msg2_main_raw(longPress, "setMinimumPressDuration:",
                    &duration, sizeof(duration),
                    NULL, 0, NULL, 0, NULL, 0);
    r_msg2_main(longPress, "setCancelsTouchesInView:", 1, 0, 0, 0);
    r_msg2_main(view, "addGestureRecognizer:", longPress, 0, 0, 0);
    uint64_t associationKey = r_sel("cyanideWatchLayoutLongPressInvocation");
    r_dlsym_call(R_TIMEOUT, "objc_setAssociatedObject",
                 view, associationKey, invocation,
                 1 /* OBJC_ASSOCIATION_RETAIN_NONATOMIC */, 0, 0, 0, 0);
    r_msg2_main(longPress, "release", 0, 0, 0, 0);
    return true;
}

static uint64_t wl_icon_controller(void)
{
    uint64_t cls = r_class("SBIconController");
    return r_is_objc_ptr(cls) ? wl_safe_msg(cls, "sharedInstance", 0, 0, 0, 0) : 0;
}

static uint64_t wl_root_folder_controller(uint64_t controller, uint64_t manager)
{
    uint64_t owners[] = { manager, controller };
    const char *selectors[] = {
        "rootFolderController",
        "_rootFolderController",
        "rootFolderViewController",
        NULL,
    };
    for (int ownerIndex = 0; ownerIndex < 2; ownerIndex++) {
        for (int selectorIndex = 0; selectors[selectorIndex]; selectorIndex++) {
            uint64_t value = wl_safe_msg(owners[ownerIndex], selectors[selectorIndex],
                                         0, 0, 0, 0);
            if (r_is_objc_ptr(value)) return value;
        }
    }
    return 0;
}

static uint64_t wl_root_folder_view(uint64_t rootController)
{
    const char *selectors[] = { "rootFolderView", "folderView", "view", NULL };
    for (int i = 0; selectors[i]; i++) {
        uint64_t view = wl_safe_msg(rootController, selectors[i], 0, 0, 0, 0);
        if (r_is_objc_ptr(view)) return view;
    }
    return 0;
}

static uint64_t wl_dock_list_view(uint64_t controller,
                                  uint64_t manager,
                                  uint64_t rootController)
{
    uint64_t owners[] = { manager, controller, rootController };
    for (int i = 0; i < 3; i++) {
        uint64_t dock = wl_safe_msg(owners[i], "dockListView", 0, 0, 0, 0);
        if (r_is_objc_ptr(dock)) return dock;
    }
    return 0;
}

static int wl_collect_lists(uint64_t rootController,
                            uint64_t rootView,
                            uint64_t listClass,
                            uint64_t dockList,
                            uint64_t *out,
                            int cap)
{
    int count = 0;
    const char *arraySelectors[] = { "iconListViews", "visibleIconListViews", NULL };
    for (int i = 0; arraySelectors[i] && count < cap; i++) {
        uint64_t array = wl_safe_msg(rootController, arraySelectors[i], 0, 0, 0, 0);
        uint64_t candidates[WL_MAX_LISTS] = {0};
        int candidateCount = wl_copy_array(array, candidates, WL_MAX_LISTS);
        for (int j = 0; j < candidateCount && count < cap; j++) {
            uint64_t list = candidates[j];
            if (list == dockList || wl_pointer_seen(out, count, list)) continue;
            if (r_msg2_main(list, "isKindOfClass:", listClass, 0, 0, 0)) out[count++] = list;
        }
    }

    if (count == 0 && r_is_objc_ptr(rootView)) {
        uint64_t candidates[WL_MAX_LISTS] = {0};
        int candidateCount = sb_collect_views(rootView, listClass,
                                              candidates, WL_MAX_LISTS);
        for (int i = 0; i < candidateCount && count < cap; i++) {
            uint64_t list = candidates[i];
            if (list != dockList && !wl_pointer_seen(out, count, list)) out[count++] = list;
        }
    }
    return count;
}

static uint64_t wl_new_scroll_view(WLRect frame)
{
    uint64_t cls = r_class("UIScrollView");
    uint64_t alloc = r_is_objc_ptr(cls) ? r_msg2_main(cls, "alloc", 0, 0, 0, 0) : 0;
    return r_is_objc_ptr(alloc)
        ? r_msg2_main_raw(alloc, "initWithFrame:",
                          &frame, sizeof(frame),
                          NULL, 0, NULL, 0, NULL, 0)
        : 0;
}

static uint64_t wl_new_view(WLRect frame)
{
    uint64_t cls = r_class("UIView");
    uint64_t alloc = r_is_objc_ptr(cls)
        ? r_msg2_main(cls, "alloc", 0, 0, 0, 0)
        : 0;
    return r_is_objc_ptr(alloc)
        ? r_msg2_main_raw(alloc, "initWithFrame:",
                          &frame, sizeof(frame),
                          NULL, 0, NULL, 0, NULL, 0)
        : 0;
}

static uint64_t wl_new_image_view(WLRect frame, uint64_t image)
{
    if (!r_is_objc_ptr(image)) return 0;
    uint64_t cls = r_class("UIImageView");
    uint64_t alloc = r_is_objc_ptr(cls)
        ? r_msg2_main(cls, "alloc", 0, 0, 0, 0)
        : 0;
    uint64_t view = r_is_objc_ptr(alloc)
        ? r_msg2_main_raw(alloc, "initWithFrame:",
                          &frame, sizeof(frame),
                          NULL, 0, NULL, 0, NULL, 0)
        : 0;
    if (!r_is_objc_ptr(view)) return 0;
    r_msg2_main(view, "setImage:", image, 0, 0, 0);
    r_msg2_main(view, "setContentMode:", 1, 0, 0, 0);
    r_msg2_main(view, "setUserInteractionEnabled:", 0, 0, 0, 0);
    return view;
}

static uint64_t wl_new_initial_label(WLRect frame, const char *text)
{
    uint64_t cls = r_class("UILabel");
    uint64_t alloc = r_is_objc_ptr(cls)
        ? r_msg2_main(cls, "alloc", 0, 0, 0, 0)
        : 0;
    uint64_t label = r_is_objc_ptr(alloc)
        ? r_msg2_main_raw(alloc, "initWithFrame:",
                          &frame, sizeof(frame),
                          NULL, 0, NULL, 0, NULL, 0)
        : 0;
    if (!r_is_objc_ptr(label)) return 0;
    uint64_t value = r_nsstr_retained(text && *text ? text : "?");
    if (r_is_objc_ptr(value)) {
        r_msg2_main(label, "setText:", value, 0, 0, 0);
        r_msg2_main(value, "release", 0, 0, 0, 0);
    }
    r_msg2_main(label, "setTextAlignment:", 1, 0, 0, 0);
    r_msg2_main(label, "setUserInteractionEnabled:", 0, 0, 0, 0);
    return label;
}

static void wl_configure_round_wrapper(uint64_t wrapper, double size)
{
    r_msg2_main(wrapper, "setClipsToBounds:", 1, 0, 0, 0);
    r_msg2_main(wrapper, "setUserInteractionEnabled:", 1, 0, 0, 0);
    uint64_t layer = wl_safe_msg(wrapper, "layer", 0, 0, 0, 0);
    if (r_is_objc_ptr(layer)) {
        wl_set_double(layer, "setCornerRadius:", size * 0.5);
        r_msg2_main(layer, "setMasksToBounds:", 1, 0, 0, 0);
    }
}

static int wl_disable_native_icon_competing_interactions(uint64_t view)
{
    const struct {
        const char *selector;
        const char *ivar;
    } interactions[] = {
        { "tapGestureRecognizer", "_tapGestureRecognizer" },
        { "editingModeGestureRecognizer", "_editingModeGestureRecognizer" },
        { "dragInteraction", "_dragInteraction" },
    };
    int disabled = 0;
    for (int i = 0; i < (int)(sizeof(interactions) / sizeof(interactions[0])); i++) {
        uint64_t interaction = wl_safe_msg(view, interactions[i].selector,
                                           0, 0, 0, 0);
        if (!r_is_objc_ptr(interaction))
            interaction = r_ivar_value(view, interactions[i].ivar);
        if (r_is_objc_ptr(interaction) &&
            r_responds_main(interaction, "setEnabled:")) {
            r_msg2_main(interaction, "setEnabled:", 0, 0, 0, 0);
            disabled++;
        }
    }
    return disabled;
}

static bool wl_forbid_native_icon_editing(uint64_t view)
{
    if (!r_is_objc_ptr(view)) return false;
    if (r_responds_main(view, "setEditing:animated:"))
        r_msg2_main(view, "setEditing:animated:", 0, 0, 0, 0);
    else if (r_responds_main(view, "setEditing:"))
        r_msg2_main(view, "setEditing:", 0, 0, 0, 0);
    if (r_responds_main(view, "setAllowsEditingAnimation:"))
        r_msg2_main(view, "setAllowsEditingAnimation:", 0, 0, 0, 0);

    if (!r_responds_main(view, "startForbiddingEditingModeWithReason:")) return false;
    uint64_t associationKey = r_sel("cyanideWatchLayoutEditingReason");
    uint64_t existingReason = r_dlsym_call(
        R_TIMEOUT, "objc_getAssociatedObject",
        view, associationKey, 0, 0, 0, 0, 0, 0);
    if (r_is_objc_ptr(existingReason)) return true;
    uint64_t reason = r_nsstr_retained("CyanideWatchLayout");
    if (!r_is_objc_ptr(reason)) return false;
    r_msg2_main(view, "startForbiddingEditingModeWithReason:",
                reason, 0, 0, 0);
    r_dlsym_call(R_TIMEOUT, "objc_setAssociatedObject",
                 view, associationKey, reason,
                 1 /* OBJC_ASSOCIATION_RETAIN_NONATOMIC */, 0, 0, 0, 0);
    r_msg2_main(reason, "release", 0, 0, 0, 0);
    return true;
}

static bool wl_scale_native_icon_view(uint64_t view,
                                      uint64_t tile,
                                      bool logGeometry)
{
    if (!r_is_objc_ptr(view) || !r_is_objc_ptr(tile)) return false;
    r_msg2_main(view, "setNeedsLayout", 0, 0, 0, 0);
    r_msg2_main(view, "layoutIfNeeded", 0, 0, 0, 0);

    WLRect nativeBounds = {0};
    WLRect tileBounds = {0};
    if (!wl_get_rect(view, "bounds", &nativeBounds) ||
        !wl_get_rect(tile, "bounds", &tileBounds) ||
        nativeBounds.width <= 0.0 || nativeBounds.height <= 0.0 ||
        tileBounds.width <= 0.0 || tileBounds.height <= 0.0) return false;

    double scale = fmin(tileBounds.width / nativeBounds.width,
                        tileBounds.height / nativeBounds.height);
    if (!isfinite(scale) || scale <= 0.0) return false;
    WLAffineTransform transform = {scale, 0.0, 0.0, scale, 0.0, 0.0};
    r_msg2_main_raw(view, "setTransform:",
                    &transform, sizeof(transform),
                    NULL, 0, NULL, 0, NULL, 0);
    wl_set_point(view, "setCenter:",
                 (WLPoint){tileBounds.width * 0.5,
                           tileBounds.height * 0.5});
    if (logGeometry) {
        printf("[WATCHLAYOUT] native icon geometry %.1fx%.1f -> %.1fx%.1f scale=%.3f\n",
               nativeBounds.width, nativeBounds.height,
               tileBounds.width, tileBounds.height, scale);
    }
    return true;
}

static uint64_t wl_new_native_icon_view(uint64_t bundleID,
                                        uint64_t manager,
                                        const WLIconSource *source)
{
    uint64_t icon = wl_fetch_icon_model(bundleID, source);
    uint64_t cls = r_class("SBIconView");
    if (!r_is_objc_ptr(icon) || !r_is_objc_ptr(cls) ||
        !r_is_objc_ptr(manager)) return 0;

    uint64_t provider = wl_safe_msg(manager, "listLayoutProvider", 0, 0, 0, 0);
    uint64_t alloc = r_msg2_main(cls, "alloc", 0, 0, 0, 0);
    if (!r_is_objc_ptr(alloc)) return 0;

    // Option 2 hides the stock label while preserving native interactions.
    uint64_t view = r_responds_main(
        alloc, "initWithConfigurationOptions:listLayoutProvider:")
        ? r_msg2_main(alloc, "initWithConfigurationOptions:listLayoutProvider:",
                      2, provider, 0, 0)
        : r_msg2_main(alloc, "initWithConfigurationOptions:", 2, 0, 0, 0);
    if (!r_is_objc_ptr(view)) return 0;

    uint64_t location = wl_safe_msg(cls, "defaultIconLocation", 0, 0, 0, 0);
    if (r_is_objc_ptr(location))
        r_msg2_main(view, "setLocation:", location, 0, 0, 0);
    if (r_is_objc_ptr(provider) &&
        r_responds_main(view, "setListLayoutProvider:"))
        r_msg2_main(view, "setListLayoutProvider:", provider, 0, 0, 0);

    if (r_responds_main(manager, "configureIconView:forIcon:"))
        r_msg2_main(manager, "configureIconView:forIcon:", view, icon, 0, 0);
    else
        r_msg2_main(view, "setDelegate:", manager, 0, 0, 0);
    r_msg2_main(view, "setIcon:", icon, 0, 0, 0);
    r_msg2_main(view, "setLabelHidden:", 1, 0, 0, 0);
    r_msg2_main(view, "setAllowsCloseBox:", 0, 0, 0, 0);

    wl_disable_native_icon_competing_interactions(view);
    wl_forbid_native_icon_editing(view);
    uint64_t contextMenu = wl_safe_msg(view, "contextMenuInteraction",
                                       0, 0, 0, 0);
    if (!r_is_objc_ptr(contextMenu)) {
        r_msg2_main(view, "release", 0, 0, 0, 0);
        return 0;
    }
    return view;
}

static void wl_layout_position(int index,
                               double width,
                               double iconSize,
                               double topPadding,
                               WLPoint *center)
{
    int remaining = index;
    int row = 0;
    while (true) {
        int capacity = (row % 2 == 0) ? 5 : 4;
        if (remaining < capacity) break;
        remaining -= capacity;
        row++;
    }

    int capacity = (row % 2 == 0) ? 5 : 4;
    double availableSpacing = capacity > 1
        ? (width - iconSize - 20.0) / (capacity - 1)
        : iconSize;
    double compact = (double)s_compact_percent / 100.0;
    double targetSpacing = iconSize * (0.92 + 0.38 * compact);
    double spacing = fmin(targetSpacing, availableSpacing);
    if (spacing < iconSize * 1.06) spacing = iconSize * 1.06;
    double rowWidth = iconSize + (capacity - 1) * spacing;
    double startX = (width - rowWidth) * 0.5 + iconSize * 0.5;
    center->x = startX + remaining * spacing;
    double verticalStep = iconSize * (0.98 + 0.25 * compact);
    center->y = topPadding + iconSize * 0.5 + row * verticalStep;
}

static uint64_t wl_direct_child_below_root(uint64_t view, uint64_t root)
{
    uint64_t current = view;
    for (int depth = 0; depth < 12 && r_is_objc_ptr(current); depth++) {
        uint64_t parent = wl_safe_msg(current, "superview", 0, 0, 0, 0);
        if (parent == root) return current;
        current = parent;
    }
    return 0;
}

static void wl_release_state_objects(void)
{
    for (int i = 0; i < s_list_count; i++) {
        if (r_is_objc_ptr(s_lists[i].listView))
            r_msg2_main(s_lists[i].listView, "release", 0, 0, 0, 0);
    }
    if (r_is_objc_ptr(s_scroll_view))
        r_msg2_main(s_scroll_view, "release", 0, 0, 0, 0);
    if (r_is_objc_ptr(s_root_view))
        r_msg2_main(s_root_view, "release", 0, 0, 0, 0);
    for (int i = 0; i < s_gesture_guard_count; i++) {
        if (r_is_objc_ptr(s_gesture_guards[i].recognizer))
            r_msg2_main(s_gesture_guards[i].recognizer,
                        "release", 0, 0, 0, 0);
    }
}

static void wl_clear_local_state(void)
{
    memset(s_lists, 0, sizeof(s_lists));
    s_list_count = 0;
    memset(s_gesture_guards, 0, sizeof(s_gesture_guards));
    s_gesture_guard_count = 0;
    s_root_view = 0;
    s_scroll_view = 0;
    s_active = false;
}

void watchlayout_configure(int compactPercent, int iconScalePercent)
{
    if (compactPercent < 60) compactPercent = 60;
    if (compactPercent > 100) compactPercent = 100;
    if (iconScalePercent < 60) iconScalePercent = 60;
    if (iconScalePercent > 110) iconScalePercent = 110;
    if (s_compact_percent != compactPercent ||
        s_icon_scale_percent != iconScalePercent) {
        s_configuration_dirty = true;
        s_retry_after = 0.0;
    }
    s_compact_percent = compactPercent;
    s_icon_scale_percent = iconScalePercent;
    log_user("[WATCHLAYOUT][CONFIG] implementation=overlay-v6 compact=%d%% iconScale=%d%% layout=5/4 verticalScroll=1.\n",
             s_compact_percent, s_icon_scale_percent);
}

bool watchlayout_stop_in_session(void)
{
    if (!watchlayout_has_cached_state()) {
        // Treat an already-stopped overlay as a successful, idempotent cleanup.
        // This also lets a manual off/on toggle retry immediately after a
        // previous bounded discovery failure.
        s_configuration_dirty = true;
        s_retry_after = 0.0;
        s_suppressed_retries = 0;
        return true;
    }

    uint32_t oldSettle = r_settle_us(0);
    for (int i = 0; i < s_list_count; i++) {
        WLListState *state = &s_lists[i];
        if (!r_is_objc_ptr(state->listView)) continue;
        wl_set_double(state->listView, "setAlpha:", state->originalAlpha);
        r_msg2_main(state->listView, "setNeedsLayout", 0, 0, 0, 0);
        r_msg2_main(state->listView, "layoutIfNeeded", 0, 0, 0, 0);
    }
    if (r_is_objc_ptr(s_scroll_view))
        r_msg2_main(s_scroll_view, "removeFromSuperview", 0, 0, 0, 0);
    int restoredGestures = wl_restore_ancestor_editing_gestures();
    r_settle_us(oldSettle);

    int lists = s_list_count;
    wl_release_state_objects();
    wl_clear_local_state();
    s_configuration_dirty = true;
    s_retry_after = 0.0;
    s_suppressed_retries = 0;
    printf("[WATCHLAYOUT] removed overlay; relaidLists=%d restoredGestures=%d iconModelWrites=0\n",
           lists, restoredGestures);
    log_user("[WATCHLAYOUT][RESTORE] overlayRemoved=1 relaidLists=%d restoredGestures=%d iconModelWrites=0.\n",
             lists, restoredGestures);
    return lists > 0;
}

bool watchlayout_has_cached_state(void)
{
    return s_active || r_is_objc_ptr(s_scroll_view);
}

static bool wl_apply_failed(const char *stage)
{
    s_retry_after = [NSDate timeIntervalSinceReferenceDate] + 30.0;
    s_suppressed_retries = 0;
    log_user("[WATCHLAYOUT][FAIL] stage=%s retryCooldown=30s nativeListsRemainVisible=1 partialOverlayCleaned=1.\n",
             stage ? stage : "unknown");
    return false;
}

bool watchlayout_apply_in_session(void)
{
    if (watchlayout_has_cached_state() && !s_configuration_dirty) return true;
    if (watchlayout_has_cached_state()) (void)watchlayout_stop_in_session();

    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now < s_retry_after) {
        s_suppressed_retries++;
        if (s_suppressed_retries == 1)
            log_user("[WATCHLAYOUT][BACKOFF] suppressing repeated apply attempts for %.0fs after the last failure.\n",
                     s_retry_after - now);
        return false;
    }

    printf("[WATCHLAYOUT] implementation=overlay-v6 scaleOwner=SBIconView editingGuard=forbid boundedReads=1\n");

    log_user("[WATCHLAYOUT][1/3] Reading the SpringBoard app catalog without remote string copies...\n");
    WLAppEntry apps[WL_MAX_APPS] = {0};
    int appCount = wl_installed_apps(apps, WL_MAX_APPS);
    if (appCount == 0) {
        printf("[WATCHLAYOUT] installed app catalog is empty\n");
        return wl_apply_failed("application-catalog");
    }
    printf("[WATCHLAYOUT] installed app catalog=%d source=SBApplicationController remoteStringReads=0\n",
           appCount);

    log_user("[WATCHLAYOUT][2/3] Locating the Home Screen host and creating the honeycomb canvas...\n");
    printf("[WATCHLAYOUT] resolving SpringBoard Home Screen host\n");
    uint64_t controller = wl_icon_controller();
    uint64_t manager = wl_safe_msg(controller, "iconManager", 0, 0, 0, 0);
    uint64_t rootController = wl_root_folder_controller(controller, manager);
    uint64_t rootView = wl_root_folder_view(rootController);
    uint64_t listClass = r_class("SBIconListView");
    if (!r_is_objc_ptr(controller) || !r_is_objc_ptr(rootController) ||
        !r_is_objc_ptr(rootView) || !r_is_objc_ptr(listClass)) {
        printf("[WATCHLAYOUT] SpringBoard Home Screen objects unavailable\n");
        return wl_apply_failed("home-screen-host");
    }

    WLRect rootBounds = {0};
    if (!wl_get_rect(rootView, "bounds", &rootBounds) ||
        rootBounds.width < 200.0 || rootBounds.height < 300.0) {
        printf("[WATCHLAYOUT] invalid root bounds %.1fx%.1f\n",
               rootBounds.width, rootBounds.height);
        return wl_apply_failed("root-bounds");
    }
    WLInsets safeArea = {0};
    (void)wl_get_insets(rootView, "safeAreaInsets", &safeArea);
    double topPadding = safeArea.top > 0.0 ? safeArea.top + 16.0 : 72.0;

    uint64_t dockList = wl_dock_list_view(controller, manager, rootController);
    uint64_t lists[WL_MAX_LISTS] = {0};
    uint32_t collectionSettle = r_settle_us(0);
    int listCount = wl_collect_lists(rootController, rootView, listClass,
                                     dockList, lists, WL_MAX_LISTS);
    r_settle_us(collectionSettle);
    if (listCount <= 0) {
        printf("[WATCHLAYOUT] no Home Screen icon lists found\n");
        return wl_apply_failed("icon-lists");
    }

    uint64_t dockChild = wl_direct_child_below_root(dockList, rootView);
    WLRect dockFrame = {0};
    double dockReservedHeight = fmax(110.0, safeArea.bottom + 82.0);
    double overlayHeight = fmax(300.0,
                                rootBounds.height - dockReservedHeight);
    if (r_is_objc_ptr(dockChild) && wl_get_rect(dockChild, "frame", &dockFrame) &&
        dockFrame.y > rootBounds.height * 0.55 && dockFrame.y < rootBounds.height) {
        overlayHeight = fmin(overlayHeight, dockFrame.y - 8.0);
    }
    if (overlayHeight < 300.0)
        overlayHeight = fmax(300.0, rootBounds.height - dockReservedHeight);

    uint64_t overlayHost = wl_safe_msg(rootView, "superview", 0, 0, 0, 0);
    WLRect rootFrame = {0};
    if (!r_is_objc_ptr(overlayHost) || !wl_get_rect(rootView, "frame", &rootFrame)) {
        overlayHost = rootView;
        rootFrame = rootBounds;
    }
    WLRect scrollFrame = {
        rootFrame.x,
        rootFrame.y,
        rootBounds.width,
        overlayHeight,
    };
    uint64_t scroll = wl_new_scroll_view(scrollFrame);
    if (!r_is_objc_ptr(scroll)) return wl_apply_failed("scroll-overlay");
    r_msg2_main(scroll, "setOpaque:", 0, 0, 0, 0);
    r_msg2_main(scroll, "setAlwaysBounceVertical:", 1, 0, 0, 0);
    r_msg2_main(scroll, "setShowsVerticalScrollIndicator:", 0, 0, 0, 0);
    r_msg2_main(scroll, "setShowsHorizontalScrollIndicator:", 0, 0, 0, 0);
    r_msg2_main(scroll, "setDirectionalLockEnabled:", 1, 0, 0, 0);
    r_msg2_main(scroll, "setDelaysContentTouches:", 1, 0, 0, 0);
    r_msg2_main(scroll, "setCanCancelContentTouches:", 1, 0, 0, 0);
    r_msg2_main(scroll, "setClipsToBounds:", 1, 0, 0, 0);
    r_msg2_main(overlayHost, "addSubview:", scroll, 0, 0, 0);

    s_root_view = overlayHost;
    s_scroll_view = scroll;
    r_msg2_main(s_root_view, "retain", 0, 0, 0, 0);
    s_active = true;
    int disabledAncestorGestures =
        wl_disable_ancestor_editing_gestures(scroll, controller);
    printf("[WATCHLAYOUT][GESTURE-GUARD] active=%d\n",
           disabledAncestorGestures);

    for (int i = 0; i < listCount && s_list_count < WL_MAX_LISTS; i++) {
        double alpha = 1.0;
        if (!wl_get_double(lists[i], "alpha", &alpha)) alpha = 1.0;
        r_msg2_main(lists[i], "retain", 0, 0, 0, 0);
        s_lists[s_list_count++] = (WLListState) {
            .listView = lists[i],
            .originalAlpha = alpha,
        };
    }

    uint64_t workspaceClass = r_class("LSApplicationWorkspace");
    uint64_t workspace = r_is_objc_ptr(workspaceClass)
        ? wl_safe_msg(workspaceClass, "defaultWorkspace", 0, 0, 0, 0)
        : 0;
    if (!r_is_objc_ptr(workspace) ||
        !r_responds_main(workspace, "openApplicationWithBundleID:")) {
        printf("[WATCHLAYOUT] LSApplicationWorkspace launch API unavailable\n");
        (void)watchlayout_stop_in_session();
        return wl_apply_failed("launch-workspace");
    }

    WLIconSource iconSource = {0};
    iconSource.imageClass = r_class("UIImage");
    iconSource.privateImageAPI = r_is_objc_ptr(iconSource.imageClass) &&
        r_responds(iconSource.imageClass,
                   "_applicationIconImageForBundleIdentifier:format:scale:");
    iconSource.iconModel = wl_safe_msg(manager, "iconModel", 0, 0, 0, 0);
    if (r_is_objc_ptr(iconSource.iconModel)) {
        iconSource.applicationIconForBundle = r_responds(
            iconSource.iconModel, "applicationIconForBundleIdentifier:");
        iconSource.expectedIconForDisplay = r_responds(
            iconSource.iconModel, "expectedIconForDisplayIdentifier:");
    }
    uint64_t applicationIconClass = r_class("SBApplicationIcon");
    iconSource.iconImage = wl_class_has_instance_method(
        applicationIconClass, "iconImage");
    iconSource.getIconImage = wl_class_has_instance_method(
        applicationIconClass, "getIconImage:");
    iconSource.generateIconImage = wl_class_has_instance_method(
        applicationIconClass, "generateIconImage:");
    printf("[WATCHLAYOUT] icon source privateUIImage=%d iconModel=%d modelLookup=%d/%d imageSelectors=%d/%d/%d\n",
           iconSource.privateImageAPI,
           r_is_objc_ptr(iconSource.iconModel),
           iconSource.applicationIconForBundle,
           iconSource.expectedIconForDisplay,
           iconSource.iconImage,
           iconSource.getIconImage,
           iconSource.generateIconImage);

    double baseIconSize = rootBounds.width < 360.0 ? 52.0 : 60.0;
    double iconSize = baseIconSize * ((double)s_icon_scale_percent / 100.0);
    if (iconSize < 38.0) iconSize = 38.0;
    if (iconSize > 68.0) iconSize = 68.0;
    uint32_t oldSettle = r_settle_us(0);
    int installed = 0;
    int imageFailures = 0;
    int actionFailures = 0;
    int longPressGuardFailures = 0;
    int nativeMenuIcons = 0;
    int scaleFailures = 0;
    int editingGestureGuards = 0;
    int editingModeGuards = 0;
    log_user("[WATCHLAYOUT][3/3] Building %d lightweight pressable icons...\n",
             appCount);
    for (int appIndex = 0; appIndex < appCount; appIndex++) {
        uint64_t bundleID = apps[appIndex].bundleID;
        if (!r_is_objc_ptr(bundleID)) continue;

        WLPoint center = {0};
        wl_layout_position(installed, rootBounds.width, iconSize,
                           topPadding, &center);
        WLRect tileFrame = {
            center.x - iconSize * 0.5,
            center.y - iconSize * 0.5,
            iconSize,
            iconSize,
        };
        uint64_t tile = wl_new_view(tileFrame);
        if (!r_is_objc_ptr(tile)) continue;
        wl_configure_round_wrapper(tile, iconSize);

        // A native SBIconView costs dozens of cross-process calls per app and
        // was the source of the apparently frozen first pass. UIImageView plus
        // an invocation-backed tap gesture remains fully pressable while being
        // much cheaper and avoiding editing-mode side effects.
        uint64_t image = wl_fetch_icon_image(bundleID, &iconSource);
        if (r_is_objc_ptr(image)) {
            uint64_t imageView = wl_new_image_view(
                (WLRect){0.0, 0.0, iconSize, iconSize}, image);
            if (r_is_objc_ptr(imageView)) {
                r_msg2_main(tile, "addSubview:", imageView, 0, 0, 0);
                r_msg2_main(imageView, "release", 0, 0, 0, 0);
            } else {
                imageFailures++;
            }
        } else {
            imageFailures++;
            uint64_t label = wl_new_initial_label(
                (WLRect){0.0, 0.0, iconSize, iconSize}, "?");
            if (r_is_objc_ptr(label)) {
                r_msg2_main(tile, "addSubview:", label, 0, 0, 0);
                r_msg2_main(label, "release", 0, 0, 0, 0);
            }
        }

        r_msg2_main(tile, "setAccessibilityLabel:", bundleID, 0, 0, 0);
        if (!wl_bind_open_action(tile, workspace, bundleID))
            actionFailures++;
        // Do not add a second long-press recognizer to every tile. The tap
        // invocation is sufficient for launching, and omitting the redundant
        // recognizer removes another expensive group of remote calls per app.
        r_msg2_main(scroll, "addSubview:", tile, 0, 0, 0);
        r_msg2_main(tile, "release", 0, 0, 0, 0);
        installed++;
        if (installed == 1 || installed % 20 == 0 || installed == appCount) {
            log_user("[WATCHLAYOUT][BUILD] icons=%d/%d pressActions=%d imageFallbacks=%d.\n",
                     installed, appCount, installed - actionFailures,
                     imageFailures);
        }
    }

    for (int i = 0; i < s_list_count; i++)
        wl_set_double(s_lists[i].listView, "setAlpha:", 0.0);

    WLPoint lastCenter = {0};
    wl_layout_position(installed > 0 ? installed - 1 : 0,
                       rootBounds.width, iconSize, topPadding, &lastCenter);
    WLSize contentSize = {
        rootBounds.width,
        fmax(overlayHeight + 1.0, lastCenter.y + iconSize * 0.5 + 60.0),
    };
    r_msg2_main_raw(scroll, "setContentSize:",
                    &contentSize, sizeof(contentSize),
                    NULL, 0, NULL, 0, NULL, 0);
    r_settle_us(oldSettle);

    if (installed <= 0) {
        (void)watchlayout_stop_in_session();
        return wl_apply_failed("icon-install");
    }
    if (actionFailures >= installed) {
        printf("[WATCHLAYOUT] no app launch gestures were installed\n");
        (void)watchlayout_stop_in_session();
        return wl_apply_failed("tap-actions");
    }

    printf("[WATCHLAYOUT] overlay lists=%d catalogApps=%d nativeMenus=%d scaleFailures=%d editingGestureGuards=%d editingModeGuards=%d imageFailures=%d actionFailures=%d longPressGuardFailures=%d viewportHeight=%.1f contentHeight=%.1f layout=5/4 compact=%d%% scale=%d%% modelWrites=0\n",
           s_list_count, installed, nativeMenuIcons,
           scaleFailures, editingGestureGuards, editingModeGuards,
           imageFailures, actionFailures,
           longPressGuardFailures,
           overlayHeight, contentSize.height,
           s_compact_percent, s_icon_scale_percent);
    log_user("[WATCHLAYOUT][APPLY] implementation=overlay-v6 overlay=scrolling-honeycomb layout=5/4 source=SBApplicationController lists=%d apps=%d systemAppsIncluded=1 folderContentsIncluded=0 nativeMenus=%d scaleFailures=%d editingGestureGuards=%d editingModeGuards=%d imageFailures=%d actionFailures=%d longPressGuardFailures=%d viewportHeight=%.1f compact=%d%% scale=%d%% mainThreadLaunch=1 boundedReads=1 iconModelWrites=0.\n",
             s_list_count, installed, nativeMenuIcons,
             scaleFailures, editingGestureGuards, editingModeGuards,
             imageFailures, actionFailures,
             longPressGuardFailures, overlayHeight,
             s_compact_percent, s_icon_scale_percent);
    s_configuration_dirty = false;
    s_retry_after = 0.0;
    s_suppressed_retries = 0;
    return true;
}

void watchlayout_forget_remote_state(void)
{
    int forgottenLists = s_list_count;
    wl_clear_local_state();
    s_configuration_dirty = true;
    s_retry_after = 0.0;
    s_suppressed_retries = 0;
    if (forgottenLists > 0) {
        printf("[WATCHLAYOUT] forgot stale overlay state lists=%d\n",
               forgottenLists);
    }
}
