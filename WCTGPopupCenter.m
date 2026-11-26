#import "WCTGPopupCenter.h"
#import "WCTGPopupView.h"
#import "WCTGPConfig.h"

@interface WCTGPopupWindow : UIWindow
@property (nonatomic, weak) UIView *cardView;
@end

@implementation WCTGPopupWindow
// 只让卡片本身接收触摸，其它事件透传给微信
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    UIView *card = self.cardView;
    if (!hit || !card) return nil;
    if (hit == card || [hit isDescendantOfView:card]) return hit;
    return nil;
}
@end

@interface WCTGPopupCenter ()
@property (nonatomic, strong) WCTGPopupWindow *window;
@property (nonatomic, strong) WCTGPopupView *card;
@property (nonatomic, strong) NSTimer *holdTimer;
@property (nonatomic, strong) NSMutableSet<NSString *> *recentKeys;
@property (nonatomic, copy) void (^pendingTap)(void);
@property (nonatomic, assign) NSTimeInterval lastShowTime;
@end

@implementation WCTGPopupCenter

+ (WCTGPopupCenter *)shared {
    static WCTGPopupCenter *c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ c = [WCTGPopupCenter new]; });
    return c;
}

- (instancetype)init {
    if ((self = [super init])) {
        _recentKeys = [NSMutableSet set];
        // 注意：这里不能用 [WCTGPopupCenter shared]，会重入 dispatch_once 造成死锁
        __weak typeof(self) weakSelf = self;
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationWillResignActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(__unused NSNotification *n) {
            [weakSelf dismiss];
        }];
    }
    return self;
}

- (void)reloadConfig {
    [[WCTGPConfig shared] reload];
}

#pragma mark - 展示

- (void)showWithTitle:(NSString *)title
                 body:(NSString *)body
            avatarURL:(NSString *)avatarURL
                 seed:(NSString *)seed
            dedupeKey:(NSString *)key
           tapHandler:(void (^)(void))tapHandler {
    WCTGPConfig *cfg = [WCTGPConfig shared];
    if (!cfg.enabled) {
        return;
    }
    if (title.length == 0 && body.length == 0) {
        return;
    }

    // 去重：同一条消息不重复弹
    if (key.length) {
        if ([self.recentKeys containsObject:key]) {
            return;
        }
        [self.recentKeys addObject:key];
        if (self.recentKeys.count > 64) {
            [self.recentKeys removeObject:self.recentKeys.anyObject];
        }
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        // 只在前台弹（后台创建 UIWindow 在部分系统上会崩）
        if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) {
            return;
        }
        // 两个 hook 可能对同一条消息各触发一次，200ms 内只认第一条
        NSTimeInterval now = [NSDate date].timeIntervalSince1970;
        if (now - self.lastShowTime < 0.2 && !(self.card && self.card.superview)) {
            return;
        }
        self.lastShowTime = now;

        self.pendingTap = tapHandler;

        // 已有卡片在显示：原地换内容并「再落一次」，对应视频里连续消息的连击感
        if (self.card && self.card.superview) {
            [self.card refreshContentWithTitle:title body:body];
            [self.card.layer removeAllAnimations];
            self.card.transform = CGAffineTransformMakeTranslation(0, cfg.dropFrom * 0.35);
            [self.card playEntryWithCompletion:nil];
            [self restartHoldTimer];
            return;
        }

        [self buildWindowIfNeeded];
        if (!self.window) return;
        CGFloat width = self.window.bounds.size.width - cfg.cardInset * 2;
        WCTGPopupView *card = [[WCTGPopupView alloc] initWithWidth:width];
        card.frame = CGRectMake(cfg.cardInset, cfg.topMargin, width, cfg.cardHeight);
        card.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
                                UIViewAutoresizingFlexibleRightMargin;
        __weak typeof(self) weakSelf = self;
        card.onTap = ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (self.pendingTap) {
                self.pendingTap();
            }
            [self dismiss];
        };
        [card configureWithTitle:title body:body avatarURL:avatarURL avatarSeed:seed];
        [self.window.rootViewController.view addSubview:card];
        self.window.cardView = card;
        self.card = card;
        self.window.hidden = NO;

        if (cfg.haptic) {
            UIImpactFeedbackGenerator *g =
                [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
            [g prepare];
            [g impactOccurred];
        }

        [card playEntryWithCompletion:nil];
        [self restartHoldTimer];
    });
}

- (void)buildWindowIfNeeded {
    if (self.window) {
        return;
    }
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]] &&
            s.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)s;
            break;
        }
    }
    if (!scene) {
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]]) {
                scene = (UIWindowScene *)s;
                break;
            }
        }
    }
    if (!scene) {
        return;
    }

    WCTGPopupWindow *win = [[WCTGPopupWindow alloc] initWithWindowScene:scene];
    win.frame = scene.coordinateSpace.bounds;
    win.windowLevel = UIWindowLevelAlert + 100;
    win.backgroundColor = [UIColor clearColor];
    win.rootViewController = [UIViewController new];
    win.rootViewController.view.backgroundColor = [UIColor clearColor];
    win.hidden = NO;
    self.window = win;
}

#pragma mark - 停留 / 收起

- (void)restartHoldTimer {
    [self.holdTimer invalidate];
    WCTGPConfig *cfg = [WCTGPConfig shared];
    self.holdTimer = [NSTimer scheduledTimerWithTimeInterval:MAX(0.8, cfg.holdSeconds)
                                                      target:self
                                                    selector:@selector(holdFired:)
                                                    userInfo:nil
                                                     repeats:NO];
}

- (void)holdFired:(NSTimer *)t {
    [self dismiss];
}

- (void)dismiss {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.holdTimer invalidate];
        self.holdTimer = nil;
        WCTGPopupView *card = self.card;
        if (!card) {
            return;
        }
        self.card = nil;
        [card playExitWithCompletion:^(BOOL finished) {
            [card removeFromSuperview];
            self.window.hidden = YES;
        }];
    });
}

@end
