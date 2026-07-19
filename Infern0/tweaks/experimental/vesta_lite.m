//
//  vesta_lite.m
//  Community-requested, session-only SpringBoard app drawer.
//

#import "vesta_lite.h"
#import "../remote_objc.h"
#import "../../LogTextView.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <math.h>
#import <string.h>

typedef struct { double x, y, width, height; } VestaRect;
typedef struct { double width, height; } VestaSize;

enum { VESTA_MAX_APPS = 36 };

static uint64_t s_panel = 0;
static uint64_t s_handle = 0;
static uint64_t s_host = 0;
static bool s_active = false;
static bool s_dirty = true;
static int s_width = 300;
static int s_y = 110;
static int s_height = 480;
static int s_radius = 24;
static int s_alpha = 90;

static uint64_t vesta_msg(uint64_t object, const char *selector,
                          uint64_t a0, uint64_t a1, uint64_t a2, uint64_t a3)
{
    if (!r_is_objc_ptr(object) || !selector ||
        !r_responds_main(object, selector)) return 0;
    return r_msg2_main(object, selector, a0, a1, a2, a3);
}

static void vesta_set_double(uint64_t object, const char *selector, double value)
{
    if (!r_is_objc_ptr(object) || !r_responds_main(object, selector)) return;
    r_msg2_main_raw(object, selector, &value, sizeof(value),
                    NULL, 0, NULL, 0, NULL, 0);
}

static uint64_t vesta_color(double r, double g, double b, double a)
{
    uint64_t cls = r_class("UIColor");
    return r_is_objc_ptr(cls)
        ? r_msg2_main_raw(cls, "colorWithRed:green:blue:alpha:",
                          &r, sizeof(r), &g, sizeof(g),
                          &b, sizeof(b), &a, sizeof(a)) : 0;
}

static uint64_t vesta_new_view(const char *className, VestaRect frame)
{
    uint64_t cls = r_class(className);
    uint64_t alloc = r_is_objc_ptr(cls)
        ? r_msg2_main(cls, "alloc", 0, 0, 0, 0) : 0;
    return r_is_objc_ptr(alloc)
        ? r_msg2_main_raw(alloc, "initWithFrame:",
                          &frame, sizeof(frame), NULL, 0, NULL, 0, NULL, 0) : 0;
}

static uint64_t vesta_label(VestaRect frame, const char *text, double size)
{
    uint64_t label = vesta_new_view("UILabel", frame);
    if (!r_is_objc_ptr(label)) return 0;
    uint64_t value = r_nsstr_retained(text ? text : "");
    if (r_is_objc_ptr(value)) {
        r_msg2_main(label, "setText:", value, 0, 0, 0);
        r_msg2_main(value, "release", 0, 0, 0, 0);
    }
    uint64_t fontClass = r_class("UIFont");
    uint64_t font = r_is_objc_ptr(fontClass)
        ? r_msg2_main_raw(fontClass, "boldSystemFontOfSize:",
                          &size, sizeof(size), NULL, 0, NULL, 0, NULL, 0) : 0;
    if (r_is_objc_ptr(font)) r_msg2_main(label, "setFont:", font, 0, 0, 0);
    r_msg2_main(label, "setTextAlignment:", 1, 0, 0, 0);
    r_msg2_main(label, "setUserInteractionEnabled:", 0, 0, 0, 0);
    return label;
}

static uint64_t vesta_home_host(void)
{
    uint64_t controllerClass = r_class("SBIconController");
    uint64_t controller = r_is_objc_ptr(controllerClass)
        ? vesta_msg(controllerClass, "sharedInstance", 0, 0, 0, 0) : 0;
    uint64_t manager = vesta_msg(controller, "iconManager", 0, 0, 0, 0);
    uint64_t owners[] = { manager, controller };
    const char *selectors[] = {
        "rootFolderController", "_rootFolderController",
        "rootFolderViewController", NULL
    };
    uint64_t root = 0;
    for (int owner = 0; owner < 2 && !r_is_objc_ptr(root); owner++)
        for (int i = 0; selectors[i] && !r_is_objc_ptr(root); i++)
            root = vesta_msg(owners[owner], selectors[i], 0, 0, 0, 0);
    const char *viewSelectors[] = { "rootFolderView", "folderView", "view", NULL };
    for (int i = 0; viewSelectors[i]; i++) {
        uint64_t view = vesta_msg(root, viewSelectors[i], 0, 0, 0, 0);
        if (r_is_objc_ptr(view)) return view;
    }
    return 0;
}

