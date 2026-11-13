# fmusic 本地/WebDAV Fork — AI 接续说明

> 最后更新：2026-11-14（Mac Catalyst / macOS 27 / Xcode 27.1）
> 写给接手的 AI：本文档自包含，读完就能开工。仓库里的 `HANDOFF.md` 是更早的逐日日志，
> 部分内容已过时（例如“大面积未提交”“最后提交 bdee704”），冲突时以本文档为准。

## 0. 一句话状态

桌面歌词已按 LyricsX Next 重写（clear Liquid Glass、逐字波浪/长音光晕、双缓冲换行、五键控制条），
设置侧栏已对齐首页并加入可用的设置搜索；2026-11-14 用户明确要求推送 GitHub 并发版，发布目标
`main` + tag `v0.3.0`（CI 出 DMG 并附到 Release）。本轮提交后工作树应为干净；
`feature/webdav-local` 与 `origin/main` 同步到同一个发布提交。

## 1. 项目与环境

- 仓库：`/Users/apple/Desktop/AI/Quder/fmusic`
- 分支：`feature/webdav-local`；`origin` = `lemonevo/fmusic`（私有），`upstream` 只作参考，不要推。
- App：版本 2.1.2 (1)，Bundle ID `lol.levo.fmusic`，Deployment Target iOS 26（Catalyst），需 Xcode 27 / macOS 27 SDK。
- 只保留 **本地文件夹 + WebDAV** 两种音源；Subsonic/Ampache 已删；没有 Last.fm/scrobble。
- 用户数据：WebDAV 账号、约 40 艺人 / 38 专辑 / 53 首歌、播放缓存约 1.8 GB。
  **不要清 `~/Library/Application Support/fmusic`、不要清播放缓存、不要重装账号。**
- 调试 App 可能正在后台播放（用户在用）；重启用
  `osascript -e 'tell application "fmusic" to quit'`，等 2 秒再 `open <app>`，不要 `kill -9`。

上一版 v0.2.0 = `ad6efb8`。v0.3.0 在此之上包含：

| 提交 | 内容 |
|---|---|
| `47c5ce7` | 去重图标素材，缩小包体（DMG ≈ 10.5 MB） |
| `38989ef` | WebDAV FLAC 流式 seek 从帧边界重新解析（修 -108） |
| `b1975cc` | 桌面歌词按 LyricsX 原理重写（玻璃 + 逐字遮罩 + 行进动效） |
| 本轮发布提交 | 双缓冲换行、五键控制条与单曲偏移、设置侧栏搜索、播放/索引热路径优化 |

## 2. 构建、运行、验证

```bash
cd /Users/apple/Desktop/AI/Quder/fmusic
xcodebuild -project fmusic.xcodeproj -scheme fmusic -configuration Debug \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath /tmp/fmusic-build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build

# 必须：重签成真实 bundle id，否则 Now Playing 身份会退化成 "fmusic"
codesign --force --deep --sign - --identifier lol.levo.fmusic \
  /tmp/fmusic-build/Build/Products/Debug-maccatalyst/fmusic.app

open /tmp/fmusic-build/Build/Products/Debug-maccatalyst/fmusic.app
```

- 必须带 `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`，否则没有 provisioning profile 会直接失败。
- **构建后必须 codesign**：关闭签名时 main binary 的签名标识会变成 `fmusic`，MediaRemote 就把这个 App 报成 `fmusic`；
  LyricsX Next 等 Now Playing 客户端按 bundle id 匹配不到运行中的 App，会显示“当前来源不是音乐播放器”。
  重签后 `codesign -dv` 应显示 `Identifier=lol.levo.fmusic`。`/Applications/fmusic.app` 本身是正确签名的，所以安装版没这个问题。
- 当前调试产物固定在 `/tmp/fmusic-build/...`；如果换目录，`open` 时用**完整路径**，防止拉起 DerivedData 里的旧包。
- 没有 CI 门禁：`xcodebuild` 成功不代表界面正确，视觉改动必须打开 App 看真实渲染。

### 2.1 Release 构建与发布

```bash
xcodebuild -project fmusic.xcodeproj -scheme fmusic -configuration Release \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath /tmp/fmusic-release-build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  ARCHS=arm64 build

codesign --force --deep --sign - \
  /tmp/fmusic-release-build/Build/Products/Release-maccatalyst/fmusic.app
```

- ad-hoc 重签后 `Identifier` 仍是 `lol.levo.fmusic`（上一版 v0.2.0 的 DMG 已核实）。
- 推 `main` 会跑 `.github/workflows/build-dmg.yml`，产出 `fmusic-dmg` artifact；
  推 `v*` tag 会额外把 `fmusic.dmg` + sha256 附到 GitHub Release。
- 2026-11-14 用户已明确授权本轮推送与发版（`v0.3.0`）；日常仍遵循“用户明确要求才 push/tag”。

### 2.2 窗口与截图（看清浮窗最可靠的方式）

`CGWindowList` 坐标是**屏幕左上原点**，AppKit `window.frame` 是**左下原点**，换算：
`cgY = screenHeight − frame.origin.y − frame.height`（本机屏幕 1710×1112 pt）。

```swift
// /tmp/winlist.swift：列出 fmusic 的所有在屏窗口
import CoreGraphics
import Foundation
let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
for info in (CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] ?? []) {
  guard (info[kCGWindowOwnerName as String] as? String ?? "").lowercased().contains("fmusic") else { continue }
  print(info[kCGWindowOwnerPID as String] ?? "", info[kCGWindowNumber as String] ?? "",
        info[kCGWindowLayer as String] ?? "", info[kCGWindowBounds as String] ?? "")
}
```

