//
//  hide_home_bar.m
//  Cyanide
//

#include "hide_home_bar.h"
#include "../utils/file.h"
#import "../LogTextView.h"

static const char *kHideHomeBarMaterialKitAssets =
    "/System/Library/PrivateFrameworks/MaterialKit.framework/Assets.car";

bool hide_home_bar_apply(void)
{
    log_user("[HOME BAR] Zeroing MaterialKit Assets.car page using stable file-page zeroing.\n");
    int rc = zero_system_file_page(kHideHomeBarMaterialKitAssets, 0);
    if (rc == 0) {
        log_user("[OK] Home bar asset page zeroed. Respring to refresh SpringBoard assets.\n");
        return true;
    }

    log_user("[FAIL] Hide Home Bar did not zero the MaterialKit asset page.\n");
    return false;
}

bool hide_home_bar_restore(void)
{
    log_user("[HOME BAR] Restore queued. Respring to reload the stock home bar assets.\n");
    return true;
}
