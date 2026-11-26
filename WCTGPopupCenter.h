#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 弹窗调度中心：管窗口、去重、队列、停留计时
@interface WCTGPopupCenter : NSObject

@property (class, nonatomic, readonly) WCTGPopupCenter *shared;

/// 主入口：来一条消息就调这个
/// @param title      显示名（好友昵称 / 群名 · 发送人）
/// @param body       消息内容
/// @param avatarURL  头像地址（可为 nil，会退化成彩色首字母）
/// @param seed       用于稳定配色的种子（一般是 wxid）
/// @param key        去重键（一般是 msgId / localId）
/// @param tapHandler 点击回调（可为 nil）
- (void)showWithTitle:(NSString *)title
                 body:(NSString *)body
            avatarURL:(nullable NSString *)avatarURL
                seed:(nullable NSString *)seed
            dedupeKey:(nullable NSString *)key
           tapHandler:(nullable void (^)(void))tapHandler;

- (void)dismiss;
- (void)reloadConfig;
@end

NS_ASSUME_NONNULL_END
