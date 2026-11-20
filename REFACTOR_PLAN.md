# fmusic B 方案重构交接文档（给接手的 AI）

> 最后更新：2026-11-20
> 适用分支：`refactor/native-appkit-multiplatform`（从 `main` 的 `74a68f6` 拉出）
> 本文自包含：读完就能开工。**先读第 0、1、2 节再动代码。**

---

## 0. 一句话状态与目标

**目标**：把当前「Catalyst 单工程（iOS App 跑在 Mac 上）」重构为 **B 方案**：

```
fmusic.xcworkspace
├─ Packages/FmusicKit        ← 真正的 Swift Package，跨平台共享核心（去 UIKit 耦合）
├─ fmusic-iOS                ← iOS/iPad App target（SwiftUI + UIKit 兜底）
└─ fmusic-macOS              ← macOS App target（SwiftUI + 原生 AppKit 兜底）
```

**`main` 分支是稳定可发版版本，不要动它。** 所有重构只在本分支做。

---

## 1. 环境、数据与硬约束

### 1.1 环境
- 仓库：`/Users/apple/Downloads/ceshi/fmusic`（本地路径可能变，以实际 git 根为准）
- origin：`https://github.com/lemonevo/fmusic.git`（私有仓库 `lemonevo/fmusic`）
- 工具链：Xcode 27.1 / Swift 6.4 / macOS 27 SDK / Apple Silicon（arm64）
- 当前工程 deploy：`IPHONEOS_DEPLOYMENT_TARGET = 26.0`（另有一处 15.0 残留），`SDKROOT = iphoneos`，`SUPPORTS_MACCATALYST = YES`
- **push / tag / 发版必须先得到用户明确同意**；本地提交可以自己做，英文 commit message
- 网络：Git 配了代理 `127.0.0.1:7897`，偶发 SSL 失败；推送失败就用 `git -c http.version=HTTP/1.1 push` 重试（实测有效）

### 1.2 用户数据（绝对不能清）
- 曲库：`~/Library/Application Support/fmusic/fmusic.sqlite`（含 -wal/-shm），当前约 53 首 / 49 专辑 / 35 艺人
- 封面缓存：`~/Library/lol.levo.fmusic/accounts/.../artworks/`（48 个 png）
- 元数据覆盖：`~/Library/Application Support/fmusic/metadata-overrides.json`
- 账号：WebDAV `admin` @ `http://127.0.0.1:5244/dav/移动/音乐/猫曦汐喜欢的音乐`（AList 本地服务）
- **不要清库、不要重装账号、不要删缓存、不要 `git reset --hard` / `git checkout --` / `rm`**（删除用 `trash`）
- 调试 App 单实例运行；重启用 `osascript -e 'tell application "fmusic" to quit'` + `open`，不要 `kill -9`

### 1.3 协作偏好
- 中文、结论先行、短；给一个推荐 + 代价，不丢一串选项
- “帮我改”= 直接做；只有签名/sudo/真机等必须用户做的才留给他
- 视觉改动必须**实机截图**验证，编译通过不算
- 最小改动，不加未要求的功能/开关/抽象
- 不打印/不写密码、token、Cookie（注意上面账号密码不要输出到聊天/文档）

---

## 2. 当前家底（已实测，别再重复统计）

### 2.1 工程形态
- **不是多平台 workspace**：单个 `.xcodeproj`，3 个 target：
  - `fmusic`（application，**Catalyst**：iOS App 跑 Mac）
  - `fmusicKit`（**framework target，不是 SwiftPM**）
  - `fmusicKitTests`（unit test bundle）
- 构建命令（Catalyst Debug）：
  ```bash
  xcodebuild -project fmusic.xcodeproj -scheme fmusic -configuration Debug \
    -destination 'platform=macOS,variant=Mac Catalyst' \
    -derivedDataPath /tmp/fmusic-build \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
  ```
  构建后需 `codesign --force --deep --sign - --identifier lol.levo.fmusic <app>`，否则 Now Playing 身份退化。