```bash
xcrun swiftc -O /tmp/winlist.swift -o /tmp/winlist && /tmp/winlist
screencapture -x -R467,937,760,82 /tmp/panel.png   # -R 用左上原点的屏幕坐标
```

桌面歌词浮窗特征：`layer=3`、无窗口名、宽固定 760、高度随行数变化。
逐字填充要连拍才能看清：`for i in $(seq 1 15); do screencapture -x -R<x,y,w,h> /tmp/b-$i.png; sleep 0.2; done`。

### 2.3 CUA（电脑控制）

- `node_repl` + `@qoder-space/computer-use`，`getApp()` 传 **App 全路径**。
- 播放中 AX 元素 ID 每个 tick 都变：**取树和点击要在同一次调用里完成**。
- 启动/切换歌曲优先点主窗口的播放按钮；点击会让 fmusic 抢前台，用户正在浏览时注意别反复操作。
- 设置窗口（`Cmd+,`）有时不在 AX 树里：不要硬点，直接改 plist（见 2.3）。

### 2.4 直接改设置（App 必须先退出）

设置存在 `~/Library/Preferences/lol.levo.fmusic.plist` 的 `settings.user`（JSON Data）：

```bash
# 先退出 App
python3 - <<'EOF'
import plistlib, json, os
p = os.path.expanduser("~/Library/Preferences/lol.levo.fmusic.plist")
d = plistlib.load(open(p, 'rb'))
j = json.loads(d["settings.user"].decode('utf-8'))
j["_isDesktopLyricsEnabled"] = True
j["_desktopLyricsBackgroundOpacity"] = 74   # 0=全透明 100=不透明
j["_desktopLyricsFontSize"] = 1             # 0=24 1=30 2=36
j["_desktopLyricsAlignment"] = 1            # 0=左 1=中 2=右
d["settings.user"] = json.dumps(j).encode('utf-8')
plistlib.dump(d, open(p, 'wb'))
EOF
killall cfprefsd
```

## 3. 桌面歌词（刚重写，最可能被要求继续改）

### 3.1 文件

| 路径 | 作用 |
|---|---|
| `fmusic/LyricsOverlay/DesktopLyricsWindow.swift` | 渲染器 + 浮窗控制器（本次重写） |
| `fmusic/LyricsOverlay/LyricsOverlayManager.swift` | 订阅播放时钟，喂桌面浮窗和菜单栏；已去掉 30 fps 限流 |
| `fmusic/LyricsOverlay/LyricsLineTracker.swift` | 当前行/下一行/音节进度快照，提前 0.25 s 切行 |
| `fmusic/LyricsOverlay/MenuBarLyricsController.swift` | 菜单栏歌词（NSStatusBar 走 runtime） |
| `fmusic/Screens/View/Lyrics/LyricsLineLayers.swift` | 与播放器歌词视图共用：`LyricsTimingMap`、`LyricsTextLayout`、`LyricsSyllableMaskLayer` |
| `fmusic/SwiftUI/Settings/Display/DisplaySettingsView.swift` | 设置 → 显示里的两个开关和外层参数 |
| `fmusicKit/Storage/Settings.swift` | `UserSettings` 字段（JSON key 都是下划线前缀） |

### 3.2 结构（从下到上）

```
FMDesktopLyricsPanel（runtime 子类，borderless + nonactivating，styleMask = 1<<7；
                 覆写 _hasActiveAppearance / _hasActiveAppearanceIgnoringKeyFocus 返回 YES）
└─ NSView（layer-backed，内容视图）
   ├─ NSGlassEffectView（z=0；**clear** Liquid Glass，圆角 32，强制 darkAqua）
   ├─ CAGradientLayer scrim（z=1；黑，顶部 0.60×opacity，0.38/0.76 处 0.66/0.28，底部全透明）
   ├─ CALayer 纯色兜底（z=0.5；仅「降低透明度」开启时显示 0.12 灰）
   ├─ CALayer 细描边（z=2；glass 模式下隐藏，交给 AppKit 原生高光）
   ├─ CALayer content（z=3）
   │  ├─ headerLayer          「歌名 · 歌手」左上角小字（11 pt medium）
   │  ├─ nextLayer            下一句（缩小的预栅格化图）
   │  └─ surfaceA / surfaceB  主歌词双缓冲；当前句 + 离场句各占一套，换行时交替
   │     ├─ baseLayer         未唱（dim）图；无音节时放亮图
   │     ├─ sungLayer         亮图 + LyricsSyllableMaskLayer（无分字图时的整行兜底）
   │     └─ syllableContainer 每个字一张亮图 + 3 pt 水平渐变遮罩（扫光 + 波浪形变；
   │                           长音时亮图层自带白色 glyph-shaped 光晕）
   └─ NSVisualEffectView toolbarContainer（z=10；166×34 HUD 胶囊 + 5 个 runtime NSButton）
      ├─ timer                歌词同步面板（单曲偏移 ±0.1 s / 重置）
      ├─ expand               打开主窗口
      ├─ lock.fill/open       位置锁（movableByWindowBackground）
      ├─ cursorarrow.rays/slash  点击穿透（控制条自动移入独立小面板）
      └─ xmark                关闭桌面歌词（写入 settings.user）
```

