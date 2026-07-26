//
//  ipadecryptor.m
//  Local installed-app FairPlay dump for Infern0.
//
//  The process/VM-map architecture is adapted from rooootdev/lara's
//  AGPL-3.0 App Decrypt implementation. Infern0 and Lara are both AGPL-3.0.
//  This implementation is independently integrated with Infern0's kutils,
//  VM mapper, logging, UI lifecycle, and atomic archive pipeline.
//

#import "ipadecryptor.h"
#import "../../LogTextView.h"
#import "../../TaskRop/VM.h"
#import "../../kexploit/kexploit_opa334.h"
#import "../../kexploit/kutils.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <libkern/OSByteOrder.h>
#import <mach/mach.h>
#import <mach-o/fat.h>
#import <mach-o/loader.h>
#import <objc/message.h>
#import <sys/stat.h>
#import <unistd.h>

extern void vm_map_iterate_entries(uint64_t vm_map_ptr,
    void (^itBlock)(uint64_t start, uint64_t end, uint64_t entry, BOOL *stop));
extern kern_return_t mach_vm_deallocate(task_t task, mach_vm_address_t address,
                                         mach_vm_size_t size);

static NSString * const kIPADecryptorKeyBundleID = @"bundleID";
static NSString * const kIPADecryptorKeyName = @"name";
static NSString * const kIPADecryptorKeyBundlePath = @"bundlePath";

typedef struct {
    bool isMachO;
    bool is64;
    bool hasEncryptionInfo;
    bool hasUUID;
    uint32_t cryptid;
    uint64_t cryptoff;
    uint64_t cryptsize;
    uint64_t encryptionCommandOffset;
    uint64_t textFileoff;
    uint64_t textVMAddr;
    uint64_t sliceOffset;
    uint64_t sliceSize;
    uint8_t uuid[16];
} IPADecryptorMachOInfo;

static NSString *ipadec_nonempty_string(id value)
{
    return [value isKindOfClass:NSString.class] && [(NSString *)value length] > 0
        ? (NSString *)value : nil;
}

static id ipadec_perform0(id target, SEL selector)
{
    if (!target || !selector || ![target respondsToSelector:selector]) return nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    return [target performSelector:selector];
#pragma clang diagnostic pop
}

static void ipadec_clear_legacy_account_state(void)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray<NSString *> *keys = @[
            @"cyanide.ipadecryptor.apple.email",
            @"cyanide.ipadecryptor.apple.passwordToken",
            @"cyanide.ipadecryptor.apple.dsid",
            @"cyanide.ipadecryptor.apple.storeFront",
            @"cyanide.ipadecryptor.apple.pod",
            @"cyanide.ipadecryptor.apple.name",
            @"cyanide.ipadecryptor.apple.guid"
        ];
        NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
        BOOL removed = NO;
        for (NSString *key in keys) {
            if ([d objectForKey:key] != nil) {
                [d removeObjectForKey:key];
                removed = YES;
            }
        }
        if (removed) {
            [d synchronize];
            log_user("[IPADEC][MIGRATION] Removed legacy App Store account tokens; local installed-app mode stores no Apple credentials.\n");
        }
    });
}

static NSString *ipadec_bundle_path_from_proxy(id proxy)
{
    NSURL *url = ipadec_perform0(proxy, @selector(bundleURL));
    if ([url isKindOfClass:NSURL.class] && url.path.length > 0) return url.path;
    url = ipadec_perform0(proxy, @selector(bundleContainerURL));
    return [url isKindOfClass:NSURL.class] ? url.path : nil;
}

static NSDictionary<NSString *, NSString *> *ipadec_app_entry(NSString *bundleID,
                                                               NSString *name,
                                                               NSString *path)
{
    if (bundleID.length == 0 || path.length == 0) return nil;
    return @{
        kIPADecryptorKeyBundleID: bundleID,
        kIPADecryptorKeyName: name.length > 0 ? name : bundleID,
        kIPADecryptorKeyBundlePath: path
    };
}

