//
//  remote_objc.m
//

#import "remote_objc.h"
#import "../TaskRop/RemoteCall.h"
#import <stdlib.h>
#import <string.h>
#import <unistd.h>

extern uint64_t remote_read64(uint64_t src);

static useconds_t gSettleUS = 50000;

static void r_settle(void)
{
    if (gSettleUS) usleep(gSettleUS);
}

uint32_t r_settle_us(uint32_t usec)
{
    uint32_t old = (uint32_t)gSettleUS;
    gSettleUS = (useconds_t)usec;
    return old;
}

bool r_is_objc_ptr(uint64_t ptr)
{
    return ptr >= 0x100000000ULL;
}

uint64_t r_dlsym_call(int timeout, const char *fnName,
                      uint64_t a0, uint64_t a1, uint64_t a2, uint64_t a3,
                      uint64_t a4, uint64_t a5, uint64_t a6, uint64_t a7)
{
    return do_remote_call_stable(timeout, fnName, a0, a1, a2, a3, a4, a5, a6, a7);
}

uint64_t r_alloc_str(const char *s)
{
    if (!s) return 0;
    uint64_t len = strlen(s) + 1;
    uint64_t buf = do_remote_call_stable(R_TIMEOUT, "malloc", len, 0, 0, 0, 0, 0, 0, 0);
    if (buf) remote_writeStr(buf, s);
    return buf;
}

void r_free(uint64_t ptr)
{
    if (!ptr) return;
    do_remote_call_stable(R_TIMEOUT, "free", ptr, 0, 0, 0, 0, 0, 0, 0);
}

uint64_t r_sel(const char *name)
{
    uint64_t s = r_alloc_str(name);
    if (!s) return 0;
    uint64_t sel = do_remote_call_stable(R_TIMEOUT, "sel_registerName", s, 0, 0, 0, 0, 0, 0, 0);
    r_free(s);
    return sel;
}

uint64_t r_class(const char *name)
{
    uint64_t s = r_alloc_str(name);
    if (!s) return 0;
    uint64_t c = do_remote_call_stable(R_TIMEOUT, "objc_getClass", s, 0, 0, 0, 0, 0, 0, 0);
    r_free(s);
    return c;
}

uint64_t r_msg(uint64_t obj, uint64_t sel,
               uint64_t a0, uint64_t a1, uint64_t a2, uint64_t a3)
{
    if (!obj || !sel) return 0;
    return do_remote_call_stable(R_TIMEOUT, "objc_msgSend",
                                 obj, sel, a0, a1, a2, a3, 0, 0);
}

uint64_t r_msg2(uint64_t obj, const char *selName,
                uint64_t a0, uint64_t a1, uint64_t a2, uint64_t a3)
{
    if (!obj || !selName) return 0;
    uint64_t sel = r_sel(selName);
    if (!sel) return 0;
    r_settle();
    return r_msg(obj, sel, a0, a1, a2, a3);
}

static uint64_t r_method_signature(uint64_t obj, uint64_t sel)
{
    if (!r_is_objc_ptr(obj) || !sel) return 0;

    uint64_t sigSel = r_sel("methodSignatureForSelector:");
    uint64_t sig = r_msg(obj, sigSel, sel, 0, 0, 0);
    if (r_is_objc_ptr(sig)) return sig;

    uint64_t cls = do_remote_call_stable(R_TIMEOUT, "object_getClass",
                                         obj, 0, 0, 0, 0, 0, 0, 0);
    if (!r_is_objc_ptr(cls)) return 0;

    uint64_t method = do_remote_call_stable(R_TIMEOUT, "class_getInstanceMethod",
                                            cls, sel, 0, 0, 0, 0, 0, 0);
    if (!method) return 0;

    uint64_t types = do_remote_call_stable(R_TIMEOUT, "method_getTypeEncoding",
                                           method, 0, 0, 0, 0, 0, 0, 0);
    if (!types) return 0;

    uint64_t NSMethodSignature = r_class("NSMethodSignature");
    if (!r_is_objc_ptr(NSMethodSignature)) return 0;
    return r_msg2(NSMethodSignature, "signatureWithObjCTypes:", types, 0, 0, 0);
}

static bool r_write_remote_arg(uint64_t remoteBuf, const void *arg, size_t argSize, size_t remoteSize)
{
    if (!remoteBuf || remoteSize == 0) return false;

    uint8_t stackBuf[64];
    void *localBuf = stackBuf;
    if (remoteSize > sizeof(stackBuf)) {
        localBuf = calloc(1, remoteSize);
        if (!localBuf) return false;
    } else {
        memset(stackBuf, 0, remoteSize);
    }

    if (arg && argSize) {
        size_t copySize = (argSize < remoteSize) ? argSize : remoteSize;
        memcpy(localBuf, arg, copySize);
    }

    bool ok = remote_write(remoteBuf, localBuf, remoteSize);
    if (localBuf != stackBuf) free(localBuf);
    return ok;
}