static int vesta_collect_bundles(uint64_t *out, int cap)
{
    if (!out || cap <= 0) return 0;
    memset(out, 0, sizeof(uint64_t) * (size_t)cap);
    uint64_t cls = r_class("SBApplicationController");
    uint64_t controller = r_is_objc_ptr(cls)
        ? vesta_msg(cls, "sharedInstance", 0, 0, 0, 0) : 0;
    uint64_t apps = vesta_msg(controller, "allApplications", 0, 0, 0, 0);
    if (!r_is_objc_ptr(apps))
        apps = vesta_msg(controller, "applications", 0, 0, 0, 0);
    if (r_is_objc_ptr(apps) && r_responds_main(apps, "allObjects"))
        apps = vesta_msg(apps, "allObjects", 0, 0, 0, 0);
    else if (r_is_objc_ptr(apps) && r_responds_main(apps, "allValues"))
        apps = vesta_msg(apps, "allValues", 0, 0, 0, 0);
    uint64_t count = r_is_objc_ptr(apps)
        ? vesta_msg(apps, "count", 0, 0, 0, 0) : 0;
    if (count > 500) count = 500;
    int accepted = 0, hidden = 0, system = 0, invalid = 0;
    for (uint64_t i = 0; i < count && accepted < cap; i++) {
        uint64_t app = vesta_msg(apps, "objectAtIndex:", i, 0, 0, 0);
        if (!r_is_objc_ptr(app)) continue;
        if ((r_responds_main(app, "isHidden") &&
             vesta_msg(app, "isHidden", 0, 0, 0, 0)) ||
            (r_responds_main(app, "isInternalApplication") &&
             vesta_msg(app, "isInternalApplication", 0, 0, 0, 0))) {
            hidden++;
            continue;
        }
        if ((r_responds_main(app, "isSystemApplication") &&
             vesta_msg(app, "isSystemApplication", 0, 0, 0, 0)) ||
            (r_responds_main(app, "isSystemApp") &&
             vesta_msg(app, "isSystemApp", 0, 0, 0, 0))) {
            system++;
            continue;
        }
        uint64_t bundle = vesta_msg(app, "bundleIdentifier", 0, 0, 0, 0);
        if (!r_is_objc_ptr(bundle))
            bundle = vesta_msg(app, "displayIdentifier", 0, 0, 0, 0);
        if (!r_is_objc_ptr(bundle)) { invalid++; continue; }
        bool duplicate = false;
        for (int j = 0; j < accepted; j++)
            if (out[j] == bundle) { duplicate = true; break; }
        if (!duplicate) out[accepted++] = bundle;
    }
    log_user("[VESTA][CATALOG] scanned=%llu accepted=%d cap=%d hidden=%d systemExcluded=%d invalid=%d rawStringReads=0.\n",
             (unsigned long long)count, accepted, cap, hidden, system, invalid);
    return accepted;
}

static uint64_t vesta_invocation(uint64_t target, const char *selector)
{
    uint64_t sel = r_sel(selector);
    uint64_t signature = sel
        ? r_msg2_main(target, "methodSignatureForSelector:", sel, 0, 0, 0) : 0;
    uint64_t cls = r_class("NSInvocation");
    uint64_t inv = r_is_objc_ptr(cls) && r_is_objc_ptr(signature)
        ? r_msg2_main(cls, "invocationWithMethodSignature:", signature, 0, 0, 0) : 0;
    if (!r_is_objc_ptr(inv)) return 0;
    r_msg2_main(inv, "setTarget:", target, 0, 0, 0);
    r_msg2_main(inv, "setSelector:", sel, 0, 0, 0);
    return inv;
}

