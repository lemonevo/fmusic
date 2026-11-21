# fmusic AppKit 原生移植 — 剩余优化任务交接文档

> 交接时间：2026-11-21
> 仓库：`/Users/apple/Downloads/ceshi/fmusic`
> 分支：`refactor/native-appkit-multiplatform`（约 100+ 个本地提交，**从未 push**；`main` 分支未动，禁止推送/打 tag/发布，除用户明确要求）
> 构建/运行环境：Xcode 27.1 / Swift 6.4 / macOS 27 SDK，arm64

---

## 0. 项目背景（给接手 AI 的必读上下文）

这是一个 **Catalyst/UIKit 音乐 App（fmusic）的纯 AppKit 原生移植**：

- `fmusic-macOS/` — **当前开发目标**：纯 AppKit 应用（约 76 个 Swift 文件，26k 行）
- `Packages/FmusicKit/` — 跨平台核心（SwiftPM，`fmusicKit` module，含 Core Data、播放器、网络、歌词解析）
- `fmusic/` — **只读参考**：原 Catalyst 源码（388 个文件）。移植时用它作为 1:1 行为/像素依据，**不要修改**
- `fmusic-iOS/` — iOS target 的 Info.plist（iOS 运行时验证尚未做，无 Simulator runtime）
- 原 App `/Applications/fmusic.app`（Catalyst 版）仅用于**对照截图**；与本项目共享 bundle id `lol.levo.fmusic`，截图/自动化时必须按 **pid** 定位窗口，不能按 bundle id

### 用户硬性要求（贯穿全部开发）
1. **不得删除/破坏用户数据**：`~/Library/Application Support/fmusic/fmusic.sqlite`、`~/Library/lol.levo.fmusic`（封面缓存）、metadata-overrides.json
2. 删除文件用 `trash`，不要用 `rm`
3. 视觉改动必须给 **真实截图** 验证（`screencapture`）
4. 用户负责最终功能测试；**不要随意切歌**（验证播放时用一次，结束后暂停）
5. UI 复刻要**先看 `fmusic/` 源码里用的是哪个系统组件**，再找 AppKit 对应系统控件；AppKit 确实没有对应物时才自绘，并明确说明
6. 用户偏好中文、结论先行；提交信息用英文；不推送、不打 tag、不发布

### 关键路径 / 数据
- 共享 Core Data store：`~/Library/Application Support/fmusic/fmusic.sqlite`（与安装的原版 app 共用）
- 偏好设置：`~/Library/Preferences/lol.levo.fmusic.plist`，JSON 存在 `settings.user`（hex data），测试常用键：`_isPlayerLyricsDisplayed`、`_appearanceMode`（0 系统 / 1 浅色 / 2 深色）、`_desktopLyricsFontSize`

---

## 1. 构建 / 安装 / 验证命令

```bash
cd /Users/apple/Downloads/ceshi/fmusic

# 1) 核心包
cd Packages/FmusicKit && swift build && cd ../..

# 2) macOS App（Debug）
xcodebuild -project fmusic.xcodeproj -scheme fmusic-macOS -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/fm-mac-dd \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build

# 3) 安装测试副本（不动 /Applications）
pkill -f "fmusic-AppKit" 2>/dev/null; sleep 2
rm -rf ~/Applications/fmusic-AppKit.app            # 仅测试副本，可重建
cp -R /tmp/fm-mac-dd/Build/Products/Debug/fmusic.app ~/Applications/fmusic-AppKit.app
codesign --force --deep --sign - --identifier lol.levo.fmusic ~/Applications/fmusic-AppKit.app
open ~/Applications/fmusic-AppKit.app
```

