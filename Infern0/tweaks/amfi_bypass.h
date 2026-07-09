#ifndef amfi_bypass_h
#define amfi_bypass_h

#include <stdint.h>
#include <stdbool.h>

// ── Exploit name ──────────────────────────────────────────────────────────
#define AMFI_BYPASS_EXPLOIT_NAME    "Entitle"
#define AMFI_BYPASS_EXPLOIT_VERSION "1.0"
// ───────────────────────────────────────────────────────────────────────────

// Patch the current process's AMFI OSEntitlements state to mark it as a
// valid platform binary. This can enable loading unsigned dylibs via dlopen
// without a full kPAC/PPL bypass.
//
// Returns true on success, false on failure.
bool amfi_patch_self(void);

// Patch a specific process (kernel proc pointer) the same way.
bool amfi_patch_proc(uint64_t proc);

// Convenience: patch self, then attempt dlopen of the given path.
// Returns the dlopen handle (non-NULL) on success, or NULL.
void *amfi_try_load_dylib(const char *path);

// Debug dump of our process's AMFI state.
void amfi_dump_self(void);

#endif
