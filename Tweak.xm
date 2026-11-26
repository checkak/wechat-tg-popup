//
//  Tweak.xm
//  WeChat TG 风格消息弹窗
//
//  闪退防护（v1.1 重点）：
//   1) 私有字段一律「校验方法签名」再调用：
//        · 只接受 0 参方法（method_getNumberOfArguments == 2）
//        · 只接受返回对象 '@' 或整型 'i/q/I/Q/B/c/s'
//      以前 respondsToSelector: 之后就按 id(*)(id,SEL) 调，遇到同名带参方法
//      或返回结构体的方法会直接野指针 → 用一阵就闪退。
//   2) 完全不用 KVC valueForKey:（微信部分类改写了它，可能抛/崩）
//   3) 整条处理链包 @try，任何异常只丢这一条消息，不影响微信
//   4) 只在前台弹；窗口/视图全部在主线程
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "WCTGPopupCenter.h"
#import "WCTGPConfig.h"

#define WCTGLog(fmt, ...) NSLog(@"[WCTGPOPUP] " fmt, ##__VA_ARGS__)

#pragma mark - 签名安全的取值

/// 只调用「零参、返回对象」的方法
static id WCTGObject(id obj, NSString *selName) {
    if (!obj || selName.length == 0) return nil;
    @try {
        Class cls = object_getClass(obj);
        if (!cls) return nil;
        SEL sel = NSSelectorFromString(selName);
        Method m = class_getInstanceMethod(cls, sel);
        if (!m) return nil;
        if (method_getNumberOfArguments(m) != 2) return nil;   // 必须是 (self, _cmd)

        char ret[8] = {0};
        method_getReturnType(m, ret, sizeof(ret));
        if (ret[0] != '@') return nil;                        // 只接受对象返回

        IMP imp = method_getImplementation(m);
        return ((id (*)(id, SEL))imp)(obj, sel);
    } @catch (__unused NSException *e) {
        return nil;
    }
}

/// 只调用「零参、返回整型」的方法（bool / int / long 等）
static long long WCTGInteger(id obj, NSString *selName) {
    if (!obj || selName.length == 0) return 0;
    @try {
        Class cls = object_getClass(obj);
        if (!cls) return 0;
        SEL sel = NSSelectorFromString(selName);
        Method m = class_getInstanceMethod(cls, sel);
        if (!m) return 0;
        if (method_getNumberOfArguments(m) != 2) return 0;

        char ret[8] = {0};
        method_getReturnType(m, ret, sizeof(ret));
        if (strchr("iIqQBsScC", ret[0]) == NULL) return 0;    // 只接受整型返回

        IMP imp = method_getImplementation(m);
        return ((long long (*)(id, SEL))imp)(obj, sel);
    } @catch (__unused NSException *e) {
        return 0;
    }
}

static NSString *WCTGString(id obj, NSArray<NSString *> *keys) {
    for (NSString *k in keys) {
        id v = WCTGObject(obj, k);
        if ([v isKindOfClass:[NSString class]] && [v length] > 0) {
            return v;
        }
    }
    return nil;
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
            id c = ((id (*)(id, SEL, id))[mgr methodForSelector:byName])(mgr, byName, usr);
            return c;
        }
    } @catch (__unused NSException *e) {}
    return nil;
}

- (NSString *)displayNameForUsr:(NSString *)usr {
    id contact = [self contactForUsr:usr];
    NSString *n = contact ? WCTGString(contact, @[ @"m_nsNickName", @"m_nsRemark" ]) : nil;
    if (n.length) return n;
    if (usr.length > 10) return [usr substringFromIndex:usr.length - 6];
    return usr.length ? usr : @"微信";
}

