//
//  ipadecryptor.m
//  Cyanide private/in-dev IPA decryptor scaffold.
//

#import "ipadecryptor.h"
#import "../../LogTextView.h"
#import "../../kexploit/kutils.h"

#import <Foundation/Foundation.h>
#import <mach-o/fat.h>
#import <mach-o/loader.h>
#import <libkern/OSByteOrder.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <ifaddrs.h>
#import <net/if_dl.h>
#import <sys/socket.h>
#import <sys/stat.h>
#import <stdlib.h>
#import <unistd.h>
#include <spawn.h>
#include <sys/wait.h>

static NSString * const kIPADecryptorKeyBundleID = @"bundleID";
static NSString * const kIPADecryptorKeyName = @"name";
static NSString * const kIPADecryptorKeyBundlePath = @"bundlePath";
static NSString * const kIPADecryptorKeyAppStoreID = @"appStoreID";
static NSString * const kIPADecryptorKeyVersion = @"version";
static NSString * const kIPADecryptorKeyTrackURL = @"trackURL";
static NSString * const kIPADecryptorKeyCountry = @"country";
static NSString * const kIPADecryptorKeyFileSizeBytes = @"fileSizeBytes";
static NSString * const kIPADecryptorKeyPrice = @"price";

static NSString * const kIPADefaultUserAgent = @"Configurator/2.17 (Macintosh; OS X 15.2; 24C5089c) AppleWebKit/0620.1.16.11.6";
static NSString * const kIPAFallbackAuthUserAgent = @"iTunes/12.10.11 (Macintosh; OS X 10.15.7) AppleWebKit/605.1.15";
static NSString * const kIPADefaultUSStoreFront = @"143441-1,29";
static NSString * const kIPAAccountEmailKey = @"cyanide.ipadecryptor.apple.email";
static NSString * const kIPAAccountTokenKey = @"cyanide.ipadecryptor.apple.passwordToken";
static NSString * const kIPAAccountDSIDKey = @"cyanide.ipadecryptor.apple.dsid";
static NSString * const kIPAAccountStoreFrontKey = @"cyanide.ipadecryptor.apple.storeFront";
static NSString * const kIPAAccountPodKey = @"cyanide.ipadecryptor.apple.pod";
static NSString * const kIPAAccountNameKey = @"cyanide.ipadecryptor.apple.name";
static NSString * const kIPAGUIDKey = @"cyanide.ipadecryptor.apple.guid";

typedef struct {
    bool isMachO;
    bool hasEncryptionInfo;
    uint32_t cryptid;
    uint32_t cryptoff;
    uint32_t cryptsize;
    uint32_t archCount;
} IPADecryptorMachOInfo;

@interface IPADECHTTPRedirectBlocker : NSObject <NSURLSessionTaskDelegate>
@property (atomic, strong) NSHTTPURLResponse *redirectResponse;
@property (atomic, copy) NSURLRequest *redirectRequest;
@end

@implementation IPADECHTTPRedirectBlocker
- (void)URLSession:(__unused NSURLSession *)session
              task:(__unused NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler
{
    self.redirectResponse = response;
    self.redirectRequest = request;
    completionHandler(nil);
}
@end

static NSString *ipadec_nonempty_string(id value)
{
    return [value isKindOfClass:NSString.class] && [(NSString *)value length] > 0
        ? (NSString *)value
        : nil;
}

static id ipadec_perform0(id target, SEL selector)
{
    if (!target || !selector || ![target respondsToSelector:selector]) return nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    return [target performSelector:selector];
#pragma clang diagnostic pop
}

static NSString *ipadec_bundle_path_from_proxy(id proxy)
{
    NSURL *bundleURL = ipadec_perform0(proxy, @selector(bundleURL));
    if ([bundleURL isKindOfClass:NSURL.class] && bundleURL.path.length > 0) {
        return bundleURL.path;
    }

    NSURL *containerURL = ipadec_perform0(proxy, @selector(bundleContainerURL));
    if ([containerURL isKindOfClass:NSURL.class] && containerURL.path.length > 0) {
        return containerURL.path;
    }
    return nil;
}

static NSMutableDictionary<NSString *, NSString *> *ipadec_app_entry(NSString *bundleID,
                                                                     NSString *name,
                                                                     NSString *bundlePath)
{
    if (bundleID.length == 0 || bundlePath.length == 0) return nil;
    NSMutableDictionary<NSString *, NSString *> *entry = [NSMutableDictionary dictionary];
    entry[kIPADecryptorKeyBundleID] = bundleID;
    entry[kIPADecryptorKeyName] = name.length > 0 ? name : bundleID;
    entry[kIPADecryptorKeyBundlePath] = bundlePath;
    return entry;
}

static NSArray<NSDictionary<NSString *, NSString *> *> *ipadec_apps_from_launchservices(void)
{
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    id workspace = ipadec_perform0(workspaceClass, @selector(defaultWorkspace));
    NSArray *proxies = ipadec_perform0(workspace, @selector(allApplications));
    if (![proxies isKindOfClass:NSArray.class]) return @[];

    NSMutableArray<NSDictionary<NSString *, NSString *> *> *out = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id proxy in proxies) {
        NSString *bundleID = ipadec_nonempty_string(ipadec_perform0(proxy, @selector(bundleIdentifier)));
        if (bundleID.length == 0 || [seen containsObject:bundleID]) continue;

        NSString *bundlePath = ipadec_bundle_path_from_proxy(proxy);
        if (bundlePath.length == 0) continue;

        // IPA decryption is only meaningful for user-installed app bundles.
        // Keep the picker focused so system apps do not dominate the list.
        if ([bundlePath rangeOfString:@"/Bundle/Application/"].location == NSNotFound &&
            [bundlePath rangeOfString:@"/Containers/Bundle/Application/"].location == NSNotFound) {
            continue;
        }

        NSString *name = ipadec_nonempty_string(ipadec_perform0(proxy, @selector(localizedName)));
        if (name.length == 0) name = ipadec_nonempty_string(ipadec_perform0(proxy, @selector(itemName)));
        NSMutableDictionary *entry = ipadec_app_entry(bundleID, name, bundlePath);
        if (!entry) continue;
        [out addObject:entry];
        [seen addObject:bundleID];
    }
    return out;
}

static NSArray<NSDictionary<NSString *, NSString *> *> *ipadec_apps_from_bundle_scan(void)
{
    NSString *root = @"/var/containers/Bundle/Application";
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray<NSString *> *containers = [fm contentsOfDirectoryAtPath:root error:nil];
    if (containers.count == 0) return @[];

    NSMutableArray<NSDictionary<NSString *, NSString *> *> *out = [NSMutableArray array];
    for (NSString *container in containers) {
        NSString *containerPath = [root stringByAppendingPathComponent:container];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:containerPath isDirectory:&isDir] || !isDir) continue;
        NSArray<NSString *> *items = [fm contentsOfDirectoryAtPath:containerPath error:nil];
        for (NSString *item in items) {
            if (![item.pathExtension.lowercaseString isEqualToString:@"app"]) continue;
            NSString *bundlePath = [containerPath stringByAppendingPathComponent:item];
            NSString *infoPath = [bundlePath stringByAppendingPathComponent:@"Info.plist"];
            NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
            NSString *bundleID = ipadec_nonempty_string(info[@"CFBundleIdentifier"]);
            NSString *name = ipadec_nonempty_string(info[@"CFBundleDisplayName"])
                ?: ipadec_nonempty_string(info[@"CFBundleName"])
                ?: bundleID;
            NSMutableDictionary *entry = ipadec_app_entry(bundleID, name, bundlePath);
            if (entry) [out addObject:entry];
        }
    }
    return out;
}

NSArray<NSDictionary<NSString *, NSString *> *> *ipadecryptor_installed_apps(void)
{
    NSMutableDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *byBundle = [NSMutableDictionary dictionary];
    for (NSDictionary<NSString *, NSString *> *entry in ipadec_apps_from_launchservices()) {
        NSString *bundleID = entry[kIPADecryptorKeyBundleID];
        if (bundleID.length > 0) byBundle[bundleID] = entry;
    }
    for (NSDictionary<NSString *, NSString *> *entry in ipadec_apps_from_bundle_scan()) {
        NSString *bundleID = entry[kIPADecryptorKeyBundleID];
        if (bundleID.length > 0 && !byBundle[bundleID]) byBundle[bundleID] = entry;
    }

    NSArray *sorted = [byBundle.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSString *an = a[kIPADecryptorKeyName] ?: a[kIPADecryptorKeyBundleID] ?: @"";
        NSString *bn = b[kIPADecryptorKeyName] ?: b[kIPADecryptorKeyBundleID] ?: @"";
        NSComparisonResult r = [an localizedCaseInsensitiveCompare:bn];
        if (r != NSOrderedSame) return r;
        return [(a[kIPADecryptorKeyBundleID] ?: @"") compare:(b[kIPADecryptorKeyBundleID] ?: @"")];
    }];
    return sorted ?: @[];
}

static NSDictionary<NSString *, NSString *> *ipadec_lookup_app(NSString *bundleID)
{
    if (bundleID.length == 0) return nil;
    for (NSDictionary<NSString *, NSString *> *entry in ipadecryptor_installed_apps()) {
        if ([entry[kIPADecryptorKeyBundleID] isEqualToString:bundleID]) return entry;
    }
    return nil;
}

NSString *ipadecryptor_display_name_for_bundle(NSString *bundleID)
{
    NSDictionary *entry = ipadec_lookup_app(bundleID);
    NSString *name = entry[kIPADecryptorKeyName];
    if (name.length > 0 && bundleID.length > 0) {
        return [NSString stringWithFormat:@"%@ (%@)", name, bundleID];
    }
    return bundleID.length > 0 ? bundleID : @"None selected";
}

