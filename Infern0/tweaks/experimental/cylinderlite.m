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
static int gCyProgressBuckets[CY_LIST_CAP] = {0};
static double gCyBaseProgress[CY_LIST_CAP] = {0};
static double gCyPageOffset = 0.0;
static bool gCyBaselineReady = false;
static int gCyListCount = 0;

typedef struct {
    double m11, m12, m13, m14;
    double m21, m22, m23, m24;
    double m31, m32, m33, m34;
    double m41, m42, m43, m44;
} CYRemoteCATransform3D;

typedef struct { double x, y; } CYPoint;
typedef struct { double x, y, width, height; } CYRect;

static CYRemoteCATransform3D cy_identity_transform(void)
{
    CYRemoteCATransform3D t;
    memset(&t, 0, sizeof(t));
    t.m11 = 1.0;
    t.m22 = 1.0;
    t.m33 = 1.0;
    t.m44 = 1.0;
    return t;
}

static bool cy_get_rect(uint64_t obj, const char *selector, CYRect *out)
{
    if (!r_is_objc_ptr(obj) || !out) return false;
    memset(out, 0, sizeof(*out));
    return r_msg2_main_struct_ret(obj, selector, out, sizeof(*out),
                                  NULL, 0, NULL, 0, NULL, 0, NULL, 0);
}

static bool cy_get_point(uint64_t obj, const char *selector, CYPoint *out)
{
    if (!r_is_objc_ptr(obj) || !out) return false;
    memset(out, 0, sizeof(*out));
    return r_msg2_main_struct_ret(obj, selector, out, sizeof(*out),
                                  NULL, 0, NULL, 0, NULL, 0, NULL, 0);
}

static bool cy_list_is_excluded(uint64_t list)
{
    uint64_t view = list;
    for (int depth = 0; r_is_objc_ptr(view) && depth < 8; depth++) {
        char cls[160] = {0};
        if (!sb_read_class_name(view, cls, sizeof(cls))) return true;
        if (strstr(cls, "Dock") || strstr(cls, "Library"))
            return true;
        view = r_msg2_main(view, "superview", 0, 0, 0, 0);
    }
    return false;
}

// Use the list's center in its superview coordinate space. Unlike frame or a
// rect converted from the list itself, this measurement is not distorted by
// the transform Cylinder applied on the previous refresh.
static bool cy_page_progress(uint64_t list, double *outProgress)
{
    if (!outProgress) return false;
    uint64_t superview = r_msg2_main(list, "superview", 0, 0, 0, 0);
    uint64_t window = r_msg2_main(list, "window", 0, 0, 0, 0);
    if (!r_is_objc_ptr(superview) || !r_is_objc_ptr(window)) return false;

    CYPoint center = {0}, windowPoint = {0};
    CYRect windowBounds = {0};
    uint64_t nilView = 0;
    if (!cy_get_point(list, "center", &center) ||
        !r_msg2_main_struct_ret(superview, "convertPoint:toView:",
                                &windowPoint, sizeof(windowPoint),
                                &center, sizeof(center), &nilView, sizeof(nilView),
                                NULL, 0, NULL, 0) ||
        !cy_get_rect(window, "bounds", &windowBounds) || windowBounds.width <= 1.0)
        return false;

    *outProgress = (windowPoint.x -
                    (windowBounds.x + windowBounds.width * 0.5)) /
                   windowBounds.width;
    return true;
}

static CYRemoteCATransform3D cy_page_transform(double progress)
{
    CYRemoteCATransform3D t = cy_identity_transform();
    double angle = progress * 1.35;
    double cosine = cos(angle), sine = sin(angle);
    int distance = gCyPerspectiveDistance < 250 ? 250 : gCyPerspectiveDistance;
    t.m11 = cosine;
    t.m13 = -sine;
    t.m31 = sine;
    t.m33 = cosine;
    t.m34 = -1.0 / (double)distance;
    t.m43 = (double)gCyDepth * fabs(progress);
    return t;
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
        if (cy_list_is_excluded(list)) {
            gCyExcludedLists++;
            continue;
        }
        // The page itself is the only cached UIKit object. Retaining it keeps
        // geometry reads valid while SpringBoard recycles neighboring pages.
        r_msg2_main(list, "retain", 0, 0, 0, 0);
        gCyLists[gCyListCount] = list;
        gCyProgressBuckets[gCyListCount] = INT32_MIN;
        double measured = 0.0;
        if (gCyBaselineReady && cy_page_progress(list, &measured))
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
        if (!cy_page_progress(gCyLists[i], &gCyBaseProgress[i])) {
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
    if (!cy_page_progress(gCyLists[anchor], &measuredAnchor))
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
        uint64_t layer = r_msg2_main(gCyLists[i], "layer", 0, 0, 0, 0);
        if (!r_is_objc_ptr(layer)) continue;
        CYRemoteCATransform3D transform = cy_page_transform(stableProgress);
        if (sb_cc_override_bytes("cylinderlite", layer, "transform", "setTransform:",
                                 &transform, sizeof(transform))) {
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
    printf("[CYLINDER] apply page-layer engine\n");
    gCyCircuitOpen = false;
    gCyTransportFailures = 0;
    int added = cy_discover_pages();
    bool active = cylinderlite_refresh_in_session(false);
    printf("[CYLINDER] pages=%d added=%d excluded=%d pageMutationsOnly=1 iconMutations=0 result=%d\n",
           gCyListCount, added, gCyExcludedLists, active);
    log_user("[CYLINDER][APPLY] engine=page-layer pages=%d newlyDiscovered=%d excludedDockLibrary=%d depth=%d perspective=%d pageCap=%d iconReads=0 iconMutations=0 tapsPreserved=1 transportFailures=%d result=%s.\n",
             gCyListCount, added, gCyExcludedLists, gCyDepth,
             gCyPerspectiveDistance, gCyPageCap, gCyTransportFailures,
             active ? "active" : "waiting");
    return active;
}

bool cylinderlite_stop_in_session(void)
{
    printf("[CYLINDER] stop\n");
    int listCount = gCyListCount;
    int restored = sb_cc_restore_owner("cylinderlite");
    for (int i = 0; i < gCyListCount; i++)
        if (r_is_objc_ptr(gCyLists[i]))
            r_msg2_main(gCyLists[i], "release", 0, 0, 0, 0);
    memset(gCyLists, 0, sizeof(gCyLists));
    memset(gCyProgressBuckets, 0, sizeof(gCyProgressBuckets));
    memset(gCyBaseProgress, 0, sizeof(gCyBaseProgress));
    gCyListCount = 0;
    gCyPageOffset = 0.0;
    gCyBaselineReady = false;
    gCyExcludedLists = 0;
    gCyTransportFailures = 0;
    gCyCircuitOpen = false;
    gCyApplied = false;
    log_user("[CYLINDER][RESTORE] pages=%d exactLayerTransforms=%d iconObjectsTouched=0 result=%s.\n",
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
        printf("[CYLINDER] config changed depth=%d perspective=%d pageCap=%d; page transforms invalidated\n",
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
    memset(gCyProgressBuckets, 0, sizeof(gCyProgressBuckets));
    memset(gCyBaseProgress, 0, sizeof(gCyBaseProgress));
    gCyListCount = 0;
    gCyPageOffset = 0.0;
    gCyBaselineReady = false;
    // The remote process/session is already gone here. Never release cached
    // pages or message coordinator targets from the old address space.
    sb_cc_forget_owner("cylinderlite");
}
