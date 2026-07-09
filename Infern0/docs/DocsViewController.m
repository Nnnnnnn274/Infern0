//
//  DocsViewController.m
//  infern0
//

#import "DocsViewController.h"

#pragma mark - DocsSectionHeader

@interface DocsSectionHeader : UITableViewHeaderFooterView
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
- (void)configureWithSymbol:(NSString *)symbolName tint:(UIColor *)tint title:(NSString *)title;
@end

@implementation DocsSectionHeader

- (instancetype)initWithReuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithReuseIdentifier:reuseIdentifier];
    if (!self) return nil;

    UIView *bg = [[UIView alloc] init];
    bg.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.backgroundView = bg;

    _iconView = [[UIImageView alloc] init];
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconView.contentMode = UIViewContentModeScaleAspectFit;
    _iconView.tintColor = UIColor.labelColor;
    [self.contentView addSubview:_iconView];

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    _titleLabel.adjustsFontForContentSizeCategory = YES;
    _titleLabel.textColor = UIColor.labelColor;
    _titleLabel.numberOfLines = 0;
    [self.contentView addSubview:_titleLabel];

    [_iconView setContentHuggingPriority:UILayoutPriorityRequired
                                 forAxis:UILayoutConstraintAxisHorizontal];
    [_iconView setContentCompressionResistancePriority:UILayoutPriorityRequired
                                               forAxis:UILayoutConstraintAxisHorizontal];

    [NSLayoutConstraint activateConstraints:@[
        [_iconView.leadingAnchor    constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor],
        [_iconView.centerYAnchor    constraintEqualToAnchor:_titleLabel.firstBaselineAnchor constant:-6.0],

        [_titleLabel.leadingAnchor  constraintEqualToAnchor:_iconView.trailingAnchor constant:10.0],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],
        [_titleLabel.topAnchor      constraintEqualToAnchor:self.contentView.topAnchor    constant:14.0],
        [_titleLabel.bottomAnchor   constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6.0],
    ]];
    return self;
}

- (void)configureWithSymbol:(NSString *)symbolName tint:(UIColor *)tint title:(NSString *)title
{
    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithFont:self.titleLabel.font
                                                    scale:UIImageSymbolScaleSmall];
    self.iconView.image = [UIImage systemImageNamed:symbolName withConfiguration:cfg];
    self.iconView.tintColor = tint;
    self.titleLabel.text = title;
}

@end

#pragma mark - DocsFooter

@interface DocsFooter : UITableViewHeaderFooterView
@property (nonatomic, strong) UILabel *body;
- (void)configureWithText:(NSString *)text;
@end

@implementation DocsFooter

- (instancetype)initWithReuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithReuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    UIView *bg = [[UIView alloc] init];
    bg.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.backgroundView = bg;

    _body = [[UILabel alloc] init];
    _body.translatesAutoresizingMaskIntoConstraints = NO;
    _body.numberOfLines = 0;
    _body.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    _body.adjustsFontForContentSizeCategory = YES;
    _body.textColor = UIColor.secondaryLabelColor;
    [self.contentView addSubview:_body];

    [NSLayoutConstraint activateConstraints:@[
        [_body.leadingAnchor  constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor],
        [_body.trailingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],
        [_body.topAnchor      constraintEqualToAnchor:self.contentView.topAnchor    constant:8.0],
        [_body.bottomAnchor   constraintEqualToAnchor:self.contentView.bottomAnchor constant:-18.0],
    ]];
    return self;
}

- (void)configureWithText:(NSString *)text { self.body.text = text; }

@end

#pragma mark - DocsCell

@interface DocsCell : UITableViewCell
@property (nonatomic, strong) UITextView *body;
@property (nonatomic, strong) UIView *codeBackground;
@property (nonatomic, strong) UILabel *filenameLabel;
@property (nonatomic, strong) UIView *divider;
@property (nonatomic, strong) NSLayoutConstraint *dividerHeight;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *proseConstraints;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *codeConstraints;
- (void)configureProseWithText:(NSString *)text;
- (void)configureCodeWithText:(NSString *)text filename:(NSString *)filename;
@end

