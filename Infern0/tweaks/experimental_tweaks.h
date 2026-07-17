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

#import "retired_tweak_compat.h"

#import "experimental/rssidisplay.h"
#import "experimental/typebanner.h"
#import "experimental/stagestrip.h"
#import "experimental/cylinderlite.h"
#import "experimental/barmoji.h"
#import "watchlayout.h"
#import "experimental/customizers.h"
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
