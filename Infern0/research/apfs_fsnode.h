//
//  apfs_fsnode.h
//  Cyanide
//
//  Created by seo on 4/6/26.
//

// BELOW CONTENTS ARE MADE BY CLAUDE AI, SO MAY NOT BE CORRECT.

/*
 * apfs_fsnode.h  (v3 — final, no padding)
 *
 * iPadOS 18.3.x – iPad M3 (kernel_ipadm3_183.raw)
 * com.apple.filesystems.apfs kext (TEXT_EXEC: 0xaa997d0, 3904 syms)
 *
 * vnode->v_data (off 0xe0) points to this structure.
 * 228 vnode_fsnode() call sites, 300+ lck_rw references,
 * 132 xf_get references analyzed.
 *
 * uid/gid/mode at +0x80/+0x84/+0x88 — identical to kfund (iOS 16.x).
 */

#include <stdint.h>
#include <sys/types.h>

struct apfs_fsnode {

    /* +0x00 (1B) [LDR/STR] 45 refs
     * Inode type / node state byte.
     *   apfs_vnop_reclaim, apfs_vnop_getattr, apfs_lock_vnode_callback,
     *   apfs_clone_internal, apfs_fsync_internal, apfs_vnop_lookup, ...
     */
    uint8_t             type;                   /* +0x00 */
    uint8_t             _type_pad[7];           /* +0x01..07 */

    /* +0x08 (8B) [LDR/STR] 96 refs — most accessed field
     * APFS inode number (ino64_t)
     *   apfs_vnop_getattr, apfs_vnop_lookup, apfs_jhash_insertvnode,
     *   apfs_vnop_strategy, apfs_get_nstream_vnode, ...
     */
    uint64_t            ino;                    /* +0x08 */

    /* +0x10 (8B) [LDR] 4 refs
     * jhash linkage / sub-struct with embedded sub-fields.
     *   apfs_jhash_insertvnode: ADD x25, x19, #0x10 (used as list link)
     *   apfs_graft:             LDR x8, [x20, #0x10]
     *   apfs_inode_getxattr:    LDR x8, [x20, #0x10]
     *   apfs_vnop_open:         LDR x8, [x20, #0x10]
     *
     * +0x14 (2B) 2 refs: apfs_inode_getxattr — sub-field (e.g. xattr count)
     * +0x16 (2B) 1 ref:  apfs_inode_getxattr — sub-field (e.g. xattr flags)
     */
    union {
        uint64_t        jhash_prev;
        struct {
            uint32_t    _jhash_prev_lo;
            uint16_t    xattr_count;            /* +0x14 */
            uint16_t    xattr_flags;            /* +0x16 */
        };
    };                                          /* +0x10 */

    /* +0x18 (8B) [LDR] 1 ref
     * jhash linkage (next pointer)
     *   apfs_jhash_insertvnode:  STR x25, [x9, #0x18]
     *   apfs_vnop_setxattr:     LDR x8, [x19, #0x18]
     */
    uint64_t            jhash_next;             /* +0x18 */

    /* +0x20 (8B) [LDR/STR] 18 refs
     * Parent inode number
     *   apfs_vnop_lookup, apfs_get_nstream_parent_inode,
     *   apfs_vnop_exchange, apfs_fsync_internal, apfs_raw_encrypted_lookup,
     *   apfs_load_inode_internal (STR x22, [x9, #0x20])
     *
     * +0x24 (2B) 1 ref: apfs_truncate_decmpfs_unlock — parent sub-field
     */
    union {
        uint64_t        parent_ino_or_owner_vnode;
        struct {
            uint32_t    parent_ino_lo;          /* +0x20 */
            uint16_t    parent_sub;             /* +0x24 */
            uint16_t    _parent_pad;            /* +0x26 */
        };
    };                                          /* +0x20 */

    /* +0x28 (4B) [LDR] 11 refs
     * Named stream / xattr stream identifier
     *   apfs_nstream_vnop_getattr, apfs_get_nstream_vnode,
     *   apfs_jhash_insertvnode (LDR w26, [x19, #0x28])
     */
    uint32_t            nstream_id;             /* +0x28 */