static NSArray<NSDictionary<NSString *, NSString *> *> *ipadec_apps_from_launchservices(void)
{
    Class cls = NSClassFromString(@"LSApplicationWorkspace");
    id workspace = ipadec_perform0(cls, @selector(defaultWorkspace));
    NSArray *proxies = ipadec_perform0(workspace, @selector(allApplications));
    if (![proxies isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *apps = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (id proxy in proxies) {
        NSString *bundleID = ipadec_nonempty_string(ipadec_perform0(proxy, @selector(bundleIdentifier)));
        NSString *path = ipadec_bundle_path_from_proxy(proxy);
        if (bundleID.length == 0 || path.length == 0 || [seen containsObject:bundleID]) continue;
        if ([path rangeOfString:@"/Bundle/Application/"].location == NSNotFound &&
            [path rangeOfString:@"/Containers/Bundle/Application/"].location == NSNotFound) continue;
        NSString *name = ipadec_nonempty_string(ipadec_perform0(proxy, @selector(localizedName)))
            ?: ipadec_nonempty_string(ipadec_perform0(proxy, @selector(itemName)))
            ?: bundleID;
        NSDictionary *entry = ipadec_app_entry(bundleID, name, path);
        if (entry) { [apps addObject:entry]; [seen addObject:bundleID]; }
    }
    return apps;
}

static NSArray<NSDictionary<NSString *, NSString *> *> *ipadec_apps_from_bundle_scan(void)
{
    NSString *root = @"/var/containers/Bundle/Application";
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableArray *apps = [NSMutableArray array];
    for (NSString *container in [fm contentsOfDirectoryAtPath:root error:nil] ?: @[]) {
        NSString *containerPath = [root stringByAppendingPathComponent:container];
        for (NSString *item in [fm contentsOfDirectoryAtPath:containerPath error:nil] ?: @[]) {
            if (![item.pathExtension.lowercaseString isEqualToString:@"app"]) continue;
            NSString *path = [containerPath stringByAppendingPathComponent:item];
            NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
                [path stringByAppendingPathComponent:@"Info.plist"]];
            NSString *bundleID = ipadec_nonempty_string(info[@"CFBundleIdentifier"]);
            NSString *name = ipadec_nonempty_string(info[@"CFBundleDisplayName"])
                ?: ipadec_nonempty_string(info[@"CFBundleName"])
                ?: bundleID;
            NSDictionary *entry = ipadec_app_entry(bundleID, name, path);
            if (entry) [apps addObject:entry];
        }
    }
    return apps;
}

NSArray<NSDictionary<NSString *, NSString *> *> *ipadecryptor_installed_apps(void)
{
    ipadec_clear_legacy_account_state();
    NSMutableDictionary *byID = [NSMutableDictionary dictionary];
    for (NSDictionary *entry in ipadec_apps_from_launchservices())
        if ([entry[kIPADecryptorKeyBundleID] length] > 0) byID[entry[kIPADecryptorKeyBundleID]] = entry;
    for (NSDictionary *entry in ipadec_apps_from_bundle_scan())
        if ([entry[kIPADecryptorKeyBundleID] length] > 0 && !byID[entry[kIPADecryptorKeyBundleID]])
            byID[entry[kIPADecryptorKeyBundleID]] = entry;
    return [byID.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[kIPADecryptorKeyName] localizedCaseInsensitiveCompare:b[kIPADecryptorKeyName]];
    }] ?: @[];
}

static NSDictionary<NSString *, NSString *> *ipadec_lookup_app(NSString *bundleID)
{
    for (NSDictionary *entry in ipadecryptor_installed_apps())
        if ([entry[kIPADecryptorKeyBundleID] isEqualToString:bundleID]) return entry;
    return nil;
}

NSString *ipadecryptor_display_name_for_bundle(NSString *bundleID)
{
    NSDictionary *entry = ipadec_lookup_app(bundleID);
    NSString *name = entry[kIPADecryptorKeyName];
    return name.length > 0 ? [NSString stringWithFormat:@"%@ (%@)", name, bundleID]
                           : (bundleID.length > 0 ? bundleID : @"None selected");
}

