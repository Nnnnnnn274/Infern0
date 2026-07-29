//
//  CYIconBadge.m
//  Cyanide
//

#import "CYIconBadge.h"
#import <objc/runtime.h>

static const void *kCYPolishedButtonKey = &kCYPolishedButtonKey;
static const void *kCYButtonSurfaceKey = &kCYButtonSurfaceKey;
static const void *kCYEntranceAnimatedKey = &kCYEntranceAnimatedKey;

@interface CYInteractionDriver : NSObject
@end

@implementation CYInteractionDriver

+ (UIView *)surfaceForButton:(UIButton *)button
{
    NSValue *value = objc_getAssociatedObject(button, kCYButtonSurfaceKey);
    return value.nonretainedObjectValue ?: button;
}

+ (void)pressBegan:(UIButton *)button
{
    UIView *surface = [self surfaceForButton:button];
    [UIView animateWithDuration:0.12 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut animations:^{
        surface.transform = CGAffineTransformMakeScale(0.975, 0.975);
        surface.alpha = 0.88;
    } completion:nil];
}

+ (void)pressEnded:(UIButton *)button
{
    UIView *surface = [self surfaceForButton:button];
    [UIView animateWithDuration:0.36 delay:0 usingSpringWithDamping:0.72 initialSpringVelocity:0.4 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        surface.transform = CGAffineTransformIdentity;
        surface.alpha = 1.0;
    } completion:nil];
}

+ (void)pressCommitted:(UIButton *)button
{
    [self pressEnded:button];
    CYSelectionHaptic();
}

@end

NSString * const CYInterfaceStyleDefaultsKey = @"CYInterfaceStyle";

BOOL CYUsesClassicInterfaceStyle(void)
{
    return [[NSUserDefaults standardUserDefaults] integerForKey:CYInterfaceStyleDefaultsKey] == 1;
}

BOOL CYUsesMidnightInterfaceStyle(void)
{
    return [[NSUserDefaults standardUserDefaults] integerForKey:CYInterfaceStyleDefaultsKey] == 2;
}

BOOL CYUsesFr0stInterfaceStyle(void)
{
    return [[NSUserDefaults standardUserDefaults] integerForKey:CYInterfaceStyleDefaultsKey] == 3;
}

BOOL CYUsesMinecraftInterfaceStyle(void)
{
    return [[NSUserDefaults standardUserDefaults] integerForKey:CYInterfaceStyleDefaultsKey] == 4;
}

NSArray *CYHeroGradientLayerColors(void)
{
    if (CYUsesClassicInterfaceStyle()) {
        return @[
            (id)[UIColor colorWithRed:0.16 green:0.055 blue:0.035 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:0.52 green:0.080 blue:0.050 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:1.00 green:0.340 blue:0.120 alpha:1.0].CGColor,
        ];
    }
    if (CYUsesMidnightInterfaceStyle()) {
        return @[
            (id)[UIColor colorWithRed:0.035 green:0.020 blue:0.040 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:0.145 green:0.050 blue:0.105 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:0.350 green:0.120 blue:0.245 alpha:1.0].CGColor,
        ];
    }
    if (CYUsesFr0stInterfaceStyle()) {
        return @[
            (id)[UIColor colorWithRed:0.018 green:0.055 blue:0.105 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:0.035 green:0.220 blue:0.440 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:0.210 green:0.610 blue:0.880 alpha:1.0].CGColor,
        ];
    }
    if (CYUsesMinecraftInterfaceStyle()) {
        return @[
            (id)[UIColor colorWithRed:0.035 green:0.090 blue:0.040 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:0.120 green:0.310 blue:0.100 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:0.390 green:0.600 blue:0.190 alpha:1.0].CGColor,
        ];
    }
    return @[
        (id)[UIColor colorWithRed:0.12 green:0.035 blue:0.055 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.34 green:0.070 blue:0.105 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.62 green:0.180 blue:0.215 alpha:1.0].CGColor,
    ];
}

