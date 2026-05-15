//
//  PackageDetailViewController.h
//  Cyanide
//
//  Installer-style detail page for a single package.
//

#import <UIKit/UIKit.h>
#import "Package.h"

NS_ASSUME_NONNULL_BEGIN

@interface PackageDetailViewController : UITableViewController

- (instancetype)initWithPackage:(Package *)package NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithStyle:(UITableViewStyle)style NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