uint64_t r_msg_main_raw(uint64_t obj, uint64_t sel,
                        const void *a0, size_t a0Size,
                        const void *a1, size_t a1Size,
                        const void *a2, size_t a2Size,
                        const void *a3, size_t a3Size)
{
    if (!r_is_objc_ptr(obj) || !sel) return 0;

    uint64_t sig = r_method_signature(obj, sel);
    if (!r_is_objc_ptr(sig)) return 0;

    uint64_t NSInvocation = r_class("NSInvocation");
    if (!r_is_objc_ptr(NSInvocation)) return 0;

    uint64_t inv = r_msg2(NSInvocation, "invocationWithMethodSignature:", sig, 0, 0, 0);
    if (!r_is_objc_ptr(inv)) return 0;

    uint64_t retainedInv = r_msg2(inv, "retain", 0, 0, 0, 0);
    if (r_is_objc_ptr(retainedInv)) inv = retainedInv;

    uint64_t numArgs = r_msg2(sig, "numberOfArguments", 0, 0, 0, 0);
    uint64_t maxUserArgs = (numArgs > 2) ? (numArgs - 2) : 0;
    if (maxUserArgs > 4) maxUserArgs = 4;

    r_msg2(inv, "setTarget:", obj, 0, 0, 0);
    r_msg2(inv, "setSelector:", sel, 0, 0, 0);

    const void *argData[4] = { a0, a1, a2, a3 };
    size_t argSizes[4] = { a0Size, a1Size, a2Size, a3Size };
    for (uint64_t i = 0; i < maxUserArgs; i++) {
        size_t argBufLen = (argSizes[i] > 8) ? argSizes[i] : 8;
        uint64_t argBuf = do_remote_call_stable(R_TIMEOUT, "malloc",
                                                argBufLen, 0, 0, 0, 0, 0, 0, 0);
        if (!argBuf) continue;
        if (r_write_remote_arg(argBuf, argData[i], argSizes[i], argBufLen))
            r_msg2(inv, "setArgument:atIndex:", argBuf, i + 2, 0, 0);
        r_free(argBuf);
    }

    r_msg2(inv, "retainArguments", 0, 0, 0, 0);

    uint64_t performSel = r_sel("performSelectorOnMainThread:withObject:waitUntilDone:");
    uint64_t invokeSel = r_sel("invoke");
    if (performSel && invokeSel) {
        r_msg(inv, performSel, invokeSel, 0, 1, 0);
    }

    uint64_t ret = 0;
    uint64_t retLen = r_msg2(sig, "methodReturnLength", 0, 0, 0, 0);
    if (retLen > 0) {
        uint64_t retBufLen = (retLen > 8) ? retLen : 8;
        uint64_t retBuf = do_remote_call_stable(R_TIMEOUT, "malloc",
                                                retBufLen, 0, 0, 0, 0, 0, 0, 0);
        if (retBuf) {
            remote_write64(retBuf, 0);
            r_msg2(inv, "getReturnValue:", retBuf, 0, 0, 0);
            ret = remote_read64(retBuf);
            r_free(retBuf);
        }
    }

    r_msg2(inv, "release", 0, 0, 0, 0);
    return ret;
}

uint64_t r_msg_main(uint64_t obj, uint64_t sel,
                    uint64_t a0, uint64_t a1, uint64_t a2, uint64_t a3)
{
    uint64_t args[4] = { a0, a1, a2, a3 };
    return r_msg_main_raw(obj, sel,
                          &args[0], sizeof(args[0]),
                          &args[1], sizeof(args[1]),
                          &args[2], sizeof(args[2]),
                          &args[3], sizeof(args[3]));
}

uint64_t r_msg2_main(uint64_t obj, const char *selName,
                     uint64_t a0, uint64_t a1, uint64_t a2, uint64_t a3)
{
    if (!obj || !selName) return 0;
    uint64_t sel = r_sel(selName);
    if (!sel) return 0;
    r_settle();
    return r_msg_main(obj, sel, a0, a1, a2, a3);
}

