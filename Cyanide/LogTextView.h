//
//  LogTextView.h
//  Cyanide
//
//  Created by seo on 4/7/26.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface LogTextView : UITextView
@end

void log_init(void);
void log_write(const char *msg);
void log_set_verbose(BOOL enabled);
BOOL log_verbose_enabled(void);
void log_user(const char *fmt, ...) __attribute__((format(printf, 1, 2)));

// Mirror printf into the LogTextView ring buffer. Any TU that imports this
// header gets its printf calls echoed both to stdout and to the in-app log.
#define printf(fmt, ...) ({ \
    printf(fmt, ##__VA_ARGS__); \
    char _logbuf[2560]; \
    snprintf(_logbuf, sizeof(_logbuf), fmt, ##__VA_ARGS__); \
    log_write(_logbuf); \
})
