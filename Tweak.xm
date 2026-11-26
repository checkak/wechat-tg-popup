//
//  Tweak.xm
//  WeChat TG 风格消息弹窗
//
//  设计原则：
//   1) 只读不改：不拦截、不吞消息，仅「旁听」并在独立 UIWindow 上叠一层卡片
//   2) 所有私有类/方法都用运行时探测 + @try 兜底，微信版本差异不会崩
//   3) 失败静默：拿不到字段就不弹，绝不打断正常收发
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "WCTGPopupCenter.h"
#import "WCTGPConfig.h"

#define WCTGLog(fmt, ...) NSLog(@"[WCTGPOPUP] " fmt, ##__VA_ARGS__)

#pragma mark - 安全取值

static id WCTGValue(id obj, NSArray<NSString *> *keys) {
    if (!obj) return nil;
    for (NSString *k in keys) {
        @try {
            id v = [obj valueForKey:k];
            if (v && v != [NSNull null]) return v;
        } @catch (__unused NSException *e) {}
        @try {
            SEL sel = NSSelectorFromString(k);
            if ([obj respondsToSelector:sel]) {
                id (*fn)(id, SEL) = (id (*)(id, SEL))[obj methodForSelector:sel];
                id v = fn(obj, sel);
                if (v && v != [NSNull null]) return v;
            }
        } @catch (__unused NSException *e) {}
    }
    return nil;
}

static NSString *WCTGString(id obj, NSArray<NSString *> *keys) {
    id v = WCTGValue(obj, keys);
    if ([v isKindOfClass:[NSString class]]) return v;
    if ([v respondsToSelector:@selector(stringValue)]) return [v stringValue];
    return nil;
}

static NSInteger WCTGInt(id obj, NSArray<NSString *> *keys, NSInteger fallback) {
    id v = WCTGValue(obj, keys);
    if ([v respondsToSelector:@selector(integerValue)]) return [v integerValue];
    return fallback;
}

#pragma mark - 桥接

@interface WCTGHookBridge : NSObject

+ (instancetype)shared;
- (void)handleWrap:(id)wrap;
- (void)openChatWithUsr:(NSString *)usr;

@end

@implementation WCTGHookBridge

+ (instancetype)shared {
    static WCTGHookBridge *b;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ b = [WCTGHookBridge new]; });
    return b;
}

/// MMServiceCenter → CContactMgr → CContact
- (id)contactForUsr:(NSString *)usr {
    if (usr.length == 0) return nil;
    @try {
        Class centerCls = NSClassFromString(@"MMServiceCenter");
        Class mgrCls = NSClassFromString(@"CContactMgr");
        if (!centerCls || !mgrCls) return nil;

        SEL defaultSel = NSSelectorFromString(@"defaultCenter");
        if (![centerCls respondsToSelector:defaultSel]) return nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id center = [centerCls performSelector:defaultSel];
#pragma clang diagnostic pop
        if (!center) return nil;

        SEL getService = NSSelectorFromString(@"getService:");
        if (![center respondsToSelector:getService]) return nil;
        id mgr = ((id (*)(id, SEL, id))[center methodForSelector:getService])(center, getService, mgrCls);
        if (!mgr) return nil;

        SEL byName = NSSelectorFromString(@"getContactByName:");
        if ([mgr respondsToSelector:byName]) {
            return ((id (*)(id, SEL, id))[mgr methodForSelector:byName])(mgr, byName, usr);
        }
    } @catch (__unused NSException *e) {}
    return nil;
}

- (NSString *)displayNameForUsr:(NSString *)usr {
    id contact = [self contactForUsr:usr];
    if (contact) {
        NSString *n = WCTGString(contact, @[ @"m_nsNickName", @"m_nsRemark", @"nickName" ]);
        if (n.length) return n;
    }
    if (usr.length > 10) return [usr substringFromIndex:usr.length - 6];
    return usr.length ? usr : @"微信";
}

- (NSString *)avatarURLForUsr:(NSString *)usr {
    id contact = [self contactForUsr:usr];
    if (!contact) return nil;

    NSString *u = WCTGString(contact, @[ @"m_nsHeadImgUrl", @"m_nsHeadImgUrlBig" ]);
    if (u.length) return u;

    BOOL isGroup = WCTGInt(contact, @[ @"m_uiChatRoomStatus" ], 0) != 0;
    @try {
        if (isGroup) {
            SEL s = NSSelectorFromString(@"getChatRoomHeadImgUrl");
            if ([contact respondsToSelector:s]) {
                id v = ((id (*)(id, SEL))[contact methodForSelector:s])(contact, s);
                if ([v isKindOfClass:[NSString class]]) return v;
            }
        } else {
            SEL s = NSSelectorFromString(@"getHeadImgUrlByType:");
            if ([contact respondsToSelector:s]) {
                id v = ((id (*)(id, SEL, id))[contact methodForSelector:s])(contact, s, @0);
                if ([v isKindOfClass:[NSString class]]) return v;
            }
        }
    } @catch (__unused NSException *e) {}
    return nil;
}

- (NSString *)previewForWrap:(id)wrap content:(NSString *)content {
    NSInteger type = WCTGInt(wrap, @[ @"m_uiMessageType", @"messageType" ], 1);
    switch (type) {
        case 1:     return content.length ? content : @"[消息]";
        case 3:     return @"[图片]";
        case 34:    return @"[语音]";
        case 42:    return @"[名片]";
        case 43:    return @"[视频]";
        case 47:    return @"[表情]";
        case 48:    return @"[位置]";
        case 49:    return content.length ? content : @"[链接/文件]";
        case 50:    return @"[通话]";
        case 10000: return content.length ? content : @"[系统消息]";
        default:    return content.length ? content : @"[消息]";
    }
}