    /* +0x2C (4B) [LDR/STR]
     * Internal flags (bitfield)
     *   apfs_jhash_insertvnode: LDR w9, [x19, #0x2c]; AND; STR
     * +0x2C (1B) 1 ref: apfs_vnop_reclaim
     * +0x2D (1B) 3 refs: apfs_vnop_renamex, check_for_busy_parent
     * +0x2E~2F: part of the same u32
     */
    union {
        uint32_t        internal_flags;
        struct {
            uint8_t     reclaim_flag;           /* +0x2C */
            uint8_t     busy_flag;              /* +0x2D */
            uint16_t    internal_flags_hi;      /* +0x2E */
        };
    };                                          /* +0x2C */

    /* +0x30 (8B) [LDR] 2 refs
     * jhash gate or object pointer
     *   apfs_jhash_insertvnode: STR x21, [x19, #0x30]; BL _lck_rw_gate_init
     *   apfs_load_inode_internal: LDR
     *   apfs_vnop_getattrlistbulk: LDR
     */
    void                *jhash_gate;            /* +0x30 */

    /* +0x38 (8B) [LDR/STR] 14 refs
     * Internal state or list linkage
     *   apfs_vnop_remove, apfs_load_fs_vnodes, apfs_vfsop_unmount,
     *   apfs_internal_lookup_ext, apfs_load_inode_internal,
     *   apfs_vnop_getattr
     *
     * +0x39 (1B) 1 ref: apfs_snap_vnop_rename — sub-byte flag
     * +0x3C (4B) 2 refs: handle_snapshot_mount
     * +0x3E (2B) 1 ref: apfs_vnop_lookup
     */
    union {
        uint64_t        internal_link;
        struct {
            uint8_t     _link_base;             /* +0x38 */
            uint8_t     snap_rename_flag;        /* +0x39 */
            uint16_t    _link_pad;              /* +0x3A */
            uint32_t    snap_mount_state;        /* +0x3C */
        };
    };                                          /* +0x38 */

    /* +0x40 (8B) [LDR/STR] 14 refs
     * Graft state
     *   apfs_graft, apfs_find_graft_state_by_graft_private_id,
     *   apfs_vnop_mmap_check, apfs_load_inode_internal
     */
    uint64_t            graft_state;            /* +0x40 */

    /* +0x48 (8B) [LDR] 4 refs
     * Snapshot metadata
     *   apfs_fake_vnop_getattr, apfs_vfs_ioctl, handle_snap_make_dataless
     */
    uint64_t            snap_state;             /* +0x48 */

    /* +0x50 (8B) [LDR] 1 ref
     * Fake getattr data / general metadata
     *   apfs_fake_vnop_getattr: LDR x8, [x22, #0x50]
     *   STP x0,x0,[x22,#0x50] in clone_fs (zero pair with +0x58)
     *   STP x31,x31,[x27,#0x50] in vnop_renamex
     */
    uint64_t            fake_getattr_data;      /* +0x50 */

    /* +0x58 (8B) [LDR/STR] 2 refs
     * mnomap / mmap tracking data
     *   apfs_fake_vnop_getattr: LDR x8, [x22, #0x58]
     *   apfs_vnop_mnomap:       STR x8, [x20, #0x58]
     */
    uint64_t            mnomap_data;            /* +0x58 */

    /* +0x60 (8B) [LDR] 2 refs
     * Cleanup / purgatory data (paired with +0x68)
     *   apfs_cleanup_purgatory_continuation: LDR x8, [x20, #0x60]
     *   apfs_fake_vnop_getattr:              LDR x8, [x22, #0x60]
     *   STP x31,x31,[x25,#0x60] in snap_vnop_getattr (zero pair)
     *   LDP x0,x1,[x19,#0x60] in vnop_setattr
     */
    uint64_t            cleanup_data;           /* +0x60 */

