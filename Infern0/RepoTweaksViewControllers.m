#import "RepoTweaksViewControllers.h"
#import "tweaks/RepoTweaks.h"
#import "installer/CYIconBadge.h"
#import <math.h>

static NSString *repo_string_or_empty(id value)
{
    return [value isKindOfClass:NSString.class] ? (NSString *)value : @"";
}

static NSString *repo_l10n_text(id value)
{
    NSString *text = repo_string_or_empty(value);
    return text.length > 0 ? NSLocalizedString(text, nil) : text;
}

static BOOL repo_js_identifier_valid(NSString *name)
{
    if (![name isKindOfClass:NSString.class] || name.length == 0) return NO;
    unichar first = [name characterAtIndex:0];
    if (![[NSCharacterSet letterCharacterSet] characterIsMember:first] && first != '_' && first != '$') return NO;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_$"];
    return [name rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound;
}

static NSMutableDictionary *repo_string_values_dictionary(id raw)
{
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    if (![raw isKindOfClass:NSDictionary.class]) return out;
    [(NSDictionary *)raw enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        (void)stop;
        if ([key isKindOfClass:NSString.class] && [obj isKindOfClass:NSString.class]) out[key] = obj;
    }];
    return out;
}

static UIColor *repo_color_from_hex_string(NSString *hexString)
{
    if (![hexString isKindOfClass:NSString.class]) return UIColor.blackColor;
    NSString *clean = [hexString stringByReplacingOccurrencesOfString:@"#" withString:@""];
    unsigned rgb = 0;
    [[NSScanner scannerWithString:clean] scanHexInt:&rgb];
    return [UIColor colorWithRed:((rgb & 0xFF0000) >> 16) / 255.0
                           green:((rgb & 0x00FF00) >> 8) / 255.0
                            blue:(rgb & 0x0000FF) / 255.0 alpha:1.0];
}

static NSString *repo_hex_string_from_color(UIColor *color)
{
    if (![color isKindOfClass:UIColor.class]) return @"#000000";
    const CGFloat *components = CGColorGetComponents(color.CGColor);
    if (CGColorGetNumberOfComponents(color.CGColor) != 4) return @"#000000";
    return [NSString stringWithFormat:@"#%02lX%02lX%02lX",
            lroundf(components[0] * 255.0), lroundf(components[1] * 255.0), lroundf(components[2] * 255.0)];
}

static void settings_clear_repo_tweak_defaults(NSString *repoURL, NSString *tweakID)
{
    if (![repoURL isKindOfClass:NSString.class] || repoURL.length == 0 ||
        ![tweakID isKindOfClass:NSString.class] || tweakID.length == 0) {
        return;
    }
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d removeObjectForKey:repotweaks_enabled_defaults_key(repoURL, tweakID)];
    [d removeObjectForKey:repotweaks_script_defaults_key(repoURL, tweakID)];
    [d removeObjectForKey:repotweaks_values_defaults_key(repoURL, tweakID)];
    [d synchronize];
    repotweaks_cancel_tweak(repoURL, tweakID);
}

static NSDictionary *settings_repotweaks_caches(void)
{
    id raw = [[NSUserDefaults standardUserDefaults] objectForKey:@"RepoTweaksCaches"];
    return [raw isKindOfClass:NSDictionary.class] ? (NSDictionary *)raw : @{};
}

static NSString * const kSettingsDefaultRepoURL = @"https://zeroxjf.github.io/cyanide-repotweaks.json";

static NSArray<NSString *> *settings_repotweaks_urls(void)
{
    id raw = [[NSUserDefaults standardUserDefaults] objectForKey:@"RepoTweaksURLs"];
    if (![raw isKindOfClass:NSArray.class]) return @[];
    NSMutableArray<NSString *> *urls = [NSMutableArray array];
    for (id value in (NSArray *)raw) {
        if ([value isKindOfClass:NSString.class]) [urls addObject:value];
    }
    return urls;
}

static NSDictionary *settings_repotweaks_repo_for_url(NSString *repoURL)
{
    id repo = repoURL.length ? settings_repotweaks_caches()[repoURL] : nil;
    return [repo isKindOfClass:NSDictionary.class] ? (NSDictionary *)repo : @{};
}

