//
//  mood_wallpaper.m
//  Cyanide
//
//  Static-image wallpaper switcher. It owns the same bottom SpringBoard
//  wallpaper layer space as LiveWP/Metal Lock Light, so callers must keep those
//  features mutually exclusive.
//

#import "mood_wallpaper.h"
#import "remote_objc.h"
#import "../LogTextView.h"
#import "../TaskRop/RemoteCall.h"
#import "../SettingsViewController.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <math.h>
#import <stdio.h>

typedef struct { double x, y, w, h; } MoodWallpaperRect;

static const int kMoodWallpaperMaxImages = 8;

static uint64_t g_mood_home_views[8] = {0};
static uint64_t g_mood_lock_views[8] = {0};
static uint64_t g_mood_home_window = 0;
static uint64_t g_mood_lock_window = 0;
static uint64_t g_mood_images[8] = {0};
static int g_mood_image_count = 0;
static int g_mood_main_index = 0;
static int g_mood_current_index = -1;
static bool g_mood_configured = false;

NSString *mood_wallpaper_absolute_path(NSString *relativePath)
{
    if (![relativePath isKindOfClass:NSString.class] || relativePath.length == 0) return nil;
    if ([relativePath hasPrefix:@"/"]) return relativePath;
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    return docs.length ? [docs stringByAppendingPathComponent:relativePath] : nil;
}

static bool mood_is_kind_of_class_fast(uint64_t obj, uint64_t cls)
{
    if (!r_is_objc_ptr(obj) || !r_is_objc_ptr(cls)) return false;

    uint64_t cur = r_dlsym_call(R_TIMEOUT, "object_getClass", obj, 0, 0, 0, 0, 0, 0, 0);
    for (int depth = 0; r_is_objc_ptr(cur) && depth < 16; depth++) {
        if (cur == cls) return true;
        cur = r_dlsym_call(R_TIMEOUT, "class_getSuperclass", cur, 0, 0, 0, 0, 0, 0, 0);
    }
    return false;
}

static uint64_t mood_load_image_retained(NSString *path)
{
    if (path.length == 0) return 0;
    uint64_t pathStr = r_nsstr_retained(path.UTF8String);
    if (!r_is_objc_ptr(pathStr)) return 0;

    uint64_t image = r_msg2_main(r_class("UIImage"), "imageWithContentsOfFile:", pathStr, 0, 0, 0);
    r_msg2(pathStr, "release", 0, 0, 0, 0);
    if (r_is_objc_ptr(image)) image = r_msg2_main(image, "retain", 0, 0, 0, 0);
    return image;
}

static void mood_release_images(void)
{
    for (int i = 0; i < kMoodWallpaperMaxImages; i++) {
        if (r_is_objc_ptr(g_mood_images[i])) r_msg2_main(g_mood_images[i], "release", 0, 0, 0, 0);
        g_mood_images[i] = 0;
    }
    g_mood_image_count = 0;
}

static uint64_t mood_make_image_view(uint64_t image)
{
    MoodWallpaperRect zero = {0, 0, 1, 1};
    uint64_t obj = r_msg2(r_class("UIImageView"), "alloc", 0, 0, 0, 0);
    if (!r_is_objc_ptr(obj)) return 0;
    uint64_t view = r_msg2_main_raw(obj, "initWithFrame:",
                                    &zero, sizeof(zero),
                                    NULL, 0, NULL, 0, NULL, 0);
    if (!r_is_objc_ptr(view)) view = obj;
    r_msg2_main(view, "setContentMode:", 2, 0, 0, 0); // UIViewContentModeScaleAspectFill
    r_msg2_main(view, "setClipsToBounds:", 1, 0, 0, 0);
    if (r_is_objc_ptr(image)) r_msg2_main(view, "setImage:", image, 0, 0, 0);
    return view;
}

static void mood_set_view_alpha(uint64_t view, double alpha)
{
    if (!r_is_objc_ptr(view)) return;
    r_msg2_main_raw(view, "setAlpha:",
                    &alpha, sizeof(alpha), NULL, 0, NULL, 0, NULL, 0);
    r_msg2_main(view, "setHidden:", alpha <= 0.0 ? 1 : 0, 0, 0, 0);
}

static void mood_remove_opacity_animation(uint64_t imageView)
{
    if (!r_is_objc_ptr(imageView)) return;
    uint64_t layer = r_msg2_main(imageView, "layer", 0, 0, 0, 0);
    if (!r_is_objc_ptr(layer)) return;
    uint64_t key = r_nsstr_retained("MoodWallpaperFade");
    r_msg2_main(layer, "removeAnimationForKey:", key, 0, 0, 0);
    if (r_is_objc_ptr(key)) r_msg2(key, "release", 0, 0, 0, 0);
}

