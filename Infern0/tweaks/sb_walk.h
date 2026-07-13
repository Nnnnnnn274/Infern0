//
//  sb_walk.h
//  RemoteCall view-tree helpers shared between tweaks that need to find
//  SpringBoard views of a particular class (SBIconListView, SBIconView, etc).
//

#ifndef sb_walk_h
#define sb_walk_h

#import <stdint.h>

// BFS from `root` collecting subviews that are instances of `klass`.
// Matched views are NOT recursed into. Returns the count written to `out`,
// capped at `cap`. Not reentrant — uses a static BFS queue. Callers are
// already serialized under the settings RemoteCall lock.
int sb_collect_views(uint64_t root, uint64_t klass, uint64_t *out, int cap);

// Walks every UIApplication window (falls back to keyWindow if -windows
// returns empty) and collects views of `klass` across all of them.
int sb_collect_views_in_windows(uint64_t klass, uint64_t *out, int cap);

// Bridge-only variant: BFS via the vphone bridge using a class name string.
int sb_collect_views_in_windows_by_name(const char *className, uint64_t *out, int cap);

// Collects UIApplication's windows in back-to-front order. This avoids the
// deprecated -keyWindow path, which is commonly nil for SpringBoard scenes.
int sb_collect_windows(uint64_t *out, int cap);

// Returns the key window when one exists, otherwise the frontmost visible
// UIApplication window.
uint64_t sb_frontmost_window(void);

#endif /* sb_walk_h */
