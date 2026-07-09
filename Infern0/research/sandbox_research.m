//
//  sandbox_research.m
//  Cyanide
//
//  Created by seo on 4/6/26.
//

#import <Foundation/Foundation.h>

#import "sandbox_research.h"
#import "../utils/sandbox.h"
#import "../kexploit/kutils.h"
#import "../kexploit/krw.h"
#import "../LogTextView.h"

int research_sandbox(uint64_t proc) {
    uint64_t label = proc_get_cred_label(proc);
    uint64_t sbx = label_get_sandbox(label);
    
    struct sandbox_label sbx_lbl = {0};
    kreadbuf(sbx, &sbx_lbl, sizeof(struct sandbox_label));
    uint64_t ext_set_kptr = (uint64_t)sbx_lbl.extension_set;
    
    printf("sbx_lbl->ext_set = 0x%llx\n", ext_set_kptr);
    
    struct extension_set ext_set = {0};
    kreadbuf(ext_set_kptr, &ext_set, sizeof(struct extension_set));
    for(int i = 0; i < 9; i++) {
        uint64_t ext_class_node_kptr = (uint64_t)ext_set.type_buckets[i];
        printf("type_buckets[%d] = 0x%llx\n", i, ext_class_node_kptr);
        if(ext_class_node_kptr != 0) {
            struct extension_class_node ext_class_node = {0};
            kreadbuf(ext_class_node_kptr, &ext_class_node, sizeof(ext_class_node));
            
            printf("  extension_class_node @ 0x%llx\n", ext_class_node_kptr);
            printf("    next           = 0x%llx\n", (uint64_t)ext_class_node.next);
            printf("    ext_list_head  = 0x%llx\n", (uint64_t)ext_class_node.ext_list_head);
            printf("    class_name     = 0x%llx", (uint64_t)ext_class_node.class_name);
            if (ext_class_node.class_name) {
                char name[128] = {0};
                kreadbuf((uint64_t)ext_class_node.class_name, name, 127);
                printf(" \"%s\"", name);
            }
            printf("\n");
            
            
            uint64_t ext_kptr = (uint64_t)ext_class_node.ext_list_head;
            if (ext_kptr != 0) {
                struct extension ext = {0};
                kreadbuf(ext_kptr, &ext, sizeof(ext));
                
                printf("  extension @ 0x%llx\n", ext_kptr);
                printf("    next         = 0x%llx\n", (uint64_t)ext.next);
                printf("    handle       = 0x%llx\n", ext.handle);
                printf("    refcnt       = %u\n", ext.refcnt);
                printf("    type         = %u\n", ext.type);
                printf("    flags        = 0x%x\n", ext.flags);
                printf("    refgrp       = 0x%llx\n", (uint64_t)ext.refgrp);
                printf("    data_ptr     = 0x%llx\n", (uint64_t)ext.data_ptr);
                if (ext.type <= 1) {
                    printf("    path_len     = %llu\n", ext.path_len);
                    if (ext.data_ptr) {
                        char buf[256] = {0};
                        kreadbuf((uint64_t)ext.data_ptr, buf, 255);
                        printf("    path         = \"%s\"\n", buf);
                    }
                    printf("    consumed     = %u\n", ext.file.consumed);
                    printf("    storage_cls  = 0x%x\n", ext.file.storage_class);
                    printf("    st_dev       = 0x%x\n", ext.file.st_dev);
                    printf("    st_ino       = 0x%llx\n", ext.st_ino);
                }
                printf("    sc_prev      = 0x%llx\n", (uint64_t)ext.sc_prev);
                printf("    sc_next      = 0x%llx\n", (uint64_t)ext.sc_next);
            }
        }
    }
    puts("============");
    
    return 0;
}
