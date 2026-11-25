# fmusic 项目说明与运行指南（供 AI 协作使用）

> 仓库路径：`/Users/apple/Downloads/ceshi/fmusic`
> 语言 / 工具链：Swift 6 / Xcode（macOS 14+，液态玻璃效果适配 macOS 26+）

---

## 1. 项目架构

本项目已从原 Catalyst 版完成纯 AppKit 原生移植，采用**跨平台核心 + 平台原生 UI** 分层结构：

```text
fmusic/
├── Packages/FmusicKit/   # 跨平台共享核心（SwiftPM，支持 iOS 17+ / macOS 14+）
│                         # 包含 Core Data、音频播放与队列、WebDAV/本地文件夹索引、
│                         # 在线歌词匹配、专辑封面兜底与缓存、均衡器、L10n 国际化
├── fmusic-macOS/         # 当前主开发目标：纯 AppKit 原生 macOS 应用
├── fmusic/               # 旧 Catalyst / UIKit+SwiftUI 源码（仅作只读参考，勿轻易修改）
├── fmusic-iOS/           # iOS Target 配置（未来若新建纯 SwiftUI iOS/iPad 端可独立复用 FmusicKit）
├── Vendor/AudioStreaming # 魔改含 FLAC seek 补丁的音频流库（勿随意升级）
└── BuildTools/           # 工程同步脚本（sync-macos-sources.rb 等）
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
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
```

### 2.4 安装测试副本并启动（不覆盖 `/Applications`）

```bash
pkill -f "fmusic-AppKit" 2>/dev/null; sleep 1
rm -rf ~/Applications/fmusic-AppKit.app
cp -R /tmp/fm-mac-dd/Build/Products/Debug/fmusic.app ~/Applications/fmusic-AppKit.app
codesign --force --deep --sign - --identifier lol.levo.fmusic ~/Applications/fmusic-AppKit.app
open ~/Applications/fmusic-AppKit.app
```

### 2.5 常用开发启动参数

```bash
# 直接打开指定页面或详情页
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
2. **Git 约束**：不要执行 `git push`、打 tag、发 release，也不要修改 `main` 分支。
3. **修改 `L10n.swift` 后必须检查重复 Key**：
   - 路径：`Packages/FmusicKit/Sources/fmusicKit/Common/L10n.swift`
   - Swift 字典字面量存在重复 key 会在运行时直接崩溃，改完可用脚本验证：
     ```bash
     python3 -c '
     import re
     text = open("Packages/FmusicKit/Sources/fmusicKit/Common/L10n.swift").read()
     keys = re.findall(r"^\s*\"((?:[^\"\\]|\\.)*)\"\s*:", text, re.M)
     print("Duplicates:", [k for k in set(keys) if keys.count(k) > 1])
     '
     ```
4. **窗口定位**：原版 Catalyst 应用（如装在 `/Applications/fmusic.app`）与本项目共享 Bundle ID `lol.levo.fmusic`，自动化或截图时需按进程 PID 区分。

---

## 4. 当前核心功能现状（macOS AppKit）

- **播放与音频**：支持 WebDAV 与本地文件夹多来源切换（**设置 → 账户 → 添加账户**）、底部液态玻璃悬浮胶囊播放条（含进度拖拽、方向键快进/快退、悬停时间提示与无障碍滑块）、主窗口内大播放页覆盖层（Esc 关闭）、播放队列键盘/右键删除与拖拽排序、系统控制中心封面（歌曲封面优先，缺省回退当前应用图标）。
- **资料库与搜索**：专辑 / 艺人 / 歌曲均支持顶部工具栏实时搜索；列表统一使用 `InteractiveTableView` 支持 Return 播放、Delete 删除与右键菜单；支持右键专辑或歌曲强制“重新匹配封面”。
- **歌词系统**：后台线程异步解析歌词；右侧歌词栏支持精准点击跳转；歌词搜索页支持多源预览与一键应用；支持桌面悬浮歌词（`NSTrackingArea` 无轮询省电 + `NSAnimationContext` 高度动画 + 完整中英文国际化）与菜单栏歌词开关。
- **元数据与封面兜底**：优先读取文件自带内嵌封面，仅对缺失、非正方形（比例 `< 0.92`）或小于 `200px` 的封面触发在线元数据匹配，若无合适在线图则本地无放大居中裁切为 1:1 正方形。
- **外观与设置**：支持浅色/深色/跟随系统、液态玻璃三档（柔和 / 标准 / 通透）、主题色与自定义应用图标、中英文切换（含一键重启提示）、设置项级别搜索与直达跳转、Core Data 启动异常可恢复备份重建。

---

## 5. 未来扩展 iPhone / iPad 的建议

如需支持 iOS / iPadOS，**直接复用 `Packages/FmusicKit/` 全部业务逻辑**，只需新建一个纯 SwiftUI 的 iOS/iPadOS App Target：
- iPhone 用 `TabView`、iPad 用 `NavigationSplitView` 自适应布局；
- 通过轻量 `@Observable` 桥接 `FmusicKit.shared.player`（`MusicPlayable`）与 `FmusicKit.shared.storage`；
- 开启后台播放（`UIBackgroundModes: audio` + `AVAudioSession` `.playback`），本地文件夹通过 `.fileImporter` 获取安全书签；
- 无需移植 macOS 专属的桌面悬浮歌词、菜单栏歌词和全局空格键拦截。
