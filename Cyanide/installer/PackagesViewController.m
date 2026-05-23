//
//  PackagesViewController.m
//  Cyanide
//

#import "PackagesViewController.h"
#import "PackageCatalog.h"
#import "PackageDetailViewController.h"
#import "PackageQueue.h"
#import "../SettingsViewController.h"

static NSString * const kPackageCellID         = @"PackageCell";
static NSString * const kGroupByCategoryDefault = @"installer.groupByCategory";

@interface PackagesViewController () <UISearchResultsUpdating>
@property (nonatomic, copy)   NSArray<Package *> *allPackagesSorted;
@property (nonatomic, copy)   NSArray<Package *> *flatPackages;        // shown when !groupByCategory
@property (nonatomic, copy)   NSArray<NSString *> *visibleCategories;  // shown when groupByCategory
@property (nonatomic, copy)   NSDictionary<NSString *, NSArray<Package *> *> *packagesByCategory;
@property (nonatomic, copy)   NSString *searchText;
@property (nonatomic, assign) BOOL groupByCategory;
@property (nonatomic, strong) UISearchController *searchCtl;
@end

@implementation PackagesViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Installer";
    self.navigationItem.title = @"Installer";

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if (![ud objectForKey:kGroupByCategoryDefault]) {
        [ud setBool:YES forKey:kGroupByCategoryDefault];
    }
    self.groupByCategory = [ud boolForKey:kGroupByCategoryDefault];
    self.searchText = @"";

    self.allPackagesSorted = [[PackageCatalog allPackages]
        sortedArrayUsingComparator:^NSComparisonResult(Package *a, Package *b) {
            return [a.name caseInsensitiveCompare:b.name];
        }];

    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 68.0;
    self.tableView.sectionFooterHeight = 4.0;
    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 0.0;
    }

    // Search controller pinned in the nav bar so it shows above the table.
    self.searchCtl = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchCtl.searchResultsUpdater = self;
    self.searchCtl.obscuresBackgroundDuringPresentation = NO;
    self.searchCtl.searchBar.placeholder = @"Search tweaks";
    self.navigationItem.searchController = self.searchCtl;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;

    [self installSortBarButton];
    [self installTipsHeader];
    [self rebuildFilteredData];

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
    [self rebuildFilteredData];
    [self.tableView reloadData];
}

- (void)queueDidChange:(NSNotification *)note
{
    if (!self.isViewLoaded) return;
    [self.tableView reloadData];
}

#pragma mark - Sort menu

#pragma mark - Tips header

// Each entry becomes a row in the card: leading SF Symbol icon, then bold
// title + body text wrapping below. Order matters — top to bottom.
- (NSArray<NSDictionary *> *)tipsEntries
{
    return @[
        @{ @"icon":  @"bolt.fill",
           @"color": UIColor.systemYellowColor,
           @"title": @"Axon Lite — still beta",
           @"body":  @"Recent passes improved filter switching speed and fixed the duplicate-icon bug, but it's a beta and still has rough edges. Hit Contact below if you run into one." },
        @{ @"icon":  @"exclamationmark.triangle.fill",
           @"color": UIColor.systemOrangeColor,
           @"title": @"Don't force-quit Cyanide",
           @"body":  @"From the App Switcher kills live tweaks instantly — StatBar, Axon Lite, and anything else running per session stops the moment the app dies." },
        @{ @"icon":  @"envelope.fill",
           @"color": UIColor.systemBlueColor,
           @"title": @"Need specific help?",
           @"body":  @"Diagnostic log uploads are opt-in from Settings > About. Use the button below to reach me directly with your device info — tell me what you ran into." },
    ];
}

