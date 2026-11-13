# fmusic 本地/WebDAV Fork — AI 接续说明

> 最后更新：2026-11-13 16:54（Mac Catalyst / macOS 27 / Xcode 27.1）
> 写给接手的 AI：本文档自包含，读完就能开工。仓库里的 `HANDOFF.md` 是更早的逐日日志，
> 部分内容已过时（例如“大面积未提交”“最后提交 bdee704”），冲突时以本文档为准。

## 0. 一句话状态

桌面歌词已按 LyricsX 的三层遮罩 + 玻璃面板原理重写，并在真机验证通过；
工作树干净；本地领先 `origin/main` 4 个提交（最后一个是本文档）。
用户明确要求“先本地改完几个 bug 再推 GitHub”——**没有明确同意不要 push / tag / 发版**。

## 1. 项目与环境

- 仓库：`/Users/apple/Desktop/AI/Quder/fmusic`
- 分支：`feature/webdav-local`；`origin` = `lemonevo/fmusic`（私有），`upstream` 只作参考，不要推。
- App：版本 2.1.2 (1)，Bundle ID `lol.levo.fmusic`，Deployment Target iOS 26（Catalyst），需 Xcode 27 / macOS 27 SDK。
- 只保留 **本地文件夹 + WebDAV** 两种音源；Subsonic/Ampache 已删；没有 Last.fm/scrobble。
- 用户数据：WebDAV 账号、约 40 艺人 / 38 专辑 / 53 首歌、播放缓存约 1.8 GB。
  **不要清 `~/Library/Application Support/fmusic`、不要清播放缓存、不要重装账号。**
- 调试 App 可能正在后台播放（用户在用）；重启用
  `osascript -e 'tell application "fmusic" to quit'`，等 2 秒再 `open <app>`，不要 `kill -9`。

本地未推送提交（`git log --oneline origin/main..HEAD`）：

| 提交 | 内容 |
|---|---|
| `47c5ce7` | 去重图标素材，缩小包体（DMG ≈ 10.5 MB） |
| `38989ef` | WebDAV FLAC 流式 seek 从帧边界重新解析（修 -108） |
| `b1975cc` | 桌面歌词按 LyricsX 原理重写（玻璃 + 逐字遮罩 + 行进动效） |
| 本文档提交 | 交接文档 |

## 2. 构建、运行、验证

```bash
cd /Users/apple/Desktop/AI/Quder/fmusic
xcodebuild -project fmusic.xcodeproj -scheme fmusic -configuration Debug \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath /tmp/fmusic-build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build

open /tmp/fmusic-build/Build/Products/Debug-maccatalyst/fmusic.app
```

- 必须带 `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`，否则没有 provisioning profile 会直接失败。
- 当前调试产物固定在 `/tmp/fmusic-build/...`；如果换目录，`open` 时用**完整路径**，防止拉起 DerivedData 里的旧包。
- 没有 CI 门禁：`xcodebuild` 成功不代表界面正确，视觉改动必须打开 App 看真实渲染。

### 2.1 窗口与截图（看清浮窗最可靠的方式）

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

### 2.2 CUA（电脑控制）

- `node_repl` + `@qoder-space/computer-use`，`getApp()` 传 **App 全路径**。
- 播放中 AX 元素 ID 每个 tick 都变：**取树和点击要在同一次调用里完成**。
- 启动/切换歌曲优先点主窗口的播放按钮；点击会让 fmusic 抢前台，用户正在浏览时注意别反复操作。
- 设置窗口（`Cmd+,`）有时不在 AX 树里：不要硬点，直接改 plist（见 2.3）。