static NSArray<NSDictionary *> *settings_repotweaks_tweaks_for_url(NSString *repoURL)
{
    id raw = settings_repotweaks_repo_for_url(repoURL)[@"tweaks"];
    if (![raw isKindOfClass:NSArray.class]) return @[];
    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    for (id value in (NSArray *)raw) {
        if ([value isKindOfClass:NSDictionary.class]) {
            NSMutableDictionary *tweak = [(NSDictionary *)value mutableCopy];
            if ([repoURL isKindOfClass:NSString.class] && repoURL.length > 0) {
                tweak[@"_repoURL"] = repoURL;
            }
            [out addObject:tweak];
        }
    }
    return out;
}



// =============================================================================
// REPOTWEAKS: Details and Dynamic parameters window
// =============================================================================
@interface RepoTweakDetailController : UITableViewController
@property (nonatomic, strong) NSDictionary *tweak;
@property (nonatomic, strong) NSString *tweakID;
@property (nonatomic, strong) NSString *repoURL;
@property (nonatomic, strong) NSString *rawScript;
@property (nonatomic, strong) NSArray<NSDictionary *> *params;
@property (nonatomic, strong) NSMutableDictionary *values;
@end

@implementation RepoTweakDetailController

- (instancetype)initWithTweak:(NSDictionary *)tweak {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        self.tweak = [tweak isKindOfClass:NSDictionary.class] ? tweak : @{};
        self.tweakID = repo_string_or_empty(self.tweak[@"id"]);
        self.repoURL = repo_string_or_empty(self.tweak[@"_repoURL"]);
        self.title = repo_string_or_empty(self.tweak[@"name"]).length ? repo_string_or_empty(self.tweak[@"name"]) : @"RepoTweak";

        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        // Retrieve js code from repo
        NSString *scriptKey = repotweaks_script_defaults_key(self.repoURL, self.tweakID);
        self.rawScript = [d stringForKey:scriptKey] ?: @"";

        // Retrieve tweaks-specific user saved settings
        NSString *valuesKey = repotweaks_values_defaults_key(self.repoURL, self.tweakID);
        self.values = repo_string_values_dictionary([d dictionaryForKey:valuesKey]);

        // Analyze @param comments in js code
        NSMutableArray *parsedParams = [NSMutableArray array];
        NSArray *lines = [self.rawScript componentsSeparatedByString:@"\n"];
        for (NSString *line in lines) {
            if ([line containsString:@"@param:"]) {
                NSArray *parts = [line componentsSeparatedByString:@"|"];
                if (parts.count >= 4) {
                    NSArray *typeParts = [parts[0] componentsSeparatedByString:@"@param:"];
                    if (typeParts.count < 2) continue;
                    NSString *rawType = typeParts[1];
                    NSString *type = [rawType stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    NSString *varName = [parts[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    NSString *label = [parts[2] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    NSString *defValue = [parts[3] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    if (!repo_js_identifier_valid(varName)) continue;

                    NSMutableDictionary *paramDict = [@{@"type": type, @"varName": varName, @"label": label, @"default": defValue} mutableCopy];
                    if (parts.count >= 5 && ([type isEqualToString:@"slider"] || [type isEqualToString:@"number"])) {
                        NSString *rangeStr = [parts[4] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                        NSArray *rangeParts = [rangeStr componentsSeparatedByString:@"-"];
                        if (rangeParts.count == 2) {
                            paramDict[@"min"] = rangeParts[0];
                            paramDict[@"max"] = rangeParts[1];
                        }
                    }
                    [parsedParams addObject:paramDict];
                    if (!self.values[varName]) {
                        self.values[varName] = defValue; //default values if new
                    }
                }
            }
        }
        self.params = parsedParams;
    }
    return self;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.params.count > 0 ? 3 : 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 2; //description and version
    if (section == 1) return 1; //status (active or not)
    return self.params.count;   //JS dynamic parameters
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (section == 0) return CYSectionHeaderView(repo_l10n_text(@"Tweak Infos"));
    if (section == 1) return CYSectionHeaderView(repo_l10n_text(@"Tweak Status"));
    return CYSectionHeaderView(repo_l10n_text(@"Personalization Options"));
}
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section { return 46.0; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"info-cell"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (indexPath.row == 0) {
            cell.textLabel.text = repo_l10n_text(@"Description");
            cell.detailTextLabel.text = repo_string_or_empty(self.tweak[@"description"]);
            cell.detailTextLabel.numberOfLines = 0;
        } else {
            cell.textLabel.text = repo_l10n_text(@"Version");
            cell.detailTextLabel.text = repo_string_or_empty(self.tweak[@"version"]);
        }
        return cell;
    }

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];

    if (indexPath.section == 1) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"toggle-cell"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = repo_l10n_text(@"Enable Tweak");

        UISwitch *sw = [[UISwitch alloc] init];
        NSString *toggleKey = repotweaks_enabled_defaults_key(self.repoURL, self.tweakID);
        sw.on = [d boolForKey:toggleKey];

        UIAction *action = [UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
            [d setBool:sw.isOn forKey:toggleKey];
            [d synchronize];
            if (!sw.isOn) {
                repotweaks_cancel_tweak(self.repoURL, self.tweakID);
            }
        }];
        [sw addAction:action forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        return cell;
    }

    // Dynamic parameters section (same as QuickLoader)
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"param-cell"];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    NSDictionary *param = self.params[indexPath.row];
    cell.textLabel.text = param[@"label"];

    NSString *varName = param[@"varName"];
    NSString *pType = param[@"type"];
    NSString *currentValue = repo_string_or_empty(self.values[varName]);

    NSString *valuesKey = repotweaks_values_defaults_key(self.repoURL, self.tweakID);

    if ([pType isEqualToString:@"switch"]) {
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = [currentValue isEqualToString:@"true"];
        UIAction *action = [UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
            self.values[varName] = sw.isOn ? @"true" : @"false";
            [d setObject:self.values forKey:valuesKey];
            [d synchronize];
        }];
        [sw addAction:action forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    }
    else if ([pType isEqualToString:@"text"]) {
        UITextField *tf = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 150, 30)];
        tf.textAlignment = NSTextAlignmentRight;
        tf.textColor = UIColor.secondaryLabelColor;
        tf.text = currentValue;
        UIAction *action = [UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
            self.values[varName] = tf.text;
            [d setObject:self.values forKey:valuesKey];
            [d synchronize];
        }];
        [tf addAction:action forControlEvents:UIControlEventEditingChanged];
        cell.accessoryView = tf;
    }
    else if ([pType isEqualToString:@"color"]) {
        UIColorWell *colorWell = [[UIColorWell alloc] init];
        colorWell.translatesAutoresizingMaskIntoConstraints = NO;
        //call to convert color
        colorWell.selectedColor = repo_color_from_hex_string(currentValue ?: @"#FF0000");

        UIAction *action = [UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
            colorWell.title = param[@"label"];
            self.values[varName] = repo_hex_string_from_color(colorWell.selectedColor);
            [d setObject:self.values forKey:valuesKey];
            [d synchronize];
        }];
        [colorWell addAction:action forControlEvents:UIControlEventValueChanged];

        [cell.contentView addSubview:colorWell];
        [NSLayoutConstraint activateConstraints:@[
            [colorWell.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
            [colorWell.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [colorWell.widthAnchor constraintEqualToConstant:32.0],
            [colorWell.heightAnchor constraintEqualToConstant:32.0]
        ]];
    }
    else if ([pType isEqualToString:@"slider"] || [pType isEqualToString:@"number"]) {
        UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectMake(0, 0, 220, 30)];
        stack.axis = UILayoutConstraintAxisHorizontal;
        stack.spacing = 10;
        stack.alignment = UIStackViewAlignmentCenter;

        UISlider *slider = [[UISlider alloc] init];
        slider.minimumValue = param[@"min"] ? [param[@"min"] floatValue] : 0.0;
        slider.maximumValue = param[@"max"] ? [param[@"max"] floatValue] : 1.0;

        //if there is none, retrieve default value
        float defVal = param[@"default"] ? [param[@"default"] floatValue] : slider.minimumValue;
        slider.value = currentValue ? [currentValue floatValue] : defVal;

        UILabel *valLabel = [[UILabel alloc] init];
        valLabel.textColor = [UIColor secondaryLabelColor];
        valLabel.font = [UIFont systemFontOfSize:14];
        [valLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

        void (^updateLabelText)(float) = ^(float value) {
            if (fabs(value - defVal) < 0.01) {
                valLabel.text = [NSString stringWithFormat:@"%.2f (Def)", value];
            } else {
                valLabel.text = [NSString stringWithFormat:@"%.2f", value];
            }
        };

        updateLabelText(slider.value);

        [stack addArrangedSubview:slider];
        [stack addArrangedSubview:valLabel];

        UIAction *updateTextAction = [UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
            updateLabelText(slider.value);
        }];
        [slider addAction:updateTextAction forControlEvents:UIControlEventValueChanged];

        UIAction *saveAction = [UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
            self.values[varName] = [NSString stringWithFormat:@"%.2f", slider.value];
            [d setObject:self.values forKey:valuesKey];
            [d synchronize];
        }];
        [slider addAction:saveAction forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];

        cell.accessoryView = stack;
    }

    return cell;
}