static void mood_add_opacity_animation(uint64_t imageView, double from, double to)
{
    if (!r_is_objc_ptr(imageView)) return;
    uint64_t layer = r_msg2_main(imageView, "layer", 0, 0, 0, 0);
    if (!r_is_objc_ptr(layer)) return;
    uint64_t keyPath = r_nsstr_retained("opacity");
    uint64_t anim = r_msg2_main(r_class("CABasicAnimation"), "animationWithKeyPath:", keyPath, 0, 0, 0);
    if (r_is_objc_ptr(keyPath)) r_msg2(keyPath, "release", 0, 0, 0, 0);
    if (!r_is_objc_ptr(anim)) return;

    double duration = 0.22;
    uint64_t fromNum = r_msg2_main_raw(r_class("NSNumber"), "numberWithDouble:",
                                       &from, sizeof(from), NULL, 0, NULL, 0, NULL, 0);
    uint64_t toNum = r_msg2_main_raw(r_class("NSNumber"), "numberWithDouble:",
                                     &to, sizeof(to), NULL, 0, NULL, 0, NULL, 0);
    if (r_is_objc_ptr(fromNum)) r_msg2_main(anim, "setFromValue:", fromNum, 0, 0, 0);
    if (r_is_objc_ptr(toNum)) r_msg2_main(anim, "setToValue:", toNum, 0, 0, 0);
    r_msg2_main_raw(anim, "setDuration:",
                    &duration, sizeof(duration), NULL, 0, NULL, 0, NULL, 0);
    uint64_t key = r_nsstr_retained("MoodWallpaperFade");
    r_msg2_main(layer, "addAnimation:forKey:", anim, key, 0, 0);
    if (r_is_objc_ptr(key)) r_msg2(key, "release", 0, 0, 0, 0);
}

static bool mood_ensure_view_in_window_at_index(uint64_t view, uint64_t window, uint64_t index)
{
    if (!r_is_objc_ptr(view) || !r_is_objc_ptr(window)) return false;

    MoodWallpaperRect bounds = {0};
    r_msg2_main_struct_ret(window, "bounds", &bounds, sizeof(bounds),
                           NULL, 0, NULL, 0, NULL, 0, NULL, 0);
    r_msg2_main_raw(view, "setFrame:",
                    &bounds, sizeof(bounds), NULL, 0, NULL, 0, NULL, 0);

    uint64_t curSuper = r_msg2_main(view, "superview", 0, 0, 0, 0);
    if (curSuper != window) {
        if (r_is_objc_ptr(curSuper)) r_msg2_main(view, "removeFromSuperview", 0, 0, 0, 0);
        r_msg2_main(window, "insertSubview:atIndex:", view, index, 0, 0);
    }
    return true;
}

static bool mood_move_view_to_image_stack_top(uint64_t view, uint64_t window)
{
    if (!r_is_objc_ptr(view) || !r_is_objc_ptr(window)) return false;
    uint64_t topIndex = g_mood_image_count > 0 ? (uint64_t)(g_mood_image_count - 1) : 0;
    r_msg2_main_async(window, "insertSubview:atIndex:", view, topIndex, 0, 0);
    return true;
}

static bool mood_find_windows(uint64_t *homeOut, uint64_t *lockOut)
{
    if (homeOut) *homeOut = 0;
    if (lockOut) *lockOut = 0;

    uint64_t app = r_msg2_main(r_class("UIApplication"), "sharedApplication", 0, 0, 0, 0);
    if (!r_is_objc_ptr(app)) return false;
    uint64_t windows = r_msg2_main(app, "windows", 0, 0, 0, 0);
    uint64_t count = r_is_objc_ptr(windows) ? r_msg2_main(windows, "count", 0, 0, 0, 0) : 0;
    uint64_t homeScreenViewCls = r_class("SBHomeScreenView");
    uint64_t coverSheetCls = r_class("SBCoverSheetWindow");

    uint64_t homeWin = 0;
    uint64_t lockWin = 0;
    for (uint64_t i = 0; i < count && i < 32; i++) {
        uint64_t w = r_msg2_main(windows, "objectAtIndex:", i, 0, 0, 0);
        if (!r_is_objc_ptr(w)) continue;
        if (mood_is_kind_of_class_fast(w, coverSheetCls)) {
            lockWin = w;
            if (homeWin) break;
            continue;
        }
        if (!homeWin && r_is_objc_ptr(homeScreenViewCls)) {
            uint64_t subviews = r_msg2_main(w, "subviews", 0, 0, 0, 0);
            uint64_t subCount = r_is_objc_ptr(subviews) ? r_msg2_main(subviews, "count", 0, 0, 0, 0) : 0;
            for (uint64_t j = 0; j < subCount && j < 8; j++) {
                uint64_t sv = r_msg2_main(subviews, "objectAtIndex:", j, 0, 0, 0);
                if (mood_is_kind_of_class_fast(sv, homeScreenViewCls)) {
                    homeWin = w;
                    break;
                }
            }
        }
    }

    if (homeOut) *homeOut = homeWin;
    if (lockOut) *lockOut = lockWin;
    return r_is_objc_ptr(homeWin) || r_is_objc_ptr(lockWin);
}

