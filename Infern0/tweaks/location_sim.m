//
//  location_sim.m
//  Cyanide
//

#import "location_sim.h"
#import "remote_objc.h"
#import "../TaskRop/RemoteCall.h"

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <math.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <unistd.h>

typedef struct {
    double latitude;
    double longitude;
} LocationSimCoordinate;

typedef struct {
    const void *data;
    size_t size;
} LocationSimInvocationArg;

static const int kLocationSimOptionalHostInitTimeoutMS = 15000;
static const double kLocationSimPi = 3.14159265358979323846;
static const double kLocationSimMetersPerDegreeLatitude = 111320.0;
static const double kLocationSimRouteIntervalSeconds = 1.0;
static const size_t kLocationSimRoutePointCount = 12;

static NSInteger locationsim_ios_major_version(void)
{
    return NSProcessInfo.processInfo.operatingSystemVersion.majorVersion;
}

static bool locationsim_is_ios_below_18(void)
{
    NSInteger major = locationsim_ios_major_version();
    return major > 0 && major < 18;
}

static const char *locationsim_host_or_default(const char *host)
{
    return (host && host[0]) ? host : "Maps";
}

static bool locationsim_host_is_maps(const char *host)
{
    host = locationsim_host_or_default(host);
    return strcmp(host, "Maps") == 0;
}

static const char *locationsim_str_or_null(const char *value)
{
    return (value && value[0]) ? value : NULL;
}

static bool locationsim_write_arg(uint64_t remoteBuf,
                                  const void *arg,
                                  size_t argSize,
                                  size_t remoteSize)
{
    if (!remoteBuf || remoteSize == 0) return false;

    uint8_t stackBuf[64];
    void *localBuf = stackBuf;
    if (remoteSize > sizeof(stackBuf)) {
        localBuf = calloc(1, remoteSize);
        if (!localBuf) return false;
    } else {
        memset(stackBuf, 0, remoteSize);
    }

    if (arg && argSize) {
        size_t copySize = (argSize < remoteSize) ? argSize : remoteSize;
        memcpy(localBuf, arg, copySize);
    }

    bool ok = remote_write(remoteBuf, localBuf, remoteSize);
    if (localBuf != stackBuf) free(localBuf);
    return ok;
}

static bool locationsim_set_invocation_arg(uint64_t invocation,
                                           uint64_t index,
                                           const void *arg,
                                           size_t argSize)
{
    size_t argBufLen = (argSize > 8) ? argSize : 8;
    uint64_t argBuf = r_dlsym_call(R_TIMEOUT, "malloc",
                                   argBufLen, 0, 0, 0, 0, 0, 0, 0);
    if (!argBuf) return false;

    bool ok = locationsim_write_arg(argBuf, arg, argSize, argBufLen);
    if (ok) {
        r_msg2(invocation, "setArgument:atIndex:", argBuf, index, 0, 0);
    }
    r_free(argBuf);
    return ok;
}