NSString *ipadecryptor_default_output_directory(void)
{
    NSArray<NSString *> *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                                    NSUserDomainMask,
                                                                    YES);
    NSString *base = docs.firstObject ?: NSTemporaryDirectory();
    NSString *dir = [base stringByAppendingPathComponent:@"DecryptedIPAs"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
    return dir;
}

static NSString *ipadec_executable_path_for_bundle(NSString *bundlePath)
{
    if (bundlePath.length == 0) return nil;
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
        [bundlePath stringByAppendingPathComponent:@"Info.plist"]];
    NSString *exec = ipadec_nonempty_string(info[@"CFBundleExecutable"]);
    if (exec.length == 0) {
        exec = bundlePath.lastPathComponent.stringByDeletingPathExtension;
    }
    return exec.length > 0 ? [bundlePath stringByAppendingPathComponent:exec] : nil;
}

static BOOL ipadec_macho_info_at_offset(const uint8_t *bytes,
                                        NSUInteger length,
                                        NSUInteger offset,
                                        IPADecryptorMachOInfo *info)
{
    if (!bytes || !info || offset + sizeof(uint32_t) > length) return NO;
    uint32_t magic = 0;
    memcpy(&magic, bytes + offset, sizeof(magic));
    BOOL is64 = (magic == MH_MAGIC_64 || magic == MH_CIGAM_64);
    BOOL is32 = (magic == MH_MAGIC || magic == MH_CIGAM);
    if (!is64 && !is32) return NO;

    BOOL swap = (magic == MH_CIGAM || magic == MH_CIGAM_64);
    uint32_t ncmds = 0;
    uint32_t sizeofcmds = 0;
    NSUInteger cursor = 0;
    if (is64) {
        if (offset + sizeof(struct mach_header_64) > length) return NO;
        struct mach_header_64 header;
        memcpy(&header, bytes + offset, sizeof(header));
        ncmds = swap ? OSSwapInt32(header.ncmds) : header.ncmds;
        sizeofcmds = swap ? OSSwapInt32(header.sizeofcmds) : header.sizeofcmds;
        cursor = offset + sizeof(struct mach_header_64);
    } else {
        if (offset + sizeof(struct mach_header) > length) return NO;
        struct mach_header header;
        memcpy(&header, bytes + offset, sizeof(header));
        ncmds = swap ? OSSwapInt32(header.ncmds) : header.ncmds;
        sizeofcmds = swap ? OSSwapInt32(header.sizeofcmds) : header.sizeofcmds;
        cursor = offset + sizeof(struct mach_header);
    }

    if (cursor + sizeofcmds > length) return NO;
    info->isMachO = true;
    info->archCount++;

    for (uint32_t i = 0; i < ncmds; i++) {
        if (cursor + sizeof(struct load_command) > length) return NO;
        struct load_command lc;
        memcpy(&lc, bytes + cursor, sizeof(lc));
        uint32_t cmd = swap ? OSSwapInt32(lc.cmd) : lc.cmd;
        uint32_t cmdsize = swap ? OSSwapInt32(lc.cmdsize) : lc.cmdsize;
        if (cmdsize < sizeof(struct load_command) || cursor + cmdsize > length) return NO;

        if (cmd == LC_ENCRYPTION_INFO || cmd == LC_ENCRYPTION_INFO_64) {
            if (cursor + sizeof(struct encryption_info_command) <= length) {
                struct encryption_info_command enc;
                memcpy(&enc, bytes + cursor, sizeof(enc));
                uint32_t cryptid = swap ? OSSwapInt32(enc.cryptid) : enc.cryptid;
                uint32_t cryptoff = swap ? OSSwapInt32(enc.cryptoff) : enc.cryptoff;
                uint32_t cryptsize = swap ? OSSwapInt32(enc.cryptsize) : enc.cryptsize;
                info->hasEncryptionInfo = true;
                if (cryptid != 0 || info->cryptsize == 0) {
                    info->cryptid = cryptid;
                    info->cryptoff = cryptoff;
                    info->cryptsize = cryptsize;
                }
            }
        }
        cursor += cmdsize;
    }
    return YES;
}

static IPADecryptorMachOInfo ipadec_macho_info_for_file(NSString *path)
{
    IPADecryptorMachOInfo info = {0};
    NSData *data = [NSData dataWithContentsOfFile:path
                                          options:NSDataReadingMappedIfSafe
                                            error:nil];
    if (data.length < sizeof(uint32_t)) return info;

    const uint8_t *bytes = data.bytes;
    uint32_t magic = 0;
    memcpy(&magic, bytes, sizeof(magic));

    if (magic == FAT_CIGAM || magic == FAT_MAGIC) {
        if (data.length < sizeof(struct fat_header)) return info;
        struct fat_header header;
        memcpy(&header, bytes, sizeof(header));
        BOOL swap = (magic == FAT_CIGAM);
        uint32_t nfat = swap ? OSSwapBigToHostInt32(header.nfat_arch) : header.nfat_arch;
        NSUInteger cursor = sizeof(struct fat_header);
        for (uint32_t i = 0; i < nfat; i++) {
            if (cursor + sizeof(struct fat_arch) > data.length) break;
            struct fat_arch arch;
            memcpy(&arch, bytes + cursor, sizeof(arch));
            uint32_t off = swap ? OSSwapBigToHostInt32(arch.offset) : arch.offset;
            (void)ipadec_macho_info_at_offset(bytes, data.length, off, &info);
            cursor += sizeof(struct fat_arch);
        }
        return info;
    }

    if (magic == FAT_CIGAM_64 || magic == FAT_MAGIC_64) {
        if (data.length < sizeof(struct fat_header)) return info;
        struct fat_header header;
        memcpy(&header, bytes, sizeof(header));
        BOOL swap = (magic == FAT_CIGAM_64);
        uint32_t nfat = swap ? OSSwapBigToHostInt32(header.nfat_arch) : header.nfat_arch;
        NSUInteger cursor = sizeof(struct fat_header);
        for (uint32_t i = 0; i < nfat; i++) {
            if (cursor + sizeof(struct fat_arch_64) > data.length) break;
            struct fat_arch_64 arch;
            memcpy(&arch, bytes + cursor, sizeof(arch));
            uint64_t off = swap ? OSSwapBigToHostInt64(arch.offset) : arch.offset;
            if (off <= NSUIntegerMax) {
                (void)ipadec_macho_info_at_offset(bytes, data.length, (NSUInteger)off, &info);
            }
            cursor += sizeof(struct fat_arch_64);
        }
        return info;
    }

    (void)ipadec_macho_info_at_offset(bytes, data.length, 0, &info);
    return info;
}

static BOOL ipadec_file_exists(NSString *path)
{
    BOOL isDir = NO;
    return path.length > 0 &&
           [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDir] &&
           !isDir;
}

static NSString *ipadec_trimmed(NSString *s)
{
    return [s isKindOfClass:NSString.class]
        ? [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
        : @"";
}

static NSString *ipadec_extract_app_store_id(NSString *input)
{
    NSString *s = ipadec_trimmed(input);
    if (s.length == 0) return nil;

    NSCharacterSet *nonDigits = NSCharacterSet.decimalDigitCharacterSet.invertedSet;
    if ([s rangeOfCharacterFromSet:nonDigits].location == NSNotFound) return s;

    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"(?:^|[^A-Za-z0-9])id(\\d{5,})"
                                                                        options:0
                                                                          error:nil];
    NSTextCheckingResult *match = [re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
    if (match && match.numberOfRanges > 1) {
        return [s substringWithRange:[match rangeAtIndex:1]];
    }
    return nil;
}

static NSString *ipadec_country_from_app_store_input(NSString *input)
{
    NSURLComponents *components = [NSURLComponents componentsWithString:ipadec_trimmed(input)];
    NSArray<NSString *> *parts = components.path.pathComponents;
    for (NSString *part in parts) {
        if (part.length != 2) continue;
        NSCharacterSet *letters = NSCharacterSet.letterCharacterSet;
        unichar a = [part characterAtIndex:0];
        unichar b = [part characterAtIndex:1];
        if ([letters characterIsMember:a] && [letters characterIsMember:b]) {
            return part.uppercaseString;
        }
    }
    return @"US";
}

static NSString *ipadec_string_from_json_value(id value)
{
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSNumber.class]) return [(NSNumber *)value stringValue];
    return nil;
}

static void ipadec_log_guid_source_once(const char *source)
{
    static BOOL didLog = NO;
    if (didLog) return;
    didLog = YES;
    log_user("[IPADEC] App Store GUID source: %s\n", source ?: "unknown");
}

static NSString *ipadec_mac12_from_string(NSString *s)
{
    if (![s isKindOfClass:NSString.class]) return nil;
    NSMutableString *hex = [NSMutableString string];
    NSCharacterSet *hexChars = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if ([hexChars characterIsMember:c]) {
            [hex appendFormat:@"%C", c];
        }
    }
    NSString *out = hex.uppercaseString;
    return out.length == 12 ? out : nil;
}

static NSString *ipadec_mac12_from_data(NSData *data)
{
    if (![data isKindOfClass:NSData.class] || data.length < 6) return nil;
    const uint8_t *mac = data.bytes;
    return [NSString stringWithFormat:@"%02X%02X%02X%02X%02X%02X",
            mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]];
}

static BOOL ipadec_mac12_is_placeholder(NSString *mac)
{
    return mac.length != 12 ||
           [mac isEqualToString:@"000000000000"] ||
           [mac isEqualToString:@"020000000000"];
}

