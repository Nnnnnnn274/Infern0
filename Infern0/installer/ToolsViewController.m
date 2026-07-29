//
//  ToolsViewController.m
//  Infern0
//

#import "ToolsViewController.h"
#import "Package.h"
#import "PackageCatalog.h"
#import "PackageDetailViewController.h"
#import "CYIconBadge.h"
#import <math.h>

typedef NS_ENUM(NSInteger, ToolsScope) {
    ToolsScopeUtilities = 0,
    ToolsScopeLara,
};

@interface ToolsViewController ()
@property (nonatomic, copy) NSArray<Package *> *tools;
@property (nonatomic, strong) UISegmentedControl *scopeControl;
@property (nonatomic, strong) UIView *toolsHeader;
@property (nonatomic, strong) UIView *heroCard;
@property (nonatomic, strong) CAGradientLayer *heroGradient;
@property (nonatomic, strong) UILabel *heroSubtitle;
@end

@implementation ToolsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Tools";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    CYConfigureTableView(self.tableView);
    CYApplyNavigationStyle(self.navigationController);
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 82.0;
    self.tableView.separatorInset = UIEdgeInsetsMake(0.0, 68.0, 0.0, 18.0);

    self.scopeControl = [[UISegmentedControl alloc] initWithItems:@[@"Utilities", @"Lara"]];
    self.scopeControl.selectedSegmentIndex = ToolsScopeUtilities;
    CYConfigureSegmentedControl(self.scopeControl);
    [self.scopeControl addTarget:self action:@selector(scopeChanged:) forControlEvents:UIControlEventValueChanged];

    if (CYUsesClassicInterfaceStyle()) {
        self.tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
        self.tableView.rowHeight = 74.0;
        self.navigationItem.titleView = self.scopeControl;
    } else {
        [self buildToolsHeader];
    }
    [self reloadTools];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGFloat width = self.tableView.bounds.size.width;
    if (width <= 0.0 || !self.toolsHeader) return;
    if (fabs(self.toolsHeader.frame.size.width - width) < 0.5 &&
        self.heroCard.bounds.size.width > 0.0) return;
    self.toolsHeader.frame = CGRectMake(0.0, 0.0, width, 174.0);
    self.heroCard.frame = CGRectMake(16.0, 8.0, width - 32.0, 102.0);
    self.heroGradient.frame = self.heroCard.bounds;
    [self.heroCard viewWithTag:4301].frame = CGRectMake(18.0, 23.0, 48.0, 48.0);
    [self.heroCard viewWithTag:4302].frame = CGRectMake(82.0, 20.0, self.heroCard.bounds.size.width - 100.0, 16.0);
    [self.heroCard viewWithTag:4303].frame = CGRectMake(82.0, 36.0, self.heroCard.bounds.size.width - 100.0, 27.0);
    [self.heroCard viewWithTag:4304].frame = CGRectMake(82.0, 65.0, self.heroCard.bounds.size.width - 100.0, 18.0);
    self.scopeControl.frame = CGRectMake(16.0, 122.0, width - 32.0, 36.0);
    self.tableView.tableHeaderView = self.toolsHeader;
}

