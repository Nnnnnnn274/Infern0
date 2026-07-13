#import "barmoji.h"
#import "../remote_objc.h"
#import "../sb_walk.h"
#import "../../TaskRop/RemoteCall.h"

#import <Foundation/Foundation.h>

typedef struct {
    double x;
    double y;
    double width;
    double height;
} BarmojiRect;

static uint64_t gBarmojiView = 0;
static uint64_t gBarmojiFeedback = 0;
static int gBarmojiYOffset = 92;
static int gBarmojiWidthPercent = 92;
static int gBarmojiFontSize = 21;
static int gBarmojiBackgroundAlphaPercent = 86;

static uint64_t barmoji_color(double red, double green, double blue, double alpha)
{
    uint64_t UIColor = r_class("UIColor");
    if (!r_is_objc_ptr(UIColor)) return 0;
    return r_msg2_main_raw(UIColor, "colorWithRed:green:blue:alpha:",
                           &red, sizeof(red),
                           &green, sizeof(green),
                           &blue, sizeof(blue),
                           &alpha, sizeof(alpha));
}

static BarmojiRect barmoji_bounds_for_view(uint64_t view)
{
    BarmojiRect bounds = { 0, 0, 390, 844 };
    if (r_is_objc_ptr(view)) {
        r_msg2_main_struct_ret(view, "bounds", &bounds, sizeof(bounds),
                               NULL, 0, NULL, 0, NULL, 0, NULL, 0);
    }
    if (bounds.width <= 0) bounds.width = 390;
    if (bounds.height <= 0) bounds.height = 844;
    return bounds;
}

static uint64_t barmoji_alloc_view(double x, double y, double w, double h)
{
    uint64_t UIView = r_class("UIView");
    if (!r_is_objc_ptr(UIView)) return 0;
    uint64_t view = r_msg2_main(UIView, "alloc", 0, 0, 0, 0);
    if (!r_is_objc_ptr(view)) return 0;
    BarmojiRect frame = { x, y, w, h };
    view = r_msg2_main_raw(view, "initWithFrame:", &frame, sizeof(frame), NULL, 0, NULL, 0, NULL, 0);
    return r_is_objc_ptr(view) ? view : 0;
}

static uint64_t barmoji_alloc_button(const char *emoji, double x, double y,
                                     double w, double h, double fontSize)
{
    uint64_t UIButton = r_class("UIButton");
    if (!r_is_objc_ptr(UIButton)) return 0;
    uint64_t button = r_msg2_main(UIButton, "buttonWithType:", 0, 0, 0, 0);
    if (!r_is_objc_ptr(button)) return 0;
    BarmojiRect frame = { x, y, w, h };
    r_msg2_main_raw(button, "setFrame:", &frame, sizeof(frame), NULL, 0, NULL, 0, NULL, 0);
    uint64_t title = r_nsstr_retained(emoji ?: "");
    if (r_is_objc_ptr(title)) {
        r_msg2_main(button, "setTitle:forState:", title, 0, 0, 0);
        r_msg2_main(title, "release", 0, 0, 0, 0);
    }
    uint64_t label = r_msg2_main(button, "titleLabel", 0, 0, 0, 0);
    uint64_t UIFont = r_class("UIFont");
    if (r_is_objc_ptr(label) && r_is_objc_ptr(UIFont)) {
        uint64_t font = r_msg2_main_raw(UIFont, "systemFontOfSize:",
                                        &fontSize, sizeof(fontSize),
                                        NULL, 0, NULL, 0, NULL, 0);
        if (r_is_objc_ptr(font)) r_msg2_main(label, "setFont:", font, 0, 0, 0);
    }
    r_msg2_main(button, "setShowsTouchWhenHighlighted:", 1, 0, 0, 0);
    r_msg2_main(button, "setExclusiveTouch:", 1, 0, 0, 0);
    r_msg2_main(button, "setUserInteractionEnabled:", 1, 0, 0, 0);
    if (r_is_objc_ptr(gBarmojiFeedback)) {
        r_msg2_main(button, "addTarget:action:forControlEvents:",
                    gBarmojiFeedback, r_sel("selectionChanged"), 1ULL << 6, 0);
    }
    return button;
}

