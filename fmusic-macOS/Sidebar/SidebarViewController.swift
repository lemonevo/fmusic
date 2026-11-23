//
//  SidebarViewController.swift
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

/// Apple Music style source list (search/home + library section) with an account footer.
@MainActor
final class SidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
  var onSelectionChanged: ((SidebarItem) -> Void)?
  var onToggleSidebar: (() -> Void)?
  var onEditHome: (() -> Void)?
  var onOpenSettings: (() -> Void)?

  private enum Row {
    case section(String)
    case item(SidebarItem)
  }

  private let rows: [Row] = [
    .item(.search),
    .item(.home),
    .section(L10n.tr("Library")),
    .item(.songs),
    .item(.artists),
    .item(.albums),
    .item(.newestAlbums),
    .item(.recentlyPlayed),
    .item(.lyricsSearch),
    .item(.favoriteSongs),
    .item(.playlists),
    .item(.podcasts),
    .item(.directories),
    .item(.radios),
    .item(.downloads),
  ]

  private let tableView = NSTableView()
  private let scrollView = NSScrollView()
  private let accountLabel = NSTextField(labelWithString: "")
  private let editButton = NSButton()
  private let sidebarButton = NSButton()
  private let accountAvatar = AvatarView()

  private let cellIdentifier = NSUserInterfaceItemIdentifier("SidebarCell")
  private let groupIdentifier = NSUserInterfaceItemIdentifier("SidebarGroup")
  private let columnIdentifier = NSUserInterfaceItemIdentifier("SidebarColumn")

  override func loadView() {
    let root = SidebarBackgroundView()
    root.wantsLayer = true
    root.layer?.backgroundColor = MacTheme.sidebarBackgroundColor.cgColor

    // 1 px divider flush with the sidebar's trailing edge. It lives inside the sidebar
    // column so it tracks the split position automatically (resize, collapse, drag)
    // without the main controller having to lay it out.
    let divider = ColumnSeparatorView()
    divider.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(divider)

    let column = NSTableColumn(identifier: columnIdentifier)
    column.resizingMask = .autoresizingMask
    tableView.addTableColumn(column)
    tableView.headerView = nil
    tableView.style = .fullWidth
    tableView.selectionHighlightStyle = .regular
    tableView.rowSizeStyle = .custom
    tableView.floatsGroupRows = false
    tableView.backgroundColor = .clear
    tableView.dataSource = self
    tableView.delegate = self

    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = false
    scrollView.drawsBackground = false
    scrollView.automaticallyAdjustsContentInsets = false
    scrollView.contentInsets = NSEdgeInsets(top: 38, left: 0, bottom: 4, right: 0)
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    // Top bar: 编辑 + sidebar toggle, floating over the sidebar surface.
    editButton.title = L10n.tr("Edit")
    editButton.isBordered = false
    editButton.bezelStyle = .regularSquare
    editButton.font = .systemFont(ofSize: 13, weight: .medium)
    editButton.contentTintColor = .labelColor
    editButton.wantsLayer = true
    editButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
    editButton.layer?.cornerRadius = 15
    editButton.target = self
    editButton.action = #selector(editPressed)
    editButton.translatesAutoresizingMaskIntoConstraints = false

    sidebarButton.image = NSImage(
      systemSymbolName: "sidebar.left",
      accessibilityDescription: L10n.tr("Show Sidebar")
    )
    sidebarButton.isBordered = false
    sidebarButton.bezelStyle = .regularSquare
    sidebarButton.imagePosition = .imageOnly
    sidebarButton.contentTintColor = .labelColor
    sidebarButton.wantsLayer = true
    sidebarButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
    sidebarButton.layer?.cornerRadius = 15
    sidebarButton.target = self
    sidebarButton.action = #selector(sidebarPressed)
    sidebarButton.translatesAutoresizingMaskIntoConstraints = false

    let footer = makeAccountFooter()
    root.addSubview(editButton)
    root.addSubview(sidebarButton)
    root.addSubview(scrollView)
    root.addSubview(footer)
    NSLayoutConstraint.activate([
      // Matches the Catalyst titlebar: 编辑 52×36 at x≈108, 边栏 44×36 right after it,
      // both centred on the traffic-light baseline (26 pt from the window top).
      editButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 108),
      editButton.centerYAnchor.constraint(equalTo: root.topAnchor, constant: 26),
      editButton.heightAnchor.constraint(equalToConstant: 36),
      editButton.widthAnchor.constraint(equalToConstant: 52),
      sidebarButton.leadingAnchor.constraint(equalTo: editButton.trailingAnchor, constant: 2),
      sidebarButton.centerYAnchor.constraint(equalTo: editButton.centerYAnchor),
      sidebarButton.widthAnchor.constraint(equalToConstant: 44),
      sidebarButton.heightAnchor.constraint(equalToConstant: 36),
    ])

    NSLayoutConstraint.activate([
      divider.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      divider.topAnchor.constraint(equalTo: root.topAnchor),
      divider.bottomAnchor.constraint(equalTo: root.bottomAnchor),
      divider.widthAnchor.constraint(equalToConstant: 1),

      scrollView.topAnchor.constraint(equalTo: root.topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor),

      footer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      footer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      footer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
      footer.heightAnchor.constraint(equalToConstant: 56),
    ])

    self.view = root
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    selectRow(for: .home)
    updateAccountFooter()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(themeColorChanged),
      name: .macThemeColorChanged,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(accountChanged),
      name: .accountActiveChanged,
      object: nil
    )
  }

  // MARK: - Footer

  // MARK: - Top bar actions

  @objc
  private func editPressed() {
    let menu = NSMenu()
    let home = NSMenuItem(
      title: L10n.tr("Edit Home"),
      action: #selector(editHomePressed),
      keyEquivalent: ""
    )
    home.target = self
    menu.addItem(home)
    let settings = NSMenuItem(
      title: L10n.tr("Settings…"),
      action: #selector(settingsPressed),
      keyEquivalent: ""
    )
    settings.target = self
    menu.addItem(settings)
    menu.popUp(
      positioning: nil,
      at: NSPoint(x: editButton.bounds.midX, y: editButton.bounds.minY - 4),
      in: editButton
    )
  }

  @objc
  private func editHomePressed() {
    onEditHome?()
  }

  @objc
  private func settingsPressed() {
    onOpenSettings?()
  }

  @objc
  private func sidebarPressed() {
    onToggleSidebar?()
  }

  private func makeAccountFooter() -> NSView {
    let footer = NSView()
    footer.translatesAutoresizingMaskIntoConstraints = false
    footer.wantsLayer = true

    accountAvatar.translatesAutoresizingMaskIntoConstraints = false
    accountLabel.font = .systemFont(ofSize: MacTheme.bodyFontSize, weight: .semibold)
    accountLabel.lineBreakMode = .byTruncatingTail
    accountLabel.translatesAutoresizingMaskIntoConstraints = false

    let settingsButton = NSButton()
    settingsButton.image = NSImage(
      systemSymbolName: "gearshape",
      accessibilityDescription: L10n.tr("Settings")
    )
    settingsButton.isBordered = false
    settingsButton.bezelStyle = .regularSquare
    settingsButton.contentTintColor = .secondaryLabelColor
    settingsButton.target = self
    settingsButton.action = #selector(openSettings)
    settingsButton.translatesAutoresizingMaskIntoConstraints = false

    footer.addSubview(accountAvatar)
    footer.addSubview(accountLabel)
    footer.addSubview(settingsButton)

    NSLayoutConstraint.activate([
      accountAvatar.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 14),
      accountAvatar.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
      accountAvatar.widthAnchor.constraint(equalToConstant: 26),
      accountAvatar.heightAnchor.constraint(equalToConstant: 26),

      accountLabel.leadingAnchor.constraint(equalTo: accountAvatar.trailingAnchor, constant: 8),
      accountLabel.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
      accountLabel.trailingAnchor.constraint(lessThanOrEqualTo: settingsButton.leadingAnchor, constant: -8),

      settingsButton.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -12),
      settingsButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
      settingsButton.widthAnchor.constraint(equalToConstant: 22),
      settingsButton.heightAnchor.constraint(equalToConstant: 22),
    ])
    return footer
  }

  private func updateAccountFooter() {
    let storage = FmusicKit.shared.storage
    let accountInfo = storage.settings.accounts.active
    let name = accountInfo
      .flatMap { storage.settings.accounts.getSetting($0).read.loginCredentials?.username } ?? "—"
    accountLabel.stringValue = name
    accountAvatar.displayName = name
    if let accountInfo {
      accountAvatar.color = storage.settings.accounts.getSetting(accountInfo).read.themePreference
        .asColor
    } else {
      accountAvatar.color = MacTheme.accentColor
    }
  }

  @objc
  private func accountChanged() {
    updateAccountFooter()
  }

  @objc
  private func themeColorChanged() {
    updateAccountFooter()
    tableView.reloadData()
  }

  @objc
  private func openSettings() {
    AppDelegate.sharedAppDelegate?.showSettings(nil)
  }

  // MARK: - Selection

  func select(item: SidebarItem) {
    selectRow(for: item)
  }

  private func selectRow(for item: SidebarItem) {
    guard let index = rows.firstIndex(where: {
      if case .item(let value) = $0 { return value == item }
      return false
    }) else { return }
    tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
  }

  // MARK: - NSTableViewDataSource

  func numberOfRows(in tableView: NSTableView) -> Int {
    rows.count
  }

  func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
    if case .section = rows[row] { return true }
    return false
  }

  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    if case .section = rows[row] { return MacTheme.sidebarSectionRowHeight }
    return MacTheme.sidebarRowHeight
  }

  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    guard !self.tableView(tableView, isGroupRow: row) else { return nil }
    let rowView = ThemedRowView()
    rowView.cornerRadius = 6
    rowView.horizontalInset = 8
    // Sidebar uses a flat light-grey pill (#DCDCE0) rather than the translucent tint.
    rowView.solidSelectionColor = MacTheme.sidebarSelectionColor
    rowView.needsDisplay = true
    return rowView
  }

  func tableView(
    _ tableView: NSTableView,
    viewFor tableColumn: NSTableColumn?,
    row: Int
  )
    -> NSView? {
    switch rows[row] {
    case .section(let title):
      let cell = tableView.makeView(withIdentifier: groupIdentifier, owner: self) as?
        SidebarGroupCellView ?? SidebarGroupCellView()
      cell.identifier = groupIdentifier
      cell.title = title
      return cell
    case .item(let item):
      let cell = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as?
        SidebarCellView ?? SidebarCellView()
      cell.identifier = cellIdentifier
      cell.configure(item: item)
      return cell
    }
  }

  // MARK: - NSTableViewDelegate

  func tableViewSelectionDidChange(_ notification: Notification) {
    let row = tableView.selectedRow
    guard row >= 0, row < rows.count else { return }
    if case .item(let item) = rows[row] {
      onSelectionChanged?(item)
    }
  }
}

