#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 单条弹窗卡片：毛玻璃白卡 + 头像 + 昵称 + 正文
/// 动画全部按视频实测参数实现（见 WCTGPConfig）
@interface WCTGPopupView : UIView

@property (nonatomic, copy, nullable) void (^onTap)(void);

- (instancetype)initWithWidth:(CGFloat)width;
- (void)configureWithTitle:(NSString *)title
                      body:(NSString *)body
                  avatarURL:(nullable NSString *)avatarURL
                 avatarSeed:(nullable NSString *)seed;

- (void)playEntryWithCompletion:(nullable void (^)(BOOL finished))completion;
- (void)playExitWithCompletion:(nullable void (^)(BOOL finished))completion;
- (void)refreshContentWithTitle:(NSString *)title body:(NSString *)body;

@end

NS_ASSUME_NONNULL_END
