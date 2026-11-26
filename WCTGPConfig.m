#import "WCTGPConfig.h"

static void WCTGConfigChanged(CFNotificationCenterRef center, void *observer,
                              CFStringRef name, const void *object,
                              CFDictionaryRef userInfo);

static NSString *const kWCTGDomain = @"com.wctg.popup";
static NSString *const kWCTGPrefsPath =
    @"/var/mobile/Library/Preferences/com.wctg.popup.plist";

@implementation WCTGPConfig

+ (instancetype)shared {
    static WCTGPConfig *cfg;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cfg = [WCTGPConfig new];
        [cfg reload];
        // 设置面板改完发 Darwin 通知，这里热重载
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        (__bridge const void *)cfg,
                                        (CFNotificationCallback)WCTGConfigChanged,
                                        CFSTR("com.wctg.popup/changed"),
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    });
    return cfg;
}

static void WCTGConfigChanged(CFNotificationCenterRef center, void *observer,
                              CFStringRef name, const void *object,
                              CFDictionaryRef userInfo) {
    [(__bridge WCTGPConfig *)observer reload];
}

- (id)valueForKey:(NSString *)key fallback:(id)fallback {
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                    (__bridge CFStringRef)kWCTGDomain);
    if (v) {
        return (__bridge_transfer id)v;
    }
    return fallback;
}

- (BOOL)boolFor:(NSString *)key fallback:(BOOL)fallback {
    id v = [self valueForKey:key fallback:nil];
    return v ? [v boolValue] : fallback;
}

- (double)doubleFor:(NSString *)key fallback:(double)fallback {
    id v = [self valueForKey:key fallback:nil];
    return v ? [v doubleValue] : fallback;
}

- (void)reload {
    // 默认值全部来自视频逐帧量测
    _enabled = [self boolFor:@"enabled" fallback:YES];
    _mutedSuppress = [self boolFor:@"mutedSuppress" fallback:YES];
    _showWhenInChat = [self boolFor:@"showWhenInChat" fallback:NO];
    _haptic = [self boolFor:@"haptic" fallback:YES];
    _showGroupName = [self boolFor:@"showGroupName" fallback:YES];

    _cardInset = [self doubleFor:@"cardInset" fallback:15.0];
    _cardHeight = [self doubleFor:@"cardHeight" fallback:64.0];
    _cardRadius = [self doubleFor:@"cardRadius" fallback:20.0];
    _avatarSize = [self doubleFor:@"avatarSize" fallback:40.0];
    _topMargin = [self doubleFor:@"topMargin" fallback:60.0];

    _dropFrom = [self doubleFor:@"dropFrom" fallback:-36.0];
    _enterScale = [self doubleFor:@"enterScale" fallback:0.72];
    _enterDuration = [self doubleFor:@"enterDuration" fallback:0.52];
    _enterDamping = [self doubleFor:@"enterDamping" fallback:0.38];
    _enterVelocity = [self doubleFor:@"enterVelocity" fallback:0.6];

    _jelly = [self boolFor:@"jelly" fallback:YES];
    _jellyAmount = [self doubleFor:@"jellyAmount" fallback:0.06];

    _holdSeconds = [self doubleFor:@"holdSeconds" fallback:3.6];
    _exitDuration = [self doubleFor:@"exitDuration" fallback:0.16];
    _exitLift = [self doubleFor:@"exitLift" fallback:-22.0];

    // 兜底，防止面板输入越界把动画搞崩
    if (_cardHeight < 40) _cardHeight = 40;
    if (_cardInset < 0) _cardInset = 0;
    if (_cardRadius < 0) _cardRadius = 0;
    if (_avatarSize < 20) _avatarSize = 20;
    if (_avatarSize > _cardHeight - 8) _avatarSize = _cardHeight - 8;
    if (_enterDuration < 0.1) _enterDuration = 0.1;
    if (_enterDamping < 0.1) _enterDamping = 0.1;
    if (_enterDamping > 1.0) _enterDamping = 1.0;
    if (_enterScale < 0.3) _enterScale = 0.3;
    if (_enterScale > 1.0) _enterScale = 1.0;
    if (_holdSeconds < 0.5) _holdSeconds = 0.5;
    if (_exitDuration < 0.05) _exitDuration = 0.05;
    if (_jellyAmount < 0) _jellyAmount = 0;
    if (_jellyAmount > 0.2) _jellyAmount = 0.2;
}

/// 设置面板「恢复默认」用
+ (void)resetToDefaults {
    CFPreferencesSetAppValue(CFSTR("enabled"), NULL, (__bridge CFStringRef)kWCTGDomain);
    NSArray<NSString *> *keys = @[ @"mutedSuppress", @"showWhenInChat", @"haptic",
                                   @"showGroupName", @"cardInset", @"cardHeight",
                                   @"cardRadius", @"avatarSize", @"topMargin", @"dropFrom",
                                   @"enterScale", @"enterDuration", @"enterDamping",
                                   @"enterVelocity", @"jelly", @"jellyAmount",
                                   @"holdSeconds", @"exitDuration", @"exitLift" ];
    for (NSString *k in keys) {
        CFPreferencesSetAppValue((__bridge CFStringRef)k, NULL,
                                 (__bridge CFStringRef)kWCTGDomain);
    }
    CFPreferencesAppSynchronize((__bridge CFStringRef)kWCTGDomain);
}

@end
