//
//  PackagesViewController.m
//  Cyanide
//

#import "PackagesViewController.h"
#import "CYIconBadge.h"
#import "CommunityVotesViewController.h"
#import "PackageCatalog.h"
#import "PackageDetailViewController.h"
#import "PackageQueue.h"
#import "../SettingsViewController.h"
#import "../tweaks/RepoTweaks.h"
#import "MainTabBarController.h"
#import <math.h>

static NSString * const kPkgCellID = @"PkgCell";
static const NSTimeInterval kPackageNewWindow = 14.0 * 24.0 * 60.0 * 60.0;

typedef NS_ENUM(NSInteger, PackagesScope) {
    PackagesScopeAll = 0,
    PackagesScopeActive,
    PackagesScopeUpdates,
    PackagesScopeNew,
};

static NSString *relative_time(NSTimeInterval timestamp)
{
    if (timestamp <= 0) return nil;
    NSTimeInterval diff = [[NSDate date] timeIntervalSince1970] - timestamp;
    if (diff < 60)          return @"Just now";
    if (diff < 3600)        return [NSString stringWithFormat:@"%ldm ago", (long)(diff / 60)];
    if (diff < 86400)       return [NSString stringWithFormat:@"%ldh ago", (long)(diff / 3600)];
    if (diff < 86400 * 2)   return @"Yesterday";
    if (diff < 86400 * 7)   return [NSString stringWithFormat:@"%ldd ago", (long)(diff / 86400)];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"MMM d";
    return [fmt stringFromDate:[NSDate dateWithTimeIntervalSince1970:timestamp]];
}

static NSTimeInterval package_seen_timestamp(Package *pkg)
{
    if (pkg.kind != PackageInstallKindRepoTweak || pkg.repoURL.length == 0 || pkg.repoTweakID.length == 0) return 0;
    return repotweaks_seen_timestamp(pkg.repoURL, pkg.repoTweakID);
}

static BOOL package_is_recent(Package *pkg)
{
    NSTimeInterval seen = package_seen_timestamp(pkg);
    if (seen <= 0) return NO;
    NSTimeInterval age = [[NSDate date] timeIntervalSince1970] - seen;
    return age >= 0 && age <= kPackageNewWindow;
}

static BOOL package_has_repo_update(Package *pkg)
{
    if (pkg.kind != PackageInstallKindRepoTweak) return NO;
    if (pkg.isInstallDisabled) return NO;
    if (pkg.repoURL.length == 0 || pkg.repoTweakID.length == 0) return NO;
    NSString *installed = [[NSUserDefaults standardUserDefaults]
        stringForKey:repotweaks_installed_version_key(pkg.repoURL, pkg.repoTweakID)];
    if (installed.length == 0 || pkg.version.length == 0) return NO;
    return repotweaks_compare_versions(pkg.version, installed) == NSOrderedDescending;
}

static UILabel *packages_stat_label(void)
{
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.numberOfLines = 2;
    label.textAlignment = NSTextAlignmentCenter;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.8;
    return label;
}

@interface PackagesViewController () <UISearchResultsUpdating>
@property (nonatomic, copy) NSArray<Package *> *allPackagesSorted;
@property (nonatomic, copy) NSArray<Package *> *recentPackages;
@property (nonatomic, copy) NSArray<NSArray<Package *> *> *displayedSections;
@property (nonatomic, copy) NSArray<NSString *> *displayedSectionTitles;
@property (nonatomic, copy) NSArray<Package *> *searchResults;
@property (nonatomic, copy) NSString *searchText;
@property (nonatomic, strong) UISearchController *searchCtl;
@property (nonatomic, assign) PackagesScope scope;

@property (nonatomic, strong) UIView *libraryHeader;
@property (nonatomic, strong) UIView *summaryCard;
@property (nonatomic, strong) UILabel *libraryTitleLabel;
@property (nonatomic, strong) UILabel *librarySubtitleLabel;
@property (nonatomic, copy) NSArray<UILabel *> *statLabels;
@property (nonatomic, strong) UISegmentedControl *scopeControl;
@end

