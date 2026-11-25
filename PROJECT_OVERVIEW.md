# fmusic 项目说明（AppKit 原生移植）

> 本文是**项目总览**：讲清 fmusic 是什么、当前做到哪一步、还剩什么没做。
> 面向维护者 / 接手者。用户安装说明见 [`README.md`](./README.md)，构建打包命令与
> 逐项任务细节见 [`HANDOFF_REMAINING_TASKS.md`](./HANDOFF_REMAINING_TASKS.md)。

---

## 1. 一句话定位

**fmusic** 是一款 macOS 本地 / WebDAV 音乐播放器。项目当前正在把原来基于
**Mac Catalyst（UIKit）** 的 App，迁移为**纯 AppKit 原生**实现，目标是更贴近
macOS 原生观感、降低资源占用、并摆脱 Catalyst 的历史兼容包袱。

| 项 | 值 |
| --- | --- |
| 版本 | 2.1.2 |
| 开发分支 | `refactor/native-appkit-multiplatform` |
| Bundle ID | `lol.levo.fmusic` |
| 系统要求 | macOS 14.0+（构建用 macOS SDK 27 / Xcode 27.1），Apple Silicon（arm64） |
| 仓库 | https://github.com/lemonevo/fmusic （public） |
| 产物 | `fmusic.app` / `fmusic-appkit-<版本>-arm64.dmg`（ad-hoc 签名） |

---

## 2. 它是干什么的（功能）

面向喜欢本地曲库 / 自建网盘音乐的用户，核心能力：

- **音乐库**：添加本地文件夹或 WebDAV 目录；WebDAV 支持自动增量扫描，只处理新增/变化文件
- **单文件打开**：Finder 中用 fmusic 打开音频即加入当前库并播放；同一文件不重复入库
- **界面**：Apple Music 风格侧栏；正常/编辑两种侧栏模式（编辑模式可拖拽排序）；深色模式、字号、封面显示可调
- **播放**：无缝切歌、交叉淡入淡出（关 / 3 / 5 / 8 秒）、随机、循环、睡眠定时器
- **音效**：均衡器、ReplayGain
- **歌词**：读取同名 `.lrc` / `.yrc` / `.qrc` / `.krc`，也可联网搜索（网易云 / QQ / 酷狗 / LRCLIB）；支持播放器内歌词、桌面浮窗歌词、菜单栏歌词；逐字高亮、手动偏移校准
- **歌单**：新建 / 编辑，支持 `.m3u` 导入导出
- **曲库**：内嵌封面或同目录 `cover`/`folder`/`front` 图；评分、收藏、搜索；缺失专辑信息先用歌词标签补全，再在线匹配
- **系统集成**：`fmusic://` x-callback-url、菜单栏控制、媒体键（MediaRemote）

支持格式：`flac mp3 m4a mp4 aac wav aiff aif ogg oga opus`

---

## 3. 技术架构

```
fmusic-macOS/        纯 AppKit 原生实现（当前开发目标，80 个 Swift 文件 / ~2.7 万行）
  ├─ App/            应用入口、AppDelegate、启动流程
  ├─ Window/         主窗口、标题栏/工具栏、播放胶囊容器
  ├─ Sidebar/        侧栏（普通/编辑模式、拖拽排序、统一单元格）
  ├─ Library/        首页、歌曲、艺人、专辑、播放列表、搜索、下载、队列、Now Playing…
  ├─ Player/         播放条、更多菜单面板、实体动作、播放时钟
  ├─ Lyrics/         桌面歌词浮窗、菜单栏歌词、歌词时间轴核心
  ├─ Settings/       设置窗口与各设置页
  ├─ Theme/          主题色、玻璃材质样式（GlassStyleManager）
  └─ Login/ M3U/ XCallback/ …
Packages/FmusicKit/  跨平台核心（SwiftPM `fmusicKit` 模块，171 个文件）
  ├─ Storage/        Core Data（PersistentStorage）、缓存文件、设置、日志
  ├─ Player/         播放引擎（MusicPlayable）、均衡器、ReplayGain
  ├─ Api/            同步、歌词解析/匹配、事件日志、后端代理
  ├─ Download/       下载与缓存淘汰
  └─ Common/ Resources/ Platform/ …
fmusic/              原 Mac Catalyst 源码（只读参考，198 个文件，用于 1:1 对照）
fmusic-iOS/          iOS target Info.plist（运行时未验证）
```

设计要点：
- **核心与 UI 分离**：Core Data、播放、网络、歌词解析都在 `FmusicKit`，AppKit 与
  Catalyst 两套 UI 共用同一份核心
