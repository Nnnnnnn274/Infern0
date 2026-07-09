#ifndef tweakloader_h
#define tweakloader_h

#include <stdbool.h>

typedef bool (*tweakloader_func_t)(void);

void tweakloader_register(const char *name, tweakloader_func_t apply, tweakloader_func_t stop);
void tweakloader_reload_list(void);
unsigned int tweakloader_loaded_count(void);
const char *tweakloader_name_at(unsigned int index);
bool tweakloader_apply_at(unsigned int index);
bool tweakloader_stop_at(unsigned int index);
bool tweakloader_apply_in_session(void);
bool tweakloader_stop_in_session(void);
void tweakloader_forget_remote_state(void);

#endif