    /* +0x68 (8B) [LDR/STR] 5 refs
     * Crypto / protection state
     *   apfs_initialize_namedstream_vnode (STR),
     *   apfs_raw_encrypted_lookup, apfs_truncate_locked,
     *   child_size_calculator_cb
     *
     * Sub-byte fields within this u64:
     * +0x69 (1B) 7 refs: encryption class
     *   apfs_vnop_read, apfs_vnop_write, apfs_vnop_close,
     *   apfs_vnop_allocate, apfs_get_nstream_vnode, apfs_nstream_write
     * +0x6A (1B) 6 refs: crypto flags
     *   apfs_vnop_mmap, check_for_busy_parent, preallocate_inline,
     *   apfs_load_inode_internal, apfs_raw_encrypted_lookup
     * +0x6C (4B) 7 refs: extended crypto state
     *   apfs_cleanup_purgatory, apfs_vfs_ioctl, handle_snap_make_dataless
     */
    union {
        uint64_t        crypto_state;
        struct {
            uint8_t     _crypto_base;           /* +0x68 */
            uint8_t     crypto_class;           /* +0x69 */
            uint8_t     crypto_flags;           /* +0x6A */
            uint8_t     _crypto_pad;            /* +0x6B */
            uint32_t    crypto_extra;           /* +0x6C */
        };
    };                                          /* +0x68 */

    /* +0x70 (4B) [LDR/STR] 6 refs
     * BSD flags (UF_HIDDEN, UF_IMMUTABLE, SF_ARCHIVED, etc.)
     *   apfs_fake_vnop_getattr, apfs_load_inode_internal,
     *   apfs_raw_encrypted_lookup, apfs_vnop_getattr (→ get_nlink_for_object)
     */
    uint32_t            bsd_flags;              /* +0x70 */

    /* +0x74 (4B) [LDR] 9 refs
     * Generation count or protection flags
     *   apfs_vnop_open, apfs_vnop_setattr, apfs_vnode_recycle_callback,
     *   apfs_initialize_namedstream_vnode, apfs_nstream_vnop_pagein
     */
    uint32_t            gen_flags;              /* +0x74 */

    /* +0x78 (8B) [LDR/STR] 5 refs
     * mmap state / snapshot data
     *   apfs_cleanup_purgatory, apfs_vfs_ioctl, apfs_vnop_mnomap,
     *   handle_snap_make_dataless
     */
    uint64_t            mmap_state;             /* +0x78 */

    /* +0x80 (4B) uid — CONFIRMED
     *   apfs_vnop_getattr path1: LDR w9,[fsnode,#0x80] → STR w9,[vap,#0x44]
     *   apfs_vnop_getattr path2: LDR w9,[x22,#0x80]   → STR w9,[vap,#0x44]
     *   Identical to kfund iOS 16.x offset.
     */
    uid_t               uid;                    /* +0x80 */

    /* +0x84 (4B) gid — CONFIRMED
     *   apfs_vnop_getattr: LDR w9,[fsnode,#0x84] → STR w9,[vap,#0x48]
     *   apfs_raw_encrypted_lookup: STR w8,[x20,#0x84]
     */
    gid_t               gid;                    /* +0x84 */

    /* +0x88 (2B) [LDR/STR] 30 refs — mode + open_count (shared field)
     * Dual purpose: stores POSIX permission bits AND open reference count.
     *
     * As mode (in apfs_vnop_getattr):
     *   LDR h9,[fsnode,#0x88] → STR h9,[vap,#0x4c] (va_mode)
     *
     * As open_count (in apfs_vnop_open/close):
     *   LDR h8,[x20,#0x88]
     *   (increment/decrement pattern in surrounding instructions)
     *
     * Note: separate code paths handle these differently.
     * The getattr path reads it as mode; the open/close path
     * uses it as a reference count after the lock is acquired.
     */
    uint16_t            mode;                   /* +0x88: POSIX permission bits */
    uint16_t            open_refcnt;            /* +0x8A: open reference tracking */

    /* +0x8C..8F: inode property flags (part of getattr va_flags computation)
     *   apfs_vnop_getattr: LDR b8,[x21,#0x7c] — but actually reads 4B at +0x7C
     *   The +0x7C field extends into this area as a 32-bit ino_flags field.
     *   +0x8C itself is not directly accessed but is part of the
     *   alignment gap between mode(+0x88) and raw_enc_data(+0x90).
     */
    uint32_t            ino_flags_ext;          /* +0x8C */

    /* +0x90 (8B) [STR] 1 ref
     * Raw encryption metadata
     *   apfs_raw_encrypted_lookup: STR x8, [x20, #0x90]
     *   STP x31,x31,[x25,#0x90] in snap_vnop_getattr (zeroed pair with +0x98)
     *   STP x31,x31,[x8,#0x90] in handle_snapshot_mount
     */
    uint64_t            raw_enc_data;           /* +0x90 */

