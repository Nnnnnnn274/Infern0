//
//  cylinderlite.h
//  Cyanide
//

#ifndef cylinderlite_h
#define cylinderlite_h

#import <stdbool.h>

typedef enum {
    CylinderLiteEffectSlide = 1,
    CylinderLiteEffectFlip = 2,
    CylinderLiteEffectPageSpin = 3,
    CylinderLiteEffectPageFlip = 4,
    CylinderLiteEffectPageTwist = 5,
    CylinderLiteEffectVerticalScroll = 6,
    CylinderLiteEffectBackwards = 7,
    CylinderLiteEffectHellaFar = 8,
    CylinderLiteEffectCubeInside = 9,
    CylinderLiteEffectCubeOutside = 10,
    CylinderLiteEffectCardHorizontal = 11,
    CylinderLiteEffectCardVertical = 12,
    CylinderLiteEffectWheel = 13,
    CylinderLiteEffectHinge = 14,
    CylinderLiteEffectTurn = 15,
    CylinderLiteEffectZoomFadeOut = 16,
    CylinderLiteEffectZoomFadeIn = 17,
    CylinderLiteEffectLast = CylinderLiteEffectZoomFadeIn,
} CylinderLiteEffect;

bool cylinderlite_apply_in_session(CylinderLiteEffect effect);
bool cylinderlite_apply_in_session_with_options(CylinderLiteEffect effect,
                                                int intensityPct,
                                                int opacityPct,
                                                bool followGesture,
                                                int oneShotDurationMs);
bool cylinderlite_tick_in_session(void);
bool cylinderlite_stop_in_session(void);
void cylinderlite_forget_remote_state(void);

#endif /* cylinderlite_h */