@end


// ==========================================
// REPOTWEAKS: REPO DETAIL VIEW CONTROLLER
// ==========================================
@interface RepoDetailController : UITableViewController
@property (nonatomic, strong) NSString *repoURL;
@end

@implementation RepoDetailController

- (void)viewDidLoad {
    [super viewDidLoad];
    NSDictionary *repo = settings_repotweaks_repo_for_url(self.repoURL);
    NSString *repoName = repo_string_or_empty(repo[@"repoName"]);
    self.title = repoName.length ? repoName : repo_l10n_text(@"Repository");
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2; // Section 0: Tweaks, Section 1: Delete
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (section == 0) {
        NSDictionary *repo = settings_repotweaks_repo_for_url(self.repoURL);
        NSString *author = repo_string_or_empty(repo[@"author"]);
        return CYSectionHeaderView([NSString stringWithFormat:repo_l10n_text(@"By %@"), author.length ? author : repo_l10n_text(@"Unknown")]);
    }
    return nil;
}
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return section == 0 ? UITableViewAutomaticDimension : 0.0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 1) return 1;
    return settings_repotweaks_tweaks_for_url(self.repoURL).count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];

    // The Delete Button
    if (indexPath.section == 1) {
        cell.textLabel.text = repo_l10n_text(@"Delete Repository");
        cell.textLabel.textColor = [UIColor systemRedColor];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        return cell;
    }

    // The Tweaks
    NSArray *tweaks = settings_repotweaks_tweaks_for_url(self.repoURL);
    if (indexPath.row >= (NSInteger)tweaks.count) return cell;
    NSDictionary *tweak = tweaks[indexPath.row];

    cell.textLabel.text = repo_string_or_empty(tweak[@"name"]);
    cell.detailTextLabel.text = repo_string_or_empty(tweak[@"description"]);
    cell.detailTextLabel.numberOfLines = 0;

    UISwitch *toggle = [[UISwitch alloc] init];
    toggle.tag = indexPath.row; // Link the switch to the tweak array index
    NSString *tweakID = repo_string_or_empty(tweak[@"id"]);
    NSString *key = repotweaks_enabled_defaults_key(self.repoURL, tweakID);
    toggle.on = [[NSUserDefaults standardUserDefaults] boolForKey:key];
    [toggle addTarget:self action:@selector(toggled:) forControlEvents:UIControlEventValueChanged];

    cell.accessoryView = toggle;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)toggled:(UISwitch *)sender {
    NSArray *tweaks = settings_repotweaks_tweaks_for_url(self.repoURL);
    if (sender.tag < 0 || sender.tag >= (NSInteger)tweaks.count) return;
    NSDictionary *tweak = tweaks[sender.tag];
    NSString *tweakID = repo_string_or_empty(tweak[@"id"]);
    if (tweakID.length == 0) return;
    NSString *key = repotweaks_enabled_defaults_key(self.repoURL, tweakID);
    [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:key];
    [[NSUserDefaults standardUserDefaults] synchronize];
    if (!sender.on) {
        repotweaks_cancel_tweak(self.repoURL, tweakID);
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0) {
        NSArray *tweaks = settings_repotweaks_tweaks_for_url(self.repoURL);
        if (indexPath.row >= (NSInteger)tweaks.count) return;
        RepoTweakDetailController *detailVC = [[RepoTweakDetailController alloc] initWithTweak:tweaks[indexPath.row]];
        [self.navigationController pushViewController:detailVC animated:YES];
        return;
    }

    // Handle Repo Deletion
    if (indexPath.section == 1) {
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        for (NSDictionary *tweak in settings_repotweaks_tweaks_for_url(self.repoURL)) {
            settings_clear_repo_tweak_defaults(self.repoURL, repo_string_or_empty(tweak[@"id"]));
        }

        NSMutableArray *urls = [settings_repotweaks_urls() mutableCopy];
        if (!urls) urls = [NSMutableArray array];
        [urls removeObject:self.repoURL];
        [d setObject:urls forKey:@"RepoTweaksURLs"];

        NSMutableDictionary *caches = [settings_repotweaks_caches() mutableCopy];
        if (!caches) caches = [NSMutableDictionary dictionary];
        [caches removeObjectForKey:self.repoURL];
        [d setObject:caches forKey:@"RepoTweaksCaches"];
        [d synchronize];

        [self.navigationController popViewControllerAnimated:YES]; // Slide back to main menu
    }
}
@end






