#import "cylinderlite.h"
#import "../remote_objc.h"
#import "../sb_walk.h"
#import "../../TaskRop/RemoteCall.h"
#import "../../LogTextView.h"

#import <Foundation/Foundation.h>
#import <math.h>
#import <string.h>

#define CY_LIST_CAP 16
#define CY_PROGRESS_STEPS 40
#define CY_FAILURE_LIMIT 2

static bool gCyApplied = false;
static bool gCyCircuitOpen = false;
static int gCyDepth = -10;
static int gCyPerspectiveDistance = 650;
static int gCyPageCap = CY_LIST_CAP;
static int gCyTransportFailures = 0;
static int gCyExcludedLists = 0;
static uint64_t gCyLists[CY_LIST_CAP] = {0};
static uint64_t gCyScrollViews[CY_LIST_CAP] = {0};
static int gCyProgressBuckets[CY_LIST_CAP] = {0};
static double gCyBaseProgress[CY_LIST_CAP] = {0};
static double gCyPageOffset = 0.0;
static bool gCyBaselineReady = false;
static int gCyListCount = 0;
static uint64_t gCyKeyPositionX = 0;
static uint64_t gCyKeyBoundsWidth = 0;
static uint64_t gCyKeyBoundsOriginX = 0;
static uint64_t gCyKeyRotationY = 0;
static uint64_t gCyKeyTranslationZ = 0;

static bool cy_prepare_scalar_keys(void)
{
    if (!gCyKeyPositionX) gCyKeyPositionX = r_nsstr_retained("position.x");
    if (!gCyKeyBoundsWidth) gCyKeyBoundsWidth = r_nsstr_retained("bounds.size.width");
    if (!gCyKeyBoundsOriginX) gCyKeyBoundsOriginX = r_nsstr_retained("bounds.origin.x");
    if (!gCyKeyRotationY) gCyKeyRotationY = r_nsstr_retained("transform.rotation.y");
    if (!gCyKeyTranslationZ) gCyKeyTranslationZ = r_nsstr_retained("transform.translation.z");
    return r_is_objc_ptr(gCyKeyPositionX) &&
           r_is_objc_ptr(gCyKeyBoundsWidth) &&
           r_is_objc_ptr(gCyKeyBoundsOriginX) &&
           r_is_objc_ptr(gCyKeyRotationY) &&
           r_is_objc_ptr(gCyKeyTranslationZ);
}

static bool cy_integer_keypath(uint64_t object, uint64_t key, int64_t *out)
{
    if (!r_is_objc_ptr(object) || !r_is_objc_ptr(key) || !out) return false;
    uint64_t number = r_msg2_main(object, "valueForKeyPath:", key, 0, 0, 0);
    if (!r_is_objc_ptr(number)) return false;
    *out = (int64_t)r_msg2_main(number, "longLongValue", 0, 0, 0, 0);
    return remote_call_current_success();
}

static uint64_t cy_scroll_view_for_list(uint64_t list)
{
    uint64_t scrollClass = r_class("UIScrollView");
    if (!r_is_objc_ptr(scrollClass)) return 0;
    uint64_t view = r_msg2_main(list, "superview", 0, 0, 0, 0);
    for (int depth = 0; r_is_objc_ptr(view) && depth < 8; depth++) {
        if (r_msg2_main(view, "isKindOfClass:", scrollClass, 0, 0, 0)) return view;
        view = r_msg2_main(view, "superview", 0, 0, 0, 0);
    }
    return 0;
}

// Read scalar NSNumber values through KVC. This intentionally avoids
// r_msg2_main_struct_ret(), whose return-buffer remote_read path cannot map
// some malloc pages on affected devices (vm_get_object:148).
static bool cy_page_progress(uint64_t list, uint64_t scrollView, double *outProgress)
{
    if (!outProgress || !cy_prepare_scalar_keys()) return false;
    uint64_t listLayer = r_msg2_main(list, "layer", 0, 0, 0, 0);
    uint64_t scrollLayer = r_msg2_main(scrollView, "layer", 0, 0, 0, 0);
    if (!r_is_objc_ptr(listLayer) || !r_is_objc_ptr(scrollLayer)) return false;
    int64_t positionX = 0, offsetX = 0, width = 0;
    if (!cy_integer_keypath(listLayer, gCyKeyPositionX, &positionX) ||
        !cy_integer_keypath(scrollLayer, gCyKeyBoundsOriginX, &offsetX) ||
        !cy_integer_keypath(scrollLayer, gCyKeyBoundsWidth, &width) || width <= 1)
        return false;
    *outProgress = ((double)positionX - (double)offsetX - (double)width * 0.5) /
                   (double)width;
    return true;
}

