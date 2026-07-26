//
//  ToolsViewController.m
//  Infern0
//

#import "ToolsViewController.h"
#import "Package.h"
#import "PackageCatalog.h"
#import "PackageDetailViewController.h"
#import "CYIconBadge.h"

@interface ToolsViewController ()
@property (nonatomic, copy) NSArray<Package *> *tools;
@end

@implementation ToolsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Tools";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.tableView.rowHeight = 74.0;

    [self reloadTools];
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
    return self.tools;
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
    return @"Direct Utilities";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    (void)tableView;
    (void)section;
    return @"These are native Infern0 utilities. They run directly and are not installed, queued, or applied as tweak packages.";
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