static uint64_t vesta_hidden_invocation(uint64_t view, bool hidden)
{
    uint64_t inv = vesta_invocation(view, "setHidden:");
    uint64_t arg = r_dlsym_call(R_TIMEOUT, "malloc", 8, 0, 0, 0, 0, 0, 0, 0);
    uint64_t value = hidden ? 1 : 0;
    if (!r_is_objc_ptr(inv) || !arg ||
        !remote_write(arg, &value, sizeof(value))) {
        if (arg) r_free(arg);
        return 0;
    }
    r_msg2_main(inv, "setArgument:atIndex:", arg, 2, 0, 0);
    r_free(arg);
    r_msg2_main(inv, "retainArguments", 0, 0, 0, 0);
    return inv;
}

static uint64_t vesta_open_invocation(uint64_t workspace, uint64_t bundle)
{
    uint64_t inv = vesta_invocation(workspace, "openApplicationWithBundleID:");
    uint64_t arg = r_dlsym_call(R_TIMEOUT, "malloc", sizeof(bundle),
                                0, 0, 0, 0, 0, 0, 0);
    if (!r_is_objc_ptr(inv) || !arg ||
        !remote_write(arg, &bundle, sizeof(bundle))) {
        if (arg) r_free(arg);
        return 0;
    }
    r_msg2_main(inv, "setArgument:atIndex:", arg, 2, 0, 0);
    r_free(arg);
    r_msg2_main(inv, "retainArguments", 0, 0, 0, 0);
    return inv;
}

static uint64_t vesta_background_invocation(uint64_t invocation)
{
    if (!r_is_objc_ptr(invocation)) return 0;
    uint64_t outer = vesta_invocation(
        invocation, "performSelectorInBackground:withObject:");
    if (!r_is_objc_ptr(outer)) return 0;
    uint64_t selector = r_sel("invoke");
    uint64_t selectorArg = r_dlsym_call(R_TIMEOUT, "malloc", sizeof(selector),
                                        0, 0, 0, 0, 0, 0, 0);
    uint64_t objectArg = r_dlsym_call(R_TIMEOUT, "malloc", sizeof(uint64_t),
                                      0, 0, 0, 0, 0, 0, 0);
    uint64_t nilObject = 0;
    if (!selectorArg || !objectArg ||
        !remote_write(selectorArg, &selector, sizeof(selector)) ||
        !remote_write(objectArg, &nilObject, sizeof(nilObject))) {
        if (selectorArg) r_free(selectorArg);
        if (objectArg) r_free(objectArg);
        return 0;
    }
    r_msg2_main(outer, "setArgument:atIndex:", selectorArg, 2, 0, 0);
    r_msg2_main(outer, "setArgument:atIndex:", objectArg, 3, 0, 0);
    r_free(selectorArg);
    r_free(objectArg);
    r_msg2_main(outer, "retainArguments", 0, 0, 0, 0);
    return outer;
}

static bool vesta_bind(uint64_t view, uint64_t invocation)
{
    if (!r_is_objc_ptr(view) || !r_is_objc_ptr(invocation)) return false;
    uint64_t cls = r_class("UITapGestureRecognizer");
    uint64_t alloc = r_is_objc_ptr(cls)
        ? r_msg2_main(cls, "alloc", 0, 0, 0, 0) : 0;
    uint64_t tap = r_is_objc_ptr(alloc)
        ? r_msg2_main(alloc, "initWithTarget:action:",
                      invocation, r_sel("invoke"), 0, 0) : 0;
    if (!r_is_objc_ptr(tap)) return false;
    r_msg2_main(tap, "setCancelsTouchesInView:", 0, 0, 0, 0);
    r_msg2_main(view, "setUserInteractionEnabled:", 1, 0, 0, 0);
    r_msg2_main(view, "addGestureRecognizer:", tap, 0, 0, 0);
    r_dlsym_call(R_TIMEOUT, "objc_setAssociatedObject", tap,
                 r_sel("infern0VestaInvocation"), invocation,
                 1, 0, 0, 0, 0);
    r_msg2_main(tap, "release", 0, 0, 0, 0);
    return true;
}

