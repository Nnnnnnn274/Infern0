//
//  amfi_research.h
//  Cyanide
//
//  Created by seo on 4/6/26.
//

#ifndef AMFI_RESEARCH_H
#define AMFI_RESEARCH_H

#include <stdint.h>
#include <stddef.h>

/*
 * Valid kernel pointer check for arm64 iOS.
 */
static inline int is_valid_kptr(uint64_t ptr) {
    return (ptr >= 0xFFFFFE0000000000ULL && ptr != 0xFFFFFFFFFFFFFFFFULL);
}


/* ================================================================
 *  OSEntitlements  (cr_label->l_perpolicy[0])
 * ================================================================
 *
 * Identical layout across iOS 17 and iOS 18.
 */
struct OSEntitlements {
    /* +0x00 */ void                        *vtable;
    /* +0x08 */ uint32_t                    retainCount;
    /* +0x0C */ uint32_t                    _pad0c;
    /* +0x10 */ struct OSEntitlementsState  *state;
    /* +0x18 */ uint64_t                    lock[2];        /* lck_rw_t */
};
/* sizeof = 0x28 */


/* ================================================================
 *  OSEntitlementsState — version detection
 * ================================================================
 *
 * The state structure layout changed between iOS 17 and iOS 18.
 * Detection: check the first qword of query_context (state+0x08).
 *
 *   iOS 17:  state+0x08 = kernel pointer (0xFFFFFF...)
 *            → Legacy flat layout after fixed header
 *            → valid/is_cs_platform are populated
 *            → signing_identity at +0x68, xml_dict at +0x70
 *
 *   iOS 18+: state+0x08 = 0x0000000100000000 (CE version)
 *            → Inline entitlement entry array after +0x58
 *            → valid/is_cs_platform may be 0 for platform binaries
 *            → signing_identity/xml_dict NOT at fixed offsets
 */

/* Layout version enum */
enum amfi_state_version {
    AMFI_STATE_IOS17 = 0,   /* legacy flat layout */
    AMFI_STATE_IOS18 = 1,   /* inline entry array */
};

/*
 * Detect layout version from raw state buffer.
 * state_buf must be at least 0x10 bytes.
 */
static inline enum amfi_state_version amfi_detect_version(const uint8_t *state_buf) {
    uint64_t qc_first = *(const uint64_t *)&state_buf[0x08];
    if (is_valid_kptr(qc_first)) {
        return AMFI_STATE_IOS17;
    }
    return AMFI_STATE_IOS18;
}


/* ================================================================
 *  Fixed header (shared between iOS 17 and 18)
 *  Only the first 0x58 bytes are guaranteed identical.
 * ================================================================ */
struct OSEntitlementsState {
    /* +0x00 */ uint64_t    pac_signature;

    /* +0x08 ~ +0x47: Inline CEQueryContext (0x40 bytes)
     *
     *   iOS 17 layout:
     *     +0x08: blob data ptr (kernel ptr)
     *     +0x10: blob validator ptr (kernel ptr)
     *     +0x18: entitlement count
     *     +0x20: flags
     *     +0x28: state (0x101)
     *     +0x30: DER data start (kernel ptr)
     *     +0x38: DER data end (kernel ptr)
     *     +0x40: NULL
     *
     *   iOS 18 layout:
     *     +0x08: CE version (0x0000000100000000)
     *     +0x10: blob data ptr (kernel ptr)
     *     +0x18: blob validator ptr (kernel ptr)
     *     +0x20: entitlement count
     *     +0x28: flags
     *     +0x30: state (0x101)
     *     +0x38: DER data start (kernel ptr)
     *     +0x40: DER data end (kernel ptr)
     */
    uint8_t                 query_context[0x40];

    /* +0x48 */ uint8_t     valid;
    /* +0x49 */ uint8_t     _pad49;
    /* +0x4A */ uint8_t     is_cs_platform;
    /* +0x4B */ uint8_t     _pad4b;
    /* +0x4C */ uint8_t     has_transmuted;
    /* +0x4D */ uint8_t     _pad4d[3];
    /* +0x50 */ void        *transmuted_blob;
};
/* sizeof(fixed header) = 0x58 */


