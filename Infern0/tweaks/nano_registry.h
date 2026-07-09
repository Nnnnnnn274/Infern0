//
//  nano_registry.h
//  Backwards-compatibility override for Apple Watch pairing gates that
//  NRPairingCompatibilityVersionInfo reads from
//  /var/mobile/Library/Preferences/com.apple.NanoRegistry.plist.
//

#ifndef nano_registry_h
#define nano_registry_h

#import <stdbool.h>

// Pairing limits stored by NanoRegistry. The app preset uses max_pairing=99
// to raise the watchOS pairing ceiling and min_pairing=23 to keep
// generation-23 setup messages accepted.
typedef struct {
    int max_pairing;            // maxPairingCompatibilityVersion
    int min_pairing;            // minPairingCompatibilityVersion
    int min_pairing_chip_id;    // minPairingCompatibilityVersionWithChipID
    int min_quick_switch;       // minQuickSwitchCompatibilityVersion
} nano_registry_values;

// Reads the four NanoRegistry compatibility keys from disk.
// `out_present` is set to true when at least one of the keys exists in the
// plist (i.e. an override has previously been applied). Missing keys are
// left at the caller-supplied default in *out_values, so callers can
// pre-fill with sane defaults before invoking.
// Returns true on success (plist read or missing-and-treated-as-empty),
// false only on I/O / parse failure with the file present.
bool nano_registry_load(nano_registry_values *out_values, bool *out_present);

// Writes the four keys to com.apple.NanoRegistry.plist atomically.
// Sandbox patch is applied internally if needed (kexploit must have run).
// Returns true on success.
bool nano_registry_apply(const nano_registry_values *values);

// Removes the four override keys. Leaves any unrelated keys (Apple may
// store other state in the same plist) untouched. Returns true on success
// or when there is nothing to clear.
bool nano_registry_clear(void);

// Data-only diagnostic for the next pairing gate: logs NanoRegistry/Bridge
// MobileAsset and ProductKit cache state without touching executable pages.
// Requires KRW only so the app can get enough /private/var read access.
bool nano_registry_probe_pairing_assets(void);

// Runtime-only product steering for newer Watch7 hardware. Uses RemoteCall
// into already-running Bridge/NanoRegistry processes and normal NRDevice
// setters to alias unknown Watch7 product types to a known Ultra product
// type. No dlopen and no executable-page patching.
bool nano_registry_steer_new_watch_product_alias(void);

// Data-only compatibility-index seed. Adds the current phone product type
// (e.g. iPhone17,2) to NanoRegistryPairingCompatibilityIndex.plist's iPhone
// dictionary, backing the original file up beside it as .cyanide.bak.
bool nano_registry_seed_current_phone_compatibility_index(int max_pairing_version);

// Pushes the four override keys directly into the mobile-user cfprefsd's
// in-memory cache via RemoteCall + CFPreferencesSetValue. This is needed
// because cfprefsd is the source of truth for CFPreferencesCopyValue
// reads — writing the file directly is not enough; cfprefsd can overwrite
// the file with its stale cache the next time any process calls
// CFPreferencesSetValue on the same domain. Pass apply=false to clear.
// Requires KRW (kexploit must have run); does its own RemoteCall init.
bool nano_registry_push_to_cfprefsd(const nano_registry_values *values, bool apply);

#endif /* nano_registry_h */
