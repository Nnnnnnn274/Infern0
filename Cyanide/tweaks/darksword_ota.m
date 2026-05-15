//
//  darksword_ota.m
//

#import "darksword_ota.h"
#import "remote_objc.h"
#import "../TaskRop/RemoteCall.h"
#import "../LogTextView.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <fcntl.h>
#import <mach/vm_prot.h>
#import <mach-o/dyld.h>
#import <mach-o/getsect.h>
#import <notify.h>
#import <stdint.h>
#import <stdio.h>
#import <string.h>
#import <sys/mman.h>
#import <sys/stat.h>
#import <unistd.h>

static const char *kOTAPlistPath = "/var/db/com.apple.xpc.launchd/disabled.plist";
static NSString * const kOTAMobileGestaltPath =
    @"/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist";
static const uint64_t kOTABufferSize = 65536;

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

static uint64_t ota_remote_open(uint64_t remotePath, int flags, mode_t mode)
{
    return r_dlsym_call(1000, "open",
                        remotePath, (uint64_t)flags, (uint64_t)mode,
                        0, 0, 0, 0, 0);
}

static NSMutableDictionary *ota_read_disabled_plist(uint64_t remotePath, uint64_t fileBuf)
{
    NSMutableDictionary *plist = [NSMutableDictionary dictionary];

    uint64_t fd = ota_remote_open(remotePath, O_RDONLY, 0);
    if ((int64_t)fd < 0) {
        printf("[OTA] disabled.plist missing/unreadable; creating fresh dictionary\n");
        return plist;
    }

    uint64_t bytesRead = r_dlsym_call(1000, "read",
                                      fd, fileBuf, kOTABufferSize,
                                      0, 0, 0, 0, 0);
    r_dlsym_call(1000, "close", fd, 0, 0, 0, 0, 0, 0, 0);
    if ((int64_t)bytesRead <= 0 || bytesRead > kOTABufferSize) {
        printf("[OTA] disabled.plist read empty/invalid bytes=%lld\n", (long long)bytesRead);
        return plist;
    }

    uint8_t *buf = malloc((size_t)bytesRead);
    if (!buf) return plist;
    bool copied = remote_read(fileBuf, buf, bytesRead);
    if (copied) {
        NSData *data = [NSData dataWithBytes:buf length:(NSUInteger)bytesRead];
        NSMutableDictionary *existing = [[NSPropertyListSerialization
            propertyListWithData:data
                         options:NSPropertyListMutableContainersAndLeaves
                          format:nil
                           error:nil] mutableCopy];
        if (existing) plist = existing;
    }
    free(buf);
    return plist;
}

static bool ota_write_disabled_plist(uint64_t remotePath, uint64_t fileBuf, NSDictionary *plist)
{
    NSData *outData = [NSPropertyListSerialization dataWithPropertyList:plist
                                                                 format:NSPropertyListXMLFormat_v1_0
                                                                options:0
                                                                  error:nil];
    if (!outData || outData.length == 0 || outData.length > kOTABufferSize) {
        printf("[OTA] plist serialization failed/too large len=%lu\n", (unsigned long)outData.length);
        return false;
    }

    if (!remote_write(fileBuf, outData.bytes, outData.length)) {
        printf("[OTA] remote_write plist failed\n");
        return false;
    }

    uint64_t fd = ota_remote_open(remotePath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if ((int64_t)fd < 0) {
        printf("[OTA] open disabled.plist for write failed fd=%lld\n", (long long)fd);
        return false;
    }

    uint64_t totalWritten = 0;
    uint64_t remaining = outData.length;
    while (remaining > 0) {
        uint64_t written = r_dlsym_call(1000, "write",
                                        fd, fileBuf + totalWritten, remaining,
                                        0, 0, 0, 0, 0);
        if ((int64_t)written <= 0) break;
        totalWritten += written;
        remaining -= written;
    }

    uint64_t chmodRet = r_dlsym_call(1000, "fchmod", fd, 0644, 0, 0, 0, 0, 0, 0);
    uint64_t syncRet = r_dlsym_call(1000, "fsync", fd, 0, 0, 0, 0, 0, 0, 0);
    r_dlsym_call(1000, "close", fd, 0, 0, 0, 0, 0, 0, 0);

    printf("[OTA] disabled.plist written %llu/%lu bytes fchmod=%lld fsync=%lld\n",
           totalWritten, (unsigned long)outData.length,
           (long long)chmodRet, (long long)syncRet);
    return totalWritten == outData.length;
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

bool darksword_ota_set_disabled(bool disabled)
{
    printf("[OTA] === %s OTA ===\n", disabled ? "DISABLING" : "ENABLING");

    if (init_remote_call("launchd", false) != 0) {
        printf("[OTA] init_remote_call(launchd) failed\n");
        return false;
    }

    bool ok = false;
    uint64_t fileBuf = 0;
    uint64_t remotePath = 0;

    do {
        fileBuf = r_dlsym_call(1000, "mmap",
                               0, kOTABufferSize, VM_PROT_READ | VM_PROT_WRITE,
                               MAP_PRIVATE | MAP_ANON, (uint64_t)-1, 0, 0, 0);
        if (!fileBuf) {
            printf("[OTA] mmap failed\n");
            break;
        }

        remotePath = r_alloc_str(kOTAPlistPath);
        if (!remotePath) {
            printf("[OTA] remote path allocation failed\n");
            break;
        }

        NSMutableDictionary *plist = ota_read_disabled_plist(remotePath, fileBuf);
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

        ok = ota_write_disabled_plist(remotePath, fileBuf, plist);
    } while (0);

    if (remotePath) r_free(remotePath);
    if (fileBuf) {
        r_dlsym_call(1000, "munmap", fileBuf, kOTABufferSize, 0, 0, 0, 0, 0, 0);
    }
    destroy_remote_call();

    if (!disabled) {
        ok = ota_run_enable_cleanup() && ok;
    }

    printf("[OTA] === %s OTA result=%d reboot/userspace restart required ===\n",
           disabled ? "DISABLE" : "ENABLE", ok);
    return ok;
}
