#import "WCTGPConfig.h"

static NSString *const kWCTGPrefsPath =
    @"/var/mobile/Library/Preferences/com.wctg.popup.plist";

@implementation WCTGPConfig

+ (WCTGPConfig *)shared {
    static WCTGPConfig *cfg;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cfg = [WCTGPConfig new];
        [cfg reload];
    });
    return cfg;
}

- (void)reload {
    // 默认值（都来自视频实测）
    _enabled = YES;
    _showWhenInChat = NO;
    _haptic = YES;
    _showGroupName = YES;

    _cardInset = 15.0;
    _cardHeight = 64.0;
    _cardRadius = 20.0;
    _avatarSize = 40.0;
    _topMargin = 60.0;

    _dropFrom = -36.0;
    _enterScale = 0.72;
    _enterDuration = 0.52;
    _enterDamping = 0.38;
    _enterVelocity = 0.6;

    _jelly = YES;
    _jellyAmount = 0.06;

    _holdSeconds = 3.6;
    _exitDuration = 0.16;
    _exitLift = -22.0;

    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:kWCTGPrefsPath];
    if (![d isKindOfClass:[NSDictionary class]] || d.count == 0) {
        return;
    }

    #define TAKE_BOOL(key, prop) \
        if ([d objectForKey:key]) self.prop = [d[key] boolValue];
    #define TAKE_NUM(key, prop) \
        if ([d objectForKey:key]) self.prop = [d[key] doubleValue];

    TAKE_BOOL(@"enabled", enabled)
    TAKE_BOOL(@"showWhenInChat", showWhenInChat)
    TAKE_BOOL(@"haptic", haptic)
    TAKE_BOOL(@"showGroupName", showGroupName)
    TAKE_BOOL(@"jelly", jelly)

    TAKE_NUM(@"cardInset", cardInset)
    TAKE_NUM(@"cardHeight", cardHeight)
    TAKE_NUM(@"cardRadius", cardRadius)
    TAKE_NUM(@"avatarSize", avatarSize)
    TAKE_NUM(@"topMargin", topMargin)

    TAKE_NUM(@"dropFrom", dropFrom)
    TAKE_NUM(@"enterScale", enterScale)
    TAKE_NUM(@"enterDuration", enterDuration)
    TAKE_NUM(@"enterDamping", enterDamping)
    TAKE_NUM(@"enterVelocity", enterVelocity)
    TAKE_NUM(@"jellyAmount", jellyAmount)

    TAKE_NUM(@"holdSeconds", holdSeconds)
    TAKE_NUM(@"exitDuration", exitDuration)
    TAKE_NUM(@"exitLift", exitLift)

    #undef TAKE_BOOL
    #undef TAKE_NUM
}

@end
