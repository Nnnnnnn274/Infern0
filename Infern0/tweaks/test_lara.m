#import <UIKit/UIKit.h>
#include "../../utils/lara/pe/sbx.h"
#include "../../utils/lara/utils.h"
#include "../../utils/lara/pe/vfs.h"

@interface MainViewController : UIViewController
@end

@implementation MainViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor systemBackgroundColor];

    // Main panel
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(25, 80,
                                self.view.bounds.size.width - 50, 330)];
    panel.backgroundColor = [UIColor secondarySystemBackgroundColor];
    panel.layer.cornerRadius = 18;
    panel.layer.borderWidth = 1;
    panel.layer.borderColor = [UIColor systemGray4Color].CGColor;
    [self.view addSubview:panel];

    // Title
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 20,
                                panel.bounds.size.width, 35)];
    title.text = @"SpringBoard Customizer";
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:24];
    [panel addSubview:title];

    NSArray *titles = @[
        @"SBX",
        @"VFS",
        @"Respring",
        @"GetProc"
    ];

    CGFloat width = panel.bounds.size.width - 40;
    CGFloat height = 50;
    CGFloat y = 80;

    for (NSInteger i = 0; i < 4; i++) {

        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];

        button.frame = CGRectMake(20,
                                  y + (height + 15) * i,
                                  width,
                                  height);

        button.backgroundColor = [UIColor systemOrangeColor];
        button.layer.cornerRadius = 12;

        [button setTitle:titles[i] forState:UIControlStateNormal];
        [button setTitleColor:[UIColor whiteColor]
                     forState:UIControlStateNormal];

        button.titleLabel.font = [UIFont boldSystemFontOfSize:18];
        button.tag = i + 1;

        [button addTarget:self
                   action:@selector(buttonPressed:)
         forControlEvents:UIControlEventTouchUpInside];

        [panel addSubview:button];
    }
}

- (void)buttonPressed:(UIButton *)sender
{
    switch (sender.tag) {

        case 1:
            uint64_t proc = ourproc();
            sbx_escape(proc);
            break;

        case 2:
            vfs_init();
            if (vfs_isready() == true) {
                char path[] = "/private/var/mobile/Library/Preferences/com.apple.accounts.exists.plist";
                int64_t test = vfs_filesize(path);
            }
            break;

        case 3:
            crashproc("SpringBoard");
            break;

        case 4:
            ourproc();
            break;
    }
}

@end