- **悬停控制条**：50 ms 轮询 `NSEvent.mouseLocation`（runtime class method），指针在窗口 frame 内时淡入；
  指针离开后 0.2 s 隐藏。图标 15 pt medium，布局对齐 LyricsX Next 的 `OverlayControlLayout`：
  宽 166、高 34、右上 14/8、按钮 30×30、间距 2、内边距 4。
- **玻璃的激活态**：非激活窗口的 Liquid Glass 会退化成一层浅灰雾（用户截图里的“毛玻璃”就是这个），
  所以面板用 runtime 子类覆写 `_hasActiveAppearance` / `_hasActiveAppearanceIgnoringKeyFocus` 恒为 YES，
  即使 fmusic 在后台也保持 clear 折射。
- **点击穿透**：cursor 按钮把 `ignoresMouseEvents` 置 true，并自动位置锁；控制条搬到独立的 166×34
  `NSPanel`（level +1）继续可用。设置里的 `_isDesktopLyricsLocked` 与这个按钮是同一状态。
  解锁（lock 按钮）会同时关闭点击穿透；关闭穿透不会自动解锁，与 LyricsX Next 一致。
- **歌词同步面板**：timer 弹 340×176 的独立 `NSPanel`（level +2，NSVisualEffectView popover + 深色遮罩），
  显示「单曲偏移 / 通用 / 合计」，延后/提前 0.1 s、重置；点外部、关闭按钮都会收起。
- **单曲偏移**：存 `UserDefaults` 的 `fmusic.desktopLyrics.songOffsets`（songID → ms，±5 s）；
  实际歌词偏移 = `settings.user.lyricsOffsetMs` + 单曲偏移。
- **两种“锁”**：设置里的 `_isDesktopLyricsLocked` = 点击穿透；控制条的锁按钮 = 位置锁
  （`fmusic.desktopLyrics.positionLocked`），两者独立但穿透会强制位置锁。

- **栅格化策略**：分字行（YRC）每个音节 dim/bright/glow 各一张 `CGImage`，三张图共享同一个
  `LyricsTextLayout`；整行 dim/bright 只在没有分字渲染时（无时间轴行、>64 音节、分字全部失败）生成，
  作为整行遮罩兜底。播放时钟只改遮罩/图层变换，不重排文字。
  60 Hz 更新来自 `BackendAudioPlayer` 的歌词 Timer（1/60 s）→ `didLyricsTimeChange` → `LyricsOverlayManager.render`。
- **双缓冲换行**：`PrimarySurface` A/B 轮流承载当前句；旧句保持活的 mask/glow 直接淡出 0.20 s，
  不再栅格化整行快照，换行主路径的整行栅格化为 0 次。详见“性能收口 → 双缓冲换行”。
- 遮罩复用播放器歌词页的 `LyricsSyllableMaskLayer`（渐变羽化 3 pt，对齐 LyricsX `clipReveal` 的 3 pt 上限）；
  TextKit 的 rect 是**左上原点**，进 CALayer 前统一 `y = height - rect.maxY` 翻转。
- **长音强调**：`DesktopLyricsEmphasis.value(progress:duration:)`，`duration > 0.45 s` 时按 LyricsX 包络
  （`smooth((d-0.45)/1.15) * smoother(p/0.42) * (1 - smoother((p-0.70)/0.30))`）做最多 5.5% 放大、
  3.5% 行高上浮和白色 glyph-shadow 光晕。门槛是**词/音节 cue 本身的时长**，不是整行时长：
  0.45 s 起亮、1.6 s 达到满强度（0.8 s≈0.22、1.0 s≈0.47、1.2 s≈0.72）；包络在前 42% 升起、
  70% 后回落，所以光晕只在字被唱出来的过程中出现，唱完即归零。LyricsX 对纯 LRC 不产生
  cue，因此没有高亮；本项目为 LRC 合成按字时间，分组后的词跨度仍可能超过门槛，会出现近似
  光晕——这是与源码的已知差异（YRC 才是精确行为）。
- **行进动效**：切行时旧行快照上移 3 pt、0.20 s 淡出；新行如果正是刚才的“下一句”，
  从预览行的距顶位置和 12/26 比例开始，0.62 s 生长到主行（LyricsX 的 promotion）；否则
  从下方 10 pt、0.985 比例淡入（0.5 s）。
- **圆角**：`min(34, max(18, 高度 × 0.32))`（`panelCornerRadius(forHeight:)`），比全胶囊“方一点”，
  scrim/描边/玻璃同步更新。
- **自动高度**：宽固定 620；高度 = 上/下 10 + header（+6 间距）+ 当前行 + (3 + 下一句)。改高度时**顶边固定**
  （`origin.y += oldH - newH`）；可见状态下用 60 Hz Timer 逐帧改 `NSWindow` frame，增长 0.34 s、收缩 0.48 s。
- 面板位置存 `UserDefaults` 的 `fmusic.desktopLyrics.frame`（左下原点数组），恢复时用存档高度，避免每次启动高度跳变导致位置漂移。
- 面板是 `NSPanel` + nonactivating：点击不会激活 fmusic；`movableByWindowBackground` 可拖动；
  「锁定」= `ignoresMouseEvents`；「置顶」= level 3 / level 0。

### 3.3 关键常量（要调视觉先看这里）

