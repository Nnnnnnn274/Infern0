#include <stdio.h>
#include "../kexploit/krw.h"
#include "ds_bridge.h"
#include "../kexploit/offsets.h"
#include "../XPF/src/xpf.h"
#include "../kexploit/kutils.h"
#include "../kexploit/kexploit_opa334.h"
#include "../kexploit/lara_compat.h"
#import <Foundation/Foundation.h>

uint64_t ds_kread64(uint64_t address) {
    return kread64(address);
}

uint32_t ds_kread32(uint64_t address) {
    return kread32(address);
}

uint16_t ds_kread16(uint64_t addr) {
    return kread16(addr);
}

uint8_t ds_kread8(uint64_t addr) {
    return kread8(addr);
}

void ds_kwrite64(uint64_t address, uint64_t value) {
    kwrite64(address, value);
}

void ds_kwrite32(uint64_t address, uint32_t value) {
    kwrite32(address, value);
}

void ds_kwrite16(uint64_t addr, uint16_t val) {
    kwrite16(addr, val);   
}

void ds_kwrite8(uint64_t what, uint8_t val) {
    kwrite8(what, val);
}

void ds_kread(uint64_t address, void *buffer, uint64_t size) {
    kread(address, buffer, size);
}

void ds_kreadbuf(uint64_t address, void *buffer, uint64_t size) {
    kread(address, buffer, size);
}

void ds_kwrite(uint64_t address, void *buffer, uint64_t size) {
    kwrite(address, buffer, size);
}

uint64_t ds_get_our_proc(void) {
    uint64_t proc = proc_self();
    return proc;
}

uint64_t ds_get_our_task(void) {
    uint64_t task = task_self();
    return task;
}

uint64_t ds_kreadptr(uint64_t va) {
    uint64_t res = kread_ptr(va);
    return res;
}

uint64_t ds_kreadsmrptr(uint64_t va) {
    return kread_smrptr(va);
}

uint64_t ds_kallocarrdec(uint64_t pointer) {
    return kalloc_array_decode(pointer);
}

uint64_t ds_get_kernel_base(void) {
    return g_kernel_base;
}

uint64_t ds_get_kernel_slide(void) {
    return g_kernel_slide;
}

cpu_subtype_t get_hw_cpufamily(void) {
    cpu_subtype_t cpuFamily = 0;
    size_t cpuFamilySize = sizeof(cpuFamily);
    sysctlbyname("hw.cpufamily", &cpuFamily, &cpuFamilySize, NULL, 0);
    return cpuFamily;
}

bool ds_is_ready(void) {
    bool result = infern0_lara_krw_ready();
    return result;
}

void lara_offsets_init(void) {
    offsets_init();
}

int ds_run(void) {
    int res = kexploit_opa334();
    return res;
}
