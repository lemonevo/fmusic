//
//  SettingsSidebarViewController.swift
//  fmusic-macOS
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import AppKit
import fmusicKit

// MARK: - SettingsSearchItem

private struct SettingsSearchItem {
  let title: String
  let page: SettingsPage
  let keywords: [String]

  init(_ title: String, _ page: SettingsPage, keywords: [String] = []) {
    self.title = title
    self.page = page
    self.keywords = keywords
  }
}

// MARK: - SettingsSearchCatalog

@MainActor
private enum SettingsSearchCatalog {
  static let items: [SettingsSearchItem] = [
    // General
    .init(L10n.tr("Language"), .general, keywords: ["language", "语言", "中文", "english"]),
    .init(L10n.tr("Offline Mode"), .general, keywords: ["offline", "离线"]),
    .init(
      L10n.tr("Prevent Screen Lock"),
      .general,
      keywords: ["screen lock", "sleep", "锁屏", "防止屏幕锁定"]
    ),

    // Account
    .init("URL", .account, keywords: ["server", "服务器", "地址"]),
    .init(L10n.tr("Username"), .account, keywords: ["username", "用户名"]),
    .init(L10n.tr("Backend API"), .account, keywords: ["backend", "api", "后端", "webdav"]),
    .init(
      L10n.tr("Resync Library"),
      .account,
      keywords: ["resync", "scan", "重新同步", "扫描"]
    ),
    .init(L10n.tr("Logout"), .account, keywords: ["logout", "退出登录"]),
    .init(L10n.tr("Add Account"), .account, keywords: ["add account", "添加账户"]),

    // Playback
    .init(L10n.tr("Crossfade"), .playback, keywords: ["crossfade", "fade", "淡入淡出"]),
    .init(
      L10n.tr("Auto-cache played tracks and download upcoming ones"),
      .playback,
      keywords: ["cache", "download", "缓存", "预下载"]
    ),
    .init(
      L10n.tr("Song Playback Resume"),
      .playback,
      keywords: ["resume", "续播", "记忆播放"]
    ),
    .init(L10n.tr("Manual Playback"), .playback, keywords: ["manual", "手动播放"]),
    .init(
      L10n.tr("Autoplay After End"),
      .playback,
      keywords: ["autoplay", "instant mix", "自动播放"]
    ),
    .init(
      L10n.tr("Music Player Skip Buttons"),
      .playback,
      keywords: ["skip", "快进", "快退"]
    ),
    .init(
      L10n.tr("Disable Player Shuffle Button"),
      .playback,
      keywords: ["shuffle", "random", "随机", "随机播放"]
    ),

    // Audio & Effects
    .init(
      L10n.tr("Enable ReplayGain"),
      .equalizer,
      keywords: ["replaygain", "loudness", "响度"]
    ),
    .init(L10n.tr("Equalizer"), .equalizer, keywords: ["equalizer", "eq", "均衡器", "音效"]),

    // Lyrics
    .init(
      L10n.tr("Desktop Lyrics"),
      .lyrics,
      keywords: ["desktop lyrics", "lyrics", "桌面歌词"]
    ),
    .init(
      L10n.tr("Desktop Lyrics Font Size"),
      .lyrics,
      keywords: ["font size", "字号", "字体大小"]
    ),
    .init(L10n.tr("Alignment"), .lyrics, keywords: ["align", "对齐"]),
    .init(
      L10n.tr("Background Opacity"),
      .lyrics,
      keywords: ["opacity", "transparent", "透明度", "背景"]
    ),
    .init(
      L10n.tr("Show Next Line"),
      .lyrics,
      keywords: ["next line", "下一句"]
    ),
    .init(
      L10n.tr("Always on Top"),
      .lyrics,
      keywords: ["always on top", "置顶"]
    ),
    .init(
      L10n.tr("Lock Desktop Lyrics"),
      .lyrics,
      keywords: ["lock", "click through", "锁定", "鼠标穿透"]
    ),
    .init(
      L10n.tr("Menu Bar Lyrics"),
      .lyrics,
      keywords: ["menu bar", "lyrics", "菜单栏歌词", "任务栏歌词"]
    ),
    .init(
      L10n.tr("Lyrics Smooth Scrolling"),
      .lyrics,
      keywords: ["lyrics", "scroll", "歌词", "滚动"]
    ),

    // Display
    .init(
      L10n.tr("Appearance"),
      .displayInteraction,
      keywords: ["appearance", "dark", "light", "外观", "深色", "浅色"]
    ),
    .init(
      L10n.tr("Liquid Glass"),
      .displayInteraction,
      keywords: ["liquid glass", "transparency", "depth", "液态玻璃", "透明度", "层次", "柔和", "标准", "通透"]
    ),
    .init(
      L10n.tr("Theme Color"),
      .displayInteraction,
      keywords: ["theme", "color", "主题颜色", "配色"]
    ),
    .init(
      L10n.tr("Artwork Display"),
      .displayInteraction,
      keywords: ["artwork", "cover", "封面显示"]
    ),
    .init(
      L10n.tr("App Icon"),
      .displayInteraction,
      keywords: ["app icon", "icon", "应用图标", "图标"]
    ),

    // Storage & Artwork
    .init(L10n.tr("Cached Songs"), .storage, keywords: ["cached", "缓存"]),
    .init(
      L10n.tr("Complete Cache Size"),
      .storage,
      keywords: ["cache size", "缓存大小"]
    ),
    .init(
      L10n.tr("Cache Size Limit"),
      .storage,
      keywords: ["cache limit", "缓存上限"]
    ),
    .init(
      L10n.tr("Automatically Clean Cache"),
      .storage,
      keywords: ["clean", "evict", "自动清理缓存"]
    ),
    .init(
      L10n.tr("Download all songs in library"),
      .storage,
      keywords: ["download all", "全部下载"]
    ),
    .init(
      L10n.tr("Delete downloaded songs"),
      .storage,
      keywords: ["delete", "cache", "删除缓存"]
    ),
    .init(
      L10n.tr("Artwork & Cache"),
      .storage,
      keywords: ["artwork", "cover", "封面", "缓存"]
    ),

    // Library
    .init(L10n.tr("Playlists"), .library, keywords: ["playlists", "播放列表"]),
    .init(L10n.tr("Artists"), .library, keywords: ["artists", "艺人"]),
    .init(L10n.tr("Albums"), .library, keywords: ["albums", "专辑"]),
    .init(L10n.tr("Songs"), .library, keywords: ["songs", "歌曲"]),
    .init(L10n.tr("Synchronization"), .library, keywords: ["sync", "同步"]),

    // Support / Developer / About
    .init(L10n.tr("Event Log"), .support, keywords: ["event", "log", "日志", "支持"]),
    .init(L10n.tr("Export log"), .support, keywords: ["export", "log", "导出日志"]),
    .init(L10n.tr("Diagnostics"), .developer, keywords: ["diagnostics", "developer", "诊断", "开发者"]),
    .init(L10n.tr("Version"), .about, keywords: ["version", "about", "版本", "关于"]),
  ]
}

