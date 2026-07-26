//
//  compat.h
//  lara
//
//  Created by ruter on 14.04.26.
//  Stolen from baconmania :heart:
//

#ifndef compat_h
#define compat_h

#import "darksword.h"
#import "offsets.h"
#import "utils.h"

#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v) \
    ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)

#endif /* compat_h */
