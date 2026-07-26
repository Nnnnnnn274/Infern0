#import "ota.h"
#import "darksword.h"
#import "pe/apfs.h"
#import "TaskRop/RemoteCall.h"

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <errno.h>
#import <fcntl.h>
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

static const char *kOTAPlistAbsPath = "/private/var/db/com.apple.xpc.launchd/disabled.plist";
static NSString * const kOTAMobileGestaltPath =
    @"/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist";
static const uint64_t kOTABufSize = 65536;

static NSArray<NSString *> *ota_daemon_labels(void) {
    return @[
        @"com.apple.mobile.softwareupdated",
        @"com.apple.OTATaskingAgent",
        @"com.apple.softwareupdateservicesd",
        @"com.apple.mobile.NRDUpdated",
    ];
}

static NSArray<NSString *> *ota_catalog_pref_paths(void) {
    return @[
        @"/var/mobile/Library/Preferences/com.apple.softwareupdateservicesd.plist",
        @"/var/mobile/Library/Preferences/com.apple.MobileSoftwareUpdate.plist",
    ];
}

static bool ota_write_catalog_pref(NSString *path, NSDictionary *plist) {
    NSData *outData = [NSPropertyListSerialization dataWithPropertyList:plist
                                                                 format:NSPropertyListXMLFormat_v1_0
                                                                options:0
                                                                  error:nil];
    if (outData.length == 0) return false;
    BOOL ok = [outData writeToFile:path atomically:YES];
    if (ok) chmod(path.UTF8String, 0644);
    return ok;
}

static bool ota_ensure_catalog_preferences(void) {
    bool ok = true;
    bool changed = false;
    for (NSString *path in ota_catalog_pref_paths()) {
        NSData *data = [NSData dataWithContentsOfFile:path];
        NSMutableDictionary *plist = nil;
        if (data.length > 0) {
            plist = [[NSPropertyListSerialization
                propertyListWithData:data
                             options:NSPropertyListMutableContainersAndLeaves
                              format:nil
                               error:nil] mutableCopy];
        }
        if (![plist isKindOfClass:NSMutableDictionary.class]) {
            plist = [NSMutableDictionary dictionary];
        }
        if ([plist[@"SUQueryCustomerBuilds"] isEqual:@YES]) continue;
        plist[@"SUQueryCustomerBuilds"] = @YES;
        if (!ota_write_catalog_pref(path, plist)) {
            ok = false;
        } else {
            changed = true;
        }
    }
    if (changed) notify_post("SUPreferencesChangedNotification");
    return ok;
}

static long ota_find_mobilegestalt_cachedata_offset(const char *mgKey) {
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
    if (!header) return -1;

    unsigned long cstringSize = 0;
    const char *cstringSection = (const char *)getsectiondata(header, "__TEXT", "__cstring", &cstringSize);
    if (!cstringSection) return -1;

    const char *keyPtr = NULL;
    for (unsigned long off = 0; off < cstringSize; ) {
        const char *s = cstringSection + off;
        size_t len = strnlen(s, cstringSize - off);
        if (strcmp(s, mgKey) == 0) { keyPtr = s; break; }
        off += len + 1;
        if (len == 0 && off >= cstringSize) break;
    }
    if (!keyPtr) return -1;

    unsigned long constSize = 0;
    const uintptr_t *constSection = (const uintptr_t *)getsectiondata(header, "__AUTH_CONST", "__const", &constSize);
    if (!constSection) {
        constSection = (const uintptr_t *)getsectiondata(header, "__DATA_CONST", "__const", &constSize);
    }
    if (!constSection) return -1;

    for (unsigned long i = 0; i < constSize / sizeof(uintptr_t); i++) {
        if (constSection[i] == (uintptr_t)keyPtr) {
            const uint16_t *entry = (const uint16_t *)&constSection[i];
            return ((long)entry[0x9a / 2]) << 3;
        }
    }
    return -1;
}

static bool ota_zero_mobilegestalt_cachedata_key(NSMutableData *cacheData, const char *key) {
    long offset = ota_find_mobilegestalt_cachedata_offset(key);
    if (offset < 0) return false;
    if ((NSUInteger)offset + sizeof(uint64_t) > cacheData.length) return false;

    uint64_t oldValue = 0;
    memcpy(&oldValue, (const uint8_t *)cacheData.bytes + offset, sizeof(oldValue));
    if (oldValue == 0) return false;

    uint64_t zero = 0;
    memcpy((uint8_t *)cacheData.mutableBytes + offset, &zero, sizeof(zero));
    printf("[OTA][MG] zeroed CacheData key=%s offset=%ld old=0x%llx\n",
           key, offset, (unsigned long long)oldValue);
    return true;
}