static bool mood_attach_all_views(void)
{
    uint64_t homeWin = g_mood_home_window;
    uint64_t lockWin = g_mood_lock_window;
    if (!r_is_objc_ptr(homeWin) && !r_is_objc_ptr(lockWin)) {
        mood_find_windows(&homeWin, &lockWin);
    }
    if (!r_is_objc_ptr(homeWin) && !r_is_objc_ptr(lockWin)) return false;

    bool ok = false;
    for (int i = 0; i < g_mood_image_count; i++) {
        if (r_is_objc_ptr(homeWin)) {
            ok |= mood_ensure_view_in_window_at_index(g_mood_home_views[i], homeWin, (uint64_t)i);
            g_mood_home_window = homeWin;
        }
        if (r_is_objc_ptr(lockWin)) {
            ok |= mood_ensure_view_in_window_at_index(g_mood_lock_views[i], lockWin, (uint64_t)i);
            g_mood_lock_window = lockWin;
        }
    }
    return ok;
}

static bool mood_apply_index(int index)
{
    if (index < 0 || index >= g_mood_image_count) return false;
    if (!r_is_objc_ptr(g_mood_home_window) && !r_is_objc_ptr(g_mood_lock_window)) {
        if (!mood_attach_all_views()) return false;
    }

    if (r_is_objc_ptr(g_mood_home_window)) {
        mood_move_view_to_image_stack_top(g_mood_home_views[index], g_mood_home_window);
    }
    if (r_is_objc_ptr(g_mood_lock_window)) {
        mood_move_view_to_image_stack_top(g_mood_lock_views[index], g_mood_lock_window);
    }
    g_mood_current_index = index;
    return true;
}

static NSArray<NSString *> *mood_configured_relative_paths(void)
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSArray *raw = [d arrayForKey:kSettingsMoodWallpaperImagePaths];
    NSMutableArray<NSString *> *paths = [NSMutableArray arrayWithCapacity:kMoodWallpaperMaxImages];
    for (id item in raw) {
        if (paths.count >= kMoodWallpaperMaxImages) break;
        if (![item isKindOfClass:NSString.class]) continue;
        NSString *rel = (NSString *)item;
        if (rel.length > 0) [paths addObject:rel];
    }
    if (paths.count == 0) {
        NSString *left = [d stringForKey:kSettingsMoodWallpaperLeftPath];
        NSString *right = [d stringForKey:kSettingsMoodWallpaperRightPath];
        if (left.length > 0) [paths addObject:left];
        if (right.length > 0 && paths.count < kMoodWallpaperMaxImages) [paths addObject:right];
        if (paths.count > 0) {
            [d setObject:paths forKey:kSettingsMoodWallpaperImagePaths];
            [d synchronize];
        }
    }
    return paths;
}

static bool mood_is_static_image_path(NSString *path)
{
    NSString *ext = path.pathExtension.lowercaseString;
    return [ext isEqualToString:@"png"] ||
           [ext isEqualToString:@"jpg"] ||
           [ext isEqualToString:@"jpeg"] ||
           [ext isEqualToString:@"heic"] ||
           [ext isEqualToString:@"heif"];
}

