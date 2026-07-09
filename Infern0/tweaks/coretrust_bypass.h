#ifndef coretrust_bypass_h
#define coretrust_bypass_h

#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>
#include <fcntl.h>

extern char g_crash_log_path[4096];

const char *coretrust_write_test_binary(void);

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

// ── Strategy 6: TXM bypass (enhanced) ───────────────────────────────────
// Comprehensive IOKit brute-force: tries user client types 0-2, selectors
// 0-15 with IOConnectCallStructMethod and IOConnectCallMethod to find the
// TXM trust cache load selector.

bool coretrust_txm_bypass(void);

// ── XPC to MSM ──────────────────────────────────────────────────────────
// Send trust cache request via XPC to the MSM daemon (MobileStorageMounter).
// This is a cleaner alternative to RemoteCall, uses the standard XPC
// protocol for interdaemon communication, and is safe on SPTM devices.

bool coretrust_xpc_to_msm(void);

// ── Unified entry point ─────────────────────────────────────────────────
// Run all strategies in sequence; returns true if unsigned execution is
// verified.

bool coretrust_bypass_all(void);

#endif