### 截图 / 自动化注意事项
- 窗口列表工具：`/tmp/winlist`（pid、window id、owner、frame）；**按 pid 过滤**，因为原版 Catalyst app 共享 bundle id/名称
- 截图：`screencapture -x -o -l <windowID> /tmp/shot.png`；若截图文件内容不变，说明抓到了陈旧窗口/失败，换窗口或全屏截图裁剪
- 菜单自动化：`osascript` + `System Events` + `(first process whose unix id is <pid>)`；大播放页可用 `key code 53`（Esc）验证关闭
- 开发启动参数：`--args --page <sidebar-item-raw-value>`、`--songs`、`--album <name>`、`--artist <name>`、`--playlist <name>`
- X-Callback：`open -a ~/Applications/fmusic-AppKit.app "fmusic://x-callback-url/playRandomSongs"`
- **新增/删除 Swift 文件后必须运行**：`ruby BuildTools/sync-macos-sources.rb`（不要手改 pbxproj 的 Sources）
- 修改 `Packages/FmusicKit/Sources/fmusicKit/Common/L10n.swift` 后检查重复 key（重复会运行时崩溃）

---

## 2. 已完成的本轮优化（2026-11-21，供接手方了解基线）

最近提交（`git log --oneline`）：

- `8f83ac8` 歌曲列表 Return 播放 + 右键菜单
- `1eb282f` 胶囊三段式改 Auto Layout（删除 viewDidLayout 手动 frame）
- `1c28139` 胶囊宽度按 `NSSplitViewItem.isCollapsed` 真实状态
- `f7e86e8` 歌词位图/模糊缓存 + 分栏/上次页面持久化 + 右簇 trailing 约束
- `43ee867` 歌词缓存与布局持久化（含上一条内容）
- `481d453` ⌘1–⌘9 侧栏跳转、secure restorable state、播放条无障碍标签
- `f1bae29` Esc 关闭大播放页
- `c499148` 播放条拖动 seek、⌘F 聚焦搜索、文本输入时 ⌘←/→ 不抢快捷键
- `afeee88` 独立播放大页固定尺寸窗口、共享 CIContext、睡眠定时器统一
- `52acdd1` 删除死代码（LibraryPlaceholderViewController、NowPlayingOverlayWindow）、清理日志、补 L10n
- `0005a75` Timer 泄漏修复（weak block timer + viewDidDisappear invalidate）、搜索防抖、批量下载 `try!`→`try?`、外观切换不重绘透明窗口

构建当前状态：`swift build` 与 `xcodebuild fmusic-macOS` 均通过（仅剩 2 条无关警告）。

---

## 3. 剩余任务（按优先级）

### P1-A. 大播放页改为"主窗口内子视图"（原生化）
**现状**
- 大播放页是独立**无边框子窗口**：`fmusic-macOS/Window/MainViewController.swift` 的 `presentNowPlayingOverlay()` 创建 NSWindow、`addChildWindow`、`minSize/maxSize` 锁定主窗口尺寸、黑色 layer 背景（约 263–336 行）。
- 后果：不随主窗口缩放/移动、不进全屏、无法成为 key window（键盘事件/焦点异常）、traffic lights 被覆盖。
- 另有一个旧的独立窗口路径 `PlayerBarViewController.showMoreMenu → PlayerPageWindowController.presentNowPlaying()`（`fmusic-macOS/Library/NowPlaying/PlayerPageWindowController.swift`），与 overlay 是两套呈现；两条路径都已把页面塞进固定尺寸容器（上一轮修复了窗口被撑大的问题）。

**目标**
- 用窗口内视图（child view controller + 覆盖层）代替子窗口：`ViewController.view` 加到 `window.contentView` 之上，尺寸 = contentView.bounds，跟随 resize/全屏；Esc 关闭（当前通过 `MainViewController.cancelOperation` 已能关）；`onClose` 统一接线。

**参考**
- `fmusic/Screens/Player/PopupPlayerVC.swift`：`modalPresentationStyle = .fullScreen`、`modalTransitionStyle = .coverVertical`（`MiniPlayerView.swift:668-670`）
- 现有 overlay 的 cover-vertical 动画已实现（layer transform/CABasicAnimation），迁移时保留

**验收**
- 打开大播放页 → 主窗口 resize/拖动/全屏时页面跟随且不变形；
- 页面内按钮/滑条/歌词可交互；Esc 关闭；chevron 关闭；
- 两条入口（胶囊点击、显示菜单 ⇧⌘P、播放条 ···）行为一致。

