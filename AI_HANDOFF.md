# Amperfy 本地/WebDAV Fork — AI 接续说明

> 写给接手的 AI：这份文档是当前状态的最小充分上下文，直接读它就能接着干。
> 更长的逐日改动日志在仓库根目录 `HANDOFF.md`（约 48 KB），遇到具体历史问题再去搜。

## 1. 这是什么

Amperfy 的一个 macOS Catalyst fork，只保留**本地文件夹 + WebDAV**两种音源（Subsonic / Ampache 后端已删）。
UI 目标是对齐 Apple Music：210 pt 侧栏、专辑网格、两栏大播放器、毛玻璃迷你条。
App 版本 2.1.2 (1)，Bundle ID `de.familie-zimba.amperfy-music`，Deployment Target iOS 26（Catalyst），需 Xcode 27 / macOS 27 SDK。

- 仓库：`/Users/apple/Desktop/AI/Quder/amperfy`
- 分支：`feature/webdav-local`（**只在本地提交，不要 push，除非用户明确要求**）
- 最近提交：
  - `24ecdc4` Settings: shorten sidebar, nest detail pages, add language switch
  - `2725621` Fork: local/WebDAV library with Apple Music-style UI and dark mode
  - `dbba5a5` Snapshot: local/WebDAV fork before refactor
- 构建产物：`~/Library/Developer/Xcode/DerivedData/Amperfy-eyetrzidtspoevgufmttlsihklja/Build/Products/Debug-maccatalyst/Amperfy.app`
  （DerivedData 哈希可能变，用 `xcodebuild -showBuildSettings` 或 `mdfind` 重新定位；启动时用**带哈希的完整路径**，否则可能拉起旧包）

## 2. 构建与运行

```bash
cd /Users/apple/Desktop/AI/Quder/amperfy
xcodebuild -project Amperfy.xcodeproj -scheme Amperfy -configuration Debug \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build

open -a "/Users/apple/Library/Developer/Xcode/DerivedData/Amperfy-eyetrzidtspoevgufmttlsihklja/Build/Products/Debug-maccatalyst/Amperfy.app"
```

- 必须带 `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`，否则没有 provisioning profile 会失败。
- 没有 CI 门禁；改完至少 `xcodebuild` 成功 + 真实打开 App 看目标界面。
- 测试 target `AmperfyKitTests` 存在，但当前工作流以构建 + 手工 UI 验证为主。

## 3. 代码地图

| 路径 | 作用 |
|---|---|
| `Amperfy/SceneDelegate.swift` | 主窗口、根 VC、外观/文字大小应用、设置 modal 防悬挂 |
| `Amperfy/MiniPlayerSceneDelegate.swift` | 迷你播放器独立 Scene（继承 App 内外观） |
| `Amperfy/AppDelegate.swift` | 全局单例入口、外观/主题/文字大小、语言、账户增删、顶部 VC |
| `Amperfy/Screens/Player/` | 大播放器 `PopupPlayerVC`、控制条、迷你条、歌词、AirPlay 输出选择 |
| `Amperfy/Screens/ViewController/SettingsHostVC.swift` | 设置容器；把 SwiftUI `Settings` (@Published) 与持久化设置双向绑定 |
| `Amperfy/SwiftUI/Settings/` | 设置页；`NavigationTarget` 定义侧栏与页面，`SettingsTabView` 画侧栏 |
| `AmperfyKit/Storage/` | Core Data 库、`UserSettings` 等设置模型、同步/缓存 |
| `AmperfyKit/Common/L10n.swift` | App 自身文案的中英词典（英文即 key） |
| `AmperfyKit/Common/M3UPlaylist.swift` | M3U/M3U8 解析、导出与按曲库匹配（导入/导出 UI 在 `PlaylistsVC` / `PlaylistDetailVC`） |
| `Amperfy/zh-Hans.lproj/Localizable.strings` | 只负责系统 UI（菜单栏、标准按钮）的中文 |
| `AmperfyKit/Player/` | 播放核心、ReplayGain、EQ、Now Playing |
| `Vendor/AudioStreaming/` | 内嵌流式播放引擎（环形缓冲、gapless、交叉淡入淡出 `AudioPlayer.swift` / `AudioPlayerRenderProcessor.swift`） |

