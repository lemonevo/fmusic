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

/// Settings sidebar mirroring Catalyst's `SettingsTabView`:
/// floating window controls, “Back to App”, a search field, and grouped rows.
@MainActor
final class SettingsSidebarViewController: NSViewController {
  var onSelectionChanged: ((SettingsPage) -> Void)?
  var onToggleSidebar: (() -> Void)?

  private struct Section {
    let title: String
    let pages: [SettingsPage]
  }

  private enum Row {
    case header(String)
    case page(SettingsPage)
    case spacer
  }

  private static let standaloneSections: [Section] = [
    Section(title: L10n.tr("Settings"), pages: [.general, .account]),
    Section(title: L10n.tr("Playback"), pages: [.playback, .equalizer]),
    Section(title: L10n.tr("Appearance"), pages: [.lyrics, .displayInteraction]),
    Section(
      title: L10n.tr("Library"),
      pages: [.storage, .library]
    ),
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

  private let searchCatalog: [(page: SettingsPage, keywords: [String])] = [
    (.general, ["language", "offline", "screen lock", "语言", "离线", "锁屏", "外观"]),
    (.account, ["account", "server", "url", "username", "账号", "服务器", "用户名"]),
    (.playback, ["playback", "volume", "crossfade", "播放", "音量", "淡入淡出"]),
    (.equalizer, ["equalizer", "eq", "均衡器"]),
    (.lyrics, ["lyrics", "歌词"]),
    (.displayInteraction, ["display", "appearance", "显示", "外观"]),
    (.storage, ["storage", "cache", "artwork", "存储", "缓存", "封面"]),
    (.library, ["library", "playlists", "artists", "albums", "songs", "资料库", "播放列表", "艺人", "专辑", "歌曲"]),
    (.support, ["support", "about", "支持", "关于"]),
    (.developer, ["developer", "开发者"]),
    (.about, ["about", "关于"]),
  ]

  private let tableView = NSTableView()
  private let scrollView = NSScrollView()
  private let searchField = NSSearchField()
  private let searchContainer = SettingsBackgroundView()
  private let toggleButton = SidebarTitleButton()

  private let cellIdentifier = NSUserInterfaceItemIdentifier("SettingsSidebarCell")
  private let headerIdentifier = NSUserInterfaceItemIdentifier("SettingsSidebarHeader")
  private let columnIdentifier = NSUserInterfaceItemIdentifier("SettingsSidebarColumn")

  private var filteredRows: [Row] = []
  private var isShowingSearchResults = false

  override func loadView() {
    let root = SettingsBackgroundView()
    root.backgroundColor = MacTheme.sidebarBackgroundColor

    let column = NSTableColumn(identifier: columnIdentifier)
    column.resizingMask = .autoresizingMask
    tableView.addTableColumn(column)
    tableView.headerView = nil
    tableView.style = .fullWidth
    tableView.selectionHighlightStyle = .regular
    tableView.rowSizeStyle = .custom
    tableView.backgroundColor = .clear
    tableView.focusRingType = .none
    tableView.dataSource = self
    tableView.delegate = self
    tableView.target = self
    tableView.doubleAction = #selector(activateSelectedRow)

    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = false
    scrollView.drawsBackground = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.automaticallyAdjustsContentInsets = false
    // Without the Back to App row the field gets the same breathing room as the
    // Catalyst settings sidebar before the first group header.
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
    searchContainer.addSubview(searchField)
    searchContainer.backgroundColor = MacTheme.searchFieldBackgroundColor
    searchContainer.cornerRadius = 7
    searchContainer.translatesAutoresizingMaskIntoConstraints = false

    // Circular sidebar toggle in the top-right of the sidebar, like the Catalyst scene.
    toggleButton.content = .symbol("sidebar.left")
    toggleButton.toolTip = L10n.tr("Show Sidebar")
    toggleButton.onClick = { [weak self] in self?.onToggleSidebar?() }
    toggleButton.translatesAutoresizingMaskIntoConstraints = false

    root.addSubview(searchContainer)
    root.addSubview(toggleButton)
    root.addSubview(scrollView)

    NSLayoutConstraint.activate([
      toggleButton.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
      toggleButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
      toggleButton.widthAnchor.constraint(equalToConstant: 36),
      toggleButton.heightAnchor.constraint(equalToConstant: 36),

      searchContainer.topAnchor.constraint(equalTo: root.topAnchor, constant: 52),
      searchContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
      searchContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
      searchContainer.heightAnchor.constraint(equalToConstant: 28),

      searchField.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 8),
      searchField.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: -6),
      searchField.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),

      scrollView.topAnchor.constraint(equalTo: root.topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
    ])

    self.view = root
    refreshRows()
  }

  // MARK: - Selection

  func select(page: SettingsPage) {
    guard let row = filteredRows.firstIndex(where: {
      if case let .page(candidate) = $0 { return candidate == page }
      return false
    }) else { return }
    tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    tableView.scrollRowToVisible(row)
  }

  // MARK: - Search

  @objc
  private func searchChanged() {
    refreshRows()
  }

  private func refreshRows() {
    let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    isShowingSearchResults = !query.isEmpty
    if query.isEmpty {
      filteredRows = Self.rows
    } else {
      let matches = searchCatalog.filter { entry in
        entry.page.title.localizedStandardContains(query) ||
          entry.keywords.contains { $0.localizedStandardContains(query) }
      }
      filteredRows = matches.isEmpty
        ? [.header(L10n.tr("No Settings Found"))]
        : matches.map { .page($0.page) }
    }
    tableView.reloadData()
  }

  @objc
  private func activateSelectedRow() {
    let row = tableView.clickedRow
    guard row >= 0, row < filteredRows.count else { return }
    if case let .page(page) = filteredRows[row] { onSelectionChanged?(page) }
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
    case .spacer: return 10
    }
  }

  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    guard row >= 0, row < filteredRows.count,
          case .page = filteredRows[row] else { return nil }
    return SidebarRowView()
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
        as? SidebarTableCellView ?? SidebarTableCellView(frame: .zero, usesMediumText: true, supportsDragHandle: false)
      cell.identifier = cellIdentifier
      cell.configure(symbolName: page.symbolName, title: page.title)
      return cell
    case .spacer:
      return NSView()
    }
  }
}

// MARK: - NSTableViewDelegate

extension SettingsSidebarViewController: NSTableViewDelegate {
  func tableViewSelectionDidChange(_ notification: Notification) {
    let row = tableView.selectedRow
    guard row >= 0, row < filteredRows.count else { return }
    if case let .page(page) = filteredRows[row] { onSelectionChanged?(page) }
  }
}

// MARK: - Settings side deferential rows are provided by SidebarStyle.