NSString *ipadecryptor_default_output_directory(void)
{
    NSString *base = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                          NSUserDomainMask, YES).firstObject
        ?: NSTemporaryDirectory();
    NSString *dir = [base stringByAppendingPathComponent:@"DecryptedIPAs"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir
                            withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

static NSString *ipadec_executable_name(NSString *bundlePath)
{
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
        [bundlePath stringByAppendingPathComponent:@"Info.plist"]];
    return ipadec_nonempty_string(info[@"CFBundleExecutable"])
        ?: bundlePath.lastPathComponent.stringByDeletingPathExtension;
}

static bool ipadec_range_ok(NSUInteger length, uint64_t offset, uint64_t size)
{
    return offset <= length && size <= length - offset;
}

static bool ipadec_parse_thin(const uint8_t *bytes, NSUInteger length,
                              uint64_t sliceOffset, uint64_t sliceSize,
                              IPADecryptorMachOInfo *out)
{
    if (!out || !ipadec_range_ok(length, sliceOffset, sizeof(uint32_t))) return false;
    uint32_t magic = *(const uint32_t *)(bytes + sliceOffset);
    bool is64 = magic == MH_MAGIC_64;
    if (!is64 && magic != MH_MAGIC) return false;
    uint64_t headerSize = is64 ? sizeof(struct mach_header_64) : sizeof(struct mach_header);
    if (!ipadec_range_ok(length, sliceOffset, headerSize)) return false;
    uint32_t ncmds = is64
        ? ((const struct mach_header_64 *)(bytes + sliceOffset))->ncmds
        : ((const struct mach_header *)(bytes + sliceOffset))->ncmds;
    uint64_t cursor = sliceOffset + headerSize;
    IPADecryptorMachOInfo info = { .isMachO = true, .is64 = is64,
        .sliceOffset = sliceOffset, .sliceSize = sliceSize };
    bool foundText = false;
    for (uint32_t i = 0; i < ncmds; i++) {
        if (!ipadec_range_ok(length, cursor, sizeof(struct load_command))) return false;
        const struct load_command *lc = (const struct load_command *)(bytes + cursor);
        if (lc->cmdsize < sizeof(*lc) || !ipadec_range_ok(length, cursor, lc->cmdsize)) return false;
        if (lc->cmd == LC_UUID && lc->cmdsize >= sizeof(struct uuid_command)) {
            memcpy(info.uuid, ((const struct uuid_command *)lc)->uuid, sizeof(info.uuid));
            info.hasUUID = true;
        } else if (is64 && lc->cmd == LC_ENCRYPTION_INFO_64 &&
                   lc->cmdsize >= sizeof(struct encryption_info_command_64)) {
            const struct encryption_info_command_64 *enc = (const void *)lc;
            info.hasEncryptionInfo = true;
            info.cryptid = enc->cryptid;
            info.cryptoff = enc->cryptoff;
            info.cryptsize = enc->cryptsize;
            info.encryptionCommandOffset = cursor;
        } else if (!is64 && lc->cmd == LC_ENCRYPTION_INFO &&
                   lc->cmdsize >= sizeof(struct encryption_info_command)) {
            const struct encryption_info_command *enc = (const void *)lc;
            info.hasEncryptionInfo = true;
            info.cryptid = enc->cryptid;
            info.cryptoff = enc->cryptoff;
            info.cryptsize = enc->cryptsize;
            info.encryptionCommandOffset = cursor;
        } else if (is64 && lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg = (const void *)lc;
            if (strncmp(seg->segname, "__TEXT", 16) == 0) {
                info.textFileoff = seg->fileoff; info.textVMAddr = seg->vmaddr; foundText = true;
            }
        } else if (!is64 && lc->cmd == LC_SEGMENT) {
            const struct segment_command *seg = (const void *)lc;
            if (strncmp(seg->segname, "__TEXT", 16) == 0) {
                info.textFileoff = seg->fileoff; info.textVMAddr = seg->vmaddr; foundText = true;
            }
        }
        cursor += lc->cmdsize;
    }
    if (!foundText) return false;
    *out = info;
    return true;
}