@implementation PackagesViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Packages";
    self.navigationItem.title = @"Packages";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    UIBarButtonItem *votesItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Vote"
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(openCommunityVotes)];
    votesItem.accessibilityLabel = @"Community Votes";
    self.navigationItem.rightBarButtonItem = votesItem;
    self.searchText = @"";
    self.scope = PackagesScopeAll;

    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 84.0;
    self.tableView.sectionFooterHeight = 8.0;
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 60.0, 0, 18.0);

    [self buildLibraryHeader];
    [self refreshCatalog];

    UIRefreshControl *refresh = [[UIRefreshControl alloc] init];
    refresh.tintColor = UIColor.systemOrangeColor;
    refresh.attributedTitle = [[NSAttributedString alloc] initWithString:@"Refresh package sources"];
    [refresh addTarget:self action:@selector(pullToRefresh) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = refresh;

    self.searchCtl = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchCtl.searchResultsUpdater = self;
    self.searchCtl.obscuresBackgroundDuringPresentation = NO;
    self.searchCtl.searchBar.placeholder = @"Search tweaks, categories, or authors";
    self.navigationItem.searchController = self.searchCtl;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(catalogDidChange:)
                                                 name:PackageQueueDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(catalogDidChange:)
                                                 name:kSettingsActionsDidCompleteNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(catalogDidChange:)
                                                 name:RepoTweaksDidRefreshNotification
                                               object:nil];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    [self layoutLibraryHeader];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self refreshCatalog];
    [self.tableView reloadData];
}

#pragma mark - Library header

- (void)buildLibraryHeader
{
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 194.0)];
    UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
    card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    card.layer.cornerRadius = 22.0;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    [header addSubview:card];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
    title.text = @"TWEAK LIBRARY";
    title.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightHeavy];
    title.textColor = UIColor.systemOrangeColor;
    [card addSubview:title];

    UILabel *subtitle = [[UILabel alloc] initWithFrame:CGRectZero];
    subtitle.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
    subtitle.textColor = UIColor.secondaryLabelColor;
    subtitle.numberOfLines = 1;
    [card addSubview:subtitle];

    NSMutableArray<UILabel *> *stats = [NSMutableArray arrayWithCapacity:4];
    for (NSInteger i = 0; i < 4; i++) {
        UILabel *label = packages_stat_label();
        [card addSubview:label];
        [stats addObject:label];
    }

    UISegmentedControl *scope = [[UISegmentedControl alloc] initWithItems:@[@"All", @"Active", @"Updates", @"New"]];
    scope.selectedSegmentIndex = PackagesScopeAll;
    scope.selectedSegmentTintColor = UIColor.systemOrangeColor;
    [scope setTitleTextAttributes:@{NSForegroundColorAttributeName: UIColor.whiteColor,
                                    NSFontAttributeName: [UIFont systemFontOfSize:12.0 weight:UIFontWeightBold]}
                         forState:UIControlStateSelected];
    [scope addTarget:self action:@selector(scopeDidChange:) forControlEvents:UIControlEventValueChanged];
    [header addSubview:scope];

    self.libraryHeader = header;
    self.summaryCard = card;
    self.libraryTitleLabel = title;
    self.librarySubtitleLabel = subtitle;
    self.statLabels = stats;
    self.scopeControl = scope;
    self.tableView.tableHeaderView = header;
}

- (void)layoutLibraryHeader
{
    CGFloat width = self.tableView.bounds.size.width;
    if (width <= 0 || !self.libraryHeader) return;
    if (fabs(self.libraryHeader.frame.size.width - width) > 0.5) {
        CGRect headerFrame = self.libraryHeader.frame;
        headerFrame.size.width = width;
        self.libraryHeader.frame = headerFrame;
        self.tableView.tableHeaderView = self.libraryHeader;
    }

    CGFloat inset = 16.0;
    self.summaryCard.frame = CGRectMake(inset, 8.0, width - inset * 2.0, 128.0);
    self.libraryTitleLabel.frame = CGRectMake(18.0, 14.0, self.summaryCard.bounds.size.width - 36.0, 17.0);
    self.librarySubtitleLabel.frame = CGRectMake(18.0, 32.0, self.summaryCard.bounds.size.width - 36.0, 19.0);

    CGFloat statWidth = self.summaryCard.bounds.size.width / 4.0;
    for (NSInteger i = 0; i < (NSInteger)self.statLabels.count; i++) {
        self.statLabels[i].frame = CGRectMake(statWidth * i, 61.0, statWidth, 54.0);
    }
    self.scopeControl.frame = CGRectMake(inset, 147.0, width - inset * 2.0, 36.0);
}

