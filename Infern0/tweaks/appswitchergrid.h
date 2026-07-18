//
//  appswitchergrid.h
//  Cyanide
//

#ifndef appswitchergrid_h
#define appswitchergrid_h

#import <stdbool.h>

typedef enum {
    AppSwitcherLayoutAutomatic = 0,
    AppSwitcherLayoutDeck = 1,
    AppSwitcherLayoutGridCompact = 2,
    AppSwitcherLayoutGridBalanced = 3,
    AppSwitcherLayoutGridLarge = 4,
} AppSwitcherLayoutMode;

typedef enum {
    AppSwitcherAnimationSystem = 0,
    AppSwitcherAnimationSnappy = 1,
    AppSwitcherAnimationSmooth = 2,
    AppSwitcherAnimationBouncy = 3,
} AppSwitcherAnimationMode;

typedef struct {
    AppSwitcherLayoutMode layout;
    AppSwitcherAnimationMode animation;
} AppSwitcherGridConfig;

bool appswitchergrid_apply_in_session(void);
bool appswitchergrid_apply_config_in_session(AppSwitcherGridConfig config);
bool appswitchergrid_stop_in_session(void);
void appswitchergrid_forget_remote_state(void);

#endif /* appswitchergrid_h */
