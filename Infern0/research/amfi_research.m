//
//  amfi_research.m
//  Cyanide
//
//  Created by seo on 4/6/26.
//

#import <Foundation/Foundation.h>

#import "amfi_research.h"
#import "../utils/sandbox.h"
#import "../kexploit/kutils.h"
#import "../kexploit/krw.h"
#import "../kexploit/xpaci.h"
#import "../LogTextView.h"


static void print_ptr_field(const char *label, size_t offset, uint64_t raw) {
    uint64_t stripped = xpaci(raw);
    if (raw == 0) {
        printf("  [+0x%02lx] %-20s = 0x0 (NULL)\n", offset, label);
    } else if (raw == stripped) {
        printf("  [+0x%02lx] %-20s = 0x%llx", offset, label, raw);
        if (!is_valid_kptr(raw))
            printf("  ⚠ NOT a valid kernel ptr");
        printf("\n");
    } else {
        printf("  [+0x%02lx] %-20s = 0x%llx (PAC stripped: 0x%llx)", offset, label, raw, stripped);
        if (!is_valid_kptr(stripped))
            printf("  ⚠ NOT a valid kernel ptr");
        printf("\n");
    }
}


static void dump_query_context(const uint8_t *state_buf, enum amfi_state_version ver) {
    printf("  [+0x08] query_context (inline CEQueryContext, 0x40 bytes):\n");

    uint64_t *qc = (uint64_t *)&state_buf[0x08];

    const char *ios17_labels[] = {
        "blob_data_ptr",  "blob_validator",  "ent_count",
        "flags",          "ce_state",        "der_data_start",
        "der_data_end",   "reserved",
    };
    const char *ios18_labels[] = {
        "ce_version",     "blob_data_ptr",   "blob_validator",
        "ent_count",      "flags",           "ce_state",
        "der_data_start", "der_data_end",
    };

    const char **labels = (ver == AMFI_STATE_IOS17) ? ios17_labels : ios18_labels;

    for (int i = 0; i < 8; i++) {
        uint64_t val = qc[i];
        uint64_t stripped = xpaci(val);
        printf("    [+0x%02x] %-16s 0x%016llx", (int)(0x08 + i * 8), labels[i], val);
        if (val == 0)
            printf("  (NULL)");
        else if (val != stripped)
            printf("  (PAC stripped: 0x%llx)", stripped);
        else if (is_valid_kptr(val))
            printf("  ← kernel ptr");
        else if (val < 0x100000)
            printf("  = %llu", val);
        printf("\n");
    }
}