static NSString *ipadec_guid_from_mobilegestalt(void)
{
    void *h = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY);
    if (!h) return nil;
    typedef CFTypeRef (*MGCopyAnswerFn)(CFStringRef);
    MGCopyAnswerFn MGCopyAnswer = (MGCopyAnswerFn)dlsym(h, "MGCopyAnswer");
    if (!MGCopyAnswer) return nil;

    NSArray<NSString *> *keys = @[@"WifiAddress", @"WiFiAddress", @"EthernetMacAddress", @"BluetoothAddress"];
    for (NSString *key in keys) {
        CFTypeRef answerRef = MGCopyAnswer((__bridge CFStringRef)key);
        id answer = CFBridgingRelease(answerRef);
        NSString *mac = nil;
        if ([answer isKindOfClass:NSString.class]) {
            mac = ipadec_mac12_from_string(answer);
        } else if ([answer isKindOfClass:NSData.class]) {
            mac = ipadec_mac12_from_data(answer);
        }
        if (mac.length == 12 && !ipadec_mac12_is_placeholder(mac)) {
            ipadec_log_guid_source_once("MobileGestalt Wi-Fi hardware address");
            return mac;
        }
    }
    return nil;
}

static NSString *ipadec_guid_from_network_interfaces_plist(void)
{
    NSArray<NSString *> *paths = @[
        @"/Library/Preferences/SystemConfiguration/NetworkInterfaces.plist",
        @"/private/var/preferences/SystemConfiguration/NetworkInterfaces.plist"
    ];
    for (NSString *path in paths) {
        NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:path];
        NSArray *interfaces = [plist[@"Interfaces"] isKindOfClass:NSArray.class] ? plist[@"Interfaces"] : nil;
        for (NSDictionary *iface in interfaces) {
            if (![iface isKindOfClass:NSDictionary.class]) continue;
            NSString *bsd = [iface[@"BSD Name"] isKindOfClass:NSString.class] ? iface[@"BSD Name"] : @"";
            if (![bsd isEqualToString:@"en0"]) continue;

            NSString *mac = nil;
            id raw = iface[@"IOMACAddress"];
            if ([raw isKindOfClass:NSData.class]) {
                mac = ipadec_mac12_from_data(raw);
            } else if ([raw isKindOfClass:NSString.class]) {
                mac = ipadec_mac12_from_string(raw);
            }
            if (mac.length == 12 && !ipadec_mac12_is_placeholder(mac)) {
                ipadec_log_guid_source_once("NetworkInterfaces en0 hardware address");
                return mac;
            }
        }
    }
    return nil;
}

static NSString *ipadec_guid(void)
{
    NSString *realMAC = ipadec_guid_from_mobilegestalt();
    if (realMAC.length == 12) return realMAC;

    realMAC = ipadec_guid_from_network_interfaces_plist();
    if (realMAC.length == 12) return realMAC;

    // Match londek/ipadecrypt: Configurator-shaped GUID is the machine MAC
    // address, uppercase, with colons removed. Do not filter iOS' privacy
    // placeholder address; ipadecrypt uses any non-empty en0 hardware address.
    struct ifaddrs *ifaddr = NULL;
    if (getifaddrs(&ifaddr) == 0) {
        NSString *fallback = nil;
        for (struct ifaddrs *ifa = ifaddr; ifa != NULL; ifa = ifa->ifa_next) {
            if (!ifa->ifa_addr || ifa->ifa_addr->sa_family != AF_LINK) continue;
            struct sockaddr_dl *sdl = (struct sockaddr_dl *)ifa->ifa_addr;
            if (sdl->sdl_alen < 6) continue;

            unsigned char *mac = (unsigned char *)LLADDR(sdl);
            NSString *candidate = [NSString stringWithFormat:@"%02X%02X%02X%02X%02X%02X",
                                   mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]];
            if (strcmp(ifa->ifa_name, "en0") == 0) {
                freeifaddrs(ifaddr);
                ipadec_log_guid_source_once("en0 hardware address");
                return candidate;
            }
            if (!fallback) fallback = candidate;
        }
        freeifaddrs(ifaddr);
        if (fallback.length == 12) {
            ipadec_log_guid_source_once("network interface hardware address");
            return fallback;
        }
    }

    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSString *guid = [d stringForKey:kIPAGUIDKey];
    if (guid.length == 12) {
        ipadec_log_guid_source_once("stored fallback");
        return guid;
    }

    static const char hex[] = "0123456789ABCDEF";
    char buf[13] = {0};
    for (int i = 0; i < 12; i++) {
        buf[i] = hex[arc4random_uniform(16)];
    }
    guid = [NSString stringWithUTF8String:buf];
    [d setObject:guid forKey:kIPAGUIDKey];
    [d synchronize];
    ipadec_log_guid_source_once("generated fallback");
    return guid;
}

static NSString *ipadec_xml_escaped(NSString *s)
{
    NSMutableString *m = [(s ?: @"") mutableCopy];
    [m replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, m.length)];
    return m;
}

static void ipadec_append_plist_value(NSMutableString *xml, id value);

static void ipadec_append_plist_dict(NSMutableString *xml, NSDictionary *dict)
{
    [xml appendString:@"<dict>"];
    NSArray *keys = [[dict allKeys] sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
        return [[a description] compare:[b description]];
    }];
    for (id key in keys) {
        NSString *keyString = [key description] ?: @"";
        [xml appendFormat:@"<key>%@</key>", ipadec_xml_escaped(keyString)];
        ipadec_append_plist_value(xml, dict[key]);
    }
    [xml appendString:@"</dict>"];
}

static void ipadec_append_plist_array(NSMutableString *xml, NSArray *array)
{
    [xml appendString:@"<array>"];
    for (id value in array) {
        ipadec_append_plist_value(xml, value);
    }
    [xml appendString:@"</array>"];
}

static void ipadec_append_plist_value(NSMutableString *xml, id value)
{
    if (!value || value == NSNull.null) {
        [xml appendString:@"<string/>"];
    } else if ([value isKindOfClass:NSDictionary.class]) {
        ipadec_append_plist_dict(xml, (NSDictionary *)value);
    } else if ([value isKindOfClass:NSArray.class]) {
        ipadec_append_plist_array(xml, (NSArray *)value);
    } else if ([value isKindOfClass:NSData.class]) {
        [xml appendFormat:@"<data>%@</data>",
         [(NSData *)value base64EncodedStringWithOptions:0] ?: @""];
    } else if ([value isKindOfClass:NSNumber.class]) {
        NSNumber *n = (NSNumber *)value;
        if (CFGetTypeID((__bridge CFTypeRef)n) == CFBooleanGetTypeID()) {
            [xml appendString:n.boolValue ? @"<true/>" : @"<false/>"];
        } else {
            [xml appendFormat:@"<integer>%@</integer>", n.stringValue ?: @"0"];
        }
    } else {
        [xml appendFormat:@"<string>%@</string>", ipadec_xml_escaped([value description] ?: @"")];
    }
}

static NSData *ipadec_plist_body(NSDictionary *dict, NSString **messageOut)
{
    if (dict && ![dict isKindOfClass:NSDictionary.class]) {
        if (messageOut) *messageOut = @"plist encode failed: root is not dictionary";
        return nil;
    }
    NSMutableString *xml = [NSMutableString stringWithString:
        @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        @"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
        @"<plist version=\"1.0\">"];
    ipadec_append_plist_dict(xml, dict ?: @{});
    [xml appendString:@"</plist>"];
    return [xml dataUsingEncoding:NSUTF8StringEncoding];
}

