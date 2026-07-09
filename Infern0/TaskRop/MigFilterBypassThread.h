//
//  MigFilterBypassThread.m
//  Cyanide
//
//  Created by seo on 3/28/26.
//

#import <stdio.h>
#import <stdint.h>

#ifndef MigFilterBypassThread_m
#define MigFilterBypassThread_m

/*
 Okay, so... actually
 - migLock is _duplicate_lock at com.apple.security.sandbox:__bss
 - migSbxMsg is (_is_duplicate_report.previous addr) + 0x10 at com.apple.security.sandbox:__bss
 - And finally, migKernelStackLR is actually return address of _sb_event, which is located in handle_evaluation_result code at com.apple.security.sandbox:__text
 
 All symbols are based on iPad Air M3/18.3.x DEVELOPMENT kernel.
 */

// iPhone SE3 / 18.6.2
#define KOFFSET_IPHONE_14_6_1862_MIG_LOCK               0xFFFFFFF00A8C0DA8
#define KOFFSET_IPHONE_14_6_1862_MIG_SBX_MSG            0xFFFFFFF00A8C0DC8
#define KOFFSET_IPHONE_14_6_1862_MIG_KERNEL_STACK_LR    0xFFFFFFF00A209560

// iPhone SE3 / 26.0
#define KOFFSET_IPHONE_14_6_260_MIG_LOCK                0xFFFFFFF00ACBDFB0
#define KOFFSET_IPHONE_14_6_260_MIG_SBX_MSG             0xFFFFFFF00ACBDFD0
#define KOFFSET_IPHONE_14_6_260_MIG_KERNEL_STACK_LR     0xFFFFFFF00A59A118

int mig_bypass_init(uint64_t kernelSlide, uint64_t migLockOff, uint64_t migSbxMsgOff, uint64_t migKernelStackLROff);
void mig_bypass_start(void);
void mig_bypass_resume(void);
void mig_bypass_pause(void);
void mig_bypass_monitor_threads(uint64_t thread1, uint64_t thread2);

#endif /* MigFilterBypassThread_m */
