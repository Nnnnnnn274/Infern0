#import "velvet.h"
#import "../remote_objc.h"
#import "../../TaskRop/RemoteCall.h"
#import "../../LogTextView.h"

#import <Foundation/Foundation.h>
#import <math.h>
#import <sys/time.h>

#pragma mark - Style config types

static VelvetStyle gVelvetGlobalStyle;
static bool gVelvetGlobalDirty = true;

static const int kVelvetMaxStyledViews = 128;
static const int kVelvetMaxDepth = 16;

typedef struct {
    uint64_t view;
    uint64_t tick;
} VelvetStyledEntry;

static VelvetStyledEntry gVelvetStyled[kVelvetMaxStyledViews];
static int gVelvetStyledCount = 0;
static uint64_t gVelvetTick = 0;

#pragma mark - Config update (called from SettingsViewController local context)

void velvet_set_global_style(const VelvetStyle *style)
{
    if (style) {
        gVelvetGlobalStyle = *style;
        gVelvetGlobalDirty = true;
    } else {
        memset(&gVelvetGlobalStyle, 0, sizeof(gVelvetGlobalStyle));
        gVelvetGlobalDirty = true;
    }
}

#pragma mark - Remote color helpers

static uint64_t vl_remote_color(const VelvetRGBA *c)
{
    if (!c || !c->hasValue) return 0;
    uint64_t UIColor = r_class("UIColor");
    if (!r_is_objc_ptr(UIColor)) return 0;
    double r = c->r, g = c->g, b = c->b, a = c->a;
    return r_msg2_main_raw(UIColor, "colorWithRed:green:blue:alpha:",
                           &r, sizeof(r), &g, sizeof(g), &b, sizeof(b), &a, sizeof(a));
}

static uint64_t vl_clear_color(void)
{
    uint64_t UIColor = r_class("UIColor");
    if (!r_is_objc_ptr(UIColor)) return 0;
    return r_msg2_main(UIColor, "clearColor", 0, 0, 0, 0);
}

#pragma mark - Style application on a remote UIView

static bool vl_is_uiview(uint64_t obj)
{
    if (!r_is_objc_ptr(obj)) return false;
    uint64_t UIView = r_class("UIView");
    if (!r_is_objc_ptr(UIView)) return false;
    uint64_t result = r_msg2_main(obj, "isKindOfClass:", UIView, 0, 0, 0);
    return (result & 0xff) != 0;
}

static bool vl_is_uilabel(uint64_t obj)
{
    if (!r_is_objc_ptr(obj)) return false;
    uint64_t UILabel = r_class("UILabel");
    if (!r_is_objc_ptr(UILabel)) return false;
    uint64_t result = r_msg2_main(obj, "isKindOfClass:", UILabel, 0, 0, 0);
    return (result & 0xff) != 0;
}

static bool vl_apply_style_to_view(uint64_t view, const VelvetStyle *style)
{
    if (!r_is_objc_ptr(view) || !style) return false;
    bool applied = false;

    uint64_t layer = r_msg2_main(view, "layer", 0, 0, 0, 0);

    if (style->bgColor.hasValue) {
        uint64_t color = vl_remote_color(&style->bgColor);
        if (r_is_objc_ptr(color)) {
            r_msg2_main(view, "setBackgroundColor:", color, 0, 0, 0);
            applied = true;
        }
    }

    if (style->hasCornerRadius && r_is_objc_ptr(layer)) {
        double cr = style->cornerRadius;
        r_msg2_main_raw(layer, "setCornerRadius:",
                        &cr, sizeof(cr), NULL, 0, NULL, 0, NULL, 0);
        r_msg2_main(layer, "setMasksToBounds:", 1, 0, 0, 0);
        applied = true;
    }

    if (style->borderColor.hasValue && style->borderWidth > 0.0 && r_is_objc_ptr(layer)) {
        uint64_t color = vl_remote_color(&style->borderColor);
        if (r_is_objc_ptr(color)) {
            uint64_t cgColor = r_msg2_main(color, "CGColor", 0, 0, 0, 0);
            if (r_is_objc_ptr(cgColor)) {
                r_msg2_main(layer, "setBorderColor:", cgColor, 0, 0, 0);
            }
        }
        double bw = style->borderWidth;
        r_msg2_main_raw(layer, "setBorderWidth:",
                        &bw, sizeof(bw), NULL, 0, NULL, 0, NULL, 0);
        applied = true;
    }

    return applied;
}