bool barmoji_apply_in_session(void)
{
    printf("[BARMOJI] apply\n");
    if (r_is_objc_ptr(gBarmojiView)) {
        r_msg2_main(gBarmojiView, "removeFromSuperview", 0, 0, 0, 0);
        gBarmojiView = 0;
    }

    uint64_t win = sb_frontmost_window();
    if (!r_is_objc_ptr(win)) return false;
    BarmojiRect bounds = barmoji_bounds_for_view(win);
    double barWidth = bounds.width * ((double)gBarmojiWidthPercent / 100.0);
    if (barWidth > 390.0) barWidth = 390.0;
    if (barWidth < 260.0) barWidth = 260.0;
    double barX = (bounds.width - barWidth) / 2.0;
    double barY = bounds.height - (double)gBarmojiYOffset;
    uint64_t bar = barmoji_alloc_view(barX, barY, barWidth, 38);
    if (!r_is_objc_ptr(bar)) return false;
    r_msg2_main(bar, "setUserInteractionEnabled:", 1, 0, 0, 0);

    if (!r_is_objc_ptr(gBarmojiFeedback)) {
        uint64_t feedbackClass = r_class("UISelectionFeedbackGenerator");
        gBarmojiFeedback = r_is_objc_ptr(feedbackClass)
            ? r_msg2_main(feedbackClass, "new", 0, 0, 0, 0) : 0;
    }
    if (r_is_objc_ptr(gBarmojiFeedback))
        r_msg2_main(gBarmojiFeedback, "prepare", 0, 0, 0, 0);

    uint64_t bg = barmoji_color(0.16, 0.16, 0.18, (double)gBarmojiBackgroundAlphaPercent / 100.0);
    if (r_is_objc_ptr(bg)) r_msg2_main(bar, "setBackgroundColor:", bg, 0, 0, 0);
    uint64_t layer = r_msg2_main(bar, "layer", 0, 0, 0, 0);
    if (r_is_objc_ptr(layer)) {
        double radius = 10.0;
        r_msg2_main_raw(layer, "setCornerRadius:", &radius, sizeof(radius), NULL, 0, NULL, 0, NULL, 0);
        r_msg2_main(layer, "setMasksToBounds:", 1, 0, 0, 0);
        double borderWidth = 0.5;
        uint64_t border = barmoji_color(1, 1, 1, 0.18);
        uint64_t cg = r_is_objc_ptr(border) ? r_msg2_main(border, "CGColor", 0, 0, 0, 0) : 0;
        if (cg) r_msg2_main(layer, "setBorderColor:", cg, 0, 0, 0);
        r_msg2_main_raw(layer, "setBorderWidth:", &borderWidth, sizeof(borderWidth), NULL, 0, NULL, 0, NULL, 0);
    }

    const char *emojis[] = {
        "\xF0\x9F\x98\x80", "\xF0\x9F\x98\x82", "\xE2\x9D\xA4\xEF\xB8\x8F",
        "\xF0\x9F\x91\x8D", "\xF0\x9F\x99\x8F", "\xF0\x9F\x94\xA5",
        "\xF0\x9F\x98\xAD", "\xE2\x9C\xA8"
    };
    double buttonWidth = (barWidth - 12.0) / 8.0;
    int buttonCount = 0;
    for (int i = 0; i < 8; i++) {
        uint64_t button = barmoji_alloc_button(emojis[i], 6.0 + buttonWidth * i,
                                               2.0, buttonWidth, 34.0,
                                               (double)gBarmojiFontSize);
        if (!r_is_objc_ptr(button)) continue;
        r_msg2_main(bar, "addSubview:", button, 0, 0, 0);
        buttonCount++;
    }

    r_msg2_main(win, "addSubview:", bar, 0, 0, 0);
    gBarmojiView = bar;
    printf("[BARMOJI] interactive buttons=%d window=0x%llx\n", buttonCount, win);
    return buttonCount == 8;
}

bool barmoji_stop_in_session(void)
{
    printf("[BARMOJI] stop\n");
    if (r_is_objc_ptr(gBarmojiView)) r_msg2_main(gBarmojiView, "removeFromSuperview", 0, 0, 0, 0);
    gBarmojiView = 0;
    if (r_is_objc_ptr(gBarmojiFeedback)) r_msg2_main(gBarmojiFeedback, "release", 0, 0, 0, 0);
    gBarmojiFeedback = 0;
    return true;
}

void barmoji_configure(int yOffset, int widthPercent, int fontSize, int backgroundAlphaPercent)
{
    if (yOffset < 48) yOffset = 48;
    if (yOffset > 180) yOffset = 180;
    if (widthPercent < 65) widthPercent = 65;
    if (widthPercent > 100) widthPercent = 100;
    if (fontSize < 14) fontSize = 14;
    if (fontSize > 28) fontSize = 28;
    if (backgroundAlphaPercent < 20) backgroundAlphaPercent = 20;
    if (backgroundAlphaPercent > 100) backgroundAlphaPercent = 100;
    gBarmojiYOffset = yOffset;
    gBarmojiWidthPercent = widthPercent;
    gBarmojiFontSize = fontSize;
    gBarmojiBackgroundAlphaPercent = backgroundAlphaPercent;
}

void barmoji_forget_remote_state(void) { gBarmojiView = 0; gBarmojiFeedback = 0; }
