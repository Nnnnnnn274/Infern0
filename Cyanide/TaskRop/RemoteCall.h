//
//  RemoteCall.h
//  Cyanide
//
//  Created by seo on 3/29/26.
//

#ifndef RemoteCall_h
#define RemoteCall_h

#import <mach/mach.h>

struct VMShmem {
    uint64_t port;
    uint64_t remoteAddress;
    uint64_t localAddress;
    bool     used;
};

// from Duy Tran's TaskPortHaxxApp
// https://github.com/khanhduytran0/TaskPortHaxxApp/blob/pacbypass/TaskPortHaxxApp/Header.h#L83
typedef struct {
    uint64_t __x[29];       /* General purpose registers x0-x28 */
    uint64_t __fp; /* Frame pointer x29 */
    uint64_t __lr; /* Link register x30 */
    uint64_t __sp; /* Stack pointer x31 */
    uint64_t __pc; /* Program counter */
    uint32_t __cpsr;        /* Current program status register */
    uint32_t __flags; /* Flags describing structure format */
} arm_thread_state64_internal;

mach_port_t create_exception_port(void);
int disable_excguard_kill(uint64_t task);
int init_remote_call(const char* process, bool useMigFilterBypass);
uint64_t do_remote_call_stable(int timeout, const char *name, uint64_t x0, uint64_t x1, uint64_t x2, uint64_t x3, uint64_t x4, uint64_t x5, uint64_t x6, uint64_t x7);
uint64_t do_remote_call_stable_addr(int timeout, uint64_t pcAddr, const char *name, uint64_t x0, uint64_t x1, uint64_t x2, uint64_t x3, uint64_t x4, uint64_t x5, uint64_t x6, uint64_t x7);
void sign_state(uint64_t signingThread, arm_thread_state64_internal *state, uint64_t pc, uint64_t lr);
uint64_t remote_pac(uint64_t remoteThreadAddr, uint64_t address, uint64_t modifier);
bool remote_read(uint64_t src, void *dst, uint64_t size);
uint64_t remote_read64(uint64_t src);
void remote_hexdump(uint64_t remoteAddr, size_t size);
bool remote_write(uint64_t dst, const void *src, uint64_t size);
bool remote_write64(uint64_t dst, uint64_t val);
bool remote_writeStr(uint64_t dst, const char *str);
int destroy_remote_call(void);
// Drop every piece of local RemoteCall state without trying to IPC the remote
// task. Use this when the remote task is known dead (e.g. SpringBoard just
// crashed and respawned) — destroy_remote_call would otherwise hang for
// 100s on its munmap/pthread_exit calls into a vanished trojan thread.
void abandon_remote_call(void);
bool remote_call_has_local_state(void);

#endif /* RemoteCall_h */
