//
//  macaronlite.m
//  infern0
//

#import "macaronlite.h"
#import "remote_objc.h"
#import "sb_walk.h"
#import "../TaskRop/RemoteCall.h"
#import "../LogTextView.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <limits.h>
#import <stdio.h>
#import <string.h>

#define MACARON_MAX_BACKGROUNDS 96
#define MACARON_MAX_MATERIALS 48
#define MACARON_MAX_ACCENTS 64
#define MACARON_MAX_PATTERN_BYTES (8 * 1024 * 1024)

typedef enum {
    MacaronSurfaceDock = 0,
    MacaronSurfaceFolder,
    MacaronSurfacePageDots,
    MacaronSurfaceSearchPill,
} MacaronSurface;

typedef enum {
    MacaronAccentTint = 0,
    MacaronAccentPageIndicator,
    MacaronAccentCurrentPageIndicator,
} MacaronAccentProperty;

typedef struct {
    uint64_t object;
    uint64_t originalColor;
    MacaronSurface surface;
} MacaronBackgroundState;

typedef struct {
    uint64_t object;
    bool originalHidden;
} MacaronMaterialState;

typedef struct {
    uint64_t object;
    uint64_t originalColor;
    MacaronSurface surface;
    MacaronAccentProperty property;
} MacaronAccentState;

static MacaronLiteMode gMacaronMode = MacaronLiteModeSolid;
static int gMacaronOpacityPct = 82;
static bool gMacaronKeepBlur = true;
static bool gMacaronStyleDock = true;
static bool gMacaronStyleFolders = true;
static bool gMacaronStylePageDots = true;
static bool gMacaronStyleSearchPill = true;
static char gMacaronPrimary[16] = "#6E5AE6";
static char gMacaronSecondary[16] = "#34C8FF";
static char gMacaronPhotoPath[PATH_MAX] = {0};
static char gMacaronRenderedPath[PATH_MAX] = {0};
static double gMacaronRenderedScale = 1.0;
static MacaronBackgroundState gMacaronBackgrounds[MACARON_MAX_BACKGROUNDS];
static MacaronMaterialState gMacaronMaterials[MACARON_MAX_MATERIALS];
static MacaronAccentState gMacaronAccents[MACARON_MAX_ACCENTS];
static int gMacaronBackgroundCount = 0;
static int gMacaronMaterialCount = 0;
static int gMacaronAccentCount = 0;
static bool gMacaronApplied = false;

static void macaron_copy(char *dst, size_t cap, const char *src)
{
    if (!dst || cap == 0) return;
    snprintf(dst, cap, "%s", src ? src : "");
}

static UIColor *macaron_local_color(const char *raw, CGFloat alpha)
{
    NSString *hex = [NSString stringWithUTF8String:(raw ? raw : "")] ?: @"";
    hex = [[hex stringByReplacingOccurrencesOfString:@"#" withString:@""] uppercaseString];
    if (hex.length != 6) hex = @"6E5AE6";
    unsigned value = 0;
    [[NSScanner scannerWithString:hex] scanHexInt:&value];
    return [UIColor colorWithRed:((value >> 16) & 0xff) / 255.0
                           green:((value >> 8) & 0xff) / 255.0
                            blue:(value & 0xff) / 255.0
                           alpha:alpha];
}