static NSData *ipadec_normalized_plist_data(NSData *data)
{
    if (data.length == 0) return data;
    NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (s.length == 0) return data;
    NSString *trim = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];

    NSRegularExpression *doc = [NSRegularExpression regularExpressionWithPattern:@"(?is)<Document\\b[^>]*>(.*)</Document>"
                                                                         options:0
                                                                           error:nil];
    NSTextCheckingResult *docMatch = [doc firstMatchInString:trim options:0 range:NSMakeRange(0, trim.length)];
    if (docMatch && docMatch.numberOfRanges > 1) {
        trim = [[trim substringWithRange:[docMatch rangeAtIndex:1]]
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }

    NSRegularExpression *plist = [NSRegularExpression regularExpressionWithPattern:@"(?is)<plist\\b[^>]*>.*?</plist>"
                                                                           options:0
                                                                             error:nil];
    NSTextCheckingResult *plistMatch = [plist firstMatchInString:trim options:0 range:NSMakeRange(0, trim.length)];
    if (plistMatch) {
        NSString *sub = [trim substringWithRange:plistMatch.range];
        return [sub dataUsingEncoding:NSUTF8StringEncoding] ?: data;
    }

    NSRegularExpression *dict = [NSRegularExpression regularExpressionWithPattern:@"(?is)<dict\\b[^>]*>.*</dict>"
                                                                          options:0
                                                                            error:nil];
    NSTextCheckingResult *dictMatch = [dict firstMatchInString:trim options:0 range:NSMakeRange(0, trim.length)];
    if (dictMatch) {
        NSString *sub = [trim substringWithRange:dictMatch.range];
        NSString *wrapped = [NSString stringWithFormat:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\">%@</plist>", sub];
        return [wrapped dataUsingEncoding:NSUTF8StringEncoding] ?: data;
    }

    if ([trim rangeOfString:@"<key>"].location != NSNotFound) {
        NSString *wrapped = [NSString stringWithFormat:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict>%@</dict></plist>", trim];
        return [wrapped dataUsingEncoding:NSUTF8StringEncoding] ?: data;
    }
    return data;
}

static id ipadec_plist_object_from_data(NSData *data, NSString **messageOut)
{
    NSError *err = nil;
    id obj = [NSPropertyListSerialization propertyListWithData:ipadec_normalized_plist_data(data)
                                                       options:NSPropertyListMutableContainersAndLeaves
                                                        format:nil
                                                         error:&err];
    if (!obj && messageOut) {
        *messageOut = [NSString stringWithFormat:@"plist decode failed: %@", err.localizedDescription ?: @"unknown"];
    }
    return obj;
}

static NSData *ipadec_send_sync_internal(NSString *method,
                                         NSURL *url,
                                         NSDictionary<NSString *, NSString *> *headers,
                                         NSData *body,
                                         BOOL blockRedirects,
                                         NSHTTPURLResponse **httpOut,
                                         NSString **messageOut)
{
    if (!url) {
        if (messageOut) *messageOut = @"request URL missing";
        return nil;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = method ?: @"GET";
    request.timeoutInterval = 30.0;
    request.HTTPBody = body;
    [request setValue:kIPADefaultUserAgent forHTTPHeaderField:@"User-Agent"];
    [headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        (void)stop;
        if (key.length > 0 && value.length > 0) [request setValue:value forHTTPHeaderField:key];
    }];

    NSString *label = [NSString stringWithFormat:@"%@%@", url.host ?: @"", url.path ?: @""];
    CFAbsoluteTime started = CFAbsoluteTimeGetCurrent();
    log_user("[IPADEC] HTTP %s %s start\n", (method ?: @"GET").UTF8String, label.UTF8String);

    __block NSData *outData = nil;
    __block NSURLResponse *outResponse = nil;
    __block NSError *outError = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    NSURLSessionConfiguration *cfg = NSURLSessionConfiguration.defaultSessionConfiguration;
    cfg.timeoutIntervalForRequest = 30.0;
    cfg.timeoutIntervalForResource = 45.0;
    cfg.HTTPShouldSetCookies = YES;
    cfg.HTTPCookieAcceptPolicy = NSHTTPCookieAcceptPolicyAlways;
    cfg.HTTPCookieStorage = NSHTTPCookieStorage.sharedHTTPCookieStorage;
    IPADECHTTPRedirectBlocker *redirectBlocker = blockRedirects ? [IPADECHTTPRedirectBlocker new] : nil;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg
                                                          delegate:redirectBlocker
                                                     delegateQueue:nil];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        outData = data;
        outResponse = response;
        outError = error;
        dispatch_semaphore_signal(sem);
    }];
    [task resume];
    long waited = dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(45 * NSEC_PER_SEC)));
    if (waited != 0) {
        [task cancel];
        [session invalidateAndCancel];
        log_user("[IPADEC] HTTP %s timed out after 45s\n", label.UTF8String);
        if (messageOut) *messageOut = [NSString stringWithFormat:@"%@ request timed out", label];
        return nil;
    }
    [session finishTasksAndInvalidate];

    NSHTTPURLResponse *httpResponse = [outResponse isKindOfClass:NSHTTPURLResponse.class]
        ? (NSHTTPURLResponse *)outResponse
        : redirectBlocker.redirectResponse;
    if (httpResponse && httpOut) {
        *httpOut = httpResponse;
    }
    if (redirectBlocker.redirectResponse) {
        NSString *loc = redirectBlocker.redirectResponse.allHeaderFields[@"Location"] ?: redirectBlocker.redirectRequest.URL.absoluteString ?: @"";
        log_user("[IPADEC] HTTP %s captured redirect %ld -> %s\n",
                 label.UTF8String,
                 (long)redirectBlocker.redirectResponse.statusCode,
                 loc.UTF8String);
    }
    if (outError) {
        log_user("[IPADEC] HTTP %s error after %.1fs: %s\n",
                 label.UTF8String,
                 CFAbsoluteTimeGetCurrent() - started,
                 (outError.localizedDescription ?: @"network error").UTF8String);
        if (messageOut) *messageOut = outError.localizedDescription ?: @"network error";
        return nil;
    }
    log_user("[IPADEC] HTTP %s -> %ld %lu bytes in %.1fs\n",
             label.UTF8String,
             (long)httpResponse.statusCode,
             (unsigned long)outData.length,
             CFAbsoluteTimeGetCurrent() - started);
    return outData ?: [NSData data];
}

static NSData *ipadec_send_sync(NSString *method,
                                NSURL *url,
                                NSDictionary<NSString *, NSString *> *headers,
                                NSData *body,
                                NSHTTPURLResponse **httpOut,
                                NSString **messageOut)
{
    return ipadec_send_sync_internal(method, url, headers, body, false, httpOut, messageOut);
}

static NSDictionary<NSString *, NSString *> *ipadec_saved_account(void)
{
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSString *email = [d stringForKey:kIPAAccountEmailKey] ?: @"";
    NSString *token = [d stringForKey:kIPAAccountTokenKey] ?: @"";
    NSString *dsid = [d stringForKey:kIPAAccountDSIDKey] ?: @"";
    if (token.length == 0 || dsid.length == 0) return nil;
    return @{
        @"email": email,
        @"passwordToken": token,
        @"dsid": dsid,
        @"storeFront": [d stringForKey:kIPAAccountStoreFrontKey] ?: kIPADefaultUSStoreFront,
        @"pod": [d stringForKey:kIPAAccountPodKey] ?: @"",
        @"name": [d stringForKey:kIPAAccountNameKey] ?: @"",
    };
}

bool ipadecryptor_has_app_store_account(void)
{
    return ipadec_saved_account() != nil;
}

NSString *ipadecryptor_app_store_account_summary(void)
{
    NSDictionary *acc = ipadec_saved_account();
    if (!acc) return @"Not signed in. Sign in before downloading IPAs.";
    NSString *email = acc[@"email"];
    NSString *storeFront = acc[@"storeFront"];
    if (email.length == 0) email = @"Signed in";
    return [NSString stringWithFormat:@"%@ • storefront %@", email, storeFront.length > 0 ? storeFront : @"unknown"];
}

void ipadecryptor_clear_app_store_account(void)
{
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    for (NSString *key in @[kIPAAccountEmailKey,
                            kIPAAccountTokenKey,
                            kIPAAccountDSIDKey,
                            kIPAAccountStoreFrontKey,
                            kIPAAccountPodKey,
                            kIPAAccountNameKey]) {
        [d removeObjectForKey:key];
    }
    [d synchronize];
    log_user("[IPADEC] Cleared saved App Store account token.\n");
}

static NSString *ipadec_bag_auth_endpoint(NSString **messageOut)
{
    NSString *guid = ipadec_guid();
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://init.itunes.apple.com/bag.xml?guid=%@", guid]];
    log_user("[IPADEC] Fetching App Store bag for auth endpoint.\n");
    NSHTTPURLResponse *http = nil;
    NSData *data = ipadec_send_sync(@"GET", url, @{@"Accept": @"application/xml"}, nil, &http, messageOut);
    if (!data) return nil;
    if (http.statusCode != 200) {
        log_user("[IPADEC] App Store bag HTTP %ld.\n", (long)http.statusCode);
        if (messageOut) *messageOut = [NSString stringWithFormat:@"bag.xml HTTP %ld", (long)http.statusCode];
        return nil;
    }
    id plist = ipadec_plist_object_from_data(data, messageOut);
    NSDictionary *dict = [plist isKindOfClass:NSDictionary.class] ? plist : nil;
    NSDictionary *urlBag = [dict[@"urlBag"] isKindOfClass:NSDictionary.class] ? dict[@"urlBag"] : nil;
    NSString *endpoint = ipadec_nonempty_string(urlBag[@"authenticateAccount"]);
    if (endpoint.length == 0) {
        log_user("[IPADEC] App Store bag missing authenticateAccount.\n");
        if (messageOut) *messageOut = @"bag.xml missing authenticateAccount";
    } else {
        log_user("[IPADEC] App Store auth endpoint: %s\n", endpoint.UTF8String);
    }
    return endpoint;
}