bool mood_wallpaper_apply_in_session(void)
{
    uint32_t oldSettleUS = r_settle_us(0);
    bool ok = false;
    NSArray<NSString *> *relPaths = mood_configured_relative_paths();
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    id configuredMainObj = [d objectForKey:kSettingsMoodWallpaperMainIndex];

    if (relPaths.count < 2) {
        log_user("[MOOD-WP] Need at least two images.\n");
        goto out;
    }

    if (g_mood_configured) mood_wallpaper_stop_in_session();
    mood_release_images();

    for (NSString *rel in relPaths) {
        if (g_mood_image_count >= kMoodWallpaperMaxImages) break;
        NSString *path = mood_wallpaper_absolute_path(rel);
        if (path.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            log_user("[MOOD-WP] Skip missing image: %s\n", rel.UTF8String);
            continue;
        }
        if (!mood_is_static_image_path(path)) {
            log_user("[MOOD-WP] Skip non-static image: %s\n", rel.UTF8String);
            continue;
        }
        uint64_t image = mood_load_image_retained(path);
        if (!r_is_objc_ptr(image)) {
            log_user("[MOOD-WP] Skip undecodable image: %s\n", rel.UTF8String);
            continue;
        }
        g_mood_images[g_mood_image_count++] = image;
    }

    if (g_mood_image_count < 2) {
        log_user("[MOOD-WP] Fewer than two usable images.\n");
        goto out;
    }

    NSInteger configuredMain = configuredMainObj ? [d integerForKey:kSettingsMoodWallpaperMainIndex] : (g_mood_image_count / 2);
    if (configuredMain < 0) configuredMain = 0;
    if (configuredMain >= g_mood_image_count) configuredMain = g_mood_image_count - 1;
    g_mood_main_index = (int)configuredMain;
    int initialIndex = g_mood_main_index;
    for (int i = 0; i < g_mood_image_count; i++) {
        g_mood_home_views[i] = mood_make_image_view(g_mood_images[i]);
        g_mood_lock_views[i] = mood_make_image_view(g_mood_images[i]);
        mood_set_view_alpha(g_mood_home_views[i], 1.0);
        mood_set_view_alpha(g_mood_lock_views[i], 1.0);
        if (!r_is_objc_ptr(g_mood_home_views[i]) || !r_is_objc_ptr(g_mood_lock_views[i])) {
            log_user("[MOOD-WP] Failed to create wallpaper image views.\n");
            goto out;
        }
    }

    uint64_t homeWin = 0;
    uint64_t lockWin = 0;
    if (!mood_find_windows(&homeWin, &lockWin)) {
        log_user("[MOOD-WP] Could not find SpringBoard wallpaper host windows.\n");
        goto out;
    }
    g_mood_home_window = homeWin;
    g_mood_lock_window = lockWin;
    if (!mood_attach_all_views()) {
        log_user("[MOOD-WP] Failed to attach wallpaper views.\n");
        goto out;
    }
    mood_apply_index(initialIndex);
    g_mood_current_index = initialIndex;
    g_mood_configured = true;
    log_user("[MOOD-WP] OK: Mood Wallpaper active with %d images.\n", g_mood_image_count);
    ok = true;

out:
    if (!ok) {
        for (int i = 0; i < kMoodWallpaperMaxImages; i++) {
            if (r_is_objc_ptr(g_mood_home_views[i])) r_msg2_main(g_mood_home_views[i], "removeFromSuperview", 0, 0, 0, 0);
            if (r_is_objc_ptr(g_mood_lock_views[i])) r_msg2_main(g_mood_lock_views[i], "removeFromSuperview", 0, 0, 0, 0);
            g_mood_home_views[i] = 0;
            g_mood_lock_views[i] = 0;
        }
        g_mood_home_window = 0;
        g_mood_lock_window = 0;
        g_mood_current_index = -1;
        g_mood_main_index = 0;
        g_mood_configured = false;
        mood_release_images();
    }
    r_settle_us(oldSettleUS);
    return ok;
}

bool mood_wallpaper_update_index_in_session(int targetIndex)
{
    if (!g_mood_configured || g_mood_image_count < 2) return false;
    int nextIndex = targetIndex;
    if (nextIndex < 0) nextIndex = 0;
    if (nextIndex >= g_mood_image_count) nextIndex = g_mood_image_count - 1;
    if (nextIndex == g_mood_current_index) return true;
    log_user("[MOOD-WP] switch main=%d current=%d next=%d count=%d.\n",
             g_mood_main_index,
             g_mood_current_index,
             nextIndex,
             g_mood_image_count);
    return mood_apply_index(nextIndex);
}

bool mood_wallpaper_stop_in_session(void)
{
    for (int i = 0; i < kMoodWallpaperMaxImages; i++) {
        if (r_is_objc_ptr(g_mood_home_views[i])) r_msg2_main(g_mood_home_views[i], "removeFromSuperview", 0, 0, 0, 0);
        if (r_is_objc_ptr(g_mood_lock_views[i])) r_msg2_main(g_mood_lock_views[i], "removeFromSuperview", 0, 0, 0, 0);
        g_mood_home_views[i] = 0;
        g_mood_lock_views[i] = 0;
    }
    g_mood_home_window = 0;
    g_mood_lock_window = 0;
    g_mood_current_index = -1;
    g_mood_main_index = 0;
    g_mood_configured = false;
    mood_release_images();
    log_user("[MOOD-WP] stopped.\n");
    return true;
}

void mood_wallpaper_forget_remote_state(void)
{
    for (int i = 0; i < kMoodWallpaperMaxImages; i++) {
        g_mood_home_views[i] = 0;
        g_mood_lock_views[i] = 0;
    }
    g_mood_home_window = 0;
    g_mood_lock_window = 0;
    for (int i = 0; i < kMoodWallpaperMaxImages; i++) g_mood_images[i] = 0;
    g_mood_image_count = 0;
    g_mood_main_index = 0;
    g_mood_current_index = -1;
    g_mood_configured = false;
}