static bool macaron_render_pattern(void)
{
    if (!gMacaronStyleDock) return true;
    if (gMacaronMode != MacaronLiteModeGradient &&
        gMacaronMode != MacaronLiteModePhoto) return true;

    CGFloat screenWidth = MAX(UIScreen.mainScreen.bounds.size.width, 320.0);
    CGSize size = CGSizeMake(screenWidth, 120.0);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    UIImage *source = gMacaronMode == MacaronLiteModePhoto && gMacaronPhotoPath[0]
        ? [UIImage imageWithContentsOfFile:[NSString stringWithUTF8String:gMacaronPhotoPath]]
        : nil;
    if (gMacaronMode == MacaronLiteModePhoto && !source) {
        log_user("[MACARON][RENDER][ERROR] Photo mode has no readable source image.\n");
        return false;
    }

    UIImage *rendered = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        if (source) {
            CGFloat scale = MAX(size.width / source.size.width, size.height / source.size.height);
            CGSize drawSize = CGSizeMake(source.size.width * scale, source.size.height * scale);
            CGRect drawRect = CGRectMake((size.width - drawSize.width) * 0.5,
                                         (size.height - drawSize.height) * 0.5,
                                         drawSize.width, drawSize.height);
            [source drawInRect:drawRect
                     blendMode:kCGBlendModeNormal
                         alpha:gMacaronOpacityPct / 100.0];
        } else {
            NSArray *colors = @[
                (id)macaron_local_color(gMacaronPrimary, gMacaronOpacityPct / 100.0).CGColor,
                (id)macaron_local_color(gMacaronSecondary, gMacaronOpacityPct / 100.0).CGColor
            ];
            CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
            CFArrayRef array = (__bridge CFArrayRef)colors;
            CGGradientRef gradient = CGGradientCreateWithColors(space, array, NULL);
            CGContextDrawLinearGradient(context.CGContext, gradient,
                                        CGPointMake(0, size.height * 0.5),
                                        CGPointMake(size.width, size.height * 0.5), 0);
            CGGradientRelease(gradient);
            CGColorSpaceRelease(space);
        }
    }];

    NSData *png = UIImagePNGRepresentation(rendered);
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                               NSUserDomainMask, YES).firstObject;
    NSString *folder = [documents stringByAppendingPathComponent:@"MacaronLite"];
    NSError *error = nil;
    if (![NSFileManager.defaultManager createDirectoryAtPath:folder
                                withIntermediateDirectories:YES
                                                 attributes:nil error:&error]) {
        log_user("[MACARON][RENDER][ERROR] Could not create render directory: %s.\n",
                 error.localizedDescription.UTF8String);
        return false;
    }
    NSString *path = [folder stringByAppendingPathComponent:@"DockPattern.png"];
    if (![png writeToFile:path options:NSDataWritingAtomic error:&error]) {
        log_user("[MACARON][RENDER][ERROR] Could not write pattern: %s.\n",
                 error.localizedDescription.UTF8String);
        return false;
    }
    macaron_copy(gMacaronRenderedPath, sizeof(gMacaronRenderedPath), path.UTF8String);
    gMacaronRenderedScale = MAX(rendered.scale, 1.0);
    log_user("[MACARON][RENDER] Prepared %s pattern %.0fx%.0fpt at %.1fx scale at %s.\n",
             gMacaronMode == MacaronLiteModePhoto ? "photo" : "gradient",
             size.width, size.height, gMacaronRenderedScale,
             gMacaronRenderedPath);
    return true;
}

void macaronlite_configure(MacaronLiteMode mode,
                           int opacityPct,
                           bool keepBlur,
                           bool styleDock,
                           bool styleFolders,
                           bool stylePageDots,
                           bool styleSearchPill,
                           const char *primaryHex,
                           const char *secondaryHex,
                           const char *photoPath)
{
    if (mode < MacaronLiteModeSolid || mode > MacaronLiteModeTransparent)
        mode = MacaronLiteModeSolid;
    gMacaronMode = mode;
    gMacaronOpacityPct = opacityPct < 0 ? 0 : (opacityPct > 100 ? 100 : opacityPct);
    gMacaronKeepBlur = keepBlur;
    gMacaronStyleDock = styleDock;
    gMacaronStyleFolders = styleFolders;
    gMacaronStylePageDots = stylePageDots;
    gMacaronStyleSearchPill = styleSearchPill;
    macaron_copy(gMacaronPrimary, sizeof(gMacaronPrimary), primaryHex);
    macaron_copy(gMacaronSecondary, sizeof(gMacaronSecondary), secondaryHex);
    macaron_copy(gMacaronPhotoPath, sizeof(gMacaronPhotoPath), photoPath);
    gMacaronRenderedPath[0] = '\0';
    gMacaronRenderedScale = 1.0;
    log_user("[MACARON][CONFIG] mode=%d opacity=%d%% blur=%d surfaces={dock:%d folders:%d dots:%d search:%d} primary=%s secondary=%s photo=%s.\n",
             mode, gMacaronOpacityPct, keepBlur,
             styleDock, styleFolders, stylePageDots, styleSearchPill,
             gMacaronPrimary, gMacaronSecondary,
             gMacaronPhotoPath[0] ? gMacaronPhotoPath : "(none)");
}

