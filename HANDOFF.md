# Amperfy fork 交接文档

最后更新：2026-11-11（Mac Catalyst / macOS 27 / Xcode 27.1）
适用对象：接手继续改这个仓库的 AI。先读完第 0、1 节再动代码。

---

## 0. 先读：硬约束

1. 这是用户自用的 Amperfy fork，**不要 push、不要创建 PR**。仓库里有 `origin`（上游 BLeeEZ/amperfy），但用户明确要求推送前必须先问。
2. 工作区里有 **215 个未提交改动文件**（见第 1 节）。不要 `git reset --hard`、不要 `git checkout --`、不要清空工作区；这些就是唯一副本。
3. 删除文件默认用 `trash <path>`（用户的 `rm` 就是 trash）；确需永久删除才用 `/bin/rm`。
4. 仓库不放二进制/大文件。
5. 密码、token、Cookie 不打印到聊天/文档/日志。
6. 视觉类改动必须在真实运行的 App 里渲染验证，不能只靠文字描述或编译通过。
7. 小改动不要跑全量测试；这个项目没有稳定的 UI 测试，主要靠真机操作 + 截图/视图层级核对。

---

## 1. 项目与环境

- 仓库：`/Users/apple/Desktop/AI/Quder/amperfy`
- 分支：`feature/webdav-local`，最后提交 `bdee704`（"Settings: fix dismiss ..."）
- 当前是**大面积未提交状态**：`git status --short` 215 条，`git diff --stat` 约 +2366 / -17462（删掉了 Subsonic/Ampache 相关代码）。
- 目标平台：Mac Catalyst（macOS 27）。Bundle ID：`de.familie-zimba.amperfy-music`。
- 运行数据：`~/Library/Application Support/Amperfy/Amperfy.sqlite`（运行中有 `-wal/-shm`；直接读库前先拷贝一份，或只读打开）。
- 登录/库来源：登录页 `Auto-Detect` 可选 **Local Folder** 或 WebDAV。credentials 是 Codable，路径字段为 `localFolderPath` / `localFolderBookmark`（`AmperfyKit/Api/LoginCredentials.swift`），不要靠改数据库切库，走登录页。
- 数据库里目前同时存在 `ZACCOUNT` 的两条记录（ZAPITYPE 4=local、5=webdav），以当前激活账号为准；重装/清库会丢用户资料。

### 构建与启动

