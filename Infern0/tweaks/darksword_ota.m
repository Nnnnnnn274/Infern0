//
//  darksword_ota.m
//

#import "darksword_ota.h"
#import "../LogTextView.h"
#import "../TaskRop/RemoteCall.h"
#import "../kexploit/kexploit_opa334.h"
#import "../kexploit/persistence.h"
#import "../kexploit/krw.h"
#import "../kexploit/offsets.h"
#import "../kexploit/vnode.h"
#import "../utils/sandbox.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <errno.h>
#import <fcntl.h>
#import <limits.h>
#import <mach-o/dyld.h>
#import <mach-o/getsect.h>
#import <notify.h>
#import <stdint.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <sys/mman.h>
#import <sys/stat.h>
#import <unistd.h>

static const char *kOTAPlistDirPath = "/private/var/db/com.apple.xpc.launchd";
static const char *kOTAPlistFileName = "disabled.plist";
static const char *kOTAPlistTempFileName = "disabled.plist.cyanide.tmp";
static const char *kOTAOriginalPlistPath = "/var/db/com.apple.xpc.launchd/disabled.plist";
static NSString * const kOTAMobileGestaltPath =
    @"/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist";
static const uint64_t kOTABufferSize = 65536;

typedef struct {
    NSString *localDir;
    uint64_t localVnode;
    uint64_t originalVData;
    bool active;
} OTADirRedirect;

static NSArray<NSString *> *ota_daemon_labels(void)
{
    return @[
        @"com.apple.mobile.softwareupdated",
        @"com.apple.OTATaskingAgent",
        @"com.apple.softwareupdateservicesd",
        @"com.apple.mobile.NRDUpdated",
    ];
}

static NSArray<NSString *> *ota_customer_catalog_preference_paths(void)
{
    return @[
        @"/var/mobile/Library/Preferences/com.apple.softwareupdateservicesd.plist",
        @"/var/mobile/Library/Preferences/com.apple.MobileSoftwareUpdate.plist",
    ];
}

static uint64_t ota_vnode_for_absolute_path(const char *path)
{
    if (!path || path[0] != '/') return 0;

    uint64_t vnode = get_rootvnode();
    if (!vnode || vnode == (uint64_t)-1) return 0;

    char copy[PATH_MAX] = {0};
    strlcpy(copy, path, sizeof(copy));
    char *save = NULL;
    for (char *part = strtok_r(copy, "/", &save);
         part;
         part = strtok_r(NULL, "/", &save)) {
        uint64_t child = vnode_get_child_vnode(vnode, part, 0);
        if (!child || child == (uint64_t)-1) {
            printf("[OTA] vnode lookup failed path=%s part=%s parent=0x%llx\n",
                   path, part, vnode);
            return 0;
        }
        vnode = child;
    }
    return vnode;
}

static bool ota_begin_launchd_dir_redirect(OTADirRedirect *redir)
{
    if (!redir) return false;
    memset(redir, 0, sizeof(*redir));

    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/ota_launchd_redirect"];
    NSError *mkdirError = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&mkdirError];
    if (mkdirError) {
        printf("[OTA] create redirect dir failed: %s\n", mkdirError.description.UTF8String);
        return false;
    }

    uint64_t localVnode = get_vnode_for_path_by_chdir(dir.UTF8String);
    if (!localVnode || localVnode == (uint64_t)-1) {
        printf("[OTA] local redirect dir vnode lookup failed: %s\n", dir.UTF8String);
        return false;
    }

    uint64_t targetVnode = ota_vnode_for_absolute_path(kOTAPlistDirPath);
    if (!targetVnode) {
        printf("[OTA] launchd plist dir vnode lookup failed: %s\n", kOTAPlistDirPath);
        return false;
    }

    uint64_t originalVData = kread64(localVnode + off_vnode_v_data);
    uint64_t targetVData = kread64(targetVnode + off_vnode_v_data);
    if (!originalVData || !targetVData) {
        printf("[OTA] redirect v_data invalid local=0x%llx target=0x%llx\n",
               originalVData, targetVData);
        return false;
    }

    kwrite64(localVnode + off_vnode_v_data, targetVData);
    redir->localDir = dir;
    redir->localVnode = localVnode;
    redir->originalVData = originalVData;
    redir->active = true;
    printf("[OTA] redirected %s -> %s\n", dir.UTF8String, kOTAPlistDirPath);
    return true;
}