- (void)updateLibraryHeader
{
    NSInteger active = 0, updates = 0;
    for (Package *pkg in self.allPackagesSorted) {
        if (pkg.isInstalled) active++;
        if (package_has_repo_update(pkg)) updates++;
    }
    NSInteger queued = [PackageQueue sharedQueue].pendingCount;
    self.librarySubtitleLabel.text = queued > 0
        ? [NSString stringWithFormat:@"%ld pending change%@ ready to review", (long)queued, queued == 1 ? @"" : @"s"]
        : @"Browse, activate, and manage every tweak";

    NSArray<NSString *> *values = @[
        [NSString stringWithFormat:@"%ld\nTotal", (long)self.allPackagesSorted.count],
        [NSString stringWithFormat:@"%ld\nActive", (long)active],
        [NSString stringWithFormat:@"%ld\nUpdates", (long)updates],
        [NSString stringWithFormat:@"%ld\nNew", (long)self.recentPackages.count],
    ];
    NSArray<UIColor *> *colors = @[UIColor.labelColor, UIColor.systemGreenColor,
                                   UIColor.systemRedColor, UIColor.systemOrangeColor];
    for (NSInteger i = 0; i < (NSInteger)self.statLabels.count; i++) {
        UILabel *label = self.statLabels[i];
        label.text = values[i];
        label.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightBold];
        label.textColor = colors[i];
    }
}

#pragma mark - Catalog and filtering

- (void)catalogDidChange:(NSNotification *)note
{
    if (!self.isViewLoaded) return;
    [self refreshCatalog];
    [self.tableView reloadData];
}

- (void)refreshCatalog
{
    self.allPackagesSorted = [[PackageCatalog allPackages]
        sortedArrayUsingComparator:^NSComparisonResult(Package *a, Package *b) {
            return [a.name localizedCaseInsensitiveCompare:b.name];
        }];

    NSMutableArray<Package *> *recentPackages = [NSMutableArray array];
    for (Package *pkg in self.allPackagesSorted) {
        if (package_is_recent(pkg)) [recentPackages addObject:pkg];
    }
    [recentPackages sortUsingComparator:^NSComparisonResult(Package *a, Package *b) {
        NSTimeInterval ta = package_seen_timestamp(a), tb = package_seen_timestamp(b);
        if (ta != tb) return ta > tb ? NSOrderedAscending : NSOrderedDescending;
        return [a.name localizedCaseInsensitiveCompare:b.name];
    }];
    self.recentPackages = recentPackages;

    [self rebuildDisplayedSections];
    [self rebuildSearchResults];
    [self updateLibraryHeader];
    [self updateEmptyState];
}

- (void)pullToRefresh
{
    [self.refreshControl endRefreshing];
    MainTabBarController *tab = (MainTabBarController *)self.tabBarController;
    if ([tab respondsToSelector:@selector(showRefreshBanner)]) [tab showRefreshBanner];
    repotweaks_refresh_all_sources(nil);
}

- (void)openCommunityVotes
{
    CommunityVotesViewController *votes = [[CommunityVotesViewController alloc]
        initWithStyle:UITableViewStyleInsetGrouped];
    [self.navigationController pushViewController:votes animated:YES];
}

- (void)scopeDidChange:(UISegmentedControl *)sender
{
    self.scope = (PackagesScope)sender.selectedSegmentIndex;
    [self rebuildDisplayedSections];
    [self rebuildSearchResults];
    [self updateEmptyState];
    [self.tableView reloadData];
    if (self.tableView.numberOfSections > 0 && [self.tableView numberOfRowsInSection:0] > 0) {
        [self.tableView setContentOffset:CGPointMake(0, -self.tableView.adjustedContentInset.top) animated:YES];
    }
}

- (BOOL)isSearchActive { return self.searchText.length > 0; }

- (NSArray<Package *> *)packagesForCurrentScope
{
    switch (self.scope) {
        case PackagesScopeActive: {
            NSPredicate *p = [NSPredicate predicateWithBlock:^BOOL(Package *pkg, NSDictionary *bindings) {
                return pkg.isInstalled;
            }];
            return [self.allPackagesSorted filteredArrayUsingPredicate:p];
        }
        case PackagesScopeUpdates: {
            NSPredicate *p = [NSPredicate predicateWithBlock:^BOOL(Package *pkg, NSDictionary *bindings) {
                return package_has_repo_update(pkg);
            }];
            return [self.allPackagesSorted filteredArrayUsingPredicate:p];
        }
        case PackagesScopeNew:
            return self.recentPackages;
        case PackagesScopeAll:
        default:
            return self.allPackagesSorted;
    }
}