- (NSString *)currentChatName {
    @try {
        UIWindow *keyWin = nil;
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if (![s isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in ((UIWindowScene *)s).windows) {
                if (w.isKeyWindow) { keyWin = w; break; }
            }
            if (keyWin) break;
        }
        UIViewController *vc = keyWin.rootViewController;
        while (vc.presentedViewController) vc = vc.presentedViewController;
        if ([vc isKindOfClass:[UINavigationController class]]) {
            vc = ((UINavigationController *)vc).topViewController;
        }
        if ([vc isKindOfClass:[UITabBarController class]]) {
            vc = ((UITabBarController *)vc).selectedViewController;
        }
        return WCTGString(vc, @[ @"m_chatName", @"chatName", @"m_nsChatName", @"m_usrName" ]);
    } @catch (__unused NSException *e) {}
    return nil;
}

- (void)openChatWithUsr:(NSString *)usr {
    if (usr.length == 0) return;
    @try {
        Class logic = NSClassFromString(@"MMMsgLogicController");
        id target = nil;
        if (logic) {
            SEL sharedSel = NSSelectorFromString(@"sharedController");
            if ([logic respondsToSelector:sharedSel]) {
                target = ((id (*)(id, SEL))[logic methodForSelector:sharedSel])(logic, sharedSel);
            }
        }
        NSArray<NSString *> *candidates = @[ @"openChatByName:", @"OpenChat:", @"startChatWithUsr:" ];
        for (NSString *name in candidates) {
            SEL sel = NSSelectorFromString(name);
            if (target && [target respondsToSelector:sel]) {
                ((void (*)(id, SEL, id))[target methodForSelector:sel])(target, sel, usr);
                return;
            }
        }
        NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"weixin://dl/chat?%@", usr]];
        if (url) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
            });
        }
    } @catch (__unused NSException *e) {}
}

- (void)handleWrap:(id)wrap {
    WCTGPConfig *cfg = [WCTGPConfig shared];
    if (!cfg.enabled || !wrap) return;

    @autoreleasepool {
        NSString *from = WCTGString(wrap, @[ @"m_nsFromUsr", @"fromUsr" ]);
        NSString *to = WCTGString(wrap, @[ @"m_nsToUsr", @"toUsr" ]);
        NSString *content = WCTGString(wrap, @[ @"m_nsContent", @"m_nsPushContent", @"content" ]);
        NSString *chatUsr = WCTGString(wrap, @[ @"m_nsRealChatUsr", @"chatUsr" ]) ?: from;
        NSString *msgId = WCTGString(wrap, @[ @"m_nsMsgId", @"msgId" ]);
        NSInteger localId = WCTGInt(wrap, @[ @"m_uiMesLocalID", @"localId" ], 0);
        NSInteger type = WCTGInt(wrap, @[ @"m_uiMessageType", @"messageType" ], 1);

        if (type == 10000) return;                       // 系统消息不弹
        if (to.length && from.length && [to isEqualToString:from]) return;

        if (!cfg.showWhenInChat) {
            NSString *cur = [self currentChatName];
            if (cur.length && chatUsr.length && [cur isEqualToString:chatUsr]) return;
        }

        NSString *preview = [self previewForWrap:wrap content:content];
        if (preview.length > 200) {
            preview = [[preview substringToIndex:200] stringByAppendingString:@"…"];
        }

        BOOL isGroup = (chatUsr.length && from.length && ![chatUsr isEqualToString:from]);
        NSString *title;
        if (isGroup) {
            NSString *groupName = [self displayNameForUsr:chatUsr];
            NSString *senderName = [self displayNameForUsr:from];
            title = cfg.showGroupName
                ? [NSString stringWithFormat:@"%@ · %@", groupName, senderName]
                : groupName;
        } else {
            title = [self displayNameForUsr:from];
        }

        NSString *avatar = [self avatarURLForUsr:chatUsr ?: from];
        NSString *key = msgId.length
            ? msgId
            : (localId ? [NSString stringWithFormat:@"L%ld", (long)localId] : nil);

        NSString *tapUsr = (chatUsr ?: from) ?: @""; 
        WCTGLog(@"show title=%@ body=%@ key=%@", title, preview, key);

        [[WCTGPopupCenter shared] showWithTitle:title
                                           body:preview
                                      avatarURL:avatar
                                           seed:(chatUsr ?: from)
                                      dedupeKey:key
                                     tapHandler:^{
            [[WCTGHookBridge shared] openChatWithUsr:tapUsr];
        }];
    }
}

@end

#pragma mark - Hooks

// 1) 微信最主要的收消息入口
%hook CMessageMgr
- (void)AsyncOnAddMsg:(id)msg MsgWrap:(id)wrap {
    %orig;
    [[WCTGHookBridge shared] handleWrap:wrap];
}
- (void)onNewSyncAddMessage:(id)msg {
    %orig;
    [[WCTGHookBridge shared] handleWrap:msg];
}
%end

// 2) 有的版本类名没有 C 前缀
%hook MessageMgr
- (void)AsyncOnAddMsg:(id)msg MsgWrap:(id)wrap {
    %orig;
    [[WCTGHookBridge shared] handleWrap:wrap];
}
%end

%ctor {
    @autoreleasepool {
        [[WCTGPConfig shared] reload];
        WCTGLog(@"loaded, enabled=%d damping=%.2f duration=%.2f",
               (int)[WCTGPConfig shared].enabled,
               [WCTGPConfig shared].enterDamping,
               [WCTGPConfig shared].enterDuration);

        // 回到前台时热重载配置（改 plist 后不用重启微信）
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(__unused NSNotification *n) {
            [[WCTGPConfig shared] reload];
        }];
    }
}