static void ota_end_launchd_dir_redirect(OTADirRedirect *redir)
{
    if (!redir || !redir->active) return;
    kwrite64(redir->localVnode + off_vnode_v_data, redir->originalVData);
    redir->active = false;
    printf("[OTA] restored redirect dir %s\n", redir->localDir.UTF8String);
}

static NSMutableDictionary *ota_read_disabled_plist(NSString *plistPath)
{
    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfFile:plistPath
                                          options:0
                                            error:&readError];
    if (data.length == 0) {
        NSString *errorDesc = readError ? readError.description : @"empty";
        printf("[OTA] disabled.plist missing/unreadable; creating fresh dictionary error=%s\n",
               errorDesc.UTF8String);
        return [NSMutableDictionary dictionary];
    }

    if (data.length > kOTABufferSize) {
        printf("[OTA] disabled.plist too large len=%lu\n", (unsigned long)data.length);
        return [NSMutableDictionary dictionary];
    }

    NSError *plistError = nil;
    NSMutableDictionary *plist = [[NSPropertyListSerialization
        propertyListWithData:data
                     options:NSPropertyListMutableContainersAndLeaves
                      format:nil
                       error:&plistError] mutableCopy];
    if (![plist isKindOfClass:NSMutableDictionary.class]) {
        NSString *errorDesc = plistError ? plistError.description : @"not a dictionary";
        printf("[OTA] disabled.plist parse failed error=%s\n", errorDesc.UTF8String);
        return [NSMutableDictionary dictionary];
    }
    return plist;
}

static bool ota_write_all(int fd, const uint8_t *bytes, NSUInteger length)
{
    NSUInteger total = 0;
    while (total < length) {
        ssize_t written = write(fd, bytes + total, length - total);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) {
            printf("[OTA] write failed at %lu/%lu errno=%d\n",
                   (unsigned long)total, (unsigned long)length, errno);
            return false;
        }
        total += (NSUInteger)written;
    }
    return true;
}

static bool ota_vnode_chmod(const char *path, mode_t mode, const char *label)
{
    int ret = vnode_apfs_chmod(path, mode);
    if (ret != 0) {
        printf("[OTA] vnode chmod failed for %s path=%s mode=%o ret=%d\n",
               label, path, mode, ret);
        return false;
    }
    return true;
}

static bool ota_vnode_chown(const char *path, uid_t uid, gid_t gid, const char *label)
{
    int ret = vnode_apfs_chown(path, uid, gid);
    if (ret != 0) {
        printf("[OTA] vnode chown failed for %s path=%s uid=%u gid=%u ret=%d\n",
               label, path, uid, gid, ret);
        return false;
    }
    return true;
}