- (NSString *)avatarURLForUsr:(NSString *)usr {
    id contact = [self contactForUsr:usr];
    if (!contact) return nil;

    NSString *u = WCTGString(contact, @[ @"m_nsHeadImgUrl", @"m_nsHeadImgUrlBig" ]);
    if (u.length) return u;

    BOOL isGroup = WCTGInteger(contact, @"m_uiChatRoomStatus") != 0;
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

#pragma mark 免打扰

/// 判断某个会话是否「消息免打扰」
/// 依据 CContact 的 m_uiDisturbTime（到期时间戳）。
/// 同时兼容部分版本把剩余秒数写在这里的情况。
- (BOOL)isChatMuted:(NSString *)chatUsr {
    id contact = [self contactForUsr:chatUsr];
    if (!contact) return NO;

    long long disturb = WCTGInteger(contact, @"m_uiDisturbTime");
    if (disturb > 0) {
        long long now = (long long)[[NSDate date] timeIntervalSince1970];
        if (disturb > 1000000000LL) {
            return disturb > now;                   // 绝对时间戳
        }
        return YES;                                 // 剩余秒数（>0 即静音中）
    }

    // 少数版本用布尔字段
    if (WCTGInteger(contact, @"m_bDisturb") == 1) return YES;
    if (WCTGInteger(contact, @"m_bMute") == 1) return YES;
    return NO;
}

#pragma mark 其它

- (NSString *)previewForWrap:(id)wrap content:(NSString *)content {
    long long type = WCTGInteger(wrap, @"m_uiMessageType");
    if (type == 0) type = WCTGInteger(wrap, @"messageType");

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
        return WCTGString(vc, @[ @"m_chatName", @"m_nsChatName" ]);
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
        for (NSString *name in @[ @"openChatByName:", @"OpenChat:", @"startChatWithUsr:" ]) {
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

#pragma mark 入口

- (void)handleWrap:(id)wrap {
    WCTGPConfig *cfg = [WCTGPConfig shared];
    if (!cfg.enabled || !wrap) return;

    @try {
        @autoreleasepool {
            NSString *from = WCTGString(wrap, @[ @"m_nsFromUsr" ]);
            NSString *to = WCTGString(wrap, @[ @"m_nsToUsr" ]);
            NSString *content = WCTGString(wrap, @[ @"m_nsContent", @"m_nsPushContent" ]);
            NSString *chatUsr = WCTGString(wrap, @[ @"m_nsRealChatUsr" ]) ?: from;
            NSString *msgId = WCTGString(wrap, @[ @"m_nsMsgId" ]);
            long long localId = WCTGInteger(wrap, @"m_uiMesLocalID");
            long long type = WCTGInteger(wrap, @"m_uiMessageType");

            if (type == 10000) return;                            // 系统消息
            if (to.length && from.length && [to isEqualToString:from]) return;   // 自己发的

            // ★ 免打扰会话不弹
            if (cfg.mutedSuppress && [self isChatMuted:chatUsr]) {
                WCTGLog(@"skip muted chat %@", chatUsr);
                return;
            }

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
            NSString *key = msgId.length ? msgId
                : (localId ? [NSString stringWithFormat:@"L%lld", localId] : nil);
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
    } @catch (NSException *e) {
        WCTGLog(@"handleWrap exception: %@", e.reason);
    }
}

@end

#pragma mark - Hooks

%hook CMessageMgr
- (void)AsyncOnAddMsg:(id)msg MsgWrap:(id)wrap {
    %orig;
    @try {
        [[WCTGHookBridge shared] handleWrap:wrap];
    } @catch (NSException *e) {
        WCTGLog(@"hook CMessageMgr exception: %@", e.reason);
    }
}
- (void)onNewSyncAddMessage:(id)msg {
    %orig;
    @try {
        [[WCTGHookBridge shared] handleWrap:msg];
    } @catch (NSException *e) {
        WCTGLog(@"hook sync exception: %@", e.reason);
    }
}
%end

%hook MessageMgr
- (void)AsyncOnAddMsg:(id)msg MsgWrap:(id)wrap {
    %orig;
    @try {
        [[WCTGHookBridge shared] handleWrap:wrap];
    } @catch (NSException *e) {
        WCTGLog(@"hook MessageMgr exception: %@", e.reason);
    }
}
%end

%ctor {
    @autoreleasepool {
        [[WCTGPConfig shared] reload];
        WCTGLog(@"loaded enabled=%d mutedSuppress=%d damping=%.2f duration=%.2f",
               (int)[WCTGPConfig shared].enabled,
               (int)[WCTGPConfig shared].mutedSuppress,
               [WCTGPConfig shared].enterDamping,
               [WCTGPConfig shared].enterDuration);

        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(__unused NSNotification *n) {
            [[WCTGPConfig shared] reload];
        }];
    }
}
