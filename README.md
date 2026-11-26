# 微信 TG 风格消息弹窗（WCTGPOPUP）

把 Telegram 那种「果冻下落」的消息横幅搬进微信：来消息时卡片从顶部**弹簧落下 → 轻微过冲 → 回弹稳定**，停留 3.6 秒后**向上收走**。点击横幅尽力跳到对应聊天。

> 动画参数不是拍脑袋定的，是对着你给的 `1353274947.mp4` **逐帧量测**出来的，见下面「量测数据」。

---

## 1. 量测数据（视频 886×1920，59.69fps → 886px = 393pt，比例 2.2545）

| 项目 | 实测值 | 换算 / 说明 |
|---|---|---|
| 卡片静止顶边 | y = 135px | **60pt**（灵动岛下方） |
| 卡片高 | 145px | **64pt** |
| 卡片宽 | ≈819px | **≈363pt**（左右各留 15pt） |
| 头像边长 | ≈95px | **≈42pt**（实现用 40pt） |
| 入场起点 | 中心 58.5pt | 比静止位（93.7pt）高 **≈36pt** |
| 入场缩放 | 0.70 → 1.00 | 34ms 时 0.70，235ms 时 1.00 |
| **过冲** | 峰值 103.4pt vs 静止 93.7pt | **+9.7pt ≈ 行程的 27%** |
| **阻尼比** | exp(−ζπ/√(1−ζ²)) = 0.27 | **ζ ≈ 0.38**（弹） |
| 峰值时刻 | **≈170ms** | 周期 ≈340ms → ω_n ≈ 20 rad/s |
| 稳定时刻 | **≈550–600ms** | 之后中心稳定在 93.7pt |
| 收起 | 上移 + 缩小到 ~0.94 + 淡出 | **≈60–160ms**，ease-in |

据此换算成 UIKit 参数（`WCTGPConfig.m` 里的默认值）：

```c
dropFrom        = -36.0    // pt，从上方落下
enterScale      = 0.72     // 起始缩放
enterDuration   = 0.52     // s
enterDamping    = 0.38     // ζ，越小越弹
enterVelocity   = 0.6
holdSeconds     = 3.6
exitDuration    = 0.16
exitLift        = -22.0
```

---

## 2. 「果冻」是怎么做出来的

两层叠加，这是视频里那种 Q 弹手感的关键：

1. **整卡的弹簧**（`UIView animateWithDuration:usingSpringWithDamping:`）
   平移与缩放一起走同一根弹簧 → 落下时**过冲**（+27%），缩放在同一时刻略微超过 1.0 再回弹。
2. **内容的压扁-回弹**（`CAKeyframeAnimation` 作用于 `contentView`）
   `scale.y`: 1.0 → 0.94 → 1.036 → 0.988 → 1.0
   `scale.x`: 1.0 → 1.042 → 0.979 → 1.006 → 1.0
   两轴反相，形成体积守恒的「果冻」形变。

两者叠加的观感：**卡片砸下来 → 内容被压扁一下 → 一起回弹**，和视频一致。

---

## 3. 工程结构

```
wechat_tg_popup/
├─ Makefile                       # Theos（TARGET iphone:clang:latest:15.0, arm64 + arm64e）
├─ Tweak.xm                       # Hook 层：收消息 → 解析 → 交给 Center
├─ WCTGPopupCenter.h/.m           # 调度：穿透 UIWindow、去重、停留计时、点点跳转
├─ WCTGPopupView.h/.m             # 卡片 UI + 全部动画
├─ WCTGPConfig.h/.m               # 参数（默认值 + 运行时 plist 覆盖）
├─ control                        # deb 元信息
└─ layout/Library/MobileSubstrate/DynamicLibraries/WCTGPOPUP.plist   # 只注入 com.tencent.xin
```

### 关键实现点

| 关注点 | 做法 |
|---|---|
| **不影响微信原有逻辑** | 用 `%hook ... { %orig; ... }` 先执行原实现，再旁听；只读字段，不改任何状态 |
| **版本兼容** | 所有私有类/方法（`CMessageMgr`、`MMServiceCenter`、`CContactMgr`、`MMMsgLogicController`）都用 `NSClassFromString` + `respondsToSelector` 探测，取不到就静默跳过 |
| **触摸穿透** | 独立 `UIWindow`（`UIWindowLevelAlert + 100`），`hitTest:` 只放行卡片本身及其子视图，其它事件全透传给微信 |
| **不打扰当前聊天** | 顶层 VC 上取 `m_chatName`，如果正在看这个会话就不弹（可关） |
| **去重** | `m_nsMsgId` / `m_uiMesLocalID` 做 key，同一消息不重复弹；连续消息则「原地换内容 + 再落一次」 |
| **失败静默** | 拿不到昵称/内容/头像都不会崩，退化到彩色首字母 + `[图片]/[语音]` 等占位 |
| **安全兜底** | 所有 KVC 调用包在 `@try` 里；`+defaultCenter` 用 `performSelector` 并屏蔽 leak 警告 |

---

## 4. 编译

需要 **Theos**（macOS / Linux / WSL 均可）：

