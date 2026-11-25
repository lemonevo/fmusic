# fmusic 项目说明与运行指南（供 AI 协作使用）

> 仓库路径：`/Users/apple/Downloads/ceshi/fmusic`
> 技术栈：Swift 6 / AppKit（macOS 14+，液态玻璃适配 macOS 26+）/ SwiftPM 跨平台核心（iOS 17+ / macOS 14+）

---

## 1. 项目架构与目录说明

本项目已完成从 Catalyst 到原生 AppKit 的全面移植，采用**跨平台核心 + 平台原生 UI** 分层架构：

```text
fmusic/
├── Packages/FmusicKit/   # 跨平台共享核心（SwiftPM，支持 iOS 17+ / macOS 14+）
│                         # 包含 Core Data、音频播放与队列、WebDAV/本地文件夹索引、
│                         # 在线歌词与元数据匹配、封面降采样与缓存、均衡器、L10n 国际化
├── fmusic-macOS/         # 当前主开发目标：纯 AppKit 原生 macOS 应用
├── fmusic/               # 旧 Catalyst / UIKit+SwiftUI 源码（只读参考，勿轻易修改）
├── fmusic-iOS/           # iOS Target 配置（未来新建纯 SwiftUI iOS/iPad 端可直接复用 FmusicKit）
├── Vendor/AudioStreaming # 含 FLAC seek 补丁的音频流库（勿随意升级）
└── BuildTools/           # 工程同步脚本（sync-macos-sources.rb）
```

---

## 2. 编译、同步与运行命令

### 2.1 新增或删除 `fmusic-macOS/` 下的 Swift 文件后（必做）
不要手动修改 `fmusic.xcodeproj/project.pbxproj` 的 Sources，直接运行同步脚本：

```bash
cd /Users/apple/Downloads/ceshi/fmusic
ruby BuildTools/sync-macos-sources.rb
```

### 2.2 编译共享核心包（FmusicKit）

```bash
cd /Users/apple/Downloads/ceshi/fmusic/Packages/FmusicKit
swift build
```

### 2.3 编译 macOS AppKit 应用（Debug）

```bash
cd /Users/apple/Downloads/ceshi/fmusic
xcodebuild -project fmusic.xcodeproj -scheme fmusic-macOS -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/fm-mac-dd \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_IDENTITY="" build
```

### 2.4 安装测试副本并启动（不动 `/Applications`）

```bash
pkill -f "fmusic-AppKit" 2>/dev/null; sleep 1
rm -rf ~/Applications/fmusic-AppKit.app
cp -R /tmp/fm-mac-dd/Build/Products/Debug/fmusic.app ~/Applications/fmusic-AppKit.app
codesign --force --deep --sign - --identifier lol.levo.fmusic ~/Applications/fmusic-AppKit.app
open ~/Applications/fmusic-AppKit.app
```

### 2.5 常用开发启动参数

```bash
open ~/Applications/fmusic-AppKit.app --args --songs
open ~/Applications/fmusic-AppKit.app --args --page albums
open ~/Applications/fmusic-AppKit.app --args --album "专辑名"
open ~/Applications/fmusic-AppKit.app --args --artist "艺人名"
open ~/Applications/fmusic-AppKit.app --args --playlist "歌单名"
```

---

## 3. 开发红线与注意事项

1. **严禁删除或破坏用户本地数据**：
   - 数据库：`~/Library/Application Support/fmusic/fmusic.sqlite`
   - 元数据覆盖缓存：`~/Library/Application Support/fmusic/metadata-overrides.json`
   - 封面与歌词缓存：`~/Library/lol.levo.fmusic`
   - 偏好设置：`~/Library/Preferences/lol.levo.fmusic.plist`
2. **文件删除与 Git 约束**：
   - 删除仓库文件统一用 `trash`，不要用 `rm`。
   - 不要执行 `git push`、打 tag、发 release，也不要修改 `main` 分支。
3. **修改 `L10n.swift` 后必须检查重复 Key**：
   - 路径：`Packages/FmusicKit/Sources/fmusicKit/Common/L10n.swift`（当前 783 个 key）
   - Swift 字典存在重复 key 会导致运行时崩溃，修改后务必检查：
     ```bash
     python3 -c '
     import re
     text = open("Packages/FmusicKit/Sources/fmusicKit/Common/L10n.swift").read()
     keys = re.findall(r"^\s*\"((?:[^\"\\]|\\.)*)\"\s*:", text, re.M)
     print("Duplicates:", [k for k in set(keys) if keys.count(k) > 1])
     '
     ```
4. **窗口定位**：若 `/Applications/fmusic.app`（原 Catalyst 版）同时运行，因共享 Bundle ID `lol.levo.fmusic`，自动化或截图时需按进程 PID 区分。

