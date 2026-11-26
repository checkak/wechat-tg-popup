#import "WCTGPopupView.h"
#import "WCTGPConfig.h"

@interface WCTGPopupView ()
@property (nonatomic, strong) UIView *backgroundView;
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *avatarPlaceholder;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *bodyLabel;
@property (nonatomic, strong) UILabel *tagLabel;
@property (nonatomic, copy) NSString *avatarURLString;
@property (nonatomic, strong) NSURLSessionDataTask *avatarTask;

// 果冻动画用：内容层单独承载压扁回弹
@property (nonatomic, weak) UIView *jellyTarget;
@end

@implementation WCTGPopupView

- (instancetype)initWithWidth:(CGFloat)width {
    WCTGPConfig *cfg = [WCTGPConfig shared];
    CGRect frame = CGRectMake(0, 0, width, cfg.cardHeight);
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor clearColor];
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.16f;
        self.layer.shadowRadius = 16.f;
        self.layer.shadowOffset = CGSizeMake(0, 8);
        self.layer.masksToBounds = NO;
        self.userInteractionEnabled = YES;
        [self buildSubviews];
        [self addGestureRecognizer:[[UITapGestureRecognizer alloc]
                                    initWithTarget:self action:@selector(handleTap)]];
    }
    return self;
}

- (void)buildSubviews {
    WCTGPConfig *cfg = [WCTGPConfig shared];

    // 背景：毛玻璃 + 白色蒙版（视频里是浅色磨砂卡）
    _backgroundView = [[UIView alloc] initWithFrame:self.bounds];
    _backgroundView.layer.cornerRadius = cfg.cardRadius;
    _backgroundView.layer.cornerCurve = kCACornerCurveContinuous;
    _backgroundView.layer.masksToBounds = YES;
    _backgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                       UIViewAutoresizingFlexibleHeight;
    [self addSubview:_backgroundView];

    UIBlurEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialLight];
    _blurView = [[UIVisualEffectView alloc] initWithEffect:effect];
    _blurView.frame = _backgroundView.bounds;
    _blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                 UIViewAutoresizingFlexibleHeight;
    [_backgroundView addSubview:_blurView];

    UIView *white = [[UIView alloc] initWithFrame:_backgroundView.bounds];
    white.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.72];
    white.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                             UIViewAutoresizingFlexibleHeight;
    [_backgroundView addSubview:white];

    // 内容层（果冻动画作用在这一层）
    _contentView = [[UIView alloc] initWithFrame:self.bounds];
    _contentView.backgroundColor = [UIColor clearColor];
    _contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                    UIViewAutoresizingFlexibleHeight;
    [self addSubview:_contentView];
    _jellyTarget = _contentView;

    CGFloat av = cfg.avatarSize;
    _avatarView = [[UIImageView alloc] initWithFrame:CGRectMake(12, (cfg.cardHeight - av) / 2,
                                                               av, av)];
    _avatarView.layer.cornerRadius = av * 0.24f;
    _avatarView.layer.cornerCurve = kCACornerCurveContinuous;
    _avatarView.layer.masksToBounds = YES;
    _avatarView.contentMode = UIViewContentModeScaleAspectFill;
    _avatarView.backgroundColor = [UIColor colorWithWhite:0.90 alpha:1.0];
    [_contentView addSubview:_avatarView];

    _avatarPlaceholder = [[UILabel alloc] initWithFrame:_avatarView.bounds];
    _avatarPlaceholder.textAlignment = NSTextAlignmentCenter;
    _avatarPlaceholder.font = [UIFont systemFontOfSize:av * 0.42 weight:UIFontWeightSemibold];
    _avatarPlaceholder.textColor = [UIColor whiteColor];
    [_avatarView addSubview:_avatarPlaceholder];

    CGFloat textX = CGRectGetMaxX(_avatarView.frame) + 10;
    CGFloat textW = self.bounds.size.width - textX - 12;

    _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(textX, 12, textW, 19)];
    _titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _titleLabel.textColor = [UIColor labelColor];
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_contentView addSubview:_titleLabel];

    _bodyLabel = [[UILabel alloc] initWithFrame:CGRectMake(textX, 32, textW, 18)];
    _bodyLabel.font = [UIFont systemFontOfSize:13.5];
    _bodyLabel.textColor = [UIColor secondaryLabelColor];
    _bodyLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_contentView addSubview:_bodyLabel];

    // 右上角小标（微信 / 群名）
    _tagLabel = [[UILabel alloc] initWithFrame:CGRectMake(self.bounds.size.width - 60, 8, 48, 13)];
    _tagLabel.font = [UIFont systemFontOfSize:9.5 weight:UIFontWeightMedium];
    _tagLabel.textColor = [UIColor tertiaryLabelColor];
    _tagLabel.textAlignment = NSTextAlignmentRight;
    _tagLabel.text = @"微信";
    _tagLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [_contentView addSubview:_tagLabel];
}

#pragma mark - 内容

