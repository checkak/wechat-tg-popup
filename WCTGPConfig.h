#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 运行时配置。domain 与设置面板一致：com.wctg.popup
/// 文件位置：/var/mobile/Library/Preferences/com.wctg.popup.plist
@interface WCTGPConfig : NSObject

+ (instancetype)shared;

// ---- 开关 ----
@property (nonatomic, assign) BOOL enabled;          // 总开关
@property (nonatomic, assign) BOOL mutedSuppress;    // 免打扰会话不弹（默认 YES）
@property (nonatomic, assign) BOOL showWhenInChat;   // 正在和该好友聊天时是否还弹
@property (nonatomic, assign) BOOL haptic;           // 触感反馈
@property (nonatomic, assign) BOOL showGroupName;    // 群聊显示「群名 · 发送人」

// ---- 尺寸 ----
@property (nonatomic, assign) CGFloat cardInset;     // 左右留白
@property (nonatomic, assign) CGFloat cardHeight;    // 卡片高度
@property (nonatomic, assign) CGFloat cardRadius;    // 圆角
@property (nonatomic, assign) CGFloat avatarSize;    // 头像边长
@property (nonatomic, assign) CGFloat topMargin;     // 距屏幕顶部

// ---- 入场（弹簧）----
@property (nonatomic, assign) CGFloat dropFrom;      // 从上方多少 pt 落下（负值）
@property (nonatomic, assign) CGFloat enterScale;    // 起始缩放
@property (nonatomic, assign) NSTimeInterval enterDuration;
@property (nonatomic, assign) CGFloat enterDamping;  // 阻尼比，越小越弹
@property (nonatomic, assign) CGFloat enterVelocity;

// ---- 果冻 ----
@property (nonatomic, assign) BOOL jelly;
@property (nonatomic, assign) CGFloat jellyAmount;

// ---- 停留与收起 ----
@property (nonatomic, assign) NSTimeInterval holdSeconds;
@property (nonatomic, assign) NSTimeInterval exitDuration;
@property (nonatomic, assign) CGFloat exitLift;

- (void)reload;
+ (void)resetToDefaults;

@end

NS_ASSUME_NONNULL_END