static bool vl_apply_style_to_label(uint64_t label, const VelvetRGBA *color)
{
    if (!r_is_objc_ptr(label) || !color || !color->hasValue) return false;
    uint64_t textColor = vl_remote_color(color);
    if (!r_is_objc_ptr(textColor)) return false;
    r_msg2_main(label, "setTextColor:", textColor, 0, 0, 0);
    return true;
}

static bool vl_is_styled(uint64_t view)
{
    if (!view) return false;
    for (int i = 0; i < gVelvetStyledCount; i++) {
        if (gVelvetStyled[i].view == view) return true;
    }
    return false;
}

static void vl_mark_styled(uint64_t view)
{
    if (!view) return;
    if (vl_is_styled(view)) return;
    if (gVelvetStyledCount >= kVelvetMaxStyledViews) {
        int oldest = 0;
        for (int i = 1; i < gVelvetStyledCount; i++) {
            if (gVelvetStyled[i].tick < gVelvetStyled[oldest].tick) oldest = i;
        }
        gVelvetStyled[oldest].view = view;
        gVelvetStyled[oldest].tick = gVelvetTick;
        return;
    }
    gVelvetStyled[gVelvetStyledCount].view = view;
    gVelvetStyled[gVelvetStyledCount].tick = gVelvetTick;
    gVelvetStyledCount++;
}

#pragma mark - View hierarchy scanning

static void vl_read_class_name(uint64_t obj, char *out, size_t outLen)
{
    if (!out || outLen == 0) return;
    out[0] = '\0';
    if (!r_is_objc_ptr(obj)) return;
    uint64_t cls = r_dlsym_call(R_TIMEOUT, "object_getClass", obj, 0, 0, 0, 0, 0, 0, 0);
    if (!r_is_objc_ptr(cls)) return;
    uint64_t name = r_dlsym_call(R_TIMEOUT, "class_getName", cls, 0, 0, 0, 0, 0, 0, 0);
    if (!name) return;
    uint64_t buf = r_dlsym_call(R_TIMEOUT, "strdup", name, 0, 0, 0, 0, 0, 0, 0);
    if (!buf) return;
    remote_read(buf, out, outLen - 1);
    r_free(buf);
    out[outLen - 1] = '\0';
}

static bool vl_str_contains(const char *str, const char *needle)
{
    if (!str || !needle) return false;
    return strstr(str, needle) != NULL;
}

static void vl_scan_subviews(uint64_t parent, const VelvetStyle *style, int depth)
{
    if (!r_is_objc_ptr(parent) || depth > kVelvetMaxDepth) return;

    uint64_t subviews = r_msg2_main(parent, "subviews", 0, 0, 0, 0);
    if (!r_is_objc_ptr(subviews)) return;

    uint64_t count = r_msg2_main(subviews, "count", 0, 0, 0, 0);
    if (count > 64) count = 64;

    for (uint64_t i = 0; i < count; i++) {
        uint64_t sv = r_msg2_main(subviews, "objectAtIndex:", i, 0, 0, 0);
        if (!r_is_objc_ptr(sv) || vl_is_styled(sv)) continue;

        if (vl_is_uilabel(sv)) {
            char cls[128] = {0};
            vl_read_class_name(sv, cls, sizeof(cls));

            bool isDate   = vl_str_contains(cls, "Date") || vl_str_contains(cls, "date") || vl_str_contains(cls, "Secondary") || vl_str_contains(cls, "secondary");
            bool isTitle  = !isDate && (vl_str_contains(cls, "Title") || vl_str_contains(cls, "title") || vl_str_contains(cls, "Header") || vl_str_contains(cls, "header"));
            bool isMessage = !isDate && !isTitle && (vl_str_contains(cls, "Message") || vl_str_contains(cls, "message") || vl_str_contains(cls, "Body") || vl_str_contains(cls, "body"));

            if (isDate && style->dateColor.hasValue) {
                vl_apply_style_to_label(sv, &style->dateColor);
                vl_mark_styled(sv);
            } else if (isTitle && style->titleColor.hasValue) {
                vl_apply_style_to_label(sv, &style->titleColor);
                vl_mark_styled(sv);
            } else if (isMessage && style->messageColor.hasValue) {
                vl_apply_style_to_label(sv, &style->messageColor);
                vl_mark_styled(sv);
            }
        } else if (vl_is_uiview(sv)) {
            bool applied = vl_apply_style_to_view(sv, style);
            if (applied) vl_mark_styled(sv);
        }

        vl_scan_subviews(sv, style, depth + 1);
    }
}

