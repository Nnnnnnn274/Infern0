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
#import "experimental/cleancc.h"
#import "experimental/fugap.h"
#import "experimental/modulespacing.h"
#import "experimental/sugarcane.h"
#import "experimental/betterccxi.h"
#import "experimental/magma.h"
#import "experimental/betterccicons.h"
#import "experimental/ccnoplatterdim.h"
#import "experimental/ccstatus.h"
#import "experimental/hapticcc.h"
#import "experimental/securecc.h"
#import "experimental/hidellabels.h"
#import "experimental/fakeclockup.h"
#import "experimental/pancake.h"
#import "experimental/cylinderlite.h"
#import "experimental/barmoji.h"
#import "experimental/iconstyles.h"
#import "experimental/blurrybadges.h"
#import "experimental/snapper.h"
#import "experimental/pullover.h"
#import "experimental/alkaline.h"
#import "experimental/tweakloader.h"
#import "amfi_bypass.h"
#import "kpac_bypass.h"
#import "msm_trustcache.h"
#import "coretrust_bypass.h"

#define CYANIDE_EXPERIMENTAL_TWEAKS_AVAILABLE 1

static inline bool cyanide_experimental_tweaks_available(void)
{
    return true;
}

#endif /* experimental_tweaks_h */