---

### P1-B. 歌词解析移出主线程
**现状**
- `Packages/FmusicKit/Sources/fmusicKit/Api/LibrarySyncerDefaults.swift:73` 的 `parseLyrics(relFilePath:)` 在 `@MainActor extension LibrarySyncer` 中做 `Data(contentsOf:)` + QRC/KRC 解析，阻塞主线程。
- 已尝试改为 `nonisolated`，被 Swift 6 拒绝：`LyricsList` 非 Sendable，无法从 nonisolated 实现返回（编译错误 `NonSendableInAsyncConformanceOrOverride`）。

**方案（二选一）**
1. 让 `LyricsList` / `StructuredLyrics` / `LyricsLine` 满足 `Sendable`（检查其成员，多为值类型，可行），再把 `parseLyrics` 标 `nonisolated`；
2. 或保留 `@MainActor` 签名，把文件读取+解析放进 `Task.detached`，结果通过 `@MainActor` 回调返回（需处理 Sendable 边界，或使用 `@unchecked Sendable` 包装）。

**调用点**（都要确认行为不变）：
- `fmusic-macOS/Library/Lyrics/LyricsPageViewController.swift:453`
- `fmusic-macOS/Library/Lyrics/LyricsSidebarViewController.swift:197`
- `fmusic-macOS/Library/NowPlaying/LyricsPaneView.swift:235`
- `fmusic-macOS/Lyrics/LyricsOverlayController.swift:287`

**验收**：打开带歌词的页面滚动/切歌时主线程无卡顿；歌词仍能正确显示/同步。

---

### P1-C. Core Data 启动失败可恢复化
**现状**
- `Packages/FmusicKit/Sources/fmusicKit/Storage/PersistentStorage.swift`：
  - `:193` `mergedModel(from: [FmusicKitResources.bundle])!`
  - `:235` `fatalError("persistentContainer was not set up properly")`
  - `:256` `loadPersistentStores` 错误回调里 `fatalError`
- 存储损坏/迁移失败/磁盘满 → 启动即崩，无提示。

**目标**：捕获错误，用 `EventLogger` 记录，弹可恢复提示（退出 / 重建库 / 打开数据目录），不 `fatalError`。

**风险**：涉及用户数据库，务必先在临时 store 上验证迁移失败路径；**不得清空用户现有库**。

---

### P2-A. 设置窗口改原生偏好设置样式
**现状**
- `fmusic-macOS/Settings/SettingsWindowController.swift`（固定 900×620 窗口）+ `SettingsViewController.swift`（自绘 210pt 侧栏 NSTableView，macOS 14 应使用 `NSToolbar` + `.preference` 样式）。
- 关闭后 `contentViewController = nil`，下次打开总回到第一个页面（丢状态）。

**参考**：macOS 14 `NSToolbar(identifier:)` + `toolbarStyle = .preference` + `NSToolbarItem`（每个设置页一个 item；`.toolbarSelectableItemIdentifiers`）；窗口用 `NSWindow(contentRect:styleMask:[.titled,.closable,.miniaturizable],...)`，`setFrameAutosaveName`。
**验收**：键盘/VoiceOver 可切换页；重开保留上次页；外观与系统一致。

---

### P2-B. 其它列表页的键盘/右键/多选
**已完成**：歌曲页（`SongsViewController.swift` 内的 `SongsTableView`：Return 播放 + 右键菜单）。
**待做**（同模式抽公共 `NSTableView` 子类后接入）：
- `Library/AlbumDetail/AlbumDetailViewController.swift`
- `Library/Artists/ArtistsViewController.swift`、`ArtistDetailViewController.swift`
- `Library/Playlists/PlaylistDetailViewController.swift`、`PlaylistListViewController.swift`
- `Library/Queue/QueueSectionView.swift`（另需 Delete 移除队列项、拖拽排序，当前无任何 `deleteBackward`/拖拽）
- `Library/Search/SearchViewController.swift`（分组行；返回键激活当前行）
- `Library/Downloads/DownloadsViewController.swift`、`Podcasts/...`、`Radios/...`