`DesktopLyricsRenderer`：宽 620、水平内边距 24、上下 10、行距 3、header 间距 6、玻璃圆角固定 32；
主字 semibold（24/26/30，用户选 26，和 LyricsX 的默认字号一致）、tracking **-0.4**（`OverlayLyricsSurface` 的 `.tracking(-0.4)`）、
换行行距 0（`primaryLineSpacing` 默认 0）；下一句 `round(主字号 × 12/26)` semibold（26 → 12）；
header 固定 11 pt medium，白色 92%；
**未唱实心 #909090、已唱纯白 #FFFFFF**（见下方 2026-11-13 第六轮）；下一句有效白色 39.1%（0.85 × 0.46）；
阴影两层——贴字 black 0.98 / radius 1.1、外层 black 0.70 / radius 5 / y+1；header 0.60/1。

玻璃是 LyricsX Next 的 **Liquid Glass clear**：`NSGlassEffectView.style = 1`、`cornerRadius = 32`、
`appearance = darkAqua`，并用私有 `_adaptiveAppearance = 1` 阻止 AppKit 跟随主题自行变亮。
scrim 固定黑色（歌词始终白字）：顶部 `0.60 × backgroundOpacity`，按 `[1, .66, .28, 0]` 渐变到透明，
渐变位置 `[0, 0.38, 0.76, 1]`；当前用户背景透明度 31% → 顶部约 18.6% 黑
（LyricsX 的默认是 tint transparency 60% → 顶端 24% 黑；fmusic 拉到 40% 即完全一致）。
`backgroundOpacity = 0` 时连玻璃一起隐藏；系统「降低透明度」开启时隐藏玻璃，改用 0.12 灰纯色。

**逐字波浪**：每个字单独栅格化成一层（`syllableRenders`），按该字的 `progress` 做
`0.985 → 1.0` 的 1.5% 生长 + `sin²(πp)` 的轻微上下浮动；`duration > 0.45 s` 的长音再额外
放大 5.5%、上浮 3.5% 行高。锚点是字框底边中点，60 Hz 跟随歌词时钟。没有分字图
（音节数 >64 或无音节）时退回整行遮罩扫描。
LRC 只有整行时间戳；如果直接按字分配，英文会变成每个字母各自鼓一下。因此
`DesktopLyricsRenderer.motionGroups` 用 `NLTokenizer` 把字音节归到单词（中文即分词结果），
同一单词共享一个运动包络，并给词内每个字 0–22% 的相位延迟；效果接近 LyricsX 的
`WordCue` + `characterPhase`。YRC 的音节本身已经是词，不再二次分组。锚点/包络参考
LyricsX `WordHighlight.swift` 的 `LyricEmphasisFrame`。整行的全局缩放已移除；
高亮改为每个亮字层自己的白色 shadow（LyricsX compact overlay：radius = `min(9, 行高×0.24)×0.72`，
26 pt 约 5.4 pt；`shadowOpacity = 0.82 × emphasis × smoother(该字 reveal progress)`），
旧的径向 glowLayer 已删除。
扫光遮罩只羽化 3 pt：`locations = [0, start, end, 1]`、颜色 `[white, white, clear, clear]`；
`start = (pad + filled)/imageWidth`、`end = start + 3/imageWidth`。不要退回整字渐隐，
否则每个字会像“整字变白”。

### 3.4 设置项（`settings.user` JSON）

| key | 含义 |
|---|---|
| `_isDesktopLyricsEnabled` | 总开关（默认 false） |
| `_desktopLyricsFontSize` | 0/1/2 → 24/26/30 pt |
| `_desktopLyricsBackgroundOpacity` | 0–100，0 时连玻璃一起隐藏 |
| `_desktopLyricsAlignment` | 0 左 / 1 中 / 2 右 |
| `_isDesktopLyricsNextLineShown` | 显示下一句 |
| `_isDesktopLyricsAlwaysOnTop` | 窗口 level 3 / 0 |
| `_isDesktopLyricsLocked` | 鼠标穿透 |
| `_isMenuBarLyricsEnabled` | 菜单栏歌词（默认 false） |

用户当前值：开启、26 pt、居中、显示下一句、置顶、未锁定、**背景透明度 31%**。
透明度是用户自己的选择，不要当成 bug；想要更实的卡片就调高不透明度。
面板级状态（不属于 `settings.user`）：`fmusic.desktopLyrics.positionLocked`（控制条锁按钮）、
`fmusic.desktopLyrics.songOffsets`（单曲歌词偏移字典，timer 面板维护）。

### 3.5 已踩过的坑（别再踩）

1. **背景 view 的 layer 会延迟挂载**：AppKit 可能在手加子层之后才把 `NSGlassEffectView` 的 layer 插进来，
   盖住文字。必须给 scrim/border/content 设 `zPosition`（0/1/2/3），不能只依赖 addSublayer 顺序。
2. **appearance 与 style**：`NSGlassEffectView` 在设置 style 时就构建背板。现在固定 clear（1）+
   darkAqua + `_adaptiveAppearance = 1`；不要退回 regular，否则就是一整块毛玻璃。
   白字配黑 scrim，不要再按 effectiveAppearance 翻转极性。
2b. **不要把 scrim 放进 glass.contentView**：实测（原生 AppKit 对照）只要设置 contentView，
   clear 玻璃会额外铺一层浅色材质，透明感和折射全消失。scrim 必须是 glass 上方的兄弟层（zPosition 1）。
2c. **NSWindow KVC**：`isFloatingPanel` 不是合法 KVC key，会抛 NSUnknownKeyException（表现是面板创建
   半途而废、窗口停在 0,0 且不可见）。应该用 `floatingPanel`（setter `setFloatingPanel:`）；
   所有非必要 KVC 一律走 `setValueIfSupported`。
