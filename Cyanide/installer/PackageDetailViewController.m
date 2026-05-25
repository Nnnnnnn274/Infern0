//
//  PackageDetailViewController.m
//  Cyanide
//

#import "PackageDetailViewController.h"
#import "PackageQueue.h"
#import "../LogTextView.h"
#import "../SettingsViewController.h"


typedef NS_ENUM(NSInteger, PackageDetailSection) {
    PackageDetailSectionWarning = 0,
    PackageDetailSectionInfo,
    PackageDetailSectionAction,
    PackageDetailSectionSettings,
    PackageDetailSectionDescription,
    PackageDetailSectionCount,
};

@interface PackageDetailViewController ()
@property (nonatomic, strong) Package *package;
@property (nonatomic, copy)   NSArray<NSArray<NSString *> *> *infoRows;       // [[label, value], ...]
@property (nonatomic, copy)   NSArray<NSNumber *> *visibleSections;            // ordered PackageDetailSection values
@property (nonatomic, copy)   NSArray<NSDictionary<NSString *, NSString *> *> *settingsSummary;
@end

@implementation PackageDetailViewController

- (BOOL)isOTAPackage
{
    return self.package.kind == PackageInstallKindOTA;
}

// "Manual-control" packages are stateless from the Installer's POV: the user
// just queues an install or uninstall intent and confirms. OTA and the
// NanoRegistry override both fit. The detail view shows a menu instead of a
// toggle button so the user sees both options.
- (BOOL)isManualPackage
{
    return self.package.kind == PackageInstallKindOTA
        || self.package.kind == PackageInstallKindNanoRegistry;
}

- (NSString *)manualActionTitleForIntent:(PackageQueueIntent)intent
{
    if (intent != PackageQueueIntentNone) {
        if (self.package.kind == PackageInstallKindNanoRegistry) {
            return (intent == PackageQueueIntentInstall) ? @"Cancel Apply" : @"Cancel Remove";
        }
        return (intent == PackageQueueIntentInstall) ? @"Cancel Disable" : @"Cancel Enable";
    }
    if (self.package.kind == PackageInstallKindNanoRegistry) return @"Apply/Remove";
    return @"Disable/Enable";
}

- (NSString *)manualStateText
{
    PackageQueueIntent intent = [[PackageQueue sharedQueue] intentForPackage:self.package];
    if (self.package.kind == PackageInstallKindNanoRegistry) {
        if (intent == PackageQueueIntentInstall) return @"Apply Queued";
        if (intent == PackageQueueIntentUninstall) return @"Remove Queued";
        return @"Manual Control";
    }
    if (intent == PackageQueueIntentInstall) return @"Disable Queued";
    if (intent == PackageQueueIntentUninstall) return @"Enable Queued";
    return @"Manual Control";
}

- (UIColor *)manualStateColor
{
    PackageQueueIntent intent = [[PackageQueue sharedQueue] intentForPackage:self.package];
    if (intent != PackageQueueIntentNone) return self.view.tintColor;
    return UIColor.secondaryLabelColor;
}

- (NSArray<NSArray<NSString *> *> *)currentInfoRows
{
    if (![self isManualPackage]) return self.infoRows;
    NSMutableArray<NSArray<NSString *> *> *rows = [self.infoRows mutableCopy];
    [rows addObject:@[@"State", [self manualStateText]]];
    return rows;
}

- (void)queueManualIntent:(PackageQueueIntent)intent
{
    if (self.package.kind == PackageInstallKindNanoRegistry) {
        log_user("[INSTALLER] Queued watch-pairing %s\n",
                 intent == PackageQueueIntentInstall ? "apply" : "remove");
    } else {
        log_user("[INSTALLER] Queued OTA %s\n",
                 intent == PackageQueueIntentInstall ? "disable" : "enable");
    }
    [[PackageQueue sharedQueue] queueIntent:intent forPackage:self.package];
}