static uint64_t macaron_remote_solid_color(const char *hex, double alphaScale)
{
    double requestedAlpha = (gMacaronOpacityPct / 100.0) * alphaScale;
    UIColor *local = macaron_local_color(hex, MIN(MAX(requestedAlpha, 0.0), 1.0));
    CGFloat red = 0, green = 0, blue = 0, alpha = 0;
    [local getRed:&red green:&green blue:&blue alpha:&alpha];
    double r = red, g = green, b = blue, a = alpha;
    uint64_t cls = r_class("UIColor");
    return cls ? r_msg2_main_raw(cls, "colorWithRed:green:blue:alpha:",
                                 &r, sizeof(r), &g, sizeof(g),
                                 &b, sizeof(b), &a, sizeof(a)) : 0;
}

static uint64_t macaron_remote_pattern_color(void)
{
    const char *path = gMacaronRenderedPath[0] ? gMacaronRenderedPath : gMacaronPhotoPath;
    if (!path || !path[0]) return 0;
    NSData *bytes = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:path]];
    if (bytes.length == 0 || bytes.length > MACARON_MAX_PATTERN_BYTES) {
        log_user("[MACARON][TRANSFER][ERROR] Pattern size=%lu is outside the safe 1..%u byte range.\n",
                 (unsigned long)bytes.length, (unsigned)MACARON_MAX_PATTERN_BYTES);
        return 0;
    }

    uint64_t remoteBuffer = r_dlsym_call(R_TIMEOUT, "malloc",
                                         bytes.length, 0, 0, 0, 0, 0, 0, 0);
    if (!remoteBuffer || !remote_write(remoteBuffer, bytes.bytes, bytes.length)) {
        log_user("[MACARON][TRANSFER][ERROR] Could not copy %lu PNG bytes into SpringBoard.\n",
                 (unsigned long)bytes.length);
        if (remoteBuffer) r_free(remoteBuffer);
        return 0;
    }

    uint64_t dataAlloc = r_msg2(r_class("NSData"), "alloc", 0, 0, 0, 0);
    uint64_t remoteData = r_is_objc_ptr(dataAlloc)
        ? r_msg2(dataAlloc, "initWithBytes:length:", remoteBuffer, bytes.length, 0, 0)
        : 0;
    r_free(remoteBuffer);
    if (!r_is_objc_ptr(remoteData)) {
        log_user("[MACARON][TRANSFER][ERROR] SpringBoard could not create NSData for the pattern.\n");
        return 0;
    }

    double scale = gMacaronRenderedScale > 0.0 ? gMacaronRenderedScale : 1.0;
    uint64_t image = r_msg2_main_raw(r_class("UIImage"), "imageWithData:scale:",
                                     &remoteData, sizeof(remoteData),
                                     &scale, sizeof(scale),
                                     NULL, 0, NULL, 0);
    if (r_is_objc_ptr(image)) r_msg2_main(image, "retain", 0, 0, 0, 0);
    r_msg2(remoteData, "release", 0, 0, 0, 0);
    uint64_t color = r_is_objc_ptr(image)
        ? r_msg2_main(r_class("UIColor"), "colorWithPatternImage:", image, 0, 0, 0) : 0;
    if (r_is_objc_ptr(image)) r_msg2_main(image, "release", 0, 0, 0, 0);
    log_user("[MACARON][TRANSFER] Sent %lu PNG bytes to SpringBoard; decode=%s color=%s.\n",
             (unsigned long)bytes.length,
             r_is_objc_ptr(image) ? "ok" : "failed",
             r_is_objc_ptr(color) ? "ok" : "failed");
    return color;
}

static bool macaron_seen_background(uint64_t object)
{
    for (int i = 0; i < gMacaronBackgroundCount; i++)
        if (gMacaronBackgrounds[i].object == object) return true;
    return false;
}

static bool macaron_capture_background(uint64_t object, MacaronSurface surface)
{
    if (!r_is_objc_ptr(object) || macaron_seen_background(object) ||
        gMacaronBackgroundCount >= MACARON_MAX_BACKGROUNDS ||
        !r_responds_main(object, "setBackgroundColor:")) return false;
    uint64_t original = r_msg2_main(object, "backgroundColor", 0, 0, 0, 0);
    if (r_is_objc_ptr(original))
        original = r_dlsym_call(R_TIMEOUT, "objc_retain", original, 0, 0, 0, 0, 0, 0, 0);
    gMacaronBackgrounds[gMacaronBackgroundCount++] =
        (MacaronBackgroundState){ object, original, surface };
    return true;
}

