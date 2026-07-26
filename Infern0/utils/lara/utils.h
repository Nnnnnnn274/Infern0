//
//  utils.h
//  lara
//
//  Created by ruter on 25.03.26.
//

#ifndef utils_h
#define utils_h

#include <stdint.h>
#include <unistd.h>
#include <sys/types.h>
#include <stdbool.h>
#include <mach/mach.h>

// Lara carries its own kernel utility engine. Prefix its public symbols so it
// can coexist with Infern0's original engine in the same executable.
#define init_offsets lara_init_offsets
#define ourproc lara_ourproc
#define taskbyproc lara_taskbyproc
#define procbyname lara_procbyname
#define procbypid lara_procbypid
#define proclist lara_proclist
#define free_proclist lara_free_proclist
#define aslrstate lara_aslrstate
#define getaslrstate lara_getaslrstate
#define toggleaslr lara_toggleaslr
#define killproc lara_killproc
#define islcruntime lara_islcruntime
#define hexdump lara_hexdump
#define filehexdump lara_filehexdump
#define ipc_entry_lookup lara_ipc_entry_lookup
#define task_get_ipc_port_table_entry lara_task_get_ipc_port_table_entry
#define task_get_ipc_port_object lara_task_get_ipc_port_object
#define task_get_ipc_port_kobject lara_task_get_ipc_port_kobject
#define task_get_vm_map lara_task_get_vm_map
#define disable_excguard_kill lara_disable_excguard_kill
#define thread_get_t_tro lara_thread_get_t_tro
#define thread_get_task lara_thread_get_task
#define thread_get_options lara_thread_get_options
#define thread_set_options lara_thread_set_options
#define thread_set_mutex lara_thread_set_mutex
#define thread_get_mutex lara_thread_get_mutex
#define thread_get_kstackptr lara_thread_get_kstackptr
#define thread_get_jop_pid lara_thread_get_jop_pid
#define thread_get_rop_pid lara_thread_get_rop_pid
#define proc_task lara_proc_task
#define proc_find_by_name lara_proc_find_by_name
#define proc_self lara_proc_self
#define task_self lara_task_self
#define crashproc lara_crashproc

#ifdef __cplusplus
extern "C" {
#endif

void init_offsets(void);
uint64_t ourproc(void);
uint64_t taskbyproc(uint64_t procaddr);
uint64_t procbyname(const char *procname);
uint64_t procbypid(pid_t targetpid);

typedef struct {
    uint32_t pid;
    uint32_t uid;
    uint32_t gid;
    char name[32];
    uint64_t kaddr;
} proc_entry_t;

proc_entry_t* proclist(const char *search, int *out_count);
void free_proclist(proc_entry_t *list);

extern bool aslrstate;
void getaslrstate(void);
int toggleaslr(void);

int killproc(const char* name);
bool islcruntime(void);

void hexdump(const void* data, size_t size);
void filehexdump(const char *path, size_t size);

uint64_t ipc_entry_lookup(uint64_t space, mach_port_name_t name);
uint64_t task_get_ipc_port_table_entry(uint64_t task, mach_port_t port);
uint64_t task_get_ipc_port_object(uint64_t task, mach_port_t port);
uint64_t task_get_ipc_port_kobject(uint64_t task, mach_port_t port);
uint64_t task_get_vm_map(uint64_t task_ptr);

int disable_excguard_kill(uint64_t task);
uint64_t thread_get_t_tro(uint64_t thread);
uint64_t thread_get_task(uint64_t thread);
uint16_t thread_get_options(uint64_t thread);
void thread_set_options(uint64_t thread, uint16_t options);
void thread_set_mutex(uint64_t thread, uint32_t ctid);
uint32_t thread_get_mutex(uint64_t thread);
uint64_t thread_get_kstackptr(uint64_t thread);
uint64_t thread_get_jop_pid(uint64_t thread);
uint64_t thread_get_rop_pid(uint64_t thread);

uint64_t proc_task(uint64_t proc);
uint64_t proc_find_by_name(const char* name);
uint64_t proc_self(void);
uint64_t task_self(void);

int crashproc(const char* pid);

#ifdef __cplusplus
}
#endif

#endif /* utils_h */
