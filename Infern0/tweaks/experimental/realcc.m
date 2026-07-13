#import "realcc.h"
#import "../remote_objc.h"
#import "../../TaskRop/RemoteCall.h"
#import "../../LogTextView.h"

#import <Foundation/Foundation.h>
#import <stdlib.h>
#import <spawn.h>
#import <sys/wait.h>

static bool gRealccWifiDisabled = false;
static bool gRealccBtDisabled = false;

static bool realcc_kill_daemon(const char *daemonName)
{
    if (!daemonName) return false;
    pid_t pid = 0;
    const char *argv[] = { "/usr/bin/killall", daemonName, NULL };
    int ret = posix_spawn(&pid, "/usr/bin/killall", NULL, NULL, (char *const *)argv, NULL);
    if (ret == 0 && pid > 0) {
        int status = 0;
        waitpid(pid, &status, 0);
        ret = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
    }
    printf("[REALCC] killed %s: ret=%d\n", daemonName, ret);
    return ret == 0;
}

static bool realcc_write_plist_bool(NSString *path, NSString *key, BOOL value)
{
    NSMutableDictionary *plist = [NSMutableDictionary dictionaryWithContentsOfFile:path];
    if (!plist) plist = [NSMutableDictionary dictionary];
    plist[key] = @(value);
    return [plist writeToFile:path atomically:YES];
}

bool realcc_apply(bool disableWifi, bool disableBt)
{
    printf("[REALCC] apply wifi=%d bt=%d\n", disableWifi, disableBt);

    if (disableWifi) {
        BOOL ok = realcc_write_plist_bool(@"/private/var/preferences/SystemConfiguration/com.apple.wifi.plist",
                                           @"AllowEnable", NO);
        if (ok) {
            realcc_kill_daemon("wificond");
            realcc_kill_daemon("WiFiAgent");
        }
        gRealccWifiDisabled = ok;
        printf("[REALCC] wifi %s\n", ok ? "disabled" : "failed");
    }

    if (disableBt) {
        BOOL ok = realcc_write_plist_bool(@"/private/var/preferences/SystemConfiguration/com.apple.Bluetooth.plist",
                                           @"BluetoothState", NO);
        if (ok) {
            realcc_kill_daemon("bluetoothd");
        }
        gRealccBtDisabled = ok;
        printf("[REALCC] bluetooth %s\n", ok ? "disabled" : "failed");
    }

    return gRealccWifiDisabled || gRealccBtDisabled;
}

bool realcc_restore(void)
{
    printf("[REALCC] restore\n");

    if (gRealccWifiDisabled) {
        realcc_write_plist_bool(@"/private/var/preferences/SystemConfiguration/com.apple.wifi.plist",
                                @"AllowEnable", YES);
        realcc_kill_daemon("wificond");
        gRealccWifiDisabled = false;
    }

    if (gRealccBtDisabled) {
        realcc_write_plist_bool(@"/private/var/preferences/SystemConfiguration/com.apple.Bluetooth.plist",
                                @"BluetoothState", YES);
        realcc_kill_daemon("bluetoothd");
        gRealccBtDisabled = false;
    }

    return true;
}
