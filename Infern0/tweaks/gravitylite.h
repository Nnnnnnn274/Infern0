//
//  gravitylite.h
//  RemoteCall-only core port of Julio Verne's Gravity tweak.
//

#ifndef gravitylite_h
#define gravitylite_h

#import <stdbool.h>

typedef struct {
    bool includeDock;
    bool allowsRotation;
    double magnitude;
    double bounce;
    double friction;
    double resistance;
    double angularResistance;
    double explosionForce;
} GravityLiteConfig;

bool gravitylite_apply_in_session(GravityLiteConfig config);
bool gravitylite_stop_in_session(void);
bool gravitylite_explosion_in_session(double force);
bool gravitylite_update_gravity_angle_in_session(double angle, double magnitude);
void gravitylite_forget_remote_state(void);

#endif /* gravitylite_h */
