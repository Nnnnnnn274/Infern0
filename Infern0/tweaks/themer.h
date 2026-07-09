//
//  themer.h
//  Per-bundle icon swap. Walks every SBIconView in SpringBoard and replaces
//  its image with a PNG from `themePath/<bundleID>.png`.
//

#ifndef themer_h
#define themer_h

#import <stdbool.h>
#ifdef __OBJC__
#import <Foundation/Foundation.h>
#endif

// Apply the theme rooted at `themePath` — a local-process directory of
// `<bundleID>.png` files. Builds an in-memory dictionary and forwards to
// themer_apply_data_in_session.
bool themer_apply_in_session(const char *themePath);

#ifdef __OBJC__
// Apply a theme provided in-memory. Keys are bundle identifiers
// (NSString *), values are raw PNG bytes (NSData *). Caller can free the
// dictionary as soon as the call returns. Idempotent within a session —
// per-bundle SB UIImages are cached and reused. Must run under
// settings_rc_lock with the SpringBoard RemoteCall session open.
bool themer_apply_data_in_session(NSDictionary<NSString *, NSData *> *imageDataByBundle);

// Repaint currently visible icon views from the in-session UIImage cache only.
// This is for SpringBoard re-entry paths where views keep our overrideImage
// pointer but their inner image contents/layer were reset.
bool themer_repaint_cached_views_in_session(void);

// Same cache-only repaint, but does not trust SBIconImageView.displayedImage
// as proof that the visible layer is still intact.
bool themer_force_repaint_cached_views_in_session(void);

// Re-pin only dynamic icons (Clock/Calendar). This is intentionally narrower
// than a cached repaint so wake/unlock repairs don't touch normal app icons.
bool themer_repaint_dynamic_cached_views_in_session(void);

// Repaint visible icon views from the active theme data. This is heavier than
// dynamic-only repair and is meant for initial/event-triggered SnowBoard Lite
// repairs so newly visible pages can lazily pick up their themed images.
bool themer_repaint_visible_theme_views_in_session(void);
#endif

// Release the in-SB UIImage cache. SB will re-render native icons on its
// next layout pass.
bool themer_stop_in_session(void);

// Drop local pointer cache without touching SpringBoard. Call from the
// SpringBoard-restart handler so we don't release dangling pointers under
// the next SB incarnation.
void themer_forget_remote_state(void);

#endif /* themer_h */
