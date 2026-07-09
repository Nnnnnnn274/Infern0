//
//  JSTweakDocsViewController.h
//  Cyanide
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, JSTweakDocsMode) {
    JSTweakDocsModeWriteTweak = 0,
    JSTweakDocsModeSetupRepo  = 1,
};

@interface JSTweakDocsViewController : UIViewController
@property (nonatomic, assign) JSTweakDocsMode docsMode;
@end

NS_ASSUME_NONNULL_END
