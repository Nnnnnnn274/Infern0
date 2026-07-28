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

#define MACARON_MAX_BACKGROUNDS 24
#define MACARON_MAX_MATERIALS 48
#define MACARON_MAX_PATTERN_BYTES (8 * 1024 * 1024)

typedef struct {
    uint64_t object;
    uint64_t originalColor;
} MacaronBackgroundState;

typedef struct {
    uint64_t object;
    bool originalHidden;
} MacaronMaterialState;

static MacaronLiteMode gMacaronMode = MacaronLiteModeSolid;
static int gMacaronOpacityPct = 82;
static bool gMacaronKeepBlur = true;
static char gMacaronPrimary[16] = "#6E5AE6";
static char gMacaronSecondary[16] = "#34C8FF";
static char gMacaronPhotoPath[PATH_MAX] = {0};
static char gMacaronRenderedPath[PATH_MAX] = {0};
static double gMacaronRenderedScale = 1.0;
static MacaronBackgroundState gMacaronBackgrounds[MACARON_MAX_BACKGROUNDS];
static MacaronMaterialState gMacaronMaterials[MACARON_MAX_MATERIALS];
static int gMacaronBackgroundCount = 0;
static int gMacaronMaterialCount = 0;
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
                           const char *primaryHex,
                           const char *secondaryHex,
                           const char *photoPath)
{
    if (mode < MacaronLiteModeSolid || mode > MacaronLiteModeTransparent)
        mode = MacaronLiteModeSolid;
    gMacaronMode = mode;
    gMacaronOpacityPct = opacityPct < 0 ? 0 : (opacityPct > 100 ? 100 : opacityPct);
    gMacaronKeepBlur = keepBlur;
    macaron_copy(gMacaronPrimary, sizeof(gMacaronPrimary), primaryHex);
    macaron_copy(gMacaronSecondary, sizeof(gMacaronSecondary), secondaryHex);
    macaron_copy(gMacaronPhotoPath, sizeof(gMacaronPhotoPath), photoPath);
    gMacaronRenderedPath[0] = '\0';
    gMacaronRenderedScale = 1.0;
    log_user("[MACARON][CONFIG] mode=%d opacity=%d%% blur=%d primary=%s secondary=%s photo=%s.\n",
             mode, gMacaronOpacityPct, keepBlur,
             gMacaronPrimary, gMacaronSecondary,
             gMacaronPhotoPath[0] ? gMacaronPhotoPath : "(none)");
}

static uint64_t macaron_remote_solid_color(void)
{
    UIColor *local = macaron_local_color(gMacaronPrimary, gMacaronOpacityPct / 100.0);
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

static bool macaron_capture_background(uint64_t object)
{
    if (!r_is_objc_ptr(object) || macaron_seen_background(object) ||
        gMacaronBackgroundCount >= MACARON_MAX_BACKGROUNDS ||
        !r_responds_main(object, "setBackgroundColor:")) return false;
    uint64_t original = r_msg2_main(object, "backgroundColor", 0, 0, 0, 0);
    if (r_is_objc_ptr(original))
        original = r_dlsym_call(R_TIMEOUT, "objc_retain", original, 0, 0, 0, 0, 0, 0, 0);
    gMacaronBackgrounds[gMacaronBackgroundCount++] = (MacaronBackgroundState){ object, original };
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
        if (macaron_capture_background(value)) {
            char className[96] = {0};
            sb_read_class_name(value, className, sizeof(className));
            log_user("[MACARON][DISCOVERY] dock=0x%llx ivar=%s target=0x%llx class=%s.\n",
                     dock, ivars[i], value, className[0] ? className : "unknown");
            found = true;
        }
    }
    if (!found && macaron_capture_background(dock)) {
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

bool macaronlite_apply_in_session(void)
{
    if (gMacaronApplied) macaronlite_stop_in_session();
    if (!macaron_render_pattern()) return false;

    uint64_t color = 0;
    if (gMacaronMode == MacaronLiteModeTransparent)
        color = r_msg2_main(r_class("UIColor"), "clearColor", 0, 0, 0, 0);
    else if (gMacaronMode == MacaronLiteModeSolid)
        color = macaron_remote_solid_color();
    else
        color = macaron_remote_pattern_color();
    if (!r_is_objc_ptr(color)) {
        log_user("[MACARON][ERROR] Could not create the requested remote UIColor.\n");
        return false;
    }

    uint64_t docks[20] = {0};
    int dockCount = macaron_collect_docks(docks, 20);
    log_user("[MACARON][DISCOVERY] Found %d normal/floating Dock container(s).\n", dockCount);
    for (int i = 0; i < dockCount; i++) macaron_collect_targets_from_dock(docks[i]);
    if (gMacaronBackgroundCount == 0) {
        log_user("[MACARON][ERROR] No safe Dock background target was found; no views changed.\n");
        macaronlite_forget_remote_state();
        return false;
    }

    for (int i = 0; i < gMacaronMaterialCount; i++) {
        bool hide = !gMacaronKeepBlur || gMacaronMode == MacaronLiteModeTransparent;
        r_msg2_main(gMacaronMaterials[i].object, "setHidden:", hide, 0, 0, 0);
    }
    for (int i = 0; i < gMacaronBackgroundCount; i++)
        r_msg2_main(gMacaronBackgrounds[i].object, "setBackgroundColor:", color, 0, 0, 0);

    gMacaronApplied = true;
    log_user("[MACARON][OK] Applied mode=%d to %d Dock background(s); materialViews=%d blur=%d. Icon views and gesture recognizers were untouched.\n",
             gMacaronMode, gMacaronBackgroundCount, gMacaronMaterialCount, gMacaronKeepBlur);
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
    log_user("[MACARON][RESTORE] Restored %d background color(s) and %d material visibility state(s); result=%s.\n",
             gMacaronBackgroundCount, gMacaronMaterialCount, ok ? "clean" : "partial");
    memset(gMacaronBackgrounds, 0, sizeof(gMacaronBackgrounds));
    memset(gMacaronMaterials, 0, sizeof(gMacaronMaterials));
    gMacaronBackgroundCount = 0;
    gMacaronMaterialCount = 0;
    gMacaronApplied = false;
    return ok;
}

void macaronlite_forget_remote_state(void)
{
    memset(gMacaronBackgrounds, 0, sizeof(gMacaronBackgrounds));
    memset(gMacaronMaterials, 0, sizeof(gMacaronMaterials));
    gMacaronBackgroundCount = 0;
    gMacaronMaterialCount = 0;
    gMacaronApplied = false;
}
