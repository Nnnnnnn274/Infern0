#import "screentime.h"
#import "darksword.h"
#import "pe/apfs.h"
#import "TaskRop/RemoteCall.h"

#import <Foundation/Foundation.h>
#import <errno.h>
#import <fcntl.h>
#import <signal.h>
#import <stdint.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <sys/mman.h>
#import <sys/stat.h>
#import <sys/sysctl.h>
#import <unistd.h>

extern int proc_name(int pid, void *buffer, uint32_t buffersize);

static void st_killproc(const char *name) {
    int mib[3] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL };
    size_t size = 0;
    if (sysctl(mib, 3, NULL, &size, NULL, 0) != 0) return;

    struct kinfo_proc *procs = malloc(size);
    if (!procs) return;

    if (sysctl(mib, 3, procs, &size, NULL, 0) != 0) {
        free(procs);
        return;
    }

    int count = (int)(size / sizeof(struct kinfo_proc));
    for (int i = 0; i < count; i++) {
        char pname[64] = {0};
        proc_name(procs[i].kp_proc.p_pid, pname, sizeof(pname));
        if (strcasecmp(pname, name) == 0) {
            printf("[ST] killing %s pid=%d\n", name, procs[i].kp_proc.p_pid);
            kill(procs[i].kp_proc.p_pid, SIGKILL);
        }
    }
    free(procs);
}

static const char *kSTPlistAbsPath   = "/private/var/db/com.apple.xpc.launchd/disabled.plist";
static const char *kSTPrefsPath      = "/var/mobile/Library/Preferences/com.apple.ScreenTimeAgent.plist";
static const char *kSTBackupPath     = "/var/mobile/Library/Preferences/com.apple.ScreenTimeAgent.plist.bak";
static const uint64_t kSTBufSize     = 65536;

static const char *kST_ScreenTimeAgent     = "com.apple.ScreenTimeAgent";
static const char *kST_UsageTrackingAgent  = "com.apple.UsageTrackingAgent";
static const char *kST_Homed               = "com.apple.homed";
static const char *kST_Familycircled       = "com.apple.familycircled";

static RemoteCall *st_create_launchd_rc(void) {
    RemoteCall *proc = [[RemoteCall alloc] initWithProcess:@"launchd" useMigFilterBypass:NO];
    if (!proc) {
        printf("[ST] failed to create RemoteCall for launchd\n");
    }
    return proc;
}

static NSMutableDictionary *st_rc_read_disabled_plist(RemoteCall *proc, uint64_t fileBuf) {
    uint64_t scratch = proc.trojanMem;
    if (!scratch) return [NSMutableDictionary dictionary];

    [proc remote_write:scratch string:kSTPlistAbsPath];
    uint64_t fd = RemoteArbCall(proc, open, scratch, (uint64_t)O_RDONLY, 0);
    if ((int64_t)fd < 0) {
        printf("[ST] launchd open disabled.plist failed — will create fresh\n");
        return [NSMutableDictionary dictionary];
    }

    uint64_t bytesRead = RemoteArbCall(proc, read, fd, fileBuf, kSTBufSize);
    RemoteArbCall(proc, close, fd);

    if ((int64_t)bytesRead <= 0 || bytesRead > kSTBufSize) {
        printf("[ST] launchd read returned %lld bytes\n", (int64_t)bytesRead);
        return [NSMutableDictionary dictionary];
    }

    uint8_t *buf = malloc((size_t)bytesRead);
    if (!buf) return [NSMutableDictionary dictionary];

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    if ([proc remoteRead:fileBuf to:buf size:bytesRead]) {
        NSData *data = [NSData dataWithBytes:buf length:(NSUInteger)bytesRead];
        NSMutableDictionary *parsed = [[NSPropertyListSerialization
            propertyListWithData:data
                         options:NSPropertyListMutableContainersAndLeaves
                          format:nil
                           error:nil] mutableCopy];
        if ([parsed isKindOfClass:NSMutableDictionary.class]) {
            result = parsed;
        }
    }
    free(buf);
    return result;
}

static bool st_rc_write_disabled_plist(RemoteCall *proc,
                                        uint64_t fileBuf,
                                        NSDictionary *plist) {
    NSData *outData = [NSPropertyListSerialization dataWithPropertyList:plist
                                                                 format:NSPropertyListXMLFormat_v1_0
                                                                options:0
                                                                  error:nil];
    if (!outData || outData.length == 0 || outData.length > kSTBufSize) {
        printf("[ST] disabled.plist serialization failed\n");
        return false;
    }

    if (![proc remote_write:fileBuf from:outData.bytes size:outData.length]) {
        printf("[ST] failed to copy plist into launchd buffer\n");
        return false;
    }

    uint64_t scratch = proc.trojanMem;
    [proc remote_write:scratch string:kSTPlistAbsPath];

    uint64_t wfd = RemoteArbCall(proc, open,
                                 scratch,
                                 (uint64_t)(O_WRONLY | O_CREAT | O_TRUNC),
                                 (uint64_t)0644);
    if ((int64_t)wfd < 0) {
        printf("[ST] launchd open for write failed\n");
        return false;
    }

    uint64_t totalWritten = 0;
    uint64_t remaining = outData.length;
    while (remaining > 0) {
        uint64_t n = RemoteArbCall(proc, write, wfd, fileBuf + totalWritten, remaining);
        if ((int64_t)n <= 0) break;
        totalWritten += n;
        remaining -= n;
    }
    RemoteArbCall(proc, close, wfd);

    if (remaining != 0) {
        printf("[ST] launchd write incomplete: %llu/%lu bytes\n",
               totalWritten, (unsigned long)outData.length);
        return false;
    }

    if (ds_is_ready()) {
        apfs_own(kSTPlistAbsPath, 0, 0);
        apfs_mod(kSTPlistAbsPath, S_IFREG | 0644);
    }

    printf("[ST] disabled.plist written %llu bytes via launchd\n", totalWritten);
    return true;
}