static bool ota_write_disabled_plist(NSDictionary *plist, NSString *plistPath, NSString *tempPath, NSString *dirPath)
{
    NSData *outData = [NSPropertyListSerialization dataWithPropertyList:plist
                                                                 format:NSPropertyListXMLFormat_v1_0
                                                                options:0
                                                                  error:nil];
    if (!outData || outData.length == 0 || outData.length > kOTABufferSize) {
        printf("[OTA] plist serialization failed/too large len=%lu\n", (unsigned long)outData.length);
        return false;
    }

    struct stat dirStat = {0};
    if (stat(dirPath.UTF8String, &dirStat) != 0) {
        printf("[OTA] stat disabled.plist dir failed errno=%d\n", errno);
        return false;
    }

    struct stat fileStat = {0};
    bool existed = (stat(plistPath.UTF8String, &fileStat) == 0);
    mode_t finalMode = existed ? fileStat.st_mode : (S_IFREG | 0644);
    uid_t finalUid = existed ? fileStat.st_uid : 0;
    gid_t finalGid = existed ? fileStat.st_gid : 0;

    mode_t writableDirMode = dirStat.st_mode | S_IWOTH | S_IXOTH;
    bool dirModeChanged = (writableDirMode != dirStat.st_mode);
    if (dirModeChanged &&
        !ota_vnode_chmod(dirPath.UTF8String, writableDirMode, "disabled.plist dir writable")) {
        return false;
    }

    bool ok = false;
    int fd = -1;
    do {
        unlink(tempPath.UTF8String);
        fd = open(tempPath.UTF8String, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd < 0) {
            printf("[OTA] open temp disabled.plist failed errno=%d\n", errno);
            break;
        }

        printf("[OTA] locally writing %lu bytes to temp disabled.plist\n",
               (unsigned long)outData.length);
        if (!ota_write_all(fd, outData.bytes, outData.length)) break;
        if (fsync(fd) != 0) {
            printf("[OTA] fsync temp disabled.plist failed errno=%d\n", errno);
            break;
        }
        if (close(fd) != 0) {
            printf("[OTA] close temp disabled.plist failed errno=%d\n", errno);
            fd = -1;
            break;
        }
        fd = -1;

        if (!ota_vnode_chown(tempPath.UTF8String, finalUid, finalGid, "temp disabled.plist")) break;
        if (!ota_vnode_chmod(tempPath.UTF8String, finalMode, "temp disabled.plist")) break;

        if (rename(tempPath.UTF8String, plistPath.UTF8String) != 0) {
            printf("[OTA] rename temp disabled.plist failed errno=%d\n", errno);
            break;
        }

        printf("[OTA] disabled.plist local rename ok bytes=%lu existed=%d\n",
               (unsigned long)outData.length, existed);
        ok = true;
    } while (0);

    if (fd >= 0) {
        close(fd);
    }
    if (!ok) {
        unlink(tempPath.UTF8String);
    }
    if (dirModeChanged) {
        ota_vnode_chmod(dirPath.UTF8String, dirStat.st_mode, "disabled.plist dir restore");
    }
    return ok;
}

static NSMutableDictionary *ota_read_local_preference(NSString *path)
{
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data.length == 0) return [NSMutableDictionary dictionary];

    NSError *plistError = nil;
    NSMutableDictionary *plist = [[NSPropertyListSerialization
        propertyListWithData:data
                     options:NSPropertyListMutableContainersAndLeaves
                      format:nil
                       error:&plistError] mutableCopy];
    if (![plist isKindOfClass:NSMutableDictionary.class]) {
        NSString *errorDesc = plistError ? plistError.description : @"not a dictionary";
        printf("[OTA] customer catalog pref parse failed: %s error=%s\n",
               path.UTF8String, errorDesc.UTF8String);
        return nil;
    }
    return plist;
}

static bool ota_write_local_preference(NSString *path, NSDictionary *plist)
{
    NSData *outData = [NSPropertyListSerialization dataWithPropertyList:plist
                                                                 format:NSPropertyListXMLFormat_v1_0
                                                                options:0
                                                                  error:nil];
    if (outData.length == 0) {
        printf("[OTA] customer catalog pref serialization failed: %s\n", path.UTF8String);
        return false;
    }

    BOOL ok = [outData writeToFile:path atomically:YES];
    if (ok) chmod(path.UTF8String, 0644);
    printf("[OTA] customer catalog pref write %s: %s bytes=%lu\n",
           ok ? "ok" : "failed", path.UTF8String, (unsigned long)outData.length);
    return ok;
}

static bool ota_ensure_customer_catalog_preferences(void)
{
    bool ok = true;
    bool changed = false;

    printf("[OTA] ensuring customer catalog preferences\n");
    for (NSString *path in ota_customer_catalog_preference_paths()) {
        NSMutableDictionary *plist = ota_read_local_preference(path);
        if (!plist) {
            ok = false;
            continue;
        }

        if ([plist[@"SUQueryCustomerBuilds"] isEqual:@YES]) continue;

        plist[@"SUQueryCustomerBuilds"] = @YES;
        if (!ota_write_local_preference(path, plist)) {
            ok = false;
        } else {
            changed = true;
        }
    }

    if (changed) {
        int notifyRet = notify_post("SUPreferencesChangedNotification");
        printf("[OTA] posted SUPreferencesChangedNotification ret=%d\n", notifyRet);
    }
    return ok;
}

