<div align="center">

# fmusic

**面向 macOS 的原生 AppKit 本地与 WebDAV 音乐播放器**

`macOS 14+` · `Swift 6` · `AppKit` · `Apple Silicon` · [GPL-3.0](./LICENSE)

[核心特性](#核心特性) • [支持格式](#支持格式) • [安装使用](#安装使用) • [从源码构建](#从源码构建) • [项目架构](#项目架构) • [开发文档](./AI_QUICKSTART.md)

</div>

fmusic 是一款面向 macOS 的本地与 WebDAV 音乐播放器，采用 **跨平台 SwiftPM 核心（`FmusicKit`）+ 原生 AppKit 界面** 的分层架构，兼顾低内存占用、原生微动效与高解析无损音频播放体验。

## 核心特性

### 资料库与多来源管理
- **本地文件夹 & WebDAV**：支持添加多个本地音乐目录与 WebDAV 账户并自由切换；WebDAV 支持增量扫描，仅处理新增与变更文件。
- **Finder 单文件直开**：在 Finder 中用 fmusic 打开音频文件会自动入库并立即播放，重复打开不会产生冗余记录。
- **页内实时搜索与歌单**：专辑、艺人、歌曲及详情页均支持顶部工具栏实时筛选；支持歌单创建、编辑以及 `.m3u` 导入导出。
- **封面与元数据兜底**：优先读取内嵌封面与同目录 `cover` / `folder` / `front` 图片；封面缺失、过小（`< 200px`）或非正方形时自动在线匹配 1:1 封面，无合适结果时无放大居中裁切，并支持右键手动「重新匹配封面」。

### 播放与音效
- **无损与高解析播放**：支持无缝切歌、交叉淡入淡出（关闭 / 3 / 5 / 8 秒）、随机、循环、歌曲续播与睡眠定时器。
- **音效调校**：内置均衡器（EQ）与 ReplayGain 响度归一化。
- **队列与交互控制**：支持播放队列列表内与跨分组拖拽排序、全局媒体控制、进度条方向键快退/快进（±5s）及悬停时间预览。

### 歌词系统
- **本地与多源在线歌词**：读取与音频同名的 `.lrc` / `.yrc` / `.qrc` / `.krc` 文件，支持网易云、QQ、酷狗、LRCLIB 在线搜索，优先匹配逐字与双语歌词。
- **多形态展示**：内置播放器歌词侧栏、桌面浮窗歌词与菜单栏歌词，支持字号、透明度、对齐方式、位置锁定、点击穿透与手动偏移校准。

### 原生 macOS 体验
- **现代界面与液态玻璃**：Apple Music 风格侧边栏、悬浮胶囊播放条与大播放页；支持浅色/深色/跟随系统、三档液态玻璃质感、主题色与自定义应用图标。
- **系统级设置界面**：采用 macOS 分组卡片布局、全项实时搜索与中英文双语切换，所有微动效均遵循系统「减弱动态效果」设置。
- **性能与内存优化**：封面按视图尺寸分级降采样缓存，暂停或空闲时自动停止高频定时器，降低 CPU 与内存占用。

## 支持格式

| 类别     | 支持格式                                                     |
| :------- | :----------------------------------------------------------- |
| **音频** | `flac` `mp3` `m4a` `mp4` `aac` `wav` `aiff` `aif` `ogg` `oga` `opus` |
| **歌词** | `.lrc` `.yrc` `.qrc` `.krc`（与音频同名，逐字格式保留词级时间） |
| **歌单** | `.m3u`（导入 / 导出）                                        |

## 系统要求

- **运行环境**：macOS 14.0 及以上（液态玻璃特性适配 macOS 26+），Apple Silicon（`arm64`）
- **开发环境**：Xcode 16+ / Swift 6

## 安装使用

### 下载安装包
1. 前往 [Releases](https://github.com/lemonevo/fmusic/releases) 下载最新 DMG，或在 GitHub Actions 最近一次成功构建中下载 `fmusic-appkit-dmg` 产物。
2. 打开 `.dmg` 文件，将 `fmusic.app` 拖入「应用程序」文件夹。

### 首次启动说明
安装包采用 ad-hoc 签名，首次启动若提示无法验证开发者，请右键应用选择「打开」，或在终端执行：

```bash
xattr -dr com.apple.quarantine /Applications/fmusic.app
```

## 从源码构建

### 1. 编译跨平台核心包（`FmusicKit`）

```bash
cd Packages/FmusicKit
swift build
```

### 2. 编译原生 macOS 应用（Debug）

```bash
xcodebuild -project fmusic.xcodeproj -scheme fmusic-macOS -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/fm-mac-dd \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_IDENTITY="" build
```

> **开发提示**：在 `fmusic-macOS/` 下新增或删除 Swift 文件后，请运行 `ruby BuildTools/sync-macos-sources.rb` 自动同步工程文件，不要手动编辑 `project.pbxproj`。更多启动参数、测试副本安装方式与开发约束请参阅 [AI_QUICKSTART.md](./AI_QUICKSTART.md)。

## 项目架构

```text
fmusic/
├── Packages/FmusicKit/    # 跨平台核心（SwiftPM，支持 iOS 17+ / macOS 14+）
│                          # Core Data、播放与队列、WebDAV/本地索引、歌词与元数据、L10n
├── fmusic-macOS/          # 主开发目标：原生 AppKit macOS 客户端
├── fmusic-iOS/            # iOS Target 配置（可直接复用 FmusicKit 构建 SwiftUI 端）
├── fmusic/                # 旧版 Mac Catalyst 源码（参考保留）
├── Vendor/AudioStreaming/ # 本地魔改版 AudioStreaming（含 FLAC seek 等补丁）
└── BuildTools/            # 工程源码同步与格式化脚本
```

## 依赖与致谢

- [AudioStreaming](https://github.com/dimitris-c/AudioStreaming) — 流式音频播放引擎（本地补丁记录见 [Vendor/AudioStreaming/PATCHES.md](./Vendor/AudioStreaming/PATCHES.md)）
- [Ifrit](https://github.com/ukushu/Ifrit) — 模糊搜索
- [ID3TagEditor](https://github.com/chicio/ID3TagEditor) — 音频标签解析

## 开源协议

本项目基于 [GNU General Public License v3.0](./LICENSE) 开源。