@implementation DocsCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;

    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.contentView.backgroundColor = UIColor.clearColor;

    _codeBackground = [[UIView alloc] init];
    _codeBackground.translatesAutoresizingMaskIntoConstraints = NO;
    _codeBackground.backgroundColor = UIColor.tertiarySystemGroupedBackgroundColor;
    _codeBackground.layer.cornerRadius = 10.0;
    _codeBackground.layer.cornerCurve = kCACornerCurveContinuous;
    _codeBackground.layer.masksToBounds = YES;
    _codeBackground.hidden = YES;
    [self.contentView addSubview:_codeBackground];

    _filenameLabel = [[UILabel alloc] init];
    _filenameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _filenameLabel.font = [UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightMedium];
    _filenameLabel.textColor = UIColor.secondaryLabelColor;
    [_codeBackground addSubview:_filenameLabel];

    _divider = [[UIView alloc] init];
    _divider.translatesAutoresizingMaskIntoConstraints = NO;
    _divider.backgroundColor = UIColor.separatorColor;
    [_codeBackground addSubview:_divider];
    _dividerHeight = [_divider.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale];

    _body = [[UITextView alloc] init];
    _body.translatesAutoresizingMaskIntoConstraints = NO;
    _body.scrollEnabled = NO;
    _body.editable = NO;
    _body.backgroundColor = UIColor.clearColor;
    _body.textContainerInset = UIEdgeInsetsZero;
    _body.textContainer.lineFragmentPadding = 0.0;
    _body.dataDetectorTypes = UIDataDetectorTypeLink;
    _body.linkTextAttributes = @{ NSForegroundColorAttributeName: UIColor.systemRedColor };
    _body.adjustsFontForContentSizeCategory = YES;
    _body.alwaysBounceVertical = NO;
    [self.contentView addSubview:_body];

    _proseConstraints = @[
        [_body.topAnchor      constraintEqualToAnchor:self.contentView.topAnchor      constant:9.0],
        [_body.bottomAnchor   constraintEqualToAnchor:self.contentView.bottomAnchor   constant:-9.0],
        [_body.leadingAnchor  constraintEqualToAnchor:self.contentView.leadingAnchor  constant:18.0],
        [_body.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-18.0],
    ];
    _codeConstraints = @[
        [_codeBackground.topAnchor      constraintEqualToAnchor:self.contentView.topAnchor      constant:6.0],
        [_codeBackground.bottomAnchor   constraintEqualToAnchor:self.contentView.bottomAnchor   constant:-6.0],
        [_codeBackground.leadingAnchor  constraintEqualToAnchor:self.contentView.leadingAnchor  constant:12.0],
        [_codeBackground.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12.0],

        [_filenameLabel.topAnchor              constraintEqualToAnchor:_codeBackground.topAnchor      constant:9.0],
        [_filenameLabel.leadingAnchor          constraintEqualToAnchor:_codeBackground.leadingAnchor  constant:14.0],
        [_filenameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_codeBackground.trailingAnchor constant:-14.0],

        [_divider.topAnchor       constraintEqualToAnchor:_filenameLabel.bottomAnchor constant:8.0],
        [_divider.leadingAnchor   constraintEqualToAnchor:_codeBackground.leadingAnchor],
        [_divider.trailingAnchor  constraintEqualToAnchor:_codeBackground.trailingAnchor],
        _dividerHeight,

        [_body.topAnchor      constraintEqualToAnchor:_divider.bottomAnchor           constant:10.0],
        [_body.bottomAnchor   constraintEqualToAnchor:_codeBackground.bottomAnchor    constant:-12.0],
        [_body.leadingAnchor  constraintEqualToAnchor:_codeBackground.leadingAnchor   constant:14.0],
        [_body.trailingAnchor constraintEqualToAnchor:_codeBackground.trailingAnchor  constant:-14.0],
    ];
    return self;
}

- (void)configureProseWithText:(NSString *)text
{
    [NSLayoutConstraint deactivateConstraints:_codeConstraints];
    [NSLayoutConstraint activateConstraints:_proseConstraints];
    _codeBackground.hidden = YES;
    _body.textContainer.maximumNumberOfLines = 0;
    _body.textContainer.lineBreakMode = NSLineBreakByWordWrapping;

    NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
    para.lineSpacing = 3.0;
    para.paragraphSpacing = 10.0;
    _body.attributedText = [[NSAttributedString alloc] initWithString:text attributes:@{
        NSFontAttributeName: [UIFont preferredFontForTextStyle:UIFontTextStyleBody],
        NSForegroundColorAttributeName: UIColor.labelColor,
        NSParagraphStyleAttributeName: para,
    }];
}