static long ota_find_mobilegestalt_cachedata_offset(const char *mgKey)
{
    const char *mgName = "/usr/lib/libMobileGestalt.dylib";
    const struct mach_header_64 *header = NULL;

    dlopen(mgName, RTLD_LAZY | RTLD_GLOBAL);
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *imageName = _dyld_get_image_name(i);
        if (imageName && strncmp(mgName, imageName, strlen(mgName)) == 0) {
            header = (const struct mach_header_64 *)_dyld_get_image_header(i);
            break;
        }
    }
    if (!header) {
        printf("[OTA][MG] libMobileGestalt image not loaded for key %s\n", mgKey);
        return -1;
    }

    unsigned long cstringSize = 0;
    const char *cstringSection = (const char *)getsectiondata(header, "__TEXT", "__cstring", &cstringSize);
    if (!cstringSection) {
        printf("[OTA][MG] no __TEXT,__cstring for key %s\n", mgKey);
        return -1;
    }

    const char *keyPtr = NULL;
    for (unsigned long off = 0; off < cstringSize; ) {
        const char *s = cstringSection + off;
        size_t len = strnlen(s, cstringSize - off);
        if (strcmp(s, mgKey) == 0) {
            keyPtr = s;
            break;
        }
        off += len + 1;
        if (len == 0 && off >= cstringSize) break;
    }
    if (!keyPtr) {
        printf("[OTA][MG] obfuscated key not found in libMobileGestalt: %s\n", mgKey);
        return -1;
    }

    unsigned long constSize = 0;
    const uintptr_t *constSection = (const uintptr_t *)getsectiondata(header, "__AUTH_CONST", "__const", &constSize);
    if (!constSection) {
        constSection = (const uintptr_t *)getsectiondata(header, "__DATA_CONST", "__const", &constSize);
    }
    if (!constSection) {
        printf("[OTA][MG] no const section for key %s\n", mgKey);
        return -1;
    }

    for (unsigned long i = 0; i < constSize / sizeof(uintptr_t); i++) {
        if (constSection[i] == (uintptr_t)keyPtr) {
            const uint16_t *entry = (const uint16_t *)&constSection[i];
            return ((long)entry[0x9a / 2]) << 3;
        }
    }

    printf("[OTA][MG] cachedata descriptor not found for key %s\n", mgKey);
    return -1;
}

static bool ota_zero_mobilegestalt_cachedata_key(NSMutableData *cacheData, const char *key)
{
    long offset = ota_find_mobilegestalt_cachedata_offset(key);
    if (offset < 0) return false;
    if ((NSUInteger)offset + sizeof(uint64_t) > cacheData.length) {
        printf("[OTA][MG] CacheData offset out of range key=%s offset=%ld len=%lu\n",
               key, offset, (unsigned long)cacheData.length);
        return false;
    }

    uint64_t oldValue = 0;
    memcpy(&oldValue, (const uint8_t *)cacheData.bytes + offset, sizeof(oldValue));
    if (oldValue == 0) return false;

    uint64_t zero = 0;
    memcpy((uint8_t *)cacheData.mutableBytes + offset, &zero, sizeof(zero));
    printf("[OTA][MG] zeroed CacheData key=%s offset=%ld old=0x%llx\n",
           key, offset, (unsigned long long)oldValue);
    return true;
}

