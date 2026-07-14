#ifndef customizers_h
#define customizers_h

#include <stdbool.h>

void homecustom_configure(bool hideBadges, bool hidePageDots, bool hideFolderBackground,
                          bool hideDockBackground, int iconAlphaPercent);
bool homecustom_apply_in_session(void);
bool homecustom_stop_in_session(void);
void homecustom_forget_remote_state(void);

void freeplacement_configure(int horizontalStep, int verticalStep, int staggerPercent);
bool freeplacement_apply_in_session(void);
bool freeplacement_stop_in_session(void);
void freeplacement_forget_remote_state(void);

void applibrarystudio_configure(int iconScalePercent, int horizontalSpacing,
                                int verticalSpacing, bool hideLabels, bool disableTodayView);
bool applibrarystudio_apply_in_session(void);
bool applibrarystudio_stop_in_session(void);
void applibrarystudio_forget_remote_state(void);

void lockcustomizer_configure(int clockScalePercent, int horizontalOffset, int verticalOffset,
                              bool hideQuickActions, bool hidePageDots, int contentAlphaPercent,
                              int mediaScalePercent, bool hideMediaArtwork,
                              bool metalLightEnabled, int metalLightIntensityPercent,
                              int metalLightThickness, int metalLightStyle);
bool lockcustomizer_apply_in_session(void);
bool lockcustomizer_stop_in_session(void);
void lockcustomizer_forget_remote_state(void);

#endif
