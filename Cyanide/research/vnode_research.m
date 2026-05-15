//
//  vnode_research.m
//  Cyanide
//
//  Created by seo on 4/6/26.
//

#import <Foundation/Foundation.h>

#import "vnode_research.h"
#import "../kexploit/vnode.h"
#import "../kexploit/kutils.h"
#import "../kexploit/krw.h"
#import "apfs_fsnode.h"
#import "../LogTextView.h"

int research_vnode_apfs_fsnode(const char* filename) {
    uint64_t vnode = 0;
    if(strcmp(filename, "/") == 0)
    {
        vnode = get_rootvnode();
    }
    else
    {
        vnode = get_vnode_for_path_by_open(filename);
        if(vnode == -1)
        {
            printf("[-] Unable to get vnode, path: %s", filename);
            return -1;
        }
    }
    
    uint64_t v_data = kread64(vnode + off_vnode_v_data);
    if (!v_data) {
        printf("[-] v_data is NULL for %s\n", filename);
        return -1;
    }

    struct apfs_fsnode fn = {0};
    kreadbuf(v_data, &fn, sizeof(struct apfs_fsnode));

    printf("============================================================\n");
    printf("  apfs_fsnode dump: %s\n", filename);
    printf("  vnode=0x%llx  v_data=0x%llx  size=0x%lx\n",
           vnode, v_data, sizeof(struct apfs_fsnode));
    printf("============================================================\n\n");

    /* --- Identity --- */
    printf("--- Identity ---\n");
    printf("  [+0x000] type               = 0x%02x\n", fn.type);
    printf("  [+0x008] ino                = %llu (0x%llx)\n", fn.ino, fn.ino);
    printf("  [+0x020] parent_ino_or_owner_vnode         = %llu (0x%llx)\n", fn.parent_ino_or_owner_vnode, fn.parent_ino_or_owner_vnode);
    printf("    [+0x024] parent_sub       = 0x%04x\n", fn.parent_sub);
    printf("  [+0x028] nstream_id         = %u\n", fn.nstream_id);

    /* --- jhash linkage --- */
    printf("\n--- jhash linkage ---\n");
    printf("  [+0x010] jhash_prev         = 0x%llx\n", fn.jhash_prev);
    printf("    [+0x014] xattr_count      = %u\n", fn.xattr_count);
    printf("    [+0x016] xattr_flags      = 0x%04x\n", fn.xattr_flags);
    printf("  [+0x018] jhash_next         = 0x%llx\n", fn.jhash_next);
    printf("  [+0x030] jhash_gate         = 0x%llx\n", (uint64_t)fn.jhash_gate);

    /* --- Flags --- */
    printf("\n--- Flags ---\n");
    printf("  [+0x02C] internal_flags     = 0x%08x\n", fn.internal_flags);
    printf("    [+0x02C] reclaim_flag     = 0x%02x\n", fn.reclaim_flag);
    printf("    [+0x02D] busy_flag        = 0x%02x\n", fn.busy_flag);
    printf("  [+0x070] bsd_flags          = 0x%08x", fn.bsd_flags);
    if (fn.bsd_flags) {
        printf(" (");
        if (fn.bsd_flags & 0x00000001) printf("NODUMP ");
        if (fn.bsd_flags & 0x00000002) printf("IMMUTABLE ");
        if (fn.bsd_flags & 0x00000004) printf("APPEND ");
        if (fn.bsd_flags & 0x00000008) printf("OPAQUE ");
        if (fn.bsd_flags & 0x00008000) printf("HIDDEN ");
        if (fn.bsd_flags & 0x00020000) printf("TRACKED ");
        if (fn.bsd_flags & 0x00040000) printf("DATAVAULT ");
        if (fn.bsd_flags & 0x00080000) printf("SF_RESTRICTED ");
        printf("\b)");
    }
    printf("\n");
    printf("  [+0x074] gen_flags          = 0x%08x\n", fn.gen_flags);
    printf("  [+0x07C] ino_flags          = 0x%02x\n", *((uint8_t*)&fn + 0x7C));
    printf("  [+0x08C] ino_flags_ext      = 0x%08x\n", fn.ino_flags_ext);

    /* --- POSIX ownership & permissions --- */
    printf("\n--- POSIX ownership & permissions ---\n");
    printf("  [+0x080] uid                = %u\n", fn.uid);
    printf("  [+0x084] gid                = %u\n", fn.gid);
    printf("  [+0x088] mode               = 0%o", fn.mode);
    {
        char p[] = "----------";
        uint16_t m = fn.mode;
        if (fn.type == 4) p[0] = 'd';
        else if (fn.type == 10) p[0] = 'l';
        if (m & 0400) p[1] = 'r'; if (m & 0200) p[2] = 'w';
        if (m & 0100) p[3] = (m & 04000) ? 's' : 'x'; else if (m & 04000) p[3] = 'S';
        if (m & 040) p[4] = 'r';  if (m & 020) p[5] = 'w';
        if (m & 010) p[6] = (m & 02000) ? 's' : 'x'; else if (m & 02000) p[6] = 'S';
        if (m & 04) p[7] = 'r';   if (m & 02) p[8] = 'w';
        if (m & 01) p[9] = (m & 01000) ? 't' : 'x'; else if (m & 01000) p[9] = 'T';
        printf(" (%s)", p);
    }
    printf("\n");
    printf("  [+0x08A] open_refcnt        = %u\n", fn.open_refcnt);

    /* --- Internal state --- */
    printf("\n--- Internal state ---\n");
    printf("  [+0x038] internal_link      = 0x%llx\n", fn.internal_link);
    printf("    [+0x039] snap_rename_flag = 0x%02x\n", fn.snap_rename_flag);
    printf("    [+0x03C] snap_mount_state = 0x%08x\n", fn.snap_mount_state);
    printf("  [+0x040] graft_state        = 0x%llx\n", fn.graft_state);
    printf("  [+0x048] snap_state         = 0x%llx\n", fn.snap_state);
    printf("  [+0x050] fake_getattr_data  = 0x%llx\n", fn.fake_getattr_data);
    printf("  [+0x058] mnomap_data        = 0x%llx\n", fn.mnomap_data);
    printf("  [+0x060] cleanup_data       = 0x%llx\n", fn.cleanup_data);
    printf("  [+0x078] mmap_state         = 0x%llx\n", fn.mmap_state);

    /* --- Crypto --- */
    printf("\n--- Crypto ---\n");
    printf("  [+0x068] crypto_state       = 0x%llx\n", fn.crypto_state);
    printf("    [+0x069] crypto_class     = 0x%02x", fn.crypto_class);
    switch (fn.crypto_class) {
        case 0: printf(" (NONE)"); break;
        case 1: printf(" (A — Complete Protection)"); break;
        case 2: printf(" (B — Protected Unless Open)"); break;
        case 3: printf(" (C — Protected Until First Auth)"); break;
        case 4: printf(" (D — No Protection)"); break;
        default: printf(" (unknown)"); break;
    }
    printf("\n");
    printf("    [+0x06A] crypto_flags     = 0x%02x\n", fn.crypto_flags);
    printf("    [+0x06C] crypto_extra     = 0x%08x\n", fn.crypto_extra);
    printf("  [+0x090] raw_enc_data       = 0x%llx\n", fn.raw_enc_data);
    printf("  [+0x0F8] pfk_state          = 0x%llx\n", fn.pfk_state);

    /* --- Data stream --- */
    printf("\n--- Data stream ---\n");
    printf("  [+0x098] dstream            = 0x%llx\n", fn.dstream);
    printf("    [+0x09B] ds_close_state   = 0x%02x\n", fn.ds_close_state);
    printf("    [+0x09C] ds_needs_zerofill= 0x%02x\n", fn.ds_needs_zerofill);
    printf("    [+0x09D] ds_compress_flags= 0x%02x\n", fn.ds_compression_flags);
    printf("    [+0x09E] ds_nstream_flag  = 0x%02x\n", fn.ds_nstream_flag);
    printf("  [+0x190] clone_state        = 0x%llx\n", fn.clone_state);

    /* --- Lock --- */
    printf("\n--- Lock ---\n");
    printf("  [+0x0A0] rw_lock[0]         = 0x%llx\n", fn.rw_lock[0]);
    printf("  [+0x0A8] rw_lock[1]         = 0x%llx\n", fn.rw_lock[1]);

    /* --- Compression / decmpfs --- */
    printf("\n--- Compression ---\n");
    printf("  [+0x0B0] decmpfs_cnode      = 0x%llx\n", (uint64_t)fn.decmpfs_cnode);
    printf("  [+0x0C8] decmpfs_extra      = 0x%llx\n", fn.decmpfs_extra);

    /* --- xattr --- */
    printf("\n--- Extended attributes ---\n");
    printf("  [+0x0B8] xattr_inline       = 0x%llx\n", fn.xattr_inline);
    printf("  [+0x0C0] xattr_state        = 0x%llx\n", fn.xattr_state);

    /* --- Named stream / symlink --- */
    printf("\n--- Named stream / symlink ---\n");
    printf("  [+0x0D0] snap_rename_data   = 0x%llx\n", fn.snap_rename_data);
    printf("  [+0x0D8] nstream_link       = 0x%llx\n", (uint64_t)fn.nstream_link);
    printf("  [+0x0E0] readlink_data      = 0x%llx\n", fn.readlink_data);
    printf("  [+0x100] nstream_init_data  = 0x%llx\n", fn.nstream_init_data);

    /* --- Lifecycle --- */
    printf("\n--- Lifecycle ---\n");
    printf("  [+0x0E8] inactive_flags     = 0x%08x\n", fn.inactive_flags);
    printf("  [+0x0F0] io_state           = 0x%llx\n", fn.io_state);
    printf("  [+0x108] inherit_data       = 0x%02x\n", fn.inherit_data);
    printf("  [+0x11C] sync_state         = 0x%08x\n",
           *(uint32_t*)((uint8_t*)&fn + 0x11C));

    /* --- Unmount / snapshot --- */
    printf("\n--- Unmount / snapshot ---\n");
    printf("  [+0x120] unmount_snap_data  = 0x%llx\n", fn.unmount_snap_data);
    printf("    [+0x120] unmount_flag     = 0x%02x\n", fn.unmount_flag);
    printf("    [+0x121] snap_rename_byte = 0x%02x\n", fn.snap_rename_byte);
    printf("    [+0x124] prop_flag        = 0x%02x\n", fn.prop_flag);
    printf("  [+0x358] snap_rename_ext1   = 0x%08x\n", fn.snap_rename_ext1);
    printf("  [+0x35C] snap_rename_ext2   = 0x%08x\n", fn.snap_rename_ext2);
    printf("  [+0x360] unmount_ext        = 0x%08x\n", fn.unmount_ext);
    printf("  [+0x3A8] snapshot_mount_data= 0x%08x\n", fn.snapshot_mount_data);

    /* --- Purgeable / rename --- */
    printf("\n--- Purgeable / rename ---\n");
    printf("  [+0x128] purgeable_ptr      = 0x%llx\n", fn.purgeable_ptr);
    printf("  [+0x130] purgeable_data     = 0x%llx\n", fn.purgeable_data);
    printf("  [+0x144] rename_state       = 0x%08x\n", fn.rename_state);

    /* --- Extended fields (xfields, +0x148) --- */
    printf("\n--- Extended fields (+0x148, %lu bytes) ---\n",
           sizeof(fn.xfields) + 1 + sizeof(fn.xfields_rest));
    printf("  [+0x148] xfields hex dump:\n    ");
    uint8_t *xf_base = (uint8_t*)&fn + 0x148;
    for (int i = 0; i < 0x48; i++) {
        printf("%02x ", xf_base[i]);
        if ((i + 1) % 16 == 0) printf("\n    ");
    }
    printf("\n");
    printf("    [+0x15D] xf_snap_flag    = 0x%02x\n", fn.xf_snap_flag);
    printf("    [+0x160] xf_ptr1         = 0x%llx\n",
           *(uint64_t*)((uint8_t*)&fn + 0x160));
    printf("    [+0x168] xf_ptr2         = 0x%llx\n",
           *(uint64_t*)((uint8_t*)&fn + 0x168));

    /* --- Fake getattr extensions --- */
    printf("\n--- Fake getattr extensions ---\n");
    printf("  [+0x110] fake_getattr_ext1  = 0x%llx\n", fn.fake_getattr_ext1);
    printf("  [+0x118] fake_getattr_ext2  = 0x%llx\n", fn.fake_getattr_ext2);

    /* --- Cross-check with stat() --- */
    printf("\n--- stat() cross-check ---\n");
    struct stat st;
    if (stat(filename, &st) == 0) {
        printf("  stat.st_ino  = %llu %s\n",
               st.st_ino, st.st_ino == fn.ino ? "(match)" : "(MISMATCH!)");
        printf("  stat.st_uid  = %u %s\n",
               st.st_uid, st.st_uid == fn.uid ? "(match)" : "(MISMATCH!)");
        printf("  stat.st_gid  = %u %s\n",
               st.st_gid, st.st_gid == fn.gid ? "(match)" : "(MISMATCH!)");
        printf("  stat.st_mode = 0%o %s\n",
               st.st_mode & 07777,
               (st.st_mode & 07777) == fn.mode ? "(match)" : "(MISMATCH!)");
        printf("  stat.st_flags= 0x%x %s\n",
               st.st_flags,
               st.st_flags == fn.bsd_flags ? "(match)" : "(MISMATCH!)");
    } else {
        printf("  stat() failed: %s\n", strerror(errno));
    }

    printf("\n============================================================\n");
    
    return 0;
}