// Builds the icon + title/body subview for one tip row at a fixed width.
// Returns the row with its frame already sized to fit the text.
- (UIView *)buildTipRowWithIcon:(NSString *)iconName
                          color:(UIColor *)color
                          title:(NSString *)title
                           body:(NSString *)body
                          width:(CGFloat)width
{
    CGFloat iconSize  = 22.0;
    CGFloat iconGap   = 12.0;
    CGFloat textX     = iconSize + iconGap;
    CGFloat textWidth = width - textX;

    UIView *row = [[UIView alloc] init];

    UIImageSymbolConfiguration *symCfg =
        [UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightSemibold];
    UIImageView *icon = [[UIImageView alloc] initWithImage:
        [[UIImage systemImageNamed:iconName withConfiguration:symCfg]
            imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal]];
    icon.contentMode = UIViewContentModeCenter;
    icon.frame = CGRectMake(0, 1, iconSize, iconSize);
    [row addSubview:icon];

    NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
    para.lineSpacing = 1.5;

    NSMutableAttributedString *as = [[NSMutableAttributedString alloc] init];
    [as appendAttributedString:[[NSAttributedString alloc] initWithString:title attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold],
        NSForegroundColorAttributeName: UIColor.labelColor,
        NSParagraphStyleAttributeName: para,
    }]];
    [as appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold],
    }]];
    [as appendAttributedString:[[NSAttributedString alloc] initWithString:body attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightRegular],
        NSForegroundColorAttributeName: UIColor.secondaryLabelColor,
        NSParagraphStyleAttributeName: para,
    }]];

    UILabel *label = [[UILabel alloc] init];
    label.numberOfLines = 0;
    label.preferredMaxLayoutWidth = textWidth;
    label.attributedText = as;
    CGSize fit = [label sizeThatFits:CGSizeMake(textWidth, CGFLOAT_MAX)];
    label.frame = CGRectMake(textX, 0, textWidth, fit.height);
    [row addSubview:label];

    row.frame = CGRectMake(0, 0, width, MAX(fit.height, iconSize));
    return row;
}

- (void)installTipsHeader
{
    CGFloat width = self.tableView.bounds.size.width;
    if (width <= 0) width = UIScreen.mainScreen.bounds.size.width;

    CGFloat horizontalMargin = 16.0;
    CGFloat topPadding       = 14.0;
    CGFloat bottomPadding    = 0.0;     // section header below adds its own breathing room
    CGFloat cardInset        = 14.0;
    CGFloat contentWidth     = width - horizontalMargin * 2 - cardInset * 2;
    CGFloat rowGap           = 14.0;
    CGFloat headingGap       = 10.0;    // gap after heading
    CGFloat buttonGap        = 14.0;
    CGFloat buttonHeight     = 36.0;

    NSMutableArray<UIView *> *placed = [NSMutableArray array];
    CGFloat y = cardInset;

    // Heading: "What's New & Tips" with a sparkles glyph for some personality.
    UILabel *heading = [[UILabel alloc] init];
    heading.numberOfLines = 1;
    NSMutableAttributedString *headAS = [[NSMutableAttributedString alloc] init];
    NSTextAttachment *sparkle = [[NSTextAttachment alloc] init];
    UIImageSymbolConfiguration *headCfg =
        [UIImageSymbolConfiguration configurationWithPointSize:15.0 weight:UIImageSymbolWeightSemibold];
    sparkle.image = [[UIImage systemImageNamed:@"sparkles" withConfiguration:headCfg]
                        imageWithTintColor:UIColor.systemPurpleColor
                          renderingMode:UIImageRenderingModeAlwaysOriginal];
    [headAS appendAttributedString:[NSAttributedString attributedStringWithAttachment:sparkle]];
    [headAS appendAttributedString:[[NSAttributedString alloc] initWithString:@"  What's New & Tips" attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold],
        NSForegroundColorAttributeName: UIColor.labelColor,
    }]];
    heading.attributedText = headAS;
    CGSize headFit = [heading sizeThatFits:CGSizeMake(contentWidth, CGFLOAT_MAX)];
    heading.frame = CGRectMake(cardInset, y, contentWidth, headFit.height);
    [placed addObject:heading];
    y += headFit.height + headingGap;

    // Tip rows
    NSArray<NSDictionary *> *entries = [self tipsEntries];
    for (NSDictionary *entry in entries) {
        UIView *row = [self buildTipRowWithIcon:entry[@"icon"]
                                          color:entry[@"color"]
                                          title:entry[@"title"]
                                           body:entry[@"body"]
                                          width:contentWidth];
        CGRect f = row.frame;
        f.origin = CGPointMake(cardInset, y);
        row.frame = f;
        [placed addObject:row];
        y += f.size.height + rowGap;
    }
    y -= rowGap;        // last row didn't need trailing gap
    y += buttonGap;     // explicit gap before the button

    // Contact button
    UIButtonConfiguration *cfg = [UIButtonConfiguration tintedButtonConfiguration];
    cfg.title = @"Contact zeroxjf";
    cfg.image = [UIImage systemImageNamed:@"envelope.fill"];
    cfg.imagePadding = 6.0;
    cfg.imagePlacement = NSDirectionalRectEdgeLeading;
    cfg.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    __weak typeof(self) weakSelf = self;
    UIButton *contact = [UIButton buttonWithConfiguration:cfg
                                            primaryAction:[UIAction actionWithHandler:^(UIAction *_) {
        typeof(self) strongSelf = weakSelf;
        if (strongSelf) cyanide_present_contact(strongSelf);
    }]];
    contact.frame = CGRectMake(cardInset, y, contentWidth, buttonHeight);
    [placed addObject:contact];
    y += buttonHeight + cardInset;

    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(horizontalMargin,
                                                            topPadding,
                                                            width - horizontalMargin * 2,
                                                            y)];
    card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    card.layer.cornerRadius = 12.0;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    for (UIView *v in placed) [card addSubview:v];

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width,
                                                                 card.frame.size.height + topPadding + bottomPadding)];
    [container addSubview:card];

    self.tableView.tableHeaderView = container;
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    UIView *hdr = self.tableView.tableHeaderView;
    if (!hdr) return;
    // Re-fit on width changes (rotation, split view, etc.) by rebuilding the
    // header in place when the table's width no longer matches our cached size.
    if (fabs(hdr.frame.size.width - self.tableView.bounds.size.width) > 0.5) {
        [self installTipsHeader];
    }
}

