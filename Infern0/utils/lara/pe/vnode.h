//
//  vnode.h
//  lara
//
//  Created by ruter on 13.04.26.
//

#ifndef vnode_h
#define vnode_h

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <sys/stat.h>

#define vnodebychdir lara_vnodebychdir
#define vnodebyfd lara_vnodebyfd
#define vnodebyopen lara_vnodebyopen
#define vn_folderredirect lara_vn_folderredirect
#define vn_folderunredirect lara_vn_folderunredirect
#define vn_vname lara_vn_vname
#define vn_childvnode lara_vn_childvnode
#define vn_fileredirect lara_vn_fileredirect
#define vn_fileunredirect lara_vn_fileunredirect
#define vn_fsnode lara_vn_fsnode
#define vp_name lara_vp_name

uint64_t vnodebychdir(const char *path);
uint64_t vnodebyfd(int fd);
uint64_t vnodebyopen(const char *path);
uint64_t vn_folderredirect(const char *to, const char *from);
bool vn_folderunredirect(const char *folder, uint64_t orig_to_v_data);
char* vn_vname(uint64_t vnode);
uint64_t vn_childvnode(uint64_t vnode, const char* child_filename, uint64_t blacklist_vdata);
bool vn_fileredirect(const char *to, const char *from, uint64_t* orig_to_vnode, uint64_t* orig_to_v_data);
bool vn_fileunredirect(uint64_t orig_to_vnode, uint64_t orig_to_v_data);
uint64_t vn_fsnode(uint64_t vp);

#endif /* vnode_h */