static bool macaron_seen_material(uint64_t object)
{
    for (int i = 0; i < gMacaronMaterialCount; i++)
        if (gMacaronMaterials[i].object == object) return true;
    return false;
}

static void macaron_capture_material(uint64_t object)
{
    if (!r_is_objc_ptr(object) || macaron_seen_material(object) ||
        gMacaronMaterialCount >= MACARON_MAX_MATERIALS ||
        !r_responds_main(object, "setHidden:")) return;
    bool hidden = r_msg2_main(object, "isHidden", 0, 0, 0, 0) != 0;
    gMacaronMaterials[gMacaronMaterialCount++] = (MacaronMaterialState){ object, hidden };
}

static const char *macaron_accent_getter(MacaronAccentProperty property)
{
    switch (property) {
        case MacaronAccentTint: return "tintColor";
        case MacaronAccentPageIndicator: return "pageIndicatorTintColor";
        case MacaronAccentCurrentPageIndicator: return "currentPageIndicatorTintColor";
    }
    return NULL;
}

static const char *macaron_accent_setter(MacaronAccentProperty property)
{
    switch (property) {
        case MacaronAccentTint: return "setTintColor:";
        case MacaronAccentPageIndicator: return "setPageIndicatorTintColor:";
        case MacaronAccentCurrentPageIndicator: return "setCurrentPageIndicatorTintColor:";
    }
    return NULL;
}

static bool macaron_seen_accent(uint64_t object, MacaronAccentProperty property)
{
    for (int i = 0; i < gMacaronAccentCount; i++) {
        if (gMacaronAccents[i].object == object &&
            gMacaronAccents[i].property == property) return true;
    }
    return false;
}

static bool macaron_capture_accent(uint64_t object,
                                   MacaronSurface surface,
                                   MacaronAccentProperty property)
{
    const char *getter = macaron_accent_getter(property);
    const char *setter = macaron_accent_setter(property);
    if (!r_is_objc_ptr(object) || !getter || !setter ||
        macaron_seen_accent(object, property) ||
        gMacaronAccentCount >= MACARON_MAX_ACCENTS ||
        !r_responds_main(object, getter) ||
        !r_responds_main(object, setter)) return false;
    uint64_t original = r_msg2_main(object, getter, 0, 0, 0, 0);
    if (r_is_objc_ptr(original))
        original = r_dlsym_call(R_TIMEOUT, "objc_retain", original, 0, 0, 0, 0, 0, 0, 0);
    gMacaronAccents[gMacaronAccentCount++] =
        (MacaronAccentState){ object, original, surface, property };
    return true;
}

static int macaron_collect_docks(uint64_t *out, int cap)
{
    int count = 0;
    const char *classes[] = {
        "SBDockView", "SBFloatingDockView", "SBFloatingDockPlatterView",
        "SBFloatingDockRootView", "SBFloatingDockContainerView"
    };
    for (size_t c = 0; c < sizeof(classes) / sizeof(classes[0]); c++) {
        uint64_t cls = r_class(classes[c]);
        if (!cls) continue;
        uint64_t found[12] = {0};
        int n = sb_collect_views_in_windows(cls, found, 12);
        for (int i = 0; i < n && count < cap; i++) {
            bool duplicate = false;
            for (int j = 0; j < count; j++) if (out[j] == found[i]) duplicate = true;
            if (!duplicate) out[count++] = found[i];
        }
    }
    return count;
}

static void macaron_collect_targets_from_dock(uint64_t dock)
{
    const char *ivars[] = {
        "_backgroundView", "_backgroundViewContainer", "_backgroundEffectView",
        "_backgroundMaterialView", "_platterView", "_materialView"
    };
    bool found = false;
    for (size_t i = 0; i < sizeof(ivars) / sizeof(ivars[0]); i++) {
        uint64_t value = r_ivar_value(dock, ivars[i]);
        if (macaron_capture_background(value, MacaronSurfaceDock)) {
            char className[96] = {0};
            sb_read_class_name(value, className, sizeof(className));
            log_user("[MACARON][DISCOVERY] dock=0x%llx ivar=%s target=0x%llx class=%s.\n",
                     dock, ivars[i], value, className[0] ? className : "unknown");
            found = true;
        }
    }
    if (!found && macaron_capture_background(dock, MacaronSurfaceDock)) {
        char className[96] = {0};
        sb_read_class_name(dock, className, sizeof(className));
        log_user("[MACARON][DISCOVERY] Using Dock root target=0x%llx class=%s.\n",
                 dock, className[0] ? className : "unknown");
    }

    const char *materialClasses[] = {
        "MTMaterialView", "UIVisualEffectView", "_UIVisualEffectBackdropView"
    };
    for (size_t c = 0; c < sizeof(materialClasses) / sizeof(materialClasses[0]); c++) {
        uint64_t cls = r_class(materialClasses[c]);
        if (!cls) continue;
        uint64_t materials[16] = {0};
        int n = sb_collect_views(dock, cls, materials, 16);
        for (int i = 0; i < n; i++) macaron_capture_material(materials[i]);
    }
}

