#import "iconstyles.h"
#import "../remote_objc.h"
#import "../sb_walk.h"
#import "../../TaskRop/RemoteCall.h"
#import "../../LogTextView.h"

#import <Foundation/Foundation.h>
#import <math.h>
#import <string.h>

typedef struct { double x, y, width, height; } ISRect;
typedef struct { double a, b, c, d, tx, ty; } ISAffineTransform;

static int gRoundedRadius = 18;
static int gWatchCompactPercent = 82;
static int gWatchScalePercent = 88;
static uint64_t gWatchIcons[512] = {0};
static ISRect gWatchFrames[512] = {0};
static int gWatchIconCount = 0;

static void is_class_name(uint64_t obj, char *out, size_t outLen)
{
    if (!out || outLen == 0) return;
    out[0] = '\0';
    if (!r_is_objc_ptr(obj)) return;
    uint64_t cls = r_dlsym_call(R_TIMEOUT, "object_getClass", obj, 0, 0, 0, 0, 0, 0, 0);
    uint64_t name = r_is_objc_ptr(cls)
        ? r_dlsym_call(R_TIMEOUT, "class_getName", cls, 0, 0, 0, 0, 0, 0, 0) : 0;
    if (!name) return;
    remote_read(name, out, outLen - 1);
    out[outLen - 1] = '\0';
}

static bool is_inside_app_library(uint64_t view)
{
    for (int depth = 0; r_is_objc_ptr(view) && depth < 12; depth++) {
        uint64_t cls = r_dlsym_call(R_TIMEOUT, "object_getClass", view, 0, 0, 0, 0, 0, 0, 0);
        uint64_t name = r_is_objc_ptr(cls)
            ? r_dlsym_call(R_TIMEOUT, "class_getName", cls, 0, 0, 0, 0, 0, 0, 0) : 0;
        char buffer[160] = {0};
        if (name) remote_read(name, buffer, sizeof(buffer) - 1);
        if (strstr(buffer, "SBHLibrary") || strstr(buffer, "AppLibrary") ||
            strstr(buffer, "LibraryPod") || strstr(buffer, "LibraryCategory")) return true;
        view = r_msg2_main(view, "superview", 0, 0, 0, 0);
    }
    return false;
}

static bool is_inside_dock(uint64_t view)
{
    for (int depth = 0; r_is_objc_ptr(view) && depth < 12; depth++) {
        char name[160] = {0};
        is_class_name(view, name, sizeof(name));
        if (strstr(name, "Dock") || strstr(name, "FloatingDock")) return true;
        view = r_msg2_main(view, "superview", 0, 0, 0, 0);
    }
    return false;
}

static bool is_get_rect(uint64_t obj, const char *selector, ISRect *out)
{
    if (!r_is_objc_ptr(obj) || !out || !r_responds_main(obj, selector)) return false;
    memset(out, 0, sizeof(*out));
    return r_msg2_main_struct_ret(obj, selector, out, sizeof(*out),
                                  NULL, 0, NULL, 0, NULL, 0, NULL, 0);
}

static void is_set_rect(uint64_t obj, const char *selector, ISRect value)
{
    if (!r_is_objc_ptr(obj) || !r_responds_main(obj, selector)) return;
    r_msg2_main_raw(obj, selector, &value, sizeof(value), NULL, 0, NULL, 0, NULL, 0);
}

static uint64_t is_icon_image_view(uint64_t icon)
{
    const char *selectors[] = { "_iconImageView", "iconImageView", "_imageView", NULL };
    for (int i = 0; selectors[i]; i++) {
        if (!r_responds_main(icon, selectors[i])) continue;
        uint64_t view = r_msg2_main(icon, selectors[i], 0, 0, 0, 0);
        if (r_is_objc_ptr(view)) return view;
    }
    return icon;
}

static void is_round_view(uint64_t view, double radius)
{
    uint64_t layer = r_is_objc_ptr(view) ? r_msg2_main(view, "layer", 0, 0, 0, 0) : 0;
    if (!r_is_objc_ptr(layer)) return;
    r_msg2_main_raw(layer, "setCornerRadius:", &radius, sizeof(radius), NULL, 0, NULL, 0, NULL, 0);
    r_msg2_main(layer, "setMasksToBounds:", radius > 0.0, 0, 0, 0);
    if (r_responds_main(layer, "setCornerCurve:")) {
        uint64_t curve = r_nsstr_retained("continuous");
        if (r_is_objc_ptr(curve)) {
            r_msg2_main(layer, "setCornerCurve:", curve, 0, 0, 0);
            r_msg2_main(curve, "release", 0, 0, 0, 0);
        }
    }
}