static void dump_state_ios17(const uint8_t *state_buf, uint64_t state_kptr) {
    uint64_t rsv0       = *(uint64_t *)&state_buf[0x58];
    uint64_t ent_blob   = *(uint64_t *)&state_buf[0x60];
    uint64_t si_raw     = *(uint64_t *)&state_buf[0x68];
    uint64_t xd_raw     = *(uint64_t *)&state_buf[0x70];
    uint64_t extra_raw  = *(uint64_t *)&state_buf[0x78];

    printf("\n--- iOS 17 flat layout (+0x58..+0x7F) ---\n");

    if (rsv0)
        printf("  [+0x58] %-20s = 0x%llx\n", "_reserved0", rsv0);

    /* +0x60: entitlements blob */
    {
        uint64_t s = xpaci(ent_blob);
        printf("  [+0x60] %-20s = 0x%llx", "entitlements_blob", ent_blob);
        if (ent_blob == 0) printf(" (NULL)");
        else if (ent_blob != s) printf(" (PAC stripped: 0x%llx)", s);
        else if (is_valid_kptr(ent_blob)) printf(" ← kernel ptr");
        printf("\n");
    }

    /* +0x68: signing_identity */
    {
        uint64_t s = xpaci(si_raw);
        printf("  [+0x68] %-20s = 0x%llx", "signing_identity", si_raw);
        if (si_raw == 0) {
            printf(" (NULL)\n");
        } else if (!is_valid_kptr(s)) {
            if (si_raw != s) printf(" (PAC stripped: 0x%llx)", s);
            printf(" ⚠ NOT a kernel ptr\n");
        } else {
            if (si_raw != s) printf(" (PAC stripped: 0x%llx)", s);
            char identity[256] = {0};
            kreadbuf(s, identity, sizeof(identity) - 1);
            printf(" → \"%s\"\n", identity);
        }
    }

    /* +0x70: xml_dict */
    {
        uint64_t s = xpaci(xd_raw);
        printf("  [+0x70] %-20s = 0x%llx", "xml_dict", xd_raw);
        if (xd_raw == 0) {
            printf(" (NULL)\n");
        } else if (!is_valid_kptr(s)) {
            if (xd_raw != s) printf(" (PAC stripped: 0x%llx)", s);
            printf(" ⚠ NOT a kernel ptr\n");
        } else {
            if (xd_raw != s) printf(" (PAC stripped: 0x%llx)", s);
            printf(" (OSDictionary*)\n");

            /* iOS 17 OSDictionary layout */
            uint8_t d[0x30] = {0};
            kreadbuf(s, d, sizeof(d));
            printf("\n--- OSDictionary (at 0x%llx, iOS 17) ---\n", s);
            print_ptr_field("vtable", 0x00, *(uint64_t *)&d[0x00]);
            printf("  [+0x08] %-20s = %u\n", "retainCount", *(uint32_t *)&d[0x08]);
            printf("  [+0x10] %-20s = %u\n", "fOptions",    *(uint32_t *)&d[0x10]);
            printf("  [+0x14] %-20s = %u\n", "count",       *(uint32_t *)&d[0x14]);
            printf("  [+0x18] %-20s = %u\n", "capacity",    *(uint32_t *)&d[0x18]);
            printf("  [+0x1c] %-20s = %u\n", "capIncrement",*(uint32_t *)&d[0x1C]);
            print_ptr_field("dictionary", 0x20, *(uint64_t *)&d[0x20]);
        }
    }

    /* +0x78: extra */
    if (extra_raw) {
        uint64_t s = xpaci(extra_raw);
        printf("  [+0x78] %-20s = 0x%llx", "extra", extra_raw);
        if (extra_raw != s) printf(" (PAC stripped: 0x%llx)", s);
        printf("\n");
    }
}


static void dump_state_ios18_entries(const uint8_t *state_buf, size_t buf_size) {
    printf("\n--- iOS 18 inline entitlement entries (stride=0x70) ---\n\n");

    int entry_idx = 0;
    for (size_t off = 0x58; off + 0x20 <= buf_size; off += 0x70) {
        uint64_t key_raw = *(uint64_t *)&state_buf[off + 0x00];
        uint64_t key     = xpaci(key_raw);
        uint64_t rsvd    = *(uint64_t *)&state_buf[off + 0x08];
        uint64_t flags   = *(uint64_t *)&state_buf[off + 0x10];
        uint64_t val_raw = *(uint64_t *)&state_buf[off + 0x18];
        uint64_t val     = xpaci(val_raw);

        if (!is_valid_kptr(key))
            break;

        printf("  Entry[%d] at state+0x%03lx:\n", entry_idx, off);

        printf("    key    = 0x%llx", key_raw);
        if (key_raw != key) printf(" (PAC stripped: 0x%llx)", key);
        if (is_valid_kptr(key)) {
            char ks[128] = {0};
            kreadbuf(key, ks, sizeof(ks) - 1);
            if (ks[0] >= 0x20 && ks[0] < 0x7F)
                printf(" → \"%s\"", ks);
        }
        printf("\n");

        if (rsvd) printf("    rsvd   = 0x%llx\n", rsvd);
        printf("    flags  = 0x%llx\n", flags);

        printf("    value  = 0x%llx", val_raw);
        if (val_raw != val) printf(" (PAC stripped: 0x%llx)", val);
        printf("\n");

        entry_idx++;
    }
    printf("\n  Total: %d entitlement entries\n", entry_idx);
}


