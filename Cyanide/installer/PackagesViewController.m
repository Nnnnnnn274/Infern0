//
//  PackagesViewController.m
//  Cyanide
//

#import "PackagesViewController.h"
#import "PackageCatalog.h"
#import "PackageDetailViewController.h"
#import "PackageQueue.h"
#import "../SettingsViewController.h"

static NSString * const kPackageCellID = @"PackageCell";

@interface PackagesViewController ()
@property (nonatomic, copy) NSArray<NSString *> *categories;
@property (nonatomic, copy) NSDictionary<NSString *, NSArray<Package *> *> *packagesByCategory;
@end

@implementation PackagesViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Installer";
    self.navigationItem.title = @"Installer";

    self.categories = [PackageCatalog categoriesInOrder];
    self.packagesByCategory = [PackageCatalog packagesByCategory];

    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 64.0;

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
    [self.tableView reloadData];
}

- (void)queueDidChange:(NSNotification *)note
{
    if (!self.isViewLoaded) return;
    [self.tableView reloadData];
}

#pragma mark - Data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return (NSInteger)self.categories.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)self.packagesByCategory[self.categories[section]].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return self.categories[section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if ([self.categories[section] isEqualToString:@"Beta"]) {
        return @"⚠︎ Work in progress — these may be unstable or change between builds.";
    }
    return nil;
}

- (Package *)packageAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *category = self.categories[indexPath.section];
    return self.packagesByCategory[category][indexPath.row];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kPackageCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:kPackageCellID];
    }

    Package *pkg = [self packageAtIndexPath:indexPath];

    UIImage *icon = [UIImage systemImageNamed:pkg.symbolName];
    cell.imageView.image = icon;
    cell.imageView.preferredSymbolConfiguration =
        [UIImageSymbolConfiguration configurationWithPointSize:24.0 weight:UIImageSymbolWeightRegular];
    cell.imageView.tintColor = self.view.tintColor;

    cell.textLabel.text = pkg.name;
    cell.textLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];

    cell.detailTextLabel.text = pkg.shortDescription;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.detailTextLabel.numberOfLines = 2;

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

@end