// MARK: - SettingsSidebarViewController

/// Settings sidebar mirroring Catalyst's `SettingsTabView`:
/// search field with item-level grouped results, hover/selection feedback, and grouped rows.
@MainActor
final class SettingsSidebarViewController: NSViewController {
  var onSelectionChanged: ((SettingsPage) -> Void)?

  private struct Section {
    let title: String
    let pages: [SettingsPage]
  }

  private enum Row {
    case header(String)
    case page(SettingsPage)
    case searchResult(SettingsSearchItem)
    case spacer
  }

  private static let standaloneSections: [Section] = [
    Section(title: L10n.tr("Settings"), pages: [.general, .account]),
    Section(title: L10n.tr("Playback"), pages: [.playback, .equalizer]),
    Section(title: L10n.tr("Appearance"), pages: [.lyrics, .displayInteraction]),
    Section(title: L10n.tr("Library"), pages: [.storage, .library]),
  ]

  /// Flattened table rows: header, pages, then a compact gap before the next group.
  private static let rows: [Row] = {
    var result: [Row] = []
    for (index, section) in standaloneSections.enumerated() {
      result.append(.header(section.title))
      result.append(contentsOf: section.pages.map(Row.page))
      if index < standaloneSections.count - 1 { result.append(.spacer) }
    }
    return result
  }()

  private let tableView = NSTableView()
  private let scrollView = NSScrollView()
  private let searchField = NSSearchField()
  private let searchIcon = NSImageView()
  private let clearButton = NSButton()
  private let searchContainer = SettingsBackgroundView()

  private let cellIdentifier = NSUserInterfaceItemIdentifier("SettingsSidebarCell")
  private let headerIdentifier = NSUserInterfaceItemIdentifier("SettingsSidebarHeader")
  private let searchResultIdentifier = NSUserInterfaceItemIdentifier("SettingsSidebarSearchResult")
  private let columnIdentifier = NSUserInterfaceItemIdentifier("SettingsSidebarColumn")