static uint64_t locationsim_invoke_args(uint64_t target,
                                        const char *selectorName,
                                        const LocationSimInvocationArg *args,
                                        uint64_t argCount)
{
    if (!r_is_objc_ptr(target) || !selectorName) return 0;

    uint64_t selector = r_sel(selectorName);
    if (!selector) return 0;

    uint64_t signature = r_msg2(target, "methodSignatureForSelector:",
                                selector, 0, 0, 0);
    if (!r_is_objc_ptr(signature)) {
        printf("[LOCSIM] no method signature for %s\n", selectorName);
        return 0;
    }

    uint64_t reportedArgCount = r_msg2(signature, "numberOfArguments", 0, 0, 0, 0);
    if (reportedArgCount < argCount + 2) {
        printf("[LOCSIM] %s only reports %llu args, need %llu\n",
               selectorName,
               (unsigned long long)reportedArgCount,
               (unsigned long long)(argCount + 2));
        return 0;
    }

    uint64_t NSInvocation = r_class("NSInvocation");
    if (!r_is_objc_ptr(NSInvocation)) return 0;

    uint64_t invocation = r_msg2(NSInvocation, "invocationWithMethodSignature:",
                                 signature, 0, 0, 0);
    if (!r_is_objc_ptr(invocation)) return 0;

    uint64_t retained = r_msg2(invocation, "retain", 0, 0, 0, 0);
    if (r_is_objc_ptr(retained)) invocation = retained;

    r_msg2(invocation, "setTarget:", target, 0, 0, 0);
    r_msg2(invocation, "setSelector:", selector, 0, 0, 0);

    bool ok = true;
    for (uint64_t i = 0; i < argCount; i++) {
        ok = locationsim_set_invocation_arg(invocation,
                                            i + 2,
                                            args[i].data,
                                            args[i].size);
        if (!ok) break;
    }
    if (!ok) {
        r_msg2(invocation, "release", 0, 0, 0, 0);
        return 0;
    }

    r_msg2(invocation, "retainArguments", 0, 0, 0, 0);
    r_msg2(invocation, "invoke", 0, 0, 0, 0);

    uint64_t ret = 0;
    uint64_t retLen = r_msg2(signature, "methodReturnLength", 0, 0, 0, 0);
    if (retLen > 0) {
        uint64_t retBufLen = (retLen > 8) ? retLen : 8;
        uint64_t retBuf = r_dlsym_call(R_TIMEOUT, "malloc",
                                       retBufLen, 0, 0, 0, 0, 0, 0, 0);
        if (retBuf) {
            remote_write64(retBuf, 0);
            r_msg2(invocation, "getReturnValue:", retBuf, 0, 0, 0);
            ret = remote_read64(retBuf);
            r_free(retBuf);
        }
    }

    r_msg2(invocation, "release", 0, 0, 0, 0);
    return ret;
}

static uint64_t locationsim_invoke_raw5(uint64_t target,
                                        const char *selectorName,
                                        const void *a0, size_t a0Size,
                                        const void *a1, size_t a1Size,
                                        const void *a2, size_t a2Size,
                                        const void *a3, size_t a3Size,
                                        const void *a4, size_t a4Size)
{
    LocationSimInvocationArg args[] = {
        { a0, a0Size },
        { a1, a1Size },
        { a2, a2Size },
        { a3, a3Size },
        { a4, a4Size },
    };
    return locationsim_invoke_args(target, selectorName,
                                   args, sizeof(args) / sizeof(args[0]));
}

static void locationsim_set_double_property(uint64_t target,
                                            const char *selectorName,
                                            double value)
{
    LocationSimInvocationArg arg = { &value, sizeof(value) };
    locationsim_invoke_args(target, selectorName, &arg, 1);
}

static void locationsim_dlopen_corelocation(void)
{
    uint64_t path = r_alloc_str("/System/Library/Frameworks/CoreLocation.framework/CoreLocation");
    if (!path) return;
    r_dlsym_call(R_TIMEOUT, "dlopen", path, RTLD_LAZY | RTLD_GLOBAL,
                 0, 0, 0, 0, 0, 0);
    r_free(path);
}

static bool locationsim_launch_bundle(const char *bundleIdentifier, const char *label)
{
    bundleIdentifier = locationsim_str_or_null(bundleIdentifier);
    label = locationsim_str_or_null(label);
    if (!label) label = bundleIdentifier;
    if (!bundleIdentifier) return false;

    if (init_remote_call("SpringBoard", false) != 0) {
        printf("[LOCSIM] init_remote_call(SpringBoard) failed while launching %s\n",
               label);
        return false;
    }

    bool ok = false;
    uint64_t bid = r_nsstr_retained(bundleIdentifier);
    if (r_is_objc_ptr(bid)) {
        uint64_t result = r_dlsym_call(R_TIMEOUT, "SBSLaunchApplicationWithIdentifier",
                                       bid, 0, 0, 0, 0, 0, 0, 0);
        ok = remote_call_current_success();
        r_msg2_main(bid, "release", 0, 0, 0, 0);
        printf("[LOCSIM] %s foreground launch result=%llu ok=%d\n",
               label,
               (unsigned long long)result,
               ok);
    }

    destroy_remote_call();
    usleep(locationsim_is_ios_below_18() ? 3000000 : 1500000);
    return ok;
}