    /* +0x98 (8B) [LDR/STR] 70 refs — most written field
     * Data stream (dstream) pointer / descriptor
     *   apfs_fsync_internal, apfs_vnop_setattr, apfs_vnop_allocate,
     *   apfs_get_nstream_vnode, apfs_graft, apfs_initialize_namedstream_vnode,
     *   apfs_vnop_write, apfs_nstream_read, apfs_vnop_read, ...
     *
     * Sub-byte fields:
     * +0x9B (1B) 5 refs: close/inactive state
     *   apfs_raw_encrypted_lookup, apfs_vnop_close, apfs_vnop_inactive
     * +0x9C (1B) 3 refs: needs_zerofill flag
     *   apfs_get_nstream_vnode, apfs_initialize_namedstream_vnode, apfs_needs_zerofill
     * +0x9D (1B) 28 refs: compression/property flag (heavily used)
     *   apfs_vnop_getattr, apfs_vnop_open, apfs_vnop_write, apfs_vnop_read,
     *   apfs_fsync_internal, apfs_nstream_read, apfs_nstream_vnop_pagein, ...
     * +0x9E (1B) 1 ref: apfs_nstream_vnop_pagein
     */
    union {
        uint64_t        dstream;
        struct {
            uint8_t     _ds_bytes[3];           /* +0x98..9A */
            uint8_t     ds_close_state;         /* +0x9B */
            uint8_t     ds_needs_zerofill;      /* +0x9C */
            uint8_t     ds_compression_flags;   /* +0x9D */
            uint8_t     ds_nstream_flag;         /* +0x9E */
            uint8_t     _ds_pad;                /* +0x9F */
        };
    };                                          /* +0x98 */

    /* +0xA0 (16B) — per-inode read-write lock (lck_rw_t)
     * 300+ ADD xN, fsnode, #0xa0 → lck_rw_{init,destroy,lock_*,unlock_*,assert,try_lock}
     * Used by virtually every APFS vnop and internal function.
     */
    uint64_t            rw_lock[2];             /* +0xA0 */

    /* +0xB0 (8B) [LDR] 7 refs
     * decmpfs compression node pointer
     *   apfs_truncate_decmpfs_unlock, apfs_vnop_open, apfs_vnop_allocate,
     *   handle_cas_bsdflags,
     *   apfs_pack_vap_common (→ decmpfs_cnode_get_vnode_state/cmp_type/cached_size)
     */
    void                *decmpfs_cnode;         /* +0xB0 */

    /* +0xB8 (8B)
     * Inline xattr area / xattr data pointer
     *   apfs_pack_vap_common: ADD x3, x20, #0xb8 → fs_get_xattr_in_snap
     *   2 ADD refs with lck_mtx_lock
     */
    uint64_t            xattr_inline;           /* +0xB8 */

    /* +0xC0 (8B) [LDR] 4 refs
     * Extended attribute state
     *   apfs_vfs_ioctl, apfs_vnop_setxattr, handle_snapshot_mount,
     *   apfs_load_inode_internal
     */
    uint64_t            xattr_state;            /* +0xC0 */

    /* +0xC8 (8B) [LDR] 1 ref
     * Decompression / decmpfs extra data
     *   apfs_truncate_decmpfs_unlock: LDR x8, [x20, #0xc8]
     */
    uint64_t            decmpfs_extra;          /* +0xC8 */

    /* +0xD0 (8B) [LDR] 1 ref, paired with +0xD8
     * Snapshot rename / verification data
     *   apfs_snap_vnop_rename: LDR x8, [x20, #0xd0]
     *   STP x31,x31,[x22,#0xd0] in fake_vnop_getattr (zeroed pair)
     *   LDP x9,x8,[x21,#0xd0] in vnop_verify (read pair)
     */
    uint64_t            snap_rename_data;       /* +0xD0 */

    /* +0xD8 (8B) [LDR/STR] 7 refs
     * Named stream / resource fork backlink
     *   apfs_vnop_readlink, apfs_vnop_inactive, apfs_vnop_close,
     *   apfs_get_nstream_vnode, apfs_raw_encrypted_lookup
     */
    void                *nstream_link;          /* +0xD8 */