**参考原生行为**：Return/Enter 激活、Space 预览、Delete/⌘⌫ 删除（队列/播放列表）、右键 `menu(for:)`、`allowsMultipleSelection = true`（支持 Shift/Cmd 多选）、`NSTableRowView` 无障碍语义（`textField` 属性）。

---

### P2-C. 包体 / 资源瘦身
**现状**
- 主 target 资源里仍编译了 `fmusic/Assets/AppIconPreviews.xcassets`：其中 **36 个 @3x PNG（约 2.92MB）** macOS 用不到；
- **17 个从未引用的备用 `.icon` 包（约 470KB）** 在 macOS Resources phase（上一轮已删重复的 `fmusicAppIcon.icon` 条目，未删这些）；
- `Packages/FmusicKit/Sources/fmusicKit/Resources/` 里 36 个 generated-artwork imageset（只有 3x，`actool` 在 macOS SDK 会丢弃）+ 部分仅 UIKit 代码使用的图片；
- `Packages/FmusicKit/.build` 476MB、`BuildTools/.build` 606MB（未被 git 跟踪，可清理但要重新编译）。

**阻塞**：这些资源与 Catalyst/iOS 参考 target 共享，删除前需确认参考 target 是否还需要（或拆成平台专属资源集）。
**验收**：`du -sh fmusic.app` 明显下降、应用图标/备用图标切换功能仍正常、参考 target 仍可编译。

---

### P2-D. 死代码 / 未使用代码清理
- 音频可视化整条链路是**死代码**（约 385 行）：`Player/AudioVisualizerViews/GenerativeArtView.swift`、`SpectrumBarsView.swift`、`WaveformView.swift`、`Player/AudioVisualizerKit/AmplitudeSpectrumView.swift`；`AudioAnalyzer.isActive` 永远为 false；相关设置 `isPlayerVisualizerDisplayed`/`selectedVisualizerType` 从未被 UI 读取。
- `L10n.swift`（860 行、738 keys）：**339 个 key 未被 AppKit target 引用**（其中 ~293 仅 Catalyst 用、46 完全没用），**32 个被使用但未定义**（本轮补了 11 个）；另有 3 处 **period 不匹配**：`L10n.swift:643/644/645` vs `XCallback/XCallbackManager.swift:421/450/477`。
- 未被调用的 `LibraryStorage` API 约 14 个（`LibraryStorage.swift` 多处）、`Utilities.swift:96/409/413`、`PlatformFont.swift:62/72`、`PlatformImage.swift:151/180`、`CacheFileManager.swift:286/299/319` 等（详见审计报告思路）。
- 建议加一个脚本/测试：扫描 `L10n.tr("...")` 与字典 key 的差集；`BuildTools/sync-macos-sources.rb` 扩展为同时校验资源 phase。
- **阻塞**：删除前需确认 Catalyst/iOS 参考 target 去留（当前项目里仍有它们，且 `fmusicKitTests` 依赖 `fmusic` target）。

---

### P3-A. 原生外观 / 颜色语义化
- `Theme/MacTheme.swift:54-68` 内容/侧栏用硬编码黑白 sRGB，`ThemedRowView.drawSelection`（`:104-114`）用主题色固定 alpha 画选中态，绕过 `NSColor.selectedContentBackgroundColor` / `isEmphasized` / Increase Contrast / Reduce Transparency。
- 多处强制 `.darkAqua`：`NowPlayingViewController.swift:83`、`DesktopLyricsWindow.swift:1764/2025/2312/2552/2659`。
- `NSVisualEffectView.isEmphasized` 从未使用（媒体 app 应在窗口 key 时强调材质）。
- 建议：语义色（`windowBackgroundColor`/`underPageBackgroundColor`/`labelColor`/`separatorColor`）、选中态用系统色、为侧栏/播放页使用系统材质。

