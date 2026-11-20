# fmusic 纯 B 方案（原生多平台）重构交接文档

> 最后更新：2026-11-21
> 适用分支：`refactor/native-appkit-multiplatform`
> 本文自包含：读完就能开工。**先读第 0、1、2 节再动代码。**

---

## 0. 一句话目标（纯 B = 彻底不要 Catalyst）

把当前「Catalyst 单工程（iPad App 跑在 Mac 上）」重构成 **两套完全原生的 App + 一个跨平台共享核心**：

```
fmusic.xcworkspace
├─ Packages/FmusicKit/      ← 真正的 Swift Package，平台无关的业务核心
├─ fmusic-iOS/              ← iOS/iPad App（原生 UIKit/SwiftUI）
└─ fmusic-macOS/            ← macOS App（纯 AppKit 手写界面，不用 SwiftUI）
```

**macOS 端 = 纯 AppKit**：主窗口、设置、列表、播放器全部用 `NSWindow/NSViewController/NSView` 手写，**不使用 SwiftUI、不使用 Catalyst**。这是为了最接近 Apple Music 的性能与原生感。

**`main` 分支是稳定可发版版本，禁止在 main 上做重构。** 所有改动只在 `refactor/native-appkit-multiplatform` 分支。

### 明确的非目标（避免走偏）
- ❌ 不再以 Catalyst 构建成功为验收目标
- ❌ macOS 端不使用 SwiftUI 做主界面
- ❌ 不做「iPad App 勾选 Mac」的偷懒方案
- ❌ 不为了兼容旧设备降低架构目标（见 1.1）

---

## 1. 环境、数据与硬约束

### 1.1 环境
- 仓库：`/Users/apple/Downloads/ceshi/fmusic`（本地路径可能变，以 git 根为准）
- origin：`https://github.com/lemonevo/fmusic.git`（私有 `lemonevo/fmusic`）
- 工具链：Xcode 27.1 / Swift 6.4 / macOS 27 SDK / Apple Silicon（arm64）
- 当前工程形态（重构前基线）：单 `.xcodeproj`，`fmusic`(app, Catalyst) / `fmusicKit`(framework) / `fmusicKitTests`；`SUPPORTS_MACCATALYST=YES`
- **最低系统版本（纯原生）**：
  - macOS App：`.macOS(.v14)` 起步（可用更低，但别低于 v13）
  - iOS/iPad App：`.iOS(.v17)` 起步
  - 不强制兼容 macOS 26 / iOS 15 那档旧设备
- **push / tag / 发版必须得到用户明确同意**；本地提交自己做，英文 commit message
- 网络：git 代理 `127.0.0.1:7897`，偶发 SSL 失败；推送失败用 `git -c http.version=HTTP/1.1 push` 重试

### 1.2 用户数据（绝对不能清）
- 曲库：`~/Library/Application Support/fmusic/fmusic.sqlite`（+ -wal/-shm），约 53 首 / 49 专辑 / 35 艺人
- 封面缓存：`~/Library/lol.levo.fmusic/accounts/.../artworks/`
- 元数据覆盖：`~/Library/Application Support/fmusic/metadata-overrides.json`
- 账号：WebDAV `admin` @ 本地 AList `http://127.0.0.1:5244/dav/移动/音乐/猫曦汐喜欢的音乐`（密码在 plist 里，**不要打印/外传**）
- **禁止**：清库、重装账号、删缓存、`git reset --hard`、`git checkout --`、直接 `rm`（删除用 `trash`）
- 调试 App 单实例；重启用 `osascript -e 'tell application "fmusic" to quit'` + `open`，不要 `kill -9`

### 1.3 协作偏好
- 中文、结论先行、短；给一个推荐 + 代价
- “帮我改”= 直接做；签名/sudo/真机留给用户
- 视觉改动必须实机截图验证
- 最小改动，不加未要求的功能/开关/抽象
- 不打印/不写密码、token、Cookie

---

## 2. 当前家底（已实测，别重复统计）

### 2.1 代码体量与耦合
| 区域 | Swift 行数 | 说明 |
|---|---|---|
| `fmusic/Screens` | ~28,400 | 传统 **UIKit**：40 个 VC、75 个 UIKit 子类、20 个 xib、2 个 storyboard |
| `fmusic/SwiftUI` | ~6,100 | 设置页等，67 文件（纯 B 下 macOS 端要重写成 AppKit） |
| `fmusic/LyricsOverlay` | ~3,900 | 桌面歌词/菜单栏，已是 AppKit runtime 桥接 |
| `fmusicKit` | ~35,500 | 核心，33 文件 `import UIKit` |