static bool ipadec_parse_macho_data(NSData *data, IPADecryptorMachOInfo *out)
{
    if (!out || data.length < sizeof(uint32_t)) return false;
    const uint8_t *bytes = data.bytes;
    uint32_t magic = *(const uint32_t *)bytes;
    if (magic == MH_MAGIC || magic == MH_MAGIC_64)
        return ipadec_parse_thin(bytes, data.length, 0, data.length, out);
    if (magic != FAT_MAGIC && magic != FAT_CIGAM &&
        magic != FAT_MAGIC_64 && magic != FAT_CIGAM_64) return false;
    bool swap = magic == FAT_CIGAM || magic == FAT_CIGAM_64;
    bool fat64 = magic == FAT_MAGIC_64 || magic == FAT_CIGAM_64;
    const struct fat_header *header = (const void *)bytes;
    uint32_t count = swap ? OSSwapInt32(header->nfat_arch) : header->nfat_arch;
    if (count > 32) return false;
    uint64_t cursor = sizeof(*header);
    for (uint32_t i = 0; i < count; i++) {
        cpu_type_t cpu = 0; uint64_t offset = 0, size = 0;
        if (fat64) {
            if (!ipadec_range_ok(data.length, cursor, sizeof(struct fat_arch_64))) return false;
            const struct fat_arch_64 *arch = (const void *)(bytes + cursor);
            cpu = swap ? (cpu_type_t)OSSwapInt32(arch->cputype) : arch->cputype;
            offset = swap ? OSSwapInt64(arch->offset) : arch->offset;
            size = swap ? OSSwapInt64(arch->size) : arch->size;
            cursor += sizeof(*arch);
        } else {
            if (!ipadec_range_ok(data.length, cursor, sizeof(struct fat_arch))) return false;
            const struct fat_arch *arch = (const void *)(bytes + cursor);
            cpu = swap ? (cpu_type_t)OSSwapInt32(arch->cputype) : arch->cputype;
            offset = swap ? OSSwapInt32(arch->offset) : arch->offset;
            size = swap ? OSSwapInt32(arch->size) : arch->size;
            cursor += sizeof(*arch);
        }
        if ((cpu & CPU_ARCH_ABI64) && ipadec_range_ok(data.length, offset, size))
            return ipadec_parse_thin(bytes, data.length, offset, size, out);
    }
    return false;
}

static IPADecryptorMachOInfo ipadec_info_for_path(NSString *path)
{
    IPADecryptorMachOInfo info = {0};
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if (data) (void)ipadec_parse_macho_data(data, &info);
    return info;
}

static bool ipadec_launch_bundle(NSString *bundleID)
{
    __block BOOL launched = NO;
    void (^launchBlock)(void) = ^{
        Class cls = NSClassFromString(@"LSApplicationWorkspace");
        id ws = ipadec_perform0(cls, @selector(defaultWorkspace));
        SEL selector = NSSelectorFromString(@"openApplicationWithBundleID:");
        if (ws && [ws respondsToSelector:selector])
            launched = ((BOOL (*)(id, SEL, id))objc_msgSend)(ws, selector, bundleID);
    };
    if (NSThread.isMainThread) launchBlock(); else dispatch_sync(dispatch_get_main_queue(), launchBlock);
    return launched;
}

static uint64_t ipadec_find_process(NSString *executable)
{
    NSArray<NSString *> *candidates = @[
        executable ?: @"",
        executable.stringByDeletingPathExtension ?: @"",
        executable.length > 15 ? [executable substringToIndex:15] : (executable ?: @"")
    ];
    for (NSString *candidate in candidates) {
        if (candidate.length == 0) continue;
        uint64_t proc = proc_find_by_name(candidate.UTF8String);
        if (proc) return proc;
    }
    return 0;
}