### P3-B. 桌面歌词改用系统机制
`fmusic-macOS/Lyrics/DesktopLyricsWindow.swift`：
- 20Hz `Timer` 轮询 `NSEvent.mouseLocation` 判断 hover（`:1626-1635,1645-1653`）→ 用 `NSTrackingArea(.mouseEnteredAndExited, .activeAlways)`；
- 60Hz `Timer` 步进 `setFrame` 做窗口高度动画（`:2378-2413`）→ `NSAnimationContext` / `animator().setFrame`；
- 本地 event monitor 处理外部点击关闭（`:1735-1745`）→ `NSPopover`/`resignKey`；
- 硬编码中文 tooltip/文案（`:1390-1407,1453,1462,1467,1723,1781-1839`）→ 走 `L10n.tr`。

### P3-C. 窗口状态 / 恢复
- 已加 `applicationSupportsSecureRestorableState → true`；仍未做 `restorable`/`restorationClass`、NSWindow `isRestorable`；
- 主窗口缺少离屏 frame 检查（Settings 窗口有，可参考 `SettingsWindowController.swift:47-53`）：显示器变化后可能恢复到屏幕外；
- `LyricsPageWindowController`、`PlayerPageWindowController` 每次重建并 `center()`，未保存 frame（可加 `setFrameAutosaveName`）。

### P3-D. 其它原生细节
- 播放条 seek 已支持拖动，但仍是自绘 NSView：缺 `accessibilityRole = .slider`、value、键盘 seek（←/→）、时间 tooltip。
- 大播放页 `NowPlayingViewController` 的公开属性（如已收藏按钮）无 VoiceOver 语义（部分已有 label）。
- Space 在 `NSApplication.sendEvent` 中拦截播放/暂停（`App/FmusicApplication.swift:23-44`），与菜单项重复；会抢焦点控件的 Space（对话框/按钮）→ 建议只保留菜单项路径（已验证文本框优先），或加 `modalWindow`/`NSControl` 守卫。
- 主窗口 `tabbingMode = .disallowed`，无 Window 菜单标签页命令（可选开启原生标签页）。
- 关于面板缺 `NSHumanReadableCopyright`（Info.plist）。

---

## 4. 已知问题 / 需要复核的点

1. **胶囊视觉复核未完成**：最近一轮把胶囊改成 Auto Layout（左/中/右三段）并用截图验证过一次（右簇已贴右、中间自适应），但最后一次截图工具返回了旧图，需接手方自己打开 app 再确认一遍。
2. 截图工具在部分窗口会返回陈旧内容：务必先删旧文件再截，并检查文件 hash/内容变化；必要时用全屏截图 + 裁剪。
3. `fmusic-macOS/Library/Search/SearchViewController.swift` 已重写为 Catalyst 风格（工具栏搜索框 + 空状态 + 分组结果：艺人/专辑/播放列表/歌曲）；搜索历史为空时显示 clock 空状态。若与 `fmusic/Screens/ViewController/SearchVC.swift` 还有细节差异，按原版继续对齐。
4. 大播放页的歌词列使用 `LyricsPaneView`（清晰文本，24/29pt）；侧栏歌词使用栅格化+逐字填充。原版大播放页用 `LyricTableCell` 栅格化渲染，如需 1:1 再迁移。
5. 原版 app 的 UI 参考：`fmusic/Screens/...`、`fmusic/UtilitiesExtensions.swift`（`UIButton.Configuration.playerRound()` 等），玻璃效果 `UIGlassEffect` ↔ AppKit `NSGlassEffectView`（macOS 26+，旧系统回退 `NSVisualEffectView`）。

---

## 5. 工作约定（务必遵守）

- **不要** push / 打 tag / 发 release；**不要**动 `main` 分支；不要 rebase/重置已有本地提交。
- **不要**删除用户数据目录；删除文件用 `trash`。
- 每次改完必须：`swift build`（包）→ `xcodebuild`（app）→ 安装到 `~/Applications/fmusic-AppKit.app` → 启动 + 截图验证 → 中文汇报（结论先行）+ 英文 commit。
- 视觉需求先读 `fmusic/` 源码确认原版用的**系统组件**；AppKit 无对应物才自绘，并在回复中说明原因。
- 用户会自己测最终效果；验证播放后记得暂停，不要留下随机播放状态。
