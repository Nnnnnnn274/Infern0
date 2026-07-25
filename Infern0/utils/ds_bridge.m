#include <stdio.h>
#include "kexploit/krw.h"
#include "ds_bridge.h"
#include "../kexploit/offsets.h"
#include "../XPF/src/xpf.h"
#import <Foundation/Foundation.h>

uint64_t pac_mask = 0;
uint64_t t1sz_boot = xpf_gett1szboot();

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

void ds_kwrite(uint64_t address, void *buffer, uint64_t size) {
    kwrite(address, buffer, size);
}

uint64_t ds_get_our_proc() {
    uint64_t proc = proc_self();
    return proc;
}

static void refreshpacmask(void) {
    if (t1sz_boot == 0) {
        pac_mask = 0;
        return;
    }

    if (t1sz_boot >= 64) {
        pac_mask = 0;
        return;
    }

    pac_mask = ~((1ULL << (64 - t1sz_boot)) - 1ULL);
}

cpu_subtype_t get_hw_cpufamily(void) {
    cpu_subtype_t cpuFamily = 0;
    size_t cpuFamilySize = sizeof(cpuFamily);
    sysctlbyname("hw.cpufamily", &cpuFamily, &cpuFamilySize, NULL, 0);
    return cpuFamily;
}