- (void)installSortBarButton
{
    UIAction *flat = [UIAction actionWithTitle:@"Alphabetical"
                                         image:[UIImage systemImageNamed:@"list.bullet"]
                                    identifier:nil
                                       handler:^(UIAction *_) {
        [self applyGroupByCategory:NO];
    }];
    flat.state = self.groupByCategory ? UIMenuElementStateOff : UIMenuElementStateOn;

    UIAction *byCat = [UIAction actionWithTitle:@"By Category"
                                          image:[UIImage systemImageNamed:@"folder"]
                                     identifier:nil
                                        handler:^(UIAction *_) {
        [self applyGroupByCategory:YES];
    }];
    byCat.state = self.groupByCategory ? UIMenuElementStateOn : UIMenuElementStateOff;

    UIMenu *menu = [UIMenu menuWithTitle:@"Sort" children:@[flat, byCat]];
    UIBarButtonItem *btn = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"]
                 menu:menu];
    self.navigationItem.rightBarButtonItem = btn;
}

- (void)applyGroupByCategory:(BOOL)group
{
    if (_groupByCategory == group) return;
    _groupByCategory = group;
    [[NSUserDefaults standardUserDefaults] setBool:group forKey:kGroupByCategoryDefault];
    [self installSortBarButton];
    [self rebuildFilteredData];
    [self.tableView reloadData];
}

#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController
{
    NSString *q = searchController.searchBar.text ?: @"";
    if ([q isEqualToString:self.searchText]) return;
    self.searchText = q;
    [self rebuildFilteredData];
    [self.tableView reloadData];
}

#pragma mark - Filtering / bucketing

- (BOOL)package:(Package *)pkg matchesQuery:(NSString *)q
{
    if (q.length == 0) return YES;
    NSStringCompareOptions opt = NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch;
    if ([pkg.name             rangeOfString:q options:opt].location != NSNotFound) return YES;
    if ([pkg.shortDescription rangeOfString:q options:opt].location != NSNotFound) return YES;
    if ([pkg.category         rangeOfString:q options:opt].location != NSNotFound) return YES;
    return NO;
}

- (void)rebuildFilteredData
{
    NSMutableArray<Package *> *filtered = [NSMutableArray array];
    for (Package *p in self.allPackagesSorted) {
        if ([self package:p matchesQuery:self.searchText]) [filtered addObject:p];
    }
    self.flatPackages = filtered;

    if (!self.groupByCategory) {
        self.visibleCategories = nil;
        self.packagesByCategory = nil;
        return;
    }

    NSMutableArray<NSString *> *cats = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSArray<Package *> *> *bucket = [NSMutableDictionary dictionary];
    for (NSString *cat in [PackageCatalog categoriesInOrder]) {
        NSMutableArray<Package *> *inCat = [NSMutableArray array];
        for (Package *p in filtered) {
            if ([p.category isEqualToString:cat]) [inCat addObject:p];
        }
        if (inCat.count > 0) {
            [cats addObject:cat];
            bucket[cat] = inCat;
        }
    }
    self.visibleCategories = cats;
    self.packagesByCategory = bucket;
}