### 2.3 直接改设置（App 必须先退出）

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
NSPanel（borderless + nonactivating，styleMask = 1<<7）
└─ NSView（layer-backed，内容视图）
   ├─ NSGlassEffectView（z=0；clear + darkAqua；缺失时回退 NSVisualEffectView HUD）
   ├─ CAGradientLayer scrim（z=1；上深下透，替代整块黑卡）
   ├─ CALayer 细描边（z=2）
   └─ CALayer content（z=3）
      ├─ nextLayer            下一句（缩小的预栅格化图）
      ├─ previousLayer        离场行快照（淡出 + 上浮）
      └─ primaryContainer     当前行
         ├─ glowLayer         长音强调的径向白光
         ├─ baseLayer         未唱（dim）图；无音节时放亮图
         └─ sungLayer         亮图 + LyricsSyllableMaskLayer 遮罩
```

- **glyph 层只做一次栅格化**：每行生成 dim/bright 两张 `CGImage`；播放时钟只改遮罩子层宽度，不重排文字。
  60 Hz 更新来自 `BackendAudioPlayer` 的歌词 Timer（1/60 s）→ `didLyricsTimeChange` → `LyricsOverlayManager.render`。
- 遮罩复用播放器歌词页的 `LyricsSyllableMaskLayer`（渐变羽化 2.5 pt）；TextKit 的 rect 是**左上原点**，
  进 CALayer 前统一 `y = height - rect.maxY` 翻转。
- **长音强调**：`DesktopLyricsEmphasis.value(progress:duration:)`，`duration > 0.45 s` 时按 LyricsX 包络
  （`smooth((d-0.45)/1.15) * smoother(p/0.42) * (1 - smoother((p-0.70)/0.30))`）做最多 2% 放大、1.2 pt 上浮和光晕。
- **行进动效**：切行时旧行快照淡出 + 上浮；新行从下方 10–16 pt 缩放淡入；新行恰好是上一句“下一句”时用更大的位移（promotion）。
- **自动高度**：宽固定 760；高度 = 上/下 12 + 当前行 + (4 + 下一句)。改高度时**顶边固定**（`origin.y += oldH - newH`）。
- 面板位置存 `UserDefaults` 的 `fmusic.desktopLyrics.frame`（左下原点数组），恢复时用存档高度，避免每次启动高度跳变导致位置漂移。
- 面板是 `NSPanel` + nonactivating：点击不会激活 fmusic；`movableByWindowBackground` 可拖动；
  「锁定」= `ignoresMouseEvents`；「置顶」= level 3 / level 0。

### 3.3 关键常量（要调视觉先看这里）

`DesktopLyricsRenderer`：宽 760、水平内边距 30、上下 12、行距 4、圆角 20；
主字 bold（24/30/36，用户选 30）、下一句 `max(13, 0.5×主字号)` medium、kern −0.4；
未唱白 46%、已唱 98%、下一句 62%；主文字阴影 black 0.62/8（dim）与 0.52/6（bright）。

### 3.4 设置项（`settings.user` JSON）

| key | 含义 |
|---|---|
| `_isDesktopLyricsEnabled` | 总开关（默认 false） |
| `_desktopLyricsFontSize` | 0/1/2 → 24/30/36 pt |
| `_desktopLyricsBackgroundOpacity` | 0–100，0 时连玻璃一起隐藏 |
| `_desktopLyricsAlignment` | 0 左 / 1 中 / 2 右 |
| `_isDesktopLyricsNextLineShown` | 显示下一句 |
| `_isDesktopLyricsAlwaysOnTop` | 窗口 level 3 / 0 |
| `_isDesktopLyricsLocked` | 鼠标穿透 |
| `_isMenuBarLyricsEnabled` | 菜单栏歌词（默认 false） |

用户当前值：开启、30 pt、居中、显示下一句、置顶、未锁定、**背景透明度 26%**。
26% 看起来偏亮是用户自己的选择，不要当成 bug；想更接近 Apple Music 深色玻璃就调高不透明度。

### 3.5 已踩过的坑（别再踩）

1. **背景 view 的 layer 会延迟挂载**：AppKit 可能在手加子层之后才把 `NSGlassEffectView` 的 layer 插进来，
   盖住文字。必须给 scrim/border/content 设 `zPosition`（0/1/2/3），不能只依赖 addSublayer 顺序。
2. **先 appearance 后 style**：`NSGlassEffectView` 在设置 style 时就构建背板；要先设 `appearance=darkAqua`
   （窗口也设一次），再设 `style`（0 regular / 1 clear）和 `cornerRadius`。
3. **KVC 必须守卫**：`NSClassFromString` 拿到的 AppKit 类全部走 runtime，KVC 前用
   `responds(to: NSSelectorFromString("setXxx:"))` 判断；否则 NSUnknownKeyException 直接崩。
4. **frame 用 C 函数指针**：`setFrame:display:`、`initWithContentRect:styleMask:backing:defer:` 用
   `method_getImplementation` + `@convention(c)` 调，KVC 对 struct 参数不稳。
5. **LRC 没有词级时间**：`LyricsTimingMap` 会给每个字平均分配行时长，长音强调可能被“估算时长”误触发；
   YRC（`line.words` 非空）才是精确的。要更严格就只在有 word timings 时启用强调（需把标记透传到 `DesktopLyricsContent`）。
6. **歌词没有翻译字段**：`StructuredLyrics` 只有 line/synced/offset 和 word；想做双语要改解析与 UI，不止浮窗。
7. **没有 hover 控制条**：LyricsX 的悬停按钮条是刻意没做；用户要再加。
8. 遮罩/快照都依赖 `LyricsTextLayout.rects(for:)`；改字体或换行策略时先确认这两处仍对齐。

### 3.6 已验证

- 播放《庐州月》：逐字填充（“月下的你不复”亮 / “当年模样”暗）、下一句正确、换行无残影。
- 整机 CPU 约 3–7%，RSS ≈ 170 MB（60 Hz 只更新遮罩时）。
- 面板在其它 App 前台时仍显示（level 3），点击不抢焦点。

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
- 设置：窗口内整页覆盖，顶层 6 项（通用/账户/播放/显示/资料库/支持与关于）；
  外观、语言（重启生效）、歌词偏移、M3U 导入导出、交叉淡入淡出（默认关）。
- 性能约束：歌词仅可见时 60 Hz；视觉分析器 30 fps；Timer 注册到 `.common`；恢复进度每 5 s 一次。

## 7. 已知问题 / 可选后续（不是当前指派任务）

1. 语言切换必须重启 App（预期）。
2. 播放缓存不自动淘汰（`cacheLimit=0` 无限）；别自动清。
3. CarPlay 7 个文件仍编进 target（Catalyst 不触发），删前先问。
4. 桌面歌词：hover 控制条、翻译行、精确 word-timing 门控强调，都是“用户点名再做”。
5. 菜单栏歌词最近没回归验证；改动 `LyricsOverlayManager` 时顺手看一眼开关与菜单栏标题。
6. iOS 真机路径未系统验证；当前主要在 macOS Catalyst 开发。

## 8. 协作偏好（重要）

- 中文、结论先行、短；给一个推荐 + 真实代价，不要丢一串选项。
- “帮我改/加/提交”= 直接做；只有签名、sudo、真机等必须用户本人做的步骤才留给他。
- 视觉改动要**渲染真实截图**；先对齐现有 Apple Music token（13 pt / 32–38 pt / 210 pt / 次级灰 / 主题红）。
- 最小改动，不加未要求的功能/开关/抽象。
- 本地提交用英文 commit message；**不要 push**；不要 reset/clean/删文件。
- 删除默认 `trash`，永久删除才 `/bin/rm`；`find`→`fd`、`grep`→`rg`、`rm`→`trash`。
- 不打印/不写密码、token、Cookie；不擅自改用户的代理/服务状态。

## 9. 开工前 30 秒

```bash
cd /Users/apple/Desktop/AI/Quder/fmusic
git status --short          # 应为空
git log --oneline -4
pgrep -fl "fmusic.app/Contents/MacOS/fmusic" || echo not-running
/tmp/winlist 2>/dev/null || echo "rebuild winlist from section 2.1"
```

先读第 3 节再动桌面歌词；先读 `Vendor/AudioStreaming/PATCHES.md` 再动流式引擎。