UIColor *CYAccentColor(void)
{
    if (CYUsesClassicInterfaceStyle()) {
        return [UIColor colorWithRed:1.0 green:0.29 blue:0.10 alpha:1.0];
    }
    if (CYUsesMidnightInterfaceStyle()) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            return traits.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithRed:0.82 green:0.42 blue:0.62 alpha:1.0]
                : [UIColor colorWithRed:0.52 green:0.18 blue:0.38 alpha:1.0];
        }];
    }
    if (CYUsesFr0stInterfaceStyle()) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            return traits.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithRed:0.38 green:0.72 blue:0.98 alpha:1.0]
                : [UIColor colorWithRed:0.04 green:0.39 blue:0.72 alpha:1.0];
        }];
    }
    if (CYUsesMinecraftInterfaceStyle()) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            return traits.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithRed:0.53 green:0.76 blue:0.29 alpha:1.0]
                : [UIColor colorWithRed:0.25 green:0.52 blue:0.12 alpha:1.0];
        }];
    }
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:0.88 green:0.40 blue:0.44 alpha:1.0]
            : [UIColor colorWithRed:0.70 green:0.22 blue:0.28 alpha:1.0];
    }];
}

UIColor *CYCanvasColor(void)
{
    if (CYUsesClassicInterfaceStyle()) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            return traits.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithRed:0.035 green:0.028 blue:0.026 alpha:1.0]
                : [UIColor colorWithRed:0.975 green:0.965 blue:0.955 alpha:1.0];
        }];
    }
    if (CYUsesMidnightInterfaceStyle()) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            return traits.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithRed:0.020 green:0.016 blue:0.024 alpha:1.0]
                : [UIColor colorWithRed:0.965 green:0.950 blue:0.960 alpha:1.0];
        }];
    }
    if (CYUsesFr0stInterfaceStyle()) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            return traits.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithRed:0.014 green:0.030 blue:0.052 alpha:1.0]
                : [UIColor colorWithRed:0.952 green:0.975 blue:0.990 alpha:1.0];
        }];
    }
    if (CYUsesMinecraftInterfaceStyle()) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            return traits.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithRed:0.026 green:0.040 blue:0.025 alpha:1.0]
                : [UIColor colorWithRed:0.955 green:0.950 blue:0.905 alpha:1.0];
        }];
    }
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:0.033 green:0.027 blue:0.029 alpha:1.0]
            : [UIColor colorWithRed:0.978 green:0.969 blue:0.968 alpha:1.0];
    }];
}

UIColor *CYSurfaceColor(void)
{
    if (CYUsesClassicInterfaceStyle()) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            return traits.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithRed:0.095 green:0.080 blue:0.074 alpha:0.96]
                : [UIColor colorWithWhite:1.0 alpha:0.92];
        }];
    }
    if (CYUsesMidnightInterfaceStyle()) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            return traits.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithRed:0.070 green:0.052 blue:0.072 alpha:0.97]
                : [UIColor colorWithRed:0.995 green:0.982 blue:0.990 alpha:0.95];
        }];
    }
    if (CYUsesFr0stInterfaceStyle()) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            return traits.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithRed:0.040 green:0.085 blue:0.135 alpha:0.97]
                : [UIColor colorWithRed:0.980 green:0.993 blue:1.000 alpha:0.95];
        }];
    }
    if (CYUsesMinecraftInterfaceStyle()) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            return traits.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithRed:0.075 green:0.105 blue:0.068 alpha:0.98]
                : [UIColor colorWithRed:0.985 green:0.975 blue:0.925 alpha:0.96];
        }];
    }
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:0.090 green:0.075 blue:0.079 alpha:0.96]
            : [UIColor colorWithWhite:1.0 alpha:0.94];
    }];
}

UIColor *CYSurfaceBorderColor(void)
{
    if (CYUsesClassicInterfaceStyle()) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            return traits.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithWhite:1.0 alpha:0.09]
                : [UIColor colorWithRed:0.40 green:0.20 blue:0.12 alpha:0.10];
        }];
    }
    if (CYUsesMidnightInterfaceStyle()) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            return traits.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithRed:0.78 green:0.42 blue:0.62 alpha:0.13]
                : [UIColor colorWithRed:0.34 green:0.10 blue:0.25 alpha:0.12];
        }];
    }
    if (CYUsesFr0stInterfaceStyle()) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            return traits.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithRed:0.35 green:0.70 blue:1.00 alpha:0.15]
                : [UIColor colorWithRed:0.03 green:0.30 blue:0.58 alpha:0.12];
        }];
    }
    if (CYUsesMinecraftInterfaceStyle()) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            return traits.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithRed:0.43 green:0.31 blue:0.20 alpha:0.34]
                : [UIColor colorWithRed:0.34 green:0.23 blue:0.12 alpha:0.22];
        }];
    }
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:1.0 alpha:0.09]
            : [UIColor colorWithRed:0.36 green:0.15 blue:0.18 alpha:0.09];
    }];
}

