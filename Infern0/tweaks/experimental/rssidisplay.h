//
//  rssidisplay.h
//  Replaces the cellular/WiFi signal bars in SpringBoard's status bar with
//  live RSSI dBm readings via RemoteCall-only injection. No method swizzling,
//  no resident dylib — overlays a per-icon UIWindow that covers each
//  STUIStatusBar*SignalView with a UILabel updated once per second.
//

#ifndef rssidisplay_h
#define rssidisplay_h

#import <stdbool.h>

bool rssidisplay_apply_in_session(bool showWifi, bool showCell);
bool rssidisplay_stop_in_session(void);
void rssidisplay_forget_remote_state(void);

#endif /* rssidisplay_h */
