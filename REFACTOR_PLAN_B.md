# fmusic B 方案重构交接文档（写给接手的 AI）

> 创建时间：2026-11-20
> 分支：`refactor/native-appkit-multiplatform`（从 `main` 的 `74a68f6` 拉出）
> 目标：把当前 **Catalyst 单 target** 架构，重构成 **B 方案 = 共享核心 Swift Package + 各平台原生 target**（iOS/iPad 一个、macOS 原生一个）。

本文自包含：读完即可开工。开工前请先读 `AI_HANDOFF.md`（产品/硬约束）与 `DEVELOPER_NOTES.md`（隐藏功能）。

---

## 0. 一句话状态

`main` 是可发版分支（tag `v0.5.0`）。**本分支是纯重构分支，当前内容与 main 完全一致，尚未开始重构。** 你的任务是在这个分支上分阶段完成 B 方案，**不要动 main**。

---

## 1. 为什么要做 B（背景，别退回 Catalyst）

- 当前是 **Catalyst**：一个 iOS App target，`SUPPORTS_MACCATALYST = YES`，Mac 版 = iPad 版跑在 Mac 上。
- 用户实测痛点：设置窗口打开有可见卡顿、`Cmd+,` 无 Music.app 那种「秒开」感；`codesign` 骗 bundle id 才能让 Now Playing 生效。
- 根因：Catalyst + SwiftUI 首次构建整棵 `NavigationSplitView` 树（`AttributeGraph` + 泛型元数据解析），以及 Mac 系统集成只能靠 AppKit runtime 私有桥接。
- B 方案能一次性解决：Mac 端用**原生 AppKit target**，设置窗口秒开、系统集成原生、不再需要 bundle id 骗签。

**技术栈结论（别搞混）**：AppKit/UIKit 是底层地基（保留态），SwiftUI 是架在其上的声明式层；Catalyst 只是「把 UIKit 搬到 Mac」的搬运工，不是升级。B 方案 = 共享核心 + 原生 UI 层。

---

## 2. 当前家底（我已扫描，直接采信，不必重扫）

| 指标 | 数值 |
|---|---|
| 工程形态 | 3 个 target：`fmusic`(app, Catalyst) / `fmusicKit`(framework) / `fmusicKitTests` |
| `fmusicKit` | **不是 SwiftPM**（无 `Package.swift`），是 Xcode framework target |
| UI 栈 | 传统 UIKit/Storyboard：**40 个 VC、75 个 UIKit 子类、20 xib、2 storyboard** |
| UI 代码量 | `fmusic/Screens` ≈ 28,400 行；`fmusic/SwiftUI` ≈ 6,073 行（67 文件）；`fmusic/LyricsOverlay` ≈ 3,923 行 |
| 核心代码量 | `fmusicKit` ≈ 35,518 行 |
| Catalyst 耦合 | **45 个文件**含 `#if targetEnvironment(macCatalyst)` |
| `fmusicKit` 的 UIKit 耦合 | **33 个文件** `import UIKit`（含 Core Data 实体包装、`SwipeActionSettings`、`UIColor/UIImage` 用法） |
| `fmusicKit` 的 AppKit 依赖 | 0 |
| 真正 AppKit runtime 桥接 | 仅 3 文件：`DesktopLyricsWindow.swift`、`MenuBarLyricsController.swift`、`MacWindowHelper.swift` |
| 底层 SDK 设置 | `SDKROOT = iphoneos`、`SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"`、`SUPPORTS_MACCATALYST = YES`、`IPHONEOS_DEPLOYMENT_TARGET = 26.0` |

**已知坑（重构时必须保留修复）**：`AccountInfo.apiType` 不参与 Codable，解码后恒为 `.notDetected`；`MetaManager` 里已加 `resolvedApiType`，从 `loginCredentials.backendApi` 兜底解析。重构抽核心时**不要把这段兜底弄丢**，否则重新同步又会走本地索引器、清空曲库。

---

## 3. 目标架构（B）

```
fmusic.xcworkspace
├─ Packages/
│   └─ FmusicKit/              ← 共享核心（Swift Package，平台无关）
│        ├─ 模型 / Core Data
│        ├─ 网络(WebDAV/在线歌词) / 播放引擎封装 / 设置模型 / 业务服务
│        └─ 只用 #if canImport(UIKit) 做极少平台隔离
├─ fmusic-iOS/                 ← iOS App target（iPhone + iPad 共用，SwiftUI 主体 + UIKit 兜底）
└─ fmusic-macOS/               ← macOS App target（原生 AppKit + SwiftUI）
     ├─ 菜单栏歌词 / 桌面浮窗 / Now Playing / 设置窗口 = AppKit 原生
     └─ 依赖 FmusicKit
```

**规则**：
1. 逻辑全进 Swift Package，UI 不碰业务细节。
2. 界面优先 SwiftUI 复用；平台差异用 `#if os(macOS)` / `#if canImport(AppKit)`。
3. 系统能力用**协议抽象 + 各平台实现**（如 `NowPlayingService`），核心只依赖协议。
4. iPad 不单独 target（iOS target 勾支持 iPad 即可）。
5. watchOS 是**独立 target + 独立 UI**，不要硬塞进「三端」。
6. 签名/entitlements/Info.plist 各 target 各自配。

---