static bool ipadec_uuid_from_loaded_header(const uint8_t *bytes, size_t length, uint8_t uuid[16])
{
    if (!bytes || length < sizeof(uint32_t)) return false;
    uint32_t magic = *(const uint32_t *)bytes;
    bool is64 = magic == MH_MAGIC_64;
    if (!is64 && magic != MH_MAGIC) return false;
    size_t headerSize = is64 ? sizeof(struct mach_header_64) : sizeof(struct mach_header);
    if (length < headerSize) return false;
    uint32_t ncmds = is64 ? ((const struct mach_header_64 *)bytes)->ncmds
                          : ((const struct mach_header *)bytes)->ncmds;
    size_t cursor = headerSize;
    for (uint32_t i = 0; i < ncmds; i++) {
        if (cursor + sizeof(struct load_command) > length) return false;
        const struct load_command *lc = (const void *)(bytes + cursor);
        if (lc->cmdsize < sizeof(*lc) || cursor + lc->cmdsize > length) return false;
        if (lc->cmd == LC_UUID && lc->cmdsize >= sizeof(struct uuid_command)) {
            memcpy(uuid, ((const struct uuid_command *)lc)->uuid, 16);
            return true;
        }
        cursor += lc->cmdsize;
    }
    return false;
}

static uint64_t ipadec_find_loaded_image(uint64_t vmMap, const IPADecryptorMachOInfo *info)
{
    if (!vmMap || !info || !info->hasUUID) return 0;
    __block uint64_t found = 0;
    __block NSUInteger inspected = 0;
    vm_map_iterate_entries(vmMap, ^(uint64_t start, uint64_t end, uint64_t entry, BOOL *stop) {
        (void)end; (void)entry;
        if (++inspected > 4096) { *stop = YES; return; }
        if (start < 0x100000000ULL || start >= 0xffffff8000000000ULL) return;
        struct VMShmem page = vm_map_remote_page(vmMap, start);
        if (!page.used || !page.localAddress) return;
        uint8_t loadedUUID[16] = {0};
        bool parsed = ipadec_uuid_from_loaded_header((const uint8_t *)(uintptr_t)page.localAddress,
                                                     PAGE_SIZE, loadedUUID);
        mach_vm_deallocate(mach_task_self(), page.localAddress, PAGE_SIZE);
        if (parsed && memcmp(loadedUUID, info->uuid, 16) == 0) {
            found = start; *stop = YES;
        }
    });
    return found;
}

