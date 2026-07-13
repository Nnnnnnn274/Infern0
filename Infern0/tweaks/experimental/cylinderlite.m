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

    uint64_t iconViews[512] = {0};
    uint64_t listViews[64] = {0};
    uint64_t iconClass = r_class("SBIconView");
    uint64_t listClass = r_class("SBIconListView");
    if (!r_is_objc_ptr(iconClass) || !r_is_objc_ptr(listClass)) return false;

    int iconCount = sb_collect_views_in_windows(iconClass, iconViews, gCyMaxIcons);
    int listCount = sb_collect_views_in_windows(listClass, listViews, 64);
    double z = (double)gCyDepth;
    for (int i = 0; i < iconCount; i++) {
        r_msg2_main(iconViews[i], "setUserInteractionEnabled:", 1, 0, 0, 0);
        uint64_t layer = r_msg2_main(iconViews[i], "layer", 0, 0, 0, 0);
        if (r_is_objc_ptr(layer))
            r_msg2_main_raw(layer, "setZPosition:", &z, sizeof(z), NULL, 0, NULL, 0, NULL, 0);
    }
    for (int i = 0; i < listCount; i++) {
        r_msg2_main(listViews[i], "setUserInteractionEnabled:", 1, 0, 0, 0);
        uint64_t layer = r_msg2_main(listViews[i], "layer", 0, 0, 0, 0);
        cy_apply_perspective_to_layer(layer, true);
    }
    gCyLastIconListView = listCount > 0 ? listViews[0] : 0;
    printf("[CYLINDER] transformed icons=%d lists=%d scanLimit=%d pages=all-discovered taps=preserved\n",
           iconCount, listCount, gCyMaxIcons);

    gCyApplied = iconCount > 0 && listCount > 0;
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
    for (int i = 0; i < iconCount; i++) {
        uint64_t layer = r_msg2_main(iconViews[i], "layer", 0, 0, 0, 0);
        if (r_is_objc_ptr(layer))
            r_msg2_main_raw(layer, "setZPosition:", &z, sizeof(z), NULL, 0, NULL, 0, NULL, 0);
    }
    for (int i = 0; i < listCount; i++) {
        uint64_t layer = r_msg2_main(listViews[i], "layer", 0, 0, 0, 0);
        cy_apply_perspective_to_layer(layer, false);
    }
    gCyLastIconListView = 0;
    gCyApplied = false;
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