static bool locationsim_launch_maps(void)
{
    return locationsim_launch_bundle("com.apple.Maps", "Maps");
}

static uint64_t locationsim_build_source_information(void)
{
    uint64_t CLLocationSourceInformation = r_class("CLLocationSourceInformation");
    if (!r_is_objc_ptr(CLLocationSourceInformation)) {
        locationsim_dlopen_corelocation();
        CLLocationSourceInformation = r_class("CLLocationSourceInformation");
    }
    if (!r_is_objc_ptr(CLLocationSourceInformation)) {
        printf("[LOCSIM] CLLocationSourceInformation class unavailable in host\n");
        return 0;
    }

    uint64_t allocated = r_msg2(CLLocationSourceInformation, "alloc", 0, 0, 0, 0);
    if (!r_is_objc_ptr(allocated)) return 0;

    const char *selector = "initWithSoftwareSimulationState:andExternalAccessoryState:";
    if (!r_responds(allocated, selector)) {
        printf("[LOCSIM] CLLocationSourceInformation source-state initializer unavailable\n");
        return 0;
    }

    uint64_t info = r_msg2(allocated, selector, 0, 0, 0, 0);
    if (!r_is_objc_ptr(info)) {
        printf("[LOCSIM] CLLocationSourceInformation init failed\n");
        return 0;
    }
    return info;
}

static void locationsim_log_source_information(uint64_t location)
{
    if (!r_is_objc_ptr(location)) return;

    uint64_t sourceInfo = r_msg2(location, "sourceInformation", 0, 0, 0, 0);
    if (!r_is_objc_ptr(sourceInfo)) {
        printf("[LOCSIM] built CLLocation sourceInfo=nil\n");
        return;
    }

    uint64_t simulated = r_msg2(sourceInfo, "isSimulatedBySoftware", 0, 0, 0, 0);
    uint64_t accessory = r_msg2(sourceInfo, "isProducedByAccessory", 0, 0, 0, 0);
    printf("[LOCSIM] built CLLocation sourceInfo simulated=%llu accessory=%llu\n",
           (unsigned long long)(simulated & 0xff),
           (unsigned long long)(accessory & 0xff));
}

