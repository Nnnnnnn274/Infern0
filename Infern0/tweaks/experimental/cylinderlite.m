#import "cylinderlite.h"
#import "../remote_objc.h"
#import "../sb_walk.h"
#import "../../TaskRop/RemoteCall.h"
#import "../../LogTextView.h"

#import <Foundation/Foundation.h>
#import <math.h>
#import <string.h>

static bool gCyApplied = false;
static uint64_t gCyLastIconListView = 0;
static int gCyDepth = -10;
static int gCyPerspectiveDistance = 650;
static int gCyMaxIcons = 512;

typedef struct {
    double m11, m12, m13, m14;
    double m21, m22, m23, m24;
    double m31, m32, m33, m34;
    double m41, m42, m43, m44;
} CYRemoteCATransform3D;

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
    if (!r_is_objc_ptr(obj) || !out || !r_responds_main(obj, selector)) return false;
    memset(out, 0, sizeof(*out));
    return r_msg2_main_struct_ret(obj, selector, out, sizeof(*out),
                                  NULL, 0, NULL, 0, NULL, 0, NULL, 0);
}

static void cy_class_name(uint64_t obj, char *out, size_t outLen)
{
    if (!out || outLen == 0) return;
    out[0] = '\0';
    uint64_t cls = r_is_objc_ptr(obj)
        ? r_dlsym_call(R_TIMEOUT, "object_getClass", obj, 0, 0, 0, 0, 0, 0, 0) : 0;
    uint64_t name = r_is_objc_ptr(cls)
        ? r_dlsym_call(R_TIMEOUT, "class_getName", cls, 0, 0, 0, 0, 0, 0, 0) : 0;
    if (name) remote_read(name, out, outLen - 1);
    out[outLen - 1] = '\0';
}

static bool cy_list_is_excluded(uint64_t list)
{
    uint64_t view = list;
    for (int depth = 0; r_is_objc_ptr(view) && depth < 10; depth++) {
        char cls[160] = {0};
        cy_class_name(view, cls, sizeof(cls));
        if (strstr(cls, "Dock") || strstr(cls, "Library")) return true;
        view = r_msg2_main(view, "superview", 0, 0, 0, 0);
    }
    return false;
}

static CYRemoteCATransform3D cy_icon_transform(uint64_t icon, uint64_t list, int ordinal)
{
    CYRemoteCATransform3D t = cy_identity_transform();
    CYRect iconFrame = {0}, listBounds = {0};
    double normalized = ((double)(ordinal % 4) - 1.5) / 1.5;
    if (cy_get_rect(icon, "frame", &iconFrame) &&
        cy_get_rect(list, "bounds", &listBounds) && listBounds.width > 1.0) {
        double center = iconFrame.x + iconFrame.width * 0.5;
        normalized = ((center - listBounds.x) / listBounds.width - 0.5) * 2.0;
    }
    if (normalized < -1.0) normalized = -1.0;
    if (normalized > 1.0) normalized = 1.0;
    double angle = normalized * 0.72;
    double cosine = cos(angle), sine = sin(angle);
    int distance = gCyPerspectiveDistance < 250 ? 250 : gCyPerspectiveDistance;
    t.m11 = cosine;
    t.m13 = -sine;
    t.m31 = sine;
    t.m33 = cosine;
    t.m34 = -1.0 / (double)distance;
    t.m43 = (double)gCyDepth * (1.0 - cosine);
    return t;
}

static void cy_apply_perspective_to_layer(uint64_t layer, bool enabled)
{
    if (!r_is_objc_ptr(layer)) return;
    CYRemoteCATransform3D t = cy_identity_transform();
    int distance = gCyPerspectiveDistance;
    if (distance < 250) distance = 250;
    if (enabled) t.m34 = -1.0 / (double)distance;
    r_msg2_main_raw(layer, "setSublayerTransform:",
                    &t, sizeof(t), NULL, 0, NULL, 0, NULL, 0);
}