```bash
cd /Users/apple/Desktop/AI/Quder/amperfy
xcodebuild -project Amperfy.xcodeproj -scheme Amperfy -configuration Debug \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

必须带 `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`，否则会因为缺 provisioning profile 失败。

启动（DerivedData 哈希可能变，先用下面命令定位）：

```bash
find ~/Library/Developer/Xcode/DerivedData -path '*Debug-maccatalyst/Amperfy.app' -maxdepth 6 | head -1
open "<上一步输出>/Contents/MacOS/../../"   # 即 open <Amperfy.app 路径>
# 重启：
pkill -f "Amperfy.app/Contents/MacOS/Amperfy"; sleep 2; open <Amperfy.app 路径>
```

典型路径：`~/Library/Developer/Xcode/DerivedData/Amperfy-eyetrzidtspoevgufmttlsihklja/Build/Products/Debug-maccatalyst/Amperfy.app`

---

## 2. 产品形态与用户偏好（不要改回去）

- 保留 Amperfy 原 UI，删掉 Subsonic/Ampache，只做本地 + WebDAV。
- 播放器 large 已改为 Apple Music 两栏：左侧封面 + 歌曲信息 + 底部传输键，右侧歌词列（始终显示、保留逐字高亮）；compact 仍是队列列表。large 时控制条收在左栏内、AirPlay/List/More 在歌词列右下角；compact 时控制条恢复全宽、工具组回到控制条。
- 呈现方式对齐 Apple Music：点击主窗口迷你条后，在主窗口内整页进入播放器（同窗全屏、淡入），不是 sheet，也不是新窗口。
- Apple Music 风格：侧栏 210pt、行 13pt、表头 11pt、行高 32pt、中性灰选中、4 列等比网格不裁切；设置独立窗口/sheet 也用同一套。
- 中文界面跟随系统语言（不要新增独立语言开关）。
- 歌词：YRC 优先（词级逐字填充），没有 YRC 时用 LRC；外挂歌词文件只认 `.yrc`/`.lrc`，不写进音频标签。
- 播放器/歌词相关历史结论：Apple Music 式逐字高亮、句首即切、点击歌词立即跳转并回正、弹簧滚动。

---

## 3. 架构地图（改之前先看这些）

### 3.1 库扫描与写入

| 文件 | 作用 | 关键入口 |
| --- | --- | --- |
| `AmperfyKit/Api/Local/LocalLibraryIndexer.swift` | 本地文件夹扫描、标题/专辑/封面/歌词读取 | `syncInitial` L78，`read` L158，`relativePath` L251 |
| `AmperfyKit/Api/WebDAV/WebDAVLibraryIndexer.swift` | WebDAV 扫描 | `syncInitial` L84，`enumerate` L242，`read` L305，`fetchLyrics` L398 |
| `AmperfyKit/Api/FileSourceLibraryWriter.swift` | 把扫描结果写入 Core Data（新文件） | 以 `Writer` 为准 |
| `AmperfyKit/Api/Local/LocalFolderAccess.swift` | 安全作用域书签激活 | `activate(bookmark:key:)` L76 |
| `AmperfyKit/Api/LoginCredentials.swift` | local/webdav 凭据与本地路径 | L41 / L49 / L51 |

歌词候选文件名顺序见 `WebDAVLibraryIndexer.swift` L408：`.yrc` 优先于 `.lrc`（大小写都认）。

### 3.2 歌词解析与显示

| 文件 | 作用 | 关键入口 |
| --- | --- | --- |
| `AmperfyKit/Api/LibrarySyncerDefaults.swift` | 歌词文件统一解析（新文件） | `parseLyrics` L75，`isYRC` L105，`YRCFileParser` L95，`LRCFileParser` L172 |
| `AmperfyKit/Api/BackendApi.swift` | `LyricWord` L124，`LyricLine.words` L143 | 词级时间模型 |
| `Amperfy/Screens/View/Lyrics/LyricsView.swift` | 歌词表格、自动滚动、按音节推进进度（30Hz 只更新遮罩） | 行间距 `lineSpacing=30` L44，点击跳转 L199，`updateActiveFill`、`refreshAllVisibleCells` |
| `Amperfy/Screens/View/Lyrics/LyricTableCell.swift` | 行层 + 字形层；模型持有音节时间轴 | 当前行 29pt bold、非当前 24pt semibold，`lineSpacing=6`；`syllableProgress`、`applyProgress` |
| `Amperfy/Screens/View/Lyrics/LyricsLineLayers.swift` | 三层次：`LyricsTimingMap`（时间轴→显示文本）、`LyricsTextLayout`/`LyricsGlyphView`（字形）、`LyricsSyllableMaskLayer`（音节遮罩） | `syllables(for:estimatedDuration:)`、`apply(progress:)` |

历史修复（不要回退）：
- 逐字填充不得回到“每 tick 重建 NSAttributedString”：现在是两个字形视图 + 每个音节一个渐变遮罩，时钟只改遮罩宽度；30Hz 限流在 `LyricsView.updateActiveFill`。
- 音节时间必须映射到**实际显示的字符串**（UTF-16 range）后交给 TextKit 布局取 rect，不要按字符比例拍脑袋；YRC 词文本与整行不一致时 `LyricsTimingMap` 会自动按长度比例分配。
- 换行时必须 `refreshAllVisibleCells`：只刷新旧行/新行会留下“上一行还是全亮”的残影（cell 可能当时不在可见区）。
- `LyricsSyllableMaskLayer` 必须实现 `init(layer:)`，否则 CALayer 隐式动画复制 presentation layer 时会 SIGTRAP 崩溃；mask 自身 frame 用 `setFrameWithoutAnimation`。
- 点击歌词时先清 `suppressAutoScrollUntil` 再立即滚动；否则音频已经跳到新行，列表还停在旧位置几秒（用户反馈的"错位"）。

### 3.3 播放器 UI（本次重设计重点）

| 文件 | 作用 | 关键入口 |
| --- | --- | --- |
| `Amperfy/Screens/Player/PlayerControlView.swift` | 底部控制栏（XIB 视图） | `configureTransportControls` L102，`makeToggleButton` L134，`configureUtilityCluster` L146，`refreshTransportToggles` L179，`updateVolumeControlVisibility` L196，`displayPlaylistPressed` L327 |
| `Amperfy/Screens/Player/PlayerUIHandler.swift` | 图标配置与按钮刷新 | `utilitySymbolConfiguration` L42，popup 的 List 按钮 config L268 |
| `Amperfy/Screens/Player/PopupPlayerVC.swift` | 播放器容器（主窗口同窗全屏 / 独立窗口共用） | `setupVolumeControl` L184，`updateVolumeControlVisibility` L239 |
| `Amperfy/Screens/Player/PlayerWindowVolumeControl.swift` | Catalyst 标题栏音量（NSToolbar 桥） | `attach` L88，`detach` L102 |
| `Amperfy/Screens/Player/VolumeSlider.swift` | 自绘音量滑块（细轨 + 小圆钮，Apple Music 比例） | `draw`，`updateValue(at:)`，AX increment/decrement |
| `Amperfy/Screens/Player/PopupPlayer+Animations.swift` | compact/large 切换 | `changeDisplayStyleVisually` L36（开头先更新音量控件可见性） |
| `Amperfy/Screens/Player/MiniPlayerView.swift` | 主窗口底部迷你条 | `configureForMac` L589，tap 打开播放器 L599，`miniPlayerGotTouched` L721，`openPlayerView` L725 |
| `Amperfy/Screens/Player/PlayerControlView.xib` | 控制栏 XIB | 传输键 stack id `SoI-ny-Hw0`（L53） |
| `Amperfy/Screens/Player/PopupPlayerVC.xib` | 播放器容器 XIB | 大播放器顶部约束 `18e-Ia-XA9`，constant=54（L56） |
| `Amperfy/Screens/Player/LargeCurrentlyPlayingPlayerView.xib` | 大封面/详情 | 封面高度上限约束 `z4T-8m-Q1a`（L42） |

### 3.4 中文化

- `AmperfyKit/Common/L10n.swift`：`enum L10n` L23，`tr` L27，中文词条在同文件表里。界面字符串统一走 `L10n.tr(...)`，不要新增 `.strings` 语言开关（跟随系统）。
- 已汉化：播放器选项菜单（清空播放器/睡眠定时器/播放器信息等）、睡眠定时器全部档位、PlainDetails 播放器信息页、描述/歌词标题。
- 菜单是 `UIMenu`，在 AX 树里以菜单形式出现，但 CUA 抓菜单后再查状态会导致菜单关闭（见第 6 节）。

---

## 4. 最近一次会话完成的内容（2026-11-11）

### 4.1 播放器重设计（已验收）

目标：保留单栏，但控制方案与 Apple Music 一致。

- 进度条下只保留 **一行 5 个控制键**：随机、上一首、播放、下一首、循环（`configureTransportControls`）。
  - 播放 30pt，前后 22pt，随机/循环 17pt（`UIImage.SymbolConfiguration`）。
  - 随机开启、循环非 off 时用 `.tintColor`，否则 `.label`；随机被设置禁用时 alpha 0.35。
- 右上角音量：`PopupPlayerVC.setupVolumeControl`（L184）。
  - 滑块必须用自绘的 `VolumeSlider`（轨道 6pt；圆钮是 **22×16pt 横向胶囊**、拖动时 24×17pt，macOS 26 滑块就是胶囊钮不是圆钮），**不要换回 UISlider**：Mac idiom 下 UIKit 会映射成 AppKit 滑块，轨道变粗、圆钮巨大（用户 2026-11-12 明确否决）；也别往细调（3pt/11pt、4pt/13pt 都被嫌细）。
  - 对比依据：与 Apple Music 标题栏同倍率截图（2x）量过——Apple 轨道约 5.5pt、胶囊钮约 20×14pt、控件高约 34pt；我们的标题栏行只有 28pt，所以胶囊取 180×28（圆角 14）已是整行高度，靠加粗轨道/钮来对齐观感。
  - 内容区 fallback 胶囊 180×36；都是 `UIBlurEffect(.systemUltraThinMaterial)` 毛玻璃底、滑块在左、11–12pt 喇叭图标在右。
  - 2026-11-12 最终位置：large 时音量胶囊**放进窗口标题栏**（与左上红绿灯同一行、右对齐），内容区胶囊隐藏。实现 `PlayerWindowVolumeControl.swift`：`UITitlebar.toolbarStyle = .unifiedCompact` + `NSToolbarDelegate`，item 用 Catalyst 桥 `NSToolbarItem(itemIdentifier:barButtonItem:)` 包 `UIBarButtonItem(customView: UIVisualEffectView)`。
  - 标题栏 chrome 归 `PlayerWindowVolumeControl` 管：`attach` 时保存并隐藏 `titleVisibility`、`separatorStyle = .none`、`toolbarStyle = .unifiedCompact`；`detach`（关播放器 / 切 compact）时 `toolbar = nil` 并逐项还原。
  - 内容区胶囊保留为 fallback：attach 失败（窗口还没 scene/无标题栏）时仍显示；`viewDidLayoutSubviews` 每次重试 attach 并同步隐藏状态。
  - AppKit 控件（`NSSlider`/`NSVisualEffectView`/`NSView`）在 Catalyst 仍不可用，但 UIKit 视图可经上述桥进标题栏。音量联动：`PopupPlayerVC.refresh()` 调 `windowVolumeControl.syncFromPlayer()`。
  - 早期用黑色 28% 实底 180×30，在深色封面上像一块黑斑，2026-11-11 已换成毛玻璃，不要退回实底。
  - 播放器内已无 UISlider；别处若还要用 UISlider，Mac idiom 下必须 `preferredBehavioralStyle = .pad`，且不能调 track tint（会抛 `UICatalystMacIdiomUnsupported` / EXC_BREAKPOINT）。
  - 只在大尺寸显示；compact 时隐藏，音量按钮回到右下工具区。
- 右下工具区：AirPlay、显示样式切换（List）、更多，右对齐；旧的两排 7 键布局已隐藏（`optionsStackView.isHidden = true`）。
- 布局修复：
  - 大播放器顶部内边距 20 → 54（`PopupPlayerVC.xib` L56），避免音量胶囊压住封面。
  - 封面是 `width=height` 且最大 360，窗口较矮时槽位只有 320 高，封面会**向上溢出 29pt**，正好钻到音量条下面。已加“高度 ≤ 槽位高度”约束（`LargeCurrentlyPlayingPlayerView.xib` L42），较矮窗口里封面 320×320，不再溢出。
- 主窗口底部迷你条在 Mac 上原本点击无反应：已给 `infoView`（封面/标题区）加 tap 打开播放器，进度条区域不受影响（`MiniPlayerView.swift` L599）。
- sheet 关闭（2026-11-11 补，现已改为同窗全屏）：播放器现在是主窗口内的 `.fullScreen` modal（`crossDissolve`，见 `MiniPlayerView.openPlayerView`），不再有 sheet 把手；ESC（`AppDelegateKeyboardCommands.swift` L336 附近）和左上角半透明 `chevron.down` 关闭按钮（`PopupPlayerVC.swift` `setupCloseButton` L243）都返回资料库。独立 Mini Player 窗口不显示关闭按钮。
- 两栏布局（2026-11-11）：`PopupPlayerVC.setupLargeLyricsColumn` 在主窗口右侧建歌词列（宽 44%、间距 24），并停用 XIB 里“大播放器/控制条贴右边距”的约束；large 时控制条改贴左栏右缘、工具按钮（AirPlay/List/More）挪到歌词列右下角；compact 时控制条恢复全宽、工具组回到控制条内，队列表顶部内边距加到 54 避免被左上关闭按钮压住。`LargeCurrentlyPlayingPlayerView.prepare(lyricsContainer:)` 把 `LyricsView` 用约束塞进该列；外部列模式下强制 `.lyrics`、封面保持全不透明、点击歌词不再切回封面。无歌曲时右栏显示“播放歌曲并在此处查看歌词。”。工具组搬移见 `PlayerControlView.attachUtilityCluster(to:)` / `restoreUtilityCluster()`。
- 播放器显示样式：右下 List 按钮 → `switchDisplayStyleOptionPersistent()`，设置会持久化。测试完记得切回 large。

### 4.2 歌词（2026-11-12 重构为三层次）

- 逐字填充改为“音节遮罩”：`LyricsTimingMap` 把 YRC 词/ LRC 逐字时间映射到显示文本的 UTF-16 range，TextKit 取每个音节的 rect，`LyricsSyllableMaskLayer` 用渐变子层显示已唱部分；每 tick 不再重建属性字符串（30Hz 只改遮罩）。
- 字形用 `LyricsGlyphView`（TextKit 自绘）双份：暗色底 + 亮色遮罩层，布局与遮罩共用同一个 `LyricsTextLayout`，不会错位。
- 换行时刷新所有可见 cell（`refreshAllVisibleCells`），避免上一行残留全亮。
- 点击歌词立即跳转并立即回正（去掉 5 秒滚动抑制）。
- 重播/整段回跳必须把列表拉回第一行：`scroll(toTime:)` 里“第一行时间还没到”的分支原来只在 `isFirstSync || needsRealignAfterUserScroll` 时 `scrollToRow(0)`，单曲循环重播、流重启、进度条拖回开头都会停在旧行 → 用户看到“歌词和音乐时间对不上”。现在只要自动滚动没被用户拖动抑制（`isAutoScrollAllowed`）就回到第 0 行（`scrollToRow` 对同一目标幂等，不会每 tick 起动画）。
- **根因（2026-11-12 定位）**：不是歌词代码，是流式 FLAC 的 seek 落点不准。上游 `AudioStreaming` 1.4.4 把时间换算成**按平均码率估的字节偏移**（`AudioFileStreamSeek` 标记 `offsetIsEstimated`），而 `AudioEntry.progress` 在 seek 未完成时直接返回**请求的时间**。VBR FLAC 里这个偏移会差好几秒：用真实文件算，跳 185s 落在 178.8s、跳 200s 落在 192.2s；App 内实测点 3:29 实际在 3:25 播、歌放到 3:44 才结束（真实时长 3:39.87）。于是时钟说 3:29、耳朵在 3:25 → 越往后越“对不上”，靠前误差小 → “有时可以有时不行”。点进度条/点歌词只是触发 seek，跟映射无关。
- **修复**：`Vendor/AudioStreaming`（MIT，1.4.4，只保留 AudioCodecs/AudioStreaming 两个 target，`XCLocalSwiftPackageReference`），`AudioFileStreamProcessor.swift` 里 seek 后解析第一帧 FLAC 帧头（RFC 9639 §9.1，CRC-8 校验）拿真实帧号/采样号：① `seekTime` 改成真实采样位置，时钟与解码内容一致；② 落点偏差 >0.25s 时按本地 bytes/s 重算字节偏移再请求一次，最多 2 次。实测 193.79s → 首落 186.64s → 重试落在 193.68s（误差 0.11s）；184.22s 两次收敛到 184.20s。Ogg/其他格式不受影响。改法见 `Vendor/AudioStreaming/PATCHES.md`，升级依赖时要重新打补丁。
- Amperfy 侧：去掉 seek 门控（门控要求 `|elapsed - target| <= 1`，在真实落点偏离时反而会冻结 UI 6 秒）；`BackendAudioPlayer.seek` 后立即 `notifyCurrentTime()`；进度条 elapsed 定时器 1s → 0.2s，避免点歌词后进度条比歌词晚最多 1 秒。
- **暂停态 seek（2026-11-12 修）**：暂停时 `seek` 只登记 `seekRequest`，但 `processSource()` 开头的 `guard internalState != .paused` 直接 return，`resume()` 也不处理它 → 恢复后要么卡在请求位置（`progress` 一直返回 `seekRequest.time`），要么旧 entry 读完后触发 Amperfy 的 `Replay` 从头播。修在 `Vendor/AudioStreaming/AudioStreaming/Streaming/AudioPlayer/AudioPlayer.swift` 的 `resume()`：先读 `audioPlayingEntry.seekRequest.requested`，有挂起 seek 时先不 `startPlayer`，引擎/source 恢复后在 `sourceQueue` 上跑一次 `processSource()`（reading===playing → 原地 `processSeek`；reading 已因 EOF 关闭 → `setCurrentReading` 重建后由首包触发 `processSeek`），再用新增的 `isPlayerHardwareRunning` 判断是否需要 `startPlayer(resetBuffers: false)`，避免重复 start。`PATCHES.md` 已记录，升级依赖要重打。
- 验证方法：点歌词时用 lldb 在 `LyricsView.tableView(_:didSelectRowAt:)` 打印 `indexPath.row` 与 `lyric.start`，确认行→时间映射正确（本例第 13 行=62970ms，进度条应显示 1:02）。也可以在 `LyricsView.scroll(toTime:)` 断点直接 dump `self.lyricModels` 全表时间；清明雨上尾部 `21:179280 22:185700 23:192780`。注意鼠标停留会高亮悬停行，别把它误认成当前行；AX 状态与截图抓取有先后，比较时以“截图里的进度条秒数 + 高亮行”为准。
- 排版：当前行 29pt bold / 非当前 24pt semibold，行间距 30，段内行距 6；非当前行仍做高斯模糊（CI 快照）。
- 已验证：真机播放（风度/好安静/不分手的恋爱）、行内半亮边界、跨行换行、点击歌词跳转；无崩溃日志，播放 CPU 约 10–13%。2026-11-12 FLAC seek 修复后复测：播放中点进度条 → 1:42 高亮“把你最爱的歌”（86.84s）、3:06 高亮“又是清明雨上”（185.70s，落点 186.6）、连续 4 次快速跳转 → 2:28 高亮“我在人间彷徨”（146.05s）、跳到 3:29 后歌曲在 3:39 正常结束（修复前会拖到 3:44）；每次 seek 的校正日志为 `FLAC seek correction: requested=… landed=…`。暂停态 seek 修复后复测（缓存 FLAC）：暂停停 0:05 → 拖到 1:31 → 播放后 1:36 继续、高亮行正确；倒着拖 0:20 → 0:27；连拖 2:30→3:00 → 3:03；暂停时点歌词 2:52 → 播放后 2:56；播放中拖 0:30 → 0:36 无回归；`log stream` 里只有 FLAC 校正（91.393→91.626、179.915→179.862），没有 `Replay`。

### 4.3 中文化（此前完成）

- 播放器选项菜单、睡眠定时器、播放器信息页等已全部中文；CUA 验证过菜单树无英文残留。

---

## 5. 现状与验证方法

当前 App 已重启并在跑（Debug-maccatalyst 构建）。显示样式 large，音量 100%。播放器数据可能处于暂停/0:00，取决于上次会话。

### 手动验证路径

1. `open` App → 主窗口 `首页`，底部有迷你条。
2. 点击迷你条**封面/标题区** → 主窗口内整页播放器（同一窗口，`crossDissolve` 淡入，不再是 sheet，也不切独立窗口）。
3. 检查：音量胶囊在右上；两栏布局（左封面+信息，右歌词）；5 个控制键一行；右下 3 个工具图标。
4. 点右下 List 图标 → compact：音量滑块消失、音量按钮出现在右下；再点一次切回 large。
5. 播放/暂停、点进度条、拖音量应正常。
6. 崩溃看 `~/Library/Logs/DiagnosticReports/Amperfy-*.ips`。注意：2026-11-11 22:42 的 `.ips` 是早期 slider tint 崩溃，修复后未再出现，不要误判。

### 本次验证用的截图（/tmp 可能被清理）

- `/tmp/player_final.png` / `/tmp/player_compact2.png` / `/tmp/player_mini_final.png`：sheet 时代的旧截图，仅供对照；当前已是主窗口内全屏。

### 用 CUA + lldb 核布局（可复现）

- CUA（node_repl）连接要用**完整 app 路径**的 `getApp`，避免启动到旧包。
- 播放中 AX 元素 ID 每个 tick 都可能变：取树和点击必须在同一个调用里。
- 坐标点击要求“当前截图 + 窗口几何未变”，且坐标是屏幕点（Retina 截图会被缩放，别按图片像素算）。
- Catalyst 的 sheet 是独立窗口（CGWindow 名 `Untitled`），`screencapture -l <id>` 有时抓到父窗口；CUA 直接截图更稳。
- 菜单（`UIMenu`）抓状态会关闭，菜单项点击极易报 “menu is no longer open”；能走按钮/快捷键就别走菜单。
- 需要精确 frame 时用 lldb 附加本进程（非沙盒限制）：
  ```bash
  xcrun lldb -p <pid> -b \
    -o 'expr -l objc++ -- UIWindow *$win = (UIWindow *)[[[UIApplication sharedApplication] windows] firstObject]' \
    -o 'expr -l objc++ -- UIViewController *$vc = [[$win rootViewController] presentedViewController]' \
    -o 'expr -l objc++ -O -- (id)[(id)[$vc valueForKey:@"largePlayerPlaceholderView"] subviews]' \
    -o 'detach' -o 'quit'
  ```
  本次就是靠它发现封面 frame = (114, -29; 360 360) 溢出槽位。

---

## 6. 已知坑 / 注意

1. **Mac idiom + UISlider**：不要去掉 `preferredBehavioralStyle = .pad`，也不要在 Mac idiom 下调用 track tint API；会直接崩。播放器音量已改为自绘 `VolumeSlider`，不受此限制；但如果新代码又要用 UISlider，记住这条。
2. **XIB 封面溢出**：`LargeCurrentlyPlayingPlayerView.xib` 的封面是 1:1、最大 360，而槽位高度由 stack 决定；不要删除 `z4T-8m-Q1a` 高度上限，否则较矮窗口又会压到音量条。
3. **同窗全屏与独立窗口共用 `PopupPlayerVC`**：主窗口全屏随窗口尺寸（最小 980×540），独立窗口 1024×768；布局改动两边都要看。
4. **显示样式会持久化**：把 App 停在 compact 会影响用户下次打开；验证后切回 large。
5. **XIB 修改必须真机看**：只 `xcodebuild` 成功不代表 IB 约束按预期生效（可用 lldb 看 frame）。
6. **shell 别名**：`find`→fd、`grep`→rg、`rm`→trash、`ls`→lsd；需要标准行为时用 `/usr/bin/find`、`rg`、`/bin/rm`、`/bin/ls`。
7. **Catalyst 标题栏**：AppKit 控件（NSSlider/NSVisualEffectView/NSView）不可用；但 UIKit 视图可以通过 `NSToolbarItem(itemIdentifier:barButtonItem:)` 进原生标题栏（见 `PlayerWindowVolumeControl.swift`）。`titlebar.toolbar = nil` 会移除整个工具栏，只在播放器关闭时做；titleVisibility/separatorStyle/toolbarStyle 必须成对保存与还原，否则关播放器后资料库窗口没标题。标题栏音量 slider 也固定在 `preferredBehavioralStyle = .pad`。
7. **不要动用户库**：不要清 `~/Library/Application Support/Amperfy`，不要重装/重建账号，除非用户要求。
8. 播放按钮/随机/循环的 AX 描述里，`repeat.1` 符号会被读成 "go forward"（系统符号的 accessibility label），只是可读性小瑕疵，不影响功能。需要的话可给按钮显式设 `accessibilityLabel`。

---

## 7. 可选后续（都不是 bug）

- 音量胶囊现为 Apple Music 规格 180×36 + 毛玻璃；若在浅色封面上可读性不足，优先调 material 样式，而不是加回黑色实底。
- 窗口较矮时封面被限制为 320×320；如果用户想更大，需要重新平衡“顶部内边距 54 / 封面高度上限”这两个值，并同时验证独立窗口。
- compact 样式的独立播放器窗口顶部仍保留原有的 shuffle/repeat + ∞ 那一行（旧设计）；现在主传输行已经有随机/循环，若用户觉得重复可以清理，但属于单独改动。
- 中文词条仍在 `L10n.swift` 内；新 UI 文案记得同时加中文，并真机确认菜单项。

---

## 8. 交接时的检查清单

```bash
cd /Users/apple/Desktop/AI/Quder/amperfy
git status --short | wc -l          # 预期非 0，不要 reset
git branch --show-current           # feature/webdav-local
xcodebuild -project Amperfy.xcodeproj -scheme Amperfy -configuration Debug \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

- 构建成功后重启 App，按第 5 节走一遍播放器大/紧凑两种样式。
- 不要在未询问的情况下提交或推送。