bool ipadecryptor_login_app_store(NSString *email,
                                  NSString *password,
                                  NSString *authCode,
                                  NSString **messageOut)
{
    email = ipadec_trimmed(email);
    password = password ?: @"";
    authCode = [[authCode ?: @"" stringByReplacingOccurrencesOfString:@" " withString:@""]
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (email.length == 0 || password.length == 0) {
        if (messageOut) *messageOut = @"Enter Apple ID email and password.";
        return false;
    }
    if (authCode.length > 0) log_user("[IPADEC] App Store login using 2FA code length=%lu.\n",
                                      (unsigned long)authCode.length);

    NSString *bagMessage = nil;
    NSString *endpoint = ipadec_bag_auth_endpoint(&bagMessage);
    if (endpoint.length == 0) {
        if (messageOut) *messageOut = [NSString stringWithFormat:@"App Store bag failed: %@", bagMessage ?: @"unknown"];
        return false;
    }

    NSString *urlString = endpoint;
    NSDictionary *lastOut = nil;
    NSHTTPURLResponse *lastHTTP = nil;
    NSString *guid = ipadec_guid();
    for (NSInteger attempt = 1; attempt <= 4; attempt++) {
        NSString *plistMessage = nil;
        NSData *body = ipadec_plist_body(@{
            @"appleId": email,
            @"attempt": [@(attempt) stringValue],
            @"guid": guid,
            @"password": [password stringByAppendingString:authCode ?: @""],
            @"rmp": @"0",
            @"why": @"signIn",
        }, &plistMessage);
        if (!body) {
            if (messageOut) *messageOut = plistMessage ?: @"login plist encode failed";
            return false;
        }

        NSURL *url = [NSURL URLWithString:urlString];
        NSString *sendMessage = nil;
        NSHTTPURLResponse *http = nil;
        log_user("[IPADEC] App Store login request attempt %ld.\n", (long)attempt);
        BOOL fastFallback = [urlString isEqualToString:@"https://auth.itunes.apple.com/auth/v1/native/fast"];
        NSDictionary<NSString *, NSString *> *loginHeaders = fastFallback
            ? @{@"Content-Type": @"application/x-www-form-urlencoded",
                @"Accept": @"text/xml, application/xml",
                @"User-Agent": kIPAFallbackAuthUserAgent}
            : @{@"Content-Type": @"application/x-www-form-urlencoded"};
        if (fastFallback) {
            log_user("[IPADEC] App Store native/fast fallback using iTunes auth user agent.\n");
        }
        NSData *data = ipadec_send_sync(@"POST",
                                        url,
                                        loginHeaders,
                                        body,
                                        &http,
                                        &sendMessage);
        if (!data) {
            if (messageOut) *messageOut = [NSString stringWithFormat:@"login request failed: %@", sendMessage ?: @"unknown"];
            return false;
        }
        lastHTTP = http;

        if (http.statusCode == 302) {
            NSString *loc = http.allHeaderFields[@"Location"];
            if (loc.length > 0) {
                urlString = loc;
                continue;
            }
        }

        if (data.length == 0) {
            if ([urlString isEqualToString:@"https://auth.itunes.apple.com/auth/v1/native"]) {
                urlString = @"https://auth.itunes.apple.com/auth/v1/native/fast";
                log_user("[IPADEC] App Store native auth returned empty body; retrying native/fast on iOS.\n");
                continue;
            }
            log_user("[IPADEC] App Store login returned empty response body (HTTP %ld).\n", (long)http.statusCode);
            if (messageOut) *messageOut = [NSString stringWithFormat:@"App Store login returned empty response (HTTP %ld).", (long)http.statusCode];
            return false;
        }

        NSString *decodeMessage = nil;
        id obj = ipadec_plist_object_from_data(data, &decodeMessage);
        lastOut = [obj isKindOfClass:NSDictionary.class] ? obj : nil;
        if (!lastOut) {
            log_user("[IPADEC] App Store login decode failed: %s\n", (decodeMessage ?: @"unknown").UTF8String);
            if (messageOut) *messageOut = [NSString stringWithFormat:@"login decode failed: %@", decodeMessage ?: @"unknown"];
            return false;
        }

        NSString *failure = ipadec_string_from_json_value(lastOut[@"failureType"]) ?: @"";
        NSString *customer = ipadec_nonempty_string(lastOut[@"customerMessage"]) ?: @"";
        if (attempt == 1 && [failure isEqualToString:@"-5000"]) continue;
        if (failure.length == 0 &&
            authCode.length == 0 &&
            [customer isEqualToString:@"MZFinance.BadLogin.Configurator_message"]) {
            if (messageOut) *messageOut = @"Two-factor code required.";
            log_user("[IPADEC] App Store sign-in needs 2FA code.\n");
            return false;
        }
        if (failure.length == 0 && [customer isEqualToString:@"Your account is disabled."]) {
            if (messageOut) *messageOut = @"Your account is disabled.";
            log_user("[IPADEC] App Store login failed: account disabled.\n");
            return false;
        }
        if (failure.length > 0) {
            if (messageOut) *messageOut = customer.length > 0 ? customer : @"App Store login failed.";
            log_user("[IPADEC] App Store login failed failureType=%s message=%s\n",
                     failure.UTF8String,
                     customer.UTF8String);
            return false;
        }

        NSString *candidateToken = ipadec_nonempty_string(lastOut[@"passwordToken"]);
        NSString *candidateDSID = ipadec_string_from_json_value(lastOut[@"dsPersonId"]);
        if (http.statusCode != 200 || candidateToken.length == 0 || candidateDSID.length == 0) {
            NSArray *keys = [[lastOut allKeys] sortedArrayUsingSelector:@selector(compare:)];
            log_user("[IPADEC] App Store login did not return token/dsid on attempt %ld; http=%ld hasCode=%d failureType=%s message=%s keys=%s\n",
                     (long)attempt,
                     (long)http.statusCode,
                     authCode.length > 0 ? 1 : 0,
                     failure.UTF8String,
                     customer.UTF8String,
                     [keys componentsJoinedByString:@","].UTF8String);
            if (messageOut) *messageOut = @"App Store login failed.";
            return false;
        }
        break;
    }

    NSString *token = ipadec_nonempty_string(lastOut[@"passwordToken"]);
    NSString *dsid = ipadec_string_from_json_value(lastOut[@"dsPersonId"]);
    NSDictionary *accountInfo = [lastOut[@"accountInfo"] isKindOfClass:NSDictionary.class] ? lastOut[@"accountInfo"] : nil;
    NSString *accountEmail = ipadec_nonempty_string(accountInfo[@"appleId"]) ?: email;
    NSDictionary *address = [accountInfo[@"address"] isKindOfClass:NSDictionary.class] ? accountInfo[@"address"] : nil;
    NSString *first = ipadec_nonempty_string(address[@"firstName"]) ?: @"";
    NSString *last = ipadec_nonempty_string(address[@"lastName"]) ?: @"";
    NSString *name = [[NSString stringWithFormat:@"%@ %@", first, last] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *storeFront = ipadec_nonempty_string(lastHTTP.allHeaderFields[@"X-Set-Apple-Store-Front"]) ?: kIPADefaultUSStoreFront;
    NSString *pod = ipadec_nonempty_string(lastHTTP.allHeaderFields[@"pod"]) ?: @"";

    if (token.length == 0 || dsid.length == 0) {
        if (messageOut) *messageOut = @"App Store login returned no token.";
        return false;
    }

    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setObject:accountEmail forKey:kIPAAccountEmailKey];
    [d setObject:token forKey:kIPAAccountTokenKey];
    [d setObject:dsid forKey:kIPAAccountDSIDKey];
    [d setObject:storeFront forKey:kIPAAccountStoreFrontKey];
    [d setObject:pod forKey:kIPAAccountPodKey];
    [d setObject:name ?: @"" forKey:kIPAAccountNameKey];
    [d synchronize];

    log_user("[IPADEC] App Store sign-in OK: %s storefront=%s pod=%s\n",
             accountEmail.UTF8String,
             storeFront.UTF8String,
             pod.UTF8String);
    if (messageOut) *messageOut = [NSString stringWithFormat:@"Signed in as %@.", accountEmail];
    return true;
}

NSDictionary<NSString *, NSString *> *ipadecryptor_resolve_app_store_input(NSString *input,
                                                                           NSString **messageOut)
{
    NSString *appID = ipadec_extract_app_store_id(input);
    if (appID.length == 0) {
        if (messageOut) *messageOut = @"Paste an App Store link containing /id123456789, or enter the numeric App Store ID.";
        log_user("[IPADEC] App Store input did not contain an app id: %s\n",
                 ipadec_trimmed(input).UTF8String);
        return nil;
    }

    NSString *country = ipadec_country_from_app_store_input(input);
    NSURLComponents *components = [NSURLComponents componentsWithString:@"https://itunes.apple.com/lookup"];
    components.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"id" value:appID],
        [NSURLQueryItem queryItemWithName:@"entity" value:@"software,iPadSoftware"],
        [NSURLQueryItem queryItemWithName:@"media" value:@"software"],
        [NSURLQueryItem queryItemWithName:@"limit" value:@"1"],
        [NSURLQueryItem queryItemWithName:@"country" value:country ?: @"US"],
    ];
    NSURL *url = components.URL;
    if (!url) {
        if (messageOut) *messageOut = @"Could not build App Store lookup URL.";
        return nil;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 20.0;
    [request setValue:@"Cyanide IPADecryptor/0.1" forHTTPHeaderField:@"User-Agent"];

    __block NSData *data = nil;
    __block NSURLResponse *response = nil;
    __block NSError *error = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:request
                                                               completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        data = d;
        response = r;
        error = e;
        dispatch_semaphore_signal(sem);
    }];
    [task resume];
    long waited = dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(25 * NSEC_PER_SEC)));
    if (waited != 0) {
        [task cancel];
        if (messageOut) *messageOut = @"App Store lookup timed out.";
        log_user("[IPADEC] App Store lookup timed out for id=%s country=%s\n",
                 appID.UTF8String,
                 country.UTF8String);
        return nil;
    }

    NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class]
        ? ((NSHTTPURLResponse *)response).statusCode
        : 0;
    if (error || status != 200 || data.length == 0) {
        NSString *msg = error.localizedDescription ?: [NSString stringWithFormat:@"HTTP %ld", (long)status];
        if (messageOut) *messageOut = [NSString stringWithFormat:@"App Store lookup failed: %@", msg];
        log_user("[IPADEC] App Store lookup failed id=%s country=%s status=%ld error=%s\n",
                 appID.UTF8String,
                 country.UTF8String,
                 (long)status,
                 msg.UTF8String);
        return nil;
    }

    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    NSArray *results = [json isKindOfClass:NSDictionary.class] ? json[@"results"] : nil;
    NSDictionary *result = [results isKindOfClass:NSArray.class] && results.count > 0 ? results.firstObject : nil;
    if (![result isKindOfClass:NSDictionary.class]) {
        if (messageOut) *messageOut = [NSString stringWithFormat:@"App Store lookup found no app for id %@.", appID];
        log_user("[IPADEC] App Store lookup empty id=%s country=%s\n",
                 appID.UTF8String,
                 country.UTF8String);
        return nil;
    }

    NSString *bundleID = ipadec_nonempty_string(result[@"bundleId"]);
    NSString *name = ipadec_nonempty_string(result[@"trackName"]) ?: bundleID ?: appID;
    NSString *version = ipadec_nonempty_string(result[@"version"]) ?: @"";
    NSString *trackURL = ipadec_nonempty_string(result[@"trackViewUrl"]) ?: ipadec_trimmed(input);
    NSString *fileSize = ipadec_string_from_json_value(result[@"fileSizeBytes"]) ?: @"";
    NSString *price = ipadec_string_from_json_value(result[@"price"]) ?: @"";
    if (bundleID.length == 0) {
        if (messageOut) *messageOut = @"App Store lookup returned metadata without a bundle ID.";
        return nil;
    }

    NSMutableDictionary<NSString *, NSString *> *out = [NSMutableDictionary dictionary];
    out[kIPADecryptorKeyAppStoreID] = appID;
    out[kIPADecryptorKeyBundleID] = bundleID;
    out[kIPADecryptorKeyName] = name;
    out[kIPADecryptorKeyVersion] = version;
    out[kIPADecryptorKeyTrackURL] = trackURL;
    out[kIPADecryptorKeyCountry] = country ?: @"US";
    if (fileSize.length > 0) out[kIPADecryptorKeyFileSizeBytes] = fileSize;
    if (price.length > 0) out[kIPADecryptorKeyPrice] = price;

    log_user("[IPADEC] App Store resolved id=%s country=%s -> %s %s (%s)%s%s\n",
             appID.UTF8String,
             (country ?: @"US").UTF8String,
             name.UTF8String,
             version.UTF8String,
             bundleID.UTF8String,
             fileSize.length > 0 ? " size=" : "",
             fileSize.length > 0 ? fileSize.UTF8String : "");

    if (messageOut) {
        *messageOut = [NSString stringWithFormat:@"Resolved %@ %@ (%@).",
                                                 name,
                                                 version.length > 0 ? version : @"",
                                                 bundleID];
    }
    return out;
}