2d. **点击穿透会触发同步刷新**：设置回调里 `updateLyricsOverlays()` 会重入 `setLocked`；
   `setClickThrough` 用 `applyingClickThrough` 守卫，否则控制条会被嵌套调用搬回主面板。
2e. **nonactivating 面板不能成为 key window**：首击会被 AppKit 吞掉。控制条/同步面板的按钮
   统一用 runtime 子类 `FMOverlayButton`，实现 `acceptsFirstMouse:` 返回 YES。
2f. **非激活窗口的玻璃会变灰雾**：只设 clear + darkAqua 还不够；LyricsX Next 的 `OverlayMaterialPanel`
   覆写了 `_hasActiveAppearance` / `_hasActiveAppearanceIgnoringKeyFocus`。实测修正后，把面板拖到
   壁纸上仍能透出 Dock 图标和桌面细节；修正前同一位置是一整块乳白灰。做视觉验证时要在
   **fmusic 非前台**、且背景不是纯白窗口时截图。
3. **KVC 必须守卫**：`NSClassFromString` 拿到的 AppKit 类全部走 runtime，KVC 前用
   `responds(to: NSSelectorFromString("setXxx:"))` 判断；否则 NSUnknownKeyException 直接崩。
4. **frame 用 C 函数指针**：`setFrame:display:`、`initWithContentRect:styleMask:backing:defer:` 用
   `method_getImplementation` + `@convention(c)` 调，KVC 对 struct 参数不稳。
5. **LRC 没有词级时间**：`LyricsTimingMap` 会给每个字平均分配行时长，长音强调可能被“估算时长”误触发；
   YRC（`line.words` 非空）才是精确的。要更严格就只在有 word timings 时启用强调（需把标记透传到 `DesktopLyricsContent`）。
6. **歌词没有翻译字段**：`StructuredLyrics` 只有 line/synced/offset 和 word；想做双语要改解析与 UI，不止浮窗。
7. **悬停控制条已经做了**（2026-11-13 晚）：按钮是 runtime `NSButton`，不是 SwiftUI；改按钮时注意
   `setTarget:`/`setAction:` 都要走 IMP，`imagePosition` 要设 1（imageOnly），图标用 `NSImage`
   `imageWithSystemSymbolName:accessibilityDescription:`，白色靠 `contentTintColor`。
8. 遮罩/快照都依赖 `LyricsTextLayout.rects(for:)`；改字体或换行策略时先确认这两处仍对齐。
9. **LRC 元数据行**：`LRCFileParser` 会跳过残留 `[` 前缀的坏 tag 和 `作词/作曲/编曲…：` 行；
   否则 `[00:00.00-1] 作词 : X` 会被当成第一句歌词显示出来。过滤在
   `fmusicKit/Api/LibrarySyncerDefaults.swift`，主歌词页和桌面浮窗共用。

### 3.6 已验证

- 播放《庐州月》：逐字填充（“月下的你不复”亮 / “当年模样”暗）、下一句正确、换行无残影。
- 2026-11-13 晚按用户提供的 LyricsX 参考图改为浅色玻璃 + 左上角「歌名 · 歌手」，随后按 LyricsX Next
  缩到 620×101，并加悬停控制条。
- 2026-11-13 晚（第二轮，对照 LyricsX Next 源码）：桌面歌词改成 clear Liquid Glass；控制条改为
  timer / expand / lock / cursorarrow / xmark 五键。实机验证：《惊鸿一面》播放中，玻璃能透出后方
  fmusic 窗口内容；控制条首击可点；timer 打开同步面板，延后/提前/重置会更新并持久化单曲偏移；
  点击穿透后主面板 `ignoresMouseEvents=1`、控制条移到独立面板仍可点击，再点 cursor 关闭穿透；
  位置锁图标在 lock.open/lock.fill 间切换；关闭同步面板和收起控制条都正常。
- 2026-11-13 晚（第三轮）：补上 `FMDesktopLyricsPanel` 的激活态覆写后，在 fmusic 非前台、面板位于
  壁纸区域时截图，能清楚看到 Dock 图标透过玻璃；乳白灰雾消失。用户背景透明度仍为 31%。
- 整机 CPU 约 3–7%，RSS ≈ 170 MB（60 Hz 只更新遮罩时）。
- 面板在其它 App 前台时仍显示（level 3），点击不抢焦点。
- 2026-11-13 晚（第四轮，对照 LyricsX Next 实机与 `WordHighlight.swift`）：
  - scrim 从 `0.32 × opacity` 改为 `0.60 × opacity`，渐变位置对齐 `[0, 0.38, 0.76, 1]`；
    用户背景 31% → 顶端 18.6% 黑，和 LyricsX（顶端 24% 黑）接近，不再发白。
  - 未唱字 66%→55%，下一句 78%→45%，头部 11 pt；面板 97 pt 高与 LyricsX 96 pt 基本一致。
  - 每个字独立图层：横向遮罩逐字扫描 + 1.5% 生长/正弦浮动，长音 5.5%/3.5% 行高；
    录制 60 fps 逐帧检查过，能看到亮色从左到右逐字推进。
  - `LRCFileParser` 过滤元数据行后，《一笑倾城》不再把“作词/作曲”当歌词显示。