// Fire-and-forget variant: dispatches the call to main thread with
// waitUntilDone:NO and skips the return-value plumbing. Use this when the
// selector returns void and we don't need to wait — main thread retains the
// NSInvocation for the duration of the call, so it's safe to release here.
void r_msg2_main_async(uint64_t obj, const char *selName,
                       uint64_t a0, uint64_t a1, uint64_t a2, uint64_t a3)
{
    if (!r_is_objc_ptr(obj) || !selName) return;
    uint64_t sel = r_sel(selName);
    if (!sel) return;
    r_settle();

    uint64_t sig = 0;
    {
        uint64_t sigSel = r_sel("methodSignatureForSelector:");
        sig = r_msg(obj, sigSel, sel, 0, 0, 0);
    }
    if (!r_is_objc_ptr(sig)) return;

    uint64_t NSInvocation = r_class("NSInvocation");
    if (!r_is_objc_ptr(NSInvocation)) return;
    uint64_t inv = r_msg2(NSInvocation, "invocationWithMethodSignature:", sig, 0, 0, 0);
    if (!r_is_objc_ptr(inv)) return;

    uint64_t numArgs = r_msg2(sig, "numberOfArguments", 0, 0, 0, 0);
    uint64_t maxUserArgs = (numArgs > 2) ? (numArgs - 2) : 0;
    if (maxUserArgs > 4) maxUserArgs = 4;

    r_msg2(inv, "setTarget:", obj, 0, 0, 0);
    r_msg2(inv, "setSelector:", sel, 0, 0, 0);

    uint64_t userArgs[4] = { a0, a1, a2, a3 };
    for (uint64_t i = 0; i < maxUserArgs; i++) {
        uint64_t argBuf = do_remote_call_stable(R_TIMEOUT, "malloc",
                                                8, 0, 0, 0, 0, 0, 0, 0);
        if (!argBuf) continue;
        remote_write64(argBuf, userArgs[i]);
        r_msg2(inv, "setArgument:atIndex:", argBuf, i + 2, 0, 0);
        r_free(argBuf);
    }

    r_msg2(inv, "retainArguments", 0, 0, 0, 0);

    uint64_t performSel = r_sel("performSelectorOnMainThread:withObject:waitUntilDone:");
    uint64_t invokeSel = r_sel("invoke");
    if (performSel && invokeSel) {
        r_msg(inv, performSel, invokeSel, 0, 0, 0);
    }
}

uint64_t r_msg2_main_raw(uint64_t obj, const char *selName,
                         const void *a0, size_t a0Size,
                         const void *a1, size_t a1Size,
                         const void *a2, size_t a2Size,
                         const void *a3, size_t a3Size)
{
    if (!obj || !selName) return 0;
    uint64_t sel = r_sel(selName);
    if (!sel) return 0;
    r_settle();
    return r_msg_main_raw(obj, sel, a0, a0Size, a1, a1Size, a2, a2Size, a3, a3Size);
}

// Same flow as r_msg_main_raw, but copies the full method return buffer back
// into outBuf instead of truncating to 8 bytes. Used for selectors that return
// a struct larger than a register pair (e.g. CGRect from -convertRect:toView:).
bool r_msg2_main_struct_ret(uint64_t obj, const char *selName,
                            void *outBuf, size_t outSize,
                            const void *a0, size_t a0Size,
                            const void *a1, size_t a1Size,
                            const void *a2, size_t a2Size,
                            const void *a3, size_t a3Size)
{
    if (!r_is_objc_ptr(obj) || !selName || !outBuf || outSize == 0) return false;
    uint64_t sel = r_sel(selName);
    if (!sel) return false;
    r_settle();

    uint64_t sig = r_method_signature(obj, sel);
    if (!r_is_objc_ptr(sig)) return false;

    uint64_t NSInvocation = r_class("NSInvocation");
    if (!r_is_objc_ptr(NSInvocation)) return false;

    uint64_t inv = r_msg2(NSInvocation, "invocationWithMethodSignature:", sig, 0, 0, 0);
    if (!r_is_objc_ptr(inv)) return false;

    uint64_t retainedInv = r_msg2(inv, "retain", 0, 0, 0, 0);
    if (r_is_objc_ptr(retainedInv)) inv = retainedInv;

    uint64_t numArgs = r_msg2(sig, "numberOfArguments", 0, 0, 0, 0);
    uint64_t maxUserArgs = (numArgs > 2) ? (numArgs - 2) : 0;
    if (maxUserArgs > 4) maxUserArgs = 4;

    r_msg2(inv, "setTarget:", obj, 0, 0, 0);
    r_msg2(inv, "setSelector:", sel, 0, 0, 0);

    const void *argData[4] = { a0, a1, a2, a3 };
    size_t argSizes[4] = { a0Size, a1Size, a2Size, a3Size };
    for (uint64_t i = 0; i < maxUserArgs; i++) {
        size_t argBufLen = (argSizes[i] > 8) ? argSizes[i] : 8;
        uint64_t argBuf = do_remote_call_stable(R_TIMEOUT, "malloc",
                                                argBufLen, 0, 0, 0, 0, 0, 0, 0);
        if (!argBuf) continue;
        if (r_write_remote_arg(argBuf, argData[i], argSizes[i], argBufLen))
            r_msg2(inv, "setArgument:atIndex:", argBuf, i + 2, 0, 0);
        r_free(argBuf);
    }

    r_msg2(inv, "retainArguments", 0, 0, 0, 0);

    uint64_t performSel = r_sel("performSelectorOnMainThread:withObject:waitUntilDone:");
    uint64_t invokeSel = r_sel("invoke");
    if (performSel && invokeSel) {
        r_msg(inv, performSel, invokeSel, 0, 1, 0);
    }

    bool ok = false;
    uint64_t retLen = r_msg2(sig, "methodReturnLength", 0, 0, 0, 0);
    if (retLen >= outSize) {
        uint64_t retBuf = do_remote_call_stable(R_TIMEOUT, "malloc",
                                                retLen, 0, 0, 0, 0, 0, 0, 0);
        if (retBuf) {
            r_msg2(inv, "getReturnValue:", retBuf, 0, 0, 0);
            ok = remote_read(retBuf, outBuf, outSize);
            r_free(retBuf);
        }
    }

    r_msg2(inv, "release", 0, 0, 0, 0);
    return ok;
}

