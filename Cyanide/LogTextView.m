//
//  LogTextView.m
//  Cyanide
//
//  Created by seo on 4/7/26.
//

#import "LogTextView.h"
#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#define LOG_MAX_LINES   50000
#define LOG_TRIM_TO     30000
#define LOG_LINE_SIZE   2560

static char            log_buf[LOG_MAX_LINES][LOG_LINE_SIZE];
static int             log_count    = 0;
static int             log_dirty    = 0;
static int             log_trim_gen = 0;  // increments each time the buffer is trimmed
static int             log_verbose  = 1;
static pthread_mutex_t log_mutex    = PTHREAD_MUTEX_INITIALIZER;

void log_init(void) {
    pthread_mutex_lock(&log_mutex);
    log_count = 0;
    log_dirty = 0;
    pthread_mutex_unlock(&log_mutex);
}

static char line_buf[LOG_LINE_SIZE];
static int  line_pos = 0;

static void log_write_raw(const char *msg) {
    pthread_mutex_lock(&log_mutex);

    while (*msg) {
        if (*msg == '\n') {
            line_buf[line_pos] = '\0';

            if (log_count >= LOG_MAX_LINES) {
                memmove(log_buf[0], log_buf[LOG_MAX_LINES - LOG_TRIM_TO], LOG_TRIM_TO * LOG_LINE_SIZE);
                log_count = LOG_TRIM_TO;
                log_trim_gen++;
            }
            strlcpy(log_buf[log_count], line_buf, LOG_LINE_SIZE);
            log_count++;
            log_dirty = 1;
            line_pos  = 0;
        } else {
            if (line_pos < LOG_LINE_SIZE - 1)
                line_buf[line_pos++] = *msg;
        }
        msg++;
    }

    pthread_mutex_unlock(&log_mutex);
}

void log_write(const char *msg) {
    if (!log_verbose_enabled()) return;
    log_write_raw(msg);
}

void log_set_verbose(BOOL enabled) {
    pthread_mutex_lock(&log_mutex);
    log_verbose = enabled ? 1 : 0;
    pthread_mutex_unlock(&log_mutex);
}

BOOL log_verbose_enabled(void) {
    pthread_mutex_lock(&log_mutex);
    BOOL enabled = log_verbose != 0;
    pthread_mutex_unlock(&log_mutex);
    return enabled;
}

void log_user(const char *fmt, ...) {
    char buf[LOG_LINE_SIZE];
    va_list ap, ap2;
    va_start(ap, fmt);
    va_copy(ap2, ap);
    vfprintf(stdout, fmt, ap2);
    va_end(ap2);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    log_write_raw(buf);
}

// Returns only lines [fromLine, log_count). Outputs current total and trim
// generation so callers can detect full-buffer trims. Returns nil if nothing new.
static NSString *log_snapshot_from(int fromLine, int *outTotal, int *outTrimGen) {
    pthread_mutex_lock(&log_mutex);
    int total   = log_count;
    int trimGen = log_trim_gen;
    if (outTotal)   *outTotal   = total;
    if (outTrimGen) *outTrimGen = trimGen;

    if (fromLine >= total && !log_dirty) {
        pthread_mutex_unlock(&log_mutex);
        return nil;
    }
    log_dirty = 0;

    int start = (fromLine < total) ? fromLine : total;
    if (start >= total) {
        pthread_mutex_unlock(&log_mutex);
        return nil;
    }

    NSMutableString *s = [[NSMutableString alloc] initWithCapacity:(total - start) * 80];
    for (int i = start; i < total; i++) {
        NSString *line = [NSString stringWithUTF8String:log_buf[i]];
        if (!line) line = [[NSString alloc] initWithBytes:log_buf[i]
                                                   length:strlen(log_buf[i])
                                                 encoding:NSISOLatin1StringEncoding];
        if (line) { [s appendString:line]; [s appendString:@"\n"]; }
    }

    pthread_mutex_unlock(&log_mutex);
    return s;
}

// ---------------------------------------------------------------------------
// Color map