static uint64_t cy_decimal_number(double value)
{
    uint64_t numberClass = r_class("NSDecimalNumber");
    if (!r_is_objc_ptr(numberClass)) return 0;
    bool negative = value < 0.0;
    uint64_t mantissa = (uint64_t)llround(fabs(value) * 10000.0);
    return r_msg2_main(numberClass,
                       "decimalNumberWithMantissa:exponent:isNegative:",
                       mantissa, (uint64_t)(int64_t)-4, negative ? 1 : 0, 0);
}

static bool cy_set_page_transform(uint64_t list, double progress)
{
    if (!r_is_objc_ptr(list) || !cy_prepare_scalar_keys()) return false;
    uint64_t layer = r_msg2_main(list, "layer", 0, 0, 0, 0);
    if (!r_is_objc_ptr(layer)) return false;

    double distanceScale = 650.0 / (double)gCyPerspectiveDistance;
    double angle = progress * 1.35 * distanceScale;
    double depth = (double)gCyDepth * fabs(progress);
    uint64_t angleNumber = cy_decimal_number(angle);
    uint64_t depthNumber = cy_decimal_number(depth);
    if (!r_is_objc_ptr(angleNumber) || !r_is_objc_ptr(depthNumber)) return false;

    // Scalar KVC avoids both struct-return reads and CATransform3D argument
    // buffers. The VM shared-page mapper is never used by this mutation path.
    r_msg2_main(layer, "setValue:forKeyPath:", angleNumber, gCyKeyRotationY, 0, 0);
    r_msg2_main(layer, "setValue:forKeyPath:", depthNumber, gCyKeyTranslationZ, 0, 0);
    return remote_call_current_success();
}

static bool cy_list_known(uint64_t list)
{
    for (int i = 0; i < gCyListCount; i++)
        if (gCyLists[i] == list) return true;
    return false;
}

static int cy_discover_pages(void)
{
    uint64_t listClass = r_class("SBIconListView");
    if (!r_is_objc_ptr(listClass)) return 0;

    uint64_t lists[32] = {0};
    int count = sb_collect_views_in_windows(listClass, lists, 32);
    int added = 0;
    for (int i = 0; i < count && gCyListCount < gCyPageCap; i++) {
        uint64_t list = lists[i];
        if (!r_is_objc_ptr(list) || cy_list_known(list)) continue;
        uint64_t scrollView = cy_scroll_view_for_list(list);
        // Home pages live in a paging scroll view. Dock lists have no such
        // ancestor and App Library collection views do not page horizontally,
        // so this structural gate avoids private class-name reads entirely.
        if (!r_is_objc_ptr(scrollView) ||
            !r_msg2_main(scrollView, "isPagingEnabled", 0, 0, 0, 0)) {
            gCyExcludedLists++;
            continue;
        }
        // Retaining the page and its scroll container keeps scalar geometry
        // calls valid while SpringBoard recycles neighboring content.
        r_msg2_main(list, "retain", 0, 0, 0, 0);
        r_msg2_main(scrollView, "retain", 0, 0, 0, 0);
        gCyLists[gCyListCount] = list;
        gCyScrollViews[gCyListCount] = scrollView;
        gCyProgressBuckets[gCyListCount] = INT32_MIN;
        double measured = 0.0;
        if (gCyBaselineReady && cy_page_progress(list, scrollView, &measured))
            gCyBaseProgress[gCyListCount] = measured - gCyPageOffset;
        else
            gCyBaselineReady = false;
        gCyListCount++;
        added++;
    }
    return added;
}

static bool cy_rebuild_baseline(void)
{
    if (gCyListCount == 0) return false;
    for (int i = 0; i < gCyListCount; i++) {
        if (!cy_page_progress(gCyLists[i], gCyScrollViews[i], &gCyBaseProgress[i])) {
            gCyBaselineReady = false;
            return false;
        }
        gCyProgressBuckets[i] = INT32_MIN;
    }
    gCyPageOffset = 0.0;
    gCyBaselineReady = true;
    return true;
}

static int cy_anchor_page(void)
{
    int anchor = 0;
    double bestDistance = HUGE_VAL;
    for (int i = 0; i < gCyListCount; i++) {
        double distance = fabs(gCyBaseProgress[i] + gCyPageOffset);
        if (distance < bestDistance) {
            bestDistance = distance;
            anchor = i;
        }
    }
    return anchor;
}