// ==========================================
// REPOTWEAKS: REPO MANAGER CONTROLLER (the main page)
// ==========================================
@interface RepoManagerController ()
@property (nonatomic, strong) NSArray *flattenedTweaks;
@end

@implementation RepoManagerController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"RepoTweaks";

    // + and refresh buttons (menu bar)
    UIBarButtonItem *addButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addRepo)];
    UIBarButtonItem *refreshButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refreshAll)];
    self.navigationItem.rightBarButtonItems = @[addButton, refreshButton];

    repotweaks_seed_default_repos();
    if ([settings_repotweaks_urls() containsObject:kSettingsDefaultRepoURL]) {
        NSDictionary *repo = settings_repotweaks_repo_for_url(kSettingsDefaultRepoURL);
        NSArray *tweaks = repo[@"tweaks"];
        if (![tweaks isKindOfClass:NSArray.class] || tweaks.count == 0) {
            __weak typeof(self) weakSelf = self;
            repotweaks_refresh_repo(kSettingsDefaultRepoURL, ^(BOOL success, NSString *message) {
                (void)success;
                (void)message;
                [weakSelf updateData];
            });
        }
    }
}

// auto refresh (there was a bug and I had to go back to the page and it would not refresh the UI without this)
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateData];
}

- (void)updateData {
    NSMutableArray *tempTweaks = [NSMutableArray array];
    for (NSString *url in settings_repotweaks_urls()) {
        [tempTweaks addObjectsFromArray:settings_repotweaks_tweaks_for_url(url)];
    }
    self.flattenedTweaks = tempTweaks;
    [self.tableView reloadData];
}