  private var filteredRows: [Row] = []
  private var isShowingSearchResults = false
  private var isSearchFocused = false
  private var lastSearchQuery: String?
  private var isUpdatingSelection = false
  private var selectedPage: SettingsPage = .general

  override func loadView() {
    let root = SettingsBackgroundView()
    root.backgroundColor = MacTheme.sidebarBackgroundColor

    let column = NSTableColumn(identifier: columnIdentifier)
    column.resizingMask = .autoresizingMask
    tableView.addTableColumn(column)
    tableView.headerView = nil
    tableView.style = .fullWidth
    tableView.selectionHighlightStyle = .regular
    tableView.allowsEmptySelection = true
    tableView.rowSizeStyle = .custom
    tableView.backgroundColor = .clear
    tableView.focusRingType = .none
    tableView.dataSource = self
    tableView.delegate = self
    tableView.target = self
    tableView.action = #selector(activateSelectedRow)
    tableView.doubleAction = #selector(activateSelectedRow)

    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.automaticallyAdjustsContentInsets = false
    scrollView.contentInsets = NSEdgeInsets(top: 92, left: 0, bottom: 10, right: 0)

    searchField.placeholderString = L10n.tr("Search Settings")
    searchField.isBezeled = false
    searchField.drawsBackground = false
    searchField.focusRingType = .none
    searchField.font = .systemFont(ofSize: 13)
    searchField.textColor = .labelColor
    searchField.translatesAutoresizingMaskIntoConstraints = false
    searchField.target = self
    searchField.action = #selector(searchChanged)
    searchField.delegate = self
    searchField.sendsSearchStringImmediately = true
    searchField.sendsWholeSearchString = false
    searchField.isEditable = true
    searchField.isSelectable = true
    if let cell = searchField.cell as? NSSearchFieldCell {
      cell.searchButtonCell = nil
      cell.cancelButtonCell = nil
    }

    searchIcon.image = NSImage(
      systemSymbolName: "magnifyingglass",
      accessibilityDescription: nil
    )?.withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
    searchIcon.contentTintColor = .secondaryLabelColor
    searchIcon.imageScaling = .scaleProportionallyDown
    searchIcon.translatesAutoresizingMaskIntoConstraints = false

    clearButton.image = NSImage(
      systemSymbolName: "xmark.circle.fill",
      accessibilityDescription: L10n.tr("Clear")
    )?.withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
    clearButton.isBordered = false
    clearButton.bezelStyle = .regularSquare
    clearButton.imagePosition = .imageOnly
    clearButton.contentTintColor = .secondaryLabelColor
    clearButton.target = self
    clearButton.action = #selector(clearSearch)
    clearButton.isHidden = true
    clearButton.translatesAutoresizingMaskIntoConstraints = false

    searchContainer.addSubview(searchIcon)
    searchContainer.addSubview(searchField)
    searchContainer.addSubview(clearButton)
    searchContainer.backgroundColor = Self.searchFieldBackgroundColor
    searchContainer.cornerRadius = 7
    updateSearchContainerAppearance()
    searchContainer.translatesAutoresizingMaskIntoConstraints = false

    root.addSubview(scrollView)
    root.addSubview(searchContainer)

    NSLayoutConstraint.activate([
      searchContainer.topAnchor.constraint(equalTo: root.topAnchor, constant: 52),
      searchContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
      searchContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
      searchContainer.heightAnchor.constraint(equalToConstant: 28),

      searchIcon.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 8),
      searchIcon.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
      searchIcon.widthAnchor.constraint(equalToConstant: 14),
      searchIcon.heightAnchor.constraint(equalToConstant: 14),

      clearButton.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: -6),
      clearButton.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
      clearButton.widthAnchor.constraint(equalToConstant: 16),
      clearButton.heightAnchor.constraint(equalToConstant: 16),

      searchField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 6),
      searchField.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -4),
      searchField.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),

      scrollView.topAnchor.constraint(equalTo: root.topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
    ])

    self.view = root
    refreshRows()
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(themeColorChanged),
      name: .macThemeColorChanged,
      object: nil
    )
  }

  deinit { NotificationCenter.default.removeObserver(self) }

  private static var searchFieldBackgroundColor: NSColor {
    NSColor(name: nil) { appearance in
      let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      return isDark
        ? NSColor.white.withAlphaComponent(0.08)
        : NSColor.white.withAlphaComponent(0.88)
    }
  }

  private func updateSearchContainerAppearance() {
    if isSearchFocused {
      searchContainer.borderColor = MacTheme.accentColor.withAlphaComponent(0.45)
      searchContainer.borderWidth = 1
    } else {
      searchContainer.borderColor = NSColor.labelColor.withAlphaComponent(0.08)
      searchContainer.borderWidth = 0.5
    }
  }

  @objc
  private func themeColorChanged() {
    updateSearchContainerAppearance()
    tableView.reloadData()
    restorePageSelection()
  }

  // MARK: - Selection

  func select(page: SettingsPage) {
    selectedPage = page
    restorePageSelection()
  }

  private func restorePageSelection() {
    guard !isShowingSearchResults else { return }
    guard let row = filteredRows.firstIndex(where: {
      if case let .page(candidate) = $0 { return candidate == selectedPage }
      return false
    }) else { return }
    isUpdatingSelection = true
    tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    tableView.scrollRowToVisible(row)
    isUpdatingSelection = false
  }

  // MARK: - Search

  @objc
  private func searchChanged() {
    refreshRows()
  }

  @objc
  private func clearSearch() {
    searchField.stringValue = ""
    refreshRows(force: true)
    view.window?.makeFirstResponder(tableView)
  }

  private func refreshRows(force: Bool = false) {
    let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    clearButton.isHidden = query.isEmpty
    guard force || query != lastSearchQuery else { return }
    lastSearchQuery = query
    isShowingSearchResults = !query.isEmpty
    if query.isEmpty {
      filteredRows = Self.rows
      tableView.allowsEmptySelection = false
    } else {
      tableView.allowsEmptySelection = true
      var groups: [(page: SettingsPage, items: [SettingsSearchItem])] = []
      for page in SettingsPage.allCases {
        let pageItems = SettingsSearchCatalog.items.filter { $0.page == page }
        let matches: [SettingsSearchItem]
        if page.title.localizedStandardContains(query) {
          matches = pageItems.isEmpty ? [SettingsSearchItem(page.title, page)] : pageItems
        } else {
          matches = pageItems.filter { item in
            item.title.localizedStandardContains(query) ||
              item.keywords.contains { $0.localizedStandardContains(query) }
          }
        }
        if !matches.isEmpty {
          groups.append((page, matches))
        }
      }
      // Pages whose own title matches lead the results.
      let pageMatches = groups.filter { $0.page.title.localizedStandardContains(query) }
      let itemMatches = groups.filter { !$0.page.title.localizedStandardContains(query) }
      let ordered = pageMatches + itemMatches

      if ordered.isEmpty {
        filteredRows = [.header(L10n.tr("No Settings Found"))]
      } else {
        var rows: [Row] = []
        for (index, group) in ordered.enumerated() {
          rows.append(.header(group.page.title))
          rows.append(contentsOf: group.items.map(Row.searchResult))
          if index < ordered.count - 1 { rows.append(.spacer) }
        }
        filteredRows = rows
      }
    }
    tableView.reloadData()
    restorePageSelection()
  }

  private func openSearchResult(_ item: SettingsSearchItem) {
    selectedPage = item.page
    onSelectionChanged?(item.page)
    searchField.stringValue = ""
    refreshRows(force: true)
    view.window?.makeFirstResponder(tableView)
  }

  private func openFirstSearchResult() {
    guard isShowingSearchResults else { return }
    for row in filteredRows {
      if case let .searchResult(item) = row {
        openSearchResult(item)
        return
      }
    }
  }

  @objc
  private func activateSelectedRow() {
    let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
    guard row >= 0, row < filteredRows.count else { return }
    switch filteredRows[row] {
    case let .page(page):
      selectedPage = page
      onSelectionChanged?(page)
    case let .searchResult(item):
      openSearchResult(item)
    case .header, .spacer:
      break
    }
  }
}