```bash
export THEOS=~/theos
cd wechat_tg_popup
make package                     # 产出 packages/com.wctg.popup_1.0.0_iphoneos-arm64.deb
make package DEBUG=0 FINALPACKAGE=1
```

只想快速试：

```bash
make clean && make
make install                     # 需配置 THEOS_DEVICE_IP / THEOS_DEVICE_PORT
```

### 已经在 CI 上编好了 ✅

本仓库带 `.github/workflows/build-deb.yml`，跑在 macOS-15 runner 上（Theos + Xcode 的 iPhoneOS SDK）：

```
https://github.com/checkak/wechat-tg-popup/actions
```

最近一次成功构建的产物：

```
com.wctg.popup_1.0.0_iphoneos-arm64.deb   27,048 bytes
sha256  edf2b870330f3bc1a1ac7a1ea8ccaa40fe3b8e2714a3e27cf184b63e7c6eafb1
```

包内结构（实测）：

```
./Library/MobileSubstrate/DynamicLibraries/WCTGPOPUP.dylib    755 root:root  239,152 B
./Library/MobileSubstrate/DynamicLibraries/WCTGPOPUP.plist    644 root:root       87 B
```

dylib 是 **FAT 双架构**（`arm64` + `arm64e`，每个 slice 108,080 B），里面能查到 `[WCTGPOPUP]` 日志前缀与 `wctg.squash` 动画键 —— 说明代码确实编进去了。

### CI 上踩过的 3 个坑（都已修）

| 现象 | 原因 | 修法 |
|---|---|---|
| `Tweak.xm:1:1: unexpected character <U+FEFF>` | Windows 下 `Set-Content -Encoding UTF8` 会写 BOM，Logos 预处理器不认 | 全仓去 BOM、统一 LF（`normalize.py`） |
| `You are missing a filter property list` | 这个 Theos 版本的 `__exists` 只看 `$(CURDIR)`，不递归 `layout/` | 把 `WCTGPOPUP.plist` 放**工程根目录**（Theos 会自动拷进 DynamicLibraries） |
| 包根多出 `./Filter.plist`、属主是 `501:20` | `layout/` 里的副本被合并；macOS 的 `dpkg-deb` 用当前用户打包 | 删掉 `layout/`；用 `dpkg-deb --root-owner-group -Zxz` 重打包 |

---

## 5. 安装

```bash
# 手机上（Filza 或 SSH）
dpkg -i com.wctg.popup_1.0.0_iphoneos-arm64.deb
killall -9 WeChat
```

要求：**越狱 + 已安装 MobileSubstrate/ElleKit 等注入框架**；微信版本建议 8.x（class 名未变）。

---

## 6. 调参（不用重编译）

把下面任意键写进 `/var/mobile/Library/Preferences/com.wctg.popup.plist`，
**回到前台自动热重载**（`UIApplicationDidBecomeActiveNotification`）：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>enabled</key>            <true/>
    <key>showWhenInChat</key>     <false/>
    <key>haptic</key>             <true/>
    <key>showGroupName</key>      <true/>

    <key>cardInset</key>          <real>15</real>
    <key>cardHeight</key>         <real>64</real>
    <key>cardRadius</key>         <real>20</real>
    <key>avatarSize</key>         <real>40</real>
    <key>topMargin</key>          <real>60</real>

    <!-- 想更「果冻」就把 damping 调到 0.30，想更稳就 0.55 -->
    <key>dropFrom</key>           <real>-36</real>
    <key>enterScale</key>         <real>0.72</real>
    <key>enterDuration</key>      <real>0.52</real>
    <key>enterDamping</key>       <real>0.38</real>
    <key>enterVelocity</key>      <real>0.6</real>

    <key>jelly</key>              <true/>
    <key>jellyAmount</key>        <real>0.06</real>

    <key>holdSeconds</key>        <real>3.6</real>
    <key>exitDuration</key>       <real>0.16</real>
    <key>exitLift</key>           <real>-22</real>
</dict>
</plist>
```

调参对照：

| 想要的效果 | 怎么改 |
|---|---|
| 更弹、更「果冻」 | `enterDamping` 0.38 → **0.28**，`jellyAmount` 0.06 → **0.09** |
| 更克制、更像系统通知 | `enterDamping` → **0.6**，`dropFrom` → **-24**，`jelly` → false |
| 落得更快 | `enterDuration` 0.52 → **0.36** |
| 停留更久 | `holdSeconds` → **5.0** |
| 卡片更矮小 | `cardHeight` 64 → **56**，`avatarSize` 40 → **34** |

---

## 7. 已知限制 / 需要你实测确认的点

1. **收消息 hook 的类名**：用的是社区常用的 `CMessageMgr -AsyncOnAddMsg:MsgWrap:`（以及 `MessageMgr` 同名方法与 `onNewSyncAddMessage:`）。
   微信大版本更新偶尔会改类名——如果装上没反应，在 Console 里搜 `[WCTGPOPUP]`：
   - 有 `loaded` 但没有 `show` → hook 没挂着，把微信的可执行文件丢给 `class-dump` 看真实的 `*MessageMgr` 类名，改 `Tweak.xm` 里两个 `%hook` 即可。
2. **点击跳转**是「尽力而为」：依次尝试 `MMMsgLogicController` 的 `openChatByName:` / `OpenChat:` / `startChatWithUsr:`，全失败则退化成 `weixin://dl/chat?<wxid>`。
3. **头像**走 `m_nsHeadImgUrl` / `getHeadImgUrlByType:`；都拿不到就用彩色首字母（同一个人颜色固定）。
4. **群聊**标题为「群名 · 发送人」，可用 `showGroupName=false` 关掉。
5. 本机是 Windows，**没有 Theos/Xcode，无法替你编译**；代码按 iOS 15+ / ObjC ARC 写，`arm64 + arm64e`。首次 `make` 若有报错，把错误贴我，我按行改。