static uint64_t vesta_icon_image(uint64_t bundle)
{
    uint64_t cls = r_class("UIImage");
    if (!r_is_objc_ptr(cls) ||
        !r_responds_main(cls, "_applicationIconImageForBundleIdentifier:format:scale:"))
        return 0;
    int64_t format = 2;
    double scale = UIScreen.mainScreen.scale;
    return r_msg2_main_raw(cls,
        "_applicationIconImageForBundleIdentifier:format:scale:",
        &bundle, sizeof(bundle), &format, sizeof(format),
        &scale, sizeof(scale), NULL, 0);
}

void pullover_configure(int width, int yOffset, int maxHeight,
                        int cornerRadius, int backgroundAlphaPercent)
{
    // Old PullOver shipped with a 76pt default. Treat that legacy value as an
    // automatic migration to Vesta's usable four-column drawer width.
    if (width < 200) width = 300;
    if (width > 380) width = 380;
    if (yOffset < 40) yOffset = 40;
    if (yOffset > 300) yOffset = 300;
    if (maxHeight < 260) maxHeight = 260;
    if (maxHeight > 720) maxHeight = 720;
    if (cornerRadius < 0) cornerRadius = 0;
    if (cornerRadius > 44) cornerRadius = 44;
    if (backgroundAlphaPercent < 30) backgroundAlphaPercent = 30;
    if (backgroundAlphaPercent > 100) backgroundAlphaPercent = 100;
    if (s_width != width || s_y != yOffset || s_height != maxHeight ||
        s_radius != cornerRadius || s_alpha != backgroundAlphaPercent)
        s_dirty = true;
    s_width = width; s_y = yOffset; s_height = maxHeight;
    s_radius = cornerRadius; s_alpha = backgroundAlphaPercent;
    log_user("[VESTA][CONFIG] width=%dpt y=%dpt maxHeight=%dpt radius=%dpt opacity=%d%% trigger=right-edge-tap appCap=%d.\n",
             s_width, s_y, s_height, s_radius, s_alpha, VESTA_MAX_APPS);
}

bool pullover_stop_in_session(void)
{
    bool removed = r_is_objc_ptr(s_panel) || r_is_objc_ptr(s_handle);
    if (r_is_objc_ptr(s_panel)) {
        r_msg2_main(s_panel, "removeFromSuperview", 0, 0, 0, 0);
        r_msg2_main(s_panel, "release", 0, 0, 0, 0);
    }
    if (r_is_objc_ptr(s_handle)) {
        r_msg2_main(s_handle, "removeFromSuperview", 0, 0, 0, 0);
        r_msg2_main(s_handle, "release", 0, 0, 0, 0);
    }
    if (r_is_objc_ptr(s_host)) r_msg2_main(s_host, "release", 0, 0, 0, 0);
    s_panel = s_handle = s_host = 0;
    s_active = false;
    s_dirty = true;
    log_user("[VESTA][RESTORE] drawerRemoved=%d stockIconLayoutWrites=0 result=%s.\n",
             removed, removed ? "success" : "already-stock");
    return true;
}

