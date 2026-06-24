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
        if ([p.category isEqualToString:@"Beta"]) continue;
        [filtered addObject:p];
        if (p.kind == PackageInstallKindRepoTweak) {
            if (!p.isInstalled) {
                [recentPkgs addObject:p];
            } else if (p.repoURL.length > 0 && p.repoTweakID.length > 0) {
                NSString *installed = [[NSUserDefaults standardUserDefaults]
                    stringForKey:repotweaks_installed_version_key(p.repoURL, p.repoTweakID)];
                if (installed.length > 0 && p.version.length > 0 &&
                    [p.version compare:installed options:NSNumericSearch] == NSOrderedDescending) {
                    [recentPkgs addObject:p];
                }
            }
        }
    }

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
    if ([self isSearchActive]) return [self packageCellForPackage:self.searchResults[indexPath.row] tableView:tableView];
    if (indexPath.section == PackagesSectionNew) return [self packageCellForPackage:self.recentPackages[indexPath.row] tableView:tableView];
    return [self packageCellForPackage:self.allPackagesSorted[indexPath.row] tableView:tableView];
}

- (UITableViewCell *)packageCellForPackage:(Package *)pkg tableView:(UITableView *)tableView
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kPkgCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kPkgCellID];
    }

    UIColor *iconColor = pkg.isInstallDisabled ? UIColor.secondaryLabelColor : self.view.tintColor;
    UIListContentConfiguration *config = [UIListContentConfiguration subtitleCellConfiguration];
    config.image = CYIconBadgeImage(pkg.symbolName, iconColor, 32.0);
    config.imageProperties.reservedLayoutSize = CGSizeMake(32.0, 32.0);
    config.imageProperties.maximumSize = CGSizeMake(32.0, 32.0);
    config.imageToTextPadding = 12.0;
    config.text = pkg.name;
    config.textProperties.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    if (pkg.isInstallDisabled) config.textProperties.color = UIColor.secondaryLabelColor;
    config.secondaryText = pkg.shortDescription;
    config.secondaryTextProperties.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
    config.secondaryTextProperties.color = [UIColor.labelColor colorWithAlphaComponent:0.55];
    config.secondaryTextProperties.numberOfLines = 3;
    config.textToSecondaryTextVerticalPadding = 2.0;
    NSDirectionalEdgeInsets m = config.directionalLayoutMargins;
    m.top = 10.0; m.bottom = 10.0;
    config.directionalLayoutMargins = m;
    cell.contentConfiguration = config;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.accessoryView = nil;
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