static UIColor *colorForLogLine(NSString *line) {
    // Slim-mode milestone labels
    if ([line hasPrefix:@"[OK]"])        return [UIColor colorWithRed:0.38 green:0.90 blue:0.55 alpha:1.0]; // bright green
    if ([line hasPrefix:@"[WARN]"])      return [UIColor colorWithRed:0.96 green:0.38 blue:0.32 alpha:1.0]; // red
    if ([line hasPrefix:@"[DONE]"])      return [UIColor colorWithRed:0.30 green:0.85 blue:0.95 alpha:1.0]; // cyan
    if ([line hasPrefix:@"[RUN"])        return [UIColor colorWithRed:0.98 green:0.82 blue:0.30 alpha:1.0]; // gold ([RUN] and [RUN N/N])
    if ([line hasPrefix:@"[PLAN]"])      return [UIColor colorWithRed:0.65 green:0.60 blue:0.95 alpha:1.0]; // indigo
    if ([line hasPrefix:@"[BOOT]"])      return [UIColor colorWithRed:0.55 green:0.72 blue:0.92 alpha:1.0]; // cornflower
    if ([line hasPrefix:@"[SESSION]"])   return [UIColor colorWithRed:0.50 green:0.75 blue:0.95 alpha:1.0]; // sky blue
    if ([line hasPrefix:@"[CLEANUP]"])   return [UIColor colorWithRed:0.82 green:0.72 blue:0.56 alpha:1.0]; // warm tan
    if ([line hasPrefix:@"[LOG]"])       return [UIColor colorWithRed:0.60 green:0.62 blue:0.68 alpha:1.0]; // muted gray

    // Verbose subsystem labels
    if ([line hasPrefix:@"[SETTINGS]"])  return [UIColor colorWithRed:0.40 green:0.72 blue:0.96 alpha:1.0]; // sky blue
    if ([line hasPrefix:@"[SBC]"])       return [UIColor colorWithRed:0.80 green:0.58 blue:0.90 alpha:1.0]; // lavender
    if ([line hasPrefix:@"[STATBAR]"])   return [UIColor colorWithRed:0.56 green:0.88 blue:0.64 alpha:1.0]; // mint
    if ([line hasPrefix:@"[POWERCUFF]"]) return [UIColor colorWithRed:0.96 green:0.50 blue:0.50 alpha:1.0]; // coral
    if ([line hasPrefix:@"[DST"])        return [UIColor colorWithRed:0.40 green:0.90 blue:0.88 alpha:1.0]; // teal
    if ([line hasPrefix:@"[OTA]"])       return [UIColor colorWithRed:1.00 green:0.88 blue:0.40 alpha:1.0]; // amber
    if ([line hasPrefix:@"[RESPRING]"])  return [UIColor colorWithRed:1.00 green:0.72 blue:0.30 alpha:1.0]; // orange
    if ([line hasPrefix:@"[5ICON]"])     return [UIColor colorWithRed:0.98 green:0.95 blue:0.55 alpha:1.0]; // pale yellow
    if ([line hasPrefix:@"[KRW]"])       return [UIColor colorWithRed:1.00 green:0.55 blue:0.70 alpha:1.0]; // pink
    if ([line hasPrefix:@"[PERSIST]"])   return [UIColor colorWithRed:0.70 green:0.75 blue:0.85 alpha:1.0]; // steel blue

    return [UIColor colorWithWhite:0.86 alpha:1.0];
}

// ---------------------------------------------------------------------------

@interface LogTextView ()
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic) int renderedLineCount;
@property (nonatomic) int renderedTrimGen;
@property (nonatomic) BOOL followTail;
@property (nonatomic) BOOL pendingTailScroll;
@end

@implementation LogTextView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) [self setup];
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) [self setup];
    return self;
}

