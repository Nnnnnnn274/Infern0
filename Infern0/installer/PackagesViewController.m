//
//  PackagesViewController.m
//  Cyanide
//

#import "PackagesViewController.h"
#import "CYIconBadge.h"
#import "PackageCatalog.h"
#import "PackageDetailViewController.h"
#import "PackageQueue.h"
#import "../SettingsViewController.h"
#import "../tweaks/RepoTweaks.h"
#import "MainTabBarController.h"

static NSString * const kPkgCellID    = @"PkgCell";
static NSString * const kSearchCellID = @"SearchPkgCell";

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

typedef NS_ENUM(NSInteger, PackagesSection) {
    PackagesSectionNew = 0,
    PackagesSectionAll,
    PackagesSectionCount,
};

@interface PackagesViewController () <UISearchResultsUpdating>
@property (nonatomic, copy) NSArray<Package *> *recentPackages;
@property (nonatomic, copy) NSArray<Package *> *allPackagesSorted;
@property (nonatomic, copy) NSArray<Package *> *searchResults;
@property (nonatomic, copy) NSString *searchText;
@property (nonatomic, strong) UISearchController *searchCtl;
@end

@implementation PackagesViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Packages";
    self.navigationItem.title = @"Packages";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.searchText = @"";

    [self refreshCatalog];

    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 68.0;
    self.tableView.sectionFooterHeight = 4.0;

    UIRefreshControl *refresh = [[UIRefreshControl alloc] init];
    [refresh addTarget:self action:@selector(pullToRefresh) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = refresh;

    self.searchCtl = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchCtl.searchResultsUpdater = self;
    self.searchCtl.obscuresBackgroundDuringPresentation = NO;
    self.searchCtl.searchBar.placeholder = @"Search all tweaks";
    self.navigationItem.searchController = self.searchCtl;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;

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

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self refreshCatalog];
    [self.tableView reloadData];
}

- (void)catalogDidChange:(NSNotification *)note
{
    if (!self.isViewLoaded) return;
    [self refreshCatalog];
    [self.tableView reloadData];
}

- (void)refreshCatalog
{
    NSArray<Package *> *all = [[PackageCatalog allPackages]
        sortedArrayUsingComparator:^NSComparisonResult(Package *a, Package *b) {
            return [a.name caseInsensitiveCompare:b.name];
        }];

    NSMutableArray<Package *> *recentPkgs = [NSMutableArray array];
    NSMutableArray<Package *> *filtered = [NSMutableArray array];
    for (Package *p in all) {
        [filtered addObject:p];
        if (p.kind == PackageInstallKindRepoTweak && p.repoURL.length > 0 && p.repoTweakID.length > 0) {
            NSTimeInterval seen = repotweaks_seen_timestamp(p.repoURL, p.repoTweakID);
            if (seen > 0) [recentPkgs addObject:p];
        }
    }

    [recentPkgs sortUsingComparator:^NSComparisonResult(Package *a, Package *b) {
        NSTimeInterval ta = repotweaks_seen_timestamp(a.repoURL, a.repoTweakID);
        NSTimeInterval tb = repotweaks_seen_timestamp(b.repoURL, b.repoTweakID);
        if (ta != tb) return ta > tb ? NSOrderedAscending : NSOrderedDescending;
        return NSOrderedSame;
    }];

    self.recentPackages = recentPkgs;
    self.allPackagesSorted = filtered;
    [self rebuildSearchResults];
}

- (void)pullToRefresh
{
    [self.refreshControl endRefreshing];
    MainTabBarController *tab = (MainTabBarController *)self.tabBarController;
    if ([tab respondsToSelector:@selector(showRefreshBanner)]) [tab showRefreshBanner];
    repotweaks_refresh_all_sources(nil);
}

- (BOOL)isSearchActive { return self.searchText.length > 0; }

#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController
{
    NSString *q = searchController.searchBar.text ?: @"";
    if ([q isEqualToString:self.searchText]) return;
    self.searchText = q;
    [self rebuildSearchResults];
    [self.tableView reloadData];
}