### 2.2 代码体量与耦合
| 区域 | Swift 行数 | 说明 |
|---|---|---|
| `fmusic/Screens` | ~28,400 | 传统 **UIKit**：40 个 VC、75 个 UIKit 子类、20 个 xib、2 个 storyboard |
| `fmusic/SwiftUI` | ~6,100 | 设置页等，67 文件 |
| `fmusic/LyricsOverlay` | ~3,900 | 桌面歌词/菜单栏，**已是 AppKit runtime 桥接** |
| `fmusicKit` | ~35,500 | 共享核心（framework target），**33 文件 `import UIKit`** |

- `fmusicKit` 的 UIKit 耦合主要是图片：`UIImage.create`（约 100 处）、`UIUserInterfaceStyle`、`UIImage.heartFill/playlist/...` 等；分散在 `Storage/`、`Api/`、`Player/`。
- 45 个文件带 `#if targetEnvironment(macCatalyst)` 分支——Mac 专属逻辑已有雏形，但都是「UIKit-on-Mac」写法。
- 真正的 AppKit runtime 桥接只有 3 个文件：
  `fmusic/LyricsOverlay/DesktopLyricsWindow.swift`、`MenuBarLyricsController.swift`、`fmusic/MacWindowHelper.swift`
  （通过 `NSClassFromString("NSWindow"/"NSPanel"/"NSVisualEffectView"/"NSGlassEffectView")` + `objc_*` runtime 调 AppKit）
- `Vendor/AudioStreaming` 是本地 SwiftPM（platforms iOS15/macOS13/tvOS16，含 FLAC seek 补丁，见其 `PATCHES.md`，**不要覆盖升级**）。
- 其他 SPM 依赖：VYPlayIndicator、CallbackURLKit、MarqueeLabel、NotificationBanner、ID3TagEditor、Ifrit、DominantColors。

### 2.3 关键架构文件（改动前先看）
| 文件 | 作用 |
|---|---|
| `fmusicKit/fmusicKit.swift` | `FmusicKit` 单例，持有 storage/player/meta/network |
| `fmusicKit/MetaManager.swift` | 每个账号的 backendApi/librarySyncer/下载管理器；**近期修过一个 apiType 兜底 bug**（`resolvedApiType`），重构时别丢 |
| `fmusicKit/Api/BackendProxy.swift` | 按 `selectedApi` 选 local/webdav 实现（`BackenApiType`: notDetected=0/local=4/webdav=5） |
| `fmusic/AppDelegate.swift` | 应用生命周期、`getMeta/resetMeta`、`settingsAnchorFrame` |
| `fmusic/SceneDelegate.swift` | 主窗口场景、窗口尺寸/位置记忆（min 980×540） |
| `fmusic/SettingsSceneDelegate.swift` | 设置独立窗口场景（900×620，居中主窗口；关闭时销毁 scene） |
| `fmusic/AppDelegateMainMenuExtension.swift` | 菜单、`showSettings/showMiniPlayer/openMainWindow`（均已修：激活已有 scene / 前置 app） |
| `fmusicKit/Api/Local/LocalFolderAccess.swift` | 本地文件夹安全书签 |

### 2.4 已修的 bug（重构基线，别回退）
- `AccountInfo.apiType` 不参与 Codable，解码后是 `.notDetected` → `MetaManager.resolvedApiType` 从凭据兜底，避免 WebDAV 账号重同步走 local 索引器（曾导致「重新同步」清空曲库）。
- 设置独立窗口；关闭销毁 scene（隐藏会留空白窗）；重开前置不重复。
- 重新同步的进度页 `present` 到设置窗口，完成后自我 dismiss。
- 主题色通过 `window.tintColor` 传播到已加载视图。
- `openMainWindow` 激活已有 scene 而非新建，且强制激活 app 前置。

