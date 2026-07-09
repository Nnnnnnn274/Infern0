//
//  sbcustomizer.m
//

#import "sbcustomizer.h"
#import "remote_objc.h"
#import "../TaskRop/RemoteCall.h"
#import <stdio.h>
#import <unistd.h>
#import "../LogTextView.h"

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
    dockIcons = clamp(dockIcons, 4, 7);
    hsCols    = clamp(hsCols,    3, 7);
    hsRows    = clamp(hsRows,    4, 8);
    printf("[SBC] === entry === dock=%d hs=%dx%d hideLabels=%d\n",
           dockIcons, hsCols, hsRows, hideLabels);

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