static bool cy_note_transport_result(bool success)
{
    bool transportOK = remote_call_current_success();
    if (transportOK) {
        gCyTransportFailures = 0;
        return success;
    }
    gCyTransportFailures++;
    if (gCyTransportFailures >= CY_FAILURE_LIMIT) {
        gCyCircuitOpen = true;
        log_user("[CYLINDER][SAFETY] refresh circuit opened after %d transport failures; further remote calls are blocked until Run or Disable.\n",
                 gCyTransportFailures);
    }
    return false;
}

bool cylinderlite_refresh_in_session(bool discoverPages)
{
    if (gCyCircuitOpen || remote_call_current_pid() <= 0) return false;
    if (discoverPages || gCyListCount == 0) cy_discover_pages();
    if (gCyListCount == 0) return cy_note_transport_result(false);
    if (!gCyBaselineReady && !cy_rebuild_baseline())
        return cy_note_transport_result(false);

    int anchor = cy_anchor_page();
    double measuredAnchor = 0.0;
    if (!cy_page_progress(gCyLists[anchor], gCyScrollViews[anchor], &measuredAnchor))
        return cy_note_transport_result(false);
    double newOffset = measuredAnchor - gCyBaseProgress[anchor];
    // A large discontinuity means SpringBoard rebuilt or repositioned its page
    // container. Re-baseline instead of sending transforms from stale geometry.
    if (fabs(newOffset - gCyPageOffset) > 1.5) {
        if (!cy_rebuild_baseline()) return cy_note_transport_result(false);
        newOffset = 0.0;
    }
    gCyPageOffset = newOffset;

    int transformed = 0;
    int unchanged = 0;
    for (int i = 0; i < gCyListCount; i++) {
        double progress = gCyBaseProgress[i] + gCyPageOffset;
        if (progress < -1.25) progress = -1.25;
        if (progress > 1.25) progress = 1.25;

        // Quantization avoids a full remote setter call for sub-pixel scroll
        // noise while preserving 40 smooth positions per page width.
        int bucket = (int)llround(progress * CY_PROGRESS_STEPS);
        if (bucket == gCyProgressBuckets[i]) {
            unchanged++;
            continue;
        }
        double stableProgress = (double)bucket / (double)CY_PROGRESS_STEPS;
        if (cy_set_page_transform(gCyLists[i], stableProgress)) {
            gCyProgressBuckets[i] = bucket;
            transformed++;
        }
    }

    bool success = transformed > 0 || unchanged > 0;
    if (!cy_note_transport_result(success)) return false;
    gCyApplied = success;
    return success;
}

bool cylinderlite_apply_in_session(void)
{
    printf("[CYLINDER] apply scalar-page-layer engine\n");
    gCyCircuitOpen = false;
    gCyTransportFailures = 0;
    printf("[CYLINDER] stage=1/3 scalar-key-preflight remoteReads=0\n");
    if (!cy_prepare_scalar_keys()) {
        log_user("[CYLINDER][FAIL] stage=scalar-key-preflight remoteReads=0 result=transport-unavailable.\n");
        cylinderlite_forget_remote_state();
        return false;
    }
    printf("[CYLINDER] stage=2/3 paging-list-discovery privateClassReads=0\n");
    int added = cy_discover_pages();
    printf("[CYLINDER] stage=3/3 scalar-baseline-and-transform pages=%d\n", gCyListCount);
    bool active = cylinderlite_refresh_in_session(false);
    printf("[CYLINDER] pages=%d added=%d excluded=%d pageMutationsOnly=1 iconMutations=0 result=%d\n",
           gCyListCount, added, gCyExcludedLists, active);
    log_user("[CYLINDER][APPLY] engine=scalar-page-layer pages=%d newlyDiscovered=%d excludedNonPagingLists=%d depth=%d curveDistance=%d pageCap=%d remoteReads=0 structBuffers=0 iconMutations=0 tapsPreserved=1 transportFailures=%d result=%s.\n",
             gCyListCount, added, gCyExcludedLists, gCyDepth,
             gCyPerspectiveDistance, gCyPageCap, gCyTransportFailures,
             active ? "active" : "waiting");
    return active;
}

