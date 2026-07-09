#ifndef msm_trustcache_h
#define msm_trustcache_h

#include <stdint.h>
#include <stdbool.h>

// ── Exploit name ──────────────────────────────────────────────────────────
#define MSM_TRUSTCACHE_EXPLOIT_NAME    "MountCache"
#define MSM_TRUSTCACHE_EXPLOIT_VERSION "1.0"
// ───────────────────────────────────────────────────────────────────────────

// Trust cache v2 entry / module struct (from XNU trustcache.h)
#define CS_CDHASH_LEN 20

struct trust_cache_entry {
    uint8_t  cdhash[CS_CDHASH_LEN];
    uint8_t  hash_type;
    uint8_t  flags;
} __attribute__((packed));

struct trust_cache_module {
    uint32_t version;
    uint8_t  uuid[16];
    uint32_t num_entries;
    struct trust_cache_entry entries[];
} __attribute__((packed));

// Build a trust cache v2 binary containing the CDHash for a given Mach-O.
// Returns a heap-allocated buffer (caller must free) and sets outSize.
uint8_t *msm_build_trust_cache(const uint8_t *cdhash, size_t cdhash_len, size_t *outSize);

// Compute a SHA256 CDHash (truncated to 20 bytes) for a Mach-O at `path`.
// Returns a heap-allocated 20-byte buffer or NULL on error.
uint8_t *msm_compute_cdhash(const char *path);

// Write a minimal unsigned arm64 Mach-O that calls exit(0) to `path`.
// Returns true on success.
bool msm_write_test_binary(const char *path);

// Main entry point: connect to MobileStorageMounter via RemoteCall and
// load a trust cache file. Returns true on success.
bool msm_inject_trust_cache(const char *tcPath);

// Convenience: build trust cache, inject via MSM, then spawn test binary.
// Returns true if the test binary spawned successfully.
bool msm_verify_unsigned_execution(void);

#endif