- (void)configureCodeWithText:(NSString *)text filename:(NSString *)filename
{
    [NSLayoutConstraint deactivateConstraints:_proseConstraints];
    [NSLayoutConstraint activateConstraints:_codeConstraints];
    _codeBackground.hidden = NO;
    _filenameLabel.text = filename ?: @"";
    _dividerHeight.constant = 1.0 / UIScreen.mainScreen.scale;
    _body.textContainer.maximumNumberOfLines = 0;
    _body.textContainer.lineBreakMode = NSLineBreakByWordWrapping;

    NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
    para.lineSpacing = 2.0;
    UIFont *baseMono = [UIFont monospacedSystemFontOfSize:12.0 weight:UIFontWeightRegular];
    UIFont *mono = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleFootnote] scaledFontForFont:baseMono];
    _body.attributedText = [[NSAttributedString alloc] initWithString:text attributes:@{
        NSFontAttributeName: mono,
        NSForegroundColorAttributeName: UIColor.labelColor,
        NSParagraphStyleAttributeName: para,
    }];
}

@end

#pragma mark - DocsViewController

static NSString * const kProseCellID   = @"DocsProseCell";
static NSString * const kCodeCellID    = @"DocsCodeCell";
static NSString * const kHeaderID      = @"DocsSectionHeader";
static NSString * const kFooterID      = @"DocsFooter";

@interface DocsViewController ()
@property (nonatomic, copy) NSArray<NSDictionary *> *sections;
@end

@implementation DocsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Docs";
    self.navigationItem.title = @"Docs";

    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 80.0;
    self.tableView.estimatedSectionHeaderHeight = 60.0;
    self.tableView.estimatedSectionFooterHeight = 40.0;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.sectionHeaderHeight = UITableViewAutomaticDimension;
    self.tableView.sectionFooterHeight = UITableViewAutomaticDimension;
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 28, 0);
    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 6.0;
    }
    [self.tableView registerClass:DocsCell.class           forCellReuseIdentifier:kProseCellID];
    [self.tableView registerClass:DocsCell.class           forCellReuseIdentifier:kCodeCellID];
    [self.tableView registerClass:DocsSectionHeader.class  forHeaderFooterViewReuseIdentifier:kHeaderID];
    [self.tableView registerClass:DocsFooter.class         forHeaderFooterViewReuseIdentifier:kFooterID];

    [self buildSections];
}

#pragma mark - Content