static void dump_state_ios18_flat(const uint8_t *state_buf) {
    printf("\n--- iOS 18 flat layout (no inline entries) ---\n");

    uint64_t si_raw = *(uint64_t *)&state_buf[0x68];
    uint64_t si     = xpaci(si_raw);
    printf("  [+0x68] %-20s = 0x%llx", "signing_identity", si_raw);
    if (si_raw == 0)
        printf(" (NULL)\n");
    else if (!is_valid_kptr(si))
        printf(" ⚠ NOT a kernel ptr\n");
    else {
        if (si_raw != si) printf(" (PAC stripped: 0x%llx)", si);
        char identity[256] = {0};
        kreadbuf(si, identity, sizeof(identity) - 1);
        printf(" → \"%s\"\n", identity);
    }

    uint64_t xd_raw = *(uint64_t *)&state_buf[0x70];
    uint64_t xd     = xpaci(xd_raw);
    printf("  [+0x70] %-20s = 0x%llx", "xml_dict", xd_raw);
    if (xd_raw == 0) {
        printf(" (NULL)\n");
    } else if (!is_valid_kptr(xd)) {
        printf(" ⚠ NOT a kernel ptr\n");
    } else {
        if (xd_raw != xd) printf(" (PAC stripped: 0x%llx)", xd);
        printf(" (OSDictionary*)\n");

        /* iOS 18 OSDictionary */
        struct OSDictionary_kernel_ios18 dict = {0};
        kreadbuf(xd, &dict, sizeof(dict));
        printf("\n--- OSDictionary (at 0x%llx, iOS 18) ---\n", xd);
        print_ptr_field("vtable", 0x00, (uint64_t)dict.vtable);
        printf("  [+0x08] %-20s = %u\n", "retainCount", dict.retainCount);
        printf("  [+0x10] %-20s = %u\n", "updateStamp", dict.updateStamp);
        printf("  [+0x14] %-20s = 0x%08x\n", "fOptions", dict.fOptions);
        printf("  [+0x18] %-20s = 0x%llx / 0x%llx",
               "lock (lck_rw_t)", dict.lock[0], dict.lock[1]);
        if (dict.lock[0] == 0x33000000 && dict.lock[1] == 0x420000)
            printf("  (idle ✓)");
        printf("\n");
        print_ptr_field("dictionary", 0x28, (uint64_t)dict.dictionary);
        printf("  [+0x30] %-20s = %u\n", "count", dict.count);
        printf("  [+0x34] %-20s = %u\n", "capacity", dict.capacity);
    }
}