- **UI 复刻原则**：先看 `fmusic/` 里用的是哪个系统组件，再找 AppKit 对应控件；
  AppKit 没有对应物才自绘（如播放胶囊、更多菜单的玻璃面板）
- **Swift 6 并发**：`@MainActor` UI、后台 Core Data 上下文 `performAndGet`、主线程回映射 `NSManagedObjectID`

---

## 4. 当前进度：已经完成到什么程度

> 结论：**AppKit 版主体功能已可日常使用，能构建出可安装的 DMG**。
> 核心界面、播放、歌词、歌单、搜索、设置均已原生重写并跑通；性能与结构收敛完成 P0/P1；
> 剩余基本是「原生细节打磨」「边角页面键盘/右键」「资源瘦身」等非阻塞项。

### 4.1 已完成

**界面与导航**
- 全部侧栏页面 AppKit 原生重写：首页 / 歌曲 / 艺人 / 专辑 / 风格 / 最新专辑 / 最近播放 /
  歌词搜索 / 收藏（歌曲·专辑·艺人）/ 播放列表 / 目录 / 下载
- 侧栏普通/编辑模式统一数据源与单元格尺寸；编辑模式保留勾选圈与拖拽手柄
- 标题栏/工具栏原生：折叠态开关、标题、搜索框位置修正；点击「编辑」不再触发窗口缩放
- 大播放页从「独立子窗口」改为**窗口内子视图**：随窗口缩放/移动/全屏，Esc 关闭

**播放与控制胶囊**
- 胶囊三段式 Auto Layout；可见宽度按分栏折叠真实状态；8pt 进度条
- 循环/随机激活圆形高亮、图标着色、玻璃阴影统一走 `GlassStyleManager`
- 「更多」菜单：自绘 224pt 窄高玻璃面板，分组对齐 Catalyst，Add to Playlist / Download 状态正确

**歌词**
- 侧栏歌词与 Now Playing 歌词共享时间轴 / 当前行 / 换行核心（`LyricsPresentation`）
- 歌词位图/模糊缓存（32MB 上限）；桌面歌词浮窗、菜单栏歌词保留可用

**设置**
- 设置侧栏实时搜索（按标题+描述过滤）、圆形色板选中态、主题色变更即时传播
- 存储设置：缓存统计（音频/封面/内嵌封面/歌词）、自动清理开关与上限

**性能与结构（P0 / P1）**
- P0：歌词搜索全量取歌/路径解析/sidecar 扫描移到后台；歌曲/艺人/专辑/首页/播放列表/
  收藏/已下载统一「后台取对象 ID → 主线程映射」；启动迁移与 manager 启动延后到首屏后 250ms；
  日志保留 2000 条、支持页仅取最近 300 条
- P1：`PlayerEntityActions` 统一胶囊与详情页实体菜单动作；`PlaybackClock` 统一 0.5s 节拍；
  `LyricsPresentation` 统一歌词核心；更多菜单阴影读取 `GlassStyleManager`

**清理与工程**
- 彻底移除 Catalyst 旧设置/登录迁移层，启动时一次性清理旧扁平 UserDefaults 键，**AppKit-only**
- 移除 Mini Player、独立歌词页、Radios/Podcasts、音频可视化死代码
- 移除设计：文件夹浏览页与队列页布局未改动（按用户要求保持）
- CI：`.github/workflows/build-dmg-appkit.yml` 推送分支即构建并产出 `fmusic-appkit-dmg`（DMG + sha256）

### 4.2 构建/运行状态
- `swift build`（核心包）与 `xcodebuild -scheme fmusic-macOS`（Debug/Release）均通过
- GitHub Actions 已成功产出 arm64 DMG，挂载/签名（`lol.levo.fmusic`, ad-hoc）校验通过

---

## 5. 还没完成的部分（按优先级）

> 均**不阻塞**日常使用，属于「原生体验打磨 / 边角覆盖 / 体积与可维护性」。

### P1（体验 / 稳定性）
- **歌词解析移出主线程**：`FmusicKit/Api/LibrarySyncerDefaults.swift` 的 `parseLyrics`
  仍在 `@MainActor` 扩展里做 `Data(contentsOf:)` + QRC/KRC 解析，会阻塞主线程。
  方案：让 `LyricsList` 等满足 `Sendable` 后改 `nonisolated`，或放进 `Task.detached` + 主线程回调。
- **Core Data 启动失败可恢复化**：`PersistentStorage.swift` 仍有 `fatalError`
  （store 未就绪 / loadPersistentStores 失败 / `mergedModel(...)!`）。应变可恢复提示
  （退出 / 重建库 / 打开数据目录），并先用临时 store 验证迁移失败路径，**不得清空用户库**。

