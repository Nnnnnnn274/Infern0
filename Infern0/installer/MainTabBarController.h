//
//  MainTabBarController.h
//  Cyanide
//
//  Hosts the QueuePopupBar above the system tab bar and routes the tap to
//  push the queue-review screen onto the active tab's nav stack.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CYMainTabDestination) {
    CYMainTabDestinationHome = 700,
    CYMainTabDestinationPackages,
    CYMainTabDestinationTools,
    CYMainTabDestinationActivity,
    CYMainTabDestinationSettings,
};

@interface MainTabBarController : UITabBarController
- (void)showRefreshBanner;
- (void)showQueueReview;
- (BOOL)selectTab:(CYMainTabDestination)destination;
- (BOOL)showViewController:(UIViewController *)viewController
                     inTab:(CYMainTabDestination)destination
                  animated:(BOOL)animated;
@end

NS_ASSUME_NONNULL_END
