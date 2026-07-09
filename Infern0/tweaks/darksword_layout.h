//
//  darksword_layout.h
//  Ported from kolbicz/DarkSword-Tweaks
//    - dock_and_home_spacing.m
//    - dock_and_homescreen_scaling.m
//  Patches SpringBoard's SBIconController layout config so the home grid
//  and dock can take extra padding and per-icon scaling.
//

#ifndef darksword_layout_h
#define darksword_layout_h

#import <stdbool.h>

// Adds extra padding to SBIconController's root layout insets. Defaults are
// top=60 left=27 bottom=100 right=27; these arguments are *additional* deltas
// (negative is allowed but won't go below the layout's hard minimums).
bool darksword_layout_home_spacing_in_session(double extraLeft,
                                              double extraRight,
                                              double extraTop,
                                              double extraBottom);

// Adds extra horizontal inset to the dock layout. Default left/right = 16.
bool darksword_layout_dock_spacing_in_session(double extraHorizontal);

// Sets per-icon image info (width/height/cornerRadius) at scale * 60pt.
// scale must be in (0, 2].
bool darksword_layout_home_scale_in_session(double scale);
bool darksword_layout_dock_scale_in_session(double scale);

// Convenience: applies all four if their values are meaningful. scale<=0
// means "leave alone".
bool darksword_layout_apply_in_session(double extraLeft,
                                       double extraRight,
                                       double extraTop,
                                       double extraBottom,
                                       double extraDockHorizontal,
                                       double homeScale,
                                       double dockScale);

#endif
