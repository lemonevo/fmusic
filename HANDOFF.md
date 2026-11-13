# fmusic fork 交接文档

最后更新：2026-11-13（Mac Catalyst / macOS 27 / Xcode 27.1；已更名 fmusic，CI 只出 arm64）
适用对象：接手继续改这个仓库的 AI。先读完第 0、1 节再动代码。

---

## 0. 先读：硬约束

1. 这是用户自用的 fmusic 项目，仓库 `origin` 为 `lemonevo/fmusic`（私有）。**推送/tag/发版前必须等用户明确同意**（用户要求先在本地改完 bug 再推）；`upstream` 指向原始项目，仅作参考，不要推送。
2. 工作区应当是干净的（2026-11-13 已提交全量改名）；不要 `git reset --hard`、不要 `git checkout --`。
3. 删除文件默认用 `trash <path>`（用户的 `rm` 就是 trash）；确需永久删除才用 `/bin/rm`。
4. 仓库不放二进制/大文件。
5. 密码、token、Cookie 不打印到聊天/文档/日志。
6. 视觉类改动必须在真实运行的 App 里渲染验证，不能只靠文字描述或编译通过。
7. 小改动不要跑全量测试；这个项目没有稳定的 UI 测试，主要靠真机操作 + 截图/视图层级核对。

---

## 1. 项目与环境

- 仓库：`/Users/apple/Desktop/AI/Quder/fmusic`
- 分支：`feature/webdav-local`，最后提交 `bdee704`（"Settings: fix dismiss ..."）
- 当前是**大面积未提交状态**：`git status --short` 215 条，`git diff --stat` 约 +2366 / -17462（删掉了 Subsonic/Ampache 相关代码）。
- 目标平台：Mac Catalyst（macOS 27）。Bundle ID：`lol.levo.fmusic`。
- 运行数据：`~/Library/Application Support/fmusic/fmusic.sqlite`（运行中有 `-wal/-shm`；直接读库前先拷贝一份，或只读打开）。
- 登录/库来源：登录页 `Auto-Detect` 可选 **Local Folder** 或 WebDAV。credentials 是 Codable，路径字段为 `localFolderPath` / `localFolderBookmark`（`fmusicKit/Api/LoginCredentials.swift`），不要靠改数据库切库，走登录页。
- 数据库里目前同时存在 `ZACCOUNT` 的两条记录（ZAPITYPE 4=local、5=webdav），以当前激活账号为准；重装/清库会丢用户资料。

### 构建与启动

