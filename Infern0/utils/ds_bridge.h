#ifndef ds_bridge_h
#define ds_bridge_h

#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#import <Foundation/Foundation.h>

uint64_t ds_kread64(uint64_t address);
uint32_t ds_kread32(uint64_t address);
uint16_t ds_kread16(uint64_t addr);
uint8_t ds_kread8(uint64_t addr);
void ds_kwrite64(uint64_t address, uint64_t value);
void ds_kwrite32(uint64_t address, uint32_t value);
void ds_kwrite16(uint64_t addr, uint16_t val);
void ds_kwrite8(uint64_t what, uint8_t val);
void ds_kread(uint64_t address, void *buffer, uint64_t size);
void ds_kreadbuf(uint64_t address, void *buffer, uint64_t size);
void ds_kwrite(uint64_t address, void *buffer, uint64_t size);
uint64_t ds_get_our_proc(void);
uint64_t ds_get_our_task(void);
uint64_t ds_get_kernel_base(void);
uint64_t ds_get_kernel_slide(void);
uint64_t ds_kreadptr(uint64_t va);
uint64_t ds_kreadsmrptr(uint64_t va);
uint64_t ds_kallocarrdec(uint64_t pointer);
cpu_subtype_t get_hw_cpufamily(void);
bool is_pac_supported(void);
bool ds_is_ready(void);
void lara_offsets_init(void);
int ds_run(void);

#endif
