//
//  NiceBarSettingsSupport.h
//  Cyanide
//
//  NiceBar Lite Settings UI and weather helpers adapted from
//  https://github.com/d1y/cyanide-ios (AGPL-3.0).
//

#import <UIKit/UIKit.h>
#import "tweaks/retired_tweak_compat.h"

typedef void (^CyanideNiceBarWeatherCompletion)(BOOL ok,
                                                NSString *text,
                                                NSNumber *temp,
                                                NSNumber *code,
                                                BOOL fetched);

NSString *CyanideNiceBarSystemDescription(NSInteger item);
NSString *CyanideNiceBarSystemName(NSInteger item);
NSString *CyanideNiceBarSystemLanguageName(NSString *language);
NSString *CyanideNiceBarTimeFormatName(NSString *format);
NSString *CyanideNiceBarPreviewForTimeFormat(NSString *format);
NSString *CyanideNiceBarWeatherSummary(NSInteger code, BOOL chinese);

@interface CyanideNiceBarWeatherRefresher : NSObject
+ (instancetype)sharedRefresher;
- (void)refreshWeatherForce:(BOOL)force
                 useCelsius:(BOOL)useCelsius
                 completion:(CyanideNiceBarWeatherCompletion)completion;
@end

@interface CyanideNiceBarTrafficHistoryViewController : UITableViewController
@end

typedef void (^CyanideNiceBarTimeFormatSelection)(NSString *format);

@interface CyanideNiceBarTimePresetPickerViewController : UITableViewController
- (instancetype)initWithSlotTitle:(NSString *)slotTitle
                   selectedFormat:(NSString *)selectedFormat
                        selection:(CyanideNiceBarTimeFormatSelection)selection;
@end

typedef void (^CyanideNiceBarSystemItemSelection)(NSInteger item, NSString *language);

@interface CyanideNiceBarSystemItemPickerViewController : UITableViewController
- (instancetype)initWithSlotTitle:(NSString *)slotTitle
                     selectedItem:(NSInteger)selectedItem
                 selectedLanguage:(NSString *)selectedLanguage
                        selection:(CyanideNiceBarSystemItemSelection)selection;
@end