- (void)buildSections
{
    NSString *helloHeader =
        @"#ifndef hello_tweak_h\n"
        @"#define hello_tweak_h\n"
        @"#include <stdbool.h>\n"
        @"bool hello_tweak_apply_in_session(void);\n"
        @"bool hello_tweak_stop_in_session(void);\n"
        @"void hello_tweak_forget_remote_state(void);\n"
        @"#endif";

    NSString *helloImpl =
        @"#import \"hello_tweak.h\"\n"
        @"#import \"remote_objc.h\"\n"
        @"#import \"../TaskRop/RemoteCall.h\"\n"
        @"#import <stdint.h>\n"
        @"\n"
        @"static const uint64_t kHelloTag = 0xC0A11DE;\n"
        @"static uint64_t gHelloView = 0;\n"
        @"\n"
        @"static uint64_t hello_first_window(void) {\n"
        @"    uint64_t UIApplication = r_class(\"UIApplication\");\n"
        @"    uint64_t app = r_msg2_main(UIApplication, \"sharedApplication\",\n"
        @"                               0, 0, 0, 0);\n"
        @"    if (!r_is_objc_ptr(app)) return 0;\n"
        @"\n"
        @"    uint64_t keyWindow = r_msg2_main(app, \"keyWindow\", 0, 0, 0, 0);\n"
        @"    if (r_is_objc_ptr(keyWindow)) return keyWindow;\n"
        @"\n"
        @"    uint64_t windows = r_msg2_main(app, \"windows\", 0, 0, 0, 0);\n"
        @"    uint64_t count = r_msg2_main(windows, \"count\", 0, 0, 0, 0);\n"
        @"    for (uint64_t i = 0; r_is_objc_ptr(windows) && i < count && i < 16; i++) {\n"
        @"        uint64_t window = r_msg2_main(windows, \"objectAtIndex:\", i, 0, 0, 0);\n"
        @"        if (r_is_objc_ptr(window)) return window;\n"
        @"    }\n"
        @"    return 0;\n"
        @"}\n"
        @"\n"
        @"static uint64_t hello_existing_view(uint64_t window) {\n"
        @"    if (!r_is_objc_ptr(window)) return 0;\n"
        @"    uint64_t view = r_msg2_main(window, \"viewWithTag:\", kHelloTag, 0, 0, 0);\n"
        @"    if (r_is_objc_ptr(view)) gHelloView = view;\n"
        @"    return r_is_objc_ptr(view) ? view : 0;\n"
        @"}\n"
        @"\n"
        @"bool hello_tweak_apply_in_session(void) {\n"
        @"    uint64_t window = hello_first_window();\n"
        @"    if (!r_is_objc_ptr(window)) return false;\n"
        @"\n"
        @"    uint64_t existing = hello_existing_view(window);\n"
        @"    if (r_is_objc_ptr(existing)) {\n"
        @"        r_msg2_main(existing, \"setHidden:\", 0, 0, 0, 0);\n"
        @"        r_msg2_main(window, \"bringSubviewToFront:\", existing, 0, 0, 0);\n"
        @"        return true;\n"
        @"    }\n"
        @"\n"
        @"    uint64_t UIView = r_class(\"UIView\");\n"
        @"    uint64_t view = r_msg2_main(r_msg2_main(UIView, \"alloc\", 0, 0, 0, 0),\n"
        @"                                \"init\", 0, 0, 0, 0);\n"
        @"    if (!r_is_objc_ptr(view)) return false;\n"
        @"\n"
        @"    struct { double x, y, w, h; } frame = { 40.0, 120.0, 80.0, 80.0 };\n"
        @"    r_msg2_main_raw(view, \"setFrame:\",\n"
        @"                    &frame, sizeof(frame),\n"
        @"                    NULL, 0, NULL, 0, NULL, 0);\n"
        @"\n"
        @"    uint64_t UIColor = r_class(\"UIColor\");\n"
        @"    uint64_t color = r_msg2_main(UIColor, \"systemRedColor\", 0, 0, 0, 0);\n"
        @"    if (!r_is_objc_ptr(color)) color = r_msg2_main(UIColor, \"redColor\", 0, 0, 0, 0);\n"
        @"    r_msg2_main(view, \"setBackgroundColor:\", color, 0, 0, 0);\n"
        @"    r_msg2_main(view, \"setTag:\", kHelloTag, 0, 0, 0);\n"
        @"    r_msg2_main(window, \"addSubview:\", view, 0, 0, 0);\n"
        @"    r_msg2_main(view, \"release\", 0, 0, 0, 0);\n"
        @"\n"
        @"    gHelloView = view;\n"
        @"    return true;\n"
        @"}\n"
        @"\n"
        @"bool hello_tweak_stop_in_session(void) {\n"
        @"    uint64_t window = hello_first_window();\n"
        @"    uint64_t view = hello_existing_view(window);\n"
        @"    if (!r_is_objc_ptr(view)) return false;\n"
        @"\n"
        @"    r_msg2_main(view, \"setHidden:\", 1, 0, 0, 0);\n"
        @"    r_msg2_main(view, \"removeFromSuperview\", 0, 0, 0, 0);\n"
        @"    gHelloView = 0;\n"
        @"    return true;\n"
        @"}\n"
        @"\n"
        @"void hello_tweak_forget_remote_state(void) {\n"
        @"    // SpringBoard respawned or RemoteCall was abandoned; cached\n"
        @"    // remote pointers are from the old address space.\n"
        @"    gHelloView = 0;\n"
        @"}";

    NSString *wiring =
        @"#import \"tweaks/hello_tweak.h\"\n"
        @"NSString * const kSettingsHelloEnabled = @\"HelloEnabled\";\n"
        @"\n"
        @"// Add kSettingsHelloEnabled to settings_register_defaults(),\n"
        @"// settings_rc_backed_tweak_keys(), settings_key_affects_package_state(),\n"
        @"// and the Settings rows that render the switch.\n"
        @"static BOOL settings_key_is_hello(NSString *key) {\n"
        @"    return [key isEqualToString:kSettingsHelloEnabled];\n"
        @"}\n"
        @"\n"
        @"// In the Run path, after settings_ensure_springboard_remote_call_locked():\n"
        @"if ([d boolForKey:kSettingsHelloEnabled]) {\n"
        @"    bool ok = hello_tweak_apply_in_session();\n"
        @"    settings_mark_tweak_applied(kSettingsHelloEnabled,\n"
        @"                                ok && [d boolForKey:kSettingsHelloEnabled]);\n"
        @"    printf(\"[SETTINGS] Hello result=%d\\n\", ok);\n"
        @"}\n"
        @"\n"
        @"// In settings_schedule_live_apply_for_key():\n"
        @"if (settings_key_is_hello(key)) {\n"
        @"    if ([d boolForKey:kSettingsHelloEnabled] && g_springboard_rc_ready) {\n"
        @"        dispatch_async(dispatch_get_global_queue(0, 0), ^{\n"
        @"            @synchronized (settings_rc_lock()) {\n"
        @"                if (settings_cleanup_in_progress() || !g_springboard_rc_ready) return;\n"
        @"                bool ok = hello_tweak_apply_in_session();\n"
        @"                settings_mark_tweak_applied(kSettingsHelloEnabled,\n"
        @"                                            ok && [d boolForKey:kSettingsHelloEnabled]);\n"
        @"            }\n"
        @"            settings_notify_package_queue_changed_async();\n"
        @"        });\n"
        @"    } else if (![d boolForKey:kSettingsHelloEnabled]) {\n"
        @"        settings_mark_tweak_applied(kSettingsHelloEnabled, NO);\n"
        @"        settings_notify_package_queue_changed_async();\n"
        @"        if (g_springboard_rc_ready) dispatch_async(dispatch_get_global_queue(0, 0), ^{\n"
        @"            @synchronized (settings_rc_lock()) {\n"
        @"                if (g_springboard_rc_ready) hello_tweak_stop_in_session();\n"
        @"            }\n"
        @"        });\n"
        @"    }\n"
        @"    return;\n"
        @"}\n"
        @"\n"
        @"// In SpringBoard restart/abandon and manual cleanup paths:\n"
        @"hello_tweak_forget_remote_state();";

    NSString *apiCheat =
        @"#import \"remote_objc.h\"\n"
        @"#import \"../TaskRop/RemoteCall.h\"\n"
        @"\n"
        @"r_class(\"UILabel\")                  // remote Class *\n"
        @"r_sel(\"setHidden:\")                 // remote SEL\n"
        @"r_msg2(obj, \"setHidden:\", 1,0,0,0)  // objc_msgSend in target\n"
        @"r_msg2_main(label, \"setText:\", text,\n"
        @"            0,0,0)                   // UIKit/main-thread send\n"
        @"r_msg2_main_raw(obj, \"setFrame:\",\n"
        @"  &rect, sizeof(rect), NULL,0,\n"
        @"  NULL,0, NULL,0)                    // pass a struct by value\n"
        @"r_msg2_main_struct_ret(obj, \"bounds\",\n"
        @"  &out, sizeof(out), NULL,0,\n"
        @"  NULL,0, NULL,0, NULL,0)            // copy a struct return\n"
        @"\n"
        @"r_alloc_str(\"hi\") / r_free(ptr)     // C string into remote\n"
        @"r_nsstr_retained(\"hi\")              // NSString*, caller releases\n"
        @"r_cfstr(\"hi\")                       // CFStringRef, caller CFReleases\n"
        @"r_settle_us(1000)                    // tune helper delay; restore old value\n"
        @"\n"
        @"r_dlsym_call(R_TIMEOUT,\n"
        @"  \"objc_setAssociatedObject\",\n"
        @"  obj, key, val, policy, 0,0,0,0)    // any C function\n"
        @"r_is_objc_ptr(p)                     // sanity check\n"
        @"r_ivar_value(obj, \"_name\")          // read ivar\n"
        @"r_responds_main(obj, \"sel:\")        // -respondsToSelector:\n"
        @"remote_read / remote_write           // raw memory helpers\n"
        @"init_remote_call(\"SpringBoard\", false)\n"
        @"destroy_remote_call()                // one-shot sessions only\n"
        @"abandon_remote_call()                // remote task is already gone";

    NSString *portingNotes =
        @"%hook UIView                         not portable as a hook\n"
        @"- (void)setHidden:(BOOL)h { ... }    rewrite as explicit\n"
        @"                                     r_msg2_main(view,\n"
        @"                                     \"setHidden:\", h,0,0,0)\n"
        @"\n"
        @"[%c(Foo) bar]                        r_msg2(r_class(\"Foo\"),\n"
        @"                                           \"bar\", 0,0,0,0)\n"
        @"\n"
        @"struct { double x,y,w,h; } r = {0};  r_msg2_main_struct_ret(view,\n"
        @"                                     \"bounds\", &r, sizeof(r),\n"
        @"                                     NULL,0, NULL,0, NULL,0, NULL,0)\n"
        @"\n"
        @"%new -[X infern0Overlay]             associated object via\n"
        @"                                     objc_setAssociatedObject\n"
        @"                                     through r_dlsym_call\n"
        @"\n"
        @"MSHookFunction(...)                  not available here";

    self.sections = @[
        @{ @"title": @"How tweaks work",
           @"symbol": @"book.closed.fill",
           @"tint": UIColor.systemPurpleColor,
           @"footer": @"Read sbcustomizer.m, statbar.m, rssidisplay.m, and axonlite.m in "
                      @"infern0/tweaks/ for shipped patterns at increasing complexity.",
           @"rows": @[
               @{ @"kind": @"prose",
                  @"text": @"infern0 tweaks are app-side drivers. No SpringBoard dylibs, no "
                           @"Substrate hooks, no swizzled methods. The app reaches into the "
                           @"target from outside." },
               @{ @"kind": @"prose",
                  @"text": @"A RemoteCall session is the bridge. From inside one you send "
                           @"Objective-C messages, read and write memory, and call C symbols "
                           @"in the target process." },
               @{ @"kind": @"prose",
                  @"text": @"Settings holds the SpringBoard channel during Apply Tweaks. Your "
                           @"code runs inside it under settings_rc_lock(), via three "
                           @"entrypoints: apply_in_session, optional stop_in_session, and "
                           @"forget_remote_state." },
           ]},

        @{ @"title": @"The remote_objc API",
           @"symbol": @"chevron.left.forwardslash.chevron.right",
           @"tint": UIColor.systemRedColor,
           @"footer": @"_main variants dispatch to the target main thread (use them for "
                      @"UIKit). _raw passes non-pointer arguments by value. "
                      @"r_msg2_main_struct_ret copies struct returns such as CGRect.",
           @"rows": @[
               @{ @"kind": @"prose",
                  @"text": @"Import remote_objc.h and ../TaskRop/RemoteCall.h. Helpers assume "
                           @"an active session — don't call init_remote_call yourself unless "
                           @"you need a private channel." },
               @{ @"kind": @"code", @"filename": @"remote_objc.h", @"text": apiCheat },
           ]},

        @{ @"title": @"A minimal tweak",
           @"symbol": @"doc.text.fill",
           @"tint": UIColor.systemOrangeColor,
           @"footer": @"Drop both files in infern0/tweaks/. The Xcode project uses "
                      @"PBXFileSystemSynchronizedRootGroup, so new files are picked up "
                      @"automatically — no pbxproj edits needed.",
           @"rows": @[
               @{ @"kind": @"prose",
                  @"text": @"A complete RemoteCall-only tweak: paints an 80×80 red square on "
                           @"a SpringBoard window." },
               @{ @"kind": @"prose",
                  @"text": @"Idempotent on reapply, undoes itself on stop, drops cached "
                           @"pointers on respawn." },
               @{ @"kind": @"code", @"filename": @"hello_tweak.h", @"text": helloHeader },
               @{ @"kind": @"code", @"filename": @"hello_tweak.m", @"text": helloImpl },
           ]},

        @{ @"title": @"Wiring into Settings",
           @"symbol": @"gearshape.2.fill",
           @"tint": UIColor.systemGreenColor,
           @"footer": @"Mirror an existing kSettings…Enabled path — search "
                      @"kSettingsStatBarEnabled or kSettingsAxonLiteEnabled for a complete "
                      @"template covering defaults, rows, package state, Run, live apply, "
                      @"stop, and cleanup.",
           @"rows": @[
               @{ @"kind": @"prose",
                  @"text": @"SettingsViewController.m is the orchestrator. Add five things: a "
                           @"defaults key, a switch row, a Run-path apply, a live-apply "
                           @"branch, and forget_remote_state in cleanup." },
               @{ @"kind": @"prose",
                  @"text": @"Every apply checks g_springboard_rc_ready inside "
                           @"@synchronized(settings_rc_lock()). settings_mark_tweak_applied() "
                           @"keeps package state honest. forget_remote_state() runs on "
                           @"respring and abandon." },
               @{ @"kind": @"code", @"filename": @"SettingsViewController.m", @"text": wiring },
           ]},

        @{ @"title": @"Porting from Theos / Substrate",
           @"symbol": @"arrow.triangle.2.circlepath",
           @"tint": UIColor.systemPinkColor,
           @"footer": @"Shipped templates: sbcustomizer (dock layout), darksword_tweaks "
                      @"(SpringBoard state toggles), powercuff (thermalmonitord one-shot), "
                      @"statbar (overlay window), rssidisplay (per-icon overlays), "
                      @"axonlite (cached NC state).",
           @"rows": @[
               @{ @"kind": @"prose",
                  @"text": @"RemoteCall isn't a hook framework. You can't intercept a method "
                           @"or replace a C function in place." },
               @{ @"kind": @"prose",
                  @"text": @"Ports work when the effect is a finite mutation — set this "
                           @"property, call this controller method, add this view, hold this "
                           @"assertion, or refresh on a timer." },
               @{ @"kind": @"code", @"filename": @"Theos → RemoteCall", @"text": portingNotes },
               @{ @"kind": @"prose",
                  @"text": @"Targeting another process? Open a separate session with "
                           @"init_remote_call(name, false), do the work, destroy_remote_call "
                           @"before switching back. Powercuff does this for thermalmonitord." },
           ]},

        @{ @"title": @"Contribute",
           @"symbol": @"arrow.up.right.square.fill",
           @"tint": UIColor.systemRedColor,
           @"footer": @"",
           @"rows": @[
               @{ @"kind": @"prose",
                  @"text": @"Build with ./scripts/build.sh — the IPA is packaged under "
                           @"build/. Sideload, test on device, attach Log-tab output to your "
                           @"PR." },
               @{ @"kind": @"prose",
                  @"text": @"Source and issues: https://github.com/zeroxjf/cyanide" },
           ]},
    ];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSArray *rows = self.sections[section][@"rows"];
    return (NSInteger)rows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSDictionary *row = self.sections[indexPath.section][@"rows"][indexPath.row];
    NSString *kind = row[@"kind"];
    NSString *text = row[@"text"];
    BOOL isCode = [kind isEqualToString:@"code"];

    DocsCell *cell = [tableView dequeueReusableCellWithIdentifier:isCode ? kCodeCellID : kProseCellID
                                                     forIndexPath:indexPath];
    if (isCode) {
        [cell configureCodeWithText:text filename:row[@"filename"]];
    } else {
        [cell configureProseWithText:text];
    }
    return cell;
}

#pragma mark - UITableViewDelegate

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    NSDictionary *info = self.sections[section];
    DocsSectionHeader *header = [tableView dequeueReusableHeaderFooterViewWithIdentifier:kHeaderID];
    [header configureWithSymbol:info[@"symbol"] tint:info[@"tint"] title:info[@"title"]];
    return header;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section
{
    NSString *text = self.sections[section][@"footer"];
    if (text.length == 0) return nil;
    DocsFooter *footer = [tableView dequeueReusableHeaderFooterViewWithIdentifier:kFooterID];
    [footer configureWithText:text];
    return footer;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{
    NSString *text = self.sections[section][@"footer"];
    return text.length == 0 ? CGFLOAT_MIN : UITableViewAutomaticDimension;
}

@end