static bool ota_clear_internal_mobilegestalt_flags(void)
{
    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfFile:kOTAMobileGestaltPath options:0 error:&readError];
    if (data.length == 0) {
        NSString *errorDesc = readError ? readError.description : @"none";
        printf("[OTA][MG] unable to read %s error=%s\n",
               kOTAMobileGestaltPath.UTF8String, errorDesc.UTF8String);
        return false;
    }

    NSError *plistError = nil;
    NSMutableDictionary *mg = [[NSPropertyListSerialization
        propertyListWithData:data
                     options:NSPropertyListMutableContainersAndLeaves
                      format:nil
                       error:&plistError] mutableCopy];
    if (![mg isKindOfClass:NSMutableDictionary.class]) {
        NSString *errorDesc = plistError ? plistError.description : @"not a dictionary";
        printf("[OTA][MG] parse failed for %s error=%s\n",
               kOTAMobileGestaltPath.UTF8String, errorDesc.UTF8String);
        return false;
    }

    NSMutableDictionary *cacheExtra = mg[@"CacheExtra"];
    NSMutableData *cacheData = mg[@"CacheData"];
    if (![cacheExtra isKindOfClass:NSMutableDictionary.class] ||
        ![cacheData isKindOfClass:NSMutableData.class]) {
        printf("[OTA][MG] missing CacheExtra/CacheData dictionaries\n");
        return false;
    }

    bool changed = false;
    NSArray<NSString *> *internalKeys = @[
        @"LBJfwOEzExRxzlAnSuI7eg",
        @"EqrsVvjcYDdxHBiQmGhAWw",
        @"Oji6HRoPi7rH7HPdWVakuw",
    ];

    for (NSString *key in internalKeys) {
        if (cacheExtra[key]) {
            [cacheExtra removeObjectForKey:key];
            changed = true;
        }

        if (ota_zero_mobilegestalt_cachedata_key(cacheData, key.UTF8String)) {
            changed = true;
        }
    }

    if (!changed) {
        printf("[OTA][MG] internal flags already clear\n");
        return true;
    }

    NSError *writeError = nil;
    NSData *outData = [NSPropertyListSerialization dataWithPropertyList:mg
                                                                 format:NSPropertyListBinaryFormat_v1_0
                                                                options:0
                                                                  error:&writeError];
    if (outData.length == 0) {
        NSString *errorDesc = writeError ? writeError.description : @"none";
        printf("[OTA][MG] serialization failed error=%s\n", errorDesc.UTF8String);
        return false;
    }

    BOOL ok = [outData writeToFile:kOTAMobileGestaltPath atomically:YES];
    if (ok) chmod(kOTAMobileGestaltPath.UTF8String, 0644);
    printf("[OTA][MG] internal flag cleanup %s bytes=%lu\n",
           ok ? "ok" : "failed", (unsigned long)outData.length);
    return ok;
}

static bool ota_run_enable_cleanup(void)
{
    printf("[OTA] running enable cleanup for customer/internal catalog state\n");
    bool ok = ota_ensure_customer_catalog_preferences();
    ok = ota_clear_internal_mobilegestalt_flags() && ok;
    return ok;
}

static bool ota_prepare_local_root_rw(void)
{
    if (check_sandbox_var_rw() == 0) {
        printf("[OTA] app sandbox already allows /private/var read/write\n");
        return true;
    }

    if (krw_persistence_consume_launchd_root_file_token() &&
        check_sandbox_var_rw() == 0) {
        printf("[OTA] launchd root file token allows /private/var read/write\n");
        return true;
    }

    if (patch_sandbox_ext() == 0 && check_sandbox_var_rw() == 0) {
        printf("[OTA] sandbox root rw patch ok\n");
        return true;
    }
    printf("[OTA] sandbox root rw patch failed; trying extension donors\n");

    const char *donors[] = {
        "sysdiagnosed",
        "softwareupdateservicesd",
        "mobile_installation_proxy",
        "installd",
        "cfprefsd",
        NULL,
    };

    for (int i = 0; donors[i]; i++) {
        if (borrow_sandbox_ext(donors[i]) != 0) {
            continue;
        }
        if (check_sandbox_var_rw() == 0) {
            printf("[OTA] borrowed sandbox extensions from %s\n", donors[i]);
            return true;
        }
        printf("[OTA] borrowed %s extensions but /private/var rw is still denied\n",
               donors[i]);
    }

    return false;
}

static bool ota_set_local_with_launchd_krw(bool disabled)
{
    printf("[OTA] live KRW active; %s OTA without launchd RemoteCall\n",
           disabled ? "disabling" : "enabling");

    if (!ota_prepare_local_root_rw()) {
        printf("[OTA] unable to get local /private/var rw access\n");
        return false;
    }

    NSString *dirPath = @(kOTAPlistDirPath);
    NSString *plistPath = [dirPath stringByAppendingPathComponent:@(kOTAPlistFileName)];
    NSString *tempPath = [dirPath stringByAppendingPathComponent:@(kOTAPlistTempFileName)];
    NSMutableDictionary *plist = ota_read_disabled_plist(plistPath);

    int changed = 0;
    for (NSString *label in ota_daemon_labels()) {
        if (disabled) {
            if (![plist[label] boolValue]) {
                plist[label] = @YES;
                changed++;
                printf("[OTA] disabling %s\n", label.UTF8String);
            } else {
                printf("[OTA] already disabled %s\n", label.UTF8String);
            }
        } else {
            if (plist[label]) {
                [plist removeObjectForKey:label];
                changed++;
                printf("[OTA] enabling %s\n", label.UTF8String);
            } else {
                printf("[OTA] already enabled %s\n", label.UTF8String);
            }
        }
    }

    if (changed == 0) {
        printf("[OTA] no plist changes needed\n");
        return true;
    }

    return ota_write_disabled_plist(plist, plistPath, tempPath, dirPath);
}

