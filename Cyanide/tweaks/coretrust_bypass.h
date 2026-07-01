#ifndef coretrust_bypass_h
#define coretrust_bypass_h

#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>
#include <fcntl.h>

extern char g_crash_log_path[4096];

#define CORETRUST_BYPASS_EXPLOIT_NAME    "COREbreak"
#define CORETRUST_BYPASS_EXPLOIT_VERSION "1.0"

// ── Strategy 1: amfid NOP patch ──────────────────────────────────────────
// Find amfid's `cbz w22, ...` instruction at file offset 0x2ec8 and NOP it.
// This makes MISValidateSignatureAndCopyInfo always return success.
// Returns true if the patch was applied.

bool coretrust_amfid_nop_patch(void);

// ── Strategy 2: AMFI enforcement flags ──────────────────────────────────
// Zero AMFI enforcement booleans in kernel memory (cs_enforcement_disable
// and up to 10 other flags in AMFI __DATA). Requires known kernel offsets.
// Returns true if any flag was successfully zeroed.

bool coretrust_amfi_enforcement_flags_zero(void);

// ── Strategy 3: amfid kill + execution race ────────────────────────────
// Kill amfid and immediately attempt to spawn a test binary before the
// watchdog respawns it. Returns true if the binary executed.

bool coretrust_kill_amfid_race(const char *testBinPath);

// ── Test binary ─────────────────────────────────────────────────────────
// Must be called BEFORE the kernel exploit corrupts socket structures.
// Returns path (caller must free) or NULL on failure.
const char *coretrust_write_test_binary(void);

// ── Unified entry point ─────────────────────────────────────────────────
// Run all strategies in sequence; returns true if unsigned execution is
// verified.

bool coretrust_bypass_all(void);

#endif
