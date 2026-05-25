//
//  remote_objc.h
//  Thin Objective-C runtime helpers built on do_remote_call_stable.
//

#ifndef remote_objc_h
#define remote_objc_h

#import <stdint.h>
#import <stdbool.h>
#import <stddef.h>
#ifdef __OBJC__
#import "../TaskRop/RemoteCall.h"
#endif

#define R_TIMEOUT 5

uint64_t r_alloc_str(const char *s);
void     r_free(uint64_t ptr);
uint64_t r_sel(const char *name);
uint64_t r_class(const char *name);
uint64_t r_msg(uint64_t obj, uint64_t sel,
               uint64_t a0, uint64_t a1, uint64_t a2, uint64_t a3);
uint64_t r_msg2(uint64_t obj, const char *selName,
                uint64_t a0, uint64_t a1, uint64_t a2, uint64_t a3);
uint64_t r_msg_main(uint64_t obj, uint64_t sel,
                    uint64_t a0, uint64_t a1, uint64_t a2, uint64_t a3);
uint64_t r_msg2_main(uint64_t obj, const char *selName,
                     uint64_t a0, uint64_t a1, uint64_t a2, uint64_t a3);
void     r_msg2_main_async(uint64_t obj, const char *selName,
                           uint64_t a0, uint64_t a1, uint64_t a2, uint64_t a3);
uint64_t r_msg_main_raw(uint64_t obj, uint64_t sel,
                        const void *a0, size_t a0Size,
                        const void *a1, size_t a1Size,
                        const void *a2, size_t a2Size,
                        const void *a3, size_t a3Size);
uint64_t r_msg2_main_raw(uint64_t obj, const char *selName,
                         const void *a0, size_t a0Size,
                         const void *a1, size_t a1Size,
                         const void *a2, size_t a2Size,
                         const void *a3, size_t a3Size);
bool     r_msg2_main_struct_ret(uint64_t obj, const char *selName,
                                void *outBuf, size_t outSize,
                                const void *a0, size_t a0Size,
                                const void *a1, size_t a1Size,
                                const void *a2, size_t a2Size,
                                const void *a3, size_t a3Size);
uint32_t r_settle_us(uint32_t usec);
uint64_t r_perform_main(uint64_t obj, uint64_t sel, uint64_t object, bool wait);
uint64_t r_cfstr(const char *s);
uint64_t r_nsstr_retained(const char *s);
bool     r_responds(uint64_t obj, const char *selName);
bool     r_responds_main(uint64_t obj, const char *selName);
bool     r_is_objc_ptr(uint64_t ptr);
uint64_t r_ivar_value(uint64_t obj, const char *ivarName);
uint64_t r_dlsym_call(int timeout, const char *fnName,
                      uint64_t a0, uint64_t a1, uint64_t a2, uint64_t a3,
                      uint64_t a4, uint64_t a5, uint64_t a6, uint64_t a7);

// Copies the UTF-8 bytes of a remote NSString into a local C buffer (NUL
// terminated, truncated to outLen-1). Returns true only if at least one
// byte was copied.
bool     r_read_nsstring(uint64_t str, char *out, size_t outLen);

#ifdef __OBJC__
uint64_t r_session_alloc_str(RemoteCallSession *session, const char *s);
void     r_session_free(RemoteCallSession *session, uint64_t ptr);
uint64_t r_session_sel(RemoteCallSession *session, const char *name);
uint64_t r_session_class(RemoteCallSession *session, const char *name);
uint64_t r_session_msg(RemoteCallSession *session, uint64_t obj, uint64_t sel,
                       uint64_t a0, uint64_t a1, uint64_t a2, uint64_t a3);
uint64_t r_session_msg2(RemoteCallSession *session, uint64_t obj, const char *selName,
                        uint64_t a0, uint64_t a1, uint64_t a2, uint64_t a3);
uint64_t r_session_msg_main(RemoteCallSession *session, uint64_t obj, uint64_t sel,
                            uint64_t a0, uint64_t a1, uint64_t a2, uint64_t a3);
uint64_t r_session_msg2_main(RemoteCallSession *session, uint64_t obj, const char *selName,
                             uint64_t a0, uint64_t a1, uint64_t a2, uint64_t a3);
void     r_session_msg2_main_async(RemoteCallSession *session, uint64_t obj, const char *selName,
                                   uint64_t a0, uint64_t a1, uint64_t a2, uint64_t a3);
uint64_t r_session_msg_main_raw(RemoteCallSession *session, uint64_t obj, uint64_t sel,
                                const void *a0, size_t a0Size,
                                const void *a1, size_t a1Size,
                                const void *a2, size_t a2Size,
                                const void *a3, size_t a3Size);
uint64_t r_session_msg2_main_raw(RemoteCallSession *session, uint64_t obj, const char *selName,
                                 const void *a0, size_t a0Size,
                                 const void *a1, size_t a1Size,
                                 const void *a2, size_t a2Size,
                                 const void *a3, size_t a3Size);
bool     r_session_msg2_main_struct_ret(RemoteCallSession *session, uint64_t obj, const char *selName,
                                        void *outBuf, size_t outSize,
                                        const void *a0, size_t a0Size,
                                        const void *a1, size_t a1Size,
                                        const void *a2, size_t a2Size,
                                        const void *a3, size_t a3Size);
uint64_t r_session_perform_main(RemoteCallSession *session, uint64_t obj, uint64_t sel, uint64_t object, bool wait);
uint64_t r_session_cfstr(RemoteCallSession *session, const char *s);
uint64_t r_session_nsstr_retained(RemoteCallSession *session, const char *s);
bool     r_session_responds(RemoteCallSession *session, uint64_t obj, const char *selName);
bool     r_session_responds_main(RemoteCallSession *session, uint64_t obj, const char *selName);
uint64_t r_session_ivar_value(RemoteCallSession *session, uint64_t obj, const char *ivarName);
uint64_t r_session_dlsym_call(RemoteCallSession *session, int timeout, const char *fnName,
                              uint64_t a0, uint64_t a1, uint64_t a2, uint64_t a3,
                              uint64_t a4, uint64_t a5, uint64_t a6, uint64_t a7);
#endif

#endif