bool cylinderlite_stop_in_session(void)
{
    printf("[CYLINDER] stop\n");
    if (remote_call_current_pid() <= 0 ||
        (gCyCircuitOpen && !remote_call_current_success())) {
        int abandonedPages = gCyListCount;
        cylinderlite_forget_remote_state();
        log_user("[CYLINDER][RESTORE-SKIPPED] pages=%d reason=invalid-transport remoteCalls=0; SpringBoard restart returns layers to stock.\n",
                 abandonedPages);
        return false;
    }
    int listCount = gCyListCount;
    int restored = 0;
    for (int i = 0; i < gCyListCount; i++)
        if (cy_set_page_transform(gCyLists[i], 0.0)) restored++;
    for (int i = 0; i < gCyListCount; i++)
        if (r_is_objc_ptr(gCyLists[i]))
            r_msg2_main(gCyLists[i], "release", 0, 0, 0, 0);
    for (int i = 0; i < gCyListCount; i++)
        if (r_is_objc_ptr(gCyScrollViews[i]))
            r_msg2_main(gCyScrollViews[i], "release", 0, 0, 0, 0);
    if (r_is_objc_ptr(gCyKeyPositionX)) r_msg2_main(gCyKeyPositionX, "release", 0, 0, 0, 0);
    if (r_is_objc_ptr(gCyKeyBoundsWidth)) r_msg2_main(gCyKeyBoundsWidth, "release", 0, 0, 0, 0);
    if (r_is_objc_ptr(gCyKeyBoundsOriginX)) r_msg2_main(gCyKeyBoundsOriginX, "release", 0, 0, 0, 0);
    if (r_is_objc_ptr(gCyKeyRotationY)) r_msg2_main(gCyKeyRotationY, "release", 0, 0, 0, 0);
    if (r_is_objc_ptr(gCyKeyTranslationZ)) r_msg2_main(gCyKeyTranslationZ, "release", 0, 0, 0, 0);
    memset(gCyLists, 0, sizeof(gCyLists));
    memset(gCyScrollViews, 0, sizeof(gCyScrollViews));
    memset(gCyProgressBuckets, 0, sizeof(gCyProgressBuckets));
    memset(gCyBaseProgress, 0, sizeof(gCyBaseProgress));
    gCyListCount = 0;
    gCyPageOffset = 0.0;
    gCyBaselineReady = false;
    gCyExcludedLists = 0;
    gCyTransportFailures = 0;
    gCyCircuitOpen = false;
    gCyApplied = false;
    gCyKeyPositionX = gCyKeyBoundsWidth = gCyKeyBoundsOriginX = 0;
    gCyKeyRotationY = gCyKeyTranslationZ = 0;
    log_user("[CYLINDER][RESTORE] pages=%d identityLayerTransforms=%d remoteReads=0 iconObjectsTouched=0 result=%s.\n",
             listCount, restored, restored > 0 ? "restored" : "already-stock");
    return restored > 0 || listCount == 0;
}

void cylinderlite_configure(int depth, int perspectiveDistance, int maxIcons)
{
    if (depth > 0) depth = 0;
    if (depth < -80) depth = -80;
    if (perspectiveDistance < 250) perspectiveDistance = 250;
    if (perspectiveDistance > 1600) perspectiveDistance = 1600;
    // Keep the old preference ABI, but convert its historical icon budget
    // into a small page cap. No icon objects are scanned or mutated anymore.
    int pageCap = maxIcons / 32;
    if (pageCap < 3) pageCap = 3;
    if (pageCap > CY_LIST_CAP) pageCap = CY_LIST_CAP;
    bool changed = gCyDepth != depth ||
                   gCyPerspectiveDistance != perspectiveDistance ||
                   gCyPageCap != pageCap;
    gCyDepth = depth;
    gCyPerspectiveDistance = perspectiveDistance;
    gCyPageCap = pageCap;
    if (changed) {
        for (int i = 0; i < gCyListCount; i++)
            gCyProgressBuckets[i] = INT32_MIN;
        printf("[CYLINDER] config changed depth=%d curveDistance=%d pageCap=%d; page transforms invalidated\n",
               gCyDepth, gCyPerspectiveDistance, gCyPageCap);
    }
}

void cylinderlite_forget_remote_state(void)
{
    gCyApplied = false;
    gCyCircuitOpen = false;
    gCyTransportFailures = 0;
    gCyExcludedLists = 0;
    memset(gCyLists, 0, sizeof(gCyLists));
    memset(gCyScrollViews, 0, sizeof(gCyScrollViews));
    memset(gCyProgressBuckets, 0, sizeof(gCyProgressBuckets));
    memset(gCyBaseProgress, 0, sizeof(gCyBaseProgress));
    gCyListCount = 0;
    gCyPageOffset = 0.0;
    gCyBaselineReady = false;
    gCyKeyPositionX = gCyKeyBoundsWidth = gCyKeyBoundsOriginX = 0;
    gCyKeyRotationY = gCyKeyTranslationZ = 0;
    // The remote process/session is already gone here. Never release or
    // message cached objects from the old address space.
}