// MARK: - SidebarCellView

@MainActor
private final class SidebarCellView: NSTableCellView {
  private let iconView = NSImageView()
  private let titleField = NSTextField(labelWithString: "")

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    iconView.contentTintColor = MacTheme.accentColor
    iconView.translatesAutoresizingMaskIntoConstraints = false
    iconView.imageScaling = .scaleProportionallyDown
    titleField.font = MacTheme.bodyFont
    titleField.lineBreakMode = .byTruncatingTail
    titleField.translatesAutoresizingMaskIntoConstraints = false
    addSubview(iconView)
    addSubview(titleField)
    // Catalyst indents rows by 8 pt (indentationLevel 1) and reserves a 26 pt icon
    // slot, so the symbol sits ~16 pt from the sidebar edge like the section header.
    NSLayoutConstraint.activate([
      iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
      iconView.widthAnchor.constraint(equalToConstant: 22),
      iconView.heightAnchor.constraint(equalToConstant: 22),

      titleField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
      titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
    self.textField = titleField
    self.imageView = iconView
  }

  required init?(coder: NSCoder) {
    nil
  }

  func configure(item: SidebarItem) {
    iconView.image = NSImage(
      systemSymbolName: item.symbolName,
      accessibilityDescription: nil
    )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .regular))
    titleField.stringValue = item.title
  }
}