static bool ipadec_dump_binary(NSString *sourcePath, NSString *destinationPath,
                               uint64_t vmMap, NSString **errorOut)
{
    NSMutableData *data = [NSMutableData dataWithContentsOfFile:sourcePath
                                                        options:NSDataReadingMappedIfSafe
                                                          error:nil];
    IPADecryptorMachOInfo info = {0};
    if (!data || !ipadec_parse_macho_data(data, &info) || !info.isMachO) {
        if (errorOut) *errorOut = @"Mach-O parse failed."; return false;
    }
    if (!info.hasEncryptionInfo || info.cryptid == 0) return true;
    if (!info.hasUUID) { if (errorOut) *errorOut = @"Encrypted image has no LC_UUID."; return false; }
    uint64_t diskCryptoff = info.sliceOffset + info.cryptoff;
    if (!ipadec_range_ok(data.length, diskCryptoff, info.cryptsize) ||
        info.cryptoff < info.textFileoff) {
        if (errorOut) *errorOut = @"Invalid encrypted range."; return false;
    }
    uint64_t imageBase = ipadec_find_loaded_image(vmMap, &info);
    if (!imageBase) { if (errorOut) *errorOut = @"Image is not loaded in the target process."; return false; }

    log_user("[IPADEC][DUMP] image=%s base=0x%llx cryptoff=0x%llx cryptsize=0x%llx\n",
             sourcePath.lastPathComponent.UTF8String,
             (unsigned long long)imageBase,
             (unsigned long long)info.cryptoff,
             (unsigned long long)info.cryptsize);
    uint64_t copied = 0;
    while (copied < info.cryptsize) {
        uint64_t remote = imageBase + (info.cryptoff - info.textFileoff) + copied;
        uint64_t pageStart = remote & ~((uint64_t)PAGE_SIZE - 1ULL);
        uint64_t pageOffset = remote - pageStart;
        uint64_t chunk = MIN((uint64_t)PAGE_SIZE - pageOffset, info.cryptsize - copied);
        struct VMShmem page = vm_map_remote_page(vmMap, pageStart);
        if (!page.used || !page.localAddress) {
            if (errorOut) *errorOut = [NSString stringWithFormat:@"Failed to map decrypted page at 0x%llx.", remote];
            return false;
        }
        memcpy((uint8_t *)data.mutableBytes + diskCryptoff + copied,
               (const uint8_t *)(uintptr_t)page.localAddress + pageOffset,
               (size_t)chunk);
        mach_vm_deallocate(mach_task_self(), page.localAddress, PAGE_SIZE);
        copied += chunk;
    }

    uint64_t cryptidOffset = info.encryptionCommandOffset +
        (info.is64 ? offsetof(struct encryption_info_command_64, cryptid)
                   : offsetof(struct encryption_info_command, cryptid));
    if (!ipadec_range_ok(data.length, cryptidOffset, sizeof(uint32_t))) {
        if (errorOut) *errorOut = @"cryptid field is out of bounds."; return false;
    }
    *(uint32_t *)((uint8_t *)data.mutableBytes + cryptidOffset) = 0;
    NSError *writeError = nil;
    if (![data writeToFile:destinationPath options:NSDataWritingAtomic error:&writeError]) {
        if (errorOut) *errorOut = writeError.localizedDescription ?: @"Failed to write decrypted image.";
        return false;
    }
    IPADecryptorMachOInfo verify = ipadec_info_for_path(destinationPath);
    if (verify.hasEncryptionInfo && verify.cryptid != 0) {
        if (errorOut) *errorOut = @"cryptid verification failed."; return false;
    }
    log_user("[IPADEC][DUMP-OK] image=%s bytes=%llu cryptid=0\n",
             sourcePath.lastPathComponent.UTF8String, (unsigned long long)copied);
    return true;
}

static NSArray<NSString *> *ipadec_macho_paths(NSString *bundlePath)
{
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSString *main = [bundlePath stringByAppendingPathComponent:ipadec_executable_name(bundlePath) ?: @""];
    if (main.length > 0) [paths addObject:main];
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:bundlePath];
    for (NSString *relative in enumerator) {
        NSString *path = [bundlePath stringByAppendingPathComponent:relative];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:path isDirectory:&isDir] || isDir || [path isEqualToString:main]) continue;
        if (ipadec_info_for_path(path).isMachO) [paths addObject:path];
    }
    return paths;
}

static bool ipadec_archive_staging(NSString *stagingDir, NSString *ipaPath, NSString **errorOut)
{
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm removeItemAtPath:ipaPath error:nil];
    __block NSError *archiveError = nil;
    __block BOOL archived = NO;
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    [coordinator coordinateReadingItemAtURL:[NSURL fileURLWithPath:stagingDir]
                                    options:NSFileCoordinatorReadingForUploading
                                      error:&archiveError
                                 byAccessor:^(NSURL *preparedURL) {
        archived = [fm copyItemAtURL:preparedURL toURL:[NSURL fileURLWithPath:ipaPath]
                               error:&archiveError];
    }];
    if (!archived && errorOut) *errorOut = archiveError.localizedDescription ?: @"Native ZIP creation failed.";
    return archived;
}

