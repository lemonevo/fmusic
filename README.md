# fmusic

本地 / WebDAV 音乐播放器，面向 macOS（Mac Catalyst 构建），由 [Amperfy](https://github.com/BLeeEZ/amperfy) 去服务器化改造而来。

> 应用本体目前仍名为 `Amperfy`（Bundle ID 未改），仓库名与安装包名为 `fmusic`。

## 特性

- **音乐库**：本地文件夹、WebDAV 两种来源；WebDAV 支持自动增量扫描，只处理新增和变化的文件
- **界面**：Apple Music 风格侧栏、迷你播放条与大播放器，支持深色模式、字号与封面显示设置
- **播放**：无缝切歌、交叉淡入淡出（关闭 / 3 / 5 / 8 秒）、随机、循环、睡眠定时器
- **音效**：均衡器、ReplayGain
- **歌词**：外挂 `.lrc` / `.yrc`（逐字）文件，支持手动偏移校准
- **歌单**：新建与编辑，`.m3u` 导入导出
- **曲库**：内嵌封面或同目录 `cover` / `folder` / `front` 图片，评分、收藏、搜索

## 支持格式

```
flac  mp3  m4a  mp4  aac  wav  aiff  aif  ogg  oga  opus
```

歌词文件与音频同名，后缀为 `.lrc` 或 `.yrc`。

## 系统要求

- macOS 26 或更高（Mac Catalyst）
- 支持 Apple Silicon 与 Intel

## 安装

每次推送到 `main`，GitHub Actions 会自动构建 DMG：

1. 打开最近一次成功的 Actions 运行
2. 下载 `fmusic-dmg` 产物，解压得到 `fmusic.dmg` 与校验文件
3. 打开 DMG，把 `Amperfy.app` 拖入「应用程序」

安装包为 ad-hoc 签名，首次启动需要右键 →「打开」，或执行：

```bash
xattr -dr com.apple.quarantine /Applications/Amperfy.app
```

## 从源码构建

需要 Xcode 26 或更新版本。

```bash
xcodebuild -project Amperfy.xcodeproj -scheme Amperfy -configuration Release \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  CODE_SIGNING_ALLOWED=NO build
```

调试运行：用 Xcode 打开 `Amperfy.xcodeproj`，选择 `Amperfy` scheme 与「My Mac (Mac Catalyst)」。

应用数据位于 `~/Library/Application Support/Amperfy/`。

## 与上游 Amperfy 的差异

- 移除 Subsonic / Ampache 服务器支持，改为本地文件夹与 WebDAV 音乐库
- 移除 Last.fm / Scrobble 上报相关代码与数据模型
- Apple Music 风格界面重构
- 新增交叉淡入淡出、M3U 导入导出、歌词手动偏移、WebDAV 增量扫描
- 音频引擎（vendored AudioStreaming）内建无缝播放与交叉淡化

## 致谢与许可

本项目遵循上游的 [GPL-3.0](LICENSE)。感谢 [BLeeEZ/amperfy](https://github.com/BLeeEZ/amperfy)、[AudioStreaming](https://github.com/dimitris-c/AudioStreaming) 以及 MarqueeLabel、NotificationBanner、ID3TagEditor、VYPlayIndicator、CallbackURLKit、DominantColors、AudioVisualizerKit、Alamofire、Ifrit、swift-collections、SnapKit 等开源组件。