- 2026-11-13 晚（第五轮，用户指出“上面像波浪、下面一个个突出来”）：
  - 对照 `LyricsX-Next/Sources/LyricsXApp/WordHighlight.swift`：LyricsX 的动画单位是
    `WordCue`；只有 cue >0.45 s 时才按字拆分，字间再用 `characterPhase` 做最多 22% 的延迟。
    fmusic 的 LRC 回退按字分配，才会出现字母逐个鼓包。
  - 用 `NLTokenizer` 把字音节归并为词（`motionGroups`），同词共享包络并相位错开；
    中文按分词结果成组，YRC 不重复分组。整行 2% 缩放已移除。
  - 字号选项改为 24/26/30（中号 = LyricsX 的 26 pt），取消手动负 kern，
    文字阴影从 7/10 收到 3/5，更接近 LyricsX 的紧阴影。面板高度 89 pt（26 pt + 下一句）。
- 2026-11-13 晚（第六轮，用户指出“未唱更黑、已唱更亮有高光”，要求把源码细节一次看完）：
  - 纠正上一轮“取消 kern”的错误：`OverlayLyricsContent.swift:261` 对原文和下一句都加了
    `.tracking(-0.4)`，已恢复；`primaryLineSpacing` 默认 0，换行行距也从 3 pt 改为 0。
  - 字色不是“白 55%”：`LyricTypography.adaptedForGlass(dark:)` 把未唱种子夹到 **0.28 线性亮度**，
    FFFFFF 主色会解析成实心 **#909090**；`HeldNoteRenderer` 对未唱用
    `colorMultiply(wordColors.unsung)`（alpha 1），已唱用 `colorMultiply(wordColors.sung)` = 白。
    参考截图像素实测未唱字心正好 (144,144,144)，已唱 (255,255,255)。
  - 阴影是两层不是一层：`OverlayController.lyricBody` 给整个歌词面先 `.shadow(black 0.98, r1.1)`
    再 `.shadow(black 0.7, r5, y1)`；实现上贴字阴影烘焙进栅格图，外层阴影交给
    `baseLayer/nextLayer` 及当前 surface 的 CALayer shadow（`masksToBounds=false`，不会被图裁掉），
    `shadowOffset.y = -1`（CALayer 坐标向下）。
  - 下一句预览按源码的次级面计算：12 pt semibold × 0.85 透明度 × 未唱 0.46 = 有效 39.1% 白。
  - 羽化从 2.5 pt 调到 LyricsX 的 3 pt 上限；字号/字重/semibold 26 不变。
  - 验证：白底 TextEdit 垫在面板下逐帧截屏 `/tmp/ink-white/*.png`，混合帧里
    “没话讲”（已唱）为纯白、“我们互相在假装”（未唱）为 #909090，黑边+下投影与参考图一致。
- 2026-11-13 晚（第七轮，用户指出“上面流畅、下面是一句一句写出来的”）：
  - 60 fps 逐帧定位到换行瞬间：旧句整行还在原位，新句就以 **26 pt 原尺寸、全不透明**在
    同一位置淡入，两层字形叠在一起（录屏帧 426–436），所以看起来像“每句重新写一遍”。
  - 对照 `OverlayCueTransition.swift` / `OverlayMotionFrame`：LyricsX 会把上一帧已经在屏幕上的
    “下一句”原位接力——新主行从预览的中心和 `nextScale`（12/26）开始，用
    `bezier(0.28, 0, 0.30, 1)`、`min(0.64, 0.8×行时长)` 生长到主行；旧行只上移 2–4 pt、
    0.20 s 内淡出（`OverlayCueDeparture`）。
  - 实现：`update(content:)` 在改层前记录预览行的“距顶距离”和 `12/26` 比例；布局完成后
    `animateArrival` 把当前 surface 的 container 从预览位置/比例动画到 identity（0.62 s，透明度
    0.85→1）；旧句先快照上移 9→3 pt，0.20 s smootherstep 淡出（现已改为双缓冲活图层淡出）。
    非接力换行保持 10 pt 上移 + 0.985→1，改为 0.5 s，透明度 0.7→1。
  - 效果：新句从下方预览位置连续长成主句，旧句只轻微上浮消失；面板-only 10 fps 逐帧
    `/tmp/promo-panel/*.png` 可见完整的“小字在预览位→放大上移→主行”过程。
  - 面板高度变化也改成动画：`resizePanel` 用 60 Hz `Timer` 逐帧改 `NSWindow` frame（顶边固定，
    文本层每帧按新高度重新顶对齐），增长 0.34 s、收缩 0.48 s（LyricsX 的时长）；动画期间
    `windowDidMove` 不写 UserDefaults，结束才保存。实测 88→70 pt 收缩时逐帧高度
    176→162→142→140 px，过程连续。
  - 另一个“白色怎么写上去”的问题：逐字遮罩原来 `locations = [0, stop, 1]`、颜色
    `[white, white, clear]`，渐变从唱到的位置一直铺到整字末尾，等于每个字被整字淡入成白字。
    源码 `clipReveal` 只羽化 3 pt；已改成 `[0, start, end, 1]` + `[white, white, clear, clear]`，
    `end-start = 3 pt / imageWidth`，白色边界变成真正从左向右扫过。
  - 高亮：`HeldNoteRenderer.drawBloom` 在长音 cue（>0.45 s）上用白色 glyph-shadow 做光晕。
    实现不是给“已扫出的亮字”加 shadow，而是每个音节三层：
    `glow`（无 shadow 的白色整字形，独立 `white 0.82` shadow，radius `min(9, 行高×0.24)×0.72`，
    `opacity = emphasis × smoother(reveal)`，位于最底层、不受扫光遮罩裁切）+ `dim`（未唱色）+
    `bright`（白字 + 3 pt 扫光遮罩）。黑色 broad shadow 放在 container 上、画在 glow 后面，
    避免把白晕压灰。这样光晕能围绕整个字出现，即使这个字还没扫成白色——这正是原版长音前
    的“白底灰字”效果。有分字图时整行 `baseLayer` 隐藏，dim/bright/glow 在同一个 container
    里一起缩放、上浮，否则会看到白字从静止的灰字上浮出去的“双影”。`emphasis` 用带 0–22%
    字相位延迟的 `motionProgress`，与源码一致。
  - 注意：高亮只在歌词源提供词级时间且**单个 cue** >0.45 s 时出现。当前 WebDAV 曲库同时有
    `.yrc` 和 `.lrc`，索引器优先 `.yrc`（`WebDAVLibraryIndexer.fetchLyrics` 的候选顺序），
    《风度》《不分手的恋爱》等实际用的就是 YRC；只有 `.lrc` 的歌（如《后会无期》）才没有
    词级 cue、不会亮，这与原版 LyricsX 对纯 LRC 的行为一致。已用《风度》202.07 s 那句
    “来整理遗憾”（“憾” 2.28 s）的逐帧截图确认光晕真实出现。
  - YRC 的 cue 必须单独成组（`LyricsSyllableTiming.isWordTimed`），不能再被 `NLTokenizer`
    二次合并成词；否则一个词里只要总跨度超过 0.45 s，整词的字都会亮，和源码按 cue 判断不符。
  - 验证：60 fps 录屏裁出逐帧条 `/tmp/wipe60-strip.png`（“何必虚情假意的勾勒着未来”），
    白色边界逐字连续右移，未唱部分保持 #909090；面板逐帧条 `/tmp/wipe-check-strip2.png`
    可见接力换行、扫光与长音光晕；`/tmp/glow9/f070.png`、`f080.png` 是《雅俗共赏》
    “还不都是一副臭皮囊”在“囊”（2.27 s cue）上的白底灰字光晕实拍。