---

## 3. 为什么走 B（动机，供决策参考）

1. **性能**：SwiftUI + Catalyst 打开设置时主线程几乎 100% 耗在 `AttributeGraph`/`_makeViewList`/泛型元数据解析（实测 sample）。Apple Music（AppKit）秒开。
2. **原生感**：菜单栏、Now Playing、桌面浮窗、精确窗口控制只有 AppKit 最稳。
3. **多平台**：B 才能干净地「共享核心 + 各平台原生 UI」；Catalyst 是迁移手段，不是终点。
4. 注意：SwiftUI 不是被 AppKit 替代，它架在 AppKit/UIKit 之上；B 不是"全盘重写 UI"，而是"核心共享 + 平台薄 UI 层"。

---

## 4. 分阶段路线（严格按顺序，每阶段可独立验收）

### 阶段 1 — 抽核心为 SwiftPM 并去 UIKit 耦合（**先做这个，最值钱**）
**目标**：`fmusicKit` 从 framework target 变成真正的 Swift Package，能在 macOS 原生（非 Catalyst）和 iOS 都编译。

**具体任务**：
1. 新建 `Packages/FmusicKit/Package.swift`（swift-tools 5.10+，platforms `.iOS(15)`, `.macOS(13)`），把 `fmusicKit/` 源码挪进去（用 `git mv`，保留历史）。
2. 依赖进来：`Vendor/AudioStreaming`（本地 path 包）及需要的远程 SPM 包。
3. 去 UIKit 耦合（33 文件）：
   - 图片相关（`UIImage.create` 等）抽到独立的 **平台适配层**，例如 `FmusicKitPlatform` 的 `typealias PlatformImage` 或 `PlatformColor`，用 `#if canImport(UIKit) / canImport(AppKit)` 双实现；
   - `UIUserInterfaceStyle` → 平台无关的 `AppearanceMode`（内部再映射）；
   - Core Data 实体包装里的 `UIColor/UIImage` 尽量改成存基础数据（hex/Data），展示层再转平台色。
4. 主工程（Catalyst）改为依赖这个 SwiftPM 包，删掉 framework target；确认所有功能不回退。

**验收**：
- `xcodebuild` Catalyst 构建通过；
- 新建阶段 1 的 macOS 命令行目标（非 Catalyst）能 `swift build` 编译 FmusicKit 通过（可先只编核心，不编 UI）；
- 用户数据不动，App 行为不回退（尤其重新同步、歌词、播放）。

**坑**：
- `CoreData` 模型文件（`.xcdatamodeld`）要一起进 SwiftPM 的 resources，注意 `Bundle.module` 与原来 `Bundle.main` 的差异；
- `SettingsDecodeCache`、`decodeFillingMissingKeys`（`Settings.swift`）是性能关键，别改坏；
- `FmusicKit.shared` 单例初始化顺序敏感，先跑通现有构建再加平台适配。

### 阶段 2 — Mac 专属能力 AppKit 原生化
**目标**：把现有的 3 个 runtime 桥接文件，在 macOS 原生 target 里升级为真正的 AppKit 类。

**具体任务**：
1. `DesktopLyricsWindow.swift`：把 `NSClassFromString + objc_*` 换成直接 `import AppKit` 的 `NSPanel` 子类；保留现有视觉参数（620 宽、32 圆角、Liquid Glass、逐字遮罩、双缓冲、五键控制条等**全部视觉逻辑**）。
2. `MenuBarLyricsController.swift`：直接用 `NSStatusBar`。
3. `MacWindowHelper.swift`：直接 `NSApplication.shared.activate(ignoringOtherApps:)`。
4. Now Playing：Catalyst 下靠 `codesign` 骗 bundle id，原生 Mac 改用 MediaRemote/MPNowPlayingInfoCenter 正统接入。

**验收**：原生 macOS target 里桌面歌词浮窗、菜单栏歌词、主题色、打开主页面前置全部可用且实机截图确认。