## 4. 当前产品状态（已验证）

- 侧栏 / 首页 / 专辑网格：Apple Music 风；侧栏 210 pt、行高 38（32 高亮 + 间距）、13 pt 文案、实心 16 pt 图标。
- 封面：加载时用 ImageIO 降采样到最长边 1024 px，静态缓存上限 64 MB / 300 张（`LibraryEntityImage`）；不要再改回无上限 `NSCache`。
- WebDAV 曲库：启动/切回前台时自动做增量扫描（15 秒去抖，仅 WebDAV + 非离线 + 初始同步完成时；见 `AppDelegate.triggerWebDAVIncrementalScanIfNeeded`），不必手动“重新同步资料库”；本地文件夹仍需手动。
- 大播放器：主窗口内 `.fullScreen` 上滑（不是 sheet），两栏（左封面+信息+传输键，右歌词列）；**固定深色**（Apple Music 风格，不受外观设置影响）；ESC / 左上 chevron 关闭。
- 独立歌词栏（SplitVC 右侧 `LyricsVC`）已固定深色，与大播放器一致。
- 迷你条：Liquid Glass（`UIGlassEffect(.regular)`）；点封面/标题打开大播放器。
- AirPlay 键：自绘 window 级玻璃浮层（`AudioOutputPicker.swift`），CoreAudio 枚举输出设备，过滤 `CADefaultDeviceAggregate*`。
- 音量：180×36 毛玻璃胶囊 + 细轨滑块；大播放器标题栏与 compact 播放器都有。
- 码率行（如 “FLAC 888 kbps”）已隐藏；传输键 85% 白、尺寸 19/21/27 pt，随机/循环激活时用主题红。
- 设置：窗口内整页覆盖，侧栏 6 项——通用 / 账户 / 播放 / 显示 / 资料库 / 支持与关于；二级页：均衡器（播放）、轻扫操作（显示）、封面与缓存（资料库）、第三方许可 / X-Callback URL / 开发者工具 / 版本信息（支持与关于）。
- 外观：设置 → 显示 → 外观（系统/浅色/深色），全 App 语义色；强制深色启动无白闪；新窗口继承 App 内选择。
- 语言：设置 → 通用 → 语言（跟随系统 / 简体中文 / English）。写 App 自己的 `AppleLanguages`，**重启后生效**（会弹窗提示）；不要期待运行期整窗切换。
- 已中文化：App 文案、系统菜单（zh-Hans.lproj）、未知元数据占位符（`L10n.trPlaceholder`）。
- 歌词偏移：播放器「更多」→ 歌词偏移（已同步 / 提前 0.2–1.0s / 延后 0.2–1.0s）。含 LRC `[offset:]`，手动值存 `settings.user._lyricsOffsetMs`（±5000ms），行切换与词级高亮、点歌词 seek 共用同一偏移。
- 歌单 M3U：播放列表「更多」→ 导入 M3U 歌单（UTType m3u/m3u8，按相对路径/文件名/曲名/艺人-曲名匹配，导入后弹“已导入 N 首，跳过 N 条”）；歌单详情「更多」→ 导出 M3U（`#EXTM3U` + `#EXTINF`，相对 `song.url`，分享面板）。编解码与匹配在 `AmperfyKit/Common/M3UPlaylist.swift`。
- 无缝播放 & 交叉淡入淡出：跨曲共用同一个 `AudioStreamingPlayer` 环形缓冲，不重置。播到剩余 `max(10, crossfade+8)` 秒时预加载下一首；配置了淡入淡出时，引擎在 ring 里把 outgoing 最后 N 秒与 incoming 开头 N 秒做线性混音，切歌瞬间跳过 incoming 已混音的 N 帧（`framesState.played = N`，所以新曲 UI 从 N 秒开始），样本级连续、无静音。设置 → 播放 → 交叉淡入淡出（关闭 / 3 / 5 / 8 秒，**默认关闭**），存 `settings.user._crossfadeSeconds`；引擎缓冲 30s（`AmperfyKit.createPlayer`）。改这块先读 `Vendor/AudioStreaming/.../AudioPlayer.swift` 的 Crossfade 段和 `AudioPlayerRenderProcessor.inRender` 的 crossfade 分支。注意 `DispatchTimerSource.deinit` 只在 `state == .suspended` 时 resume——激活状态的定时器再 resume 会让 `restartPlayer()` 在 deinit 时 SIGTRAP。
- 性能约束（2026-11-12 优化）：歌词只在可见时做 60 Hz 更新（`LyricsView.scroll` 不可见即返回；行查找二分）；视觉分析器 30 fps 节流；播放/歌词 Timer 注册到 `.common` 模式（滚动时不停）；恢复进度每 5 s 更新一次；交叉淡化关闭时不跑 250ms 定时器。
- 状态：**没有 Last.fm / scrobble**。上游的 `ScrobbleSyncer`、`ScrobbleEntry`（Core Data 实体与 MO/包装器）、`scrobble`/`syncNowPlaying` 协议方法、`isScrobbleStreamedItems` 设置、Account/AbstractPlayable 关系都已移除；Core Data 当前模型是 `Amperfy v50`。
- 当前用户数据：WebDAV 账户、约 40 艺人 / 38 专辑 / 53 歌曲、缓存约 1.8 GB（测试环境，勿清空）。

