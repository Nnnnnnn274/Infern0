//
//  libgrabkernel2.h
//  Public API from alfiecg24/libgrabkernel2, as bundled by rooootdev/lara.
//

#ifndef infern0_libgrabkernel2_h
#define infern0_libgrabkernel2_h

#import <Foundation/Foundation.h>
#import <stdbool.h>

bool download_kernelcache_for(NSString *boardconfig, NSString *zipURL,
                              bool isOTA, NSString *outPath);
bool grab_kernelcache_for(NSString *osStr, NSString *build,
                          NSString *modelIdentifier, NSString *boardconfig,
                          NSString *outPath);
bool download_kernelcache(NSString *zipURL, bool isOTA, NSString *outPath);
bool grab_kernelcache(NSString *outPath);
bool grab_kernelcache_for_build_number(NSString *build, NSString *outPath);
int grabkernel(char *downloadPath, int isResearchKernel);

#endif