### 阶段 3 — 建立独立 macOS App target
**目标**：新建 `fmusic-macOS` target（SwiftUI + AppKit 兜底），依赖 FmusicKit 包 + 阶段 2 的 AppKit 组件。

**具体任务**：
1. 新建 target，`SUPPORTS_MACCATALYST = NO`，`SDKROOT = macosx`，bundle id 沿用 `lol.levo.fmusic`（或子域，注意与 Catalyst 版不冲突）。
2. App 生命周期改为 AppKit/SceneKit 原生（`NSApplicationDelegate` + `NSWindow` 或 SwiftUI `App` + `NSHostingView`）。
3. 主 UI 先复用能跨平台的 SwiftUI 设置页 + 必要的 AppKit 容器；UIKit 的 28k 行播放器/列表 UI **暂时不迁**，先在 macOS target 里做一个最小可用主窗口（比如 SwiftUI 版列表/播放器骨架），保证能跑通「设置 + 播放 + 歌词浮窗」。

**验收**：`fmusic-macOS` 能独立构建运行，设置窗口秒开（对比 Catalyst 版），桌面歌词正常，用户数据（同一 sqlite 路径）可读。

### 阶段 4 — iOS/iPad App target
**目标**：`fmusic-iOS`（iOS + iPad 一个 target），SwiftUI + UIKit。

**具体任务**：
1. 新 target 依赖 FmusicKit；`#if os(macOS)` 分支隔离 Mac 专属代码。
2. iPad 自适应（`NavigationSplitView`）；去掉 Mac 专属能力（菜单栏/桌面浮窗）。
3. 后台音频用 `AVAudioSession`，锁屏控制用 `MPNowPlayingInfoCenter`。

**验收**：iPhone/iPad 模拟器/真机构建运行，播放+后台+歌词正常。

### 阶段 5 — 主 UI 逐步统一（可选，长期）
**目标**：把 UIKit 的 28k 行主 UI 逐步迁到 SwiftUI（优先列表/详情/设置），最终两端共享大部分 View。
**原则**：每个阶段都要能发版；不要一次全量重写。

---

## 5. 建议的开工顺序（给接手 AI 的第一步）

1. **确认分支与环境**：`git branch --show-current` 应为 `refactor/native-appkit-multiplatform`；跑通第 2.1 节的 Catalyst 构建命令，确保基线绿。
2. **直接开始阶段 1**：先建 `Packages/FmusicKit/Package.swift` 骨架，把 `fmusicKit/` 里**最底层、无 UIKit 依赖**的文件（如 `Common/`、`Storage/ManagedObjects/`）先搬进去，`swift build` 验证；再逐个处理 UIKit 耦合文件。
3. 每完成一个可编译的里程碑就本地提交（英文 message），**不 push**（除非用户明确要求）。

---

## 6. 参考与验证清单

- 交接文档：`AI_HANDOFF.md`（最新产品状态）、`HANDOFF.md`（历史日志，部分过时）、`DEVELOPER_NOTES.md`（被隐藏的开发功能）。
- 窗口/截图工具：`/tmp/winlist`（CGWindowList 列窗口 bgid）、`screencapture -x -o -l <wid> file`；CGWindow 左上原点，AppKit frame 左下原点，换算 `cgY = screenH - frame.origin.y - frame.height`。
- 屏幕：`1710×1112 pt`，Retina 截图 2x。
- 主窗口 1024×768，设置窗口 900×620 居中（中心重合）。
- 每次视觉改动后：构建 → codesign → `open` → 截图确认 → 再提交。

**一句话给接手 AI：先把 `fmusicKit` 变成干净的跨平台 SwiftPM（阶段 1），这是后面一切的前提；再做 Mac 专属 AppKit 化（阶段 2），然后才有资格谈两个原生 target（阶段 3/4）。不要一上来就重写 28k 行 UI。**