- (void)rebuildSearchResults
{
    if (![self isSearchActive]) { self.searchResults = nil; return; }
    NSString *q = self.searchText;
    NSStringCompareOptions opt = NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch;
    NSMutableArray *out = [NSMutableArray array];
    for (Package *p in self.allPackagesSorted) {
        if ([p.name rangeOfString:q options:opt].location != NSNotFound ||
            [p.shortDescription rangeOfString:q options:opt].location != NSNotFound ||
            [p.category rangeOfString:q options:opt].location != NSNotFound) {
            [out addObject:p];
        }
    }
    self.searchResults = out;
}

#pragma mark - Data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    if ([self isSearchActive]) return 1;
    return PackagesSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if ([self isSearchActive]) return (NSInteger)self.searchResults.count;
    if (section == PackagesSectionNew) return (NSInteger)self.recentPackages.count;
    return (NSInteger)self.allPackagesSorted.count;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    if ([self isSearchActive]) return nil;
    if (section == PackagesSectionNew) return self.recentPackages.count > 0 ? CYSectionHeaderView(@"Recently Added") : nil;
    return CYSectionHeaderView(@"All Packages");
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    if ([self isSearchActive]) return 0.0;
    if (section == PackagesSectionNew && self.recentPackages.count == 0) return 0.0;
    return 46.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if ([self isSearchActive]) return [self packageCellForPackage:self.searchResults[indexPath.row] colorIndex:(NSUInteger)indexPath.row tableView:tableView];
    if (indexPath.section == PackagesSectionNew) return [self packageCellForPackage:self.recentPackages[indexPath.row] colorIndex:(NSUInteger)indexPath.row tableView:tableView];
    return [self packageCellForPackage:self.allPackagesSorted[indexPath.row] colorIndex:(NSUInteger)indexPath.row tableView:tableView];
}