#pragma mark - Data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    if (self.groupByCategory) return (NSInteger)self.visibleCategories.count;
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (self.groupByCategory) {
        NSString *cat = self.visibleCategories[section];
        return (NSInteger)self.packagesByCategory[cat].count;
    }
    return (NSInteger)self.flatPackages.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    // Tighten the first category header so it doesn't sit far below the tips
    // card. Subsequent category headers keep their natural spacing.
    if (section == 0) return 26.0;
    return UITableViewAutomaticDimension;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    // Custom only for the first category header so the gap to the tips card
    // is tight. A plain UIView (not UITableViewHeaderFooterView) avoids the
    // header-footer's built-in textLabel auto-rendering the system title on
    // top of our own.
    if (section != 0) return nil;
    NSString *title = [self tableView:tableView titleForHeaderInSection:section];
    if (!title.length) return nil;

    UIView *hdr = [[UIView alloc] init];
    UILabel *lbl = [[UILabel alloc] init];
    // Match the system's plain-style header look: uppercase, footnote weight,
    // secondary label color. Tracking is tightened a touch for the small caps.
    NSDictionary *attrs = @{
        NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold],
        NSForegroundColorAttributeName: UIColor.secondaryLabelColor,
        NSKernAttributeName: @(0.4),
    };
    lbl.attributedText = [[NSAttributedString alloc] initWithString:title.uppercaseString attributes:attrs];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    [hdr addSubview:lbl];
    [NSLayoutConstraint activateConstraints:@[
        [lbl.leadingAnchor  constraintEqualToAnchor:hdr.layoutMarginsGuide.leadingAnchor],
        [lbl.trailingAnchor constraintEqualToAnchor:hdr.layoutMarginsGuide.trailingAnchor],
        [lbl.bottomAnchor   constraintEqualToAnchor:hdr.bottomAnchor constant:-4.0],
    ]];
    return hdr;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (self.groupByCategory) return self.visibleCategories[section];
    return nil;
}

- (Package *)packageAtIndexPath:(NSIndexPath *)indexPath
{
    if (self.groupByCategory) {
        NSString *cat = self.visibleCategories[indexPath.section];
        return self.packagesByCategory[cat][indexPath.row];
    }
    return self.flatPackages[indexPath.row];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kPackageCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:kPackageCellID];
    }

    Package *pkg = [self packageAtIndexPath:indexPath];

    // UIListContentConfiguration with a fixed reservedLayoutSize so every
    // SF Symbol occupies the same horizontal slot regardless of its intrinsic
    // aspect ratio. Without this, wider glyphs (apps.iphone, antenna.*) push
    // their text further right than narrower ones (thermometer, sun.max).
    UIListContentConfiguration *config = [UIListContentConfiguration subtitleCellConfiguration];
    config.image = [UIImage systemImageNamed:pkg.symbolName];
    config.imageProperties.preferredSymbolConfiguration =
        [UIImageSymbolConfiguration configurationWithPointSize:22.0 weight:UIImageSymbolWeightRegular];
    UIColor *mainColor = pkg.isInstallDisabled ? UIColor.secondaryLabelColor : self.view.tintColor;
    config.imageProperties.tintColor       = mainColor;
    config.imageProperties.reservedLayoutSize = CGSizeMake(34.0, 28.0);
    config.imageProperties.maximumSize     = CGSizeMake(28.0, 28.0);
    config.imageToTextPadding              = 14.0;
    config.text = pkg.name;
    config.textProperties.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    if (pkg.isInstallDisabled) config.textProperties.color = UIColor.secondaryLabelColor;
    config.secondaryText = pkg.shortDescription;
    config.secondaryTextProperties.color = pkg.isInstallDisabled ? UIColor.tertiaryLabelColor : UIColor.secondaryLabelColor;
    config.secondaryTextProperties.numberOfLines = 2;
    config.textToSecondaryTextVerticalPadding = 3.0;
    NSDirectionalEdgeInsets m = config.directionalLayoutMargins;
    m.top    = 14.0;
    m.bottom = 14.0;
    config.directionalLayoutMargins = m;
    cell.contentConfiguration = config;

    cell.accessoryView = [self accessoryViewForPackage:pkg];
    if (!cell.accessoryView) {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.accessoryType = UITableViewCellAccessoryNone;
    }

    return cell;
}

