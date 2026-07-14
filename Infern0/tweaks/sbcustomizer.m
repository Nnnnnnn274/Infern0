//
//  sbcustomizer.m
//

#import "sbcustomizer.h"
#import "remote_objc.h"
#import "../TaskRop/RemoteCall.h"
#import <stdio.h>
#import <unistd.h>
#import "../LogTextView.h"

static bool gSBCIPadDockEnabled = false;
static bool gSBCDockShowRecents = true;
static bool gSBCDockShowAppLibrary = true;

static int clamp(int v, int lo, int hi) {
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

static uint64_t try_msg0(uint64_t obj, const char *selName)
{
    if (!r_is_objc_ptr(obj) || !r_responds(obj, selName)) return 0;
    return r_msg2(obj, selName, 0, 0, 0, 0);
}

void sbcustomizer_configure_ipad_dock(bool enabled, bool showRecents, bool showAppLibrary)
{
    gSBCIPadDockEnabled = enabled;
    gSBCDockShowRecents = showRecents;
    gSBCDockShowAppLibrary = showAppLibrary;
    printf("[SBC][IPADDOCK] configured enabled=%d recents=%d appLibrary=%d\n",
           enabled, showRecents, showAppLibrary);
    log_user("[SBC][IPADDOCK] enabled=%d recents=%d appLibrary=%d; live selector scan will run on Apply.\n",
             enabled, showRecents, showAppLibrary);
}

static int sbc_set_bool_if_supported(uint64_t obj, const char *selector, bool value)
{
    if (!r_is_objc_ptr(obj) || !r_responds(obj, selector)) return 0;
    r_msg2(obj, selector, value ? 1 : 0, 0, 0, 0);
    printf("[SBC][IPADDOCK] %s=%d object=0x%llx\n", selector, value, obj);
    log_user("[SBC][IPADDOCK][PATH] selector=%s value=%d object=0x%llx result=sent.\n",
             selector, value, obj);
    return 1;
}

static void patch_ipad_dock_options(uint64_t iconCtrl, uint64_t mgr, uint64_t dock)
{
    int changed = 0;
    bool showRecents = gSBCIPadDockEnabled && gSBCDockShowRecents;
    bool showAppLibrary = gSBCIPadDockEnabled && gSBCDockShowAppLibrary;
    uint64_t layout = try_msg0(dock, "layout");
    uint64_t cfg = try_msg0(layout, "layoutConfiguration");
    uint64_t floating = try_msg0(mgr, "floatingDockViewController");
    if (!floating) floating = try_msg0(iconCtrl, "floatingDockViewController");
    uint64_t floatingView = try_msg0(floating, "view");

    uint64_t targets[] = { cfg, layout, dock, floating, floatingView };
    for (unsigned i = 0; i < sizeof(targets) / sizeof(targets[0]); i++) {
        uint64_t target = targets[i];
        changed += sbc_set_bool_if_supported(target, "setShowsRecentApplications:", showRecents);
        changed += sbc_set_bool_if_supported(target, "setShowsRecents:", showRecents);
        changed += sbc_set_bool_if_supported(target, "setShowsAppLibrary:", showAppLibrary);
        changed += sbc_set_bool_if_supported(target, "setShowsAppLibraryButton:", showAppLibrary);
        changed += sbc_set_bool_if_supported(target, "setLibraryButtonVisible:", showAppLibrary);
    }
    if (gSBCIPadDockEnabled && r_is_objc_ptr(floatingView)) {
        sbc_set_bool_if_supported(floatingView, "setHidden:", false);
        sbc_set_bool_if_supported(floatingView, "setUserInteractionEnabled:", true);
    }

    uint64_t layer = try_msg0(dock, "layer");
    if (r_is_objc_ptr(layer)) {
        if (r_responds(layer, "setCornerRadius:")) {
            double radius = gSBCIPadDockEnabled ? 24.0 : 0.0;
            r_msg2_main_raw(layer, "setCornerRadius:", &radius, sizeof(radius),
                            NULL, 0, NULL, 0, NULL, 0);
        }
        sbc_set_bool_if_supported(layer, "setMasksToBounds:", false);
        changed++;
    }
    printf("[SBC][IPADDOCK] option paths changed=%d floatingVC=0x%llx\n", changed, floating);
    log_user("[SBC][IPADDOCK] completed: enabled=%d supported option paths=%d floatingController=%s icons remain live/pressable.\n",
             gSBCIPadDockEnabled, changed,
             r_is_objc_ptr(floating) ? "found" : "not exposed on this iOS build");
}

static void disable_list_autofit(uint64_t listView, const char *tag)
{
    if (!r_is_objc_ptr(listView) || !r_responds(listView, "setAutomaticallyAdjustsLayoutMetricsToFit:")) return;
    r_msg2(listView, "setAutomaticallyAdjustsLayoutMetricsToFit:", 0, 0, 0, 0);
    printf("[SBC] v3: %s autoFit=NO\n", tag);
}

static uint64_t list_view_model(uint64_t listView)
{
    uint64_t model = try_msg0(listView, "model");
    if (!model) model = try_msg0(listView, "iconListModel");
    if (!model) model = try_msg0(listView, "displayedModel");
    return model;
}

static bool patch_list_model_grid(uint64_t listView, const char *tag, int cols, int rows)
{
    if (!r_is_objc_ptr(listView)) return false;

    uint64_t model = list_view_model(listView);
    if (!r_is_objc_ptr(model) || !r_responds(model, "gridSize")) {
        printf("[SBC] v3: %s missing grid model\n", tag);
        return false;
    }

    uint64_t newGrid = (((uint64_t)rows & 0xffffULL) << 16) | ((uint64_t)cols & 0xffffULL);
    uint64_t oldGrid = r_msg2(model, "gridSize", 0, 0, 0, 0) & 0xffffffffULL;

    if (r_responds(model, "setGridSize:")) {
        r_msg2(model, "setGridSize:", newGrid, 0, 0, 0);
    } else if (r_responds(model, "changeGridSize:options:")) {
        r_msg2(model, "changeGridSize:options:", newGrid, 0, 0, 0);
    } else {
        printf("[SBC] v3: %s model lacks grid setter\n", tag);
        return false;
    }

    uint64_t afterGrid = r_msg2(model, "gridSize", 0, 0, 0, 0) & 0xffffffffULL;
    printf("[SBC] v3: %s model gridSize 0x%llx -> 0x%llx\n", tag, oldGrid, afterGrid);
    return afterGrid == newGrid;
}

static void patch_dock(uint64_t iconCtrl, int dockIcons)
{
    uint64_t mgr = try_msg0(iconCtrl, "iconManager");
    if (!mgr) { printf("[SBC] dock: nil iconManager\n"); return; }
    usleep(50000);

    uint64_t dock = try_msg0(mgr, "dockListView");
    if (!dock) dock = try_msg0(iconCtrl, "dockListView");
    if (!dock) { printf("[SBC] dock: nil dockListView\n"); return; }
    disable_list_autofit(dock, "dockListView");
    usleep(50000);

    uint64_t model = try_msg0(dock, "model");
    if (!model) model = try_msg0(dock, "iconListModel");
    if (!model) model = try_msg0(dock, "displayedModel");
    if (model && r_responds(model, "gridSize") && r_responds(model, "setGridSize:")) {
        uint64_t oldGrid = r_msg2(model, "gridSize", 0, 0, 0, 0) & 0xffffffffULL;
        uint64_t newGrid = (oldGrid & 0xffff0000ULL) | (uint64_t)dockIcons;
        usleep(50000);
        r_msg2(model, "setGridSize:", newGrid, 0, 0, 0);
        printf("[SBC] dock: gridSize 0x%llx -> 0x%llx\n", oldGrid, newGrid);
    }
    usleep(50000);

    uint64_t layout = try_msg0(dock, "layout");
    if (layout) {
        usleep(50000);
        uint64_t cfg = try_msg0(layout, "layoutConfiguration");
        if (cfg && r_responds(cfg, "setNumberOfPortraitColumns:")) {
            usleep(50000);
            r_msg2(cfg, "setNumberOfPortraitColumns:", (uint64_t)dockIcons, 0, 0, 0);
            printf("[SBC] dock: portraitColumns -> %d\n", dockIcons);
        }
    }
    usleep(50000);

    if (r_responds(dock, "setNeedsLayout")) {
        uint64_t selSetNeedsLayout = r_sel("setNeedsLayout");
        r_perform_main(dock, selSetNeedsLayout, 0, false);
    }
    patch_ipad_dock_options(iconCtrl, mgr, dock);
}

static int patch_homescreen_list_models_v3(uint64_t mgr, int cols, int rows)
{
    uint64_t rootFolder = try_msg0(mgr, "rootFolderController");
    if (!r_is_objc_ptr(rootFolder)) {
        printf("[SBC] v3: nil rootFolderController\n");
        return 0;
    }

    int touched = 0;
    if (r_responds(rootFolder, "iconListViewCount") &&
        r_responds(rootFolder, "iconListViewAtIndex:")) {
        uint64_t count = r_msg2(rootFolder, "iconListViewCount", 0, 0, 0, 0);
        uint64_t limit = count < 64 ? count : 64;
        printf("[SBC] v3: iconListViewCount=%llu\n", count);
        for (uint64_t i = 0; i < limit; i++) {
            uint64_t listView = r_msg2(rootFolder, "iconListViewAtIndex:", i, 0, 0, 0);
            if (!r_is_objc_ptr(listView)) continue;

            char tag[32];
            snprintf(tag, sizeof(tag), "page[%llu]", i);
            disable_list_autofit(listView, tag);
            if (patch_list_model_grid(listView, tag, cols, rows)) touched++;
        }
    } else if (r_responds(rootFolder, "currentIconListView")) {
        uint64_t current = r_msg2(rootFolder, "currentIconListView", 0, 0, 0, 0);
        disable_list_autofit(current, "currentIconListView");
        if (patch_list_model_grid(current, "currentIconListView", cols, rows)) touched++;
    } else {
        printf("[SBC] v3: no list-view accessor path\n");
    }

    uint64_t dockListView = try_msg0(mgr, "dockListView");
    if (r_is_objc_ptr(dockListView)) {
        disable_list_autofit(dockListView, "dockListView");
    }

    printf("[SBC] v3: patched home list models=%d\n", touched);
    return touched;
}

static void patch_homescreen_grid(uint64_t iconCtrl, int cols, int rows, bool hideLabels)
{
    uint64_t mgr = try_msg0(iconCtrl, "iconManager");
    if (!mgr) { printf("[SBC] hs: nil iconManager\n"); return; }
    usleep(50000);

    uint64_t provider = try_msg0(mgr, "listLayoutProvider");
    if (provider) {
        usleep(50000);

        uint64_t loc = r_cfstr("SBIconLocationRoot");
        if (!loc) {
            printf("[SBC] hs: cfstr failed\n");
        } else if (!r_responds(provider, "layoutForIconLocation:")) {
            printf("[SBC] hs: provider lacks layoutForIconLocation:\n");
        } else {
            uint64_t layout = r_msg2(provider, "layoutForIconLocation:", loc, 0, 0, 0);
            if (!layout) {
                printf("[SBC] hs: nil layout for root\n");
            } else {
                usleep(50000);
                uint64_t cfg = try_msg0(layout, "layoutConfiguration");
                if (!cfg) {
                    printf("[SBC] hs: nil layoutConfiguration\n");
                } else if (!r_responds(cfg, "setNumberOfPortraitColumns:")) {
                    printf("[SBC] hs: cfg lacks setNumberOfPortraitColumns:\n");
                } else {
                    usleep(50000);
                    r_msg2(cfg, "setNumberOfPortraitColumns:", (uint64_t)cols, 0, 0, 0);
                    usleep(50000);
                    if (r_responds(cfg, "setNumberOfPortraitRows:"))
                        r_msg2(cfg, "setNumberOfPortraitRows:", (uint64_t)rows, 0, 0, 0);
                    usleep(50000);
                    if (r_responds(cfg, "setNumberOfLandscapeColumns:"))
                        r_msg2(cfg, "setNumberOfLandscapeColumns:", (uint64_t)rows, 0, 0, 0);
                    usleep(50000);
                    if (r_responds(cfg, "setNumberOfLandscapeRows:"))
                        r_msg2(cfg, "setNumberOfLandscapeRows:", (uint64_t)cols, 0, 0, 0);
                    printf("[SBC] hs: provider cols=%d rows=%d\n", cols, rows);

                    if (hideLabels && r_responds(cfg, "setShowsLabels:")) {
                        usleep(50000);
                        r_msg2(cfg, "setShowsLabels:", 0, 0, 0, 0);
                        printf("[SBC] hs: showsLabels=NO\n");
                    }
                }
            }
        }
    } else {
        printf("[SBC] hs: nil listLayoutProvider\n");
    }

    patch_homescreen_list_models_v3(mgr, cols, rows);
}

bool sbcustomizer_apply_in_session(int dockIcons, int hsCols, int hsRows, bool hideLabels)
{
    dockIcons = clamp(dockIcons, 4, gSBCIPadDockEnabled ? 12 : 7);
    hsCols    = clamp(hsCols,    3, 7);
    hsRows    = clamp(hsRows,    4, 8);
    printf("[SBC] === entry === dock=%d hs=%dx%d hideLabels=%d ipadDock=%d recents=%d appLibrary=%d\n",
           dockIcons, hsCols, hsRows, hideLabels, gSBCIPadDockEnabled,
           gSBCDockShowRecents, gSBCDockShowAppLibrary);

    bool ok = false;
    do {
        usleep(100000);
        uint64_t cls = r_class("SBIconController");
        if (!cls) { printf("[SBC] SBIconController missing\n"); break; }
        usleep(50000);

        uint64_t iconCtrl = r_msg2(cls, "sharedInstance", 0, 0, 0, 0);
        if (!iconCtrl) { printf("[SBC] +sharedInstance nil\n"); break; }
        printf("[SBC] iconCtrl=0x%llx\n", iconCtrl);

        patch_dock(iconCtrl, dockIcons);
        patch_homescreen_grid(iconCtrl, hsCols, hsRows, hideLabels);
        ok = true;
    } while (0);

    return ok;
}

bool sbcustomizer_apply(int dockIcons, int hsCols, int hsRows, bool hideLabels)
{
    if (init_remote_call("SpringBoard", false) != 0) {
        printf("[SBC] init_remote_call(SpringBoard) failed\n");
        return false;
    }

    bool ok = sbcustomizer_apply_in_session(dockIcons, hsCols, hsRows, hideLabels);
    destroy_remote_call();
    return ok;
}