- (void)configureWithTitle:(NSString *)title
                      body:(NSString *)body
                 avatarURL:(NSString *)avatarURL
                avatarSeed:(NSString *)seed {
    [self refreshContentWithTitle:title body:body];
    self.avatarURLString = avatarURL;
    [self.avatarView setImage:nil];
    self.avatarPlaceholder.text = [self initialFor:seed ?: title];
    self.avatarPlaceholder.textColor = [UIColor whiteColor];
    self.avatarView.backgroundColor = [self colorForSeed:seed ?: title];

    if (avatarURL.length == 0) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    NSURL *url = [NSURL URLWithString:avatarURL];
    if (!url) {
        return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSData *data = [NSData dataWithContentsOfURL:url];
        UIImage *img = data ? [UIImage imageWithData:data] : nil;
        if (!img) {
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || ![self.avatarURLString isEqualToString:avatarURL]) {
                return;
            }
            self.avatarView.image = img;
            self.avatarPlaceholder.hidden = YES;
        });
    });
}

- (void)refreshContentWithTitle:(NSString *)title body:(NSString *)body {
    self.titleLabel.text = title;
    self.bodyLabel.text = body;
}

- (NSString *)initialFor:(NSString *)seed {
    if (seed.length == 0) {
        return @"•";
    }
    return [seed substringToIndex:1].uppercaseString;
}

- (UIColor *)colorForSeed:(NSString *)seed {
    // 稳定配色：同一联系人永远同一个底色
    NSUInteger h = seed.hash;
    CGFloat hue = (h % 360) / 360.0f;
    return [UIColor colorWithHue:hue saturation:0.55 brightness:0.80 alpha:1.0];
}

#pragma mark - 动画（参数来自视频逐帧量测）

- (void)playEntryWithCompletion:(void (^)(BOOL))completion {
    WCTGPConfig *cfg = [WCTGPConfig shared];

    CGAffineTransform start =
        CGAffineTransformConcat(CGAffineTransformMakeTranslation(0, cfg.dropFrom),
                                CGAffineTransformMakeScale(cfg.enterScale, cfg.enterScale));
    self.transform = start;
    self.alpha = 0.02f;
    self.layer.shadowOpacity = 0.0f;

    // 淡入很快，主要是「落下」在起作用
    [UIView animateWithDuration:0.08 delay:0 options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.alpha = 1.0f;
        self.layer.shadowOpacity = 0.16f;
    } completion:nil];

    // 主体：弹簧（ζ≈0.38 → 过冲 ≈27%，峰值 ≈170ms，稳定 ≈600ms）
    [UIView animateWithDuration:cfg.enterDuration
                          delay:0
         usingSpringWithDamping:cfg.enterDamping
          initialSpringVelocity:cfg.enterVelocity
                        options:(UIViewAnimationOptionBeginFromCurrentState |
                                 UIViewAnimationOptionAllowUserInteraction)
                     animations:^{
        self.transform = CGAffineTransformIdentity;
    } completion:completion];

    if (cfg.jelly) {
        [self playJelly];
    }
}

/// 果冻：内容做一次「压扁 → 回弹」，与落下的过冲叠加，产生 Q 弹手感
- (void)playJelly {
    WCTGPConfig *cfg = [WCTGPConfig shared];
    CGFloat amp = cfg.jellyAmount;             // 0.06 → 压扁 6%

    CAKeyframeAnimation *squash =
        [CAKeyframeAnimation animationWithKeyPath:@"transform.scale.y"];
    squash.values = @[@1.0, @(1.0 - amp), @(1.0 + amp * 0.6), @(1.0 - amp * 0.2), @1.0];
    squash.keyTimes = @[@0.0, @0.22, @0.52, @0.78, @1.0];
    squash.duration = MAX(0.28, cfg.enterDuration * 0.85);
    squash.timingFunction = [CAMediaTimingFunction functionWithName:
                             kCAMediaTimingFunctionEaseOut];
    squash.fillMode = kCAFillModeForwards;

    CAKeyframeAnimation *stretch =
        [CAKeyframeAnimation animationWithKeyPath:@"transform.scale.x"];
    stretch.values = @[@1.0, @(1.0 + amp * 0.7), @(1.0 - amp * 0.35), @(1.0 + amp * 0.1), @1.0];
    stretch.keyTimes = squash.keyTimes;
    stretch.duration = squash.duration;
    stretch.timingFunction = squash.timingFunction;

    [self.jellyTarget.layer addAnimation:squash forKey:@"wctg.squash"];
    [self.jellyTarget.layer addAnimation:stretch forKey:@"wctg.stretch"];
}

- (void)playExitWithCompletion:(void (^)(BOOL))completion {
    WCTGPConfig *cfg = [WCTGPConfig shared];

    CGAffineTransform end =
        CGAffineTransformConcat(CGAffineTransformMakeTranslation(0, cfg.exitLift),
                                CGAffineTransformMakeScale(0.94, 0.94));

    [UIView animateWithDuration:cfg.exitDuration
                          delay:0
                        options:(UIViewAnimationOptionCurveEaseIn |
                                 UIViewAnimationOptionBeginFromCurrentState |
                                 UIViewAnimationOptionAllowUserInteraction)
                     animations:^{
        self.transform = end;
        self.alpha = 0.0f;
        self.layer.shadowOpacity = 0.0f;
    } completion:completion];
}

#pragma mark - 交互

- (void)handleTap {
    if (self.onTap) {
        self.onTap();
    }
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    return v ? self : nil;
}

@end