void roundedicons_configure(int cornerRadius)
{
    if (cornerRadius < 0) cornerRadius = 0;
    if (cornerRadius > 36) cornerRadius = 36;
    gRoundedRadius = cornerRadius;
    log_user("[ROUNDEDICONS][CONFIG] cornerRadius=%dpt coverage=all-discovered-icon-images.\n",
             gRoundedRadius);
}

bool roundedicons_apply_in_session(void)
{
    uint64_t iconClass = r_class("SBIconView");
    uint64_t icons[512] = {0};
    int count = r_is_objc_ptr(iconClass) ? sb_collect_views_in_windows(iconClass, icons, 512) : 0;
    int rounded = 0;
    for (int i = 0; i < count; i++) {
        uint64_t icon = icons[i];
        uint64_t image = is_icon_image_view(icon);
        if (!r_is_objc_ptr(image)) continue;
        is_round_view(image, (double)gRoundedRadius);
        r_msg2_main(icon, "setUserInteractionEnabled:", 1, 0, 0, 0);
        rounded++;
    }
    printf("[ROUNDEDICONS] radius=%d applied=%d discovered=%d taps=preserved\n",
           gRoundedRadius, rounded, count);
    log_user("[ROUNDEDICONS][APPLY] radius=%dpt discovered=%d changed=%d interactionEnabled=%d result=%s.\n",
             gRoundedRadius, count, rounded, rounded, rounded > 0 ? "active" : "no matching icons");
    return rounded > 0;
}

bool roundedicons_stop_in_session(void)
{
    uint64_t iconClass = r_class("SBIconView");
    uint64_t icons[512] = {0};
    int count = r_is_objc_ptr(iconClass) ? sb_collect_views_in_windows(iconClass, icons, 512) : 0;
    for (int i = 0; i < count; i++) is_round_view(is_icon_image_view(icons[i]), 0.0);
    printf("[ROUNDEDICONS] restored=%d\n", count);
    log_user("[ROUNDEDICONS][RESTORE] removed custom corner masks from %d discovered icon(s).\n", count);
    return true;
}

void roundedicons_forget_remote_state(void)
{
    log_user("[ROUNDEDICONS][FORGET] no retained remote icon cache; session references are clear.\n");
}

void watchlayout_configure(int compactPercent, int iconScalePercent)
{
    if (compactPercent < 60) compactPercent = 60;
    if (compactPercent > 100) compactPercent = 100;
    if (iconScalePercent < 60) iconScalePercent = 60;
    if (iconScalePercent > 110) iconScalePercent = 110;
    gWatchCompactPercent = compactPercent;
    gWatchScalePercent = iconScalePercent;
    log_user("[WATCHLAYOUT][CONFIG] geometry=honeycomb compact=%d%% iconScale=%d%% dockExcluded=1 appLibraryExcluded=1.\n",
             gWatchCompactPercent, gWatchScalePercent);
}

static int is_saved_watch_icon_index(uint64_t icon)
{
    for (int i = 0; i < gWatchIconCount; i++) if (gWatchIcons[i] == icon) return i;
    return -1;
}

