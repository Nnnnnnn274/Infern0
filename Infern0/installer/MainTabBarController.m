//
//  MainTabBarController.m
//  Cyanide
//

#import "MainTabBarController.h"
#import "QueuePopupBar.h"
#import "QueueReviewViewController.h"
#import "PackageQueue.h"
#import "HomeViewController.h"
#import "ToolsViewController.h"
#import "CYIconBadge.h"
#import "../SettingsViewController.h"

static const CGFloat kPopupHeight  = 56.0;
static const CGFloat kPopupGap     = 8.0;
static const CGFloat kPopupPadding = 2.0;

@interface MainTabBarController () <UITabBarControllerDelegate>
@property (nonatomic, strong) QueuePopupBar *popupBar;
@property (nonatomic, copy) NSArray<NSLayoutConstraint *> *popupBarConstraints;
@end

@implementation MainTabBarController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.delegate = self;

    self.view.tintColor = CYAccentColor();
    self.tabBar.tintColor = CYAccentColor();
    self.tabBar.unselectedItemTintColor = UIColor.secondaryLabelColor;
    CYApplyTabBarStyle(self.tabBar);

    [self installPrimaryTabsIfNeeded];

    self.popupBar = [[QueuePopupBar alloc] initWithFrame:CGRectZero];
    self.popupBar.translatesAutoresizingMaskIntoConstraints = NO;
    __weak typeof(self) weakSelf = self;
    self.popupBar.onTap = ^{ [weakSelf showQueueReview]; };
    [self.view addSubview:self.popupBar];

    [self installPopupBarConstraintsIfReady];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(queueDidChange:)
                                                 name:PackageQueueDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(queueDidChange:)
                                                 name:kSettingsActionsDidCompleteNotification
                                               object:nil];
}

- (void)tabBarController:(UITabBarController *)tabBarController didSelectViewController:(UIViewController *)viewController
{
    (void)tabBarController;
    (void)viewController;
    CYSelectionHaptic();
}

- (void)installPrimaryTabsIfNeeded
{
    NSMutableArray<UIViewController *> *controllers = [self.viewControllers mutableCopy];
    if (controllers.count == 0) return;
    BOOL classicStyle = CYUsesClassicInterfaceStyle();

    UIViewController *packages = controllers.firstObject;
    packages.tabBarItem.title = @"Packages";
    packages.tabBarItem.image = [UIImage systemImageNamed:(classicStyle ? @"shippingbox.fill" : @"shippingbox")];
    packages.tabBarItem.selectedImage = [UIImage systemImageNamed:@"shippingbox.fill"];
    if ([packages isKindOfClass:UINavigationController.class]) {
        UINavigationController *nav = (UINavigationController *)packages;
        nav.tabBarItem.title = @"Packages";
        nav.topViewController.title = @"Packages";
        nav.topViewController.navigationItem.title = @"Packages";
    }

    // Inject Home tab at position 0 if not already present.
    BOOL hasHome = NO;
    for (UIViewController *vc in controllers) {
        if ([vc.tabBarItem.title isEqualToString:@"Home"]) { hasHome = YES; break; }
    }
    if (!hasHome) {
        HomeViewController *home = [[HomeViewController alloc] init];
        UINavigationController *homeNav = [[UINavigationController alloc] initWithRootViewController:home];
        homeNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Home"
                                                           image:[UIImage systemImageNamed:(classicStyle ? @"house.fill" : @"house")]
                                                             tag:0];
        homeNav.tabBarItem.selectedImage = [UIImage systemImageNamed:@"house.fill"];
        [controllers insertObject:homeNav atIndex:0];
    }

    BOOL hasTools = NO;
    for (UIViewController *vc in controllers) {
        if ([vc.tabBarItem.title isEqualToString:@"Tools"]) { hasTools = YES; break; }
    }
    if (!hasTools) {
        ToolsViewController *tools = [[ToolsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        UINavigationController *toolsNav = [[UINavigationController alloc] initWithRootViewController:tools];
        toolsNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Tools"
                                                            image:[UIImage systemImageNamed:(classicStyle ? @"wrench.and.screwdriver.fill" : @"wrench.and.screwdriver")]
                                                              tag:0];
        toolsNav.tabBarItem.selectedImage = [UIImage systemImageNamed:@"wrench.and.screwdriver.fill"];
        NSUInteger packagesIndex = [controllers indexOfObject:packages];
        NSUInteger insertionIndex = packagesIndex == NSNotFound ? MIN((NSUInteger)2, controllers.count) : packagesIndex + 1;
        [controllers insertObject:toolsNav atIndex:insertionIndex];
    }


    for (UIViewController *vc in controllers) {
        if ([vc.tabBarItem.title isEqualToString:@"Settings"]) {
            vc.tabBarItem.image = [UIImage systemImageNamed:(classicStyle ? @"gear" : @"gearshape")];
            vc.tabBarItem.selectedImage = [UIImage systemImageNamed:@"gearshape.fill"];
        }
        if ([vc.tabBarItem.title isEqualToString:@"Log"]) {
            vc.tabBarItem.title = @"Activity";
            vc.tabBarItem.image = [UIImage systemImageNamed:@"waveform.path.ecg"];
            vc.tabBarItem.selectedImage = [UIImage systemImageNamed:@"waveform.path.ecg.rectangle.fill"];
            UINavigationController *nav = [vc isKindOfClass:UINavigationController.class] ? (UINavigationController *)vc : nil;
            nav.topViewController.title = @"Activity";
        }
    }

    for (UIViewController *vc in controllers) {
        NSString *title = vc.tabBarItem.title;
        if ([title isEqualToString:@"Home"]) vc.tabBarItem.tag = CYMainTabDestinationHome;
        else if ([title isEqualToString:@"Packages"]) vc.tabBarItem.tag = CYMainTabDestinationPackages;
        else if ([title isEqualToString:@"Tools"]) vc.tabBarItem.tag = CYMainTabDestinationTools;
        else if ([title isEqualToString:@"Activity"]) vc.tabBarItem.tag = CYMainTabDestinationActivity;
        else if ([title isEqualToString:@"Settings"]) vc.tabBarItem.tag = CYMainTabDestinationSettings;
    }

    [self setViewControllers:controllers animated:NO];
    for (UIViewController *controller in controllers) {
        if ([controller isKindOfClass:UINavigationController.class]) {
            CYApplyNavigationStyle((UINavigationController *)controller);
        }
    }
    self.selectedIndex = 0;
}