    /* +0xE0 (8B) [LDR/STR] 4 refs
     * Symlink target / readlink data pointer
     *   apfs_vnop_readlink:  LDR x8, [x19, #0xe0]
     *   apfs_vnop_inactive:  STR xzr, [x19, #0xe0] (cleanup)
     *   apfs_raw_encrypted_lookup: LDR/STR
     */
    uint64_t            readlink_data;          /* +0xE0 */

    /* +0xE8 (4B) [LDR/STR] 3 refs
     * Inactive state flags
     *   apfs_vnop_inactive:  LDR w8, [x19, #0xe8]; STR wzr
     *   apfs_vnop_reclaim:   LDR w8, [x19, #0xe8]
     */
    uint32_t            inactive_flags;         /* +0xE8 */
    uint32_t            inactive_extra;         /* +0xEC */

    /* +0xF0 (8B) paired with +0xF8
     * IO state or pending flags
     *   LDP x12,x11,[x21,#0xf0] in fake_vnop_ioctl
     */
    uint64_t            io_state;               /* +0xF0 */

    /* +0xF8 (8B) [LDR] 5 refs
     * PFK (per-file key) state
     *   apfs_fsync_internal, apfs_raw_encrypted_lookup,
     *   apfs_vnop_listxattr, xattrs_pfk_transcribe
     */
    uint64_t            pfk_state;              /* +0xF8 */

    /* +0x100 (8B) [STR] 1 ref
     * Named stream initialization data
     *   apfs_initialize_namedstream_vnode: STR x8, [x19, #0x100]
     */
    uint64_t            nstream_init_data;      /* +0x100 */

    /* +0x108 (1B) [LDR] 1 ref
     * Inherit / doc tombstone flag
     *   inherit_doc_tombstone: LDR b8, [x20, #0x108]
     */
    uint8_t             inherit_data;           /* +0x108 */
    uint8_t             _pad_109[7];            /* +0x109..10F */

    /* +0x110 (8B) paired with +0x118
     *   STP x9,x10,[x22,#0x110] in fake_vnop_getattr
     */
    uint64_t            fake_getattr_ext1;      /* +0x110 */
    uint64_t            fake_getattr_ext2;      /* +0x118 */

    /* +0x11C — overlaps with fake_getattr_ext2
     * (4B) [LDR] 1 ref: sync state
     *   apfs_fsync_internal: LDR w8, [x21, #0x11c]
     */
    /* Note: +0x11C is within +0x118..11F; this is a sub-field access */

    /* +0x120 (8B) [LDR/STR] 5 refs
     * Unmount / snapshot mount data
     *   apfs_vfsop_unmount, handle_drop_extents_in_snap, handle_snapshot_mount
     * +0x121 (1B) 1 ref: apfs_snap_vnop_rename — sub-byte flag
     */
    union {
        uint64_t        unmount_snap_data;
        struct {
            uint8_t     unmount_flag;           /* +0x120 */
            uint8_t     snap_rename_byte;       /* +0x121 */
            uint16_t    _uspad;                 /* +0x122 */
            uint8_t     prop_flag;              /* +0x124: apfs_vnop_getattr */
            uint8_t     _uspad2[3];             /* +0x125 */
        };
    };                                          /* +0x120 */

    /* +0x128 (8B) [LDR] 1 ref, paired with +0x130
     * Purgeable file pointer
     *   remove_purgeable_file: LDR x8, [x20, #0x128]
     *   LDP x0,x1,[x19,#0x128] in vnop_setattr
     */
    uint64_t            purgeable_ptr;          /* +0x128 */
    uint64_t            purgeable_data;         /* +0x130 */

    /* +0x138..143 */
    uint64_t            _reserved_138;          /* +0x138 */
    uint32_t            _reserved_140;          /* +0x140 */

    /* +0x144 (4B) [LDR] 2 refs
     * Rename state / progress
     *   apfs_vnop_renamex: LDR w8, [x20, #0x144]
     */
    uint32_t            rename_state;           /* +0x144 */