- (void)setup {
    self.editable   = NO;
    self.font       = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    self.backgroundColor = [UIColor colorWithRed:0.08 green:0.09 blue:0.16 alpha:1.0];
    self.textColor  = UIColor.whiteColor;
    self.textContainerInset = UIEdgeInsetsMake(12, 10, 12, 10);
    self.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAlways;
    _followTail = YES;

    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
    _displayLink.preferredFramesPerSecond = 60;
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) {
        _renderedLineCount = 0;
        _followTail = YES;
        [self refreshLogTextForced:YES];
    }
}

- (void)tick {
    [self refreshLogTextForced:NO];
}

- (NSMutableAttributedString *)buildAttrStringForText:(NSString *)text {
    UIFont *font = self.font ?: [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
    para.lineSpacing = 4.0;

    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
    NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] init];
    for (NSUInteger i = 0; i < lines.count; i++) {
        NSString *line = lines[i];
        // skip the trailing empty element that follows the last \n
        if (i + 1 == lines.count && line.length == 0) break;
        NSString *lineText = [line stringByAppendingString:@"\n"];
        NSDictionary *attrs = @{
            NSFontAttributeName:            font,
            NSForegroundColorAttributeName: colorForLogLine(line),
            NSParagraphStyleAttributeName:  para,
        };
        [attr appendAttributedString:[[NSAttributedString alloc] initWithString:lineText attributes:attrs]];
    }
    return attr;
}

- (CGFloat)bottomContentOffsetY {
    CGFloat minY = -self.adjustedContentInset.top;
    CGFloat maxY = self.contentSize.height - self.bounds.size.height + self.adjustedContentInset.bottom;
    return MAX(minY, maxY);
}

- (BOOL)isCloseToBottom {
    return self.contentOffset.y >= ([self bottomContentOffsetY] - 80.0);
}

- (void)scrollToBottomNow {
    CGFloat y = [self bottomContentOffsetY];
    if (fabs(self.contentOffset.y - y) > 0.5) {
        [self setContentOffset:CGPointMake(0.0, y) animated:NO];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (_pendingTailScroll || (_followTail && !self.tracking && !self.dragging && !self.decelerating)) {
        _pendingTailScroll = NO;
        [self scrollToBottomNow];
    }
}

- (void)refreshLogTextForced:(BOOL)force {
    if (force) _renderedLineCount = 0;

    int totalLines = 0, trimGen = 0;
    NSString *newText = log_snapshot_from(_renderedLineCount, &totalLines, &trimGen);

    // Buffer was trimmed: old rendered content is stale — full rebuild.
    BOOL needsRebuild = (trimGen != _renderedTrimGen);
    if (needsRebuild) {
        _renderedLineCount = 0;
        _renderedTrimGen   = trimGen;
        newText = log_snapshot_from(0, &totalLines, &trimGen);
    }

    if (!newText) return;

    NSMutableAttributedString *newAttr = [self buildAttrStringForText:newText];
    if (newAttr.length == 0) return;

    BOOL wasEmpty = (_renderedLineCount == 0);
    BOOL userScrolling = self.tracking || self.dragging || self.decelerating;
    if (wasEmpty || (!userScrolling && [self isCloseToBottom])) {
        _followTail = YES;
    } else if (userScrolling && ![self isCloseToBottom]) {
        _followTail = NO;
    }

    [self.textStorage beginEditing];
    if (needsRebuild || wasEmpty) {
        [self.textStorage replaceCharactersInRange:NSMakeRange(0, self.textStorage.length)
                               withAttributedString:newAttr];
    } else {
        [self.textStorage appendAttributedString:newAttr];
    }
    [self.textStorage endEditing];

    _renderedLineCount = totalLines;

    if (_followTail && !userScrolling) {
        _pendingTailScroll = YES;
        [self setNeedsLayout];
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) s = weakSelf;
            if (!s) return;
            if (s.followTail && !s.tracking && !s.dragging && !s.decelerating) {
                s.pendingTailScroll = NO;
                [s layoutIfNeeded];
                [s scrollToBottomNow];
            }
        });
    }
}

- (void)removeFromSuperview {
    [_displayLink invalidate];
    _displayLink = nil;
    [super removeFromSuperview];
}

@end
