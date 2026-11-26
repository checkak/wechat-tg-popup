//
//  设置面板控制器
//
//  注意：Preferences.framework 是设备上的「私有」框架，Xcode 的 iPhoneOS SDK 里没有，
//  直接 -framework Preferences 会报 "framework not found"。
//  这里改成自带最小声明 + 运行时动态查找（Settings app 里已经有这个框架）。
//

#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import "WCTGPConfig.h"

// ---- 最小声明（不链接 Preferences.framework）----
@interface PSSpecifier : NSObject
- (NSMutableDictionary *)properties;
@end

@interface PSListController : UIViewController
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
- (void)reloadSpecifiers;
- (void)reload;
@end

static NSString *const kWCTGDomain = @"com.wctg.popup";
static CFStringRef const kWCTGDarwinNote = CFSTR("com.wctg.popup/changed");

@interface WCTGPOPUPRootListController : PSListController
@end

@implementation WCTGPOPUPRootListController {
    NSArray *_cachedSpecifiers;
}

- (NSArray *)specifiers {
    if (!_cachedSpecifiers) {
        _cachedSpecifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _cachedSpecifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSDictionary *props = [specifier properties];
    NSString *key = props[@"key"];
    if (key.length == 0) {
        return nil;
    }
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                    (__bridge CFStringRef)kWCTGDomain);
    if (v) {
        return (__bridge_transfer id)v;
    }
    return props[@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSDictionary *props = [specifier properties];
    NSString *key = props[@"key"];
    if (key.length == 0) {
        return;
    }
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFTypeRef)value,
                             (__bridge CFStringRef)kWCTGDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kWCTGDomain);

    // Darwin 通知：插件侧用 CFNotificationCenterAddObserver 监听，改完立即生效
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         kWCTGDarwinNote, NULL, NULL, true);
}

- (void)resetDefaults:(PSSpecifier *)specifier {
    [WCTGPConfig resetToDefaults];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         kWCTGDarwinNote, NULL, NULL, true);
    _cachedSpecifiers = nil;
    [self reloadSpecifiers];

    UINotificationFeedbackGenerator *g = [UINotificationFeedbackGenerator new];
    [g notificationOccurred:UINotificationFeedbackTypeSuccess];
}

@end