static uint64_t locationsim_build_location(double latitude,
                                           double longitude,
                                           double altitude,
                                           double horizontalAccuracy,
                                           double verticalAccuracy,
                                           double course,
                                           double speed,
                                           bool logSourceInfo)
{
    uint64_t CLLocation = r_class("CLLocation");
    if (!r_is_objc_ptr(CLLocation)) {
        locationsim_dlopen_corelocation();
        CLLocation = r_class("CLLocation");
    }
    if (!r_is_objc_ptr(CLLocation)) {
        printf("[LOCSIM] CLLocation class unavailable in host\n");
        return 0;
    }

    uint64_t NSDate = r_class("NSDate");
    uint64_t timestamp = r_msg2(NSDate, "date", 0, 0, 0, 0);
    if (!r_is_objc_ptr(timestamp)) {
        printf("[LOCSIM] NSDate timestamp allocation failed\n");
        return 0;
    }

    uint64_t allocated = r_msg2(CLLocation, "alloc", 0, 0, 0, 0);
    if (!r_is_objc_ptr(allocated)) return 0;

    LocationSimCoordinate coord = { latitude, longitude };
    uint64_t sourceInfo = locationsim_build_source_information();
    if (r_is_objc_ptr(sourceInfo)) {
        double courseAccuracy = 0.0;
        double speedAccuracy = 0.0;
        LocationSimInvocationArg args[] = {
            { &coord, sizeof(coord) },
            { &altitude, sizeof(altitude) },
            { &horizontalAccuracy, sizeof(horizontalAccuracy) },
            { &verticalAccuracy, sizeof(verticalAccuracy) },
            { &course, sizeof(course) },
            { &courseAccuracy, sizeof(courseAccuracy) },
            { &speed, sizeof(speed) },
            { &speedAccuracy, sizeof(speedAccuracy) },
            { &timestamp, sizeof(timestamp) },
            { &sourceInfo, sizeof(sourceInfo) },
        };
        uint64_t locWithSource = locationsim_invoke_args(
            allocated,
            "initWithCoordinate:altitude:horizontalAccuracy:verticalAccuracy:course:courseAccuracy:speed:speedAccuracy:timestamp:sourceInfo:",
            args,
            sizeof(args) / sizeof(args[0]));
        if (r_is_objc_ptr(locWithSource)) {
            if (logSourceInfo) {
                printf("[LOCSIM] built CLLocation with non-simulated sourceInfo\n");
                locationsim_log_source_information(locWithSource);
            }
            return locWithSource;
        }
        if (logSourceInfo) {
            printf("[LOCSIM] sourceInfo CLLocation init failed; falling back to legacy init\n");
        }
        allocated = r_msg2(CLLocation, "alloc", 0, 0, 0, 0);
        if (!r_is_objc_ptr(allocated)) return 0;
    }

    uint64_t loc = locationsim_invoke_raw5(
        allocated,
        "initWithCoordinate:altitude:horizontalAccuracy:verticalAccuracy:timestamp:",
        &coord, sizeof(coord),
        &altitude, sizeof(altitude),
        &horizontalAccuracy, sizeof(horizontalAccuracy),
        &verticalAccuracy, sizeof(verticalAccuracy),
        &timestamp, sizeof(timestamp));

    if (!r_is_objc_ptr(loc)) {
        printf("[LOCSIM] CLLocation initWithCoordinate failed\n");
        return 0;
    }

    if (logSourceInfo) locationsim_log_source_information(loc);
    return loc;
}

static uint64_t locationsim_new_manager(void)
{
    uint64_t CLSimulationManager = r_class("CLSimulationManager");
    if (!r_is_objc_ptr(CLSimulationManager)) {
        locationsim_dlopen_corelocation();
        CLSimulationManager = r_class("CLSimulationManager");
    }
    if (!r_is_objc_ptr(CLSimulationManager)) {
        printf("[LOCSIM] CLSimulationManager class unavailable in host\n");
        return 0;
    }

    uint64_t allocated = r_msg2(CLSimulationManager, "alloc", 0, 0, 0, 0);
    uint64_t manager = r_msg2(allocated, "init", 0, 0, 0, 0);
    if (!r_is_objc_ptr(manager)) {
        printf("[LOCSIM] CLSimulationManager init failed\n");
        return 0;
    }
    return manager;
}

static void locationsim_stop_manager(uint64_t manager)
{
    if (!r_is_objc_ptr(manager)) return;

    r_msg2(manager, "stopLocationSimulation", 0, 0, 0, 0);
    r_msg2(manager, "clearSimulatedLocations", 0, 0, 0, 0);
    r_msg2(manager, "stopWifiSimulation", 0, 0, 0, 0);
    r_msg2(manager, "stopCellSimulation", 0, 0, 0, 0);
    r_msg2(manager, "clearSimulatedCells", 0, 0, 0, 0);
    r_msg2(manager, "flush", 0, 0, 0, 0);
    usleep(250000);

    r_msg2(manager, "stopLocationSimulation", 0, 0, 0, 0);
    r_msg2(manager, "clearSimulatedLocations", 0, 0, 0, 0);
    r_msg2(manager, "flush", 0, 0, 0, 0);
    usleep(250000);
}