#pragma mark - Banner scanning (SpringBoard side)

static uint64_t vl_springboard_application(void)
{
    uint64_t UIApplication = r_class("UIApplication");
    if (!r_is_objc_ptr(UIApplication)) return 0;
    return r_msg2_main(UIApplication, "sharedApplication", 0, 0, 0, 0);
}

static uint64_t vl_try_msg0_main(uint64_t obj, const char *selName)
{
    if (!r_is_objc_ptr(obj) || !r_responds_main(obj, selName)) return 0;
    return r_msg2_main(obj, selName, 0, 0, 0, 0);
}

static uint64_t vl_banner_destination(uint64_t app)
{
    uint64_t dispatcher = vl_try_msg0_main(app, "notificationDispatcher");
    if (!r_is_objc_ptr(dispatcher)) dispatcher = r_ivar_value(app, "_notificationDispatcher");
    if (!r_is_objc_ptr(dispatcher)) return 0;

    uint64_t dest = vl_try_msg0_main(dispatcher, "bannerDestination");
    if (!r_is_objc_ptr(dest)) dest = r_ivar_value(dispatcher, "_bannerDestination");
    if (!r_is_objc_ptr(dest)) dest = r_ivar_value(dispatcher, "_alertDestination");
    return dest;
}

static uint64_t vl_active_banner_view(uint64_t bannerDest)
{
    if (!r_is_objc_ptr(bannerDest)) return 0;

    uint64_t banner = vl_try_msg0_main(bannerDest, "presentedBanner");
    if (!r_is_objc_ptr(banner)) banner = r_ivar_value(bannerDest, "_presentedBanner");
    if (!r_is_objc_ptr(banner)) banner = r_ivar_value(bannerDest, "_activeBanner");
    if (!r_is_objc_ptr(banner)) return 0;

    uint64_t view = vl_try_msg0_main(banner, "view");
    if (!r_is_objc_ptr(view)) view = r_ivar_value(banner, "_view");
    if (!r_is_objc_ptr(view)) {
        uint64_t vc = vl_try_msg0_main(banner, "viewController");
        if (!r_is_objc_ptr(vc)) vc = r_ivar_value(banner, "_viewController");
        if (r_is_objc_ptr(vc)) view = vl_try_msg0_main(vc, "view");
    }
    return view;
}

#pragma mark - List view scanning (Notification Center / Lock Screen)

static uint64_t vl_find_list_controller(void)
{
    uint64_t app = vl_springboard_application();
    if (!r_is_objc_ptr(app)) return 0;

    uint64_t windows = r_msg2_main(app, "windows", 0, 0, 0, 0);
    if (!r_is_objc_ptr(windows)) return 0;
    uint64_t winCount = r_msg2_main(windows, "count", 0, 0, 0, 0);
    if (winCount > 64) winCount = 64;

    for (uint64_t i = 0; i < winCount; i++) {
        uint64_t win = r_msg2_main(windows, "objectAtIndex:", i, 0, 0, 0);
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

        if (strstr(cls, "CoverSheet") || strstr(cls, "NCNotification")) {
            uint64_t listView = r_ivar_value(root, "_listView");
            if (!r_is_objc_ptr(listView)) listView = vl_try_msg0_main(root, "listView");
            if (r_is_objc_ptr(listView)) return listView;

            uint64_t combined = r_ivar_value(root, "_combinedListViewController");
            if (!r_is_objc_ptr(combined)) combined = vl_try_msg0_main(root, "combinedListViewController");
            if (r_is_objc_ptr(combined)) {
                uint64_t clvc = r_ivar_value(combined, "_notificationListViewController");
                if (!r_is_objc_ptr(clvc)) clvc = vl_try_msg0_main(combined, "notificationListViewController");
                if (r_is_objc_ptr(clvc)) {
                    uint64_t lv = r_ivar_value(clvc, "_listView");
                    if (!r_is_objc_ptr(lv)) lv = vl_try_msg0_main(clvc, "listView");
                    if (r_is_objc_ptr(lv)) return lv;
                }
            }
        }
    }
    return 0;
}

