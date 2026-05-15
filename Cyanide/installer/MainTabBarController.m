//
//  MainTabBarController.m
//  Cyanide
//

#import "MainTabBarController.h"
#import "QueuePopupBar.h"
#import "QueueReviewViewController.h"
#import "PackageQueue.h"

static const CGFloat kPopupHeight  = 56.0;
static const CGFloat kPopupGap     = 8.0;
static const CGFloat kPopupPadding = 2.0;

@interface MainTabBarController ()
@property (nonatomic, strong) QueuePopupBar *popupBar;
@end

@implementation MainTabBarController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.popupBar = [[QueuePopupBar alloc] initWithFrame:CGRectZero];
    self.popupBar.translatesAutoresizingMaskIntoConstraints = NO;
    __weak typeof(self) weakSelf = self;
    self.popupBar.onTap = ^{ [weakSelf showQueueReview]; };
    [self.view addSubview:self.popupBar];

    [NSLayoutConstraint activateConstraints:@[
        [self.popupBar.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor  constant:12.0],
        [self.popupBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12.0],
        [self.popupBar.bottomAnchor   constraintEqualToAnchor:self.tabBar.topAnchor    constant:-kPopupGap],
        [self.popupBar.heightAnchor   constraintEqualToConstant:kPopupHeight],
    ]];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(queueDidChange:)
                                                 name:PackageQueueDidChangeNotification
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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
