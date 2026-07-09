#pragma once

#include <stdbool.h>

#ifndef CYANIDE_VPHONE_DEBUG
#define CYANIDE_VPHONE_DEBUG 0
#endif

static inline bool cyanide_vphone_debug_build(void)
{
#if CYANIDE_VPHONE_DEBUG
    return true;
#else
    return false;
#endif
}