bool ipadecryptor_probe_installed_app(NSString *bundleID, NSString **messageOut)
{
    NSDictionary *entry = ipadec_lookup_app(bundleID);
    if (!entry) { if (messageOut) *messageOut = @"Select an installed app first."; return false; }
    NSString *bundlePath = entry[kIPADecryptorKeyBundlePath];
    NSArray<NSString *> *images = ipadec_macho_paths(bundlePath);
    NSUInteger encrypted = 0, uuidMissing = 0;
    for (NSString *path in images) {
        IPADecryptorMachOInfo info = ipadec_info_for_path(path);
        if (info.hasEncryptionInfo && info.cryptid != 0) {
            encrypted++; if (!info.hasUUID) uuidMissing++;
        }
    }
    log_user("[IPADEC][PROBE] app=%s bundle=%s machos=%lu encrypted=%lu missingUUID=%lu mode=installed-local\n",
             bundleID.UTF8String, bundlePath.UTF8String,
             (unsigned long)images.count, (unsigned long)encrypted, (unsigned long)uuidMissing);
    if (messageOut) *messageOut = [NSString stringWithFormat:
        @"Probe OK: %lu Mach-O images, %lu encrypted%@.",
        (unsigned long)images.count, (unsigned long)encrypted,
        uuidMissing ? @", some missing UUID" : @""];
    return images.count > 0 && uuidMissing == 0;
}