bool cylinderlite_apply_in_session(void)
{
    printf("[CYLINDER] apply\n");

    uint64_t listViews[64] = {0};
    uint64_t iconClass = r_class("SBIconView");
    uint64_t listClass = r_class("SBIconListView");
    if (!r_is_objc_ptr(iconClass) || !r_is_objc_ptr(listClass)) return false;

    int listCount = sb_collect_views_in_windows(listClass, listViews, 64);
    int iconCount = 0, pageCount = 0, excludedLists = 0;
    for (int i = 0; i < listCount; i++) {
        if (cy_list_is_excluded(listViews[i])) { excludedLists++; continue; }
        uint64_t pageIcons[256] = {0};
        int remaining = gCyMaxIcons - iconCount;
        if (remaining <= 0) break;
        if (remaining > 256) remaining = 256;
        int pageIconCount = sb_collect_views(listViews[i], iconClass, pageIcons, remaining);
        if (pageIconCount <= 0) continue;
        r_msg2_main(listViews[i], "setUserInteractionEnabled:", 1, 0, 0, 0);
        uint64_t layer = r_msg2_main(listViews[i], "layer", 0, 0, 0, 0);
        cy_apply_perspective_to_layer(layer, true);
        for (int j = 0; j < pageIconCount; j++) {
            uint64_t icon = pageIcons[j];
            r_msg2_main(icon, "setUserInteractionEnabled:", 1, 0, 0, 0);
            uint64_t iconLayer = r_msg2_main(icon, "layer", 0, 0, 0, 0);
            if (!r_is_objc_ptr(iconLayer)) continue;
            CYRemoteCATransform3D transform = cy_icon_transform(icon, listViews[i], j);
            r_msg2_main_raw(iconLayer, "setTransform:", &transform, sizeof(transform),
                            NULL, 0, NULL, 0, NULL, 0);
            iconCount++;
        }
        pageCount++;
    }
    gCyLastIconListView = listCount > 0 ? listViews[0] : 0;
    printf("[CYLINDER] transformed icons=%d pages=%d lists=%d excluded=%d scanLimit=%d taps=preserved\n",
           iconCount, pageCount, listCount, excludedLists, gCyMaxIcons);
    log_user("[CYLINDER][APPLY] discoveredLists=%d activePages=%d excludedDockLibraryLists=%d transformedIcons=%d depth=%d perspective=%d scanLimit=%d tapsPreserved=1 result=%s.\n",
             listCount, pageCount, excludedLists, iconCount, gCyDepth,
             gCyPerspectiveDistance, gCyMaxIcons, iconCount > 0 ? "active" : "no-home-pages");

    gCyApplied = iconCount > 0 && pageCount > 0;
    return gCyApplied;
}

bool cylinderlite_stop_in_session(void)
{
    printf("[CYLINDER] stop\n");
    uint64_t iconViews[512] = {0};
    uint64_t listViews[64] = {0};
    uint64_t iconClass = r_class("SBIconView");
    uint64_t listClass = r_class("SBIconListView");
    int iconCount = r_is_objc_ptr(iconClass) ? sb_collect_views_in_windows(iconClass, iconViews, 512) : 0;
    int listCount = r_is_objc_ptr(listClass) ? sb_collect_views_in_windows(listClass, listViews, 64) : 0;
    double z = 0.0;
    CYRemoteCATransform3D identity = cy_identity_transform();
    for (int i = 0; i < iconCount; i++) {
        uint64_t layer = r_msg2_main(iconViews[i], "layer", 0, 0, 0, 0);
        if (r_is_objc_ptr(layer)) {
            r_msg2_main_raw(layer, "setZPosition:", &z, sizeof(z), NULL, 0, NULL, 0, NULL, 0);
            r_msg2_main_raw(layer, "setTransform:", &identity, sizeof(identity),
                            NULL, 0, NULL, 0, NULL, 0);
        }
    }
    for (int i = 0; i < listCount; i++) {
        uint64_t layer = r_msg2_main(listViews[i], "layer", 0, 0, 0, 0);
        cy_apply_perspective_to_layer(layer, false);
    }
    gCyLastIconListView = 0;
    gCyApplied = false;
    log_user("[CYLINDER][RESTORE] icons=%d lists=%d identityTransforms=1 perspectiveCleared=1.\n",
             iconCount, listCount);
    return true;
}

void cylinderlite_configure(int depth, int perspectiveDistance, int maxIcons)
{
    if (depth > 0) depth = 0;
    if (depth < -80) depth = -80;
    if (perspectiveDistance < 250) perspectiveDistance = 250;
    if (perspectiveDistance > 1600) perspectiveDistance = 1600;
    if (maxIcons < 512) maxIcons = 512;
    if (maxIcons > 512) maxIcons = 512;
    gCyDepth = depth;
    gCyPerspectiveDistance = perspectiveDistance;
    gCyMaxIcons = maxIcons;
}

void cylinderlite_forget_remote_state(void)
{
    gCyApplied = false;
    gCyLastIconListView = 0;
}