## 4. 分阶段路线（严格按顺序做，每阶段均可独立交付/回滚）

### 阶段 0 —— 基线固化（已完成，勿重做）
`main` 已推送 `v0.5.0`，重构分支指针 = main。确认 `git status` 干净即可开工。

### 阶段 1 —— 抽核心：framework → Swift Package，去 UIKit 耦合（**最先做，最值钱**）
**做什么**
1. 在 `Packages/FmusicKit/` 建 `Package.swift`，`platforms` 声明 iOS 16+ / macOS 13+，product 为 library。
2. 把 `fmusicKit/` 下全部源码迁进去，删除 pbxproj 里的 `fmusicKit` framework target，改成 SPM 依赖。
3. 处理 33 个 `import UIKit` 文件：
   - `UIColor`/`UIImage` 用 `typealias` 或平台条件：`#if canImport(UIKit) import UIKit #elseif canImport(AppKit) import AppKit`；
   - 提供跨平台的 `PlatformColor`/`PlatformImage` 抽象，逐步替换直接引用；
   - 纯数据模型（如 `SwipeActionSettings`）优先去掉 UIKit 类型依赖。
4. 保持**当前 Catalyst app 仍能编译运行**（这是本阶段的验收底线）。

**验收**
- `xcodebuild ... -destination 'platform=macOS,variant=Mac Catalyst' build` 成功；
- `swift build --package-path Packages/FmusicKit` 能在 macOS 原生（非 Catalyst）下编译通过；
- 曲库数据正常、重新同步仍走 WebDAV（见第 2 节的 apiType 坑）。

### 阶段 2 —— Mac 专属能力 AppKit 原生化
**做什么**
1. 把 3 个 AppKit runtime 桥接文件从「UIKit-on-Mac 的 runtime hack」迁成真正的 AppKit 代码（可直接 `import AppKit`，不用 `NSClassFromString`+IMP）。
2. 设置窗口：在 macOS target 里用 `NSWindowController` + 原生控件重写（或 `NSHostingController` 包 SwiftUI，但用 `NSWindow` 常驻实例，关闭只 `orderOut`、重开 `makeKeyAndOrderFront`，做到 Music.app 式秒开）。
3. Now Playing / MediaRemote：去掉 codesign 骗 bundle id 的需求。
4. 菜单栏 (`NSStatusBar`)、桌面浮窗 (`NSPanel`)、全局快捷键 —— 全部 AppKit 原生。

**验收**
- Mac 端设置 `Cmd+,` 秒开、可反复开关无白屏；
- 桌面歌词、菜单栏歌词、Now Playing 身份正确（bundle id 自然生效）；
- 视觉改动必须真机截图验证（项目硬约束）。

### 阶段 3 —— 主 UI 分层（可选，工作量最大）
**做什么**
1. 逐步把 `fmusic/Screens` 的 UIKit 页面替换为 SwiftUI（优先简单页：设置已做、列表页次之），或直接在 macOS target 里写 AppKit 版本。
2. 最终形成两个独立 app target：`fmusic-iOS`（SwiftUI+UIKit）、`fmusic-macOS`（SwiftUI+AppKit），都依赖 `FmusicKit`。

**验收**
- 两个 target 各自能独立编译、 install、运行；
- iOS 模拟器和 Mac 真机都跑通核心流程（登录/同步/播放/歌词）。

---

## 5. 硬约束（违反会出事，务必遵守）

1. **不要清用户数据**：`~/Library/Application Support/fmusic`（曲库 sqlite）、播放缓存、`~/Library/Preferences/lol.levo.fmusic.plist`、`metadata-overrides.json`、`~/Library/lol.levo.fmusic*/` 下的封面/缓存 —— 一个都别删。
2. **推送/tag/发版必须先经用户明确同意**；本地提交用英文 message。
3. 删除文件默认用 `trash`，不用 `rm`；不要 `git reset --hard` / `git checkout --`。
4. 视觉改动必须**真实运行截图**验证，编译通过不算。
5. 不打印/不写密码、token、Cookie（plist 里有 WebDAV 明文密码）。
6. 构建命令必须带 `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""`；构建后如需 Now Playing 正确身份要 `codesign --force --deep --sign - --identifier lol.levo.fmusic`（阶段 2 后不再需要）。
7. 恢复进度的 symlink、`FileAudioSource` 里 `resolvingSymlinksInPath` 的修复（`Vendor/AudioStreaming/PATCHES.md`）不能丢。

---

## 6. 协作偏好

- 中文、结论先行、短；给一个推荐 + 真实代价，不要丢一串选项。
- 最小改动，不加未要求的功能/开关/抽象。
- "帮我改" = 直接做；只有签名、sudo、真机等必须用户本人做的步骤留给他。
-  prefers `fd` over `find`、`rg` over `grep`、`trash` over `rm`。

---

## 7. 开工前 30 秒

```bash
cd /Users/apple/Downloads/ceshi/fmusic
git status -sb                       # 应为 ## refactor/native-appkit-multiplatform...，clean
git log --oneline -3                 # 顶端应为 74a68f6
pgrep -fl "fmusic.app/Contents/MacOS/fmusic" || echo not-running
```

**第一步就做阶段 1**：建 `Packages/FmusicKit/Package.swift`，开始迁核心。不要先动 UI —— 核心没抽干净之前动 UI 会返工。
