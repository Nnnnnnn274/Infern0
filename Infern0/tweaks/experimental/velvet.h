#ifndef velvet_h
#define velvet_h

#import <stdbool.h>

typedef struct {
    bool  hasValue;
    double r, g, b, a;
} VelvetRGBA;

typedef struct {
    VelvetRGBA bgColor;
    VelvetRGBA borderColor;
    double    borderWidth;
    VelvetRGBA titleColor;
    VelvetRGBA messageColor;
    VelvetRGBA dateColor;
    double    cornerRadius;
    bool      hasCornerRadius;
} VelvetStyle;

bool velvet_apply_in_session(void);
bool velvet_tick_in_session(void);
bool velvet_stop_in_session(void);
void velvet_forget_remote_state(void);
bool velvet_has_remote_state(void);

void velvet_set_global_style(const VelvetStyle *style);

#endif