/* ================================================================
 *  iOS 17: Legacy flat layout after +0x58
 * ================================================================ */
struct OSEntitlementsState_ios17 {
    /* +0x00..+0x57: same fixed header */
    uint64_t    pac_signature;
    uint8_t     query_context[0x40];
    uint8_t     valid;
    uint8_t     _pad49;
    uint8_t     is_cs_platform;
    uint8_t     _pad4b;
    uint8_t     has_transmuted;
    uint8_t     _pad4d[3];
    void        *transmuted_blob;

    /* +0x58 */ uint64_t    _reserved0;
    /* +0x60 */ void        *entitlements_blob;  /* DER blob ptr or NULL */
    /* +0x68 */ char        *signing_identity;   /* "com.apple.xpc.launchd" etc. */
    /* +0x70 */ void        *xml_dict;           /* OSDictionary* */
    /* +0x78 */ void        *extra;              /* additional ptr */
};
/* sizeof = 0x80 */


/* ================================================================
 *  iOS 18: Inline entitlement entry (stride 0x70)
 * ================================================================ */
struct OSEntitlementEntry {
    /* +0x00 */ void        *key;
    /* +0x08 */ uint64_t    reserved;
    /* +0x10 */ uint64_t    type_or_flags;      /* 0x100 observed */
    /* +0x18 */ void        *value;
    /* +0x20 */ uint8_t     padding[0x50];
};
/* sizeof = 0x70 */


/* ================================================================
 *  OSDictionary_kernel (iOS 17 layout)
 * ================================================================
 *
 * iOS 17: OSObject → OSCollection → OSDictionary
 * The lock may NOT be at +0x18 on iOS 17.
 *
 * iOS 17 observed pattern (from raw dump):
 *   +0x00: vtable (PAC'd)
 *   +0x08: retainCount (u32) = 1
 *   +0x10: fOptions/flags (u32)
 *   +0x14: count (u32)
 *   +0x18: capacity (u32)
 *   +0x20: dictionary (ptr)
 *
 * iOS 18 observed pattern:
 *   +0x00: vtable (PAC'd)
 *   +0x08: retainCount (u32)
 *   +0x10: updateStamp (u32) + fOptions (u32)
 *   +0x18: lock (lck_rw_t, 16B) = 0x33000000/0x420000
 *   +0x28: dictionary (ptr)
 *   +0x30: count (u32) + capacity (u32)
 */

/* iOS 18 layout */
struct OSDictionary_kernel_ios18 {
    /* +0x00 */ void        *vtable;
    /* +0x08 */ uint32_t    retainCount;
    /* +0x0C */ uint32_t    _pad0c;
    /* +0x10 */ uint32_t    updateStamp;
    /* +0x14 */ uint32_t    fOptions;
    /* +0x18 */ uint64_t    lock[2];            /* lck_rw_t */
    /* +0x28 */ void        *dictionary;
    /* +0x30 */ uint32_t    count;
    /* +0x34 */ uint32_t    capacity;
    /* +0x38 */ uint32_t    capacityIncrement;
    /* +0x3C */ uint32_t    _pad3c;
};
/* sizeof = 0x40 */

/* iOS 17 layout (tentative — needs further verification) */
struct OSDictionary_kernel_ios17 {
    /* +0x00 */ void        *vtable;
    /* +0x08 */ uint32_t    retainCount;
    /* +0x0C */ uint32_t    _pad0c;
    /* +0x10 */ uint32_t    fOptions;
    /* +0x14 */ uint32_t    count;
    /* +0x18 */ uint32_t    capacity;
    /* +0x1C */ uint32_t    capacityIncrement;
    /* +0x20 */ void        *dictionary;
};
/* sizeof = 0x28 */


int research_amfi(uint64_t proc);

#endif /* AMFI_RESEARCH_H */