- (UIMenu *)manualActionMenu
{
    if (self.package.kind == PackageInstallKindNanoRegistry) {
        UIAction *apply = [UIAction actionWithTitle:@"Apply Pairing Override"
                                              image:[UIImage systemImageNamed:@"applewatch.radiowaves.left.and.right"]
                                         identifier:nil
                                            handler:^(__kindof UIAction *_) {
            [self queueManualIntent:PackageQueueIntentInstall];
        }];

        UIAction *remove = [UIAction actionWithTitle:@"Remove Pairing Override"
                                               image:[UIImage systemImageNamed:@"xmark.circle"]
                                          identifier:nil
                                             handler:^(__kindof UIAction *_) {
            [self queueManualIntent:PackageQueueIntentUninstall];
        }];
        remove.attributes = UIMenuElementAttributesDestructive;

        return [UIMenu menuWithTitle:@"Watch Pairing Override" children:@[apply, remove]];
    }

    UIAction *disable = [UIAction actionWithTitle:@"Disable OTA Updates"
                                            image:[UIImage systemImageNamed:@"icloud.slash"]
                                       identifier:nil
                                          handler:^(__kindof UIAction *_) {
        [self queueManualIntent:PackageQueueIntentInstall];
    }];
    disable.attributes = UIMenuElementAttributesDestructive;

    UIAction *enable = [UIAction actionWithTitle:@"Enable OTA Updates"
                                           image:[UIImage systemImageNamed:@"icloud"]
                                      identifier:nil
                                         handler:^(__kindof UIAction *_) {
        [self queueManualIntent:PackageQueueIntentUninstall];
    }];

    return [UIMenu menuWithTitle:@"OTA Updates" children:@[disable, enable]];
}

- (instancetype)initWithPackage:(Package *)package
{
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _package = package;
        _infoRows = @[
            @[@"Name",     package.name],
            @[@"Version",  package.version],
            @[@"Author",   package.author],
            @[@"Category", package.category],
        ];
        NSMutableArray<NSNumber *> *sections = [NSMutableArray array];
        if (package.unstableWarning.length > 0) {
            [sections addObject:@(PackageDetailSectionWarning)];
        }
        [sections addObject:@(PackageDetailSectionDescription)];
        _settingsSummary = [SettingsViewController settingsSummaryForSection:package.settingsSection];
        if (_settingsSummary.count > 0) {
            [sections addObject:@(PackageDetailSectionSettings)];
        }
        if (package.settingsSection != NSIntegerMax && !package.isInstallDisabled) {
            [sections addObject:@(PackageDetailSectionAction)];
        }
        [sections addObject:@(PackageDetailSectionInfo)];
        _visibleSections = sections;
    }
    return self;
}

- (PackageDetailSection)sectionAtIndex:(NSInteger)index
{
    return (PackageDetailSection)[self.visibleSections[index] integerValue];
}

- (BOOL)hasSettingsBundle
{
    return self.package.settingsSection != NSIntegerMax;
}

- (BOOL)requiresThemeSelection
{
    return [self.package.identifier isEqualToString:@"com.darksword.themer"];
}

- (BOOL)needsThemeBeforeInstall
{
    return [self requiresThemeSelection] &&
           !self.package.isInstalled &&
           !settings_themer_has_selected_theme();
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = self.package.name;
    self.tableView.tableHeaderView = [self buildHeaderView];
    [self updateActionButton];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(queueDidChange:)
                                                 name:PackageQueueDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(queueDidChange:)
                                                 name:kSettingsActionsDidCompleteNotification
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.settingsSummary = [SettingsViewController settingsSummaryForSection:self.package.settingsSection];
    self.tableView.tableHeaderView = [self buildHeaderView];
    [self.tableView reloadData];
    [self updateActionButton];
}

- (void)queueDidChange:(NSNotification *)note
{
    if (!self.isViewLoaded) return;
    self.tableView.tableHeaderView = [self buildHeaderView];
    [self.tableView reloadData];
    [self updateActionButton];
}

#pragma mark - Header