// MARK: - SidebarGroupCellView

@MainActor
private final class SidebarGroupCellView: NSTableCellView {
  private let titleField = NSTextField(labelWithString: "")

  var title: String {
    get { titleField.stringValue }
    set { titleField.stringValue = newValue }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    titleField.font = .systemFont(ofSize: 11, weight: .semibold)
    titleField.textColor = .secondaryLabelColor
    titleField.translatesAutoresizingMaskIntoConstraints = false
    addSubview(titleField)
    // Catalyst gives the section header 20 pt of air above and 2 pt below.
    NSLayoutConstraint.activate([
      titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      titleField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
    ])
  }

  required init?(coder: NSCoder) {
    nil
  }
}

// MARK: - AvatarView

/// Small circular avatar with the account's initial, Apple Music style.
@MainActor
final class AvatarView: NSView {
  var displayName: String = "" {
    didSet { rebuild() }
  }

  var color: NSColor = .systemRed {
    didSet { rebuild() }
  }

  private let label = NSTextField(labelWithString: "")

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = 13
    layer?.masksToBounds = true
    label.font = .systemFont(ofSize: 12, weight: .semibold)
    label.textColor = .white
    label.alignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false
    addSubview(label)
    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: centerXAnchor),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  required init?(coder: NSCoder) {
    nil
  }

  private func rebuild() {
    layer?.backgroundColor = color.cgColor
    let initial = displayName.first.map(String.init) ?? "?"
    label.stringValue = initial.uppercased()
  }
}


// MARK: - SidebarBackgroundView

/// Uses the Catalyst sidebar surface (`secondarySystemBackground`) and repaints it
/// when the light/dark appearance changes.
@MainActor
private final class SidebarBackgroundView: NSView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = MacTheme.sidebarBackgroundColor.cgColor
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    layer?.backgroundColor = MacTheme.sidebarBackgroundColor.cgColor
  }
}

// MARK: - ColumnSeparatorView

/// 1 px light-grey line marking the sidebar / content boundary; repaints on
/// appearance changes so it stays correct in dark mode.
@MainActor
private final class ColumnSeparatorView: NSView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = MacTheme.columnDividerColor.cgColor
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    layer?.backgroundColor = MacTheme.columnDividerColor.cgColor
  }
}