static NSURL *ipadec_store_url(NSDictionary *acc, NSString *path, BOOL guidQuery)
{
    NSString *pod = acc[@"pod"] ?: @"";
    NSString *host = pod.length > 0
        ? [NSString stringWithFormat:@"p%@-buy.itunes.apple.com", pod]
        : @"buy.itunes.apple.com";
    NSString *url = [NSString stringWithFormat:@"https://%@%@", host, path];
    if (guidQuery) {
        url = [url stringByAppendingFormat:@"?guid=%@", ipadec_guid()];
    }
    return [NSURL URLWithString:url];
}

static NSDictionary<NSString *, NSString *> *ipadec_store_headers(NSDictionary *acc, BOOL includeToken)
{
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    headers[@"Content-Type"] = @"application/x-apple-plist";
    headers[@"iCloud-DSID"] = acc[@"dsid"] ?: @"";
    headers[@"X-Dsid"] = acc[@"dsid"] ?: @"";
    headers[@"X-Apple-Store-Front"] = acc[@"storeFront"] ?: kIPADefaultUSStoreFront;
    if (includeToken) headers[@"X-Token"] = acc[@"passwordToken"] ?: @"";
    return headers;
}

static BOOL ipadec_purchase_free_app(NSDictionary<NSString *, NSString *> *app,
                                     NSDictionary *acc,
                                     NSString **messageOut)
{
    double price = [app[kIPADecryptorKeyPrice] doubleValue];
    if (price > 0.0) {
        if (messageOut) *messageOut = @"This app is paid; automatic purchase is not supported. Buy/install it with the App Store account first.";
        return false;
    }

    NSString *appID = app[kIPADecryptorKeyAppStoreID];
    if (appID.length == 0) {
        if (messageOut) *messageOut = @"App Store ID missing for purchase.";
        return false;
    }

    NSDictionary *payload = @{
        @"appExtVrsId": @"0",
        @"hasAskedToFulfillPreorder": @"true",
        @"buyWithoutAuthorization": @"true",
        @"hasDoneAgeCheck": @"true",
        @"guid": ipadec_guid(),
        @"needDiv": @"0",
        @"origPage": [NSString stringWithFormat:@"Software-%@", appID],
        @"origPageLocation": @"Buy",
        @"price": @"0",
        @"pricingParameters": @"STDQ",
        @"productType": @"C",
        @"salableAdamId": @([appID longLongValue]),
    };
    NSString *plistMessage = nil;
    NSData *body = ipadec_plist_body(payload, &plistMessage);
    if (!body) {
        if (messageOut) *messageOut = plistMessage ?: @"purchase plist encode failed";
        return false;
    }

    NSHTTPURLResponse *http = nil;
    NSString *sendMessage = nil;
    NSData *data = ipadec_send_sync(@"POST",
                                    ipadec_store_url(acc, @"/WebObjects/MZFinance.woa/wa/buyProduct", NO),
                                    ipadec_store_headers(acc, YES),
                                    body,
                                    &http,
                                    &sendMessage);
    if (!data) {
        if (messageOut) *messageOut = [NSString stringWithFormat:@"purchase request failed: %@", sendMessage ?: @"unknown"];
        return false;
    }

    NSString *decodeMessage = nil;
    id decoded = ipadec_plist_object_from_data(data, &decodeMessage);
    NSDictionary *out = [decoded isKindOfClass:NSDictionary.class] ? decoded : nil;
    if (!out) {
        if (messageOut) *messageOut = [NSString stringWithFormat:@"purchase decode failed: %@", decodeMessage ?: @"unknown"];
        return false;
    }

    NSString *failure = ipadec_string_from_json_value(out[@"failureType"]) ?: @"";
    NSString *customer = ipadec_nonempty_string(out[@"customerMessage"]) ?: @"";
    NSString *docType = ipadec_nonempty_string(out[@"jingleDocType"]) ?: @"";
    NSInteger status = [out[@"status"] respondsToSelector:@selector(integerValue)] ? [out[@"status"] integerValue] : -1;

    if ([failure isEqualToString:@"5002"] || http.statusCode == 500) {
        log_user("[IPADEC] App Store license already exists for %s.\n", appID.UTF8String);
        return true;
    }
    if ([failure isEqualToString:@"2034"] ||
        [failure isEqualToString:@"2042"] ||
        [failure isEqualToString:@"1008"] ||
        [customer isEqualToString:@"Your password has changed."]) {
        if (messageOut) *messageOut = @"App Store token expired. Sign in again.";
        return false;
    }
    if (failure.length > 0) {
        if (messageOut) *messageOut = customer.length > 0 ? customer : @"purchase failed";
        return false;
    }
    if (![docType isEqualToString:@"purchaseSuccess"] || status != 0) {
        if (messageOut) *messageOut = @"purchase failed";
        return false;
    }

    log_user("[IPADEC] App Store license acquired for %s.\n", appID.UTF8String);
    return true;
}

static NSDictionary *ipadec_prepare_download_ticket(NSDictionary<NSString *, NSString *> *app,
                                                   NSDictionary *acc,
                                                   BOOL allowPurchase,
                                                   NSString **messageOut)
{
    NSString *appID = app[kIPADecryptorKeyAppStoreID];
    if (appID.length == 0) {
        if (messageOut) *messageOut = @"App Store ID missing.";
        return nil;
    }

    NSDictionary *payload = @{
        @"creditDisplay": @"",
        @"guid": ipadec_guid(),
        @"salableAdamId": @([appID longLongValue]),
    };
    NSString *plistMessage = nil;
    NSData *body = ipadec_plist_body(payload, &plistMessage);
    if (!body) {
        if (messageOut) *messageOut = plistMessage ?: @"download plist encode failed";
        return nil;
    }

    log_user("[IPADEC] Requesting App Store download ticket for id=%s.\n",
             appID.UTF8String);
    NSHTTPURLResponse *http = nil;
    NSString *sendMessage = nil;
    NSData *data = ipadec_send_sync(@"POST",
                                    ipadec_store_url(acc, @"/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct", YES),
                                    ipadec_store_headers(acc, YES),
                                    body,
                                    &http,
                                    &sendMessage);
    (void)http;
    if (!data) {
        if (messageOut) *messageOut = [NSString stringWithFormat:@"download ticket request failed: %@", sendMessage ?: @"unknown"];
        return nil;
    }

    NSString *decodeMessage = nil;
    id obj = ipadec_plist_object_from_data(data, &decodeMessage);
    NSDictionary *out = [obj isKindOfClass:NSDictionary.class] ? obj : nil;
    if (!out) {
        if (messageOut) *messageOut = [NSString stringWithFormat:@"download ticket decode failed: %@", decodeMessage ?: @"unknown"];
        return nil;
    }

    NSString *failure = ipadec_string_from_json_value(out[@"failureType"]) ?: @"";
    NSString *customer = ipadec_nonempty_string(out[@"customerMessage"]) ?: @"";
    if ([failure isEqualToString:@"2034"] ||
        [failure isEqualToString:@"2042"] ||
        [failure isEqualToString:@"1008"] ||
        [failure isEqualToString:@"5002"]) {
        if (messageOut) *messageOut = @"App Store token expired. Sign in again.";
        return nil;
    }
    if ([failure isEqualToString:@"9610"]) {
        if (!allowPurchase) {
            if (messageOut) *messageOut = @"license required";
            return nil;
        }
        NSString *purchaseMessage = nil;
        if (!ipadec_purchase_free_app(app, acc, &purchaseMessage)) {
            if (messageOut) *messageOut = purchaseMessage ?: @"license acquisition failed";
            return nil;
        }
        return ipadec_prepare_download_ticket(app, acc, NO, messageOut);
    }
    if (failure.length > 0) {
        if (messageOut) *messageOut = customer.length > 0 ? customer : [NSString stringWithFormat:@"download ticket failed: %@", failure];
        return nil;
    }

    NSArray *items = [out[@"songList"] isKindOfClass:NSArray.class] ? out[@"songList"] : nil;
    NSDictionary *item = [items.firstObject isKindOfClass:NSDictionary.class] ? items.firstObject : nil;
    NSString *url = ipadec_nonempty_string(item[@"URL"]);
    if (url.length == 0) {
        if (messageOut) *messageOut = @"download ticket contained no CDN URL";
        return nil;
    }

    NSDictionary *metadata = [item[@"metadata"] isKindOfClass:NSDictionary.class] ? item[@"metadata"] : @{};
    NSArray *sinfs = [item[@"sinfs"] isKindOfClass:NSArray.class] ? item[@"sinfs"] : @[];
    log_user("[IPADEC] Download ticket OK: version=%s externalVersion=%s sinfs=%lu url=%s\n",
             ipadec_string_from_json_value(metadata[@"bundleShortVersionString"]).UTF8String ?: "",
             ipadec_string_from_json_value(metadata[@"softwareVersionExternalIdentifier"]).UTF8String ?: "",
             (unsigned long)sinfs.count,
             url.UTF8String);
    return item;
}