- (UIView *)accessoryViewForPackage:(Package *)pkg
{
    PackageQueueIntent intent = [[PackageQueue sharedQueue] intentForPackage:pkg];
    if (pkg.kind == PackageInstallKindOTA) {
        if (intent != PackageQueueIntentNone) {
            NSString *text = (intent == PackageQueueIntentInstall) ? @"DISABLE QUEUED" : @"ENABLE QUEUED";
            UIColor *color = self.view.tintColor;
            return [self pillWithText:text
                           background:[color colorWithAlphaComponent:0.18]
                            textColor:color];
        }
        return [self pillWithText:@"MANUAL"
                       background:[UIColor.secondaryLabelColor colorWithAlphaComponent:0.14]
                        textColor:UIColor.secondaryLabelColor];
    }
    if (pkg.kind == PackageInstallKindNanoRegistry) {
        if (intent != PackageQueueIntentNone) {
            NSString *text = (intent == PackageQueueIntentInstall) ? @"APPLY QUEUED" : @"REMOVE QUEUED";
            UIColor *color = self.view.tintColor;
            return [self pillWithText:text
                           background:[color colorWithAlphaComponent:0.18]
                            textColor:color];
        }
        return [self pillWithText:@"MANUAL"
                       background:[UIColor.secondaryLabelColor colorWithAlphaComponent:0.14]
                        textColor:UIColor.secondaryLabelColor];
    }
    if (intent != PackageQueueIntentNone) {
        NSString *text = (intent == PackageQueueIntentInstall) ? @"Queued" : @"Removing";
        UIColor *color = self.view.tintColor;
        return [self pillWithText:text
                       background:[color colorWithAlphaComponent:0.18]
                        textColor:color];
    }
    if (pkg.isInstalled) {
        return [self pillWithText:@"Installed"
                       background:[UIColor colorWithRed:0.16 green:0.55 blue:0.32 alpha:0.18]
                        textColor:[UIColor systemGreenColor]];
    }
    if (pkg.isInstallDisabled) {
        return [self pillWithText:@"BUGGY"
                       background:[[UIColor systemRedColor] colorWithAlphaComponent:0.16]
                        textColor:[UIColor systemRedColor]];
    }
    if ([pkg.category caseInsensitiveCompare:@"Beta"] == NSOrderedSame) {
        return [self pillWithText:@"BETA"
                       background:[[UIColor systemPurpleColor] colorWithAlphaComponent:0.18]
                        textColor:[UIColor systemPurpleColor]];
    }
    if (pkg.isNew) {
        return [self pillWithText:@"NEW"
                       background:[UIColor colorWithRed:0.95 green:0.55 blue:0.05 alpha:0.18]
                        textColor:[UIColor systemOrangeColor]];
    }
    return nil;
}

- (UIView *)pillWithText:(NSString *)text background:(UIColor *)bg textColor:(UIColor *)fg
{
    UILabel *pill = [[UILabel alloc] init];
    pill.text = text;
    pill.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightHeavy];
    pill.textColor = fg;
    pill.backgroundColor = bg;
    pill.textAlignment = NSTextAlignmentCenter;
    [pill sizeToFit];

    CGRect frame = pill.frame;
    frame.size.width  += 14.0;
    frame.size.height = 22.0;
    pill.frame = frame;

    pill.layer.cornerRadius = frame.size.height / 2.0;
    pill.layer.masksToBounds = YES;
    return pill;
}