bool watchlayout_apply_in_session(void)
{
    uint64_t iconClass = r_class("SBIconView");
    uint64_t icons[512] = {0};
    int count = r_is_objc_ptr(iconClass) ? sb_collect_views_in_windows(iconClass, icons, 512) : 0;
    uint64_t validIcons[512] = {0}, parents[512] = {0};
    ISRect original[512] = {{0}};
    int validCount = 0, skippedLibrary = 0, skippedDock = 0, invalidGeometry = 0;
    double compact = (double)gWatchCompactPercent / 100.0;
    double scale = (double)gWatchScalePercent / 100.0;
    ISAffineTransform transform = { scale, 0, 0, scale, 0, 0 };
    for (int i = 0; i < count; i++) {
        uint64_t icon = icons[i];
        if (is_inside_app_library(icon)) { skippedLibrary++; continue; }
        if (is_inside_dock(icon)) { skippedDock++; continue; }
        uint64_t parent = r_is_objc_ptr(icon) ? r_msg2_main(icon, "superview", 0, 0, 0, 0) : 0;
        ISRect frame, bounds;
        if (!r_is_objc_ptr(parent) || !is_get_rect(icon, "frame", &frame) ||
            !is_get_rect(parent, "bounds", &bounds) || frame.width <= 0 || frame.height <= 0) {
            invalidGeometry++;
            continue;
        }
        int savedIndex = is_saved_watch_icon_index(icon);
        if (savedIndex < 0 && gWatchIconCount < 512) {
            gWatchIcons[gWatchIconCount] = icon;
            gWatchFrames[gWatchIconCount] = frame;
            savedIndex = gWatchIconCount;
            gWatchIconCount++;
        }
        if (savedIndex >= 0) frame = gWatchFrames[savedIndex];
        validIcons[validCount] = icon;
        parents[validCount] = parent;
        original[validCount] = frame;
        validCount++;
    }

    int changed = 0, pageCount = 0;
    bool parentDone[512] = {false};
    for (int seed = 0; seed < validCount; seed++) {
        if (parentDone[seed]) continue;
        uint64_t parent = parents[seed];
        int order[512] = {0}, groupCount = 0;
        for (int i = seed; i < validCount; i++) {
            if (parents[i] != parent) continue;
            parentDone[i] = true;
            order[groupCount++] = i;
        }
        if (groupCount == 0) continue;

        // Sort by stock row, then stock column. This preserves SpringBoard's
        // icon order while replacing only its geometry.
        for (int i = 1; i < groupCount; i++) {
            int value = order[i], j = i - 1;
            double vy = original[value].y + original[value].height * 0.5;
            double vx = original[value].x + original[value].width * 0.5;
            while (j >= 0) {
                int prior = order[j];
                double py = original[prior].y + original[prior].height * 0.5;
                double px = original[prior].x + original[prior].width * 0.5;
                double rowTolerance = fmax(original[value].height, original[prior].height) * 0.45;
                bool after = (py > vy + rowTolerance) || (fabs(py - vy) <= rowTolerance && px > vx);
                if (!after) break;
                order[j + 1] = order[j];
                j--;
            }
            order[j + 1] = value;
        }

        int rowStart[64] = {0}, rowCount[64] = {0}, rows = 0;
        double rowCenterY[64] = {0};
        for (int p = 0; p < groupCount; p++) {
            int idx = order[p];
            double cy = original[idx].y + original[idx].height * 0.5;
            double tolerance = original[idx].height * 0.45;
            if (rows == 0 || fabs(cy - rowCenterY[rows - 1]) > tolerance) {
                if (rows >= 64) break;
                rowStart[rows] = p;
                rowCount[rows] = 1;
                rowCenterY[rows] = cy;
                rows++;
            } else {
                int r = rows - 1;
                rowCenterY[r] = (rowCenterY[r] * rowCount[r] + cy) / (rowCount[r] + 1);
                rowCount[r]++;
            }
        }
        if (rows == 0) continue;

        ISRect parentBounds = {0};
        is_get_rect(parent, "bounds", &parentBounds);
        double horizontalSum = 0.0, verticalSum = 0.0;
        int horizontalSamples = 0, verticalSamples = 0;
        for (int r = 0; r < rows; r++) {
            for (int c = 1; c < rowCount[r]; c++) {
                ISRect a = original[order[rowStart[r] + c - 1]];
                ISRect b = original[order[rowStart[r] + c]];
                horizontalSum += (b.x + b.width * 0.5) - (a.x + a.width * 0.5);
                horizontalSamples++;
            }
            if (r > 0) {
                verticalSum += rowCenterY[r] - rowCenterY[r - 1];
                verticalSamples++;
            }
        }
        double iconW = original[order[0]].width, iconH = original[order[0]].height;
        double stockHStep = horizontalSamples ? horizontalSum / horizontalSamples : iconW * 1.35;
        double stockVStep = verticalSamples ? verticalSum / verticalSamples : iconH * 1.35;
        double hStep = fmax(iconW * 0.78, stockHStep * compact);
        double vStep = fmax(iconH * 0.68, stockVStep * compact * 0.8660254);
        double centerX = parentBounds.x + parentBounds.width * 0.5;
        double centerY = parentBounds.y + parentBounds.height * 0.5;
        double firstY = centerY - ((double)(rows - 1) * vStep * 0.5);

        for (int r = 0; r < rows; r++) {
            double stagger = (r & 1) ? hStep * 0.25 : -hStep * 0.25;
            double firstX = centerX - ((double)(rowCount[r] - 1) * hStep * 0.5) + stagger;
            for (int c = 0; c < rowCount[r]; c++) {
                int idx = order[rowStart[r] + c];
                ISRect frame = original[idx];
                frame.x = firstX + c * hStep - frame.width * 0.5;
                frame.y = firstY + r * vStep - frame.height * 0.5;
                is_set_rect(validIcons[idx], "setFrame:", frame);
                if (r_responds_main(validIcons[idx], "setTransform:"))
                    r_msg2_main_raw(validIcons[idx], "setTransform:", &transform, sizeof(transform), NULL, 0, NULL, 0, NULL, 0);
                uint64_t image = is_icon_image_view(validIcons[idx]);
                ISRect imageBounds;
                double radius = 30.0 * scale;
                if (is_get_rect(image, "bounds", &imageBounds) && imageBounds.width > 0 && imageBounds.height > 0)
                    radius = fmin(imageBounds.width, imageBounds.height) * 0.5;
                is_round_view(image, radius);
                r_msg2_main(validIcons[idx], "setUserInteractionEnabled:", 1, 0, 0, 0);
                changed++;
            }
        }
        pageCount++;
        log_user("[WATCHLAYOUT][PAGE %d] parent=0x%llx icons=%d rows=%d hStep=%.1f vStep=%.1f stagger=%.1f result=honeycomb.\n",
                 pageCount, parent, groupCount, rows, hStep, vStep, hStep * 0.5);
    }
    printf("[WATCHLAYOUT] geometry=honeycomb compact=%d%% scale=%d%% icons=%d pages=%d taps=preserved\n",
           gWatchCompactPercent, gWatchScalePercent, changed, pageCount);
    log_user("[WATCHLAYOUT][APPLY] geometry=honeycomb discovered=%d eligible=%d changed=%d pages=%d skippedAppLibrary=%d skippedDock=%d invalidGeometry=%d savedStockFrames=%d tapsPreserved=1 result=%s.\n",
             count, validCount, changed, pageCount, skippedLibrary, skippedDock,
             invalidGeometry, gWatchIconCount, changed > 0 ? "active" : "no eligible icons");
    return changed > 0;
}