void CYApplyCardStyle(UIView *view, CGFloat cornerRadius)
{
    view.backgroundColor = CYSurfaceColor();
    view.layer.cornerRadius = CYUsesMinecraftInterfaceStyle() ? MIN(cornerRadius, 8.0) : cornerRadius;
    view.layer.cornerCurve = CYUsesMinecraftInterfaceStyle() ? kCACornerCurveCircular : kCACornerCurveContinuous;
    view.layer.borderWidth = CYUsesMinecraftInterfaceStyle() ? 1.0 : 1.0 / UIScreen.mainScreen.scale;
    view.layer.borderColor = CYSurfaceBorderColor().CGColor;
    view.layer.shadowColor = UIColor.blackColor.CGColor;
    view.layer.shadowOpacity = CYUsesMinecraftInterfaceStyle() ? 0.16 : 0.08;
    view.layer.shadowRadius = CYUsesMinecraftInterfaceStyle() ? 3.0 : 14.0;
    view.layer.shadowOffset = CYUsesMinecraftInterfaceStyle() ? CGSizeMake(0.0, 3.0) : CGSizeMake(0.0, 6.0);
}

void CYConfigureTableView(UITableView *tableView)
{
    tableView.backgroundColor = CYCanvasColor();
    tableView.separatorColor = [UIColor.separatorColor colorWithAlphaComponent:0.42];
    tableView.sectionHeaderHeight = UITableViewAutomaticDimension;
    tableView.estimatedSectionHeaderHeight = 38.0;
    tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    tableView.delaysContentTouches = NO;
    tableView.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(0.0, 18.0, 0.0, 18.0);
    if (@available(iOS 15.0, *)) tableView.sectionHeaderTopPadding = 4.0;
}

void CYConfigureSegmentedControl(UISegmentedControl *control)
{
    if (!control) return;
    control.selectedSegmentTintColor = CYAccentColor();
    control.backgroundColor = [CYSurfaceColor() colorWithAlphaComponent:0.72];
    control.layer.cornerCurve = CYUsesMinecraftInterfaceStyle() ? kCACornerCurveCircular : kCACornerCurveContinuous;
    if (CYUsesMinecraftInterfaceStyle()) control.layer.cornerRadius = 6.0;
    [control setTitleTextAttributes:@{
        NSForegroundColorAttributeName: UIColor.secondaryLabelColor,
        NSFontAttributeName: [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold],
    } forState:UIControlStateNormal];
    [control setTitleTextAttributes:@{
        NSForegroundColorAttributeName: UIColor.whiteColor,
        NSFontAttributeName: [UIFont systemFontOfSize:12.0 weight:UIFontWeightBold],
    } forState:UIControlStateSelected];
}

void CYPolishButton(UIButton *button)
{
    CYPolishOverlayButton(button, button);
}

void CYPolishOverlayButton(UIButton *button, UIView *surface)
{
    if (!button || objc_getAssociatedObject(button, kCYPolishedButtonKey)) return;
    objc_setAssociatedObject(button, kCYPolishedButtonKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (surface && surface != button) {
        objc_setAssociatedObject(button, kCYButtonSurfaceKey,
                                 [NSValue valueWithNonretainedObject:surface],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [button addTarget:CYInteractionDriver.class action:@selector(pressBegan:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [button addTarget:CYInteractionDriver.class action:@selector(pressEnded:) forControlEvents:UIControlEventTouchCancel | UIControlEventTouchDragExit | UIControlEventTouchUpOutside];
    [button addTarget:CYInteractionDriver.class action:@selector(pressCommitted:) forControlEvents:UIControlEventTouchUpInside];
}

void CYSelectionHaptic(void)
{
    UISelectionFeedbackGenerator *generator = [[UISelectionFeedbackGenerator alloc] init];
    [generator prepare];
    [generator selectionChanged];
}

void CYSuccessHaptic(void)
{
    UINotificationFeedbackGenerator *generator = [[UINotificationFeedbackGenerator alloc] init];
    [generator prepare];
    [generator notificationOccurred:UINotificationFeedbackTypeSuccess];
}

void CYAnimateEntrance(UIView *view)
{
    if (!view || UIAccessibilityIsReduceMotionEnabled() || objc_getAssociatedObject(view, kCYEntranceAnimatedKey)) return;
    objc_setAssociatedObject(view, kCYEntranceAnimatedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.alpha = 0.0;
    view.transform = CGAffineTransformMakeTranslation(0.0, 10.0);
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.48 delay:0.04 usingSpringWithDamping:0.86 initialSpringVelocity:0.15 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
            view.alpha = 1.0;
            view.transform = CGAffineTransformIdentity;
        } completion:nil];
    });
}

void CYApplyNavigationStyle(UINavigationController *navigationController)
{
    if (!navigationController) return;
    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithTransparentBackground];
    appearance.backgroundEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];
    appearance.backgroundColor = [CYCanvasColor() colorWithAlphaComponent:0.72];
    appearance.shadowColor = UIColor.clearColor;
    appearance.titleTextAttributes = @{
        NSFontAttributeName: [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold],
        NSForegroundColorAttributeName: UIColor.labelColor,
    };
    appearance.largeTitleTextAttributes = @{
        NSFontAttributeName: [UIFont systemFontOfSize:34.0 weight:UIFontWeightBold],
        NSForegroundColorAttributeName: UIColor.labelColor,
    };
    UINavigationBar *bar = navigationController.navigationBar;
    bar.standardAppearance = appearance;
    bar.scrollEdgeAppearance = appearance;
    bar.compactAppearance = appearance;
    bar.tintColor = CYAccentColor();
}

