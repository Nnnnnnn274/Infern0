//
//  QueuePopupBar.m
//  Cyanide
//

#import "QueuePopupBar.h"
#import "PackageQueue.h"

@interface QueuePopupBar ()
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIImageView *chevronView;
@end

@implementation QueuePopupBar

- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        [self buildSubviews];
        self.alpha = 0.0;
        self.hidden = YES;
    }
    return self;
}

- (void)buildSubviews
{
    self.backgroundColor = UIColor.clearColor;
    self.layer.cornerRadius = 16.0;
    self.layer.masksToBounds = YES;
    self.layer.borderWidth = 0.5;
    self.layer.borderColor = [UIColor.separatorColor colorWithAlphaComponent:0.5].CGColor;

    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    blurView.translatesAutoresizingMaskIntoConstraints = NO;
    blurView.userInteractionEnabled = NO;
    [self addSubview:blurView];
    self.blurView = blurView;

    UIImageView *iconView = [[UIImageView alloc] init];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.image = [UIImage systemImageNamed:@"shippingbox.fill"
                              withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:18.0 weight:UIImageSymbolWeightSemibold]];
    iconView.tintColor = self.tintColor;
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    [self addSubview:iconView];
    self.iconView = iconView;

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    title.textColor = UIColor.labelColor;
    [self addSubview:title];
    self.titleLabel = title;

    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular];
    subtitle.textColor = UIColor.secondaryLabelColor;
    [self addSubview:subtitle];
    self.subtitleLabel = subtitle;

    UIImageView *chev = [[UIImageView alloc] init];
    chev.translatesAutoresizingMaskIntoConstraints = NO;
    chev.image = [UIImage systemImageNamed:@"chevron.right"
                         withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:13.0 weight:UIImageSymbolWeightSemibold]];
    chev.tintColor = UIColor.tertiaryLabelColor;
    chev.contentMode = UIViewContentModeScaleAspectFit;
    [self addSubview:chev];
    self.chevronView = chev;

    [NSLayoutConstraint activateConstraints:@[
        [blurView.topAnchor      constraintEqualToAnchor:self.topAnchor],
        [blurView.bottomAnchor   constraintEqualToAnchor:self.bottomAnchor],
        [blurView.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor],
        [blurView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

        [iconView.leadingAnchor  constraintEqualToAnchor:self.leadingAnchor constant:16.0],
        [iconView.centerYAnchor  constraintEqualToAnchor:self.centerYAnchor],
        [iconView.widthAnchor    constraintEqualToConstant:24.0],
        [iconView.heightAnchor   constraintEqualToConstant:24.0],

        [title.leadingAnchor     constraintEqualToAnchor:iconView.trailingAnchor constant:12.0],
        [title.topAnchor         constraintEqualToAnchor:self.topAnchor constant:9.0],

        [subtitle.leadingAnchor  constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.topAnchor      constraintEqualToAnchor:title.bottomAnchor constant:1.0],

        [chev.trailingAnchor     constraintEqualToAnchor:self.trailingAnchor constant:-16.0],
        [chev.centerYAnchor      constraintEqualToAnchor:self.centerYAnchor],
        [chev.widthAnchor        constraintEqualToConstant:14.0],
        [chev.heightAnchor       constraintEqualToConstant:18.0],

        [title.trailingAnchor    constraintLessThanOrEqualToAnchor:chev.leadingAnchor constant:-12.0],
        [subtitle.trailingAnchor constraintLessThanOrEqualToAnchor:chev.leadingAnchor constant:-12.0],
    ]];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(didTap)];
    [self addGestureRecognizer:tap];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(queueChanged:)
                                                 name:PackageQueueDidChangeNotification
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)tintColorDidChange
{
    [super tintColorDidChange];
    self.iconView.tintColor = self.tintColor;
}

- (void)didTap
{
    if (self.onTap) self.onTap();
}

- (void)queueChanged:(NSNotification *)note
{
    [self refreshFromQueueAnimated:YES];
}

- (void)refreshFromQueueAnimated:(BOOL)animated
{
    PackageQueue *q = [PackageQueue sharedQueue];
    NSInteger count = q.pendingCount;

    if (count == 0) {
        [self setVisible:NO animated:animated];
        return;
    }

    NSInteger installs   = (NSInteger)q.queuedInstalls.count;
    NSInteger uninstalls = (NSInteger)q.queuedUninstalls.count;

    self.titleLabel.text = (count == 1) ? @"1 pending change" : [NSString stringWithFormat:@"%ld pending changes", (long)count];

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (installs > 0)   [parts addObject:[NSString stringWithFormat:@"%ld install", (long)installs]];
    if (uninstalls > 0) [parts addObject:[NSString stringWithFormat:@"%ld uninstall", (long)uninstalls]];
    self.subtitleLabel.text = [parts componentsJoinedByString:@" · "];

    [self setVisible:YES animated:animated];
}

- (void)setVisible:(BOOL)visible animated:(BOOL)animated
{
    if (!visible && self.hidden) return;
    if (visible && !self.hidden && self.alpha == 1.0) return;

    void (^update)(void) = ^{
        self.alpha = visible ? 1.0 : 0.0;
        self.transform = visible ? CGAffineTransformIdentity : CGAffineTransformMakeTranslation(0, 16.0);
    };
    void (^done)(BOOL) = ^(BOOL _) {
        self.hidden = !visible;
    };

    self.hidden = NO;
    if (!visible) {
        self.transform = CGAffineTransformIdentity;
    } else if (self.alpha < 0.01) {
        self.transform = CGAffineTransformMakeTranslation(0, 16.0);
    }

    if (animated) {
        [UIView animateWithDuration:0.28
                              delay:0
             usingSpringWithDamping:0.85
              initialSpringVelocity:0.3
                            options:UIViewAnimationOptionBeginFromCurrentState
                         animations:update
                         completion:done];
    } else {
        update();
        done(YES);
    }
}

@end
