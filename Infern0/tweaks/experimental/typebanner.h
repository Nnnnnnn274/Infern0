//
//  typebanner.h
//  TypeMillennium port: detect iMessage typing from the Messages daemon via
//  RemoteCall, show a Dynamic-Island-style banner in SpringBoard via RemoteCall.
//
//  Detection now prefers imagent with the original-thread-only RemoteCall mode.
//  The older MobileSMS IMChatRegistry poll remains for diagnostics/fallback, but
//  is not used by the live loop because synthetic RemoteCall threads can PAC/0x401
//  crash MobileSMS after it suspends.
//

#ifndef typebanner_h
#define typebanner_h

#import <stdbool.h>
#import <stdint.h>

#ifdef __OBJC__
#import <Foundation/Foundation.h>
#import "../../TaskRop/RemoteCall.h"

#define TYPEBANNER_RC_FIRST_EXCEPTION_TIMEOUT_MS 8000
// Short timeout for typing hosts: if the bootstrap exception does not arrive
// in 1s, fail fast so the live loop can re-poll on its next tick.
#define TYPEBANNER_RC_MOBILESMS_FIRST_EXCEPTION_TIMEOUT_MS 1000

// SpringBoard-side: show the typing banner with the given display name.
// Must be called inside an active SpringBoard RemoteCall context.
// Pass nil/empty to render as "Someone is typing…".
bool typebanner_prepare_in_springboard_session(void);
bool typebanner_prepare_in_springboard_remote_session(RemoteCallSession *session);
bool typebanner_show_in_springboard_session(NSString *displayName);
bool typebanner_show_in_springboard_remote_session(RemoteCallSession *session, NSString *displayName);

// SpringBoard-side: fade out and hide the banner. Idempotent.
// Must be called inside an active SpringBoard RemoteCall context.
bool typebanner_hide_in_springboard_session(void);
bool typebanner_hide_in_springboard_remote_session(RemoteCallSession *session);

// SpringBoard-side: hold/release a RunningBoard assertion that keeps the
// current MobileSMS pid runnable while TypeBanner polls IMChatRegistry.
// Currently gated off on iOS 26.0.1 because synchronous acquisition can wedge
// runningboardd's RBAssertionManager.
bool typebanner_ensure_mobilesms_keepalive_in_springboard_session(uint32_t pid);
bool typebanner_ensure_mobilesms_keepalive_in_springboard_remote_session(RemoteCallSession *session, uint32_t pid);
bool typebanner_release_mobilesms_keepalive_in_springboard_session(void);
bool typebanner_release_mobilesms_keepalive_in_springboard_remote_session(RemoteCallSession *session);

// MobileSMS-side: iterate IMChatRegistry.allExistingChats and return the
// display name of any chat whose IMChat.isLastMessageTypingIndicator is YES.
// Returns nil if nothing is typing.
// Must be called inside an active MobileSMS RemoteCall context.
NSString *typebanner_poll_in_mobilesms_session(void);
NSString *typebanner_poll_in_mobilesms_remote_session(RemoteCallSession *session);

// imagent-side daemon poll. Use with a RemoteCallSession opened with
// originalThreadOnly:YES.
NSString *typebanner_poll_in_imagent_remote_session(RemoteCallSession *session);

// MobileSMS-side: dump every IMChat in the registry with its typing state.
// Use to verify selector availability if poll stops finding hits.
// Must be called inside an active MobileSMS RemoteCall context.
void typebanner_diagnose_in_mobilesms_session(void);
void typebanner_diagnose_in_mobilesms_remote_session(RemoteCallSession *session);
#endif

// One-shot orchestration from Cyanide's process. Owns short-lived RemoteCall
// sessions for the daemon/SpringBoard paths.
// Safe to call from a background queue.
bool typebanner_run_once(void);

// Live-loop orchestration from Cyanide's process. The argument is kept for
// fallback builds that re-enable MobileSMS polling; daemon-only mode leaves it
// nil. Caller owns final teardown if a fallback session is ever created.
bool typebanner_run_once_with_mobile_session(RemoteCallSession **mobileSessionRef);
bool typebanner_run_once_with_mobile_session_and_current_springboard(RemoteCallSession **mobileSessionRef,
                                                                    bool currentSpringBoardReady);
bool typebanner_run_once_with_cached_sessions(RemoteCallSession **mobileSessionRef,
                                              RemoteCallSession **daemonSessionRef,
                                              bool currentSpringBoardReady);

// Drop cached remote handles. Call when SpringBoard or a typing host may have died.
bool typebanner_has_remote_state(void);
void typebanner_forget_remote_state(void);

// Legacy MobileSMS reachability diagnostic.
bool typebanner_mobile_was_unreachable_last_tick(void);

#endif