int research_amfi(uint64_t proc) {
    uint64_t label = proc_get_cred_label(proc);
    uint64_t amfi_obj = amfi_cslot_get(label);

    if (!amfi_obj) {
        printf("[-] AMFI slot is NULL (proc=0x%llx)\n", proc);
        return -1;
    }

    struct OSEntitlements ent = {0};
    kreadbuf(amfi_obj, &ent, sizeof(struct OSEntitlements));

    printf("============================================================\n");
    printf("  AMFI label (OSEntitlements) dump\n");
    printf("  proc=0x%llx  label=0x%llx  amfi_slot=0x%llx\n",
           proc, label, amfi_obj);
    printf("============================================================\n\n");

    printf("--- OSEntitlements (0x%lx bytes at 0x%llx) ---\n",
           sizeof(struct OSEntitlements), amfi_obj);
    print_ptr_field("vtable", offsetof(struct OSEntitlements, vtable),
                    (uint64_t)ent.vtable);
    printf("  [+0x%02lx] %-20s = %u\n",
           offsetof(struct OSEntitlements, retainCount),
           "retainCount", ent.retainCount);
    print_ptr_field("state", offsetof(struct OSEntitlements, state),
                    (uint64_t)ent.state);
    printf("  [+0x%02lx] %-20s = 0x%llx / 0x%llx",
           offsetof(struct OSEntitlements, lock), "lock (lck_rw_t)",
           ent.lock[0], ent.lock[1]);
    if (ent.lock[0] == 0x33000000 && ent.lock[1] == 0x420000)
        printf("  (idle)");
    printf("\n");

    uint64_t state_kptr = xpaci((uint64_t)ent.state);
    if (!is_valid_kptr(state_kptr)) {
        printf("[-] state pointer invalid: 0x%llx\n", state_kptr);
        return -1;
    }

    uint8_t state_buf[0x500] = {0};
    kreadbuf(state_kptr, state_buf, sizeof(state_buf));

    struct OSEntitlementsState *st = (struct OSEntitlementsState *)state_buf;
    enum amfi_state_version ver = amfi_detect_version(state_buf);

    printf("\n--- OSEntitlementsState (at 0x%llx, %s) ---\n",
           state_kptr,
           ver == AMFI_STATE_IOS17 ? "iOS 17 layout" : "iOS 18 layout");

    /* pac_signature */
    printf("  [+0x%02lx] %-20s = 0x%llx",
           offsetof(struct OSEntitlementsState, pac_signature),
           "pac_signature", st->pac_signature);
    if (st->pac_signature == amfi_obj)
        printf("  (== amfi_obj ✓)");
    printf("\n");

    /* query_context */
    dump_query_context(state_buf, ver);

    /* valid / is_cs_platform / has_transmuted */
    printf("  [+0x%02lx] %-20s = %u (%s)\n",
           offsetof(struct OSEntitlementsState, valid), "valid",
           st->valid, st->valid ? "entitlements present" : "NO entitlements");
    printf("  [+0x%02lx] %-20s = %u (%s)\n",
           offsetof(struct OSEntitlementsState, is_cs_platform), "is_cs_platform",
           st->is_cs_platform, st->is_cs_platform ? "PLATFORM BINARY" : "third-party");
    if (ver == AMFI_STATE_IOS18 && !st->valid && !st->is_cs_platform) {
        printf("    (note: on iOS 18, platform binaries may show valid=0,\n");
        printf("     is_cs_platform=0; entitlements in inline entries)\n");
    }
    printf("  [+0x%02lx] %-20s = %u (%s)\n",
           offsetof(struct OSEntitlementsState, has_transmuted), "has_transmuted",
           st->has_transmuted, st->has_transmuted ? "transmuted blob exists" : "none");

    /* transmuted_blob */
    {
        uint64_t raw = (uint64_t)st->transmuted_blob;
        uint64_t stripped = xpaci(raw);
        printf("  [+0x%02lx] %-20s = 0x%llx",
               offsetof(struct OSEntitlementsState, transmuted_blob),
               "transmuted_blob", raw);
        if (raw == 0)
            printf(" (NULL)");
        else {
            if (raw != stripped) printf(" (PAC stripped: 0x%llx)", stripped);
            uint64_t qc_addr = state_kptr + offsetof(struct OSEntitlementsState, query_context);
            if (stripped == qc_addr)
                printf("  (== &query_context, self-ref)");
            else if (!is_valid_kptr(stripped))
                printf("  ⚠ NOT a valid kernel ptr");
        }
        printf("\n");
    }

    /* Version-specific variable area */
    if (ver == AMFI_STATE_IOS17) {
        dump_state_ios17(state_buf, state_kptr);
    } else {
        uint64_t probe = *(uint64_t *)&state_buf[0x58];
        if (is_valid_kptr(xpaci(probe))) {
            dump_state_ios18_entries(state_buf, sizeof(state_buf));
        } else {
            dump_state_ios18_flat(state_buf);
        }
    }

    /* Transmuted blob */
    if (st->has_transmuted && st->transmuted_blob) {
        uint64_t bp = xpaci((uint64_t)st->transmuted_blob);
        uint64_t qc_addr = state_kptr + offsetof(struct OSEntitlementsState, query_context);
        if (is_valid_kptr(bp) && bp != qc_addr) {
            uint8_t bh[0x10] = {0};
            kreadbuf(bp, bh, sizeof(bh));
            printf("\n--- Transmuted blob (at 0x%llx) ---\n", bp);
            printf("  [+0x00] magic              = 0x%08x\n", *(uint32_t *)&bh[0x00]);
            printf("  [+0x04] length             = %u\n",     *(uint32_t *)&bh[0x04]);
            printf("  [+0x08] data               = 0x%llx\n", *(uint64_t *)&bh[0x08]);
        }
    }

    /* Raw hex dump */
    printf("\n--- Raw state hex dump (first 0x100 bytes) ---\n");
    for (int i = 0; i < 0x100; i++) {
        if (i % 16 == 0) printf("  [+0x%03x] ", i);
        printf("%02x ", state_buf[i]);
        if ((i + 1) % 16 == 0) printf("\n");
    }

    printf("\n============================================================\n");
    return 0;
}