- (UIView *)buildHeaderView
{
    CGFloat width = self.view.bounds.size.width;
    UIView *header = [[UIView alloc] init];
    header.backgroundColor = UIColor.clearColor;

    // Icon
    UIImageView *iconView = [[UIImageView alloc] init];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.image = [UIImage systemImageNamed:self.package.symbolName];
    iconView.preferredSymbolConfiguration =
        [UIImageSymbolConfiguration configurationWithPointSize:48.0 weight:UIImageSymbolWeightRegular];
    iconView.tintColor = self.view.tintColor;
    [header addSubview:iconView];

    // Name
    UILabel *nameLabel = [[UILabel alloc] init];
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    nameLabel.text = self.package.name;
    nameLabel.font = [UIFont systemFontOfSize:22.0 weight:UIFontWeightBold];
    nameLabel.textColor = UIColor.labelColor;
    nameLabel.textAlignment = NSTextAlignmentCenter;
    [header addSubview:nameLabel];

    // Subtitle: Category · Version
    UILabel *subLabel = [[UILabel alloc] init];
    subLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subLabel.text = [NSString stringWithFormat:@"%@  ·  Version %@", self.package.category, self.package.version];
    subLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular];
    subLabel.textColor = UIColor.secondaryLabelColor;
    subLabel.textAlignment = NSTextAlignmentCenter;
    [header addSubview:subLabel];

    // Status badge (optional)
    UIView *badge = nil;
    if ([self isManualPackage]) {
        UIColor *color = [self manualStateColor];
        badge = [self badgeWithText:[self manualStateText].uppercaseString
                         background:[color colorWithAlphaComponent:0.16]
                          textColor:color];
    } else if (self.package.experimental) {
        badge = [self badgeWithText:@"EXPERIMENTAL"
                         background:[UIColor.systemRedColor colorWithAlphaComponent:0.16]
                          textColor:UIColor.systemRedColor];
    } else if (self.package.isInstallDisabled) {
        badge = [self badgeWithText:@"DISABLED"
                         background:[UIColor.systemRedColor colorWithAlphaComponent:0.16]
                          textColor:UIColor.systemRedColor];
    } else if (self.package.isNew) {
        badge = [self badgeWithText:@"NEW"
                         background:[UIColor colorWithRed:0.95 green:0.55 blue:0.05 alpha:0.18]
                          textColor:[UIColor systemOrangeColor]];
    }
    if (badge) {
        badge.translatesAutoresizingMaskIntoConstraints = NO;
        [header addSubview:badge];
    }

    NSMutableArray<NSLayoutConstraint *> *cs = [NSMutableArray array];
    [cs addObjectsFromArray:@[
        [iconView.topAnchor      constraintEqualToAnchor:header.topAnchor constant:10.0],
        [iconView.centerXAnchor  constraintEqualToAnchor:header.centerXAnchor],
        [iconView.widthAnchor    constraintEqualToConstant:60.0],
        [iconView.heightAnchor   constraintEqualToConstant:54.0],

        [nameLabel.topAnchor      constraintEqualToAnchor:iconView.bottomAnchor constant:8.0],
        [nameLabel.leadingAnchor  constraintEqualToAnchor:header.leadingAnchor constant:16.0],
        [nameLabel.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16.0],

        [subLabel.topAnchor       constraintEqualToAnchor:nameLabel.bottomAnchor constant:3.0],
        [subLabel.leadingAnchor   constraintEqualToAnchor:header.leadingAnchor constant:16.0],
        [subLabel.trailingAnchor  constraintEqualToAnchor:header.trailingAnchor constant:-16.0],
    ]];

    // Anchor the *last* element to the bottom so the header self-sizes. Bumped
    // the sub→badge gap from 6→12 and the badge→bottom gap to 14 so the pill
    // gets clear breathing room above and below (it was clipping the
    // description box below before).
    if (badge) {
        [cs addObjectsFromArray:@[
            [badge.topAnchor       constraintEqualToAnchor:subLabel.bottomAnchor constant:12.0],
            [badge.centerXAnchor   constraintEqualToAnchor:header.centerXAnchor],
            [badge.bottomAnchor    constraintEqualToAnchor:header.bottomAnchor constant:-14.0],
        ]];
    } else {
        [cs addObject:[subLabel.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-12.0]];
    }
    [NSLayoutConstraint activateConstraints:cs];

    // tableHeaderView needs an explicit frame — auto layout inside it doesn't
    // size the slot. Ask the view for its natural height at the table's width.
    CGSize fit = [header systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                       withHorizontalFittingPriority:UILayoutPriorityRequired
                             verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    header.frame = CGRectMake(0, 0, width, fit.height);
    return header;
}