- (void)addRepo {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:repo_l10n_text(@"Add Source") message:repo_l10n_text(@"Paste the RAW link to your packages.json") preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) { textField.placeholder = @"https://raw.githubusercontent.com/..."; }];
    [alert addAction:[UIAlertAction actionWithTitle:repo_l10n_text(@"Add") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *url = alert.textFields.firstObject.text;
        if (url.length > 0) {
            repotweaks_refresh_repo(url, ^(BOOL success, NSString *message) {
                [self updateData];
                if (!success) {
        UIAlertController *err = [UIAlertController alertControllerWithTitle:repo_l10n_text(@"Source Failed")
                                                                     message:message ?: repo_l10n_text(@"Could not refresh that repository.")
                                                              preferredStyle:UIAlertControllerStyleAlert];
                    [err addAction:[UIAlertAction actionWithTitle:repo_l10n_text(@"OK") style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:err animated:YES completion:nil];
                }
            });
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:repo_l10n_text(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)refreshAll {
    NSArray *urls = settings_repotweaks_urls();
    if (urls.count == 0) return;

    // Refresh Alert
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:repo_l10n_text(@"Refreshing Sources")
                                                                   message:repo_l10n_text(@"Nuking old scripts and downloading the latest...")
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:alert animated:YES completion:nil];

    // track download status
    dispatch_group_t group = dispatch_group_create();

    for (NSString *url in urls) {
        dispatch_group_enter(group);
        repotweaks_refresh_repo(url, ^(BOOL success, NSString *message) {
            dispatch_group_leave(group);
        });
    }

    //dismiss alert and refresh UI on success
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        [alert dismissViewControllerAnimated:YES completion:^{
            [self updateData];
        }];
    });
}

// Native tweak sections
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return CYSectionHeaderView(repo_l10n_text(section == 0 ? @"Sources" : @"All Tweaks"));
}
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section { return 46.0; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return settings_repotweaks_urls().count;
    return self.flattenedTweaks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];

    if (indexPath.section == 0) {
        NSArray *urls = settings_repotweaks_urls();
        if (indexPath.row >= (NSInteger)urls.count) return cell;
        NSString *url = urls[indexPath.row];
        NSDictionary *repo = settings_repotweaks_repo_for_url(url);

        NSString *repoName = repo_string_or_empty(repo[@"repoName"]);
        cell.textLabel.text = repoName.length ? repoName : @"Unknown Repo";
        cell.detailTextLabel.text = url;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        if (indexPath.row >= (NSInteger)self.flattenedTweaks.count) return cell;
        NSDictionary *tweak = self.flattenedTweaks[indexPath.row];
        cell.textLabel.text = repo_string_or_empty(tweak[@"name"]);
        cell.detailTextLabel.text = repo_string_or_empty(tweak[@"description"]);
        cell.detailTextLabel.numberOfLines = 0;

        UISwitch *toggle = [[UISwitch alloc] init];
        toggle.tag = indexPath.row;
        NSString *tweakID = repo_string_or_empty(tweak[@"id"]);
        NSString *repoURL = repo_string_or_empty(tweak[@"_repoURL"]);
        NSString *key = repotweaks_enabled_defaults_key(repoURL, tweakID);
        toggle.on = [d boolForKey:key];
        [toggle addTarget:self action:@selector(toggled:) forControlEvents:UIControlEventValueChanged];

        cell.accessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    return cell;
}