void CYApplyTabBarStyle(UITabBar *tabBar)
{
    UITabBarAppearance *appearance = [[UITabBarAppearance alloc] init];
    [appearance configureWithTransparentBackground];
    appearance.backgroundEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];
    appearance.backgroundColor = [CYSurfaceColor() colorWithAlphaComponent:0.82];
    appearance.shadowColor = CYSurfaceBorderColor();
    NSArray<UITabBarItemAppearance *> *layouts = @[
        appearance.stackedLayoutAppearance,
        appearance.inlineLayoutAppearance,
        appearance.compactInlineLayoutAppearance,
    ];
    for (UITabBarItemAppearance *items in layouts) {
        items.selected.iconColor = CYAccentColor();
        items.selected.titleTextAttributes = @{
            NSForegroundColorAttributeName: CYAccentColor(),
            NSFontAttributeName: [UIFont systemFontOfSize:10.0 weight:UIFontWeightSemibold],
        };
        items.normal.iconColor = UIColor.secondaryLabelColor;
        items.normal.titleTextAttributes = @{
            NSForegroundColorAttributeName: UIColor.secondaryLabelColor,
        };
    }
    tabBar.standardAppearance = appearance;
    tabBar.scrollEdgeAppearance = appearance;
    tabBar.tintColor = CYAccentColor();
}

UIImage *CYIconBadgeImage(NSString *sfSymbol, UIColor *color, CGFloat size)
{
    UIGraphicsImageRendererFormat *fmt = [[UIGraphicsImageRendererFormat alloc] init];
    fmt.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size, size) format:fmt];

    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGRect badgeRect = CGRectInset(CGRectMake(0, 0, size, size), 0.5, 0.5);
        CGFloat badgeRadius = size * (CYUsesMinecraftInterfaceStyle() ? 0.10 : 0.30);
        UIBezierPath *badge = [UIBezierPath bezierPathWithRoundedRect:badgeRect cornerRadius:badgeRadius];
        [[color colorWithAlphaComponent:0.13] setFill];
        [badge fill];
        [[color colorWithAlphaComponent:0.22] setStroke];
        badge.lineWidth = 1.0;
        [badge stroke];

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

UIColor *CYSpectrumColor(NSUInteger index)
{
    static NSArray<UIColor *> *colors;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        colors = @[
            UIColor.systemRedColor,
            UIColor.systemTealColor,
            UIColor.systemGreenColor,
            UIColor.systemOrangeColor,
            UIColor.systemPinkColor,
            UIColor.systemPurpleColor,
            UIColor.systemIndigoColor,
            UIColor.systemOrangeColor,
            UIColor.systemRedColor,
            UIColor.systemMintColor,
        ];
    });
    return colors[index % colors.count];
}

UIView *CYSectionHeaderView(NSString *title)
{
    UIView *container = [[UIView alloc] init];

    UILabel *lbl = [[UILabel alloc] init];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    lbl.text = title;
    lbl.text = title.uppercaseString;
    lbl.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightHeavy];
    lbl.textColor = CYAccentColor();
    lbl.adjustsFontForContentSizeCategory = YES;
    [container addSubview:lbl];

    [NSLayoutConstraint activateConstraints:@[
        [lbl.leadingAnchor  constraintEqualToAnchor:container.leadingAnchor constant:20.0],
        [lbl.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor constant:-20.0],
        [lbl.topAnchor      constraintEqualToAnchor:container.topAnchor constant:14.0],
        [lbl.bottomAnchor   constraintEqualToAnchor:container.bottomAnchor constant:-5.0],
    ]];

    return container;
}