    /* +0x148 (0x48 bytes) — extended fields (xfields) area
     * 132 ADD refs with xf_get, xf_get_ptr_and_size, xf_init
     *   apfs_pack_vap_common: ADD x0, x20, #0x148 → xf_get_ptr_and_size
     *   apfs_load_inode_internal, apfs_vnop_getattr, apfs_vnop_setattr,
     *   apfs_clone_internal, ...
     *
     * +0x15D (1B) 1 ref: apfs_snap_vnop_rename — byte within xfields
     */
    uint8_t             xfields[0x15];          /* +0x148..15C */
    uint8_t             xf_snap_flag;           /* +0x15D */
    uint8_t             xfields_rest[0x32];     /* +0x15E..18F */

    /* +0x160 (8B) [LDR] 1 ref — within xfields area
     *   apfs_load_inode_internal: LDR x8, [x20, #0x160]
     */
    /* Note: +0x160 overlaps xfields; this is a sub-field/pointer within */

    /* +0x168 (8B) [LDR] 1 ref — within xfields area
     *   apfs_load_inode_internal: LDR x8, [x20, #0x168]
     */

    /* +0x190 (8B) [LDR/STR] 14 refs
     * Clone / extent state pointer
     *   apfs_clone_internal, apfs_fsync_internal,
     *   apfs_initialize_namedstream_vnode (STR xzr = clear),
     *   apfs_nstream_read, apfs_vnop_mmap, apfs_vnop_setattr,
     *   apfs_vnop_open, apfs_load_inode_internal
     */
    uint64_t            clone_state;            /* +0x190 */

    /* +0x198..357: extended / sparse area
     * No direct field accesses found in this range from vnode_fsnode callers.
     * Likely contains:
     *   - extended clone data
     *   - snapshot-specific metadata
     *   - PFK rolling state
     *   - reservation tracking
     */
    uint8_t             _extended[0x1c0];       /* +0x198..357 */

    /* +0x358 (4B) [LDR] 1 ref
     * Snapshot rename extended state
     *   apfs_snap_vnop_rename: LDR w8, [x20, #0x358]
     */
    uint32_t            snap_rename_ext1;       /* +0x358 */

    /* +0x35C (4B) [LDR] 1 ref
     *   apfs_snap_vnop_rename: LDR w8, [x20, #0x35c]
     */
    uint32_t            snap_rename_ext2;       /* +0x35C */

    /* +0x360 (4B) [LDR] 1 ref
     * Unmount extended state
     *   apfs_vfsop_unmount: LDR w8, [x19, #0x360]
     */
    uint32_t            unmount_ext;            /* +0x360 */

    /* +0x364..3A7: gap */
    uint8_t             _tail_gap[0x44];        /* +0x364..3A7 */

    /* +0x3A8 (4B) [STR] 1 ref
     * Snapshot mount data
     *   handle_snapshot_mount: STR w8, [x20, #0x3a8]
     */
    uint32_t            snapshot_mount_data;    /* +0x3A8 */

};