static bool st_patch_disabled_plist(bool killScreenTimeAgent,
                                     bool killUsageTrackingAgent,
                                     bool killHomed,
                                     bool killFamilycircled,
                                     bool disable) {
    RemoteCall *proc = st_create_launchd_rc();
    if (!proc) return false;

    bool ok = false;

    uint64_t fileBuf = RemoteArbCall(proc, mmap,
                                     0,
                                     kSTBufSize,
                                     VM_PROT_READ | VM_PROT_WRITE,
                                     MAP_PRIVATE | MAP_ANON,
                                     (uint64_t)-1,
                                     0);
    if (!fileBuf) {
        printf("[ST] mmap in launchd failed\n");
        [proc destroyRemoteCall];
        return false;
    }

    NSMutableDictionary *plist = st_rc_read_disabled_plist(proc, fileBuf);

    struct { const char *key; bool active; } entries[] = {
        { kST_ScreenTimeAgent,    killScreenTimeAgent    },
        { kST_UsageTrackingAgent, killUsageTrackingAgent },
        { kST_Homed,              killHomed              },
        { kST_Familycircled,      killFamilycircled      },
    };

    int changed = 0;
    for (size_t i = 0; i < sizeof(entries) / sizeof(entries[0]); i++) {
        if (!entries[i].active) continue;
        NSString *key = @(entries[i].key);
        if (disable) {
            if (![plist[key] boolValue]) {
                plist[key] = @YES;
                changed++;
                printf("[ST] disabling daemon %s\n", entries[i].key);
            } else {
                printf("[ST] daemon already disabled %s\n", entries[i].key);
            }
        } else {
            if (plist[key]) {
                [plist removeObjectForKey:key];
                changed++;
                printf("[ST] enabling daemon %s\n", entries[i].key);
            } else {
                printf("[ST] daemon already enabled %s\n", entries[i].key);
            }
        }
    }

    if (changed == 0) {
        printf("[ST] no plist changes needed\n");
        ok = true;
    } else {
        ok = st_rc_write_disabled_plist(proc, fileBuf, plist);
    }

    RemoteArbCall(proc, munmap, fileBuf, kSTBufSize);
    [proc destroyRemoteCall];
    return ok;
}

static void st_backup_prefs(void) {
    if (access(kSTBackupPath, F_OK) == 0) {
        printf("[ST] backup already exists at %s\n", kSTBackupPath);
        return;
    }
    if (access(kSTPrefsPath, F_OK) != 0) {
        printf("[ST] no ScreenTimeAgent prefs to back up\n");
        return;
    }
    NSError *err = nil;
    [[NSFileManager defaultManager]
        copyItemAtPath:@(kSTPrefsPath)
                toPath:@(kSTBackupPath)
                 error:&err];
    if (err) {
        printf("[ST] backup failed: %s\n", err.localizedDescription.UTF8String);
    } else {
        printf("[ST] prefs backed up to %s\n", kSTBackupPath);
    }
}

static void st_remove_prefs(void) {
    if (access(kSTPrefsPath, F_OK) != 0) return;
    NSError *err = nil;
    [[NSFileManager defaultManager] removeItemAtPath:@(kSTPrefsPath) error:&err];
    if (err) {
        printf("[ST] failed to remove prefs: %s\n", err.localizedDescription.UTF8String);
    } else {
        printf("[ST] removed ScreenTimeAgent prefs\n");
    }
}

bool screentime_disable(bool killScreenTimeAgent,
                        bool killUsageTrackingAgent,
                        bool killHomed,
                        bool killFamilycircled) {
    printf("[ST] === DISABLING SCREEN TIME ===\n");

    st_backup_prefs();
    st_remove_prefs();

    if (killScreenTimeAgent)    st_killproc("ScreenTimeAgent");
    if (killUsageTrackingAgent) st_killproc("UsageTrackingAgent");
    if (killHomed)              st_killproc("homed");
    if (killFamilycircled)      st_killproc("familycircled");

    st_remove_prefs();

    bool ok = st_patch_disabled_plist(killScreenTimeAgent,
                                      killUsageTrackingAgent,
                                      killHomed,
                                      killFamilycircled,
                                      true);

    printf("[ST] === DISABLE SCREEN TIME result=%d reboot required ===\n", ok);
    return ok;
}

bool screentime_enable(void) {
    printf("[ST] === ENABLING SCREEN TIME ===\n");

    if (access(kSTBackupPath, F_OK) == 0) {
        st_remove_prefs();
        NSError *err = nil;
        [[NSFileManager defaultManager]
            copyItemAtPath:@(kSTBackupPath)
                    toPath:@(kSTPrefsPath)
                     error:&err];
        if (err) {
            printf("[ST] failed to restore backup: %s\n", err.localizedDescription.UTF8String);
        } else {
            printf("[ST] prefs restored from backup\n");
            if (ds_is_ready()) {
                apfs_own(kSTPrefsPath, 501, 501);
                apfs_mod(kSTPrefsPath, S_IFREG | 0644);
            }
        }
    } else {
        printf("[ST] no backup found — skipping prefs restore\n");
    }

    bool ok = st_patch_disabled_plist(true, true, true, true, false);

    printf("[ST] === ENABLE SCREEN TIME result=%d reboot required ===\n", ok);
    return ok;
}