- (void)buildToolsHeader
{
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, self.tableView.bounds.size.width, 174.0)];
    UIView *card = [[UIView alloc] init];
    CYApplyCardStyle(card, 24.0);
    card.clipsToBounds = YES;
    card.layer.borderColor = [UIColor.whiteColor colorWithAlphaComponent:0.14].CGColor;
    [header addSubview:card];

    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.colors = CYHeroGradientLayerColors();
    gradient.startPoint = CGPointMake(0.0, 0.0);
    gradient.endPoint = CGPointMake(1.0, 1.0);
    [card.layer insertSublayer:gradient atIndex:0];

    UIImageView *icon = [[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:@"wrench.and.screwdriver.fill"
               withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22.0
                                                                                  weight:UIImageSymbolWeightSemibold]]];
    icon.tag = 4301;
    icon.frame = CGRectMake(18.0, 23.0, 48.0, 48.0);
    icon.tintColor = UIColor.whiteColor;
    icon.contentMode = UIViewContentModeCenter;
    icon.backgroundColor = [UIColor.whiteColor colorWithAlphaComponent:0.12];
    icon.layer.cornerRadius = 15.0;
    icon.layer.cornerCurve = kCACornerCurveContinuous;
    [card addSubview:icon];

    UILabel *eyebrow = [[UILabel alloc] initWithFrame:CGRectMake(82.0, 20.0, 220.0, 16.0)];
    eyebrow.tag = 4302;
    eyebrow.text = @"DIRECT TOOLKIT";
    eyebrow.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightHeavy];
    eyebrow.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.72];
    [card addSubview:eyebrow];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(82.0, 36.0, 250.0, 27.0)];
    title.tag = 4303;
    title.text = @"Utilities, on demand";
    title.font = [UIFont systemFontOfSize:21.0 weight:UIFontWeightBold];
    title.textColor = UIColor.whiteColor;
    title.adjustsFontSizeToFitWidth = YES;
    title.minimumScaleFactor = 0.78;
    [card addSubview:title];

    UILabel *subtitle = [[UILabel alloc] initWithFrame:CGRectMake(82.0, 65.0, 250.0, 18.0)];
    subtitle.tag = 4304;
    subtitle.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightMedium];
    subtitle.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.68];
    [card addSubview:subtitle];

    self.toolsHeader = header;
    self.heroCard = card;
    self.heroGradient = gradient;
    self.heroSubtitle = subtitle;
    [header addSubview:self.scopeControl];
    self.tableView.tableHeaderView = header;
    [self viewDidLayoutSubviews];
    CYAnimateEntrance(card);
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
    [self updateToolsHeader];
    [self updateEmptyState];
}

- (void)updateToolsHeader
{
    NSInteger utilities = 0;
    NSInteger lara = 0;
    for (Package *package in self.tools) {
        if ([self isLaraPackage:package]) lara++;
        else utilities++;
    }
    self.heroSubtitle.text = [NSString stringWithFormat:@"%ld utilities  •  %ld Lara tools",
                              (long)utilities, (long)lara];
}

- (void)updateEmptyState
{
    if (self.visibleTools.count > 0) {
        self.tableView.backgroundView = nil;
        return;
    }
    UILabel *label = [[UILabel alloc] initWithFrame:self.tableView.bounds];
    label.text = @"No tools in this collection";
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = UIColor.secondaryLabelColor;
    label.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
    self.tableView.backgroundView = label;
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
    [self updateEmptyState];
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

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    (void)tableView;
    (void)section;
    if (CYUsesClassicInterfaceStyle()) return nil;
    return CYSectionHeaderView(self.scopeControl.selectedSegmentIndex == ToolsScopeLara
        ? @"Lara Tools"
        : @"Direct Utilities");
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    (void)tableView;
    (void)section;
    if (!CYUsesClassicInterfaceStyle()) return nil;
    return self.scopeControl.selectedSegmentIndex == ToolsScopeLara
        ? @"Lara Tools"
        : @"Direct Utilities";
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    (void)tableView;
    (void)section;
    return CYUsesClassicInterfaceStyle() ? UITableViewAutomaticDimension : 46.0;
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
    if (CYUsesClassicInterfaceStyle()) {
        cell.contentConfiguration = nil;
        cell.textLabel.text = package.name;
        cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        cell.detailTextLabel.text = package.shortDescription;
        cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
        cell.detailTextLabel.numberOfLines = 2;
        cell.imageView.image = [UIImage systemImageNamed:package.symbolName ?: @"wrench.and.screwdriver.fill"];
        cell.imageView.tintColor = CYAccentColor();
        cell.backgroundColor = nil;
        return cell;
    }
    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.image = CYIconBadgeImage(package.symbolName ?: @"wrench.and.screwdriver.fill",
                                     CYAccentColor(), 38.0);
    content.imageProperties.reservedLayoutSize = CGSizeMake(38.0, 38.0);
    content.imageToTextPadding = 12.0;
    content.text = package.name;
    content.textProperties.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    content.secondaryText = package.shortDescription;
    content.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    content.secondaryTextProperties.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular];
    content.secondaryTextProperties.numberOfLines = 2;
    content.textToSecondaryTextVerticalPadding = 3.0;
    content.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(11.0, 0.0, 11.0, 0.0);
    cell.contentConfiguration = content;
    cell.backgroundColor = CYSurfaceColor();
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
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