- (UIView *)badgeWithText:(NSString *)text background:(UIColor *)bg textColor:(UIColor *)fg
{
    UILabel *pill = [[UILabel alloc] init];
    pill.text = [NSString stringWithFormat:@"  %@  ", text];
    pill.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightHeavy];
    pill.textColor = fg;
    pill.backgroundColor = bg;
    pill.textAlignment = NSTextAlignmentCenter;
    [pill sizeToFit];

    CGRect frame = pill.frame;
    frame.size.height = 22.0;
    pill.frame = frame;
    pill.layer.cornerRadius = frame.size.height / 2.0;
    pill.layer.masksToBounds = YES;
    return pill;
}

#pragma mark - Action button

- (void)updateActionButton
{
    PackageQueueIntent intent = [[PackageQueue sharedQueue] intentForPackage:self.package];
    BOOL installed = self.package.isInstalled;
    BOOL manual = [self isManualPackage];

    NSString *title;
    UIBarButtonItemStyle style = UIBarButtonItemStylePlain;
    UIColor *tint = nil;
    if (manual) {
        title = [self manualActionTitleForIntent:intent];
        tint = (intent != PackageQueueIntentNone)
            ? UIColor.secondaryLabelColor
            : self.view.tintColor;
        if (intent == PackageQueueIntentNone) style = UIBarButtonItemStyleDone;
    } else if (intent != PackageQueueIntentNone) {
        title = @"Queued";
        tint = UIColor.secondaryLabelColor;
    } else if (installed) {
        title = @"Uninstall";
        tint = UIColor.systemRedColor;
    } else if (self.package.isInstallDisabled) {
        title = @"Disabled";
        tint = UIColor.secondaryLabelColor;
    } else if ([self needsThemeBeforeInstall]) {
        title = @"Select Theme";
        style = UIBarButtonItemStyleDone;
    } else {
        title = @"Install";
        style = UIBarButtonItemStyleDone;
    }

    BOOL useMenu = manual && intent == PackageQueueIntentNone;
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithTitle:title
                                                             style:style
                                                            target:useMenu ? nil : self
                                                            action:useMenu ? nil : @selector(didTapAction)];
    if (useMenu) {
        item.menu = [self manualActionMenu];
    }
    if (tint) item.tintColor = tint;
    item.enabled = !self.package.isInstallDisabled || installed || intent != PackageQueueIntentNone;
    self.navigationItem.rightBarButtonItem = item;
}

- (void)didTapAction
{
    PackageQueueIntent intent = [[PackageQueue sharedQueue] intentForPackage:self.package];
    if (intent != PackageQueueIntentNone) {
        log_user("[INSTALLER] Removed %s from queue\n", self.package.name.UTF8String);
        [[PackageQueue sharedQueue] removePackage:self.package];
        return;
    }
    if (self.package.isInstallDisabled && !self.package.isInstalled) {
        log_user("[INSTALLER] %s is disabled for now: %s\n",
                 self.package.name.UTF8String,
                 self.package.installDisabledReason.UTF8String);
        return;
    }
    if ([self needsThemeBeforeInstall]) {
        [self promptSelectThemeBeforeInstall];
        return;
    }
    if (NO && !self.package.isInstalled && [self hasSettingsBundle]) {
        [self promptConfigureBeforeInstall];
        return;
    }
    // Manual packages dispatch via menu — didTapAction should never run for
    // them when intent == None (the bar item carries a UIMenu instead of a
    // selector target).
    if ([self isManualPackage]) {
        return;
    } else if (self.package.isInstalled) {
        log_user("[INSTALLER] Queued uninstall: %s\n", self.package.name.UTF8String);
    } else {
        log_user("[INSTALLER] Queued install: %s\n", self.package.name.UTF8String);
    }
    [[PackageQueue sharedQueue] toggleForPackage:self.package];
}