static void vl_scan_list_cells(uint64_t listView, const VelvetStyle *style)
{
    if (!r_is_objc_ptr(listView)) return;

    uint64_t subviews = r_msg2_main(listView, "subviews", 0, 0, 0, 0);
    if (!r_is_objc_ptr(subviews)) return;

    uint64_t count = r_msg2_main(subviews, "count", 0, 0, 0, 0);
    if (count > 128) count = 128;

    for (uint64_t i = 0; i < count; i++) {
        uint64_t sv = r_msg2_main(subviews, "objectAtIndex:", i, 0, 0, 0);
        if (!r_is_objc_ptr(sv) || vl_is_styled(sv)) continue;

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

        if (strstr(cls, "NCNotificationListCell") || strstr(cls, "NCNotificationRequest") ||
            strstr(cls, "Cell") || strstr(cls, "cell")) {
            bool applied = vl_apply_style_to_view(sv, style);
            if (applied) vl_mark_styled(sv);
            vl_scan_subviews(sv, style, 0);
        }
    }
}

#pragma mark - Public API

bool velvet_apply_in_session(void)
{
    printf("[VELVET] apply\n");

    if (!gVelvetGlobalDirty) return true;

    const VelvetStyle *style = &gVelvetGlobalStyle;

    uint64_t app = vl_springboard_application();
    if (r_is_objc_ptr(app)) {
        uint64_t bannerDest = vl_banner_destination(app);
        if (r_is_objc_ptr(bannerDest)) {
            uint64_t bannerView = vl_active_banner_view(bannerDest);
            if (r_is_objc_ptr(bannerView) && !vl_is_styled(bannerView)) {
                bool applied = vl_apply_style_to_view(bannerView, style);
                if (applied) vl_mark_styled(bannerView);
                vl_scan_subviews(bannerView, style, 0);
                printf("[VELVET] styled active banner view=0x%llx\n", bannerView);
            }
        }

        uint64_t listView = vl_find_list_controller();
        if (r_is_objc_ptr(listView)) {
            vl_scan_list_cells(listView, style);
            printf("[VELVET] scanned list cells listView=0x%llx\n", listView);
        }
    }

    gVelvetGlobalDirty = false;
    return true;
}

bool velvet_tick_in_session(void)
{
    gVelvetTick++;

    if (gVelvetGlobalDirty) {
        velvet_apply_in_session();
        return true;
    }

    const VelvetStyle *style = &gVelvetGlobalStyle;

    uint64_t app = vl_springboard_application();
    if (!r_is_objc_ptr(app)) return false;

    uint64_t bannerDest = vl_banner_destination(app);
    if (r_is_objc_ptr(bannerDest)) {
        uint64_t bannerView = vl_active_banner_view(bannerDest);
        if (r_is_objc_ptr(bannerView) && !vl_is_styled(bannerView)) {
            bool applied = vl_apply_style_to_view(bannerView, style);
            if (applied) vl_mark_styled(bannerView);
            vl_scan_subviews(bannerView, style, 0);
            printf("[VELVET] tick: styled new banner view=0x%llx\n", bannerView);
        }
    }

    uint64_t listView = vl_find_list_controller();
    if (r_is_objc_ptr(listView)) {
        vl_scan_list_cells(listView, style);
    }

    if (gVelvetTick % 300 == 0) {
        printf("[VELVET] tick=%llu styled=%d\n",
               (unsigned long long)gVelvetTick, gVelvetStyledCount);
    }

    return true;
}

bool velvet_stop_in_session(void)
{
    printf("[VELVET] stop\n");
    gVelvetStyledCount = 0;
    return true;
}

void velvet_forget_remote_state(void)
{
    gVelvetStyledCount = 0;
    gVelvetTick = 0;
    gVelvetGlobalDirty = true;
}

bool velvet_has_remote_state(void)
{
    return gVelvetStyledCount > 0;
}