static double locationsim_clamp(double value, double minValue, double maxValue)
{
    if (value < minValue) return minValue;
    if (value > maxValue) return maxValue;
    return value;
}

static void locationsim_configure_route_manager(uint64_t manager)
{
    if (!r_is_objc_ptr(manager)) return;

    uint64_t oldDelivery = r_msg2(manager, "locationDeliveryBehavior", 0, 0, 0, 0);
    uint64_t oldRepeat = r_msg2(manager, "locationRepeatBehavior", 0, 0, 0, 0);

    r_msg2(manager, "setLocationRepeatBehavior:", 2, 0, 0, 0);
    locationsim_set_double_property(manager, "setLocationInterval:",
                                    kLocationSimRouteIntervalSeconds);
    locationsim_set_double_property(manager, "setLocationSpeed:", 1.4);

    uint64_t newDelivery = r_msg2(manager, "locationDeliveryBehavior", 0, 0, 0, 0);
    uint64_t newRepeat = r_msg2(manager, "locationRepeatBehavior", 0, 0, 0, 0);
    printf("[LOCSIM] route manager delivery=%llu->%llu repeat=%llu->%llu interval=1.0s speed=1.4m/s\n",
           (unsigned long long)(oldDelivery & 0xff),
           (unsigned long long)(newDelivery & 0xff),
           (unsigned long long)(oldRepeat & 0xff),
           (unsigned long long)(newRepeat & 0xff));
}

static size_t locationsim_append_loop_locations(uint64_t manager,
                                                const LocationSimConfig *config,
                                                double *radiusOut)
{
    if (!r_is_objc_ptr(manager) || !config) return 0;

    double radiusMeters = locationsim_clamp(config->horizontalAccuracy * 2.5, 10.0, 15.0);
    double cosLat = cos(config->latitude * kLocationSimPi / 180.0);
    if (fabs(cosLat) < 0.000001) cosLat = (cosLat < 0.0) ? -0.000001 : 0.000001;

    double metersPerDegreeLongitude = kLocationSimMetersPerDegreeLatitude * cosLat;
    size_t appended = 0;

    for (size_t i = 0; i < kLocationSimRoutePointCount; i++) {
        double angle = (2.0 * kLocationSimPi * (double)i) / (double)kLocationSimRoutePointCount;
        double nextAngle = (2.0 * kLocationSimPi * (double)(i + 1)) /
                           (double)kLocationSimRoutePointCount;
        double eastMeters = radiusMeters * cos(angle);
        double northMeters = radiusMeters * sin(angle);
        double nextEastMeters = radiusMeters * cos(nextAngle);
        double nextNorthMeters = radiusMeters * sin(nextAngle);

        double latitude = config->latitude + northMeters / kLocationSimMetersPerDegreeLatitude;
        double longitude = config->longitude + eastMeters / metersPerDegreeLongitude;
        double deltaEast = nextEastMeters - eastMeters;
        double deltaNorth = nextNorthMeters - northMeters;
        double course = atan2(deltaEast, deltaNorth) * 180.0 / kLocationSimPi;
        if (course < 0.0) course += 360.0;

        double stepMeters = sqrt(deltaEast * deltaEast + deltaNorth * deltaNorth);
        double speed = locationsim_clamp(stepMeters / kLocationSimRouteIntervalSeconds,
                                         0.8,
                                         4.0);
        uint64_t location = locationsim_build_location(latitude,
                                                       longitude,
                                                       config->altitude,
                                                       config->horizontalAccuracy,
                                                       config->verticalAccuracy,
                                                       course,
                                                       speed,
                                                       appended == 0);
        if (!r_is_objc_ptr(location)) continue;

        r_msg2(manager, "appendSimulatedLocation:", location, 0, 0, 0);
        appended++;
    }

    if (radiusOut) *radiusOut = radiusMeters;
    return appended;
}