#pragma mark - Delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    Package *pkg = [self packageAtIndexPath:indexPath];
    PackageDetailViewController *detail = [[PackageDetailViewController alloc] initWithPackage:pkg];
    [self.navigationController pushViewController:detail animated:YES];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath
{
    Package *pkg = [self packageAtIndexPath:indexPath];
    PackageQueue *q = [PackageQueue sharedQueue];
    PackageQueueIntent intent = [q intentForPackage:pkg];
    if (pkg.isInstallDisabled && !pkg.isInstalled && intent == PackageQueueIntentNone) return nil;

    if (pkg.kind == PackageInstallKindOTA && intent == PackageQueueIntentNone) {
        UIContextualAction *disable = [UIContextualAction
            contextualActionWithStyle:UIContextualActionStyleDestructive
                                title:@"Disable"
                              handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
            [q queueIntent:PackageQueueIntentInstall forPackage:pkg];
            done(YES);
        }];
        disable.image = [UIImage systemImageNamed:@"icloud.slash"];

        UIContextualAction *enable = [UIContextualAction
            contextualActionWithStyle:UIContextualActionStyleNormal
                                title:@"Enable"
                              handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
            [q queueIntent:PackageQueueIntentUninstall forPackage:pkg];
            done(YES);
        }];
        enable.backgroundColor = UIColor.systemGreenColor;
        enable.image = [UIImage systemImageNamed:@"icloud"];

        UISwipeActionsConfiguration *cfg = [UISwipeActionsConfiguration configurationWithActions:@[disable, enable]];
        cfg.performsFirstActionWithFullSwipe = NO;
        return cfg;
    }

    if (pkg.kind == PackageInstallKindNanoRegistry && intent == PackageQueueIntentNone) {
        UIContextualAction *apply = [UIContextualAction
            contextualActionWithStyle:UIContextualActionStyleNormal
                                title:@"Apply"
                              handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
            [q queueIntent:PackageQueueIntentInstall forPackage:pkg];
            done(YES);
        }];
        apply.backgroundColor = self.view.tintColor;
        apply.image = [UIImage systemImageNamed:@"applewatch.radiowaves.left.and.right"];

        UIContextualAction *remove = [UIContextualAction
            contextualActionWithStyle:UIContextualActionStyleDestructive
                                title:@"Remove"
                              handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
            [q queueIntent:PackageQueueIntentUninstall forPackage:pkg];
            done(YES);
        }];
        remove.image = [UIImage systemImageNamed:@"xmark.circle"];

        UISwipeActionsConfiguration *cfg = [UISwipeActionsConfiguration configurationWithActions:@[apply, remove]];
        cfg.performsFirstActionWithFullSwipe = NO;
        return cfg;
    }

    NSString *title;
    UIColor *color;
    NSString *symbol;
    if (intent != PackageQueueIntentNone) {
        title  = @"Remove";
        color  = [UIColor systemGrayColor];
        symbol = @"xmark.circle";
    } else if (pkg.isInstalled) {
        title  = @"Uninstall";
        color  = [UIColor systemRedColor];
        symbol = @"trash";
    } else {
        title  = @"Queue";
        color  = self.view.tintColor;
        symbol = @"tray.and.arrow.down";
    }

    UIContextualAction *action = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleNormal
                            title:title
                          handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        BOOL isInstall = (intent == PackageQueueIntentNone && !pkg.isInstalled);
        if (NO && isInstall && pkg.settingsSection != NSIntegerMax) {
            done(YES);
            [self presentConfigureAlertForPackage:pkg];
            return;
        }
        [q toggleForPackage:pkg];
        done(YES);
    }];
    action.backgroundColor = color;
    action.image = [UIImage systemImageNamed:symbol];

    UISwipeActionsConfiguration *cfg = [UISwipeActionsConfiguration configurationWithActions:@[action]];
    cfg.performsFirstActionWithFullSwipe = YES;
    return cfg;
}

- (void)presentConfigureAlertForPackage:(Package *)pkg
{
    NSString *msg = [NSString stringWithFormat:
        @"%@ has configurable options. Set them up first so the tweak applies with your preferences on the first run.",
        pkg.name];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Customize Before Installing?"
                                                                   message:msg
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Configure First"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *_) {
        PackageDetailViewController *detail = [[PackageDetailViewController alloc] initWithPackage:pkg];
        [self.navigationController pushViewController:detail animated:YES];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Install Anyway"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *_) {
        [[PackageQueue sharedQueue] toggleForPackage:pkg];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                             style:UIAlertActionStyleCancel
                                           handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
