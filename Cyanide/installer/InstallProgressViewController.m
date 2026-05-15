//
//  InstallProgressViewController.m
//  Cyanide
//

#import "InstallProgressViewController.h"
#import "PackageQueue.h"
#import "QueueReviewViewController.h"
#import "../SettingsViewController.h"
#import "../LogTextView.h"

@interface InstallProgressViewController ()
@property (nonatomic, strong) LogTextView *logView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIBarButtonItem *hideOrDoneButton;
@property (nonatomic, assign) BOOL completed;
@end

@implementation InstallProgressViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = [UIColor colorWithRed:0.08 green:0.09 blue:0.16 alpha:1.0];
    self.title = @"Activity";
    self.modalInPresentation = NO; // user can swipe to dismiss any time

    self.logView = [[LogTextView alloc] initWithFrame:CGRectZero];
    self.logView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.logView];

    UIView *footer = [[UIView alloc] init];
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    footer.backgroundColor = [UIColor colorWithRed:0.05 green:0.06 blue:0.11 alpha:1.0];
    [self.view addSubview:footer];

    UIView *divider = [[UIView alloc] init];
    divider.translatesAutoresizingMaskIntoConstraints = NO;
    divider.backgroundColor = [UIColor.whiteColor colorWithAlphaComponent:0.08];
    [footer addSubview:divider];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.color = UIColor.whiteColor;
    [self.spinner startAnimating];
    [footer addSubview:self.spinner];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.text = @"Running — close any time, this keeps going in the background.";
    self.statusLabel.font = [UIFont systemFontOfSize:13.0];
    self.statusLabel.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.72];
    self.statusLabel.numberOfLines = 1;
    self.statusLabel.adjustsFontSizeToFitWidth = YES;
    self.statusLabel.minimumScaleFactor = 0.8;
    [footer addSubview:self.statusLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.logView.topAnchor      constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.logView.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor],
        [self.logView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.logView.bottomAnchor   constraintEqualToAnchor:footer.topAnchor],

        [footer.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor],
        [footer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [footer.bottomAnchor   constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [footer.heightAnchor   constraintEqualToConstant:54.0],

        [divider.topAnchor      constraintEqualToAnchor:footer.topAnchor],
        [divider.leadingAnchor  constraintEqualToAnchor:footer.leadingAnchor],
        [divider.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor],
        [divider.heightAnchor   constraintEqualToConstant:0.5],

        [self.spinner.leadingAnchor      constraintEqualToAnchor:footer.leadingAnchor constant:16.0],
        [self.spinner.centerYAnchor      constraintEqualToAnchor:footer.centerYAnchor],
        [self.statusLabel.leadingAnchor  constraintEqualToAnchor:self.spinner.trailingAnchor constant:12.0],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor constant:-16.0],
        [self.statusLabel.centerYAnchor  constraintEqualToAnchor:footer.centerYAnchor],
    ]];

    self.hideOrDoneButton = [[UIBarButtonItem alloc] initWithTitle:@"Hide"
                                                             style:UIBarButtonItemStylePlain
                                                            target:self
                                                            action:@selector(didTapDone)];
    self.navigationItem.rightBarButtonItem = self.hideOrDoneButton;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didReceiveCompleteNotification:)
                                                 name:kSettingsActionsDidCompleteNotification
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)didReceiveCompleteNotification:(NSNotification *)note
{
    if (self.completed) return;
    self.completed = YES;
    [self.spinner stopAnimating];
    self.spinner.hidden = YES;
    self.statusLabel.text = @"Done. All tweaks applied in-session.";
    self.statusLabel.textColor = [UIColor colorWithRed:0.45 green:0.85 blue:0.55 alpha:1.0];
    self.title = @"Complete";
    self.hideOrDoneButton.title = @"Done";
}

- (void)didTapDone
{
    UIViewController *presenter = self.presentingViewController;
    UINavigationController *nav = [presenter isKindOfClass:UINavigationController.class]
        ? (UINavigationController *)presenter
        : presenter.navigationController;
    [self dismissViewControllerAnimated:YES completion:^{
        if (!nav) return;
        // Pop any QueueReview screens off the stack so the user lands back
        // on the package list (or wherever they were before queueing).
        NSMutableArray<__kindof UIViewController *> *stack = [nav.viewControllers mutableCopy];
        NSInteger removed = 0;
        for (NSInteger i = (NSInteger)stack.count - 1; i >= 0; i--) {
            if ([stack[i] isKindOfClass:QueueReviewViewController.class]) {
                [stack removeObjectAtIndex:i];
                removed++;
            }
        }
        if (removed > 0) {
            [nav setViewControllers:stack animated:YES];
        }
    }];
}

@end