```bash
cd /Users/apple/Desktop/AI/Quder/fmusic
xcodebuild -project fmusic.xcodeproj -scheme fmusic -configuration Debug \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

必须带 `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`，否则会因为缺 provisioning profile 失败。

启动（DerivedData 哈希可能变，先用下面命令定位）：

```bash
find ~/Library/Developer/Xcode/DerivedData -path '*Debug-maccatalyst/fmusic.app' -maxdepth 6 | head -1
open "<上一步输出>/Contents/MacOS/../../"   # 即 open <fmusic.app 路径>
# 重启：
pkill -f "fmusic.app/Contents/MacOS/fmusic"; sleep 2; open <fmusic.app 路径>
```

典型路径：`~/Library/Developer/Xcode/DerivedData/fmusic-eyetrzidtspoevgufmttlsihklja/Build/Products/Debug-maccatalyst/fmusic.app`

---

## 2. 产品形态与用户偏好（不要改回去）

- 保留 fmusic 原 UI，删掉 Subsonic/Ampache，只做本地 + WebDAV。
- 播放器 large 已改为 Apple Music 两栏：左侧封面 + 歌曲信息 + 底部传输键，右侧歌词列（始终显示、保留逐字高亮）；compact 仍是队列列表。large 时控制条收在左栏内、AirPlay/List/More 在歌词列右下角；compact 时控制条恢复全宽、工具组回到控制条。
- 呈现方式对齐 Apple Music：点击主窗口迷你条后，在主窗口内整页进入播放器（同窗全屏、`coverVertical` 从下往上滑入），不是 sheet，也不是新窗口。
- Apple Music 风格：侧栏 210pt、行 13pt、表头 11pt、行高 32pt、中性灰选中、4 列等比网格不裁切；设置独立窗口/sheet 也用同一套。
- 中文界面跟随系统语言（不要新增独立语言开关）。
- 歌词：YRC 优先（词级逐字填充），没有 YRC 时用 LRC；外挂歌词文件只认 `.yrc`/`.lrc`，不写进音频标签。
- 播放器/歌词相关历史结论：Apple Music 式逐字高亮、句首即切、点击歌词立即跳转并回正、弹簧滚动。

---

## 3. 架构地图（改之前先看这些）

### 3.1 库扫描与写入

| 文件 | 作用 | 关键入口 |
| --- | --- | --- |
| `fmusicKit/Api/Local/LocalLibraryIndexer.swift` | 本地文件夹扫描、标题/专辑/封面/歌词读取 | `syncInitial` L78，`read` L158，`relativePath` L251 |
| `fmusicKit/Api/WebDAV/WebDAVLibraryIndexer.swift` | WebDAV 扫描 | `syncInitial` L84，`enumerate` L242，`read` L305，`fetchLyrics` L398 |
| `fmusicKit/Api/FileSourceLibraryWriter.swift` | 把扫描结果写入 Core Data（新文件） | 以 `Writer` 为准 |
| `fmusicKit/Api/Local/LocalFolderAccess.swift` | 安全作用域书签激活 | `activate(bookmark:key:)` L76 |
| `fmusicKit/Api/LoginCredentials.swift` | local/webdav 凭据与本地路径 | L41 / L49 / L51 |

歌词候选文件名顺序见 `WebDAVLibraryIndexer.swift` L408：`.yrc` 优先于 `.lrc`（大小写都认）。

### 3.2 歌词解析与显示

| 文件 | 作用 | 关键入口 |
| --- | --- | --- |
| `fmusicKit/Api/LibrarySyncerDefaults.swift` | 歌词文件统一解析（新文件） | `parseLyrics` L75，`isYRC` L105，`YRCFileParser` L95，`LRCFileParser` L172 |
| `fmusicKit/Api/BackendApi.swift` | `LyricWord` L124，`LyricLine.words` L143 | 词级时间模型 |
| `fmusic/Screens/View/Lyrics/LyricsView.swift` | 歌词表格、自动滚动、按音节推进进度（30Hz 只更新遮罩） | 行间距 `lineSpacing=30` L44，点击跳转 L199，`updateActiveFill`、`refreshAllVisibleCells` |
| `fmusic/Screens/View/Lyrics/LyricTableCell.swift` | 行层 + 字形层；模型持有音节时间轴 | 当前行 29pt bold、非当前 24pt semibold，`lineSpacing=6`；`syllableProgress`、`applyProgress` |
| `fmusic/Screens/View/Lyrics/LyricsLineLayers.swift` | 三层次：`LyricsTimingMap`（时间轴→显示文本）、`LyricsTextLayout`/`LyricsGlyphView`（字形）、`LyricsSyllableMaskLayer`（音节遮罩） | `syllables(for:estimatedDuration:)`、`apply(progress:)` |

历史修复（不要回退）：
- 逐字填充不得回到“每 tick 重建 NSAttributedString”：现在是两个字形视图 + 每个音节一个渐变遮罩，时钟只改遮罩宽度；30Hz 限流在 `LyricsView.updateActiveFill`。
- 音节时间必须映射到**实际显示的字符串**（UTF-16 range）后交给 TextKit 布局取 rect，不要按字符比例拍脑袋；YRC 词文本与整行不一致时 `LyricsTimingMap` 会自动按长度比例分配。
- 换行时必须 `refreshAllVisibleCells`：只刷新旧行/新行会留下“上一行还是全亮”的残影（cell 可能当时不在可见区）。
- `LyricsSyllableMaskLayer` 必须实现 `init(layer:)`，否则 CALayer 隐式动画复制 presentation layer 时会 SIGTRAP 崩溃；mask 自身 frame 用 `setFrameWithoutAnimation`。
- 点击歌词时先清 `suppressAutoScrollUntil` 再立即滚动；否则音频已经跳到新行，列表还停在旧位置几秒（用户反馈的"错位"）。

### 3.3 播放器 UI（本次重设计重点）

| 文件 | 作用 | 关键入口 |
| --- | --- | --- |
| `fmusic/Screens/Player/PlayerControlView.swift` | 底部控制栏（XIB 视图） | `configureTransportControls` L102，`makeToggleButton` L134，`configureUtilityCluster` L146，`refreshTransportToggles` L179，`updateVolumeControlVisibility` L196，`displayPlaylistPressed` L327 |
| `fmusic/Screens/Player/PlayerUIHandler.swift` | 图标配置与按钮刷新 | `utilitySymbolConfiguration` L42，popup 的 List 按钮 config L268 |
| `fmusic/Screens/Player/PopupPlayerVC.swift` | 播放器容器（主窗口同窗全屏 / 独立窗口共用） | `setupVolumeControl` L184，`updateVolumeControlVisibility` L239 |
| `fmusic/Screens/Player/PlayerWindowVolumeControl.swift` | Catalyst 标题栏音量（NSToolbar 桥） | `attach` L88，`detach` L102 |
| `fmusic/Screens/Player/VolumeSlider.swift` | 自绘音量滑块（细轨 + 小圆钮，Apple Music 比例） | `draw`，`updateValue(at:)`，AX increment/decrement |
| `fmusic/Screens/Player/PopupPlayer+Animations.swift` | compact/large 切换 | `changeDisplayStyleVisually` L36（开头先更新音量控件可见性） |
| `fmusic/Screens/Player/MiniPlayerView.swift` | 主窗口底部迷你条 | `configureForMac` L589，tap 打开播放器 L599，`miniPlayerGotTouched` L721，`openPlayerView` L725 |
| `fmusic/Screens/Player/PlayerControlView.xib` | 控制栏 XIB | 传输键 stack id `SoI-ny-Hw0`（L53） |
| `fmusic/Screens/Player/PopupPlayerVC.xib` | 播放器容器 XIB | 大播放器顶部约束 `18e-Ia-XA9`，constant=54（L56） |
| `fmusic/Screens/Player/LargeCurrentlyPlayingPlayerView.xib` | 大封面/详情 | 封面高度上限约束 `z4T-8m-Q1a`（L42） |

### 3.4 中文化

- `fmusicKit/Common/L10n.swift`：`enum L10n` L23，`tr` L27，中文词条在同文件表里。界面字符串统一走 `L10n.tr(...)`，不要新增 `.strings` 语言开关（跟随系统）。
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
- sheet 关闭（2026-11-11 补，现已改为同窗全屏）：播放器现在是主窗口内的 `.fullScreen` modal（`coverVertical` 从下往上滑入，见 `MiniPlayerView.openPlayerView`），不再有 sheet 把手；ESC（`AppDelegateKeyboardCommands.swift` L336 附近）和左上角半透明 `chevron.down` 关闭按钮（`PopupPlayerVC.swift` `setupCloseButton` L243）都返回资料库。独立 Mini Player 窗口不显示关闭按钮。
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
- fmusic 侧：去掉 seek 门控（门控要求 `|elapsed - target| <= 1`，在真实落点偏离时反而会冻结 UI 6 秒）；`BackendAudioPlayer.seek` 后立即 `notifyCurrentTime()`；进度条 elapsed 定时器 1s → 0.2s，避免点歌词后进度条比歌词晚最多 1 秒。
- **暂停态 seek（2026-11-12 修）**：暂停时 `seek` 只登记 `seekRequest`，但 `processSource()` 开头的 `guard internalState != .paused` 直接 return，`resume()` 也不处理它 → 恢复后要么卡在请求位置（`progress` 一直返回 `seekRequest.time`），要么旧 entry 读完后触发 fmusic 的 `Replay` 从头播。修在 `Vendor/AudioStreaming/AudioStreaming/Streaming/AudioPlayer/AudioPlayer.swift` 的 `resume()`：先读 `audioPlayingEntry.seekRequest.requested`，有挂起 seek 时先不 `startPlayer`，引擎/source 恢复后在 `sourceQueue` 上跑一次 `processSource()`（reading===playing → 原地 `processSeek`；reading 已因 EOF 关闭 → `setCurrentReading` 重建后由首包触发 `processSeek`），再用新增的 `isPlayerHardwareRunning` 判断是否需要 `startPlayer(resetBuffers: false)`，避免重复 start。`PATCHES.md` 已记录，升级依赖要重打。
- 验证方法：点歌词时用 lldb 在 `LyricsView.tableView(_:didSelectRowAt:)` 打印 `indexPath.row` 与 `lyric.start`，确认行→时间映射正确（本例第 13 行=62970ms，进度条应显示 1:02）。也可以在 `LyricsView.scroll(toTime:)` 断点直接 dump `self.lyricModels` 全表时间；清明雨上尾部 `21:179280 22:185700 23:192780`。注意鼠标停留会高亮悬停行，别把它误认成当前行；AX 状态与截图抓取有先后，比较时以“截图里的进度条秒数 + 高亮行”为准。
- 排版：当前行 29pt bold / 非当前 24pt semibold，行间距 30，段内行距 6；非当前行仍做高斯模糊（CI 快照）。
- 已验证：真机播放（风度/好安静/不分手的恋爱）、行内半亮边界、跨行换行、点击歌词跳转；无崩溃日志，播放 CPU 约 10–13%。2026-11-12 FLAC seek 修复后复测：播放中点进度条 → 1:42 高亮“把你最爱的歌”（86.84s）、3:06 高亮“又是清明雨上”（185.70s，落点 186.6）、连续 4 次快速跳转 → 2:28 高亮“我在人间彷徨”（146.05s）、跳到 3:29 后歌曲在 3:39 正常结束（修复前会拖到 3:44）；每次 seek 的校正日志为 `FLAC seek correction: requested=… landed=…`。暂停态 seek 修复后复测（缓存 FLAC）：暂停停 0:05 → 拖到 1:31 → 播放后 1:36 继续、高亮行正确；倒着拖 0:20 → 0:27；连拖 2:30→3:00 → 3:03；暂停时点歌词 2:52 → 播放后 2:56；播放中拖 0:30 → 0:36 无回归；`log stream` 里只有 FLAC 校正（91.393→91.626、179.915→179.862），没有 `Replay`。

### 4.3 中文化（此前完成）

- 播放器选项菜单、睡眠定时器、播放器信息页等已全部中文；CUA 验证过菜单树无英文残留。

### 4.4 冗余清理与性能（2026-11-12）

基线提交 `dbba5a5`（重构前快照），下面的改动未提交。

- **删掉的死文件**：`fmusic/Screens/View/AlbumDetailHeaderView.swift`（不在 pbxproj 里的旧版重复实现）、`Screens/Basics/SpinnerViewController.swift`、`Screens/Basics/AnimatedGradientLayer.swift`（全仓库零引用），同步删 pbxproj 条目。
- **删掉的死方法（44 个，编译验证过）**：`LibraryStorage` 的 musicFolder/podcast/radio/directory/scrobble/embeddedArtwork 旧同步辅助（12 个）及 `PrefetchIdContainer`/`PrefetchElementContainer`；`Album.markAs*`、`Artwork.markErrorIfNeeded`、`StringHasher.md5*`、`AudioPlayer.notifyArtworkChanged/removeAllNotifier`、`LocalNotificationManager.notifyDebug*`、`UIImageAssetsExtension.styleForNavigationBar/symbolImageSize`、`PersistentStorage.getPermanentObjectIDs`、`Identifyable.filterBy`、`Utilities` 的 `allIndices/averageColor/deletingPrefix/isContainedIn/setGradientBackground`、`Playlist.filter*Playlists`、`CacheFileManager.getCachedEpisodes`、`Account.assignAccount`、`AppDelegate.restartByUser`、`LibraryUpdater.cancleLibraryUpdate`、`SelectionAccessory.createEdit/createDone`、`BasicFetchedResultsController.hideResults`、`UtilitiesExtensions.isForceClicked`、`MigrationPolicyV4toV5.stringId`。
- **删除播客/电台/转码功能入口（2026-11-12，按要求“暂时用不到”）**：
  - 删文件：`RadiosVC`、`PodcastsVC`、`PodcastDetailVC`、`PodcastEpisodeTableCell`（含 xib）、`LocalNotificationManager`（只服务播客新集通知）、`BackgroundFetchTriggeredSyncer`（后台任务只同步播客），pbxproj 同步清理。
  - UI：首页 section（`HomeSection.supportedCases` 过滤 podcasts/radios/newestPodcastEpisodes，`homeSections`/`homeSectionOrder` getter 也过滤，旧设置里的残留项不会冒出来）、资料库类型（`LibraryDisplayType` 删 `.podcasts`/`.radios`）、轻扫动作（`SwipeActionType.isSupported=false`，保留 raw 值 9/10 以便旧设置解码）、CarPlay 列表与快捷入口、Siri/App Intents（`PlayableContainerTypeAppEnum` 只留 artist/song/playlist/album/genre）、主菜单/键盘的 Music↔Podcast 切换、资料库设置里的播客计数、播客自动缓存设置与后台抓取。
  - 播放器：去掉电台元数据/直播态、电台站点跳转、播客单集续播与“Show Podcast”跳转；暂停态 seek 复测正常。
  - **保留数据层**：Core Data 实体（`PodcastMO`/`PodcastEpisodeMO`/`RadioMO`）、`PlayerMO` 的 podcast 队列、`PlayerMode.podcast`、`HomeSection` 的 raw value、`LibraryDisplayType` 的 rawValue 槽位（6/14）——避免迁移风险，旧库和旧设置可直接打开；清单/搜索里不会再出现这些实体。
  - 转码设置（格式/码率、`TranscodingInfo`、`StreamingMaxBitrates` 等）此前已删；本次清掉剩余 6 条 L10n 转码文案和相关设置键。
- **设置解码缓存**（`fmusicKit/Storage/Settings.swift`）：`app/user/accounts` 原来每次 get 都从 UserDefaults 做 JSON 解码（`AccountSettings` 里还要 SHA-256 密码），而列表每个 cell、播放每 tick 都在读。现在用 `SettingsDecodeCache` 按**原始 Data** 缓存解码结果，set 时同步写缓存。**不要改成实例内存储属性缓存**：`DownloadManager`/`BackendProxy` 持有 `fmusicSettings` 的值拷贝，会看不到后续修改；按 Data 比对的静态缓存才保持原语义。
- **Now Playing 推送**（`fmusicKit/Player/NowPlayingInfoCenterHandler.swift`）：`didElapsedTimeChange` 原来每 0.2s 重建整份 `nowPlayingInfo`（读设置、取封面、请求封面下载、重建 `MPMediaItemArtwork`），MediaRemote 每次都重新编码 JPEG。现在 tick 只更新 `ElapsedPlaybackTime`/`PlaybackRate` 两个键且 ≥1s 才推；换歌/暂停/封面变化仍走完整更新，`didPlaybackRateChange` 也会立即推一次。
- **播放器 tick 去抖**（`fmusic/Screens/Player/PlayerUIHandler.swift`）：时间标签只在文本变化时赋值、进度条值变化 >0.01 才写、电台渐变 mask 只创建一次；`preferredBehavioralStyle` 也不再每 tick 设置。
- **侧栏账户块**（`fmusic/Screens/ViewController/SideBarVC.swift`）：左下角头像+用户名整体固定 128×28，头像 28×28、圆角 14、字号 13，间距 8，footer 高度 48。
- **设置窗口与侧栏统一**（`fmusic/SwiftUI/Basics/Settings*.swift`、`SettingsTabView.swift`、`NavigationTarget.swift`）：行文字 13 pt、行高 32、段头 11 pt semibold 次级色/大写、说明 11 pt；内容区去掉分组灰底和分隔线，与侧栏一样平铺；设置侧栏图标改用 outline SF Symbol（gearshape/person/play.circle 等），与主侧栏图标风格一致。
- **登录界面重设计**（`fmusic/Screens/ViewController/LoginVC.swift`，2026-11-12）：去掉整块反射壁纸的 Liquid Glass 大卡片和 50 pt 巨型字，改为经典居中式登录：44 pt 应用图标 + 28 pt 半粗主题色「fmusic」+ 13 pt 副标题「登录以连接你的音乐库」；下方 360 pt 宽分组卡片（圆角 14、`secondarySystemBackground`、1 px 分隔线、轻阴影），行高 44，内含 API 选择行（右侧值 + 上下箭头）、URL/用户名/密码三行（16 pt 三级色图标 + 13 pt 输入）和「自定义 HTTP 头」行；卡片下方通栏 40 pt 主题红填充按钮；关闭按钮改为右上角 28 pt 中性圆形 X。本地模式隐藏用户名/密码/HTTP 头并去掉多余分隔线。新增 L10n 键 `API`/`Source`/`Sign in to your music library`。注意：带 `UIButton.Configuration` 的 API 按钮更新标题要用 `setTitle(_:for:)`，直接改 `configuration.title` 再赋值不会刷新显示。
- **全局风格统一与转场动效**（2026-11-12）：
  - **字号/间距**：内容区表格与网格的 mac 字号统一到侧栏/设置的紧凑口径——`GenericTableCell` 13/11 pt（标题/副标题+信息）、`PlayableTableCell` 13/11 pt（标题/艺人+时长）、`AlbumCollectionCell` 13/11 pt；首页与表格内容水平边距统一为 20 pt（`HomeVC.sectionHorizontalInset`、`UIView.defaultMarginCellX`）。大标题、详情页头图等仍保留更大字号维持层级。
  - **鼠标悬停反馈**：`KeyboardFocusableListCell`（主侧栏行）和 `GenericTableCell`（艺人/专辑/播放列表等列表行）加入 `UIHoverGestureRecognizer` + 0.12 s 淡入的中性灰高亮；侧栏 section 标题行通过 `isHoverHighlightEnabled = false` 不响应悬停。设置窗口侧栏行用 SwiftUI `.onHover` 做同样效果。
  - **切换侧栏分类**：`SplitVC.replaceSecondary(vc:)` 替换原来的 `setViewController` 硬切。先给旧 secondary 视图做快照盖在上面，换新控制器后旧页 0.1 s 淡出、新页 0.14 s 淡入（fade-through）。**不要改回同时交叉淡入淡出**：两个密集网格叠在一起会像双曝光，已实测难看。快照插在迷你播放器下方，避免遮住底栏。
  - **进入详情**：`SplitVC.push(vc:)` 在导航栈已上屏时改为 `animated: true`（弹窗播放器关闭后跳转、从预览卡片跳转），栈未上屏时仍立即 push。
  - **根视图切换**：`SceneDelegate.replaceMainRootViewController` 对已有根视图用 0.28 s 窗口 cross-dissolve（登录→同步→主界面、切换账户）；首次启动仍直接赋值。
  - **设置窗口**：`SettingsTabView` 详情页按 `.id(selectedMenu)` + 0.18 s 动画淡入淡出；侧栏选中/悬停底色有 0.14 s 过渡。
  - 验证：首页/专辑/歌曲列表截图确认字号与 20 pt 边距一致；窗口级录屏抽帧确认切换为“旧页淡出→新页淡入”，无双曝光；设置页与登录页布局未回归。录屏请用 `screencapture -l <windowID>` 只录 fmusic 窗口，避免录到其他 App。
- **中英文补漏与系统 UI 中文化**（2026-11-12）：
  - 根因一：`UIContentUnavailableConfiguration.search()` 走的是系统本地化，而 App 只有 `Base.lproj`，所以空搜索状态一直是英文。已新增 `UIContentUnavailableConfiguration.localizedSearch()`（`CommonScreenOperations.swift`），用 L10n 构造“没有结果 / 请检查拼写或尝试新的搜索。”并替换全部 9 处调用。
  - 根因二：`UIButton.Configuration` 直接改 `configuration.title` 后赋值不会刷新按钮显示（登录页 API 按钮也踩过）。`LibraryElementDetailTableHeaderView` 的播放/随机按钮因此一直显示 nib 里的“Play/Shuffle”，现在赋值后再 `setTitle(_:for:)` 一次。
  - 硬编码英文统计：专辑/流派/文件夹/播放列表/专辑详情的 `infoCB` 改为 `L10n.tr("%d Album(s)/%d Songs/%d Artist(s)")`；新增 `%d Artist(s)`、`%d Playlist(s)` 中文条目。
  - 其余补漏：目录页标题与空状态、下载队列“Many Songs”弹窗、播放列表选择/添加弹窗、macOS 菜单栏（打开/关闭播放器窗口、切换资料库/迷你播放器、播放速度、循环、快进/快退等）、CarPlay 列表标题、设置里的自定义 HTTP 头/服务器地址/备用地址/更新密码/App 图标名称、登录失败提示、Instant Mix 事件弹窗、删除缓存确认、音量工具栏标签。
  - **新增 `fmusic/zh-Hans.lproj/Localizable.strings` 并加入 pbxproj（knownRegions + Resources）**：App 之前只有 Base.lproj，导致系统提供的 UI（菜单栏“File/Edit/View”、搜索空状态、系统按钮 tooltip）全是英文。加入 zh-Hans 后系统 UI 会自动跟随中文；该文件目前只放系统用到的 `Favorite`/`Queue`，App 自身文案仍走 `L10n`。
  - 注意：`L10n.chinese` 是字典字面量，**重复 key 会在启动时触发 `Dictionary.init(dictionaryLiteral:)` 断言崩溃**；新增译文前务必查重（本次就因 “Are you sure to delete the cached file?” 重复崩溃过一次，已移除）。
  - 验证：重启后菜单栏显示 文件/编辑/显示/控制/窗口/帮助；专辑页显示“4 张专辑 / 播放 / 随机播放”；歌曲页“6 首歌曲 / 播放 / 随机播放”；搜索 `zzzzzz` 显示“没有结果 / 请检查拼写或尝试新的搜索。”；无新崩溃。
- **第二轮硬编码英文清点**（2026-11-12，接上一轮）：
  - 枚举 `description` 直接进 UI 的两处：`RepeatMode`（`AppDelegateMainMenuExtension` 的循环菜单，补 `Single`=单曲）与 `PlayerQueueType.user.description`（用户队列头），都改为 `L10n.tr(...)`。
  - xib 默认值残留：`ContextQueueNextSectionHeader` 的 `queueNameLabel` 从不赋值，一直在显示 nib 的 “Next from:”，现在在 `refresh()` 里赋值（“接下来播放：”）；CarPlay 队列头 `Next from: %@` 同步。
  - 未知元数据占位符：索引器仍把 “Unknown Artist/Album/Genre/Title” **原样写入数据库**（保持语言中性），改在展示侧用 `L10n.trPlaceholder(...)` 翻译（`Artist/Album/Genre/AbstractPlayable/Song` 的 getter）；否则老库里已存的英文占位符永远不会变。
  - 其余补漏：搜索占位符“在“X”中搜索”（播放列表添加系列 VC）、按星级分组的 “N Star(s)/Not rated”、播放列表添加标题、扫/播放/暂停/搜索等快捷键名、WebDAV/本地文件夹/登录/API 错误描述、下载中/下载失败/无效下载、App 图标提示、文字大小档位名与脚注、事件日志类型与“状态码”、缓存上限“无限制”、X-Callback/Instant Mix 错误、混播上下文名、会话提醒与睡眠定时器事件。
  - 未处理（属系统共享界面，不在 App 窗口内）：App Intents / Shortcuts 的参数标题仍是英文；事件日志里历史条目的 topic 与系统 `URLSession` 错误文本仍是英文（数据已落库）。
  - 验证：构建通过并重启；首页随机专辑显示“未知专辑/未知艺人”；设置各页（通用/显示/账户/资料库/播放与串流/轻扫/封面/支持）AX 树无英文；文字大小脚注为“默认：列表和专辑网格中的文字大小。”；事件日志类型显示“错误”。
- **账户弹窗改自绘 + 单账户移除**（2026-11-12，`SideBarVC.swift`）：左下角账户按钮不再用 `UIMenu`，改为加在 window 上的自绘浮层（宽 194 对齐 210 pt 侧栏、底色 `secondarySystemBackground`、圆角 12、1px 分隔 + 轻阴影，位置贴在账户按钮上方左侧）：每个账户一行（勾选 + 用户名 13 pt + 服务器地址 11 pt），行右侧一个 `minus.circle` 移除按钮；点击弹“移除账户”二次确认，确认后调 `AppDelegate.removeAccount(accountInfo:)`（从设置页“退出登录”抽出的同一套逻辑，任何账户都能直接移除，不必先切换）。底部仍是“添加账户 / 设置”；点浮层外或按 ESC 关闭（ESC 走 `AppDelegate.accountSwitcherDismissHandler` + 动态 keyCommand）。注意：Catalyst 的 `UIPopoverPresentationController` 箭头会渲染成黑色三角，别用 popover；浮层要加在 window 上才能盖住迷你播放器。首版曾用 280 pt 纯白面板，用户指出“颜色太白了 还有太宽了”，现已按侧栏宽度和次级灰重做；新控件请先对齐现有 token。
- **修复移除账户时的崩溃**：`player.logout` → `AudioPlayer.stop` → `PlayerControlView.didStopPlaying` 会把已释放的 weak IBOutlet（`skipBackwardButton`，崩溃行 `PlayerControlView.swift:599`）传给非可选参数，触发 `EXC_BREAKPOINT`（2026-11-12 12:54 用户退出 Local 账户即崩）。现在 `refreshPlayer()`、`didStopPlaying()`、`didElapsedTimeChange()` 先判空 weak outlet 再刷新；账户删除流程可完整走完。
- **播放器改为 Apple Music 深色风格**（2026-11-12）：`PopupPlayerVC` 设 `overrideUserInterfaceStyle = .dark`，再在模糊封面图上叠黑色 scrim（`black` alpha 0.15），于是歌词、控制键、收藏/更多、时间标签都按 `.label` 自动变白：未唱行白 60%、当前行未唱部分白 55%、已唱部分纯白。音量胶囊改成近透明（白 12% 填充 + 1px 白 22% 描边），`VolumeSlider.contentColor` 设白，轨道白 30%、填充/胶囊钮纯白；标题栏和播放器内两处音量控件同步。独立歌词页（`LyricsVC`）当时保持浅色黑字不变（2026-11-12 晚已改为深色，见 4.4 最后一条）。
- **实测**：同一首 FLAC 缓存播放，CPU 从 ~10–13% 降到 ~7–8%（`top` 瞬时；`ps` 进程均值 4.8%）；`sample` 里 `AppleJPEG` 编码帧 134 → 2；MediaRemote `setNowPlayingInfo` 5 次/秒 → 1 次/秒；tick 调用链里不再出现 `fmusicSettings.accounts` 解码。
- 验证：重启后设置窗口（主题红色、WebDAV 账户/URL）、首页网格、大播放器歌词、播放中 seek、暂停态 seek 全部正常；改设置开关后 `defaults read ... settings.account` 变化，重启仍生效。
- 播客/电台删除后复测（2026-11-12）：侧栏只剩 艺人/专辑/最新专辑/最近播放/歌曲/喜爱歌曲/播放列表，首页编辑器同样无播客/电台项；资料库设置无播客计数；播放中暂停 → 点进度条到 2:49 → 播放继续在 2:50 且歌词跟随；无新 `.ips`。注意 CUA 的 `drag` 在 UISlider 上可能只改 AX 值不发 `valueChanged`，验证 seek 要用坐标点击（点击会发 `valueChanged`）。
- **WebDAV/本地根目录无标签文件不再拿根文件夹名当专辑**（2026-11-12）：用户库根目录直接放了一批没有 album tag 的 flac，旧逻辑 `directoryPath.isEmpty ? rootURL.lastPathComponent : 目录名` 生成了一个叫“猫曦汐喜欢的音乐”的专辑（ID = `stableID("webdav_album_", "path:")`），看起来像文件夹混进“最新专辑”。现在根目录无标签统一用 `"Unknown Album"`（展示侧经 `L10n.trPlaceholder` 显示“未知专辑”），子文件夹仍按文件夹名当专辑；`FileSourceLibraryWriter` 对已存在的专辑同步名称；WebDAV 同步末尾把老库里那个根目录专辑（ID 固定）改名，无需全量重读。验证：重新同步后 DB 中该专辑 `ZNAME = Unknown Album`，首页显示“未知专辑”。另注意这批无标签文件的曲名/艺人是从文件名按“艺人 - 曲名”猜的，用户文件是“曲名 - 艺人”，所以标题会反（未改，属另一个问题）。
- **设置改为窗口内整页覆盖（不再开独立窗口）**（2026-11-12，按用户要求对齐 Qoder 的设置形态）：`AppDelegate.showSettings` 不再 `requestSceneSessionActivation` 独立 Scene，而是从 `AppDelegate.topViewController()` 以 `.fullScreen` + `.crossDissolve` 呈现 `SettingsHostVC(showsSidebar: true)`，设置侧栏第一行是“返回应用”（`SettingsTabView.onBackToApp`，13 pt、行高 32、悬停反馈与其它行一致），点它或按 ESC 关闭（`SettingsHostVC.keyCommands`），关掉后窗口标题自动回到“首页”。`SettingsHostVC` 的 `isForOwnWindow` 参数改名 `showsSidebar`。设置侧栏行已按首页侧栏对齐：SF Symbol 实心图标（`NavigationTarget.systemImage` 用 `.fill` 变体，16 pt regular、22×22 盒；`tv.fill` 用于“显示与交互”）、行高 38 pt（32 pt 高亮 + 上下 3 pt 间隙）、文字 13 pt、强调色取 `Color.accentColor`，返回行下面不再画分隔线。旧的 `SettingsSceneDelegate` 保留但只做一件事：把老版本残留的设置 Scene session 自毁（`requestSceneSessionDestruction`），避免升级后启动时又弹出一个空设置窗口；`AppDelegate.settingsSceneSession` 已删除。`SceneDelegate.replaceMainRootViewController` 换根前会先 dismiss 已呈现的 modal，防止在设置里退出登录后 modal 悬挂。之前为独立窗口做的 alpha/scale 入场动画随之移除（窗口内 cross-dissolve 已经够顺）。
- **播放器按钮/码率标签跟 Apple Music 对齐**（2026-11-12，按用户截图反馈）：`PlayerControlView` 五个传输键统一到 `Self.iconTintColor = label 85%`（不再纯白）；尺寸 随机/循环 19 pt bold、上一首/下一首 21 pt、播放/暂停 27 pt（原来 17/22/30，播放和 outline 键比例失衡）；右下工具组同样用 85% 白。**随机/循环的图标颜色必须烘焙进图片**（`UIImage(systemName:withConfiguration:)?.withTintColor(tint, renderingMode: .alwaysOriginal)`）：这两个按钮是代码 new 出来的，`tintColor` 怎么设都只渲染出 ~62% 亮度的灰（实测峰值 158，纯白 tint 也一样），烘焙后五键峰值统一 223；开关打开时用主题色 `themePreference.asColor`（红），不再用 Catalyst 默认蓝色的 `UIColor.tintColor`。循环图标按模式直接取 `repeat`/`repeat.1`。`PlayerUIHandler.refreshTimeInfo` 不再显示 `audioInfoLabel`/`playTypeIcon`（FLAC 888 kbps 那行），`refreshAudioInfo` 已删除；迷你条和大播放器都受影响。
- **AirPlay 键改为输出设备菜单**（2026-11-12，按用户要求“像 macOS 声音菜单，但别太宽”）：新增 `fmusic/Screens/Player/AudioOutputPicker.swift`（已进 pbxproj，fileRef `5047B7A0…`）。`AudioOutputRouting` 用 CoreAudio 枚举 `kAudioHardwarePropertyDevices`，只留有输出声道的设备，按 `kAudioDevicePropertyTransportType` 映射图标（builtIn→laptopcomputer、bluetooth→airpodspro、usb→hifispeaker、display→display、virtual→waveform、other→speaker.wave.2）；**过滤掉名字以 `CADefaultDeviceAggregate` 开头的私有聚合设备**，否则 Catalyst 自己的聚合设备会以 `CADefaultDe...-<pid>-0` 出现在菜单里。点击行调 `AudioObjectSetPropertyData(kAudioHardwarePropertyDefaultOutputDevice)` 切系统默认输出，然后收起。面板为 window 级自绘浮层（宽 230、行高 38、**背景和迷你条同一套 `UIGlassEffect(style: .regular)`**（`isInteractive = false`，玻璃视图圆角 12 + clipsToBounds，阴影在外层 panel）、13 pt 名称、当前设备行尾 `checkmark` 12 semibold、悬停 6% 灰），贴在按钮上方、空间不足翻到下方，x 右对齐并夹紧窗口；点外部关闭，ESC 走 `AppDelegate.audioOutputPickerDismissHandler`（与账户浮层共用 `dismissActiveOverlayFromKeyboard`）。**每行必须显式 `heightAnchor == rowHeight`**：`.fill` 分布的 UIStackView 会把多出来的高度全给第一行（曾出现 AirPods 那行高出一倍）。`PopupPlayerVC.viewWillDisappear` 里调 `AudioOutputPicker.dismiss()`，否则关闭大播放器后浮层会留在窗口中间（ESC 关闭播放器时 UIKit 自动 dismiss 不走我们的 keyCommand）。iOS 分支仍走 `MPVolumeView`。行设置 `isAccessibilityElement`/`.button`/`.selected`，鼠标以外也可用。注意：真机验证时默认输出会被环境里别的东西抢回（本机 AirPods Pro 自动接管 / BlackHole），我们的 setter 本身是生效的（关掉 App 后 `swift /tmp/setout.swift` 设了也会被抢），别误判成 bug。
- **夜间模式（外观）已内建并补两处传播缺口**（2026-11-12，用户要求“和 Apple Music 原生一样好”）：App 本来就有 设置 → 显示与交互 → 外观（系统/浅色/深色），值存在 `settings.user` 的 `_appearanceMode`（0=系统 / 1=浅色 / 2=深色），经 `AppDelegate.setAppAppearanceMode` 写 `window.overrideUserInterfaceStyle`，选“系统”时随 macOS 实时切换；所有页面用的是语义色（`systemBackground`/`secondarySystemBackground`/`label` 等），深色下内容区 #1E1E1E、侧栏 #262524。本次只修了两个缺口：`MiniPlayerSceneDelegate` 新建的弹窗/迷你窗口原先跟随系统而不是 App 内选择，现在创建后立刻 `overrideUserInterfaceStyle = settings.user.appearanceMode`；`SceneDelegate` 先把存储的外观应用到窗口再 `makeKeyAndVisible()`，避免系统浅色 + App 强制深色时首帧闪白。**大播放器仍固定 `.dark`**（见上一条 Apple Music 风格），这是有意为之，不受外观设置影响；独立 `LyricsVC` 也仍是浅色（2026-11-12 晚已改为深色）。已知小瑕疵：Catalyst 侧栏/列表的分段索引字母仍用主题红（`tableView.sectionIndexColor` 无效果，已回退，不保留死代码；2026-11-12 晚已通过私有索引子视图 tintColor 修复）。验证：系统浅色/深色与 App 内三项交叉切换，首页网格、专辑/歌曲列表、专辑详情、搜索、各设置页、账户浮层、AirPlay 面板均正确换色；强制深色（`_appearanceMode=2`、系统浅色）重启也无白闪。
- **设置侧栏精简 + 语言切换**（2026-11-12，按用户要求“项目太多、命名有歧义”）：侧栏从 12 项压到 6 项——通用 / 账户 / 播放 / 显示 / 资料库 / 支持与关于；其余都改为父页里的二级入口：均衡器进「播放」，轻扫操作进「显示」，封面与缓存进「资料库」，第三方许可 / X-Callback URL / 开发者工具（DEBUG）进「支持与关于」，版本号也移到「支持与关于」的「关于」段。`NavigationTarget.sidebarItems` 控制侧栏顺序（`SettingsTabView` 不再遍历 `allCases`），二级页仍走各父页自己的 `NavigationLink(value:) + navigationDestination`，没选中的是值类型 enum，切换侧栏时 `detailPath` 会清空。命名改动：显示与交互→显示、播放与串流→播放、轻扫→轻扫操作、封面→封面与缓存、支持/许可→支持与关于/第三方许可、X-Callback 文档→X-Callback URL；对应 `NavigationTarget.displayName`、各页 `navigationTitle` 和 `L10n` 均已同步。
  - **语言切换**放在「通用」第一行（跟随系统 / 简体中文 / English），存 `settings.user._appLanguage` 的 `AppLanguage`（system/english/simplifiedChinese）；改动时由 `AppDelegate.applyAppLanguage` 往 App 自己的 `UserDefaults` 写 `AppleLanguages`（中文写 `zh-Hans`，跟随系统则删除该键），并弹窗提示重启。`L10n.isChinese` 仍按启动时的 `Locale.preferredLanguages` 取值，所以 UI 文案、系统菜单、`zh-Hans.lproj` 一起在下次启动生效；不要在运行期直接切 L10n，避免只换一半界面。验证：切到 English 重启后整窗（含菜单栏、设置页、Home/Library）为英文，切回跟随系统重启恢复中文；`defaults read ... AppleLanguages` 在跟随系统时不存在。
- **全面清理与优化（2026-11-12，用户要求“浏览整个项目、完善遗留瑕疵、删冗余、减内存/存储、精简逻辑”）**：
  - 死代码/资源：删 `Screens/Basics/Corners.swift`（零引用）、未注册到 `AppShortcutsProvider` 的 `OpenAppWithConfigurationIntent` / `SeekToPlaybackTimeIntent` 及两个专属 AppEnum、`JSONConverter` 空枚举体（保留 `Encodable.asJSONData/asJSONString`）、`Settings.availableApiTypes`、`DuplicateEntitiesResolver` 的 Ampache/Subsonic 专属去重分支、`SongsVC`/`PlaylistsVC`/`PlaylistAdd*`/`Genre`/`PlayerSettingsView`/`IntentManager` 里的恒真/恒假 `asServerApiType` 分支；删 `fmusicIntents.xcscheme`（对应 target 早已不存在）、pbxproj 两个空 phase（`Embed Foundation Extensions`/`CopyFiles`）、`Design/*.xcf`（6.5 MB 未引用）、`Helper/` 未编译脚本。`DebugCoreData.xcscheme` 里悬空的 fmusicIntents 条目同步删除。**CarPlay 7 个文件保留**（Catalyst 不触发，但保留 iOS CarPlay 能力；要砍需用户确认）。
  - 内存：`LibraryEntityImage` 的静态 `NSCache` 原来无上限且按原始分辨率解码（封面最大 2400px，37 张解码约 224 MB）。现在 `countLimit=300` + `totalCostLimit=64 MB`，并用 ImageIO `CGImageSourceCreateThumbnailAtIndex` 把加载上限压到 1024 px（封面视觉无差别），cost 按解码字节计；`deinit` 注销通知。`SettingsHostVC` 的 29 个 Combine sink 全部改 `[weak self] + guard let self`——原来 closure 强持有 VC，每次打开设置都泄漏一整套 `UIHostingController` + SwiftUI 树（实测 6 次开关仅 +13 MB）。`PersistentStorage.configureContext` 去掉 `retainsRegisteredObjects = true`，对象不再被 context 永久钉住（entity wrapper 自己强持有 MO，安全）。`CacheFileManager.init` 的整库缓存目录扫描移到 `.utility` detached task，不再阻塞启动主线程。`ScrobbleSyncer.stop()` 补 `scrobbleTimer?.invalidate()`。
  - 存储/资源：`Assets.xcassets/Icon-monocolor.imageset` 两张 1024² logo 源图各 4.0 MB，实际是白/黑单色+alpha，用 Pillow 无损转 `LA` PNG 后 37 KB / 6 KB（像素级一致，仓库省 8.2 MB；actool 编译后的 Assets.car 本来就会压，所以 App 体积变化很小）。播放缓存（`~/Library/lol.levo.fmusic/accounts/.../songs`，实测 1.69 GB）没有动：`cacheLimit=0` 表示无限、淘汰旧文件属破坏性行为，按 HANDOFF 约定不清用户缓存；设置里的“删除已下载歌曲”仍是手动入口。
  - 遗留瑕疵：分段索引字母改为中性灰——Catalyst 的 `sectionIndexColor` 无效，索引是 UITableView 私有子视图、吃 `tintColor`，现在 `BasicTableViewController.viewDidLayoutSubviews` 里给类名含 `Index` 的子视图设 `.secondaryLabel`（不影响表格其他 tint）。独立 `LyricsVC` 设 `overrideUserInterfaceStyle = .dark` + `systemBackground`，与大播放器一致（SplitVC 右侧歌词栏实测深色）。大播放器/迷你条的随机、循环按钮补 `accessibilityLabel`（L10n「随机播放」「循环」），AX 不再读成 “go forward”。
  - 验证：每批 `xcodebuild` 通过；重启后真机截图确认首页/歌曲列表、索引字母灰色、歌词栏深色、大播放器封面清晰、播放/暂停/进度正常、设置开关 6 次无异常；`git diff` 约 -667/+131 行。
  - 后续小修（2026-11-12）：大播放器工具组与迷你条的「更多」统一为 `ellipsis.circle`（`PlayerControlView` + `MiniPlayerView.moreButton` 两处；原来迷你条仍是裸 `ellipsis`，用户指出“图标太轻、两边不一致”）。心形旁的「···」是歌曲操作菜单，不是播放器选项，保持裸 `ellipsis`。
- **WebDAV 曲库自动增量扫描**（2026-11-12，用户要求“先加 webdav 的增量扫描”）：`WebDAVLibraryIndexer.syncInitial` 本来就是增量索引（按文件 size + lastModified 跳过未变项，`libraryIndexVersion` 决定是否全量重读），缺的是自动触发。现在**主场景 `SceneDelegate.sceneDidBecomeActive`**（Catalyst 实际走 scene 生命周期，`AppDelegate.applicationDidBecomeActive` 不触发，已实测）和 `switchAccount` 时调用 `AppDelegate.triggerWebDAVIncrementalScanIfNeeded()`：仅当资料库已初始化、非离线模式、活动账户是 WebDAV、初始同步未 abort 时执行；15 秒去抖，自动扫描不弹 SyncVC 进度 UI，成功后 post `.librarySongsSynced`。`syncInitial` 加了单飞保护（`activeIndexTask`），自动扫描与手动“重新同步资料库”不会并发重复写库；自动扫描失败只写 os_log，不弹窗。验证：启动日志 `WebDAV index: 53 unchanged, 0 to read (incremental: 1, existing: 53)` → `finished: 0 songs in 0.1s`；切回前台再次触发（16:31:32）；DB 仍是 53 歌 / 38 专辑 / 40 艺人，无新崩溃。限制：只在场景激活时检查，若 App 一直前台且从别的设备上传，需要切走再切回；本地文件夹仍走手动重新同步。
- **歌词偏移 / M3U 歌单 / 无缝播放**（2026-11-12，用户要求“先做着三个功能”）：
  - 歌词偏移：播放器「更多」新增「歌词偏移」子菜单（已同步 / 提前 0.2 / 0.5 / 1.0s / 延后 0.2 / 0.5 / 1.0s，当前值打勾；**文案用“提前/延后”而不是 ±s**，因为“+1.0s”会被理解反）。值存 `settings.user._lyricsOffsetMs`（clamp ±5000ms），改后 post `.lyricsOffsetChanged`，`LyricsView` 立即按新偏移重排；同一偏移同时用于 `updateActiveFill`（词级高亮 `rawSeconds + lyrics.offset/1000 + 用户偏移`）、行切换（额外加 0.25s `lyricsLeadTime`）和点歌词 seek（`playbackTime(for:)` 反向扣除）。LRC 的 `[offset:±ms]` 原来被丢弃，现在由 `LRCFileParser` 写入 `lyrics.offset`。正数 = 歌词提前。验证：选“提前 1.0s”后菜单副标题变“提前 1.0s”、`defaults` 里 `_lyricsOffsetMs=1000`，复位“已同步”后为 0。
  - M3U 导入/导出：编解码 + 匹配在 `fmusicKit/Common/M3UPlaylist.swift`（已进 pbxproj）。导入在播放列表页「更多 → 导入 M3U 歌单」，`UIDocumentPicker`（`.m3u`/`.m3u8`、asCopy）；解析 `#EXTINF`/裸路径，依次按“规范化相对路径 → 路径后缀 → 文件名 → 曲名（EXTINF 去掉 Artist - 前缀）→ 艺人+曲名”匹配，同曲名多条时用 duration ±2s 消歧；新建歌单名取文件名，完成后弹“已导入 N 首歌曲，跳过 N 条”。导出在歌单详情「更多 → 导出 M3U」（智能歌单隐藏），按 FRC 顺序写 `#EXTM3U` + `#EXTINF:duration,Artist - Title` + 相对 `song.url`，临时 `.m3u8` 走 `UIActivityViewController`（锚点 `optionsButton`）。实测：2 首测试 m3u8 导入成功、歌单显示 2 Songs；导出文件 148 字节，内容 `#EXTINF:265,青鸟飞鱼 - 此生不换` / `25 此生不换 - 青鸟飞鱼.flac` 等（相对路径）。测试歌单与测试文件已清理。
  - 无缝播放：同一 `AudioStreamingPlayer` 环形缓冲连续出帧——播到剩余 `max(10, crossfade+8)` 秒时 `checkForPreloadNextPlayerItem` 预加载下一首并 `queue`，播完由渲染线程从 `.buffering` 切到下一 entry，只追加缓冲、不 `resetBuffers`。日志实测 `Preloading → Insert Cache → Play Preloaded` 连续，没有重新 insert。
- **交叉淡入淡出（真实 overlap）**（2026-11-12，用户要求“把这个功能添加完善一下”）：
  - 引擎（`Vendor/AudioStreaming`）：`AudioPlayer.crossfadeDuration`，250ms 定时器在 `serializationQueue` 上 `tryPrepareCrossfade()`——要求 outgoing 的 `lastFrameQueued` 已知、incoming 已入队且解码 ≥ N 帧、ring 里还有 ≥ N+0.5s 的 outgoing 尾部（0.5s 边距防止渲染线程读到正在被覆写的尾部）；持有 `rendererContext.lock` 校验 `bufferGeneration` 后，把 outgoing 最后 N 帧与 incoming 最前 N 帧按线性增益混音（`mixCrossfade`），记录 `CrossfadeReadState`。`AudioEntry` 在首帧入环时记录 `firstFrameRingIndex`/generation（`AudioFileStreamProcessor.fillUsedFrames`）。
  - 渲染（`AudioPlayerRenderProcessor.inRender`）：crossfade 状态下 outgoing 的读取钳到它自己的末帧，剩余 quantum 从 incoming “混音头之后”（`incomingStartIndex + N`）补；`applyCrossfadeSwitchIfNeeded` 在 entry 切换时把 `frameStartIndex` 前移 N、`used -= N`，并给 incoming `framesState.played = N`。混音区最后样本 = incoming[N-1]，切换后从 incoming[N] 继续，样本级连续，无静音/爆音。
  - 播放链路：`AudioPlayerConfiguration.bufferSizeInSeconds` 10→**30**（ring 需同时容纳 outgoing 尾 + incoming 头）；预加载阈值改为 `max(10, crossfade+8)`（8s 档提前 16s 预载）；`BackendAudioPlayer.crossfadeDuration` 下发引擎，`AudioPlayer.insertIntoPlayer` 每次播放前从 `settings.user.crossfadeSeconds` 同步；新增 `PlayerFacade.updateCrossfadeDuration(seconds:)`，设置改动即时生效。
  - 设置：设置 → 播放 → 交叉淡入淡出（关闭 / 3 / 5 / 8 秒，**默认关闭**），存 `settings.user._crossfadeSeconds`（clamp 0–8），footer 说明“只有下一首已预加载时才会生效”。
  - 验证：Debug 构建通过。8 秒档连续两次自动切歌：`Crossfade prepared: frames=352800 remaining=696247` → `Crossfade switched: skipped=352800` → `Play Preloaded`（352800 = 8s × 44.1k）；第二首实际播放 142.4s + 跳过 8s = 全曲 150.3s，切歌后 UI 的 B 曲从约 8s 起跑。用 BlackHole 2ch + AVAudioEngine 录制系统输出与源 FLAC 对齐比对：切换点前后 RMS 连续（无静音/断流），B 曲开头在切换前 8 秒内按近似 `t/8` 的增益淡入（42.75s→45.25s 实测 0.71→0.89，预测 0.65→0.97），A 曲尾部渐出；关闭（0 秒）后预加载/`Play Preloaded` 仍正常且无 crossfade 日志。诊断时注意：BlackHole 的 `kAudioDevicePropertyVolumeScalar` 默认可能只有 6.25%，录到近乎静音先把它设为 1.0。
  - 注意：混音完成到 entry 切换之间，播的仍是“outgoing 条目”的帧，所以淡入淡出期间 UI 仍显示 A 曲；切歌后 B 曲进度从 N 秒开始（混音头已消耗），这是预期行为。
  - 崩溃修复（2026-11-12 17:45:40 `.ips`）：新增的 250ms 定时器在播放时处于 activated；`BackendAudioPlayer.handleError → restartPlayer → player = nil` 触发 `AudioPlayer.deinit`，而 `DispatchTimerSource.deinit` 原来无条件 `timer.resume()`（假设定时器总是 suspended，Retrier 的用法确实如此），激活状态下多 resume 一次 → libdispatch `_dispatch_lane_resume` SIGTRAP。已改为只在 `state == .suspended` 时 resume；`restartPlayer` 路径实测不再崩溃。顺带修 `Utilities.asColonDurationString` 把 `Double` 传给 `%d` 的格式串错误（macOS 27 会打 Foundation fault 日志）。
- **彻底移除 Last.fm / scrobble 残留**（2026-11-12，用户要求“把残留的 scrobble 代码删掉”）：上游 fmusic 的 scrobble 是“客户端把播放上报给 Subsonic/Ampache 服务器，由服务器转发 Last.fm”；本 fork 删掉服务器后，`ScrobbleSyncer` 调用的 `LibrarySyncerDefaults.scrobble` 是空实现，整条链路无效。
  - Swift：删 `fmusicKit/Player/ScrobbleSyncer.swift`、`Storage/EntityWrappers/ScrobbleEntry.swift`、`Storage/ManagedObjects/ScrobbleEntryMO+CoreDataClass/Properties.swift`；`MetaManager` 去掉 syncer 创建/notifier/start/stop；`BackendApi`、`LibrarySyncerProxy`、`LibrarySyncerDefaults`、测试 mock 去掉 `scrobble` 与 `syncNowPlaying`（`NowPlayingSongPosition` 一并删）；`LibraryStorage` 去掉 `getUploadableScrobbleEntryCount` / `getAllScrobbleEntries` / `getFirstUploadableScrobbleEntry` / `createScrobbleEntry` / 删账户时的清理块；`LibraryUpdater` 去掉迁移时的 Scrobbles 归属；`AbstractPlayableMO`/`AccountMO` 去掉 `scrobbleEntries` 关系属性与生成访问器；`Settings.swift` / `LegacySettings` / `PersistentStorage.UserDefaultsKey` / `ObservableSettings` / `SettingsHostVC` 去掉 `isScrobbleStreamedItems`（本来就没有 UI）；README 删 “- Scrobbling”；pbxproj 同步删除引用。
  - Core Data：从 v49 复制出 **`fmusic v50.xcdatamodel`**，删除 `ScrobbleEntry` 实体及 `Account`/`AbstractPlayable` 的两条反向关系（v1–v49 保留原样用于迁移链），`.xccurrentversion` 指向 v50，`CoreDataMigrationVersion` 加 `v50` 并让 `v49.nextVersion()` 返回它；pbxproj 增加 v50 文件引用、`currentVersion` 更新。自定义 `CoreDataMigrator` 走 `NSMappingModel.inferredMappingModel`，实体删除由轻量迁移直接丢弃表。
  - 验证：`xcodebuild` 通过；迁移前把 DB 备份到 `/tmp/fmusic_db_backup/`（含 -wal/-shm）。启动新包后 `sqlite3` 里 `ZSCROBBLEENTRY` 已不存在（原有 4 条旧记录随表删除），`ZABSTRACTLIBRARYENTITY` 仍 131 行，`pragma integrity_check` = ok；首页/迷你条/曲库数据正常，无新 `.ips`；进程 pid 53718。若需回滚：把备份三个文件放回 `~/Library/Application Support/fmusic/` 并用旧包启动。
- **热路径与常驻开销优化**（2026-11-12，用户要求“优化、删冗余、减少占用、提高响应速度”）：
  - 歌词 60 Hz：`LyricsView.scroll(toTime:)` 原来无论歌词是否显示都做“全行线性查找 + 词级高亮 + 单元格刷新”。现在 `isHidden` 或不在 window 中直接返回（重新显示时 `showLyrics` 会按当前进度同步一次），行查找改为按 `startTime` 的二分（`lyrics.line` 由 `LibrarySyncerDefaults` 按时间排序），60 Hz 下从 O(行数) 降到 O(log 行数)。
  - 播放/歌词 Timer 加入 `.common` 运行模式：原来只在 default mode，滚动列表/按住菜单时进度条和歌词会停住；现在滚动时继续走。
  - 视觉分析器：tap 每 ~6 ms 回调一次，原来每个回调都做 FFT + `Task { @MainActor }` + `@Published` 数组更新（约 170 次/秒）。现在按 30 fps 节流（每 33 ms 最多一次），回调频率降约 5.7 倍，可视化画面无差别；`isActive`（只在可视化显示时计算）逻辑未变。
  - 进度持久化：`AudioPlayer.didElapsedTimeChange` 原来每 0.2 s 都检查并写 Core Data 对象的 `playProgress/playDuration`，现在每 5 s 播放时间才更新一次（恢复点按秒计，足够）。
  - 交叉淡化定时器：`crossfadeDuration == 0`（默认）时不再创建/激活 250ms 计时器；播放中打开/关闭设置会立即 activate/suspend。
  - 删 `AudioAnalyzerProtocol`（零引用）。
  - 验证：构建通过；真机打开大播放器歌词页，60 Hz 激活行高亮/弹簧滚动正常；关闭大播放器后 CPU 采样约 3–5%（Debug 构建），RSS ~230 MB（含 30 s 引擎缓冲 ≈10 MB；1.7 GB 播放缓存未动）。注意 Debug 构建的绝对 CPU 不代表 Release。

---

## 5. 现状与验证方法

当前 App 已重启并在跑（Debug-maccatalyst 构建）。显示样式 large，音量 100%。播放器数据可能处于暂停/0:00，取决于上次会话。

### 手动验证路径

1. `open` App → 主窗口 `首页`，底部有迷你条。
2. 点击迷你条**封面/标题区** → 主窗口内整页播放器（同一窗口，`coverVertical` 从下往上滑入；关闭时向下滑出，不再是 sheet，也不切独立窗口）。
3. 检查：音量胶囊在右上；两栏布局（左封面+信息，右歌词）；5 个控制键一行；右下 3 个工具图标。
4. 点右下 List 图标 → compact：音量滑块消失、音量按钮出现在右下；再点一次切回 large。
5. 播放/暂停、点进度条、拖音量应正常。
6. 崩溃看 `~/Library/Logs/DiagnosticReports/fmusic-*.ips`。注意：2026-11-11 22:42 的 `.ips` 是早期 slider tint 崩溃，修复后未再出现，不要误判。

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

- **Core Data 模型只剩 v49/v50**：新增实体/字段必须加 `fmusic v51.xcdatamodel`，同步改迁移枚举和 `.xccurrentversion`；v48 及更老的库无法再迁移。
- **发布包是 arm64-only**（CI `ARCHS=arm64`）；需要 Intel 时在 workflow 去掉该参数。
- 播客/电台占位图和图标预览图已删除；Catalyst 上不支持切换备用图标，设置页不会出现图标选择器。

1. **Mac idiom + UISlider**：不要去掉 `preferredBehavioralStyle = .pad`，也不要在 Mac idiom 下调用 track tint API；会直接崩。播放器音量已改为自绘 `VolumeSlider`，不受此限制；但如果新代码又要用 UISlider，记住这条。
2. **XIB 封面溢出**：`LargeCurrentlyPlayingPlayerView.xib` 的封面是 1:1、最大 360，而槽位高度由 stack 决定；不要删除 `z4T-8m-Q1a` 高度上限，否则较矮窗口又会压到音量条。
3. **同窗全屏与独立窗口共用 `PopupPlayerVC`**：主窗口全屏随窗口尺寸（最小 980×540），独立窗口 1024×768；布局改动两边都要看。
4. **显示样式会持久化**：把 App 停在 compact 会影响用户下次打开；验证后切回 large。
5. **XIB 修改必须真机看**：只 `xcodebuild` 成功不代表 IB 约束按预期生效（可用 lldb 看 frame）。
6. **shell 别名**：`find`→fd、`grep`→rg、`rm`→trash、`ls`→lsd；需要标准行为时用 `/usr/bin/find`、`rg`、`/bin/rm`、`/bin/ls`。
7. **Catalyst 标题栏**：AppKit 控件（NSSlider/NSVisualEffectView/NSView）不可用；但 UIKit 视图可以通过 `NSToolbarItem(itemIdentifier:barButtonItem:)` 进原生标题栏（见 `PlayerWindowVolumeControl.swift`）。`titlebar.toolbar = nil` 会移除整个工具栏，只在播放器关闭时做；titleVisibility/separatorStyle/toolbarStyle 必须成对保存与还原，否则关播放器后资料库窗口没标题。标题栏音量 slider 也固定在 `preferredBehavioralStyle = .pad`。
7. **不要动用户库**：不要清 `~/Library/Application Support/fmusic`，不要重装/重建账号，除非用户要求。
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
cd /Users/apple/Desktop/AI/Quder/fmusic
git status --short | wc -l          # 预期非 0，不要 reset
git branch --show-current           # feature/webdav-local
xcodebuild -project fmusic.xcodeproj -scheme fmusic -configuration Debug \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

- 构建成功后重启 App，按第 5 节走一遍播放器大/紧凑两种样式。
- 不要在未询问的情况下提交或推送。
