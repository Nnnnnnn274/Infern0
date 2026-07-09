#import "cylinderlite.h"
#import "../remote_objc.h"
#import "../../TaskRop/RemoteCall.h"
#import "../../LogTextView.h"

#import <Foundation/Foundation.h>
#import <math.h>
#import <string.h>

static bool gCyApplied = false;
static uint64_t gCyLastIconListView = 0;
static int gCyDepth = -10;
static int gCyPerspectiveDistance = 650;
static int gCyMaxIcons = 128;

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

    uint64_t UIApplication = r_class("UIApplication");
    if (!r_is_objc_ptr(UIApplication)) return false;
    uint64_t app = r_msg2_main(UIApplication, "sharedApplication", 0, 0, 0, 0);
    if (!r_is_objc_ptr(app)) return false;

    uint64_t windows = r_msg2_main(app, "windows", 0, 0, 0, 0);
    if (!r_is_objc_ptr(windows)) return false;
    uint64_t winCount = r_msg2_main(windows, "count", 0, 0, 0, 0);
    if (winCount > 32) winCount = 32;

    uint64_t iconListView = 0;
    for (uint64_t i = 0; i < winCount; i++) {
        uint64_t win = r_msg2_main(windows, "objectAtIndex:", i, 0, 0, 0);
        if (!r_is_objc_ptr(win)) continue;
        uint64_t root = r_msg2_main(win, "rootViewController", 0, 0, 0, 0);
        if (!r_is_objc_ptr(root)) continue;

        char cls[128] = {0};
        uint64_t rCls = r_dlsym_call(R_TIMEOUT, "object_getClass", root, 0, 0, 0, 0, 0, 0, 0);
        if (r_is_objc_ptr(rCls)) {
            uint64_t name = r_dlsym_call(R_TIMEOUT, "class_getName", rCls, 0, 0, 0, 0, 0, 0, 0);
            if (name) {
                uint64_t buf = r_dlsym_call(R_TIMEOUT, "strdup", name, 0, 0, 0, 0, 0, 0, 0);
                if (buf) {
                    remote_read(buf, cls, sizeof(cls) - 1);
                    r_free(buf);
                }
            }
        }

        if (strstr(cls, "SBIconController") || strstr(cls, "SBRootFolder")) {
            iconListView = r_msg2_main(root, "currentIconListView", 0, 0, 0, 0);
            if (r_is_objc_ptr(iconListView)) break;

            uint64_t folder = r_msg2_main(root, "rootFolder", 0, 0, 0, 0);
            if (!r_is_objc_ptr(folder)) folder = r_ivar_value(root, "_rootFolder");
            if (r_is_objc_ptr(folder)) {
                uint64_t listViews = r_msg2_main(folder, "iconListViews", 0, 0, 0, 0);
                if (!r_is_objc_ptr(listViews)) listViews = r_ivar_value(folder, "_iconListViews");
                if (r_is_objc_ptr(listViews)) {
                    uint64_t lvCount = r_msg2_main(listViews, "count", 0, 0, 0, 0);
                    if (lvCount > 0) {
                        iconListView = r_msg2_main(listViews, "firstObject", 0, 0, 0, 0);
                        if (r_is_objc_ptr(iconListView)) break;
                    }
                }
            }
        }
    }

    if (!r_is_objc_ptr(iconListView)) {
        printf("[CYLINDER] no icon list view found\n");
        return false;
    }
    gCyLastIconListView = iconListView;

    uint64_t subviews = r_msg2_main(iconListView, "subviews", 0, 0, 0, 0);
    if (!r_is_objc_ptr(subviews)) return false;
    uint64_t iconCount = r_msg2_main(subviews, "count", 0, 0, 0, 0);
    if (iconCount > (uint64_t)gCyMaxIcons) iconCount = (uint64_t)gCyMaxIcons;

    for (uint64_t i = 0; i < iconCount; i++) {
        uint64_t sv = r_msg2_main(subviews, "objectAtIndex:", i, 0, 0, 0);
        if (!r_is_objc_ptr(sv)) continue;

        char cls[128] = {0};
        uint64_t rCls = r_dlsym_call(R_TIMEOUT, "object_getClass", sv, 0, 0, 0, 0, 0, 0, 0);
        if (r_is_objc_ptr(rCls)) {
            uint64_t name = r_dlsym_call(R_TIMEOUT, "class_getName", rCls, 0, 0, 0, 0, 0, 0, 0);
            if (name) {
                uint64_t buf = r_dlsym_call(R_TIMEOUT, "strdup", name, 0, 0, 0, 0, 0, 0, 0);
                if (buf) {
                    remote_read(buf, cls, sizeof(cls) - 1);
                    r_free(buf);
                }
            }
        }

        if (strstr(cls, "SBIconView") || strstr(cls, "SBIcon")) {
            uint64_t layer = r_msg2_main(sv, "layer", 0, 0, 0, 0);
            if (r_is_objc_ptr(layer)) {
                double z = (double)gCyDepth;
                r_msg2_main_raw(layer, "setZPosition:", &z, sizeof(z), NULL, 0, NULL, 0, NULL, 0);
                printf("[CYLINDER] set depth on icon 0x%llx\n", sv);
            }
        }
    }

    printf("[CYLINDER] applied depth transforms to %llu icon views\n", iconCount);

    uint64_t layer = r_msg2_main(iconListView, "layer", 0, 0, 0, 0);
    if (r_is_objc_ptr(layer)) {
        cy_apply_perspective_to_layer(layer, true);
        printf("[CYLINDER] set perspective transform on list view\n");
    }

    gCyApplied = true;
    return true;
}

bool cylinderlite_stop_in_session(void)
{
    printf("[CYLINDER] stop\n");
    if (r_is_objc_ptr(gCyLastIconListView)) {
        uint64_t layer = r_msg2_main(gCyLastIconListView, "layer", 0, 0, 0, 0);
        cy_apply_perspective_to_layer(layer, false);
    }
    gCyApplied = false;
    return true;
}

void cylinderlite_configure(int depth, int perspectiveDistance, int maxIcons)
{
    if (depth > 0) depth = 0;
    if (depth < -80) depth = -80;
    if (perspectiveDistance < 250) perspectiveDistance = 250;
    if (perspectiveDistance > 1600) perspectiveDistance = 1600;
    if (maxIcons < 8) maxIcons = 8;
    if (maxIcons > 256) maxIcons = 256;
    gCyDepth = depth;
    gCyPerspectiveDistance = perspectiveDistance;
    gCyMaxIcons = maxIcons;
}

void cylinderlite_forget_remote_state(void)
{
    gCyApplied = false;
    gCyLastIconListView = 0;
}