static void locationsim_notify_timezone(void)
{
    uint64_t name = r_alloc_str("AutomaticTimeZoneUpdateNeeded");
    if (!name) return;
    r_dlsym_call(R_TIMEOUT, "notify_post", name, 0, 0, 0, 0, 0, 0, 0);
    r_free(name);
}

static bool locationsim_validate_config(const LocationSimConfig *config)
{
    if (!config) return false;
    if (!isfinite(config->latitude) || !isfinite(config->longitude)) return false;
    if (config->latitude < -90.0 || config->latitude > 90.0) return false;
    if (config->longitude < -180.0 || config->longitude > 180.0) return false;
    if (!isfinite(config->altitude)) return false;
    if (!isfinite(config->horizontalAccuracy) || config->horizontalAccuracy <= 0.0) return false;
    if (!isfinite(config->verticalAccuracy) || config->verticalAccuracy <= 0.0) return false;
    return true;
}

static bool locationsim_init_host(const char *host, int initTimeoutMS)
{
    if (locationsim_is_ios_below_18() && locationsim_host_is_maps(host)) {
        int timeoutMS = initTimeoutMS > 0 ? initTimeoutMS : 120000;
        printf("[LOCSIM] using original-thread RemoteCall for Maps on iOS %ld\n",
               (long)locationsim_ios_major_version());
        return init_remote_call_original_thread_only_with_first_exception_timeout(host,
                                                                                  false,
                                                                                  timeoutMS) == 0;
    }

    if (initTimeoutMS > 0) {
        return init_remote_call_with_first_exception_timeout(host, false, initTimeoutMS) == 0;
    }
    return init_remote_call(host, false) == 0;
}

static bool locationsim_apply_to_host(const LocationSimConfig *config,
                                      const char *host,
                                      bool launchHost,
                                      int initTimeoutMS)
{
    if (!locationsim_validate_config(config)) {
        printf("[LOCSIM] invalid config\n");
        return false;
    }

    host = locationsim_host_or_default(host);
    if (launchHost && locationsim_host_is_maps(host)) {
        if (!locationsim_launch_maps()) {
            printf("[LOCSIM] Maps launch did not report success; trying host anyway\n");
        }
    }

    if (!locationsim_init_host(host, initTimeoutMS)) {
        printf("[LOCSIM] init_remote_call(%s) failed (%s pid=%u)\n",
               host,
               remote_call_init_failure_description(remote_call_last_init_failure()),
               remote_call_last_init_failure_pid());
        return false;
    }

    uint64_t manager = locationsim_new_manager();
    bool ok = false;
    if (r_is_objc_ptr(manager)) {
        locationsim_stop_manager(manager);
        locationsim_configure_route_manager(manager);

        double radiusMeters = 0.0;
        size_t routePoints = locationsim_append_loop_locations(manager,
                                                               config,
                                                               &radiusMeters);
        if (routePoints > 0) {
            r_msg2(manager, "flush", 0, 0, 0, 0);
            r_msg2(manager, "startLocationSimulation", 0, 0, 0, 0);
            locationsim_notify_timezone();
            ok = true;
            printf("[LOCSIM] started loop %.8f, %.8f alt=%.1f hAcc=%.1f host=%s points=%zu radius=%.1fm\n",
                   config->latitude,
                   config->longitude,
                   config->altitude,
                   config->horizontalAccuracy,
                   host,
                   routePoints,
                   radiusMeters);
        } else {
            printf("[LOCSIM] no loop locations appended host=%s\n", host);
        }
    }

    destroy_remote_call();
    return ok;
}

bool locationsim_apply_static(const LocationSimConfig *config)
{
    if (!config) return false;
    return locationsim_apply_to_host(config,
                                     locationsim_host_or_default(config->hostProcess),
                                     config->launchHost,
                                     0);
}