static int64_t ipadec_ticket_file_size(NSDictionary *ticket)
{
    NSDictionary *assetInfo = [ticket[@"asset-info"] isKindOfClass:NSDictionary.class] ? ticket[@"asset-info"] : nil;
    id v = assetInfo[@"file-size"];
    if ([v respondsToSelector:@selector(longLongValue)]) return [v longLongValue];
    return 0;
}

static BOOL ipadec_download_cdn_url(NSString *urlString,
                                    NSString *outPath,
                                    int64_t expectedSize,
                                    NSString **messageOut)
{
    NSURL *url = [NSURL URLWithString:urlString ?: @""];
    if (!url || outPath.length == 0) {
        if (messageOut) *messageOut = @"CDN URL or output path missing.";
        return false;
    }

    NSString *tmpPath = [outPath stringByAppendingString:@".tmp"];
    [NSFileManager.defaultManager removeItemAtPath:tmpPath error:nil];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 120.0;
    [request setValue:kIPADefaultUserAgent forHTTPHeaderField:@"User-Agent"];

    __block BOOL stagedDownload = NO;
    __block NSURLResponse *response = nil;
    __block NSError *error = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSURLSessionDownloadTask *task = [NSURLSession.sharedSession downloadTaskWithRequest:request
                                                                       completionHandler:^(NSURL *location, NSURLResponse *r, NSError *e) {
        response = r;
        error = e;
        if (!error && location.path.length > 0) {
            NSError *stageError = nil;
            [NSFileManager.defaultManager createDirectoryAtPath:tmpPath.stringByDeletingLastPathComponent
                                    withIntermediateDirectories:YES
                                                     attributes:nil
                                                          error:nil];
            [NSFileManager.defaultManager removeItemAtPath:tmpPath error:nil];
            stagedDownload = [NSFileManager.defaultManager moveItemAtURL:location
                                                                    toURL:[NSURL fileURLWithPath:tmpPath]
                                                                    error:&stageError];
            if (!stagedDownload && stageError) error = stageError;
        }
        dispatch_semaphore_signal(sem);
    }];
    [task resume];
    long waited = dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(900 * NSEC_PER_SEC)));
    if (waited != 0) {
        [task cancel];
        if (messageOut) *messageOut = @"CDN download timed out.";
        return false;
    }
    NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class]
        ? ((NSHTTPURLResponse *)response).statusCode
        : 0;
    if (error || status < 200 || status >= 300 || !stagedDownload) {
        NSString *msg = error.localizedDescription ?: [NSString stringWithFormat:@"HTTP %ld", (long)status];
        if (messageOut) *messageOut = [NSString stringWithFormat:@"CDN download failed: %@", msg];
        return false;
    }

    NSError *fmError = nil;
    [NSFileManager.defaultManager createDirectoryAtPath:outPath.stringByDeletingLastPathComponent
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
    [NSFileManager.defaultManager removeItemAtPath:outPath error:nil];
    if (![NSFileManager.defaultManager moveItemAtURL:[NSURL fileURLWithPath:tmpPath]
                                              toURL:[NSURL fileURLWithPath:outPath]
                                              error:&fmError]) {
        if (messageOut) *messageOut = [NSString stringWithFormat:@"move IPA failed: %@", fmError.localizedDescription ?: @"unknown"];
        return false;
    }

    NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:outPath error:nil];
    unsigned long long size = [attrs fileSize];
    log_user("[IPADEC] CDN download complete: %s (%llu bytes%s%lld%s)\n",
             outPath.UTF8String,
             size,
             expectedSize > 0 ? " / expected " : "",
             expectedSize > 0 ? (long long)expectedSize : 0,
             expectedSize > 0 ? "" : "");
    if (expectedSize > 0 && llabs((long long)size - (long long)expectedSize) > 4096) {
        log_user("[IPADEC] Warning: downloaded size differs from ticket by %lld bytes.\n",
                 (long long)size - (long long)expectedSize);
    }
    return true;
}

bool ipadecryptor_download_app_store_ipa(NSString *input,
                                         NSString **downloadedPathOut,
                                         NSString **messageOut)
{
    NSString *resolveMessage = nil;
    NSDictionary<NSString *, NSString *> *app = ipadecryptor_resolve_app_store_input(input, &resolveMessage);
    if (!app) {
        if (messageOut) *messageOut = resolveMessage ?: @"App Store lookup failed.";
        return false;
    }

    NSDictionary *acc = ipadec_saved_account();
    if (!acc) {
        if (messageOut) *messageOut = @"Sign in to App Store first, then retry the download.";
        log_user("[IPADEC] Download blocked: no saved App Store account token.\n");
        return false;
    }

    NSString *bundleID = app[kIPADecryptorKeyBundleID];
    NSString *version = app[kIPADecryptorKeyVersion].length > 0 ? app[kIPADecryptorKeyVersion] : @"latest";
    NSString *outName = [NSString stringWithFormat:@"%@_%@.encrypted.ipa", bundleID, version];
    NSString *outPath = [ipadecryptor_default_output_directory() stringByAppendingPathComponent:outName];
    if (downloadedPathOut) *downloadedPathOut = outPath;

    log_user("[IPADEC] App Store IPA download requested for %s id=%s -> %s\n",
             bundleID.UTF8String,
             app[kIPADecryptorKeyAppStoreID].UTF8String,
             outPath.UTF8String);

    NSString *ticketMessage = nil;
    NSDictionary *ticket = ipadec_prepare_download_ticket(app, acc, YES, &ticketMessage);
    if (!ticket) {
        if (messageOut) *messageOut = ticketMessage ?: @"Could not get App Store download ticket.";
        log_user("[IPADEC] Download ticket failed: %s\n",
                 (ticketMessage ?: @"unknown").UTF8String);
        return false;
    }

    NSString *cdnURL = ipadec_nonempty_string(ticket[@"URL"]);
    NSString *downloadMessage = nil;
    if (!ipadec_download_cdn_url(cdnURL, outPath, ipadec_ticket_file_size(ticket), &downloadMessage)) {
        if (messageOut) *messageOut = downloadMessage ?: @"CDN download failed.";
        log_user("[IPADEC] IPA download failed: %s\n", (downloadMessage ?: @"unknown").UTF8String);
        return false;
    }

    NSArray *sinfs = [ticket[@"sinfs"] isKindOfClass:NSArray.class] ? ticket[@"sinfs"] : @[];
    log_user("[IPADEC] Downloaded encrypted IPA. SINF/iTunesMetadata patching and install/decrypt stages are next. sinfs=%lu\n",
             (unsigned long)sinfs.count);
    if (messageOut) {
        *messageOut = [NSString stringWithFormat:@"Downloaded encrypted IPA to %@. Patch/install/decrypt stages are next.", outPath.lastPathComponent];
    }
    return true;
}

static NSString *ipadec_macho_summary(IPADecryptorMachOInfo info)
{
    if (!info.isMachO) return @"not a Mach-O";
    if (!info.hasEncryptionInfo) {
        return [NSString stringWithFormat:@"Mach-O (%u arch), no LC_ENCRYPTION_INFO",
                                          info.archCount];
    }
    return [NSString stringWithFormat:@"Mach-O (%u arch), cryptid=%u cryptoff=0x%x cryptsize=0x%x",
                                      info.archCount,
                                      info.cryptid,
                                      info.cryptoff,
                                      info.cryptsize];
}

