//
//  LogViewController.m
//  Cyanide
//

#import "LogViewController.h"
#import "LogTextView.h"

@interface LogViewController ()
@property (nonatomic, strong) LogTextView *logView;
@end

@implementation LogViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Log";
    self.view.backgroundColor = [UIColor colorWithRed:0.02 green:0.05 blue:0.06 alpha:1.0];

    _logView = [[LogTextView alloc] initWithFrame:CGRectZero];
    _logView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_logView];

    [NSLayoutConstraint activateConstraints:@[
        [_logView.topAnchor      constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_logView.bottomAnchor   constraintEqualToAnchor:self.view.bottomAnchor],
        [_logView.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor],
        [_logView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
}

@end