static bool ota_disable_original_remote_call(void)
{
    printf("[ota] === DISABLING OTA ===\n");

    if (init_remote_call("launchd", false) != 0) {
        printf("[ota] failed to init remote call\n");
        return false;
    }

    bool ok = false;
    uint64_t fileBuf = do_remote_call_stable(1000, "mmap",
                                             0,
                                             kOTABufferSize,
                                             VM_PROT_READ | VM_PROT_WRITE,
                                             MAP_PRIVATE | MAP_ANON,
                                             (uint64_t)-1,
                                             0,
                                             0,
                                             0);
    if (!fileBuf) {
        printf("[ota] mmap failed\n");
        destroy_remote_call();
        return false;
    }

    uint64_t scratchRemote = remote_call_trojan_mem();
    if (!scratchRemote) {
        printf("[ota] scratch remote memory unavailable\n");
        do_remote_call_stable(1000, "munmap", fileBuf, kOTABufferSize, 0, 0, 0, 0, 0, 0);
        destroy_remote_call();
        return false;
    }

    if (!remote_write(scratchRemote, kOTAOriginalPlistPath, strlen(kOTAOriginalPlistPath) + 1)) {
        printf("[ota] failed to write read path into launchd scratch\n");
        do_remote_call_stable(1000, "munmap", fileBuf, kOTABufferSize, 0, 0, 0, 0, 0, 0);
        destroy_remote_call();
        return false;
    }
    uint64_t fd = do_remote_call_stable(1000, "open",
                                        scratchRemote,
                                        0,
                                        0,
                                        0,
                                        0,
                                        0,
                                        0,
                                        0);

    NSMutableDictionary *plist = [NSMutableDictionary dictionary];
    if ((int64_t)fd >= 0) {
        uint64_t bytesRead = do_remote_call_stable(1000, "read",
                                                   fd,
                                                   fileBuf,
                                                   kOTABufferSize,
                                                   0,
                                                   0,
                                                   0,
                                                   0,
                                                   0);
        do_remote_call_stable(1000, "close", fd, 0, 0, 0, 0, 0, 0, 0);
        if ((int64_t)bytesRead > 0) {
            uint8_t *buf = malloc((size_t)bytesRead);
            if (buf) {
                if (remote_read(fileBuf, buf, bytesRead)) {
                    NSData *data = [NSData dataWithBytes:buf length:(NSUInteger)bytesRead];

                    NSMutableDictionary *existing = [[NSPropertyListSerialization
                        propertyListWithData:data
                                     options:NSPropertyListMutableContainersAndLeaves
                                      format:nil
                                       error:nil] mutableCopy];
                    if (existing) plist = existing;
                } else {
                    printf("[ota] failed to copy disabled.plist out of launchd\n");
                }
                free(buf);
            }
        }
    }

    int added = 0;
    for (NSString *key in ota_daemon_labels()) {
        if (!plist[key]) {
            plist[key] = @YES;
            printf("[ota] adding: %s\n", key.UTF8String);
            added++;
        } else {
            printf("[ota] already present: %s\n", key.UTF8String);
        }
    }

    if (added > 0) {
        NSData *outData = [NSPropertyListSerialization dataWithPropertyList:plist
                                                                     format:NSPropertyListXMLFormat_v1_0
                                                                    options:0
                                                                      error:nil];
        if (outData.length > 0) {
            if (!remote_write(fileBuf, outData.bytes, outData.length)) {
                printf("[ota] failed to copy disabled.plist into launchd buffer\n");
                goto finish;
            }
            if (!remote_write(scratchRemote, kOTAOriginalPlistPath, strlen(kOTAOriginalPlistPath) + 1)) {
                printf("[ota] failed to write output path into launchd scratch\n");
                goto finish;
            }
            uint64_t wfd = do_remote_call_stable(1000, "open",
                                                 scratchRemote,
                                                 (uint64_t)(O_WRONLY | O_CREAT | O_TRUNC),
                                                 0644,
                                                 0,
                                                 0,
                                                 0,
                                                 0,
                                                 0);
            if ((int64_t)wfd >= 0) {
                uint64_t totalWritten = 0;
                uint64_t remaining = outData.length;
                while (remaining > 0) {
                    uint64_t written = do_remote_call_stable(1000, "write",
                                                             wfd,
                                                             fileBuf + totalWritten,
                                                             remaining,
                                                             0,
                                                             0,
                                                             0,
                                                             0,
                                                             0);
                    if ((int64_t)written <= 0) break;
                    totalWritten += written;
                    remaining -= written;
                }
                do_remote_call_stable(1000, "close", wfd, 0, 0, 0, 0, 0, 0, 0);
                printf("[ota] disabled.plist written (%llu bytes) — reboot to apply\n",
                       totalWritten);
                ok = (remaining == 0);
            } else {
                printf("[ota] disabled.plist write failed\n");
            }
        } else {
            printf("[ota] disabled.plist serialization failed\n");
        }
    } else {
        printf("[ota] all entries already present — reboot to apply if needed\n");
        ok = true;
    }

finish:
    do_remote_call_stable(1000, "munmap", fileBuf, kOTABufferSize, 0, 0, 0, 0, 0, 0);
    destroy_remote_call();
    printf("[ota] === OTA DISABLED (reboot required) ===\n");
    return ok;
}

