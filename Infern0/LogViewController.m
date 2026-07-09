//
//  LogViewController.m
//  Cyanide
//

#import "LogViewController.h"
#import "LogTextView.h"
#import <sys/utsname.h>

@interface LogViewController ()
@property (nonatomic, strong) UILabel *bannerLabel;
@property (nonatomic, strong) LogTextView *logView;
@end

@implementation LogViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Log";
    UIColor *bg = [UIColor colorWithRed:0.04 green:0.05 blue:0.07 alpha:1.0];
    self.view.backgroundColor = bg;

    _bannerLabel = [[UILabel alloc] init];
    _bannerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _bannerLabel.numberOfLines = 0;
    _bannerLabel.font = [UIFont monospacedSystemFontOfSize:11.5 weight:UIFontWeightRegular];
    _bannerLabel.textColor = [UIColor colorWithWhite:0.86 alpha:1.0];
    _bannerLabel.backgroundColor = [UIColor colorWithRed:0.06 green:0.07 blue:0.10 alpha:1.0];
    _bannerLabel.textAlignment = NSTextAlignmentLeft;
    _bannerLabel.attributedText = [self buildBannerText];
    _bannerLabel.layer.cornerRadius = 10;
    _bannerLabel.clipsToBounds = YES;
    [self.view addSubview:_bannerLabel];

    UIView *separator = [[UIView alloc] init];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    separator.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.07];
    [self.view addSubview:separator];

    _logView = [[LogTextView alloc] initWithFrame:CGRectZero];
    _logView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_logView];

    [NSLayoutConstraint activateConstraints:@[
        [_bannerLabel.topAnchor      constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
        [_bannerLabel.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [_bannerLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],

        [separator.topAnchor      constraintEqualToAnchor:_bannerLabel.bottomAnchor constant:12],
        [separator.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor],
        [separator.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [separator.heightAnchor   constraintEqualToConstant:0.5],

        [_logView.topAnchor      constraintEqualToAnchor:separator.bottomAnchor],
        [_logView.bottomAnchor   constraintEqualToAnchor:self.view.bottomAnchor],
        [_logView.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor],
        [_logView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
}

- (NSAttributedString *)buildBannerText {
    NSBundle *b = [NSBundle mainBundle];
    NSDictionary *info = b.infoDictionary;
    NSString *shortVer = info[@"CFBundleShortVersionString"] ?: @"?";
    NSString *build = info[@"CFBundleVersion"] ?: @"?";

    struct utsname u = {0};
    const char *machine = "device";
    if (uname(&u) == 0 && u.machine[0])
        machine = u.machine;
    NSString *ios = UIDevice.currentDevice.systemVersion ?: @"?";

    NSString *banner = [NSString stringWithFormat:
        @"     ╭───────────╮\n"
        @"     │ ▄▄▄▄▄▄▄▄▄ │\n"
        @"     ├───────────┤\n"
        @"     │ ░░░░░░░░░ │   C Y A N I D E\n"
        @"     │ ░░░ C ░░░ │   %@ (%@)\n"
        @"     │ ░░░░░░░░░ │   %s • iOS %@\n"
        @"     │ ░░░░░░░░░ │\n"
        @"     ╰───────────╯",
        shortVer, build, machine, ios];

    NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
    para.lineSpacing = 2.0;

    return [[NSAttributedString alloc] initWithString:banner attributes:@{
        NSFontAttributeName: [UIFont monospacedSystemFontOfSize:11.5 weight:UIFontWeightRegular],
        NSForegroundColorAttributeName: [UIColor colorWithWhite:0.86 alpha:1.0],
        NSParagraphStyleAttributeName: para,
    }];
}

@end