- (void)toggled:(UISwitch *)sender {
    if (sender.tag < 0 || sender.tag >= (NSInteger)self.flattenedTweaks.count) return;
    NSDictionary *tweak = self.flattenedTweaks[sender.tag];
    NSString *tweakID = repo_string_or_empty(tweak[@"id"]);
    NSString *repoURL = repo_string_or_empty(tweak[@"_repoURL"]);
    if (tweakID.length == 0) return;
    NSString *key = repotweaks_enabled_defaults_key(repoURL, tweakID);
    [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:key];
    [[NSUserDefaults standardUserDefaults] synchronize];
    if (!sender.on) {
        repotweaks_cancel_tweak(repoURL, tweakID);
    }
}

//swipe to delete logic
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 0; //only let user swipe to delete sources
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete && indexPath.section == 0) {
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        NSMutableArray *urls = [settings_repotweaks_urls() mutableCopy];
        if (!urls) urls = [NSMutableArray array];
        if (indexPath.row >= (NSInteger)urls.count) return;
        NSString *urlToRemove = urls[indexPath.row];
        for (NSDictionary *tweak in settings_repotweaks_tweaks_for_url(urlToRemove)) {
            settings_clear_repo_tweak_defaults(urlToRemove, repo_string_or_empty(tweak[@"id"]));
        }

        [urls removeObjectAtIndex:indexPath.row];
        [d setObject:urls forKey:@"RepoTweaksURLs"];

        NSMutableDictionary *caches = [settings_repotweaks_caches() mutableCopy];
        if (!caches) caches = [NSMutableDictionary dictionary];
        [caches removeObjectForKey:urlToRemove];
        [d setObject:caches forKey:@"RepoTweaksCaches"];
        [d synchronize];

        [self updateData]; //refreshes the ui
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    // Section 0: press on the repo, it lists all tweaks
    if (indexPath.section == 0) {
        NSArray *urls = settings_repotweaks_urls();
        if (indexPath.row >= (NSInteger)urls.count) return;
        RepoDetailController *detailVC = [[RepoDetailController alloc] initWithStyle:UITableViewStyleGrouped];
        detailVC.repoURL = urls[indexPath.row];
        [self.navigationController pushViewController:detailVC animated:YES];
    }
    // Section 1: press on a tweak, it lists all dynamic parameters
    else if (indexPath.section == 1) {
        if (indexPath.row >= (NSInteger)self.flattenedTweaks.count) return;
        NSDictionary *tweak = self.flattenedTweaks[indexPath.row];

        RepoTweakDetailController *detailVC = [[RepoTweakDetailController alloc] initWithTweak:tweak];
        [self.navigationController pushViewController:detailVC animated:YES];
    }
}
@end