- (void)rebuildDisplayedSections
{
    NSMutableArray<NSArray<Package *> *> *sections = [NSMutableArray array];
    NSMutableArray<NSString *> *titles = [NSMutableArray array];

    if (self.scope != PackagesScopeAll) {
        NSArray<Package *> *packages = [self packagesForCurrentScope];
        if (packages.count > 0) {
            [sections addObject:packages];
            NSArray<NSString *> *scopeTitles = @[@"All Packages", @"Active Tweaks", @"Available Updates", @"Recently Added"];
            [titles addObject:scopeTitles[self.scope]];
        }
        self.displayedSections = sections;
        self.displayedSectionTitles = titles;
        return;
    }

    NSMutableArray<Package *> *attention = [NSMutableArray array];
    NSMutableArray<Package *> *active = [NSMutableArray array];
    NSMutableArray<Package *> *recent = [NSMutableArray array];
    NSMutableArray<Package *> *available = [NSMutableArray array];
    PackageQueue *queue = [PackageQueue sharedQueue];

    for (Package *pkg in self.allPackagesSorted) {
        BOOL needsAttention = package_has_repo_update(pkg) || [queue intentForPackage:pkg] != PackageQueueIntentNone;
        if (needsAttention) [attention addObject:pkg];
        else if (pkg.isInstalled) [active addObject:pkg];
        else if (package_is_recent(pkg)) [recent addObject:pkg];
        else [available addObject:pkg];
    }

    NSArray<NSArray<Package *> *> *buckets = @[attention, active, recent, available];
    NSArray<NSString *> *bucketTitles = @[@"Needs Attention", @"Active", @"Recently Added", @"Available"];
    for (NSInteger i = 0; i < (NSInteger)buckets.count; i++) {
        if (buckets[i].count == 0) continue;
        [sections addObject:buckets[i]];
        [titles addObject:bucketTitles[i]];
    }
    self.displayedSections = sections;
    self.displayedSectionTitles = titles;
}

#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController
{
    NSString *q = [searchController.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    if ([q isEqualToString:self.searchText]) return;
    self.searchText = q;
    [self rebuildSearchResults];
    [self updateEmptyState];
    [self.tableView reloadData];
}

- (void)rebuildSearchResults
{
    if (![self isSearchActive]) { self.searchResults = nil; return; }
    NSString *q = self.searchText;
    NSStringCompareOptions opt = NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch;
    NSMutableArray<Package *> *out = [NSMutableArray array];
    for (Package *pkg in [self packagesForCurrentScope]) {
        BOOL match = [pkg.name rangeOfString:q options:opt].location != NSNotFound ||
                     [pkg.shortDescription rangeOfString:q options:opt].location != NSNotFound ||
                     [pkg.longDescription rangeOfString:q options:opt].location != NSNotFound ||
                     [pkg.category rangeOfString:q options:opt].location != NSNotFound ||
                     [pkg.author rangeOfString:q options:opt].location != NSNotFound;
        if (match) [out addObject:pkg];
    }
    self.searchResults = out;
}

- (void)updateEmptyState
{
    BOOL empty = [self isSearchActive] ? self.searchResults.count == 0 : self.displayedSections.count == 0;
    if (!empty) {
        self.tableView.backgroundView = nil;
        return;
    }
    UILabel *label = [[UILabel alloc] initWithFrame:self.tableView.bounds];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 3;
    label.textColor = UIColor.secondaryLabelColor;
    label.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
    if ([self isSearchActive]) {
        label.text = [NSString stringWithFormat:@"No packages match “%@”\nTry a name, category, or author.", self.searchText];
    } else if (self.scope == PackagesScopeUpdates) {
        label.text = @"Everything is up to date\nPull down to refresh your sources.";
    } else if (self.scope == PackagesScopeActive) {
        label.text = @"No active tweaks yet\nOpen a package to add it to the queue.";
    } else {
        label.text = @"No packages in this view.";
    }
    self.tableView.backgroundView = label;
}

#pragma mark - Data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return [self isSearchActive] ? (self.searchResults.count > 0 ? 1 : 0) : (NSInteger)self.displayedSections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if ([self isSearchActive]) return (NSInteger)self.searchResults.count;
    return (NSInteger)self.displayedSections[section].count;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    if ([self isSearchActive]) {
        return CYSectionHeaderView([NSString stringWithFormat:@"%ld Result%@",
                                    (long)self.searchResults.count,
                                    self.searchResults.count == 1 ? @"" : @"s"]);
    }
    return CYSectionHeaderView(self.displayedSectionTitles[section]);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    return 46.0;
}

- (Package *)packageAtIndexPath:(NSIndexPath *)indexPath
{
    if ([self isSearchActive]) return self.searchResults[indexPath.row];
    return self.displayedSections[indexPath.section][indexPath.row];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return [self packageCellForPackage:[self packageAtIndexPath:indexPath] tableView:tableView];
}