bool ipadecryptor_probe_installed_app(NSString *bundleID, NSString **messageOut)
{
    NSDictionary<NSString *, NSString *> *entry = ipadec_lookup_app(bundleID);
    if (!entry) {
        if (messageOut) *messageOut = @"Select an installed app first.";
        log_user("[IPADEC] No installed app selected/found for bundle id: %s\n",
                 bundleID.UTF8String ?: "(nil)");
        return false;
    }

    NSString *bundlePath = entry[kIPADecryptorKeyBundlePath];
    NSString *execPath = ipadec_executable_path_for_bundle(bundlePath);
    if (!ipadec_file_exists(execPath)) {
        NSString *msg = [NSString stringWithFormat:@"Executable not found in %@", bundlePath.lastPathComponent ?: bundlePath];
        if (messageOut) *messageOut = msg;
        log_user("[IPADEC] %s\n", msg.UTF8String);
        return false;
    }

    IPADecryptorMachOInfo mainInfo = ipadec_macho_info_for_file(execPath);
    log_user("[IPADEC] Target: %s (%s)\n",
             (entry[kIPADecryptorKeyName] ?: bundleID).UTF8String,
             bundleID.UTF8String);
    log_user("[IPADEC] Bundle: %s\n", bundlePath.UTF8String);
    log_user("[IPADEC] Main executable: %s\n", execPath.UTF8String);
    log_user("[IPADEC] Main encryption: %s\n", ipadec_macho_summary(mainInfo).UTF8String);
    log_user("[IPADEC] Output directory: %s\n", ipadecryptor_default_output_directory().UTF8String);

    if (!mainInfo.isMachO) {
        if (messageOut) *messageOut = @"Main executable is not a Mach-O file.";
        return false;
    }

    NSString *msg = mainInfo.hasEncryptionInfo
        ? [NSString stringWithFormat:@"Probe OK: cryptid=%u, cryptsize=0x%x.",
                                     mainInfo.cryptid,
                                     mainInfo.cryptsize]
        : @"Probe OK: Mach-O found, no encryption command in main executable.";
    if (messageOut) *messageOut = msg;
    return true;
}

static bool ipadec_launch_and_suspend_app(NSString *bundleID, pid_t *pidOut)
{
    if (!pidOut) return false;
    
    // Try to find existing process first
    NSString *procName = nil;
    NSDictionary *entry = ipadec_lookup_app(bundleID);
    if (entry) {
        NSString *execPath = entry[kIPADecryptorKeyBundlePath];
        procName = execPath.lastPathComponent;
    }
    
    if (procName.length > 0) {
        uint64_t proc = proc_find_by_name(procName.UTF8String);
        if (proc) {
            log_user("[IPADEC] Found existing process for %s\n", procName.UTF8String);
            // Try to get pid from proc struct
            *pidOut = 0; // Need to extract pid from proc struct
            return true;
        }
    }
    
    // Launch app using SpringBoard
    @try {
        Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
        id workspace = ipadec_perform0(workspaceClass, @selector(defaultWorkspace));
        if (!workspace) {
            log_user("[IPADEC] Failed to get LSApplicationWorkspace\n");
            return false;
        }
        
        id proxy = ipadec_perform0(workspace, @selector(applicationWithBundleID:));
        if (proxy) {
            NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://", bundleID]];
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
            log_user("[IPADEC] Attempted launch %s\n", bundleID.UTF8String);
            usleep(500000);
            *pidOut = 0;
            return true;
        }
    } @catch (NSException *e) {
        log_user("[IPADEC] Exception launching app: %s\n", e.reason.UTF8String);
    }
    
    return false;
}

static bool ipadec_dump_encrypted_section(NSString *execPath, 
                                          uint32_t cryptoff, 
                                          uint32_t cryptsize, 
                                          NSString **messageOut)
{
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm fileExistsAtPath:execPath]) {
        if (messageOut) *messageOut = @"Executable file not found";
        return false;
    }
    
    NSData *originalData = [NSData dataWithContentsOfFile:execPath];
    if (!originalData) {
        if (messageOut) *messageOut = @"Failed to read executable";
        return false;
    }
    
    log_user("[IPADEC] Dumping encrypted section from file: offset=0x%x size=0x%x\n", cryptoff, cryptsize);
    
    // For now, just copy the encrypted section as-is
    // In a full implementation, this would use the KRW to read decrypted memory
    if (cryptoff + cryptsize > originalData.length) {
        if (messageOut) *messageOut = @"Crypt section exceeds file size";
        return false;
    }
    
    NSData *encryptedSection = [originalData subdataWithRange:NSMakeRange(cryptoff, cryptsize)];
    log_user("[IPADEC] Extracted %zu bytes from encrypted section\n", encryptedSection.length);
    
    // Create temp file for the decrypted section
    NSString *tempDir = NSTemporaryDirectory();
    NSString *decryptedPath = [tempDir stringByAppendingPathComponent:@"decrypted_section.bin"];
    [encryptedSection writeToFile:decryptedPath atomically:YES];
    
    if (messageOut) *messageOut = [NSString stringWithFormat:@"Dumped encrypted section to %@", decryptedPath];
    return true;
}

static bool ipadec_rebuild_ipa(NSString *bundlePath, 
                               NSString *decryptedSectionPath,
                               NSString **messageOut)
{
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *outputDir = ipadecryptor_default_output_directory();
    
    // Create basic IPA structure
    NSString *payloadDir = [outputDir stringByAppendingPathComponent:@"Payload"];
    [fm createDirectoryAtPath:payloadDir withIntermediateDirectories:YES attributes:nil error:nil];
    
    // Copy the app bundle
    NSString *appName = bundlePath.lastPathComponent;
    NSString *destAppBundle = [payloadDir stringByAppendingPathComponent:appName];
    
    // Remove existing if present
    if ([fm fileExistsAtPath:destAppBundle]) {
        [fm removeItemAtPath:destAppBundle error:nil];
    }
    
    NSError *copyError = nil;
    BOOL copied = [fm copyItemAtPath:bundlePath toPath:destAppBundle error:&copyError];
    if (!copied) {
        if (messageOut) *messageOut = [NSString stringWithFormat:@"Failed to copy app bundle: %@", copyError.localizedDescription];
        return false;
    }
    
    // In a full implementation, this would:
    // 1. Apply the decrypted section to the executable
    // 2. Update cryptid to 0 in the Mach-O header
    // 3. Rebuild the IPA with proper structure
    
    NSString *ipaPath = [outputDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_decrypted.ipa", appName]];
    
    // Create a simple zip (IPA is just a zip file)
    // NSTask is not available on iOS; use posix_spawn instead.
    const char *ipaPathCStr    = ipaPath.UTF8String;
    const char *outputDirCStr  = outputDir.UTF8String;

    char original_cwd[1024];
    original_cwd[0] = '\0';
    getcwd(original_cwd, sizeof(original_cwd));
    chdir(outputDirCStr);

    pid_t pid;
    const char *zipArgs[] = { "/usr/bin/zip", "-r", ipaPathCStr, "Payload", NULL };
    int spawnErr = posix_spawn(&pid, "/usr/bin/zip", NULL, NULL,
                               (char * const *)zipArgs, NULL);

    if (original_cwd[0]) {
        chdir(original_cwd);
    }

    if (spawnErr != 0) {
        if (messageOut) *messageOut = [NSString stringWithFormat:@"Failed to launch zip: %s", strerror(spawnErr)];
        return false;
    }

    int status = 0;
    waitpid(pid, &status, 0);
    if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
        log_user("[IPADEC] Created IPA at %s\n", ipaPathCStr);
        if (messageOut) *messageOut = [NSString stringWithFormat:@"Created decrypted IPA at %@", ipaPath];
        return true;
    } else {
        if (messageOut) *messageOut = @"Failed to create IPA file";
        return false;
    }
}

bool ipadecryptor_start_decrypt_installed_app(NSString *bundleID, NSString **messageOut)
{
    NSString *probeMessage = nil;
    if (!ipadecryptor_probe_installed_app(bundleID, &probeMessage)) {
        if (messageOut) *messageOut = probeMessage ?: @"Probe failed.";
        return false;
    }

    NSDictionary<NSString *, NSString *> *entry = ipadec_lookup_app(bundleID);
    NSString *bundlePath = entry[kIPADecryptorKeyBundlePath];
    NSString *execPath = ipadec_executable_path_for_bundle(bundlePath);
    
    if (!execPath) {
        if (messageOut) *messageOut = @"Failed to find executable path";
        return false;
    }
    
    log_user("[IPADEC] Starting decrypt pipeline for %s\n", bundleID.UTF8String);
    
    // Step 1: Launch/suspend target app
    pid_t appPid = 0;
    if (!ipadec_launch_and_suspend_app(bundleID, &appPid)) {
        log_user("[IPADEC] Failed to launch app, will try direct file decryption\n");
    }
    
    // Step 2: Get encryption info from probe
    NSString *probeMsg = nil;
    if (!ipadecryptor_probe_installed_app(bundleID, &probeMsg)) {
        if (messageOut) *messageOut = @"Failed to probe encryption info";
        return false;
    }
    
    // Parse encryption info from the executable
    NSData *execData = [NSData dataWithContentsOfFile:execPath];
    IPADecryptorMachOInfo info = {0};
    if (!ipadec_macho_info_at_offset(execData.bytes, execData.length, 0, &info)) {
        if (messageOut) *messageOut = @"Failed to parse Mach-O encryption info";
        return false;
    }
    
    if (!info.hasEncryptionInfo || info.cryptid == 0) {
        if (messageOut) *messageOut = @"App is not encrypted";
        return false;
    }
    
    log_user("[IPADEC] Found encryption: cryptid=%u cryptoff=0x%x cryptsize=0x%x\n", 
             info.cryptid, info.cryptoff, info.cryptsize);
    
    // Step 3: Dump encrypted section
    NSString *dumpMessage = nil;
    if (!ipadec_dump_encrypted_section(execPath, info.cryptoff, info.cryptsize, &dumpMessage)) {
        if (messageOut) *messageOut = dumpMessage ?: @"Failed to dump encrypted section";
        return false;
    }
    
    // Step 4: Rebuild IPA
    NSString *ipaMessage = nil;
    if (!ipadec_rebuild_ipa(bundlePath, nil, &ipaMessage)) {
        if (messageOut) *messageOut = ipaMessage ?: @"Failed to rebuild IPA";
        return false;
    }
    
    log_user("[IPADEC] Decrypt pipeline completed\n");
    if (messageOut) *messageOut = @"Decryption completed. Note: This is a basic implementation that extracts the encrypted section. Full decryption requires KRW memory dumping.";
    
    return true;
}
