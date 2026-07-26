//
//  apfs.m
//  lara
//
//  Created by ruter on 09.04.26.
//

#import "darksword.h"
#import "offsets.h"
#import "utils.h"
#import "xpaci.h"

#include <stdint.h>
#include <sys/stat.h>
#include <unistd.h>
#include <stdio.h>
#include <sys/types.h>

struct apfs_fsnode {
    uint8_t             type;
    uint8_t             _type_pad[7];
    uint64_t            ino;

    union {
        uint64_t        jhash_prev;
        struct {
            uint32_t    _jhash_prev_lo;
            uint16_t    xattr_count;
            uint16_t    xattr_flags;
        };
    };

    uint64_t            jhash_next;

    union {
        uint64_t        parent_ino_or_owner_vnode;
        struct {
            uint32_t    parent_ino_lo;
            uint16_t    parent_sub;
            uint16_t    _parent_pad;
        };
    };

    uint32_t            nstream_id;

    union {
        uint32_t        internal_flags;
        struct {
            uint8_t     reclaim_flag;
            uint8_t     busy_flag;
            uint16_t    internal_flags_hi;
        };
    };

    void                *jhash_gate;

    union {
        uint64_t        internal_link;
        struct {
            uint8_t     _link_base;
            uint8_t     snap_rename_flag;
            uint16_t    _link_pad;
            uint32_t    snap_mount_state;
        };
    };

    uint64_t            graft_state;
    uint64_t            snap_state;
    uint64_t            fake_getattr_data;
    uint64_t            mnomap_data;
    uint64_t            cleanup_data;

    union {
        uint64_t        crypto_state;
        struct {
            uint8_t     _crypto_base;
            uint8_t     crypto_class;
            uint8_t     crypto_flags;
            uint8_t     _crypto_pad;
            uint32_t    crypto_extra;
        };
    };

    uint32_t            bsd_flags;
    uint32_t            gen_flags;
    uint64_t            mmap_state;
    uid_t               uid;
    gid_t               gid;
    uint16_t            mode;
    uint16_t            open_refcnt;
    uint32_t            ino_flags_ext;
    uint64_t            raw_enc_data;

    union {
        uint64_t        dstream;
        struct {
            uint8_t     _ds_bytes[3];
            uint8_t     ds_close_state;
            uint8_t     ds_needs_zerofill;
            uint8_t     ds_compression_flags;
            uint8_t     ds_nstream_flag;
            uint8_t     _ds_pad;
        };
    };

    uint64_t            rw_lock[2];
    void                *decmpfs_cnode;
    uint64_t            xattr_inline;
    uint64_t            xattr_state;
    uint64_t            decmpfs_extra;
    uint64_t            snap_rename_data;
    void                *nstream_link;
    uint64_t            readlink_data;
    uint32_t            inactive_flags;
    uint32_t            inactive_extra;
    uint64_t            io_state;
    uint64_t            pfk_state;
    uint64_t            nstream_init_data;
    uint8_t             inherit_data;
    uint8_t             _pad_109[7];
    uint64_t            fake_getattr_ext1;
    uint64_t            fake_getattr_ext2;

    union {
        uint64_t        unmount_snap_data;
        struct {
            uint8_t     unmount_flag;
            uint8_t     snap_rename_byte;
            uint16_t    _uspad;
            uint8_t     prop_flag;
            uint8_t     _uspad2[3];
        };
    };

    uint64_t            purgeable_ptr;
    uint64_t            purgeable_data;
    uint64_t            _reserved_138;
    uint32_t            _reserved_140;
    uint32_t            rename_state;
    uint8_t             xfields[0x15];
    uint8_t             xf_snap_flag;
    uint8_t             xfields_rest[0x32];
    uint64_t            clone_state;
    uint8_t             _extended[0x1c0];
    uint32_t            snap_rename_ext1;
    uint32_t            snap_rename_ext2;
    uint32_t            unmount_ext;
    uint8_t             _tail_gap[0x44];
    uint32_t            snapshot_mount_data;
};

uint64_t getvnodefor(const char *path) {
    int fd = open(path, O_RDONLY);
    if (fd == -1) return -1;

    uint64_t self_proc = ds_get_our_proc();
    if (!self_proc && islcruntime()) {
        self_proc = ourproc();
        if (!self_proc) {
            printf("(apfs) failed to recover our proc in LiveContainer\n");
            close(fd);
            return -1;
        }
    }
    if (!self_proc) {
        close(fd);
        return -1;
    }
    
    uint64_t fileprocPtrArr = ds_kread64(self_proc + off_proc_p_fd + off_filedesc_fd_ofiles);
    fileprocPtrArr = xpaci(fileprocPtrArr);
    if (!fileprocPtrArr) {
        close(fd);
        return -1;
    }
    uint64_t fileproc = ds_kread64(fileprocPtrArr + (8 * fd));
    if (!fileproc) {
        close(fd);
        return -1;
    }
    uint64_t fp_glob = ds_kread64(fileproc + off_fileproc_fp_glob);
    fp_glob = xpaci(fp_glob);
    if (!fp_glob) {
        close(fd);
        return -1;
    }
    uint64_t vnode = ds_kread64(fp_glob + off_fileglob_fg_data);
    vnode = xpaci(vnode);
    
    close(fd);
    return vnode;
}

uint32_t apfs_getuid(uint64_t fs_node) {
    return ds_kread32(fs_node + offsetof(struct apfs_fsnode, uid));
}

uint32_t apfs_getgid(uint64_t fs_node) {
    return ds_kread32(fs_node + offsetof(struct apfs_fsnode, gid));
}

uint16_t apfs_getmode(uint64_t fs_node) {
    return ds_kread16(fs_node + offsetof(struct apfs_fsnode, mode));
}

void apfs_setuid(uint64_t fs_node, uint32_t uid) {
    ds_kwrite32(fs_node + offsetof(struct apfs_fsnode, uid), uid);
}

void apfs_setgid(uint64_t fs_node, uint32_t gid) {
    ds_kwrite32(fs_node + offsetof(struct apfs_fsnode, gid), gid);
}

void apfs_setmode(uint64_t fs_node, uint16_t mode) {
    ds_kwrite16(fs_node + offsetof(struct apfs_fsnode, mode), mode);
}

int apfs_own(const char* filename, uid_t uid, gid_t gid) {
    uint64_t vnode = getvnodefor(filename);
    if (vnode == -1) {
        printf("unable to get vnode: %s\n", filename);
        return -1;
    }
    
    uint64_t fs_node = ds_kread64(vnode + off_vnode_v_data);
    apfs_setuid(fs_node, uid);
    apfs_setgid(fs_node, gid);
    
    sync(); sync(); sync();

    struct stat st;
    if (stat(filename, &st) != 0) return -1;

    if (st.st_uid != uid || st.st_gid != gid) return -1;

    return 0;
}

int apfs_mod(const char* filename, mode_t mode) {
    uint64_t vnode = getvnodefor(filename);
    if (vnode == -1) {
        printf("unable to get vnode: %s\n", filename);
        return -1;
    }
    
    uint64_t fs_node = ds_kread64(vnode + off_vnode_v_data);
    apfs_setmode(fs_node, mode);
    
    sync(); sync(); sync();

    struct stat st;
    if (stat(filename, &st) != 0) return -1;

    if (st.st_mode != mode) return -1;

    return 0;
}