bool locationsim_apply_strict_hosts(const LocationSimConfig *config)
{
    if (!locationsim_validate_config(config)) {
        printf("[LOCSIM] invalid strict config\n");
        return false;
    }

    const char *primary = locationsim_host_or_default(config->hostProcess);
    bool anyOK = false;
    bool primaryOK = locationsim_apply_to_host(config, primary, config->launchHost, 0);
    anyOK = anyOK || primaryOK;
    printf("[LOCSIM] strict host primary=%s result=%s\n",
           primary,
           primaryOK ? "ok" : "failed");

    const char *strictHosts[] = {
        "locationd",
        "navd",
        "routined",
        "geod",
    };

    for (size_t i = 0; i < sizeof(strictHosts) / sizeof(strictHosts[0]); i++) {
        const char *host = strictHosts[i];
        if (strcmp(host, primary) == 0) continue;

        LocationSimConfig hostConfig = *config;
        hostConfig.hostProcess = host;
        hostConfig.launchHost = false;

        bool hostOK = locationsim_apply_to_host(&hostConfig,
                                                host,
                                                false,
                                                kLocationSimOptionalHostInitTimeoutMS);
        printf("[LOCSIM] strict host %s result=%s\n",
               host,
               hostOK ? "ok" : "failed");
        anyOK = anyOK || hostOK;
    }

    printf("[LOCSIM] strict host sweep %s\n", anyOK ? "reached at least one host" : "failed");
    return anyOK;
}

static bool locationsim_stop_in_host(const char *hostProcess, bool launchHost, int initTimeoutMS)
{
    const char *host = locationsim_host_or_default(hostProcess);
    if (launchHost && locationsim_host_is_maps(host)) {
        if (!locationsim_launch_maps()) {
            printf("[LOCSIM] Maps launch did not report success for stop; trying host anyway\n");
        }
    }

    if (!locationsim_init_host(host, initTimeoutMS)) {
        printf("[LOCSIM] init_remote_call(%s) failed for stop (%s pid=%u)\n",
               host,
               remote_call_init_failure_description(remote_call_last_init_failure()),
               remote_call_last_init_failure_pid());
        return false;
    }

    bool ok = false;
    uint64_t manager = locationsim_new_manager();
    if (r_is_objc_ptr(manager)) {
        locationsim_stop_manager(manager);
        locationsim_notify_timezone();
        ok = true;
        printf("[LOCSIM] stopped host=%s\n", host);
    }

    destroy_remote_call();
    return ok;
}

bool locationsim_stop(const char *hostProcess, bool launchHost)
{
    const char *primary = locationsim_host_or_default(hostProcess);
    bool primaryOk = locationsim_stop_in_host(primary, launchHost, 0);
    bool locationdOk = false;

    if (strcmp(primary, "locationd") != 0) {
        locationdOk = locationsim_stop_in_host("locationd",
                                               false,
                                               kLocationSimOptionalHostInitTimeoutMS);
    }

    if (!primaryOk && !locationdOk) {
        printf("[LOCSIM] restore did not reach any simulation manager\n");
    } else if (locationdOk) {
        printf("[LOCSIM] restore fallback reached locationd\n");
    }

    return primaryOk || locationdOk;
}

bool locationsim_stop_strict_hosts(const char *hostProcess, bool launchHost)
{
    const char *primary = locationsim_host_or_default(hostProcess);
    bool anyOK = locationsim_stop(primary, launchHost);

    const char *strictHosts[] = {
        "navd",
        "routined",
        "geod",
    };

    for (size_t i = 0; i < sizeof(strictHosts) / sizeof(strictHosts[0]); i++) {
        const char *host = strictHosts[i];
        if (strcmp(host, primary) == 0) continue;

        bool hostOK = locationsim_stop_in_host(host,
                                               false,
                                               kLocationSimOptionalHostInitTimeoutMS);
        printf("[LOCSIM] strict stop host %s result=%s\n",
               host,
               hostOK ? "ok" : "failed");
        anyOK = anyOK || hostOK;
    }

    printf("[LOCSIM] strict stop sweep %s\n", anyOK ? "reached at least one host" : "failed");
    return anyOK;
}
