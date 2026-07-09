#import "barmoji.h"
#import "../remote_objc.h"
#import "../../TaskRop/RemoteCall.h"

#import <Foundation/Foundation.h>

typedef struct {
    double x;
    double y;
    double width;
    double height;
} BarmojiRect;

static uint64_t gBarmojiView = 0;
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

static uint64_t barmoji_key_window(void)
{
    uint64_t UIApplication = r_class("UIApplication");
    if (!r_is_objc_ptr(UIApplication)) return 0;
    uint64_t app = r_msg2_main(UIApplication, "sharedApplication", 0, 0, 0, 0);
    if (!r_is_objc_ptr(app)) return 0;

    uint64_t windows = r_msg2_main(app, "windows", 0, 0, 0, 0);
    if (r_is_objc_ptr(windows)) {
        uint64_t count = r_msg2_main(windows, "count", 0, 0, 0, 0);
        if (count > 64) count = 64;
        for (uint64_t i = 0; i < count; i++) {
            uint64_t win = r_msg2_main(windows, "objectAtIndex:", i, 0, 0, 0);
            if (!r_is_objc_ptr(win)) continue;
            uint64_t isKey = r_msg2_main(win, "isKeyWindow", 0, 0, 0, 0);
            if (isKey & 0xff) return win;
        }
    }
    return r_msg2_main(app, "keyWindow", 0, 0, 0, 0);
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

static uint64_t barmoji_alloc_label(const char *text, double x, double y, double w, double h, double fontSize)
{
    uint64_t UILabel = r_class("UILabel");
    if (!r_is_objc_ptr(UILabel)) return 0;
    uint64_t label = r_msg2_main(UILabel, "alloc", 0, 0, 0, 0);
    if (!r_is_objc_ptr(label)) return 0;
    BarmojiRect frame = { x, y, w, h };
    label = r_msg2_main_raw(label, "initWithFrame:", &frame, sizeof(frame), NULL, 0, NULL, 0, NULL, 0);
    if (!r_is_objc_ptr(label)) return 0;

    uint64_t str = r_nsstr_retained(text ?: "");
    if (r_is_objc_ptr(str)) {
        r_msg2_main(label, "setText:", str, 0, 0, 0);
        r_msg2_main(str, "release", 0, 0, 0, 0);
    }

    uint64_t UIFont = r_class("UIFont");
    if (r_is_objc_ptr(UIFont)) {
        double weight = 0.4;
        uint64_t font = r_msg2_main_raw(UIFont, "systemFontOfSize:weight:",
                                        &fontSize, sizeof(fontSize),
                                        &weight, sizeof(weight),
                                        NULL, 0, NULL, 0);
        if (r_is_objc_ptr(font)) r_msg2_main(label, "setFont:", font, 0, 0, 0);
    }
    r_msg2_main(label, "setTextAlignment:", 1, 0, 0, 0);
    return label;
}

bool barmoji_apply_in_session(void)
{
    printf("[BARMOJI] apply\n");
    if (r_is_objc_ptr(gBarmojiView)) {
        r_msg2_main(gBarmojiView, "removeFromSuperview", 0, 0, 0, 0);
        gBarmojiView = 0;
    }

    uint64_t win = barmoji_key_window();
    if (!r_is_objc_ptr(win)) return false;
    BarmojiRect bounds = barmoji_bounds_for_view(win);
    double barWidth = bounds.width * ((double)gBarmojiWidthPercent / 100.0);
    if (barWidth > 390.0) barWidth = 390.0;
    if (barWidth < 260.0) barWidth = 260.0;
    double barX = (bounds.width - barWidth) / 2.0;
    double barY = bounds.height - (double)gBarmojiYOffset;
    uint64_t bar = barmoji_alloc_view(barX, barY, barWidth, 38);
    if (!r_is_objc_ptr(bar)) return false;

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

    const char *emojiStrip =
        "\xF0\x9F\x98\x80  "
        "\xF0\x9F\x98\x82  "
        "\xE2\x9D\xA4\xEF\xB8\x8F  "
        "\xF0\x9F\x91\x8D  "
        "\xF0\x9F\x99\x8F  "
        "\xF0\x9F\x94\xA5  "
        "\xF0\x9F\x98\xAD  "
        "\xE2\x9C\xA8";
    uint64_t label = barmoji_alloc_label(emojiStrip, 8, 2, barWidth - 16.0, 34, (double)gBarmojiFontSize);
    if (r_is_objc_ptr(label)) {
        uint64_t white = barmoji_color(1, 1, 1, 1);
        if (r_is_objc_ptr(white)) r_msg2_main(label, "setTextColor:", white, 0, 0, 0);
        r_msg2_main(bar, "addSubview:", label, 0, 0, 0);
    }

    r_msg2_main(win, "addSubview:", bar, 0, 0, 0);
    gBarmojiView = bar;
    return true;
}

bool barmoji_stop_in_session(void)
{
    printf("[BARMOJI] stop\n");
    if (r_is_objc_ptr(gBarmojiView)) r_msg2_main(gBarmojiView, "removeFromSuperview", 0, 0, 0, 0);
    gBarmojiView = 0;
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

void barmoji_forget_remote_state(void) { gBarmojiView = 0; }
