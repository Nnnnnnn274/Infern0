//
//  CYIconBadge.m
//  Cyanide
//

#import "CYIconBadge.h"

UIImage *CYIconBadgeImage(NSString *sfSymbol, UIColor *color, CGFloat size)
{
    UIGraphicsImageRendererFormat *fmt = [[UIGraphicsImageRendererFormat alloc] init];
    fmt.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size, size) format:fmt];

    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [[color colorWithAlphaComponent:0.14] setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, size, size)] fill];

        UIImageSymbolConfiguration *symCfg = [UIImageSymbolConfiguration
            configurationWithPointSize:size * 0.42 weight:UIImageSymbolWeightSemibold];
        UIImage *sym = [[UIImage systemImageNamed:sfSymbol withConfiguration:symCfg]
            imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal];
        if (!sym) return;

        CGSize symSize = [sym size];
        CGFloat x = (size - symSize.width) / 2.0;
        CGFloat y = (size - symSize.height) / 2.0;
        [sym drawInRect:CGRectMake(x, y, symSize.width, symSize.height)];
    }];
}

UIView *CYSectionHeaderView(NSString *title)
{
    UILabel *lbl = [[UILabel alloc] init];
    lbl.text = title;
    lbl.font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightBold];
    lbl.textColor = UIColor.labelColor;

    CGSize size = [lbl sizeThatFits:CGSizeMake(UIScreen.mainScreen.bounds.size.width - 40.0, CGFLOAT_MAX)];
    CGFloat height = 16.0 + ceil(size.height) + 6.0;

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, UIScreen.mainScreen.bounds.size.width, height)];
    lbl.frame = CGRectMake(20.0, 16.0, container.bounds.size.width - 40.0, ceil(size.height));
    lbl.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [container addSubview:lbl];

    return container;
}
