//
//  experimental_tweaks.h
//  Cyanide
//
//  Experimental and beta tweak APIs are part of the public source tree.
//

#ifndef experimental_tweaks_h
#define experimental_tweaks_h

#include <stdbool.h>
#include <stdint.h>

#include "location_sim.h"
#include "call_recording_sound.h"

#import "experimental/rssidisplay.h"
#import "experimental/typebanner.h"
#import "experimental/notificationisland.h"
#import "experimental/stagestrip.h"
#import "experimental/ipadecryptor.h"
#import "experimental/fastlockx_lite.h"
#import "experimental/velvet.h"
#import "experimental/cleannc.h"
#import "experimental/undertime.h"
#import "experimental/zeppelinlite.h"
#import "experimental/cleanhomescreen.h"
#import "experimental/realcc.h"
#import "experimental/hidellabels.h"
#import "experimental/fakeclockup.h"
#import "experimental/pancake.h"
#import "experimental/cylinderlite.h"

#define CYANIDE_EXPERIMENTAL_TWEAKS_AVAILABLE 1

static inline bool cyanide_experimental_tweaks_available(void)
{
    return true;
}

#endif /* experimental_tweaks_h */
