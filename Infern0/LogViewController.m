//
//  LogViewController.m
//  Cyanide
//

#import "LogViewController.h"
#import "LogTextView.h"
#import "installer/CYIconBadge.h"
#import <sys/utsname.h>

@interface LogViewController () <UISearchResultsUpdating>
@property (nonatomic, strong) UIView *bannerView;
@property (nonatomic, strong) UILabel *bannerLabel;
@property (nonatomic, strong) LogTextView *logView;
@property (nonatomic, strong) UISegmentedControl *filterControl;
@end

@implementation LogViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    BOOL classicStyle = CYUsesClassicInterfaceStyle();
    self.title = @"Activity";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.view.backgroundColor = CYCanvasColor();
    CYApplyNavigationStyle(self.navigationController);
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.arrow.up"]
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self
                                                                             action:@selector(shareActivity)];
    self.navigationItem.rightBarButtonItem.accessibilityLabel = @"Share activity log";
    UISearchController *search = [[UISearchController alloc] initWithSearchResultsController:nil];
    search.searchResultsUpdater = self;
    search.obscuresBackgroundDuringPresentation = NO;
    search.searchBar.placeholder = @"Search activity";
    self.navigationItem.searchController = search;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;

    self.bannerView = [[UIView alloc] init];
    self.bannerView.translatesAutoresizingMaskIntoConstraints = NO;
    CYApplyCardStyle(self.bannerView, 20.0);
    self.bannerView.clipsToBounds = YES;
    [self.view addSubview:self.bannerView];

    UIView *accent = [[UIView alloc] init];
    accent.translatesAutoresizingMaskIntoConstraints = NO;
    accent.backgroundColor = CYAccentColor();
    accent.hidden = classicStyle;
    [self.bannerView addSubview:accent];

    UIImageView *activityIcon = [[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:@"waveform.path.ecg"
               withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:19.0
                                                                                  weight:UIImageSymbolWeightSemibold]]];
    activityIcon.translatesAutoresizingMaskIntoConstraints = NO;
    activityIcon.tintColor = CYAccentColor();
    activityIcon.backgroundColor = [CYAccentColor() colorWithAlphaComponent:0.13];
    activityIcon.contentMode = UIViewContentModeCenter;
    activityIcon.layer.cornerRadius = 15.0;
    activityIcon.layer.cornerCurve = kCACornerCurveContinuous;
    activityIcon.hidden = classicStyle;
    [self.bannerView addSubview:activityIcon];

    UILabel *eyebrow = [[UILabel alloc] init];
    eyebrow.translatesAutoresizingMaskIntoConstraints = NO;
    eyebrow.text = @"●  LIVE ACTIVITY";
    eyebrow.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightHeavy];
    eyebrow.textColor = CYAccentColor();
    eyebrow.hidden = classicStyle;
    [self.bannerView addSubview:eyebrow];

    _bannerLabel = [[UILabel alloc] init];
    _bannerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _bannerLabel.numberOfLines = 0;
    _bannerLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    _bannerLabel.adjustsFontForContentSizeCategory = YES;
    _bannerLabel.textColor = UIColor.labelColor;
    _bannerLabel.textAlignment = classicStyle ? NSTextAlignmentCenter : NSTextAlignmentLeft;
    _bannerLabel.attributedText = [self buildBannerText];
    [self.bannerView addSubview:_bannerLabel];

    self.filterControl = [[UISegmentedControl alloc] initWithItems:@[@"All", @"Warnings", @"Errors"]];
    self.filterControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.filterControl.selectedSegmentIndex = 0;
    CYConfigureSegmentedControl(self.filterControl);
    [self.filterControl addTarget:self action:@selector(filterChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.filterControl];

    UIView *separator = [[UIView alloc] init];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    separator.backgroundColor = UIColor.separatorColor;
    [self.view addSubview:separator];

    _logView = [[LogTextView alloc] initWithFrame:CGRectZero];
    _logView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_logView];

    [NSLayoutConstraint activateConstraints:@[
        [self.bannerView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:10],
        [self.bannerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.bannerView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.bannerView.heightAnchor constraintGreaterThanOrEqualToConstant:(classicStyle ? 76 : 104)],

        [accent.leadingAnchor constraintEqualToAnchor:self.bannerView.leadingAnchor],
        [accent.topAnchor constraintEqualToAnchor:self.bannerView.topAnchor],
        [accent.bottomAnchor constraintEqualToAnchor:self.bannerView.bottomAnchor],
        [accent.widthAnchor constraintEqualToConstant:4.0],

        [activityIcon.leadingAnchor constraintEqualToAnchor:self.bannerView.leadingAnchor constant:18],
        [activityIcon.centerYAnchor constraintEqualToAnchor:self.bannerView.centerYAnchor],
        [activityIcon.widthAnchor constraintEqualToConstant:44],
        [activityIcon.heightAnchor constraintEqualToConstant:44],

        [eyebrow.leadingAnchor constraintEqualToAnchor:activityIcon.trailingAnchor constant:14],
        [eyebrow.topAnchor constraintEqualToAnchor:self.bannerView.topAnchor constant:18],
        [eyebrow.trailingAnchor constraintLessThanOrEqualToAnchor:self.bannerView.trailingAnchor constant:-16],

        [_bannerLabel.leadingAnchor constraintEqualToAnchor:(classicStyle ? self.bannerView.leadingAnchor : eyebrow.leadingAnchor)
                                                   constant:(classicStyle ? 16 : 0)],
        [_bannerLabel.topAnchor constraintEqualToAnchor:(classicStyle ? self.bannerView.topAnchor : eyebrow.bottomAnchor)
                                               constant:(classicStyle ? 14 : 5)],
        [_bannerLabel.trailingAnchor constraintEqualToAnchor:self.bannerView.trailingAnchor constant:-16],
        [_bannerLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.bannerView.bottomAnchor constant:-16],

        [self.filterControl.topAnchor constraintEqualToAnchor:self.bannerView.bottomAnchor constant:10],
        [self.filterControl.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.filterControl.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.filterControl.heightAnchor constraintEqualToConstant:34],

        [separator.topAnchor      constraintEqualToAnchor:self.filterControl.bottomAnchor constant:10],
        [separator.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor],
        [separator.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [separator.heightAnchor   constraintEqualToConstant:0.5],

        [_logView.topAnchor      constraintEqualToAnchor:separator.bottomAnchor],
        [_logView.bottomAnchor   constraintEqualToAnchor:self.view.bottomAnchor],
        [_logView.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor],
        [_logView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
    CYAnimateEntrance(self.bannerView);
}

- (void)filterChanged:(UISegmentedControl *)sender
{
    CYSelectionHaptic();
    [self.logView setLogSeverityFilter:sender.selectedSegmentIndex];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController
{
    [self.logView setLogFilterText:searchController.searchBar.text];
}

- (void)shareActivity
{
    NSString *snapshot = log_inapp_buffer_snapshot();
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[snapshot.length ? snapshot : @"No Infern0 activity yet."] applicationActivities:nil];
    activity.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:activity animated:YES completion:nil];
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

    BOOL classicStyle = CYUsesClassicInterfaceStyle();
    NSString *banner = classicStyle
        ? [NSString stringWithFormat:@"● LIVE ACTIVITY\nInfern0 %@ (%@) · %s · iOS %@\nDetailed operations, warnings, and recovery information appear below.",
                                     shortVer, build, machine, ios]
        : [NSString stringWithFormat:@"Infern0 %@ (%@)  •  %s  •  iOS %@\nOperations, warnings, and recovery details appear below.",
                                     shortVer, build, machine, ios];

    NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
    para.lineSpacing = 3.0;
    para.alignment = classicStyle ? NSTextAlignmentCenter : NSTextAlignmentLeft;

    return [[NSAttributedString alloc] initWithString:banner attributes:@{
        NSFontAttributeName: [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline],
        NSForegroundColorAttributeName: UIColor.labelColor,
        NSParagraphStyleAttributeName: para,
    }];
}

@end
