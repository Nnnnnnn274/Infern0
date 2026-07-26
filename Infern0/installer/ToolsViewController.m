//
//  ToolsViewController.m
//  Infern0
//

#import "ToolsViewController.h"
#import "Package.h"
#import "PackageCatalog.h"
#import "PackageDetailViewController.h"
#import "CYIconBadge.h"

typedef NS_ENUM(NSInteger, ToolsScope) {
    ToolsScopeUtilities = 0,
    ToolsScopeLara,
};

@interface ToolsViewController ()
@property (nonatomic, copy) NSArray<Package *> *tools;
@property (nonatomic, strong) UISegmentedControl *scopeControl;
@end

@implementation ToolsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Tools";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.tableView.rowHeight = 74.0;

    self.scopeControl = [[UISegmentedControl alloc] initWithItems:@[@"Utilities", @"Lara"]];
    self.scopeControl.selectedSegmentIndex = ToolsScopeUtilities;
    [self.scopeControl addTarget:self action:@selector(scopeChanged:) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = self.scopeControl;

    [self reloadTools];
}

- (BOOL)isLaraPackage:(Package *)package
{
    return [package.identifier hasPrefix:@"com.darksword.lara-"];
}

- (void)reloadTools
{
    NSPredicate *directOnly = [NSPredicate predicateWithBlock:^BOOL(Package *package, NSDictionary *bindings) {
        (void)bindings;
        return package.kind == PackageInstallKindDirectTool;
    }];
    self.tools = [[[PackageCatalog allPackages] filteredArrayUsingPredicate:directOnly]
        sortedArrayUsingComparator:^NSComparisonResult(Package *a, Package *b) {
            return [a.name localizedCaseInsensitiveCompare:b.name];
        }];
    [self.tableView reloadData];
}

- (NSArray<Package *> *)visibleTools
{
    BOOL wantsLara = self.scopeControl.selectedSegmentIndex == ToolsScopeLara;
    return [self.tools filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(Package *package, NSDictionary *bindings) {
        (void)bindings;
        return [self isLaraPackage:package] == wantsLara;
    }]];
}

- (void)scopeChanged:(UISegmentedControl *)sender
{
    (void)sender;
    CYSelectionHaptic();
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    (void)tableView;
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    (void)tableView;
    (void)section;
    return self.visibleTools.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    (void)tableView;
    (void)section;
    return self.scopeControl.selectedSegmentIndex == ToolsScopeLara
        ? @"Lara Tools"
        : @"Direct Utilities";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    (void)tableView;
    (void)section;
    return self.scopeControl.selectedSegmentIndex == ToolsScopeLara
        ? @"Lara features share Infern0's kernel session and safe write engine. They no longer launch Lara's bundled Darksword exploit."
        : @"These are manual utilities. They run directly and are not installed, queued, or applied as tweak packages.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *reuse = @"DirectToolCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuse];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }

    Package *package = self.visibleTools[indexPath.row];
    cell.textLabel.text = package.name;
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    cell.detailTextLabel.text = package.shortDescription;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.detailTextLabel.numberOfLines = 2;
    cell.imageView.image = [UIImage systemImageNamed:package.symbolName ?: @"wrench.and.screwdriver.fill"];
    cell.imageView.tintColor = CYAccentColor();
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    CYSelectionHaptic();
    Package *package = self.visibleTools[indexPath.row];
    PackageDetailViewController *detail = [[PackageDetailViewController alloc] initWithPackage:package];
    [self.navigationController pushViewController:detail animated:YES];
}

@end