static int macaron_collect_named_views(const char *const *classes,
                                       size_t classCount,
                                       uint64_t *out,
                                       int cap)
{
    int count = 0;
    for (size_t c = 0; c < classCount; c++) {
        uint64_t cls = r_class(classes[c]);
        if (!r_is_objc_ptr(cls)) continue;
        uint64_t found[32] = {0};
        int n = sb_collect_views_in_windows(cls, found, 32);
        for (int i = 0; i < n && count < cap; i++) {
            bool duplicate = false;
            for (int j = 0; j < count; j++) {
                if (out[j] == found[i]) { duplicate = true; break; }
            }
            if (!duplicate) out[count++] = found[i];
        }
    }
    return count;
}

static void macaron_collect_background_surface(uint64_t root,
                                               MacaronSurface surface,
                                               const char *surfaceName,
                                               bool captureTint)
{
    int beforeBackgrounds = gMacaronBackgroundCount;
    int beforeAccents = gMacaronAccentCount;
    const char *ivars[] = {
        "_backgroundView", "_backgroundViewContainer", "_backgroundEffectView",
        "_backgroundMaterialView", "_platterView", "_materialView",
        "_blurView", "_visualEffectView"
    };
    macaron_capture_background(root, surface);
    if (captureTint) macaron_capture_accent(root, surface, MacaronAccentTint);
    for (size_t i = 0; i < sizeof(ivars) / sizeof(ivars[0]); i++) {
        uint64_t value = r_ivar_value(root, ivars[i]);
        macaron_capture_background(value, surface);
        if (captureTint) macaron_capture_accent(value, surface, MacaronAccentTint);
    }
    char className[96] = {0};
    sb_read_class_name(root, className, sizeof(className));
    log_user("[MACARON][DISCOVERY][%s] root=0x%llx class=%s backgrounds=%d accents=%d.\n",
             surfaceName, root, className[0] ? className : "unknown",
             gMacaronBackgroundCount - beforeBackgrounds,
             gMacaronAccentCount - beforeAccents);
}

static int macaron_collect_folders(void)
{
    const char *classes[] = {
        "SBFolderBackgroundView", "SBFolderIconBackgroundView",
        "SBFolderIconImageView", "SBHLibraryPodFolderView"
    };
    uint64_t roots[48] = {0};
    int count = macaron_collect_named_views(classes,
                                            sizeof(classes) / sizeof(classes[0]),
                                            roots, 48);
    for (int i = 0; i < count; i++)
        macaron_collect_background_surface(roots[i], MacaronSurfaceFolder,
                                           "FOLDER", false);
    return count;
}

static int macaron_collect_search_pills(void)
{
    const char *classes[] = {
        "SBHSearchPillView", "SBHSearchBar", "SBHSearchTextField",
        "SBIconListSearchPillView"
    };
    uint64_t roots[20] = {0};
    int count = macaron_collect_named_views(classes,
                                            sizeof(classes) / sizeof(classes[0]),
                                            roots, 20);
    for (int i = 0; i < count; i++)
        macaron_collect_background_surface(roots[i], MacaronSurfaceSearchPill,
                                           "SEARCH", true);
    return count;
}