### 性能收口（2026-11-13）

- 换行排版：`makeLine` / `makeSyllableRenders` 现在每行只建一份 TextKit 布局，dim/bright/glow
  通过 `LyricsTextLayout.draw(foregroundColor:shadow:)` 换色重绘；分字图从每字 3 次布局降到
  1 次（12 字行约 38 次布局 → 13 次）。颜色和 shadow 都不影响字形排布，布局可安全复用。
- 60 Hz：`applySyllableWave` 先按 `MotionGroupRuntime` 算一次词组进度，再逐字调用 `applyWave`；
  已唱完/未唱的字不再每 tick 重设 `container.transform`，满格遮罩只在状态切换时写一次
  （`lastScale/lastLift/maskIsFull`）。两个歌词入口都关闭时 `didLyricsTimeChange` 直接返回，
  不再每 tick 解码 settings。
- 其它：`estimatedDurations` 改单遍反向扫描（原来逐行向前找下一个时间戳，最坏 O(n²)）；
  `LyricsView` 缓存 `lyricsOffsetMs`，`.lyricsOffsetChanged` 时刷新；`AudioPlayer` 的 notifier
  数组只在真的有弱引用失效时才重建；WebDAV PROPFIND 的 HTTP 日期解析每个响应复用一个
  `DateFormatter`；本地音源每个目录只读一次封面文件。
- 验证：构建通过；`/tmp/optcheck/glow5/f16.png`（“囊”灰字带白晕）、`f18.png`（扫白中）、
  `f20.png`、`f22.png`（全白 + 光晕）是《雅俗共赏》第二遍“还不都是一副臭皮囊”在 147.19–149.23 s
  的实拍，`*-crop2.png` 是放大的末字；`/tmp/optcheck/a.png`、`b.png`、`c.png` 为换行排版复用后的
  普通扫光。说明共享布局没有破坏字色、阴影和 glow。
- 双缓冲换行（2026-11-13 当日完成）：
  - primary 层改成 `PrimarySurface` A/B 两套（`surfaceA`/`surfaceB`），每套自带 container、base、
    sung、syllableMask、syllableContainer、分字 bundle 和 `MotionGroupRuntime`，
    `currentSurfaceIsA` 记录当前显示哪套。
  - 换行时先构建新句，再 `preparePrimarySurface` 切到另一套并 `installPrimary`；旧句用
    `startDeparture(of:)` 直接淡出**活的** layer 层（opacity 1→0、上移 3 pt、0.20 s），
    不再栅格化快照，`DesktopLyricsRenderer.snapshot` 已删除。旧 surface 260 ms 后
    `resetSurface` 归还缓冲池。
  - `DesktopLyricsLineRender` 的 `dimImage`/`brightImage` 改为可选，并去掉 `layout`：
    分字路径（YRC 词级时间）只用每字 dim/bright/glow 图层，整行图仅在没有分字渲染时
    （无时间轴行、>64 字、分字全部失败）才生成。换行主路径从每行 3 次整行栅格化降到 0 次。
  - 验证（30 fps 实拍）：`/tmp/optcheck/dbvideo2/f054.png`（旧句）、`f056`–`f059`（旧句淡出、
    新句进入）、`f061`/`f063`/`f066`（新句灰字 → 扫白），无跳变/残影；`/tmp/optcheck/dbglow/`
    的 `f001.png`、`f020.png`（“自赏”的“赏”灰字带白晕）、`f060.png`（“赏”全白）证明长音光晕
    在双缓冲后仍然工作，放大件 `f001-last2.png`/`f020-last2.png`/`f060-last2.png`。

