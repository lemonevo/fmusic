# fmusic 开发文档 / Developer Notes

本文件记录一些「不进设置界面、但开发者/维护者需要知道」的功能与入口。
fmusic 是自用项目，为保持设置界面简洁，以下内容已从「设置」窗口移除，改为在此文档说明。

---

## 1. 事件日志 Event Log

- 作用：查看运行期错误/告警/网络等事件（后台同步失败、歌词匹配失败、下载错误等都会记录）。
- 入口（开发者自行调用）：`appDelegate.eventLogger` / `EventLogSettingsView`。
  在代码里可临时用 `AppStoryboard` 或 SwiftUI `EventLogSettingsView()` 打开。
- 数据来源：`fmusicKit/Api/EventLogger.swift`；日志同时可通过「导出日志」得到 `fmusicLog.json`。

## 2. 导出日志 Export log

- 作用：打包一份 `fmusicLog.json`（应用信息 + 最近事件），用于反馈/排障。
- 实现：`SupportSettingsView.swift` 里的 `fmusicLogExport`（`Transferable`，按需生成）。
- 手动导出：需要时用 `ShareLink(item: fmusicLogExport())` 或在调试代码里直接写文件。

## 3. 第三方许可 Third-Party Licenses

- 内容：AudioStreaming 等第三方库的许可声明。
- 实现：`LicenseSettingsView.swift`（仍编译在包内，未在侧栏显示）。
- 仓库内另有 `LICENSE` 与 `Vendor/AudioStreaming/LICENSE`。

## 4. X-Callback URL

- 作用：通过 `fmusic://` 形式的 x-callback-url 触发播放/搜索等动作。
- 实现：`XCallbackURLsSetttingsView.swift` + `Intents/` 下的 App Intents。
- 主要 action：播放、暂停、下一首/上一首、搜索并播放、设置收藏/评分、切换在线离线等。

## 5. 开发者工具 Developer Tools（仅 DEBUG）

- 入口：`DeveloperView.swift`，只在 `#if DEBUG` 编译。
- 用途：快速切换主题色、触发测试数据等调试项。

## 6. 报告问题 / 版本信息

- 反馈地址：https://github.com/lemonevo/fmusic/issues
- 版本号 / 构建号：运行时取 `AppDelegate.version` / `AppDelegate.buildNumber`，
  也可在 `fmusic/Info.plist` 的 `CFBundleShortVersionString` / `CFBundleVersion` 查看。

---

## 附：如何临时把这些页面加回设置侧栏

如需在「设置」里重新显示：

1. `fmusic/SwiftUI/Settings/NavigationTarget.swift`
   - 在 `sidebarItems` 数组里加回 `.advanced`（高级，含事件日志/许可/X-Callback/开发者）或 `.support`（支持与关于）。
2. `fmusic/SwiftUI/Settings/SettingsTabView.swift`
   - 在 `sidebarSections` 里给对应 section 加回 `.advanced` / `.support`。
   - 在 `SettingsSearchCatalog.items` 里补回相应搜索项（可选）。

对应视图：`AdvancedSettingsView`（事件日志/许可/X-Callback/开发者）、
`SupportSettingsView`（报告问题/导出日志/版本）。