- `fmusicKit` UIKit 耦合主要是图片：`UIImage.create`（约 100 处）、`UIUserInterfaceStyle`、各种 `UIImage.xxx` 扩展；分散在 `Storage/`、`Api/`、`Player/`、`Assets/`。
- 45 个文件带 `#if targetEnvironment(macCatalyst)`；这些分支在纯原生下要改成 `#if os(macOS)` / `#if os(iOS)`。
- AppKit runtime 桥接 3 个文件：`DesktopLyricsWindow.swift`、`MenuBarLyricsController.swift`、`MacWindowHelper.swift`。
- 依赖：
  - `Vendor/AudioStreaming`（本地 SwiftPM，含 FLAC seek 补丁，见 `PATCHES.md`，**不要覆盖升级**）
  - 远程 SPM：VYPlayIndicator、CallbackURLKit、MarqueeLabel、NotificationBanner、ID3TagEditor、Ifrit、DominantColors
  - 注意有些是 iOS-only（如 MarqueeLabel/NotificationBanner），macOS 端要找替代或自己写

### 2.2 关键架构文件（改动前先看）
| 文件 | 作用 |
|---|---|
| `fmusicKit/fmusicKit.swift` | `FmusicKit` 单例，持有 storage/player/meta/network |
| `fmusicKit/MetaManager.swift` | 每账号 backendApi/syncer/下载器；含 `resolvedApiType` 兜底（apiType 不持久化，从凭据解析），重构别丢 |
| `fmusicKit/Api/BackendProxy.swift` | `BackenApiType`: notDetected=0/local=4/webdav=5 |
| `fmusic/AppDelegate.swift` | 生命周期、`getMeta/resetMeta`、`settingsAnchorFrame` |
| `fmusic/SceneDelegate.swift` | 主窗口场景、尺寸记忆（min 980×540） |
| `fmusic/SettingsSceneDelegate.swift` | 设置独立窗口（900×620 居中） |
| `fmusicKit/Api/Local/LocalFolderAccess.swift` | 本地文件夹安全书签 |

### 2.3 已修 bug（重构基线，别回退）
- `MetaManager.resolvedApiType`：WebDAV 账号重同步不走 local 索引器（曾清空曲库）。
- 设置独立窗口，关闭销毁 scene（隐藏留空白窗），重开前置不重复。
- 重同步进度页 present 到设置窗口，完成后自我 dismiss。
- 主题色经 `window.tintColor` 传播到已加载视图。
- `openMainWindow` 激活已有 scene 而非新建，强制激活 app 前置。

---

## 3. 阶段路线（纯原生，严格按序，每阶段可验收）

### 阶段 1 — 建立跨平台共享核心 SwiftPM（无 UI 依赖）
**目标**：`Packages/FmusicKit` 能在 macOS 和 iOS **原生**（非 Catalyst）`swift build` 通过，且不含任何 UI 框架强依赖。

**任务**：
1. `git mv fmusicKit/*` → `Packages/FmusicKit/Sources/fmusicKit/`，保留 Core Data 模型、xcassets 作为 resources。
2. `Package.swift`：swift-tools 6.0，`platforms: [.iOS(.v17), .macOS(.v14)]`，Swift 6 语言模式 + 与工程一致的 upcoming features。
3. 依赖：`Vendor/AudioStreaming`（path）、Ifrit、ID3TagEditor；iOS-only 依赖要隔离。
4. **平台抽象层**（`Sources/fmusicKit/Platform/`）：
   - `PlatformImage` / `PlatformColor` / `PlatformFont`
   - `AppearanceMode`（替代 `UIUserInterfaceStyle`）
   - `PlatformBundle`（`Bundle.module` vs `Bundle.main`）
   - `MediaSession`（`AVAudioSession`(iOS) / 原生音频会话(macOS)）
   - `NowPlaying`（`MPNowPlayingInfoCenter` + MediaRemote(macOS)）
5. 去 UIKit 耦合（33 文件）：`UIImage.create` 等图片扩展改为返回平台无关数据，展示层再转平台图片。
6. 修资源引用：`Bundle.main` → `Bundle.module`（Core Data 模型、xcassets）。

**验收**：
```bash
cd Packages/FmusicKit
swift build                       # macOS 原生，绿
swift build -Xswiftc -target -Xswiftc arm64-apple-macosx14.0   # 明确 macOS 目标
```
且 **不依赖 Catalyst**（不传 `-destination 'platform=macOS,variant=Mac Catalyst'`）。

**坑**：
- Core Data `.xcdatamodeld` 进 SwiftPM resources 后要用 `Bundle.module` 加载，`NSManagedObjectModel` 路径别写死。
- `SettingsDecodeCache`、`decodeFillingMissingKeys`（`Settings.swift`）是性能关键，别改坏。
- `FmusicKit.shared` 单例初始化顺序敏感。
- 图片资源符号（`UIImage.userQueueInsert` 等）当前构建已报错，必须在这里彻底解决。

### 阶段 2 — macOS 原生主界面（纯 AppKit，不用 SwiftUI）
**目标**：新建 `fmusic-macOS` target（`SUPPORTS_MACCATALYST=NO`），纯 AppKit 手写主界面。