bool watchlayout_stop_in_session(void)
{
    ISAffineTransform identity = {1, 0, 0, 1, 0, 0};
    int restored = 0;
    for (int i = 0; i < gWatchIconCount; i++) {
        uint64_t icon = gWatchIcons[i];
        if (!r_is_objc_ptr(icon)) continue;
        is_set_rect(icon, "setFrame:", gWatchFrames[i]);
        if (r_responds_main(icon, "setTransform:"))
            r_msg2_main_raw(icon, "setTransform:", &identity, sizeof(identity), NULL, 0, NULL, 0, NULL, 0);
        is_round_view(is_icon_image_view(icon), 0.0);
        restored++;
    }
    memset(gWatchIcons, 0, sizeof(gWatchIcons));
    memset(gWatchFrames, 0, sizeof(gWatchFrames));
    gWatchIconCount = 0;
    printf("[WATCHLAYOUT] restored=%d\n", restored);
    log_user("[WATCHLAYOUT][RESTORE] restoredFrames=%d removedCircularMasks=%d resetTransforms=%d cacheCleared=1.\n",
             restored, restored, restored);
    return true;
}

void watchlayout_forget_remote_state(void)
{
    int forgotten = gWatchIconCount;
    memset(gWatchIcons, 0, sizeof(gWatchIcons));
    memset(gWatchFrames, 0, sizeof(gWatchFrames));
    gWatchIconCount = 0;
    log_user("[WATCHLAYOUT][FORGET] cleared %d cached icon reference(s) after session teardown.\n", forgotten);
}
