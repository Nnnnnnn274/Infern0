//
//  sb_walk.m
//  Lifted verbatim from darksword_layout.m's rc_collect_list_views /
//  rc_collect_from_windows so themer.m and any future tweak can share them
//  without duplicating the BFS.
//

#import "sb_walk.h"
#import "remote_objc.h"
#import "../TaskRop/RemoteCall.h"
#import "../VPhoneDebug.h"

#import <sys/socket.h>
#import <sys/un.h>
#import <unistd.h>
#import <errno.h>

static uint64_t sw_safe_msg(uint64_t obj, const char *selname,
                            uint64_t a, uint64_t b, uint64_t c, uint64_t d)
{
    if (!obj) return 0;
    uint64_t sel = r_sel(selname);
    uint64_t rs  = r_sel("respondsToSelector:");
    if (!sel || !rs) return 0;
    if (!r_msg(obj, rs, sel, 0, 0, 0)) return 0;
    return r_msg(obj, sel, a, b, c, d);
}

#define CY_VPHONE_BRIDGE_MAGIC 0x43595342u
#define CY_VPHONE_BRIDGE_SOCK "/private/var/mobile/Library/Caches/com.zeroxjf.cyanide.vphone-springboard.sock"

typedef struct __attribute__((packed)) {
    uint32_t magic;
    uint32_t op;
    uint64_t addr;
    uint64_t size;
    uint64_t args[8];
    char name[128];
} SBWBridgeReq;

typedef struct __attribute__((packed)) {
    uint32_t magic;
    uint32_t status;
    uint64_t result;
    uint64_t extra;
} SBWBridgeResp;

static const char *sbw_class_name_from_ptr(uint64_t klass);

static bool sbw_read_full(int fd, void *buf, size_t len) {
    uint8_t *p = buf;
    while (len) { ssize_t n = read(fd, p, len); if (n <= 0) { if (n < 0 && errno == EINTR) continue; return false; } p += n; len -= n; }
    return true;
}
static bool sbw_write_full(int fd, const void *buf, size_t len) {
    const uint8_t *p = buf;
    while (len) { ssize_t n = write(fd, p, len); if (n <= 0) { if (n < 0 && errno == EINTR) continue; return false; } p += n; len -= n; }
    return true;
}

static int sb_collect_views_via_bridge_root(uint64_t root, const char *className, uint64_t *out, int cap)
{
    if (!root || !className || !className[0]) return 0;
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;

    struct sockaddr_un sun = {0};
    sun.sun_family = AF_UNIX;
    strlcpy(sun.sun_path, CY_VPHONE_BRIDGE_SOCK, sizeof(sun.sun_path));
    if (connect(fd, (struct sockaddr *)&sun, sizeof(sun)) != 0) { close(fd); return -1; }

    SBWBridgeReq req = {0};
    req.magic = CY_VPHONE_BRIDGE_MAGIC;
    req.op = 7;
    req.addr = root;
    req.args[0] = (uint64_t)cap;
    strlcpy(req.name, className, sizeof(req.name));

    if (!sbw_write_full(fd, &req, sizeof(req))) { close(fd); return -1; }

    SBWBridgeResp resp = {0};
    if (!sbw_read_full(fd, &resp, sizeof(resp)) || resp.magic != CY_VPHONE_BRIDGE_MAGIC || resp.status != 0) {
        close(fd); return -1;
    }
    int found = (int)resp.result;
    if (found > cap) found = cap;
    if (found > 0 && resp.extra > 0) {
        size_t readSz = (size_t)(found * sizeof(uint64_t));
        if (readSz > resp.extra) readSz = (size_t)resp.extra;
        if (!sbw_read_full(fd, out, readSz)) { close(fd); return -1; }
    }
    close(fd);
    return found;
}

int sb_collect_views(uint64_t root, uint64_t klass, uint64_t *out, int cap)
{
    if (!root || !klass || cap <= 0) return 0;

    if (remote_call_uses_vphone_bridge()) {
        const char *name = sbw_class_name_from_ptr(klass);
        if (name) {
            int n = sb_collect_views_via_bridge_root(root, name, out, cap);
            if (n >= 0) return n;
        }
    }
    uint64_t selSub  = r_sel("subviews");
    uint64_t selCnt  = r_sel("count");
    uint64_t selObj  = r_sel("objectAtIndex:");
    uint64_t selKind = r_sel("isKindOfClass:");

    enum { QMAX = 4096 };
    static uint64_t q[QMAX];
    int head = 0, tail = 0, found = 0, visited = 0;
    q[tail++] = root;
    while (head < tail && visited < QMAX) {
        uint64_t v = q[head++];
        visited++;
        if (!v) continue;
        if (r_msg(v, selKind, klass, 0, 0, 0)) {
            if (found < cap) out[found++] = v;
            continue;
        }
        uint64_t subs = r_msg(v, selSub, 0, 0, 0, 0);
        if (!subs) continue;
        uint64_t cn = r_msg(subs, selCnt, 0, 0, 0, 0);
        if (cn > 256) cn = 256;
        for (uint64_t i = 0; i < cn && tail < QMAX; i++) {
            uint64_t c = r_msg(subs, selObj, i, 0, 0, 0);
            if (c) q[tail++] = c;
        }
    }
    return found;
}