- (NSInteger)indexOfTab:(CYMainTabDestination)destination
{
    for (NSInteger index = 0; index < (NSInteger)self.viewControllers.count; index++) {
        if (self.viewControllers[index].tabBarItem.tag == destination) return index;
    }
    return NSNotFound;
}

- (BOOL)selectTab:(CYMainTabDestination)destination
{
    NSInteger index = [self indexOfTab:destination];
    if (index == NSNotFound) return NO;
    self.selectedIndex = index;
    return YES;
}

- (BOOL)showViewController:(UIViewController *)viewController
                     inTab:(CYMainTabDestination)destination
                  animated:(BOOL)animated
{
    if (!viewController) return NO;
    NSInteger index = [self indexOfTab:destination];
    if (index == NSNotFound) return NO;

    UIViewController *root = self.viewControllers[index];
    UINavigationController *navigation = [root isKindOfClass:UINavigationController.class]
        ? (UINavigationController *)root
        : root.navigationController;
    if (!navigation) return NO;

    BOOL alreadySelected = self.selectedIndex == index;
    [navigation popToRootViewControllerAnimated:NO];
    [navigation pushViewController:viewController animated:(alreadySelected && animated)];
    self.selectedIndex = index;
    return YES;
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    [self installPopupBarConstraintsIfReady];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)view:(UIView *)view sharesHierarchyWithView:(UIView *)otherView
{
    if (!view || !otherView) return NO;
    for (UIView *ancestor = view; ancestor; ancestor = ancestor.superview) {
        if ([otherView isDescendantOfView:ancestor]) return YES;
    }
    return NO;
}

- (void)installPopupBarConstraintsIfReady
{
    if (self.popupBarConstraints.count > 0) return;

    NSLayoutYAxisAnchor *bottomAnchor = self.view.safeAreaLayoutGuide.bottomAnchor;
    CGFloat bottomConstant = -kPopupGap;
    if ([self view:self.popupBar sharesHierarchyWithView:self.tabBar]) {
        bottomAnchor = self.tabBar.topAnchor;
    }

    self.popupBarConstraints = @[
        [self.popupBar.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor  constant:12.0],
        [self.popupBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12.0],
        [self.popupBar.bottomAnchor   constraintEqualToAnchor:bottomAnchor constant:bottomConstant],
        [self.popupBar.heightAnchor   constraintEqualToConstant:kPopupHeight],
    ];
    [NSLayoutConstraint activateConstraints:self.popupBarConstraints];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self.popupBar refreshFromQueueAnimated:NO];
    [self refreshChildInsetsAnimated:NO];
}

- (void)setViewControllers:(NSArray<UIViewController *> *)viewControllers animated:(BOOL)animated
{
    [super setViewControllers:viewControllers animated:animated];
    [self refreshChildInsetsAnimated:NO];
}

#pragma mark - Popup inset propagation

- (void)queueDidChange:(NSNotification *)note
{
    [self refreshChildInsetsAnimated:YES];
}

- (void)refreshChildInsetsAnimated:(BOOL)animated
{
    BOOL visible = [PackageQueue sharedQueue].pendingCount > 0;
    UIEdgeInsets insets = UIEdgeInsetsZero;
    if (visible) {
        insets.bottom = kPopupHeight + kPopupGap + kPopupPadding;
    }
    void (^apply)(void) = ^{
        for (UIViewController *vc in self.viewControllers) {
            vc.additionalSafeAreaInsets = insets;
        }
    };
    if (animated) {
        [UIView animateWithDuration:0.25 animations:apply];
    } else {
        apply();
    }
}


- (void)showQueueReview
{
    UIViewController *selected = self.selectedViewController;
    UINavigationController *nav = [selected isKindOfClass:UINavigationController.class]
        ? (UINavigationController *)selected
        : selected.navigationController;
    if (!nav) return;

    // Don't re-push if it's already on top.
    if ([nav.topViewController isKindOfClass:QueueReviewViewController.class]) return;

    QueueReviewViewController *review = [[QueueReviewViewController alloc] init];
    [nav pushViewController:review animated:YES];
}

@end
