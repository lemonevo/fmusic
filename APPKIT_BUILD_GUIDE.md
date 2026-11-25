# fmusic AppKit 版构建与打包说明

> 适用分支：`refactor/native-appkit-multiplatform`
> 目标产物：`fmusic.app` / `fmusic-appkit-<版本>-arm64.dmg`
> 当前版本：2.1.2（bundle id `lol.levo.fmusic`）

本文只讲**怎么把 AppKit 版编出来、打成 DMG、安装**。代码结构与后续优化见
[`HANDOFF_REMAINING_TASKS.md`](./HANDOFF_REMAINING_TASKS.md)，AI 协作文档见
[`AI_HANDOFF.md`](./AI_HANDOFF.md)。

---

## 1. 两个 target 的关系

仓库里有两套 macOS 实现，别搞混：

| 目录 | 说明 |
| --- | --- |
| `fmusic-macOS/` | **纯 AppKit 原生实现，当前开发目标**，scheme 为 `fmusic-macOS` |
| `fmusic/` | 原 **Mac Catalyst** 源码，**只读参考**，用于对照行为/像素，不要修改 |
| `Packages/FmusicKit/` | 跨平台核心（SwiftPM，`fmusicKit` 模块），两套 UI 共用 |
| `fmusic-iOS/` | iOS target 的 Info.plist（运行时验证尚未做） |

> ⚠️ 原版 Catalyst app（`/Applications/fmusic.app`）与 AppKit 版共享同一个
> bundle id `lol.levo.fmusic`。**按进程 PID 定位窗口，不能按 App 名称/bundle id**，
> 否则会误操作到对照实例。

---

## 2. 环境要求

- macOS + Xcode 27.1（Swift 6，macOS SDK 27）
- Apple Silicon（arm64）
- 项目 Deployment Target：macOS 14.0
- 无需 Apple 开发者账号：CI 与本说明均使用 **ad-hoc 签名**

---

## 3. 本地构建（Debug，用于测试）

```bash
cd /Users/apple/Downloads/ceshi/fmusic

# 1) 先编译核心包（可选，xcodebuild 也会处理）
cd Packages/FmusicKit && swift build && cd ../..

# 2) 构建 AppKit App
xcodebuild \
  -project fmusic.xcodeproj \
  -scheme fmusic-macOS \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/fm-mac-dd \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build
```

产物固定在：

```
/tmp/fm-mac-dd/Build/Products/Debug/fmusic.app
```

### 安装测试副本（不影响 /Applications 里的参考版）

```bash
pkill -f "fmusic-AppKit" 2>/dev/null; sleep 2
rm -rf ~/Applications/fmusic-AppKit.app            # 仅测试副本，可随时重建
cp -R /tmp/fm-mac-dd/Build/Products/Debug/fmusic.app ~/Applications/fmusic-AppKit.app
codesign --force --deep --sign - --identifier lol.levo.fmusic ~/Applications/fmusic-AppKit.app
open ~/Applications/fmusic-AppKit.app
```

---

## 4. 本地 Release + 打包 DMG（手动）

```bash
cd /Users/apple/Downloads/ceshi/fmusic

xcodebuild \
  -project fmusic.xcodeproj \
  -scheme fmusic-macOS \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  ARCHS=arm64 \
  build

APP="build/Build/Products/Release/fmusic.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
DMG="fmusic-appkit-${VERSION}-arm64.dmg"

# ad-hoc 签名：用真实 identifier，MediaRemote 才能正确识别、避免下载后提示“已损坏”
codesign --force --deep --sign - --identifier lol.levo.fmusic "$APP"
codesign --verify --deep --strict "$APP"

rm -rf dist && mkdir -p dist
cp -R "$APP" dist/
ln -s /Applications dist/Applications

hdiutil create -volname "fmusic (AppKit)" -srcfolder dist -ov -format UDZO "$DMG"
shasum -a 256 "$DMG" | tee "$DMG.sha256"
```

生成的就是可双击安装的 `fmusic-appkit-<版本>-arm64.dmg`（内含 app + `Applications` 快捷方式）。

---

## 5. GitHub Actions 自动构建（推荐）

工作流文件：[`.github/workflows/build-dmg-appkit.yml`](./.github/workflows/build-dmg-appkit.yml)

- **触发条件**：推送到 `refactor/native-appkit-multiplatform`，或在 Actions 页面手动 `Run workflow`
- **运行环境**：`macos-latest`
- **步骤**：Release 构建 → ad-hoc 签名 → 生成 DMG → 上传 artifact
- **产物（artifact）**：`fmusic-appkit-dmg`
  - `fmusic-appkit-<版本>-arm64.dmg`
  - `fmusic-appkit-<版本>-arm64.dmg.sha256`（保留 14 天）

获取方式：

1. 打开仓库 **Actions** → 选中最近一次成功的 `Build AppKit DMG` 运行
2. 页面底部 **Artifacts** 下载 `fmusic-appkit-dmg`
3. 解压即得 DMG

> 注意：本项目 `main` 分支的工作流对应的是 Catalyst/主分支产物（`fmusic-dmg`），
> AppKit 版请认准上面的 `Build AppKit DMG` 工作流与 `fmusic-appkit-dmg` 产物。

---

## 6. 安装与首次启动

1. 打开 DMG，把 `fmusic.app` 拖入「应用程序」
2. 安装包为 **ad-hoc 签名、未做 Apple 公证**，首次启动 Gatekeeper 可能拦截：
   - Finder 中右键 `fmusic.app` → **打开**；或
   - 终端执行去隔离属性：

```bash
xattr -dr com.apple.quarantine /Applications/fmusic.app
```

---

## 7. 校验方法（拿到 DMG 后自检）

```bash
# 挂载检查内容
hdiutil attach fmusic-appkit-2.1.2-arm64.dmg -nobrowse
ls -l /Volumes/"fmusic (AppKit)"        # 应含 fmusic.app 与 Applications -> /Applications

# 校验签名与架构
codesign -dv --verbose=2 "/Volumes/fmusic (AppKit)/fmusic.app"   # Identifier=lol.levo.fmusic, arm64, adhoc
codesign --verify --deep --strict "/Volumes/fmusic (AppKit)/fmusic.app"

hdiutil detach /Volumes/"fmusic (AppKit)"
```

---

## 8. 常见问题

- **SPM 依赖拉取失败（网络受限）**：给 `xcodebuild` 加 `-disableAutomaticPackageResolution`，或用已缓存的 DerivedData。
- **自动化/截图对错窗口**：Catalyst 参考版与 AppKit 版共用 bundle id，必须按 **PID** 定位窗口。
- **用户数据位置（构建/测试不要动）**：
  - `~/Library/Application Support/fmusic/fmusic.sqlite`（及 `-wal` / `-shm`）
  - `~/Library/lol.levo.fmusic`（封面等缓存）
  - `metadata-overrides.json`
- **删除文件用 `trash`**，不要用 `rm`（测试副本 `/tmp`、`~/Applications/fmusic-AppKit.app` 除外）。

---

## 9. 相关文档

- [`README.md`](./README.md)：功能特性与用户安装说明
- [`HANDOFF_REMAINING_TASKS.md`](./HANDOFF_REMAINING_TASKS.md)：AppKit 移植剩余优化任务与构建/自动化细节
- [`AI_HANDOFF.md`](./AI_HANDOFF.md)：给接手 AI 的项目综述
- [`DEVELOPER_NOTES.md`](./DEVELOPER_NOTES.md)：开发笔记