---

## 4. 当前核心功能与最新优化现状

### 4.1 播放、队列与交互
- **多来源支持**：支持 WebDAV 与本地文件夹多账户切换（**设置 → 账户 → 添加账户**；本地文件夹账户支持在设置内直接更换目录并重新同步）。
- **悬浮胶囊播放条 & 大播放页**：液态玻璃悬浮胶囊播放条支持切歌封面淡变、进度拖拽、方向键快退/快进（±5s）、鼠标悬停时间提示与 VoiceOver 滑块语义；大播放页采用主窗口内覆盖层（支持 Esc 关闭与窗口缩放/全屏）；控制中心封面优先显示歌曲封面，无封面时回退当前应用图标。
- **播放队列**：支持键盘 Return 播放、Delete 删除、右键菜单及**列表内/跨分组拖拽排序**（`PlayerIndex.queueType`/`index` 已公开）。
- **快捷键与窗口保护**：全局空格键拦截已放行模态弹窗、Sheet 及聚焦文本框/控件；主窗口恢复位置时带多屏离屏校验，外接显示器断开后自动居中。

### 4.2 资料库、元数据与封面兜底
- **页内实时搜索**：专辑、艺人、歌曲及各详情页均接入顶部内容工具栏实时搜索。
- **元数据与封面策略**：默认优先使用歌曲自带内嵌封面与歌词；当封面缺失、非正方形（比例 `< 0.92`）或小于 `200px` 时，自动尝试在线匹配合适尺寸的 1:1 封面，若无合适在线图则本地无放大居中裁切为 1:1 正方形；专辑网格与歌曲列表右键菜单均提供**“重新匹配封面”**入口。

### 4.3 歌词系统
- **后台异步解析**：歌词解析已移出主线程；右侧歌词栏支持点击精准跳转，歌词搜索页支持多源预览与一键应用。
- **桌面歌词 & 菜单栏歌词**：桌面歌词已全部国际化（中/英文同步切换），改用 `NSTrackingArea` 与 `NSAnimationContext` 消除常驻 20Hz/60Hz 轮询定时器；菜单栏歌词支持在设置中一键开关。

### 4.4 设置界面与丝滑动效
- **原生分组卡片与对齐**：设置页面采用 macOS 系统设置风格的圆角分组卡片、细边框与分割线，所有分组标题、行标题、多行行内副标题与页脚严格对齐在 `16pt` 基准线上；通用、播放、歌词、显示页面均已按功能重新清晰分组；支持设置项级搜索与直达跳转。
- **外观与语言**：支持浅色/深色/跟随系统、液态玻璃三档（柔和 / 标准 / 通透）、主题色、自定义应用图标、中英文切换（带一键重启提示）。
- **原生微动效**：设置窗口打开淡入上浮、设置页切换交叉淡入滑动、主窗口侧边栏切换淡变、详情页推入/返回水平滑动、专辑封面悬停轻浮缩放与阴影、播放条切歌封面淡变（全部自动遵循系统“减弱动态效果”）。

### 4.5 性能、内存与存储优化
- **分级降采样加载封面**：`ArtworkImageLoader` 支持按 `maxPixelSize` 降采样并缓存（列表与播放条 `160px`、专辑网格 `384px`、大播放页 `1024px`），内存缓存上限 `32 MB`；歌词侧栏栅格缓存上限 `16 MB`。
- **零空转待机**：歌词侧栏 60Hz 定时器与大播放页歌词定时器在暂停/停止后自动停表或跳过刷新。
- **封面磁盘瘦身**：`ArtworkImageEncoder` 落盘上限调整为 `800px`、JPEG 质量 `0.80`、`256 KB` 直通阈值。
- **Core Data 容错**：启动或迁移失败时可提示并安全备份重建，不再直接 `fatalError`。

---

## 5. 未来扩展 iPhone / iPad 的建议

如需支持 iOS / iPadOS，**直接复用 `Packages/FmusicKit/` 全部业务逻辑**，只需新建一个纯 SwiftUI 的 iOS/iPadOS App Target：
- iPhone 用 `TabView`、iPad 用 `NavigationSplitView` 自适应布局；
- 通过轻量 `@Observable` 桥接 `FmusicKit.shared.player`（`MusicPlayable`）与 `FmusicKit.shared.storage`；
- 配置后台播放（`UIBackgroundModes: audio` + `AVAudioSession` `.playback`），本地文件夹通过 `.fileImporter` 获取安全书签；
- 无需移植 macOS 专属的桌面悬浮歌词、菜单栏歌词和全局空格键拦截。