static bool ota_clear_mobilegestalt_internal_flags(void) {
    NSData *data = [NSData dataWithContentsOfFile:kOTAMobileGestaltPath options:0 error:nil];
    if (data.length == 0) {
        printf("[OTA][MG] unable to read MobileGestalt plist\n");
        return false;
    }

    NSMutableDictionary *mg = [[NSPropertyListSerialization
        propertyListWithData:data
                     options:NSPropertyListMutableContainersAndLeaves
                      format:nil
                       error:nil] mutableCopy];
    if (![mg isKindOfClass:NSMutableDictionary.class]) {
        printf("[OTA][MG] MobileGestalt plist parse failed\n");
        return false;
    }

    NSMutableDictionary *cacheExtra = mg[@"CacheExtra"];
    NSMutableData *cacheData = mg[@"CacheData"];
    if (![cacheExtra isKindOfClass:NSMutableDictionary.class] ||
        ![cacheData isKindOfClass:NSMutableData.class]) {
        printf("[OTA][MG] missing CacheExtra/CacheData\n");
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

    NSData *outData = [NSPropertyListSerialization dataWithPropertyList:mg
                                                                 format:NSPropertyListBinaryFormat_v1_0
                                                                options:0
                                                                  error:nil];
    if (outData.length == 0) {
        printf("[OTA][MG] serialization failed\n");
        return false;
    }

    BOOL ok = [outData writeToFile:kOTAMobileGestaltPath atomically:YES];
    if (ok) chmod(kOTAMobileGestaltPath.UTF8String, 0644);
    printf("[OTA][MG] internal flag cleanup %s bytes=%lu\n",
           ok ? "ok" : "failed", (unsigned long)outData.length);
    return ok;
}

static bool ota_run_enable_cleanup(void) {
    bool ok = ota_ensure_catalog_preferences();
    ok = ota_clear_mobilegestalt_internal_flags() && ok;
    return ok;
}

static RemoteCall *ota_create_launchd_rc(void) {
    RemoteCall *proc = [[RemoteCall alloc] initWithProcess:@"launchd" useMigFilterBypass:NO];
    if (!proc) {
        printf("[OTA] failed to create RemoteCall for launchd\n");
    }
    return proc;
}

static NSMutableDictionary *ota_rc_read_plist(RemoteCall *proc, uint64_t fileBuf) {
    uint64_t scratch = proc.trojanMem;
    if (!scratch) return [NSMutableDictionary dictionary];

    [proc remote_write:scratch string:kOTAPlistAbsPath];
    uint64_t fd = RemoteArbCall(proc, open, scratch, (uint64_t)O_RDONLY, 0);
    if ((int64_t)fd < 0) {
        printf("[OTA] launchd open disabled.plist failed — will create fresh\n");
        return [NSMutableDictionary dictionary];
    }

    uint64_t bytesRead = RemoteArbCall(proc, read, fd, fileBuf, kOTABufSize);
    RemoteArbCall(proc, close, fd);

    if ((int64_t)bytesRead <= 0 || bytesRead > kOTABufSize) {
        printf("[OTA] launchd read returned %lld bytes\n", (int64_t)bytesRead);
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

static bool ota_rc_write_plist(RemoteCall *proc,
                                uint64_t fileBuf,
                                NSDictionary *plist) {
    NSData *outData = [NSPropertyListSerialization dataWithPropertyList:plist
                                                                 format:NSPropertyListXMLFormat_v1_0
                                                                options:0
                                                                  error:nil];
    if (!outData || outData.length == 0 || outData.length > kOTABufSize) {
        printf("[OTA] plist serialization failed\n");
        return false;
    }

    if (![proc remote_write:fileBuf from:outData.bytes size:outData.length]) {
        printf("[OTA] failed to copy plist into launchd buffer\n");
        return false;
    }

    uint64_t scratch = proc.trojanMem;
    [proc remote_write:scratch string:kOTAPlistAbsPath];

    uint64_t wfd = RemoteArbCall(proc, open,
                                 scratch,
                                 (uint64_t)(O_WRONLY | O_CREAT | O_TRUNC),
                                 (uint64_t)0644);
    if ((int64_t)wfd < 0) {
        printf("[OTA] launchd open for write failed\n");
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
        printf("[OTA] launchd write incomplete: %llu/%lu bytes\n",
               totalWritten, (unsigned long)outData.length);
        return false;
    }

    if (ds_is_ready()) {
        apfs_own(kOTAPlistAbsPath, 0, 0);
        apfs_mod(kOTAPlistAbsPath, S_IFREG | 0644);
    }

    printf("[OTA] disabled.plist written %llu bytes via launchd\n", totalWritten);
    return true;
}

static bool ota_apply_via_launchd_rc(bool disabled) {
    printf("[OTA] === %s OTA via launchd RemoteCall ===\n",
           disabled ? "DISABLING" : "ENABLING");

    RemoteCall *proc = ota_create_launchd_rc();
    if (!proc) return false;

    bool ok = false;

    uint64_t fileBuf = RemoteArbCall(proc, mmap,
                                     0,
                                     kOTABufSize,
                                     VM_PROT_READ | VM_PROT_WRITE,
                                     MAP_PRIVATE | MAP_ANON,
                                     (uint64_t)-1,
                                     0);
    if (!fileBuf) {
        printf("[OTA] mmap in launchd failed\n");
        [proc destroyRemoteCall];
        return false;
    }

    NSMutableDictionary *plist = ota_rc_read_plist(proc, fileBuf);

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
        printf("[OTA] no changes needed\n");
        ok = true;
    } else {
        ok = ota_rc_write_plist(proc, fileBuf, plist);
    }

    RemoteArbCall(proc, munmap, fileBuf, kOTABufSize);
    [proc destroyRemoteCall];

    if (!disabled && ok) {
        ok = ota_run_enable_cleanup() && ok;
    }

    printf("[OTA] === %s OTA result=%d reboot required ===\n",
           disabled ? "DISABLE" : "ENABLE", ok);
    return ok;
}

bool ota_set_disabled(bool disabled) {
    return ota_apply_via_launchd_rc(disabled);
}