/*
 * Field summary table:
 *
 * Offset  Size  Refs  Field                  Primary accessor
 * ------  ----  ----  ---------------------  ----------------
 * +0x000  1B     45   type                   vnop_reclaim, lock_vnode_cb
 * +0x008  8B     96   ino                    vnop_getattr, vnop_lookup
 * +0x010  8B      4   jhash_prev / xattr     jhash_insertvnode, inode_getxattr
 *   +014  2B      2     xattr_count          inode_getxattr
 *   +016  2B      1     xattr_flags          inode_getxattr
 * +0x018  8B      1   jhash_next             jhash_insertvnode
 * +0x020  8B     18   parent_ino             vnop_lookup, get_nstream_parent
 *   +024  2B      1     parent_sub           truncate_decmpfs_unlock
 * +0x028  4B     11   nstream_id             nstream_vnop_getattr
 * +0x02C  4B      -   internal_flags         jhash_insertvnode
 *   +02C  1B      1     reclaim_flag         vnop_reclaim
 *   +02D  1B      3     busy_flag            vnop_renamex
 * +0x030  8B      2   jhash_gate             jhash_insertvnode (gate_init)
 * +0x038  8B     14   internal_link          vnop_remove, load_fs_vnodes
 *   +039  1B      1     snap_rename_flag     snap_vnop_rename
 *   +03C  4B      2     snap_mount_state     handle_snapshot_mount
 * +0x040  8B     14   graft_state            graft, mmap_check
 * +0x048  8B      4   snap_state             fake_vnop_getattr, vfs_ioctl
 * +0x050  8B      1   fake_getattr_data      fake_vnop_getattr
 * +0x058  8B      2   mnomap_data            fake_vnop_getattr, vnop_mnomap
 * +0x060  8B      2   cleanup_data           cleanup_purgatory, vnop_setattr
 * +0x068  8B      5   crypto_state           raw_encrypted_lookup
 *   +069  1B      7     crypto_class         vnop_read, vnop_write, vnop_close
 *   +06A  1B      6     crypto_flags         vnop_mmap, load_inode_internal
 *   +06C  4B      7     crypto_extra         cleanup_purgatory, vfs_ioctl
 * +0x070  4B      6   bsd_flags              fake_vnop_getattr, vnop_getattr
 * +0x074  4B      9   gen_flags              vnop_open, vnop_setattr
 * +0x078  8B      5   mmap_state             cleanup_purgatory, vnop_mnomap
 * +0x080  4B      -   uid ★                  vnop_getattr → va_uid
 * +0x084  4B      1   gid ★                  vnop_getattr → va_gid
 * +0x088  2B     30   mode ★                 vnop_getattr → va_mode
 * +0x08A  2B      -   open_refcnt            (secondary usage of +0x88 area)
 * +0x090  8B      1   raw_enc_data           raw_encrypted_lookup
 * +0x098  8B     70   dstream                fsync, vnop_setattr, vnop_allocate
 *   +09B  1B      5     ds_close_state       vnop_close, vnop_inactive
 *   +09C  1B      3     ds_needs_zerofill    needs_zerofill
 *   +09D  1B     28     ds_compression_flags vnop_getattr, vnop_open/read/write
 *   +09E  1B      1     ds_nstream_flag      nstream_vnop_pagein
 * +0x0A0  16B   300+  rw_lock (lck_rw_t)     ALL vnop functions
 * +0x0B0  8B      7   decmpfs_cnode          vnop_open, pack_vap_common
 * +0x0B8  8B      -   xattr_inline           pack_vap_common
 * +0x0C0  8B      4   xattr_state            vnop_setxattr, vfs_ioctl
 * +0x0C8  8B      1   decmpfs_extra          truncate_decmpfs_unlock
 * +0x0D0  8B      1   snap_rename_data       snap_vnop_rename
 * +0x0D8  8B      7   nstream_link           vnop_readlink, vnop_inactive
 * +0x0E0  8B      4   readlink_data          vnop_readlink, vnop_inactive
 * +0x0E8  4B      3   inactive_flags         vnop_inactive, vnop_reclaim
 * +0x0F0  8B      -   io_state               fake_vnop_ioctl
 * +0x0F8  8B      5   pfk_state              fsync, raw_encrypted_lookup
 * +0x100  8B      1   nstream_init_data      initialize_namedstream_vnode
 * +0x108  1B      1   inherit_data           inherit_doc_tombstone
 * +0x110  8B      -   fake_getattr_ext1      fake_vnop_getattr (STP)
 * +0x118  8B      -   fake_getattr_ext2      fake_vnop_getattr (STP)
 * +0x11C  4B      1   sync_state             fsync_internal
 * +0x120  8B      5   unmount_snap_data      vfsop_unmount, snapshot_mount
 *   +121  1B      1     snap_rename_byte     snap_vnop_rename
 *   +124  1B      1     prop_flag            vnop_getattr
 * +0x128  8B      1   purgeable_ptr          remove_purgeable_file, vnop_setattr
 * +0x130  8B      -   purgeable_data         vnop_setattr (LDP pair)
 * +0x144  4B      2   rename_state           vnop_renamex
 * +0x148  72B   132   xfields                xf_get, xf_get_ptr_and_size
 *   +15D  1B      1     xf_snap_flag         snap_vnop_rename
 *   +160  8B      1     (within xfields)     load_inode_internal
 *   +168  8B      1     (within xfields)     load_inode_internal
 * +0x190  8B     14   clone_state            clone_internal, vnop_mmap, vnop_setattr
 * +0x358  4B      1   snap_rename_ext1       snap_vnop_rename
 * +0x35C  4B      1   snap_rename_ext2       snap_vnop_rename
 * +0x360  4B      1   unmount_ext            vfsop_unmount
 * +0x3A8  4B      1   snapshot_mount_data    handle_snapshot_mount
 *
 */