**任务**（按依赖顺序）：
1. **App 骨架**：`NSApplicationDelegate` + `NSWindow` + `NSWindowController`；菜单栏、窗口尺寸/位置记忆（沿用 980×540 min、设置 900×620 居中逻辑）。
2. **基础控件层**：把 UIKit 的 cell/view 用 AppKit 对应物重写（`NSTableView`/`NSCollectionView`/`NSButton`/`NSSlider` 等）；建立统一的主题 token（13pt/32-38pt 行高/中性灰选中/主题红）。
3. **设置窗口**：用 AppKit 重写全部设置页（通用/账户/播放/音效/歌词/显示/存储与封面/资料库）。**这是验证"纯 AppKit 秒开"的第一个里程碑**。
4. **主 UI**：资料库（歌曲/专辑/艺人/歌单列表）、播放器（大/小播放器、队列、歌词页）、搜索 —— 约 28,000 行 UIKit 要逐个重写成 AppKit。按模块推进，每模块可独立编译。
5. **歌词浮窗**：把 `DesktopLyricsWindow.swift`/`MenuBarLyricsController.swift` 从 runtime 桥接改成真正 AppKit 类（`NSPanel` 子类 / `NSStatusBar`），保留全部视觉参数（620 宽、32 圆角、Liquid Glass、逐字遮罩、双缓冲、五键控制条）。
6. **系统集成**：Now Playing（MediaRemote）、Finder 打开单文件、键盘快捷键、桌面歌词置顶/穿透。

**验收**：`fmusic-macOS` 独立构建运行；设置秒开（对比旧 Catalyst 版）；桌面歌词/菜单栏/主题色/重新同步全部正常；用户数据可读。

**这是纯 B 的重头戏，工期按月算。** 建议先用「设置窗口 + 播放器最小骨架 + 歌词浮窗」跑通垂直切片，再铺开列表页。

### 阶段 3 — iOS/iPad 原生 App target
**目标**：`fmusic-iOS`（iOS + iPad 一个 target），原生 UIKit/SwiftUI，依赖 FmusicKit。

**任务**：
1. 新 target 依赖 FmusicKit；`#if os(iOS)` 隔离。
2. 现有 UIKit 代码（Screens/）大部分可复用到 iOS 端——这是保留它的价值。
3. 后台音频 `AVAudioSession`、锁屏 `MPNowPlayingInfoCenter`；去掉 Mac 专属（菜单栏/桌面浮窗）。
4. iPad 自适应（`UISplitViewController`/`NavigationSplitView`）。

**验收**：iPhone/iPad 模拟器构建运行，播放+后台+歌词正常。

### 阶段 4 — 收尾与统一
**目标**：两端共享尽可能多的业务逻辑（已在 FmusicKit），UI 各自原生，删掉旧 Catalyst target。

**任务**：
- 确认 main 的所有功能在两端具备（对照 `AI_HANDOFF.md` 功能清单）；
- 旧 `fmusic` Catalyst target 删除；
- CI 改为构建两个原生 App；
- 逐步收敛重复代码（主题 token、格式化器等进 FmusicKit）。

---

## 4. 给接手 AI 的开工指令（直接照做）

```text
这是纯 B（原生多平台）重构，不是 Catalyst 改良。

1. 确认分支 refactor/native-appkit-multiplatform，main 不动。
2. 当前主工程可能是红的（另一个 AI 改到一半），但不要以"修复 Catalyst 构建"为目标——
   唯一验收是 Packages/FmusicKit 在 macOS 原生 swift build 通过（阶段 1）。
3. 阶段 1 只做核心包：
   - git mv 源码/资源进 Packages/FmusicKit/Sources/fmusicKit
   - Package.swift (iOS17/macOS14, Swift6)
   - Platform/ 抽象层（Image/Color/Font/AppearanceMode/Bundle/MediaSession/NowPlaying）
   - 去 UIKit 耦合 33 文件，修 Bundle.module 资源
   - 验收：cd Packages/FmusicKit && swift build 绿
4. 阶段 1 绿了才进阶段 2：新建 fmusic-macOS target，纯 AppKit 手写 UI。
   先做「设置窗口 + 播放器最小骨架 + 歌词浮窗」垂直切片。
5. 每个里程碑本地提交（英文 message），不要 push（除非用户明确要求）。
6. 每步保证至少一条构建链绿：Package swift build 或 macOS target xcodebuild。
   不要留下长期不可编译状态。
```

---

## 5. 参考与验证清单
- 产品功能基线：`AI_HANDOFF.md`（最新）、`DEVELOPER_NOTES.md`（隐藏功能）、`REFACTOR_PLAN.md`（旧版混合方案，仅参考）
- 窗口/截图：`/tmp/winlist`（CGWindowList）、`screencapture -x -o -l <wid>`；屏幕 1710×1112pt，Retina 2x
- 视觉参数：主窗口 1024×768，设置 900×620 居中，侧栏 210pt/行 38pt/13pt 文案/主题红
- 每次视觉改动：构建 → 签名 → open → 截图确认 → 提交

**一句话：纯 B = FmusicKit 跨平台核心 + 纯 AppKit 的 macOS App + 原生 iOS App；macOS 端彻底告别 SwiftUI/Catalyst，代价是 28k 行 UI 要用 AppKit 重写，按月算。**