## 5. 设置与持久化（改设置页前必读）

- 底层：`UserDefaults` 三个 Data key：`settings.user` / `settings.account` / `settings.app`，内容为 JSON。
- 模型：`AmperfyKit/Storage/Settings.swift` 的 `UserSettings` / `AccountSettings` / `AppSettings`。
- **新增字段是安全的**：`AmperfySettings.decodeFillingMissingKeys` 会用默认值补齐旧 JSON 缺的键；解码结果按原始 Data 缓存。
- UI 绑定：SwiftUI 用 `ObservableSettings.swift` 里的 `Settings: ObservableObject`（一堆 `@Published`）；`SettingsHostVC.viewIsAppearing` 建立每个字段的 Combine sink，写回 `appDelegate.storage.settings…` 并执行副作用。新增设置项必须同时：加模型字段 → 加 `@Published` → 在 `SettingsHostVC` 里初始值和 sink。
- 外观值：`_appearanceMode`（0/1/2，对应 `UIUserInterfaceStyle`）。
- 语言值：`_appLanguage`（`system` / `english` / `simplifiedChinese`），由 `AppDelegate.applyAppLanguage` 映射到 `AppleLanguages`。
- 调试时可直接改 defaults（先退出 App，改完 `killall cfprefsd`）：

```bash
python3 - <<'EOF'
import plistlib, json, os
p = os.path.expanduser("~/Library/Preferences/de.familie-zimba.amperfy-music.plist")
d = plistlib.load(open(p, 'rb'))
j = json.loads(d["settings.user"].decode('utf-8'))
j["_appearanceMode"] = 2          # 0=系统 1=浅色 2=深色
d["settings.user"] = json.dumps(j).encode('utf-8')
plistlib.dump(d, open(p, 'wb'))
EOF
killall cfprefsd
```

## 6. 验证方法与坑

- **CUA（电脑控制）**：`node_repl` + `@qoder-space/computer-use`。用完整 App 路径 `getApp(...)`；先 `getAXState()` 拿元素 ID，再 click。SwiftUI `Menu` 常常点元素 ID 不开，改点坐标，并且**取截图/查树要在同一调用里完成**，否则菜单会被 AX 查询关掉。
- **原生截图**（更可靠、不受 CUA 缓存帧影响）：
  ```bash
  swift /tmp/listwin.swift                 # 输出 windowID | 标题 | frame（脚本可能不在则重写 CGWindowList 小程序）
  screencapture -x -o -l <windowID> /tmp/x.png
  ```
  截图不会覆盖同名文件，用新文件名。