- (UITableViewCell *)packageCellForPackage:(Package *)pkg colorIndex:(NSUInteger)colorIndex tableView:(UITableView *)tableView
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kPkgCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kPkgCellID];
    }

    BOOL installed = pkg.isInstalled;
    BOOL unsupported = pkg.isInstallDisabled && pkg.installDisabledReason.length > 0;
    BOOL disabledForInstall = pkg.isInstallDisabled && !installed;
    UIColor *iconColor = disabledForInstall ? UIColor.secondaryLabelColor : CYSpectrumColor(colorIndex);
    UIListContentConfiguration *config = [UIListContentConfiguration subtitleCellConfiguration];
    config.image = CYIconBadgeImage(pkg.symbolName, iconColor, 32.0);
    config.imageProperties.reservedLayoutSize = CGSizeMake(32.0, 32.0);
    config.imageProperties.maximumSize = CGSizeMake(32.0, 32.0);
    config.imageToTextPadding = 12.0;
    config.text = pkg.name;
    config.textProperties.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    if (disabledForInstall) config.textProperties.color = UIColor.secondaryLabelColor;

    BOOL hasUpdate = package_has_repo_update(pkg);
    NSTimeInterval seen = (pkg.kind == PackageInstallKindRepoTweak && pkg.repoURL.length > 0)
        ? repotweaks_seen_timestamp(pkg.repoURL, pkg.repoTweakID) : 0;
    NSString *time = relative_time(seen);
    if (unsupported && installed && pkg.shortDescription.length > 0) {
        config.secondaryText = [NSString stringWithFormat:@"Installed, unsupported here · %@ · %@",
                                pkg.installDisabledReason,
                                pkg.shortDescription];
    } else if (unsupported && installed) {
        config.secondaryText = [NSString stringWithFormat:@"Installed, unsupported here · %@",
                                pkg.installDisabledReason];
    } else if (unsupported && pkg.shortDescription.length > 0) {
        config.secondaryText = [NSString stringWithFormat:@"%@ · %@", pkg.installDisabledReason, pkg.shortDescription];
    } else if (unsupported) {
        config.secondaryText = pkg.installDisabledReason;
    } else if (hasUpdate && time && pkg.shortDescription.length > 0) {
        config.secondaryText = [NSString stringWithFormat:@"Update available · %@ · %@", time, pkg.shortDescription];
    } else if (hasUpdate && pkg.shortDescription.length > 0) {
        config.secondaryText = [NSString stringWithFormat:@"Update available · %@", pkg.shortDescription];
    } else if (hasUpdate) {
        config.secondaryText = @"Update available";
    } else if (time && pkg.shortDescription.length > 0) {
        config.secondaryText = [NSString stringWithFormat:@"%@ · %@", time, pkg.shortDescription];
    } else {
        config.secondaryText = pkg.shortDescription;
    }
    config.secondaryTextProperties.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
    config.secondaryTextProperties.color = unsupported
        ? UIColor.systemOrangeColor
        : (hasUpdate ? UIColor.systemRedColor : [UIColor.labelColor colorWithAlphaComponent:0.55]);
    config.secondaryTextProperties.numberOfLines = 3;
    config.textToSecondaryTextVerticalPadding = 2.0;
    NSDirectionalEdgeInsets m = config.directionalLayoutMargins;
    m.top = 10.0; m.bottom = 10.0;
    config.directionalLayoutMargins = m;
    cell.contentConfiguration = config;

    if (unsupported && installed) {
        UILabel *pill = [[UILabel alloc] init];
        pill.text = @"INSTALLED";
        pill.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightHeavy];
        pill.textColor = UIColor.systemGreenColor;
        pill.backgroundColor = [UIColor.systemGreenColor colorWithAlphaComponent:0.15];
        pill.textAlignment = NSTextAlignmentCenter;
        [pill sizeToFit];
        CGRect f = pill.frame;
        f.size.width += 14.0;
        f.size.height = 22.0;
        pill.frame = f;
        pill.layer.cornerRadius = f.size.height / 2.0;
        pill.layer.cornerCurve = kCACornerCurveContinuous;
        pill.layer.masksToBounds = YES;
        cell.accessoryView = pill;
    } else if (unsupported) {
        UILabel *pill = [[UILabel alloc] init];
        pill.text = [pkg.category isEqualToString:@"In Development"] ? @"DISABLED" : @"UNSUPPORTED";
        pill.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightHeavy];
        pill.textColor = UIColor.systemOrangeColor;
        pill.backgroundColor = [UIColor.systemOrangeColor colorWithAlphaComponent:0.15];
        pill.textAlignment = NSTextAlignmentCenter;
        [pill sizeToFit];
        CGRect f = pill.frame;
        f.size.width += 14.0;
        f.size.height = 22.0;
        pill.frame = f;
        pill.layer.cornerRadius = f.size.height / 2.0;
        pill.layer.cornerCurve = kCACornerCurveContinuous;
        pill.layer.masksToBounds = YES;
        cell.accessoryView = pill;
    } else if (hasUpdate) {
        UILabel *pill = [[UILabel alloc] init];
        pill.text = @"UPDATE";
        pill.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightHeavy];
        pill.textColor = UIColor.systemRedColor;
        pill.backgroundColor = [UIColor.systemRedColor colorWithAlphaComponent:0.15];
        pill.textAlignment = NSTextAlignmentCenter;
        [pill sizeToFit];
        CGRect f = pill.frame;
        f.size.width += 14.0;
        f.size.height = 22.0;
        pill.frame = f;
        pill.layer.cornerRadius = f.size.height / 2.0;
        pill.layer.cornerCurve = kCACornerCurveContinuous;
        pill.layer.masksToBounds = YES;
        cell.accessoryView = pill;
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

    Package *pkg;
    if ([self isSearchActive]) {
        pkg = self.searchResults[indexPath.row];
    } else if (indexPath.section == PackagesSectionNew) {
        pkg = self.recentPackages[indexPath.row];
    } else {
        pkg = self.allPackagesSorted[indexPath.row];
    }
    PackageDetailViewController *detail = [[PackageDetailViewController alloc] initWithPackage:pkg];
    [self.navigationController pushViewController:detail animated:YES];
}

@end