bool darksword_ota_set_disabled(bool disabled)
{
    if (!kexploit_krw_ready()) {
        printf("[OTA] refusing plist edit: KRW is not active/recovered\n");
        log_user("[OTA] Failed: kernel recovery is not active. Run the chain first.\n");
        return false;
    }

    if (disabled && kexploit_krw_ready()) {
        bool ok = ota_set_local_with_launchd_krw(disabled);
        printf("[OTA] === DISABLE OTA result=%d reboot/userspace restart required ===\n", ok);
        return ok;
    }

    if (krw_persistence_launchd_holds_krw()) {
        bool ok = ota_set_local_with_launchd_krw(disabled);
        if (!disabled) {
            ok = ota_run_enable_cleanup() && ok;
        }
        printf("[OTA] === %s OTA result=%d reboot/userspace restart required ===\n",
               disabled ? "DISABLE" : "ENABLE", ok);
        return ok;
    }

    if (disabled) {
        return ota_disable_original_remote_call();
    }

    printf("[OTA] === %s OTA ===\n", disabled ? "DISABLING" : "ENABLING");

    OTADirRedirect redir = {0};
    if (!ota_begin_launchd_dir_redirect(&redir)) {
        printf("[OTA] launchd plist dir redirect failed\n");
        return false;
    }

    NSString *plistPath = [redir.localDir stringByAppendingPathComponent:@(kOTAPlistFileName)];
    NSString *tempPath = [redir.localDir stringByAppendingPathComponent:@(kOTAPlistTempFileName)];

    bool ok = false;

    do {
        NSMutableDictionary *plist = ota_read_disabled_plist(plistPath);
        int changed = 0;
        for (NSString *label in ota_daemon_labels()) {
            if (disabled) {
                if (![plist[label] boolValue]) {
                    plist[label] = @YES;
                    changed++;
                    printf("[OTA] disabling %s\n", label.UTF8String);
                } else {
                    printf("[OTA] already disabled %s\n", label.UTF8String);
                }
            } else {
                if (plist[label]) {
                    [plist removeObjectForKey:label];
                    changed++;
                    printf("[OTA] enabling %s\n", label.UTF8String);
                } else {
                    printf("[OTA] already enabled %s\n", label.UTF8String);
                }
            }
        }

        if (changed == 0) {
            printf("[OTA] no plist changes needed\n");
            ok = true;
            break;
        }

        ok = ota_write_disabled_plist(plist, plistPath, tempPath, redir.localDir);
    } while (0);

    ota_end_launchd_dir_redirect(&redir);

    if (!disabled) {
        ok = ota_run_enable_cleanup() && ok;
    }

    printf("[OTA] === %s OTA result=%d reboot/userspace restart required ===\n",
           disabled ? "DISABLE" : "ENABLE", ok);
    return ok;
}