// MARK: - NSTableViewDataSource

extension SettingsSidebarViewController: NSTableViewDataSource {
  func numberOfRows(in tableView: NSTableView) -> Int {
    filteredRows.count
  }

  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    guard row >= 0, row < filteredRows.count else { return 0 }
    switch filteredRows[row] {
    case .header: return SidebarStyle.sectionRowHeight
    case .page: return SidebarStyle.rowHeight
    case .searchResult: return 32
    case .spacer: return 10
    }
  }

  func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
    guard row >= 0, row < filteredRows.count else { return false }
    switch filteredRows[row] {
    case .page, .searchResult: return true
    case .header, .spacer: return false
    }
  }

  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    guard row >= 0, row < filteredRows.count else { return nil }
    switch filteredRows[row] {
    case .page, .searchResult:
      return HoverableSidebarRowView()
    case .header, .spacer:
      return nil
    }
  }

  func tableView(
    _ tableView: NSTableView,
    viewFor tableColumn: NSTableColumn?,
    row: Int
  )
    -> NSView? {
    guard row >= 0, row < filteredRows.count else { return nil }
    switch filteredRows[row] {
    case let .header(title):
      let header = tableView.makeView(withIdentifier: headerIdentifier, owner: self)
        as? SidebarSectionCellView ?? SidebarSectionCellView()
      header.identifier = headerIdentifier
      header.title = title
      return header
    case let .page(page):
      let cell = tableView.makeView(withIdentifier: cellIdentifier, owner: self)
        as? SidebarTableCellView ?? SidebarTableCellView(
          frame: .zero,
          usesMediumText: true,
          supportsDragHandle: false
        )
      cell.identifier = cellIdentifier
      cell.configure(symbolName: page.symbolName, title: page.title)
      return cell
    case let .searchResult(item):
      let cell = tableView.makeView(withIdentifier: searchResultIdentifier, owner: self)
        as? SettingsSearchResultCellView ?? SettingsSearchResultCellView()
      cell.identifier = searchResultIdentifier
      cell.configure(title: item.title)
      return cell
    case .spacer:
      return NSView()
    }
  }
}