bool ipadecryptor_start_decrypt_installed_app(NSString *bundleID, NSString **messageOut)
{
    ipadec_clear_legacy_account_state();
    if (!kexploit_krw_ready()) {
        if (messageOut) *messageOut = @"Kernel read/write is not ready."; return false;
    }
    NSDictionary *entry = ipadec_lookup_app(bundleID);
    if (!entry) { if (messageOut) *messageOut = @"Installed app not found."; return false; }
    NSString *bundlePath = entry[kIPADecryptorKeyBundlePath];
    NSString *executable = ipadec_executable_name(bundlePath);
    if (bundlePath.length == 0 || executable.length == 0) {
        if (messageOut) *messageOut = @"App bundle metadata is incomplete."; return false;
    }

    __block UIBackgroundTaskIdentifier bgTask = UIBackgroundTaskInvalid;
    dispatch_sync(dispatch_get_main_queue(), ^{
        bgTask = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"IPADecryptor"
                                                            expirationHandler:^{
            log_user("[IPADEC][FAIL] iOS ended the background task before export completed.\n");
        }];
    });
    bool success = false;
    NSString *resultMessage = nil;
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *staging = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"Infern0IPA-%@", NSUUID.UUID.UUIDString]];
    @try {
        uint64_t proc = ipadec_find_process(executable);
        if (!proc) {
            log_user("[IPADEC][LAUNCH] app=%s result=requested\n", bundleID.UTF8String);
            if (!ipadec_launch_bundle(bundleID)) { resultMessage = @"Failed to launch installed app."; return false; }
            for (int attempt = 0; attempt < 40 && !proc; attempt++) {
                usleep(250000); proc = ipadec_find_process(executable);
            }
        }
        if (!proc) { resultMessage = @"App process did not appear after launch."; return false; }
        uint64_t task = proc_task(proc);
        uint64_t vmMap = task_get_vm_map(task);
        if (!task || !vmMap) { resultMessage = @"Failed to resolve target task VM map."; return false; }
        log_user("[IPADEC][TARGET] app=%s executable=%s proc=0x%llx task=0x%llx vmMap=0x%llx\n",
                 bundleID.UTF8String, executable.UTF8String,
                 (unsigned long long)proc, (unsigned long long)task, (unsigned long long)vmMap);

        NSString *payload = [staging stringByAppendingPathComponent:@"Payload"];
        NSString *destBundle = [payload stringByAppendingPathComponent:bundlePath.lastPathComponent];
        [fm createDirectoryAtPath:payload withIntermediateDirectories:YES attributes:nil error:nil];
        NSError *copyError = nil;
        if (![fm copyItemAtPath:bundlePath toPath:destBundle error:&copyError]) {
            resultMessage = [NSString stringWithFormat:@"Bundle copy failed: %@", copyError.localizedDescription];
            return false;
        }

        NSArray<NSString *> *images = ipadec_macho_paths(bundlePath);
        NSUInteger encrypted = 0, dumped = 0;
        for (NSString *source in images) {
            IPADecryptorMachOInfo info = ipadec_info_for_path(source);
            if (!info.hasEncryptionInfo || info.cryptid == 0) continue;
            encrypted++;
            NSString *relative = [source substringFromIndex:bundlePath.length + 1];
            NSString *destination = [destBundle stringByAppendingPathComponent:relative];
            NSString *dumpError = nil;
            if (!ipadec_dump_binary(source, destination, vmMap, &dumpError)) {
                resultMessage = [NSString stringWithFormat:@"%@ failed: %@",
                                 relative, dumpError ?: @"unknown dump error"];
                log_user("[IPADEC][FAIL] image=%s reason=%s atomicCleanup=1\n",
                         relative.UTF8String, resultMessage.UTF8String);
                return false;
            }
            dumped++;
        }

        for (NSString *path in ipadec_macho_paths(destBundle)) {
            IPADecryptorMachOInfo verify = ipadec_info_for_path(path);
            if (verify.hasEncryptionInfo && verify.cryptid != 0) {
                resultMessage = [NSString stringWithFormat:@"Validation found an encrypted image: %@",
                                 [path substringFromIndex:destBundle.length + 1]];
                return false;
            }
        }
        NSString *safeName = [entry[kIPADecryptorKeyName] stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
        if (safeName.length == 0) safeName = executable;
        NSString *ipaPath = [ipadecryptor_default_output_directory()
            stringByAppendingPathComponent:[safeName stringByAppendingPathExtension:@"ipa"]];
        NSString *archiveError = nil;
        if (!ipadec_archive_staging(staging, ipaPath, &archiveError)) {
            resultMessage = [NSString stringWithFormat:@"IPA archive failed: %@", archiveError ?: @"unknown"];
            return false;
        }
        log_user("[IPADEC][COMPLETE] app=%s machos=%lu encrypted=%lu dumped=%lu output=%s\n",
                 bundleID.UTF8String, (unsigned long)images.count,
                 (unsigned long)encrypted, (unsigned long)dumped, ipaPath.UTF8String);
        resultMessage = [NSString stringWithFormat:@"Decrypted %lu image%@ and saved %@.",
                         (unsigned long)dumped, dumped == 1 ? @"" : @"s", ipaPath.lastPathComponent];
        success = true;
    } @finally {
        [fm removeItemAtPath:staging error:nil];
        if (bgTask != UIBackgroundTaskInvalid) dispatch_async(dispatch_get_main_queue(), ^{
            [UIApplication.sharedApplication endBackgroundTask:bgTask];
        });
        if (!success) log_user("[IPADEC][ABORT] outputCreated=0 temporaryFilesRemoved=1 reason=%s\n",
                               resultMessage.UTF8String ?: "unknown");
    }
    if (messageOut) *messageOut = resultMessage ?: (success ? @"IPA export completed." : @"IPA export failed.");
    return success;
}

// Compatibility stubs for old Settings binaries/actions. They deliberately
// perform no network requests and retain no credentials.
NSString *ipadecryptor_app_store_account_summary(void) { ipadec_clear_legacy_account_state(); return @"Removed — local installed-app mode"; }
bool ipadecryptor_has_app_store_account(void) { ipadec_clear_legacy_account_state(); return false; }
bool ipadecryptor_login_app_store(NSString *email, NSString *password, NSString *authCode, NSString **messageOut)
{ (void)email; (void)password; (void)authCode; if (messageOut) *messageOut = @"App Store sign-in was removed. Choose an installed app."; return false; }
void ipadecryptor_clear_app_store_account(void) { ipadec_clear_legacy_account_state(); }
NSDictionary<NSString *, NSString *> *ipadecryptor_resolve_app_store_input(NSString *input, NSString **messageOut)
{ (void)input; if (messageOut) *messageOut = @"App Store lookup was removed. Choose an installed app."; return nil; }
bool ipadecryptor_download_app_store_ipa(NSString *input, NSString **downloadedPathOut, NSString **messageOut)
{ (void)input; if (downloadedPathOut) *downloadedPathOut = nil; if (messageOut) *messageOut = @"App Store downloading was removed. Choose an installed app."; return false; }