- (UILabel *)statusPillWithText:(NSString *)text color:(UIColor *)color
{
    UILabel *pill = [[UILabel alloc] init];
    pill.text = text;
    pill.font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightHeavy];
    pill.textColor = color;
    pill.backgroundColor = [color colorWithAlphaComponent:0.14];
    pill.textAlignment = NSTextAlignmentCenter;
    [pill sizeToFit];
    CGRect frame = pill.frame;
    frame.size.width += 14.0;
    frame.size.height = 22.0;
    pill.frame = frame;
    pill.layer.cornerRadius = 11.0;
    pill.layer.cornerCurve = kCACornerCurveContinuous;
    pill.layer.masksToBounds = YES;
    return pill;
}

- (UITableViewCell *)packageCellForPackage:(Package *)pkg tableView:(UITableView *)tableView
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kPkgCellID];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kPkgCellID];

    BOOL installed = pkg.isInstalled;
    BOOL unsupported = pkg.isInstallDisabled;
    BOOL hasUpdate = package_has_repo_update(pkg);
    PackageQueueIntent intent = [[PackageQueue sharedQueue] intentForPackage:pkg];
    NSUInteger colorIndex = (NSUInteger)pkg.identifier.hash;
    UIColor *iconColor = unsupported && !installed ? UIColor.secondaryLabelColor : CYSpectrumColor(colorIndex);

    UIListContentConfiguration *config = [UIListContentConfiguration subtitleCellConfiguration];
    config.image = CYIconBadgeImage(pkg.symbolName, iconColor, 34.0);
    config.imageProperties.reservedLayoutSize = CGSizeMake(34.0, 34.0);
    config.imageProperties.maximumSize = CGSizeMake(34.0, 34.0);
    config.imageToTextPadding = 12.0;
    config.text = pkg.name;
    config.textProperties.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    if (unsupported && !installed) config.textProperties.color = UIColor.secondaryLabelColor;

    NSTimeInterval seen = package_seen_timestamp(pkg);
    NSString *time = relative_time(seen);
    NSMutableArray<NSString *> *meta = [NSMutableArray array];
    if (pkg.category.length) [meta addObject:pkg.category];
    if (pkg.version.length) [meta addObject:[NSString stringWithFormat:@"v%@", pkg.version]];
    if (time.length && package_is_recent(pkg)) [meta addObject:time];
    NSString *metaLine = [meta componentsJoinedByString:@"  •  "];

    NSString *description = pkg.shortDescription ?: @"";
    if (unsupported && pkg.installDisabledReason.length) description = pkg.installDisabledReason;
    config.secondaryText = description.length > 0
        ? [NSString stringWithFormat:@"%@\n%@", metaLine, description]
        : metaLine;
    config.secondaryTextProperties.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular];
    config.secondaryTextProperties.color = unsupported ? UIColor.systemOrangeColor : UIColor.secondaryLabelColor;
    config.secondaryTextProperties.numberOfLines = 3;
    config.textToSecondaryTextVerticalPadding = 3.0;
    NSDirectionalEdgeInsets margins = config.directionalLayoutMargins;
    margins.top = 11.0;
    margins.bottom = 11.0;
    config.directionalLayoutMargins = margins;
    cell.contentConfiguration = config;

    cell.accessoryType = UITableViewCellAccessoryNone;
    if (intent == PackageQueueIntentInstall) {
        cell.accessoryView = [self statusPillWithText:@"QUEUED" color:UIColor.systemOrangeColor];
    } else if (intent == PackageQueueIntentUninstall) {
        cell.accessoryView = [self statusPillWithText:@"REMOVE" color:UIColor.systemRedColor];
    } else if (hasUpdate) {
        cell.accessoryView = [self statusPillWithText:@"UPDATE" color:UIColor.systemRedColor];
    } else if (unsupported && installed) {
        cell.accessoryView = [self statusPillWithText:@"ACTIVE" color:UIColor.systemGreenColor];
    } else if (unsupported) {
        NSString *label = [pkg.category isEqualToString:@"In Development"] ? @"DISABLED" : @"UNSUPPORTED";
        cell.accessoryView = [self statusPillWithText:label color:UIColor.systemOrangeColor];
    } else if (installed) {
        cell.accessoryView = [self statusPillWithText:@"ACTIVE" color:UIColor.systemGreenColor];
    } else {
        cell.accessoryView = nil;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

#pragma mark - Delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    PackageDetailViewController *detail = [[PackageDetailViewController alloc]
        initWithPackage:[self packageAtIndexPath:indexPath]];
    [self.navigationController pushViewController:detail animated:YES];
}

@end