static int macaron_collect_page_dots(void)
{
    const char *classes[] = {
        "SBIconListPageControl", "SBHPageControl",
        "SBHIconManagerPageControl", "SBRootFolderPageControl"
    };
    uint64_t controls[20] = {0};
    int count = macaron_collect_named_views(classes,
                                            sizeof(classes) / sizeof(classes[0]),
                                            controls, 20);
    for (int i = 0; i < count; i++) {
        int before = gMacaronAccentCount;
        macaron_capture_accent(controls[i], MacaronSurfacePageDots,
                               MacaronAccentPageIndicator);
        macaron_capture_accent(controls[i], MacaronSurfacePageDots,
                               MacaronAccentCurrentPageIndicator);
        macaron_capture_accent(controls[i], MacaronSurfacePageDots,
                               MacaronAccentTint);
        char className[96] = {0};
        sb_read_class_name(controls[i], className, sizeof(className));
        log_user("[MACARON][DISCOVERY][DOTS] control=0x%llx class=%s accents=%d.\n",
                 controls[i], className[0] ? className : "unknown",
                 gMacaronAccentCount - before);
    }
    return count;
}

bool macaronlite_apply_in_session(void)
{
    if (gMacaronApplied) macaronlite_stop_in_session();
    if (!gMacaronStyleDock && !gMacaronStyleFolders &&
        !gMacaronStylePageDots && !gMacaronStyleSearchPill) {
        log_user("[MACARON][ERROR] No Home Screen surfaces are enabled.\n");
        return false;
    }
    if (!macaron_render_pattern()) return false;

    uint64_t clearColor = 0;
    if (gMacaronMode == MacaronLiteModeTransparent)
        clearColor = r_msg2_main(r_class("UIColor"), "clearColor", 0, 0, 0, 0);
    uint64_t primaryColor = gMacaronMode == MacaronLiteModeTransparent
        ? clearColor : macaron_remote_solid_color(gMacaronPrimary, 1.0);
    uint64_t secondaryColor = gMacaronMode == MacaronLiteModeTransparent
        ? clearColor : macaron_remote_solid_color(gMacaronSecondary, 0.55);
    uint64_t dockColor = 0;
    if (gMacaronStyleDock) {
        if (gMacaronMode == MacaronLiteModeTransparent)
            dockColor = clearColor;
        else if (gMacaronMode == MacaronLiteModeSolid)
            dockColor = primaryColor;
        else
            dockColor = macaron_remote_pattern_color();
    }
    if ((gMacaronStyleDock && !r_is_objc_ptr(dockColor)) ||
        ((!gMacaronStyleDock || gMacaronStyleFolders ||
          gMacaronStylePageDots || gMacaronStyleSearchPill) &&
         !r_is_objc_ptr(primaryColor))) {
        log_user("[MACARON][ERROR] Could not create the requested remote colors.\n");
        return false;
    }

    int dockCount = 0, folderCount = 0, dotsCount = 0, searchCount = 0;
    if (gMacaronStyleDock) {
        uint64_t docks[20] = {0};
        dockCount = macaron_collect_docks(docks, 20);
        for (int i = 0; i < dockCount; i++) macaron_collect_targets_from_dock(docks[i]);
    }
    if (gMacaronStyleFolders) folderCount = macaron_collect_folders();
    if (gMacaronStylePageDots) dotsCount = macaron_collect_page_dots();
    if (gMacaronStyleSearchPill) searchCount = macaron_collect_search_pills();

    log_user("[MACARON][DISCOVERY] roots={dock:%d folders:%d dots:%d search:%d} captured={backgrounds:%d accents:%d materials:%d}.\n",
             dockCount, folderCount, dotsCount, searchCount,
             gMacaronBackgroundCount, gMacaronAccentCount, gMacaronMaterialCount);
    if (gMacaronBackgroundCount == 0 && gMacaronAccentCount == 0) {
        log_user("[MACARON][ERROR] No safe target was found for the enabled surfaces; no views changed.\n");
        macaronlite_forget_remote_state();
        return false;
    }

    for (int i = 0; i < gMacaronMaterialCount; i++) {
        bool hide = !gMacaronKeepBlur || gMacaronMode == MacaronLiteModeTransparent;
        r_msg2_main(gMacaronMaterials[i].object, "setHidden:", hide, 0, 0, 0);
    }
    int surfaceBackgrounds[4] = {0};
    int surfaceAccents[4] = {0};
    for (int i = 0; i < gMacaronBackgroundCount; i++) {
        MacaronBackgroundState state = gMacaronBackgrounds[i];
        uint64_t color = state.surface == MacaronSurfaceDock ? dockColor : primaryColor;
        r_msg2_main(state.object, "setBackgroundColor:", color, 0, 0, 0);
        if (state.surface >= MacaronSurfaceDock &&
            state.surface <= MacaronSurfaceSearchPill)
            surfaceBackgrounds[state.surface]++;
    }
    for (int i = 0; i < gMacaronAccentCount; i++) {
        MacaronAccentState state = gMacaronAccents[i];
        const char *setter = macaron_accent_setter(state.property);
        uint64_t color = state.property == MacaronAccentPageIndicator
            ? secondaryColor : primaryColor;
        if (setter) r_msg2_main(state.object, setter, color, 0, 0, 0);
        if (state.surface >= MacaronSurfaceDock &&
            state.surface <= MacaronSurfaceSearchPill)
            surfaceAccents[state.surface]++;
    }

    gMacaronApplied = true;
    log_user("[MACARON][OK] Applied mode=%d backgrounds={dock:%d folders:%d dots:%d search:%d} accents={dock:%d folders:%d dots:%d search:%d} materialViews=%d blur=%d. Icon views, layout, and gesture recognizers were untouched.\n",
             gMacaronMode,
             surfaceBackgrounds[MacaronSurfaceDock],
             surfaceBackgrounds[MacaronSurfaceFolder],
             surfaceBackgrounds[MacaronSurfacePageDots],
             surfaceBackgrounds[MacaronSurfaceSearchPill],
             surfaceAccents[MacaronSurfaceDock],
             surfaceAccents[MacaronSurfaceFolder],
             surfaceAccents[MacaronSurfacePageDots],
             surfaceAccents[MacaronSurfaceSearchPill],
             gMacaronMaterialCount, gMacaronKeepBlur);
    return true;
}

