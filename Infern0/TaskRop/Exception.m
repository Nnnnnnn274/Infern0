//
//  Exception.m
//  Cyanide
//
//  Created by seo on 4/4/26.
//

#import "../kexploit/kexploit_opa334.h"
#import "Exception.h"
#import "RemoteCall.h"
#import <Foundation/Foundation.h>
#import <mach/mach.h>

// xnu-10002.81.5/osfmk/mach/port.h
#define MPO_PROVISIONAL_ID_PROT_OPTOUT     0x8000  /* Opted out of EXCEPTION_IDENTITY_PROTECTED violation for now */

// from pe_main.js
#define EXCEPTION_MSG_SIZE              0x160
#define EXCEPTION_REPLY_SIZE            0x13c

mach_port_t create_exception_port(void)
{
    mach_port_options_t options = {
        .flags = MPO_INSERT_SEND_RIGHT | MPO_PROVISIONAL_ID_PROT_OPTOUT,
        .mpl   = { .mpl_qlimit = 0 }
    };

    mach_port_t exceptionPort = MACH_PORT_NULL;

    kern_return_t kr = mach_port_construct(mach_task_self_, &options, 0, &exceptionPort);
    if (kr != KERN_SUCCESS)
    {
        printf("[%s:%d] Failed to create exception port: %s (kr=%d)", __FUNCTION__, __LINE__, mach_error_string(kr), kr);
        return MACH_PORT_NULL;
    }

    return exceptionPort;
}

void destroy_exception_port(mach_port_t exceptionPort)
{
    if (!MACH_PORT_VALID(exceptionPort)) return;

    mach_port_type_t type = 0;
    kern_return_t kr = mach_port_type(mach_task_self_, exceptionPort, &type);
    if (kr == KERN_SUCCESS && (type & MACH_PORT_TYPE_SEND)) {
        kr = mach_port_mod_refs(mach_task_self_, exceptionPort, MACH_PORT_RIGHT_SEND, -1);
        if (kr != KERN_SUCCESS &&
            kr != KERN_INVALID_NAME &&
            kr != KERN_INVALID_RIGHT &&
            kr != KERN_INVALID_VALUE) {
            printf("[%s:%d] Failed to drop exception port send right 0x%x: %s (kr=%d)\n",
                   __FUNCTION__, __LINE__, exceptionPort, mach_error_string(kr), kr);
        }
    }

    kr = mach_port_destruct(mach_task_self_, exceptionPort, 0, 0);
    if (kr != KERN_SUCCESS && kr != KERN_INVALID_NAME)
        printf("[%s:%d] Failed to destroy exception port 0x%x: %s (kr=%d)\n",
               __FUNCTION__, __LINE__, exceptionPort, mach_error_string(kr), kr);
}

bool wait_exception(mach_port_t exceptionPort, ExceptionMessage *excBuffer, int timeout, bool debug) {
    kern_return_t kr = mach_msg(&excBuffer->Head, MACH_RCV_MSG | MACH_RCV_TIMEOUT, 0, EXCEPTION_MSG_SIZE, exceptionPort, timeout, MACH_PORT_NULL);
    
    if(kr != KERN_SUCCESS)  return false;

    return true;
}

void reply_with_state(ExceptionMessage *exc, arm_thread_state64_internal *state)
{
    uint8_t replyBuf[EXCEPTION_REPLY_SIZE];
    memset(replyBuf, 0, sizeof(replyBuf));
    ExceptionReply *reply = (ExceptionReply *)replyBuf;

    reply->Head.msgh_bits        = MACH_MSGH_BITS(MACH_MSG_TYPE_MOVE_SEND_ONCE, 0);
    reply->Head.msgh_size        = EXCEPTION_REPLY_SIZE;
    reply->Head.msgh_remote_port = exc->Head.msgh_remote_port;
    reply->Head.msgh_local_port  = MACH_PORT_NULL;
    reply->Head.msgh_id          = exc->Head.msgh_id + 100;
    reply->NDR                   = exc->NDR;
    reply->RetCode               = 0;
    reply->flavor                = ARM_THREAD_STATE64;
    reply->new_stateCnt          = ARM_THREAD_STATE64_COUNT;
    memcpy(&reply->threadState, state, sizeof(arm_thread_state64_t));

    kern_return_t kr = mach_msg((mach_msg_header_t *)replyBuf,
                                MACH_SEND_MSG,
                                EXCEPTION_REPLY_SIZE, 0,
                                MACH_PORT_NULL,
                                MACH_MSG_TIMEOUT_NONE,
                                MACH_PORT_NULL);
    if (kr != KERN_SUCCESS)
        printf("[%s:%d] reply_with_state failed: %s\n", __FUNCTION__, __LINE__, mach_error_string(kr));
}