---

## 8. 想直接看动画效果？

不用装越狱也能验证参数：把 `enterDamping=0.38 / enterDuration=0.52 / dropFrom=-36 / enterScale=0.72`
这四个数丢进任意弹簧动画模拟（或下面这段 CSS）就能复现同样的曲线：

```css
@keyframes tgDrop {
  0%   { transform: translateY(-36px) scale(0.72); opacity: 0; }
  12%  { opacity: 1; }
  33%  { transform: translateY(9.7px) scale(1.02); }   /* 过冲 ≈27% */
  62%  { transform: translateY(-2px) scale(0.995); }
  100% { transform: translateY(0) scale(1); opacity: 1; }
}
.card { animation: tgDrop .52s cubic-bezier(.22,1.2,.36,1) both; }
```

---

## 9. v1.1 变更（设置面板 + 稳定性）

### 9.1 设置面板「弹窗动画」

装好后：**设置 → 弹窗动画**（PreferenceLoader 入口，`label` 就叫「弹窗动画」）

| 分组 | 条目 |
|---|---|
| 总开关 | 启用弹窗 / **免打扰会话不弹** / 正在聊天时也弹 / 触感反馈 / 群聊显示群名 |
| 尺寸 | 卡片高度、左右留白、圆角、头像大小、距顶部 |
| 入场动画（果冻） | 落下距离、起始缩放、动画时长、阻尼比、初速度、果冻压扁、果冻幅度 |
| 停留与收起 | 停留时长、收起时长、收起上移 |
| 关于 | 恢复默认设置 |

实现要点：
- 面板是 `PSListController`，但**不链接 `Preferences.framework`**（Xcode SDK 里没有这个私有框架），
  改为自带最小声明 + `-Wl,-undefined,dynamic_lookup`，由设置 App 在运行时提供符号。
- 读写统一走 `CFPreferences` 域 `com.wctg.popup`；
- 每次改动 `CFNotificationCenterPostNotification(Darwin, "com.wctg.popup/changed")`，
  插件侧监听同一通知 → **立刻热重载，不用重启微信**。

### 9.2 闪退修复（这是 v1.0 的真凶）

| 原因 | 说明 | 修法 |
|---|---|---|
| **私有 getter 签名不符** | v1.0 用 `respondsToSelector:` 后直接 `id(*)(id,SEL)` 调用。`content`/`chatName`/`messageType` 这类通用名在微信里可能是**带参方法**或**返回结构体**，零参调用 = 野指针 → 用一阵就闪退 | 改成 `class_getInstanceMethod` + `method_getNumberOfArguments == 2` + `method_getReturnType` 白名单（对象 `@` / 整型 `iIqQBsScC`）才调用 |
| **KVC 探测** | `valueForKey:` 在微信某些类上会抛 `NSUnknownKeyException` 或触发自定义实现 | 彻底不用 KVC，全部走上面的签名安全取值 |
| **`dispatch_once` 重入死锁** | `WCTGPopupCenter -init` 里注册通知时调用了 `[WCTGPopupCenter shared]`，重入 once 块 → 启动即卡死 | 回调里改用 `__weak self` |
| **后台建窗口** | 微信在后台时创建 `UIWindow` 在部分系统上会崩 | `applicationState != Active` 直接返回 |
| **双 hook 双弹** | `CMessageMgr` 与 `MessageMgr` 可能对同一条消息各触发一次 | 200ms 节流 + `msgId` 去重 |
| **窗口残留** | 弹窗停留在系统 UI（来电/通知中心）之上 | 监听 `UIApplicationWillResignActiveNotification` 立即收起 |

另外所有 hook 与 `handleWrap:` 都包了 `@try`，异常只丢当前这一条消息，不影响微信。

### 9.3 免打扰不弹

依据 `CContact` 的 `m_uiDisturbTime`（免打扰到期时间戳）：

```objc
long long disturb = WCTGInteger(contact, @"m_uiDisturbTime");
if (disturb > 1e9)  return disturb > now;   // 绝对时间戳，未过期=静音中
if (disturb > 0)    return YES;             // 少数版本写剩余秒数
```

旧版本兼容字段：`m_bDisturb` / `m_bMute`。
开关在面板里叫「免打扰会话不弹」，默认 **开**。

日志里会打印 `skip muted chat <wxid>`，方便你确认生效。