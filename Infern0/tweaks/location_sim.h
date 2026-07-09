//
//  location_sim.h
//  Cyanide
//
//  CoreLocation simulation driver.
//

#ifndef location_sim_h
#define location_sim_h

#include <stdbool.h>

typedef struct {
    double latitude;
    double longitude;
    double altitude;
    double horizontalAccuracy;
    double verticalAccuracy;
    const char *hostProcess;
    bool launchHost;
} LocationSimConfig;

bool locationsim_apply_static(const LocationSimConfig *config);
bool locationsim_apply_strict_hosts(const LocationSimConfig *config);
bool locationsim_stop(const char *hostProcess, bool launchHost);
bool locationsim_stop_strict_hosts(const char *hostProcess, bool launchHost);

#endif /* location_sim_h */