## 4. WebDAV FLAC seek 修复（`38989ef`）

- 现象：冷缓存下从 WebDAV 开始播放后立即拖进度，顶部红条报错；等一会再拖就正常。
- 根因：seek 后 `AudioFileStreamParseBytes` 从中途字节开始喂，解析器返回 `-108`（memFullErr，不在已映射错误里，
  UI 显示“未知错误”）。离线探针证明：从帧同步点开始永远不会失败，半帧开始必失败。
- 修法（`Vendor/AudioStreaming/`）：
  - `AudioFileStreamProcessor.swift`：新增 `FlacSeekHandling`（notPending/swallow/parse(from:)）、`scannedBytes`；
    丢弃数据直到 CRC-8 校验通过的 FLAC 帧，再从该帧位置重新喂；512 KB 后放宽时间窗到无限。
  - `RemoteAudioSource.swift`：stream generation 计数，seek/close 后丢弃旧代数据，避免竞态把旧字节拼进新解析。
  - 细节和复现记录在 `Vendor/AudioStreaming/PATCHES.md`。
- 验证：冷启动 WebDAV 曲目后立即 seek 到 60%+，不再报错；不要用“清缓存”当修法。

## 5. 包体 / 数据模型（`47c5ce7` 及之前）

- CI 只出 **arm64**，DMG ≈ 10.5 MB，安装后 ≈ 19 MB；不支持 Intel。
- Core Data 只剩 `fmusic v49` / `v50`；**新增字段/实体必须加 v51**，同时改 `CoreDataMigrationVersion`、`.xccurrentversion`；
  v48 及更老的库不能迁移。
- 图片已去重（App 图标/预览图共用一套）；不要再把大图重复塞进 Assets。
- 构建缓存 `BuildTools/.build` 约 600 MB，可随时删；仓库不放二进制。

## 6. 产品状态（已验证，改别处时当回归基线）

- 侧栏 210 pt、行高 38（32 高亮）、13 pt 文案、实心 16 pt 图标；Apple Music 式首页/专辑网格。
- 封面：ImageIO 降采样到最长边 1024，缓存上限 64 MB / 300 张（`LibraryEntityImage`）。
- WebDAV 曲库：启动/回前台增量扫描（15 s 去抖）；本地文件夹需手动同步。
- 大播放器：主窗口内 `.fullScreen` 上滑，两栏，**固定深色**；ESC / 左上 chevron 关闭。
- 独立歌词栏 `LyricsVC` 固定深色；迷你条 `UIGlassEffect(.regular)`。
- 设置：独立设置窗口（Cmd+,），侧栏 210 pt / 38 pt 行高 / 13 pt medium / 16 pt 实心图标；
  顶部固定搜索框（页面名 + 设置项名 + 关键词，结果按页面分组，点结果跳转）；
  顶层 6 项（通用/账户/播放/显示/资料库/支持与关于）；
  外观、语言（重启生效）、歌词偏移、M3U 导入导出、交叉淡入淡出（默认关）。
  搜索索引是 `SettingsTabView.swift` 里的 `SettingsSearchCatalog`，新增设置项要同步补一条。
- 性能约束：歌词仅可见时 60 Hz；视觉分析器 30 fps；Timer 注册到 `.common`；恢复进度每 5 s 一次。

## 7. 已知问题 / 可选后续（不是当前指派任务）

1. 语言切换必须重启 App（预期）。
2. 播放缓存不自动淘汰（`cacheLimit=0` 无限）；别自动清。
3. CarPlay 7 个文件仍编进 target（Catalyst 不触发），删前先问。
4. 桌面歌词：翻译行、精确 word-timing 门控强调，都是“用户点名再做”（控制条和单曲偏移已完成）。
5. 菜单栏歌词最近没回归验证；改动 `LyricsOverlayManager` 时顺手看一眼开关与菜单栏标题。
6. iOS 真机路径未系统验证；当前主要在 macOS Catalyst 开发。

## 8. 协作偏好（重要）

- 中文、结论先行、短；给一个推荐 + 真实代价，不要丢一串选项。
- “帮我改/加/提交”= 直接做；只有签名、sudo、真机等必须用户本人做的步骤才留给他。
- 视觉改动要**渲染真实截图**；先对齐现有 Apple Music token（13 pt / 32–38 pt / 210 pt / 次级灰 / 主题红）。
- 最小改动，不加未要求的功能/开关/抽象。
- 本地提交用英文 commit message；push/tag/发版只在用户明确要求时做；不要 reset/clean/删文件。
- 删除默认 `trash`，永久删除才 `/bin/rm`；`find`→`fd`、`grep`→`rg`、`rm`→`trash`。
- 不打印/不写密码、token、Cookie；不擅自改用户的代理/服务状态。

## 9. 开工前 30 秒

```bash
cd /Users/apple/Desktop/AI/Quder/fmusic
git status --short          # 应为空
git log --oneline -4
pgrep -fl "fmusic.app/Contents/MacOS/fmusic" || echo not-running
/tmp/winlist 2>/dev/null || echo "rebuild winlist from section 2.2"
```

先读第 3 节再动桌面歌词；先读 `Vendor/AudioStreaming/PATCHES.md` 再动流式引擎。
