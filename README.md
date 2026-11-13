# fmusic

面向 macOS 的本地 / WebDAV 音乐播放器（Mac Catalyst）。

## 功能

- **音乐库**：添加本地文件夹或 WebDAV 目录；WebDAV 支持自动增量扫描，只处理新增和变化文件
- **界面**：Apple Music 风格侧栏、迷你播放条与大播放器；深色模式、字号、封面显示可调；设置侧栏支持按页面或设置项搜索
- **播放**：无缝切歌、交叉淡入淡出（关闭 / 3 / 5 / 8 秒）、随机、循环、睡眠定时器
- **音效**：均衡器、ReplayGain
- **歌词**：读取与音频同名的 `.lrc` / `.yrc` 文件，逐字高亮；支持播放器内歌词、桌面浮窗歌词和菜单栏歌词，可调字号、背景透明度、对齐方式、锁定位置与置顶，手动偏移校准；桌面歌词悬停控制条支持同步、打开主窗口、位置锁、点击穿透与关闭
- **歌单**：新建与编辑歌单，支持 `.m3u` 导入导出
- **曲库**：读取内嵌封面或同目录 `cover` / `folder` / `front` 图片；评分、收藏、搜索

## 支持格式

```
flac  mp3  m4a  mp4  aac  wav  aiff  aif  ogg  oga  opus
```

歌词文件与音频同名，后缀为 `.lrc` 或 `.yrc`。

## 系统要求

- macOS 26 或更高
- Apple Silicon（arm64）

## 安装

每次推送到 `main`，GitHub Actions 会自动构建 DMG：

1. 打开最近一次成功的 Actions 运行
2. 下载 `fmusic-dmg` 产物，解压得到 `fmusic.dmg`
3. 打开 DMG，把 `fmusic.app` 拖入「应用程序」

也可以直接从 [Releases](https://github.com/lemonevo/fmusic/releases) 下载 `fmusic.dmg`（打 `v*` tag 时会自动附加）。

安装包为 ad-hoc 签名，首次启动需要右键 →「打开」，或执行：

```bash
xattr -dr com.apple.quarantine /Applications/fmusic.app
```