bool pullover_apply_in_session(void)
{
    if (s_active && !s_dirty && r_is_objc_ptr(s_panel) && r_is_objc_ptr(s_handle))
        return true;
    if (s_active || r_is_objc_ptr(s_panel) || r_is_objc_ptr(s_handle))
        pullover_stop_in_session();

    log_user("[VESTA][1/4] Resolving the native Home Screen host without a window or class-name VM scan...\n");
    uint64_t host = vesta_home_host();
    CGRect screen = UIScreen.mainScreen.bounds;
    if (!r_is_objc_ptr(host) || screen.size.width < 250 || screen.size.height < 400) {
        log_user("[VESTA][FAIL] Home Screen host unavailable; no views were attached.\n");
        return false;
    }

    double width = fmin((double)s_width, screen.size.width - 28.0);
    double height = fmin((double)s_height, screen.size.height - s_y - 34.0);
    double x = screen.size.width - width - 10.0;
    uint64_t panel = vesta_new_view("UIView", (VestaRect){x, s_y, width, height});
    uint64_t handle = vesta_new_view("UIView", (VestaRect){screen.size.width - 28.0,
                                                            s_y + 42.0, 28.0, 72.0});
    if (!r_is_objc_ptr(panel) || !r_is_objc_ptr(handle)) {
        if (r_is_objc_ptr(panel)) r_msg2_main(panel, "release", 0, 0, 0, 0);
        if (r_is_objc_ptr(handle)) r_msg2_main(handle, "release", 0, 0, 0, 0);
        log_user("[VESTA][FAIL] Drawer shell allocation failed; Home Screen remains stock.\n");
        return false;
    }
    uint64_t dark = vesta_color(0.025, 0.03, 0.045, (double)s_alpha / 100.0);
    uint64_t accent = vesta_color(1.0, 0.22, 0.16, 0.96);
    if (r_is_objc_ptr(dark)) r_msg2_main(panel, "setBackgroundColor:", dark, 0, 0, 0);
    if (r_is_objc_ptr(accent)) r_msg2_main(handle, "setBackgroundColor:", accent, 0, 0, 0);
    r_msg2_main(panel, "setClipsToBounds:", 1, 0, 0, 0);
    vesta_set_double(vesta_msg(panel, "layer", 0, 0, 0, 0), "setCornerRadius:", s_radius);
    vesta_set_double(vesta_msg(handle, "layer", 0, 0, 0, 0), "setCornerRadius:", 14.0);

    uint64_t title = vesta_label((VestaRect){18, 10, width - 72, 34}, "VESTA", 17.0);
    uint64_t close = vesta_label((VestaRect){width - 48, 8, 40, 40}, "X", 16.0);
    uint64_t glyph = vesta_label((VestaRect){0, 0, 28, 72}, "<", 18.0);
    uint64_t white = vesta_color(1, 1, 1, 1);
    if (r_is_objc_ptr(white)) {
        if (r_is_objc_ptr(title)) r_msg2_main(title, "setTextColor:", white, 0, 0, 0);
        if (r_is_objc_ptr(close)) r_msg2_main(close, "setTextColor:", white, 0, 0, 0);
        if (r_is_objc_ptr(glyph)) r_msg2_main(glyph, "setTextColor:", white, 0, 0, 0);
    }
    if (r_is_objc_ptr(title)) { r_msg2_main(panel, "addSubview:", title, 0, 0, 0); r_msg2_main(title, "release", 0, 0, 0, 0); }
    if (r_is_objc_ptr(close)) { r_msg2_main(close, "setUserInteractionEnabled:", 1, 0, 0, 0); r_msg2_main(panel, "addSubview:", close, 0, 0, 0); }
    if (r_is_objc_ptr(glyph)) { r_msg2_main(handle, "addSubview:", glyph, 0, 0, 0); r_msg2_main(glyph, "release", 0, 0, 0, 0); }

    log_user("[VESTA][2/4] Reading up to %d visible third-party applications...\n", VESTA_MAX_APPS);
    uint64_t bundles[VESTA_MAX_APPS] = {0};
    int appCount = vesta_collect_bundles(bundles, VESTA_MAX_APPS);
    uint64_t scroll = vesta_new_view("UIScrollView", (VestaRect){8, 50, width - 16, height - 58});
    uint64_t workspaceClass = r_class("LSApplicationWorkspace");
    uint64_t workspace = r_is_objc_ptr(workspaceClass)
        ? vesta_msg(workspaceClass, "defaultWorkspace", 0, 0, 0, 0) : 0;
    int columns = width >= 290.0 ? 4 : 3;
    double cell = (width - 32.0) / columns;
    double iconSize = fmin(58.0, cell - 12.0);
    int installed = 0, imageFallbacks = 0, actionFailures = 0;
    log_user("[VESTA][3/4] Building %d pressable drawer items in %d columns...\n",
             appCount, columns);
    for (int i = 0; i < appCount && r_is_objc_ptr(scroll); i++) {
        int row = i / columns, column = i % columns;
        double tileX = column * cell + (cell - iconSize) * 0.5;
        double tileY = row * (iconSize + 18.0) + 8.0;
        uint64_t tile = vesta_new_view("UIView", (VestaRect){tileX, tileY, iconSize, iconSize});
        if (!r_is_objc_ptr(tile)) continue;
        r_msg2_main(tile, "setClipsToBounds:", 1, 0, 0, 0);
        vesta_set_double(vesta_msg(tile, "layer", 0, 0, 0, 0),
                         "setCornerRadius:", iconSize * 0.24);
        uint64_t image = vesta_icon_image(bundles[i]);
        uint64_t imageView = r_is_objc_ptr(image)
            ? vesta_new_view("UIImageView", (VestaRect){0, 0, iconSize, iconSize}) : 0;
        if (r_is_objc_ptr(imageView)) {
            r_msg2_main(imageView, "setImage:", image, 0, 0, 0);
            r_msg2_main(imageView, "setContentMode:", 1, 0, 0, 0);
            r_msg2_main(imageView, "setUserInteractionEnabled:", 0, 0, 0, 0);
            r_msg2_main(tile, "addSubview:", imageView, 0, 0, 0);
            r_msg2_main(imageView, "release", 0, 0, 0, 0);
        } else {
            imageFallbacks++;
            uint64_t fallback = vesta_color(0.18, 0.20, 0.25, 1.0);
            if (r_is_objc_ptr(fallback)) r_msg2_main(tile, "setBackgroundColor:", fallback, 0, 0, 0);
        }
        uint64_t open = vesta_open_invocation(workspace, bundles[i]);
        uint64_t backgroundOpen = vesta_background_invocation(open);
        if (r_is_objc_ptr(backgroundOpen)) open = backgroundOpen;
        if (!vesta_bind(tile, open)) actionFailures++;
        r_msg2_main(scroll, "addSubview:", tile, 0, 0, 0);
        r_msg2_main(tile, "release", 0, 0, 0, 0);
        installed++;
    }
    if (r_is_objc_ptr(scroll)) {
        int rows = (installed + columns - 1) / columns;
        VestaSize content = { width - 16.0, fmax(height - 58.0, rows * (iconSize + 18.0) + 16.0) };
        r_msg2_main_raw(scroll, "setContentSize:", &content, sizeof(content),
                        NULL, 0, NULL, 0, NULL, 0);
        r_msg2_main(scroll, "setShowsVerticalScrollIndicator:", 0, 0, 0, 0);
        r_msg2_main(panel, "addSubview:", scroll, 0, 0, 0);
        r_msg2_main(scroll, "release", 0, 0, 0, 0);
    }

    uint64_t show = vesta_hidden_invocation(panel, false);
    uint64_t hideHandle = vesta_hidden_invocation(handle, true);
    uint64_t hide = vesta_hidden_invocation(panel, true);
    uint64_t showHandle = vesta_hidden_invocation(handle, false);
    bool controls = vesta_bind(handle, show) && vesta_bind(handle, hideHandle) &&
                    r_is_objc_ptr(close) && vesta_bind(close, hide) && vesta_bind(close, showHandle);
    if (r_is_objc_ptr(close)) r_msg2_main(close, "release", 0, 0, 0, 0);
    if (!controls || installed == 0 || actionFailures == installed) {
        r_msg2_main(panel, "release", 0, 0, 0, 0);
        r_msg2_main(handle, "release", 0, 0, 0, 0);
        log_user("[VESTA][FAIL] controls=%d installed=%d actionFailures=%d; nothing attached.\n",
                 controls, installed, actionFailures);
        return false;
    }

    r_msg2_main(panel, "setHidden:", 1, 0, 0, 0);
    r_msg2_main(host, "addSubview:", panel, 0, 0, 0);
    r_msg2_main(host, "addSubview:", handle, 0, 0, 0);
    r_msg2_main(host, "retain", 0, 0, 0, 0);
    s_panel = panel; s_handle = handle; s_host = host;
    s_active = true; s_dirty = false;
    log_user("[VESTA][4/4] active=1 apps=%d columns=%d imageFallbacks=%d actionFailures=%d panelHidden=1 nativeLayoutWrites=0 vmClassScans=0. Tap the red right-edge handle to open.\n",
             installed, columns, imageFallbacks, actionFailures);
    return true;
}

void pullover_forget_remote_state(void)
{
    s_panel = s_handle = s_host = 0;
    s_active = false;
    s_dirty = true;
    log_user("[VESTA][FORGET] cleared stale remote drawer pointers.\n");
}
