//
//  sandbox_research.h
//  Cyanide
//
//  Created by seo on 4/6/26.
//

struct lck_rw {
    uintptr_t opaque[2];
};

// Below structure code related sandbox is created/reversed by Claude AI, so might be inaccurate.
// FYI: Reversing kernelcache is ipad air m3(T8122)/18.3.x/DEVELOPMENT
struct extension {
    /* +0x00 */ struct extension *next;
    /* +0x08 */ uint64_t handle;             // -1 if not consumed
    /* +0x10 */ uint64_t inline_data[4];     // internal (zeros)
    
    /* +0x30 */ uint32_t refcnt;
    /* +0x34 */ uint8_t  type;               // 0=FILE, 1=STRING, ...
    /* +0x35 */ uint8_t  flags;
    /* +0x36 */ uint16_t _pad36;
    /* +0x38 */ void    *refgrp;             // os_ref group (can be NULL)

    /* +0x40 - type-dependent pointer */
    union {
        void    *data_ptr;                   // FILE:   path buffer kaddr
        void    *aux_ptr;                    // STRING: auxiliary pointer
    };

    /* +0x48 */
    union {
        uint64_t path_len;                   // FILE:   strlen(path)
        char    *ext_string;                 // STRING: extension string kaddr
    };

    /* +0x50 */
    union {
        struct {                             // FILE type
            uint8_t  consumed;               // +0x50
            uint8_t  storage_class;          // +0x51
            uint8_t  _pad52[2];              // +0x52
            uint32_t st_dev;                 // +0x54
        } file;
        uint64_t ext_string_len;             // STRING: strlen
    };

    /* +0x58 */ uint64_t st_ino;             // FILE: inode, STRING: 0
    /* +0x60 */ uint64_t _reserved;
    /* +0x68 */ struct extension *sc_prev;    // storage-class chain
    /* +0x70 */ struct extension *sc_next;
};

struct extension_sc_node {
    struct extension_sc_node *next;              // +0x00
    struct extension         *ext_sc_head;       // +0x08
    uint8_t              storage_class_id;  // +0x10
    uint8_t              _pad[7];           // +0x11
};

struct extension_class_node {
    struct extension_class_node *next;           // +0x00
    struct extension            *ext_list_head;  // +0x08
    char                   *class_name;     // +0x10
};

struct extension_set {
    struct extension_class_node *type_buckets[9];   // +0x00~+0x47 (9 × 8 = 72)
    struct extension_sc_node    *sc_buckets[9];     // +0x48~+0x8F (9 × 8 = 72)
    uint64_t                handle_counter;    // +0x90 (atomic)
    struct lck_rw                ext_lock;          // +0x98
    uint64_t                set_metadata_1;    // +0xA0
    uint64_t                set_metadata_2;    // +0xA8
};

struct sandbox_label {
    void               *profile;
    uint64_t            flags;
    struct extension_set    *extension_set;
    uint64_t            mem_usage;
    uint64_t            mem_limit;
    uint64_t            refcnt_area_1;
    uint64_t            refcnt_area_2;
    uint64_t            sb_flags2;
    uint64_t            sb_data1;
    uint64_t            sb_data2;
    uint64_t            capacity;
    void               *extra_ptr;
    uint64_t            sb_data3;
};

#define SC_ISSUED           0x02   /* sandbox_extension_issue_file */
#define SC_CONTAINER        0x07   /* app data container (/var/mobile/Containers/Data/...) */
#define SC_EXECUTABLE       0x0A   /* app bundle (/var/containers/Bundle/Application/...) */
#define SC_BYPASS           0xFF   /* IDK */

int research_sandbox(uint64_t proc);