### P2（覆盖度 / 体积 / 可维护性）
- **其它列表页的键盘/右键/多选**：目前只有「歌曲」页做了 Return 播放 + 右键菜单。
  待接入：专辑详情、艺人列表/详情、播放列表列表/详情、队列（另需 Delete 移除与拖拽排序）、
  搜索页、下载页等。建议抽公共 `NSTableView` 子类统一接入。
- **设置窗口改原生偏好设置样式**：现为自绘 210pt 侧栏；macOS 14 应使用
  `NSToolbar` + `toolbarStyle = .preference` 每页一个 item；且关闭后重建会丢上次页
  （已有 frame autosave 与离屏检查，但页面状态会重置）。
- **包体 / 资源瘦身**：主 target 仍编译了 macOS 用不到的 `AppIconPreviews.xcassets`
  （约 2.9MB @3x）与多个未引用 `.icon` 包；`FmusicKit` 资源里也有仅 iOS/UIKit 用的图。
  需先确认 Catalyst/iOS 参考 target 去留再拆平台专属资源集。
- **L10n 清理**：约 339 个 key 未被 AppKit target 引用、少量使用但未定义；建议加脚本
  扫描 `L10n.tr("...")` 与字典 key 差集（可视化死代码已删除，此项仍需处理）。

### P3（原生细节打磨）
- **颜色语义化**：`MacTheme` 内容/侧栏硬编码黑白 sRGB、选中态固定 alpha 绘制，绕过
  `NSColor.selectedContentBackgroundColor` / Increase Contrast / Reduce Transparency；
  `NowPlayingViewController` 与 `DesktopLyricsWindow` 多处强制 `.darkAqua`。
- **桌面歌词改系统机制**：用 `NSTrackingArea` 替代 20Hz 鼠标位置轮询、`NSAnimationContext`
  替代 60Hz `setFrame` 步进、`NSPopover`/`resignKey` 替代本地事件监听；硬编码中文文案走 `L10n`。
- **窗口状态 / 恢复**：主窗口缺离屏 frame 检查；`LyricsPageWindowController`、
  `PlayerPageWindowController` 每次重建并 `center()`，未保存 frame。
- **其它**：播放条 seek 滑杆缺 `accessibilityRole = .slider` 与键盘 seek；
  Space 全局拦截播放/暂停与菜单项重复（应加控件/模态守卫）；关于面板缺
  `NSHumanReadableCopyright`。

### 5.1 尚未完整回归验证
- **WebDAV 同步链路**、**缓存自动清理的实际删除行为**、**桌面歌词长时运行**尚未完整回归
- 胶囊视觉虽已用截图核对过一次，接手后建议再打开确认（截图工具有时返回陈旧帧）

---

## 6. 已知风险与约定（维护必读）

- **共享数据，勿破坏**：`~/Library/Application Support/fmusic/fmusic.sqlite`（含 WAL/SHM）、
  `~/Library/lol.levo.fmusic`（封面缓存）、`metadata-overrides.json`
- **同 bundle id 双实例**：Catalyst 参考版 `/Applications/fmusic.app` 与 AppKit 测试版
  共享 `lol.levo.fmusic`，自动化/截图必须按 **PID** 定位窗口
- **删除用 `trash`**，不用 `rm`（仅测试副本 `/tmp`、`~/Applications/fmusic-AppKit.app` 例外）
- 新增/删除 Swift 文件后需运行 `ruby BuildTools/sync-macos-sources.rb` 同步 pbxproj
- 视觉改动需真实截图验证；改完 `swift build` → `xcodebuild` → 装测试副本 → 启动验证

---

## 7. 目录速查与相关文档

| 文档 | 内容 |
| --- | --- |
| [`README.md`](./README.md) | 用户视角：功能特性、安装、系统要求 |
| [`APPKIT_BUILD_GUIDE.md`](./APPKIT_BUILD_GUIDE.md) | 如何本地/CI 构建、打包 DMG、安装校验 |
| [`HANDOFF_REMAINING_TASKS.md`](./HANDOFF_REMAINING_TASKS.md) | 剩余任务逐条细节、验收标准、构建命令、自动化注意事项 |
| [`AI_HANDOFF.md`](./AI_HANDOFF.md) | 给接手 AI 的项目综述与协作上下文 |
| [`DEVELOPER_NOTES.md`](./DEVELOPER_NOTES.md) | 不进设置界面的开发者功能（事件日志、X-Callback 等） |