uint64_t r_perform_main(uint64_t obj, uint64_t sel, uint64_t object, bool wait)
{
    if (!r_is_objc_ptr(obj) || !sel) return 0;
    uint64_t performSel = r_sel("performSelectorOnMainThread:withObject:waitUntilDone:");
    if (!performSel) return 0;
    return r_msg(obj, performSel, sel, object, wait ? 1 : 0, 0);
}

uint64_t r_cfstr(const char *s)
{
    if (!s) return 0;
    uint64_t buf = r_alloc_str(s);
    if (!buf) return 0;
    // CFStringCreateWithCString(alloc=NULL, cstr, encoding=kCFStringEncodingUTF8=0x08000100)
    uint64_t cf = do_remote_call_stable(R_TIMEOUT, "CFStringCreateWithCString",
                                        0, buf, 0x08000100, 0, 0, 0, 0, 0);
    r_free(buf);
    return cf;
}

uint64_t r_nsstr_retained(const char *s)
{
    if (!s) return 0;
    uint64_t buf = r_alloc_str(s);
    if (!buf) return 0;
    uint64_t NSString = r_class("NSString");
    if (!r_is_objc_ptr(NSString)) { r_free(buf); return 0; }
    uint64_t allocated = r_msg2(NSString, "alloc", 0, 0, 0, 0);
    if (!r_is_objc_ptr(allocated)) { r_free(buf); return 0; }
    uint64_t ns = r_msg2(allocated, "initWithUTF8String:", buf, 0, 0, 0);
    r_free(buf);
    return ns;
}

bool r_responds(uint64_t obj, const char *selName)
{
    if (!r_is_objc_ptr(obj)) return false;
    uint64_t sel = r_sel(selName);
    if (!sel) return false;
    uint64_t respondsSel = r_sel("respondsToSelector:");
    if (!respondsSel) return false;
    r_settle();
    uint64_t r = r_msg(obj, respondsSel, sel, 0, 0, 0);
    return (r & 0xff) != 0;
}

bool r_responds_main(uint64_t obj, const char *selName)
{
    if (!r_is_objc_ptr(obj)) return false;
    uint64_t sel = r_sel(selName);
    if (!sel) return false;
    uint64_t respondsSel = r_sel("respondsToSelector:");
    if (!respondsSel) return false;
    r_settle();
    uint64_t r = r_msg_main(obj, respondsSel, sel, 0, 0, 0);
    return (r & 0xff) != 0;
}

uint64_t r_ivar_value(uint64_t obj, const char *ivarName)
{
    if (!r_is_objc_ptr(obj)) return 0;
    uint64_t cls = do_remote_call_stable(R_TIMEOUT, "object_getClass", obj, 0, 0, 0, 0, 0, 0, 0);
    if (!cls) return 0;
    uint64_t nameBuf = r_alloc_str(ivarName);
    if (!nameBuf) return 0;
    uint64_t ivar = do_remote_call_stable(R_TIMEOUT, "class_getInstanceVariable",
                                          cls, nameBuf, 0, 0, 0, 0, 0, 0);
    r_free(nameBuf);
    if (!ivar) return 0;
    uint64_t offset = do_remote_call_stable(R_TIMEOUT, "ivar_getOffset",
                                            ivar, 0, 0, 0, 0, 0, 0, 0);
    return remote_read64(obj + offset);
}
