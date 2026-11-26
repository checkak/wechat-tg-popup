//
//  WCTGPConfig.h
//  TG 风格消息弹窗 —— 可调参数
//
//  所有参数都能在运行时用 plist 覆盖：
//    /var/mobile/Library/Preferences/com.wctg.popup.plist
//  改完不用重启，下一条消息生效。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface WCTGPConfig : NSObject

+ (instancetype)shared;

// ---- 开关 ----
@property (nonatomic, assign) BOOL enabled;          // 总开关
@property (nonatomic, assign) BOOL showWhenInChat;   // 正在和该好友聊天时是否还弹
@property (nonatomic, assign) BOOL haptic;           // 触感反馈
@property (nonatomic, assign) BOOL showGroupName;    // 群聊时显示「群名 · 发送人」

// ---- 尺寸 ----
@property (nonatomic, assign) CGFloat cardInset;     // 左右留白，默认 15
@property (nonatomic, assign) CGFloat cardHeight;    // 卡片高度，默认 64
@property (nonatomic, assign) CGFloat cardRadius;    // 圆角，默认 20
@property (nonatomic, assign) CGFloat avatarSize;    // 头像边长，默认 40
@property (nonatomic, assign) CGFloat topMargin;     // 距屏幕顶部（含灵动岛），默认 60

// ---- 入场（弹簧）----
@property (nonatomic, assign) CGFloat dropFrom;      // 从上方多少 pt 落下，默认 -36
@property (nonatomic, assign) CGFloat enterScale;    // 起始缩放，默认 0.72
@property (nonatomic, assign) NSTimeInterval enterDuration;   // 默认 0.52
@property (nonatomic, assign) CGFloat enterDamping;  // 阻尼比，默认 0.38（<0.4 就很弹）
@property (nonatomic, assign) CGFloat enterVelocity; // 初速度，默认 0.6

// ---- 果冻 ----
@property (nonatomic, assign) BOOL jelly;            // 内容压扁回弹
@property (nonatomic, assign) CGFloat jellyAmount;   // 压扁幅度，默认 0.06

// ---- 停留与收起 ----
@property (nonatomic, assign) NSTimeInterval holdSeconds;    // 默认 3.6
@property (nonatomic, assign) NSTimeInterval exitDuration;   // 默认 0.16
@property (nonatomic, assign) CGFloat exitLift;              // 收起上移，默认 -22

- (void)reload;
@end

NS_ASSUME_NONNULL_END