bool macaronlite_stop_in_session(void)
{
    bool ok = true;
    for (int i = gMacaronBackgroundCount - 1; i >= 0; i--) {
        MacaronBackgroundState state = gMacaronBackgrounds[i];
        if (r_is_objc_ptr(state.object))
            r_msg2_main(state.object, "setBackgroundColor:", state.originalColor, 0, 0, 0);
        else
            ok = false;
        if (r_is_objc_ptr(state.originalColor))
            r_dlsym_call(R_TIMEOUT, "objc_release", state.originalColor, 0, 0, 0, 0, 0, 0, 0);
    }
    for (int i = gMacaronMaterialCount - 1; i >= 0; i--) {
        MacaronMaterialState state = gMacaronMaterials[i];
        if (!r_is_objc_ptr(state.object)) { ok = false; continue; }
        r_msg2_main(state.object, "setHidden:", state.originalHidden, 0, 0, 0);
    }
    for (int i = gMacaronAccentCount - 1; i >= 0; i--) {
        MacaronAccentState state = gMacaronAccents[i];
        const char *setter = macaron_accent_setter(state.property);
        if (r_is_objc_ptr(state.object) && setter)
            r_msg2_main(state.object, setter, state.originalColor, 0, 0, 0);
        else
            ok = false;
        if (r_is_objc_ptr(state.originalColor))
            r_dlsym_call(R_TIMEOUT, "objc_release", state.originalColor, 0, 0, 0, 0, 0, 0, 0);
    }
    log_user("[MACARON][RESTORE] Restored %d background color(s), %d accent color(s), and %d material visibility state(s); result=%s.\n",
             gMacaronBackgroundCount, gMacaronAccentCount,
             gMacaronMaterialCount, ok ? "clean" : "partial");
    memset(gMacaronBackgrounds, 0, sizeof(gMacaronBackgrounds));
    memset(gMacaronMaterials, 0, sizeof(gMacaronMaterials));
    memset(gMacaronAccents, 0, sizeof(gMacaronAccents));
    gMacaronBackgroundCount = 0;
    gMacaronMaterialCount = 0;
    gMacaronAccentCount = 0;
    gMacaronApplied = false;
    return ok;
}

void macaronlite_forget_remote_state(void)
{
    memset(gMacaronBackgrounds, 0, sizeof(gMacaronBackgrounds));
    memset(gMacaronMaterials, 0, sizeof(gMacaronMaterials));
    memset(gMacaronAccents, 0, sizeof(gMacaronAccents));
    gMacaronBackgroundCount = 0;
    gMacaronMaterialCount = 0;
    gMacaronAccentCount = 0;
    gMacaronApplied = false;
}