static int sb_collect_views_via_bridge(const char *className, uint64_t *out, int cap)
{
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;

    struct sockaddr_un sun = {0};
    sun.sun_family = AF_UNIX;
    strlcpy(sun.sun_path, CY_VPHONE_BRIDGE_SOCK, sizeof(sun.sun_path));
    if (connect(fd, (struct sockaddr *)&sun, sizeof(sun)) != 0) { close(fd); return -1; }

    SBWBridgeReq req = {0};
    req.magic = CY_VPHONE_BRIDGE_MAGIC;
    req.op = 6;
    req.args[0] = (uint64_t)cap;
    strlcpy(req.name, className, sizeof(req.name));

    if (!sbw_write_full(fd, &req, sizeof(req))) { close(fd); return -1; }

    SBWBridgeResp resp = {0};
    if (!sbw_read_full(fd, &resp, sizeof(resp)) || resp.magic != CY_VPHONE_BRIDGE_MAGIC || resp.status != 0) {
        close(fd);
        return -1;
    }

    int found = (int)resp.result;
    if (found > cap) found = cap;
    if (found > 0 && resp.extra > 0) {
        size_t readSz = (size_t)(found * sizeof(uint64_t));
        if (readSz > resp.extra) readSz = (size_t)resp.extra;
        if (!sbw_read_full(fd, out, readSz)) { close(fd); return -1; }
    }
    close(fd);
    return found;
}

int sb_collect_views_in_windows_by_name(const char *className, uint64_t *out, int cap)
{
    if (!className || !className[0]) return 0;
    int n = sb_collect_views_via_bridge(className, out, cap);
    if (n < 0) {
        printf("[SB_WALK] vphone bridge sb_collect_views failed for %s\n", className);
    }
    if (n >= 0)
        printf("[SB_WALK] vphone bridge sb_collect_views class=%s found=%d\n", className, n);
    return n;
}

static uint64_t sbw_cached_SBIconListView = 0;
static uint64_t sbw_cached_SBIconView = 0;

static const char *sbw_class_name_from_ptr(uint64_t klass)
{
    if (klass == sbw_cached_SBIconListView && klass) return "SBIconListView";
    if (klass == sbw_cached_SBIconView && klass) return "SBIconView";

    uint64_t p = r_class("SBIconListView");
    if (p) sbw_cached_SBIconListView = p;
    if (p == klass) return "SBIconListView";

    p = r_class("SBIconView");
    if (p) sbw_cached_SBIconView = p;
    if (p == klass) return "SBIconView";

    return NULL;
}

int sb_collect_views_in_windows(uint64_t klass, uint64_t *out, int cap)
{
    if (remote_call_uses_vphone_bridge()) {
        const char *name = sbw_class_name_from_ptr(klass);
        if (name) {
            int bridged = sb_collect_views_in_windows_by_name(name, out, cap);
            if (bridged >= 0) return bridged;
            printf("[SB_WALK] falling back to generic RemoteCall view walk for %s\n", name);
        }
    }

    uint64_t clsApp = r_class("UIApplication");
    if (!clsApp) return 0;
    uint64_t app = sw_safe_msg(clsApp, "sharedApplication", 0, 0, 0, 0);
    if (!app) return 0;

    int n = 0;
    uint64_t wins = sw_safe_msg(app, "windows", 0, 0, 0, 0);
    if (wins) {
        uint64_t wc = r_msg(wins, r_sel("count"), 0, 0, 0, 0);
        if (wc > 32) wc = 32;
        for (uint64_t i = 0; i < wc && n < cap; i++) {
            uint64_t w = r_msg(wins, r_sel("objectAtIndex:"), i, 0, 0, 0);
            if (w) n += sb_collect_views(w, klass, out + n, cap - n);
        }
    }
    if (n == 0) {
        uint64_t kw = sw_safe_msg(app, "keyWindow", 0, 0, 0, 0);
        if (kw) n += sb_collect_views(kw, klass, out + n, cap - n);
    }
    return n;
}

int sb_collect_windows(uint64_t *out, int cap)
{
    if (!out || cap <= 0) return 0;
    uint64_t clsApp = r_class("UIApplication");
    if (!clsApp) return 0;
    uint64_t app = sw_safe_msg(clsApp, "sharedApplication", 0, 0, 0, 0);
    if (!app) return 0;

    int n = 0;
    uint64_t wins = sw_safe_msg(app, "windows", 0, 0, 0, 0);
    if (wins) {
        uint64_t count = r_msg(wins, r_sel("count"), 0, 0, 0, 0);
        if (count > (uint64_t)cap) count = (uint64_t)cap;
        for (uint64_t i = 0; i < count; i++) {
            uint64_t win = r_msg(wins, r_sel("objectAtIndex:"), i, 0, 0, 0);
            if (r_is_objc_ptr(win)) out[n++] = win;
        }
    }
    if (n == 0) {
        uint64_t key = sw_safe_msg(app, "keyWindow", 0, 0, 0, 0);
        if (r_is_objc_ptr(key)) out[n++] = key;
    }
    return n;
}

uint64_t sb_frontmost_window(void)
{
    uint64_t windows[64] = {0};
    int count = sb_collect_windows(windows, 64);
    for (int i = count - 1; i >= 0; i--) {
        uint64_t hidden = sw_safe_msg(windows[i], "isHidden", 0, 0, 0, 0);
        if (!(hidden & 0xff)) return windows[i];
    }
    for (int i = 0; i < count; i++) {
        uint64_t isKey = sw_safe_msg(windows[i], "isKeyWindow", 0, 0, 0, 0);
        if (isKey & 0xff) return windows[i];
    }
    return count > 0 ? windows[count - 1] : 0;
}
