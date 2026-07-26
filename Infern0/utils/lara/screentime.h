#ifndef screentime_h
#define screentime_h

#include <stdbool.h>

bool screentime_disable(bool killScreenTimeAgent,
                        bool killUsageTrackingAgent,
                        bool killHomed,
                        bool killFamilycircled);

bool screentime_enable(void);

#endif