- (void)promptSelectThemeBeforeInstall
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Select a Theme"
                                                                   message:@"Cyanide Themer needs a selected theme before it can be queued. Choose iOS 6 Theme or import a custom theme first."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Open Theme Settings"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *_) {
        [self navigateToSettingsSection];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                             style:UIAlertActionStyleCancel
                                           handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)promptConfigureBeforeInstall
{
    NSString *msg = [NSString stringWithFormat:
        @"%@ has configurable options. Set them up first so the tweak applies with your preferences on the first run.",
        self.package.name];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Customize Before Installing?"
                                                                   message:msg
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Configure First"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *_) {
        [self navigateToSettingsSection];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Install Anyway"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *_) {
        log_user("[INSTALLER] Queued install: %s\n", self.package.name.UTF8String);
        [[PackageQueue sharedQueue] toggleForPackage:self.package];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                             style:UIAlertActionStyleCancel
                                           handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return (NSInteger)self.visibleSections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch ([self sectionAtIndex:section]) {
        case PackageDetailSectionWarning:     return 1;
        case PackageDetailSectionInfo:        return (NSInteger)[self currentInfoRows].count;
        case PackageDetailSectionAction:      return 1;
        case PackageDetailSectionSettings:    return (NSInteger)self.settingsSummary.count;
        case PackageDetailSectionDescription: return 1;
        case PackageDetailSectionCount:       return 0;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch ([self sectionAtIndex:section]) {
        case PackageDetailSectionWarning:     return nil;
        case PackageDetailSectionInfo:        return @"Information";
        case PackageDetailSectionAction:      return @"Configure";
        case PackageDetailSectionSettings:    return @"Current Settings";
        case PackageDetailSectionDescription: return @"Description";
        case PackageDetailSectionCount:       return nil;
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if ([self sectionAtIndex:section] == PackageDetailSectionAction) {
        return @"Settings can be changed any time — before or after install. Configuring before install is best so the tweak applies with your options on the very next run.";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    switch ([self sectionAtIndex:indexPath.section]) {
        case PackageDetailSectionWarning: {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"WarningCell"];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                              reuseIdentifier:@"WarningCell"];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            }
            // Wipe any previous subviews from cell reuse before rebuilding.
            for (UIView *v in [cell.contentView.subviews copy]) [v removeFromSuperview];
            cell.textLabel.text   = nil;
            cell.imageView.image  = nil;
            cell.backgroundColor  = [UIColor.systemRedColor colorWithAlphaComponent:0.14];

            UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"exclamationmark.triangle.fill"]];
            icon.translatesAutoresizingMaskIntoConstraints = NO;
            icon.tintColor = UIColor.systemRedColor;
            icon.preferredSymbolConfiguration =
                [UIImageSymbolConfiguration configurationWithPointSize:20.0 weight:UIImageSymbolWeightSemibold];
            [icon setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
            [icon setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
            [cell.contentView addSubview:icon];

            UILabel *label = [[UILabel alloc] init];
            label.translatesAutoresizingMaskIntoConstraints = NO;
            label.text = self.package.unstableWarning;
            label.textColor = UIColor.systemRedColor;
            label.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
            label.numberOfLines = 0;
            [cell.contentView addSubview:label];

            UILayoutGuide *m = cell.contentView.layoutMarginsGuide;
            [NSLayoutConstraint activateConstraints:@[
                [icon.leadingAnchor    constraintEqualToAnchor:m.leadingAnchor],
                [icon.topAnchor        constraintEqualToAnchor:m.topAnchor constant:2.0],
                [icon.widthAnchor      constraintEqualToConstant:22.0],

                [label.leadingAnchor   constraintEqualToAnchor:icon.trailingAnchor constant:10.0],
                [label.trailingAnchor  constraintEqualToAnchor:m.trailingAnchor],
                [label.topAnchor       constraintEqualToAnchor:m.topAnchor],
                [label.bottomAnchor    constraintEqualToAnchor:m.bottomAnchor],
            ]];
            return cell;
        }
        case PackageDetailSectionInfo: {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"InfoCell"];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                              reuseIdentifier:@"InfoCell"];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            }
            NSArray<NSArray<NSString *> *> *rows = [self currentInfoRows];
            NSArray<NSString *> *row = indexPath.row < (NSInteger)rows.count ? rows[indexPath.row] : @[];
            NSString *label = row.count > 0 ? row[0] : @"";
            NSString *value = row.count > 1 ? row[1] : @"";
            cell.textLabel.text = label;
            cell.detailTextLabel.text = value;
            cell.detailTextLabel.textColor = ([self isManualPackage] && [label isEqualToString:@"State"])
                ? [self manualStateColor]
                : UIColor.secondaryLabelColor;
            cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
            return cell;
        }
        case PackageDetailSectionDescription: {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DescCell"];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                              reuseIdentifier:@"DescCell"];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                cell.textLabel.numberOfLines = 0;
                cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
                cell.textLabel.textColor = UIColor.labelColor;
            }
            cell.textLabel.text = self.package.longDescription;
            return cell;
        }
        case PackageDetailSectionSettings: {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SettingsSummaryCell"];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                              reuseIdentifier:@"SettingsSummaryCell"];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
            }
            NSDictionary *row = self.settingsSummary[indexPath.row];
            cell.textLabel.text = row[@"title"];
            cell.detailTextLabel.text = row[@"value"];
            return cell;
        }
        case PackageDetailSectionAction: {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ActionCell"];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                              reuseIdentifier:@"ActionCell"];
            }
            cell.textLabel.text = [NSString stringWithFormat:@"Customize %@", self.package.name];
            cell.textLabel.textColor = self.view.tintColor;
            cell.textLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
            cell.detailTextLabel.text = @"Adjust options in the Settings tab";
            cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
            cell.imageView.image = [UIImage systemImageNamed:@"slider.horizontal.3"];
            cell.imageView.tintColor = self.view.tintColor;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }
        case PackageDetailSectionCount:
            break;
    }
    return [[UITableViewCell alloc] init];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ([self sectionAtIndex:indexPath.section] != PackageDetailSectionAction) return;
    if (![self hasSettingsBundle]) return;
    [self navigateToSettingsSection];
}

- (void)navigateToSettingsSection
{
    UITabBarController *tab = self.tabBarController;
    NSUInteger settingsIndex = NSNotFound;
    UINavigationController *settingsNav = nil;
    for (NSUInteger i = 0; i < tab.viewControllers.count; i++) {
        UIViewController *vc = tab.viewControllers[i];
        if ([vc.tabBarItem.title isEqualToString:@"Settings"]) {
            settingsIndex = i;
            if ([vc isKindOfClass:UINavigationController.class]) {
                settingsNav = (UINavigationController *)vc;
            }
            break;
        }
    }
    if (settingsIndex == NSNotFound || !settingsNav) return;

    [settingsNav popToRootViewControllerAnimated:NO];
    SettingsViewController *bundle = [[SettingsViewController alloc] initWithUnderlyingSection:self.package.settingsSection
                                                                                   bundleTitle:self.package.name];
    bundle.installerReturnPackageName = self.package.name;
    [settingsNav pushViewController:bundle animated:NO];
    tab.selectedIndex = settingsIndex;
}

@end