// MARK: - NSTableViewDelegate

extension SettingsSidebarViewController: NSTableViewDelegate {
  func tableViewSelectionDidChange(_ notification: Notification) {
    guard !isUpdatingSelection else { return }
    let row = tableView.selectedRow
    guard row >= 0, row < filteredRows.count else { return }
    switch filteredRows[row] {
    case let .page(page):
      selectedPage = page
      onSelectionChanged?(page)
    case let .searchResult(item):
      openSearchResult(item)
    case .header, .spacer:
      break
    }
  }
}

// MARK: - Live search

extension SettingsSidebarViewController: NSSearchFieldDelegate {
  func controlTextDidBeginEditing(_ obj: Notification) {
    isSearchFocused = true
    updateSearchContainerAppearance()
  }

  func controlTextDidEndEditing(_ obj: Notification) {
    isSearchFocused = false
    updateSearchContainerAppearance()
  }

  func controlTextDidChange(_ obj: Notification) {
    refreshRows()
  }

  func control(
    _ control: NSControl,
    textView: NSTextView,
    doCommandBy commandSelector: Selector
  )
    -> Bool {
    if commandSelector == #selector(NSResponder.insertNewline(_:)) {
      openFirstSearchResult()
      return true
    }
    if commandSelector == #selector(NSResponder.cancelOperation(_:)),
       !searchField.stringValue.isEmpty {
      clearSearch()
      return true
    }
    return false
  }
}

// MARK: - HoverableSidebarRowView

@MainActor
private final class HoverableSidebarRowView: SidebarRowView {
  private var isHovered = false
  private var trackingArea: NSTrackingArea?

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea {
      removeTrackingArea(trackingArea)
    }
    let area = NSTrackingArea(
      rect: bounds,
      options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(area)
    trackingArea = area
  }

  override func mouseEntered(with event: NSEvent) {
    super.mouseEntered(with: event)
    isHovered = true
    needsDisplay = true
  }

  override func mouseExited(with event: NSEvent) {
    super.mouseExited(with: event)
    isHovered = false
    needsDisplay = true
  }

  override func drawBackground(in dirtyRect: NSRect) {
    super.drawBackground(in: dirtyRect)
    guard isHovered, !isSelected else { return }
    let rect = bounds.insetBy(dx: horizontalInset, dy: 2)
    MacTheme.sidebarSelectionColor.withAlphaComponent(0.55).setFill()
    NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
  }
}

// MARK: - SettingsSearchResultCellView

@MainActor
private final class SettingsSearchResultCellView: NSTableCellView {
  private let label = NSTextField(labelWithString: "")

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    label.font = SidebarStyle.bodyFont
    label.textColor = .labelColor
    label.lineBreakMode = .byTruncatingTail
    label.translatesAutoresizingMaskIntoConstraints = false
    addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(
        equalTo: leadingAnchor,
        constant: SidebarStyle.iconLeading
      ),
      label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  required init?(coder: NSCoder) {
    nil
  }

  func configure(title: String) {
    label.stringValue = title
  }
}