- 设置用 `Cmd+,` 打开；ESC 关闭。
- 改完 XIB/约束必须真机看，`xcodebuild` 成功不代表布局对。
- Catalyst 已知渲染坑：
  - 代码 new 的 symbol UIButton，`tintColor` 可能被忽略（只渲染 ~62% 亮度）；要把颜色烘焙进图片：`UIImage(systemName:withConfiguration:)?.withTintColor(tint, renderingMode: .alwaysOriginal)`。
  - `UIPopoverPresentationController` 箭头在 Catalyst 会变黑三角 → 账户浮层是自绘 window overlay，不要改回 popover。
  - `.fill` 分布的 UIStackView 会把剩余高度全给第一行 → 行要显式 `heightAnchor`（AirPlay 面板踩过）。
  - 侧栏/列表右侧分段索引字母仍为主题红（`tableView.sectionIndexColor` 无效），未解决、别误以为回归。
  - 大播放器固定 `.dark`、独立 `LyricsVC` 仍浅色，都是有意设计，不是暗色模式 bug。
- 用户 shell 里 `find`→`fd`、`grep`→`rg`、`rm`→`trash`；脚本/文档里写命令时注意，必要时用绝对路径 `/usr/bin/grep`。

## 7. 协作偏好（重要）

- 回复用中文、结论先行、短；不要丢一堆选项让用户选，给一个推荐和真实代价。
- 执行类请求（“帮我改/加/提交”）直接做；只对必须本人完成的步骤（签名、OAuth、sudo、真机）留给他。
- 视觉改动要**渲染真实截图**给他看，文字描述不算交付；先对齐现有 Apple Music 风格 token（13 pt 行、32/38 pt 行高、210 pt 侧栏、次级灰、主题红）。
- 最小改动，不做未要求的功能；不要为假设需求加抽象/开关。
- 本地提交用英文 commit message；**不要 push**；不要擅自 reset/clean/删除文件。
- 每次改完更新 `HANDOFF.md` 的改动日志（一条 bullet，写清文件、原因、验证方式、坑）。

## 8. 已知问题 / 待办

当前没有用户指派的未完成任务。以下只是已知瑕疵，除非用户点名否则不用主动做：

1. 语言切换必须重启 App；系统菜单与 App 文案一起切换属于预期行为。
2. iOS 真机路径未系统验证；当前主要在 macOS Catalyst 上开发。
3. 播放缓存不会自动淘汰：`cacheLimit=0`（默认）表示无限，超过上限只阻止新下载、不删旧文件。用户缓存是离线播放数据，不要自动清空。
4. CarPlay 7 个文件仍编进 target（Catalyst 不触发），保留是为了不丢 iOS CarPlay 能力；删除前先问用户。

已修（2026-11-12 全面清理）：
- 分段索引字母已改中性灰（`BasicTableViewController` 布局时给私有 `*Index*` 子视图设 `.secondaryLabel`）。
- 独立歌词页已固定深色。
- 随机/循环按钮已有 `accessibilityLabel`（读屏不再读成 "go forward"）。
- 设置页反复开关不再泄漏 SwiftUI 树（29 个 sink 全部 `[weak self]`）。
- 启动不再同步扫描播放缓存目录（移到后台 utility task）。

## 9. 开工前 30 秒检查

```bash
cd /Users/apple/Desktop/AI/Quder/amperfy
git status --short          # 应干净
git log --oneline -3
pgrep -fl "Amperfy.app/Contents/MacOS/Amperfy" || echo not-running
```

先读 `HANDOFF.md` 里对应模块的最新 bullet，再动代码。
