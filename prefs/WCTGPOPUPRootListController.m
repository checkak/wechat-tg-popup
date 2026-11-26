#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <notify.h>
#import "WCTGPConfig.h"

static NSString *const kWCTGDomain = @"com.wctg.popup";
static const char *kWCTGDarwinNote = "com.wctg.popup/changed";

@interface WCTGPOPUPRootListController : PSListController
@end

@implementation WCTGPOPUPRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

// 读：直接读 com.wctg.popup 域
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier properties][@"key"];
    if (key.length == 0) {
        return nil;
    }
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                    (__bridge CFStringRef)kWCTGDomain);
    if (v) {
        return (__bridge_transfer id)v;
    }
    return [specifier properties][@"default"];
}

// 写：写回同一域，并发 Darwin 通知让插件立刻热重载
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier properties][@"key"];
    if (key.length == 0) {
        return;
    }
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFTypeRef)value,
                             (__bridge CFStringRef)kWCTGDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kWCTGDomain);
    notify_post(kWCTGDarwinNote);
}

- (void)resetDefaults:(PSSpecifier *)specifier {
    [WCTGPConfig resetToDefaults];
    notify_post(kWCTGDarwinNote);
    [self reloadSpecifiers];
    // 给点反馈
    UINotificationFeedbackGenerator *g = [UINotificationFeedbackGenerator new];
    [g notificationOccurred:UINotificationFeedbackTypeSuccess];
}

@end
