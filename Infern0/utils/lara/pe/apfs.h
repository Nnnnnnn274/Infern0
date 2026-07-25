//
//  apfs.h
//  lara
//
//  Created by ruter on 10.04.26.
//

#ifndef APFS_H
#define APFS_H

#include <stdint.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>

struct apfs_fsnode;

uint64_t getvnodefor(const char *path);

uint32_t apfs_getuid(uint64_t fs_node);
uint32_t apfs_getgid(uint64_t fs_node);
uint16_t apfs_getmode(uint64_t fs_node);

void apfs_setuid(uint64_t fs_node, uint32_t uid);
void apfs_setgid(uint64_t fs_node, uint32_t gid);
void apfs_setmode(uint64_t fs_node, uint16_t mode);

int apfs_own(const char* filename, uid_t uid, gid_t gid);
int apfs_mod(const char* filename, mode_t mode);

#endif /* APFS_H */
