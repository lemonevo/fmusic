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
  var onOpenSettings: (() -> Void)?

  private enum Row {
    case section(String)
    case item(SidebarItem)
    /// A configurable row in Edit mode: shows a check circle + drag handle.
    case editable(SidebarItem)
  }

  private var rows: [Row] = []

  /// Whether the sidebar is in its "编辑 / 完成" configuration mode.
  private var isEditingSidebar = false

  /// Index of the first configurable row (the editable block starts here).
  private var editableStartIndex: Int {
    rows.firstIndex(where: {
      if case .editable = $0 { return true }
      if case .item(let item) = $0 { return !SidebarConfiguration.fixedItems.contains(item) }
      return false
    }) ?? rows.count
  }

  private var configuredItems: [SidebarItem] {
    isEditingSidebar ? SidebarConfiguration.editingItems() : SidebarConfiguration.visibleItems()
  }

  private func rebuildRows() {
    var result: [Row] = [.item(.search), .item(.home), .section(L10n.tr("Library"))]
    for item in configuredItems {
      result.append(isEditingSidebar ? .editable(item) : .item(item))
    }
    rows = result
  }

  private let tableView = NSTableView()
  private let scrollView = NSScrollView()
  private let accountLabel = NSTextField(labelWithString: "")
  private let editButton = SidebarTitleButton()
  private let sidebarButton = SidebarTitleButton()
  private let accountAvatar = AvatarView()

  // Normal and edit modes share one cell class and identifier; edit mode only
  // toggles the optional check circle / drag handle on the same layout.
  private let cellIdentifier = NSUserInterfaceItemIdentifier("SidebarCell")
  private let editableIdentifier = NSUserInterfaceItemIdentifier("SidebarEditableCell")
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
    tableView.registerForDraggedTypes([.string])
    tableView.setDraggingSourceOperationMask(.move, forLocal: true)
    tableView.draggingDestinationFeedbackStyle = .gap

    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = false
    scrollView.drawsBackground = false
    scrollView.automaticallyAdjustsContentInsets = false
    // Reference gives the first row real breathing room under the 52 pt titlebar
    // (搜索 centre ~72 pt from the window top); 52 pt of top inset reproduces that
    // without pushing the menu into the floating 编辑 / 边栏 buttons.
    scrollView.contentInsets = NSEdgeInsets(top: 52, left: 0, bottom: 4, right: 0)
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    // Top bar: 编辑 + sidebar toggle, floating over the sidebar surface. Both are
    // independent raised controls (white pill, hairline border, soft shadow) drawn with
    // draw(_:) so the labels stay crisp inside the titlebar's glass band.
    editButton.content = .title(L10n.tr("Edit"))
    editButton.onClick = { [weak self] in self?.toggleEditMode() }
    editButton.translatesAutoresizingMaskIntoConstraints = false
    editButton.toolTip = L10n.tr("Edit")
    editButton.setAccessibilityRole(.button)
    editButton.setAccessibilityLabel(L10n.tr("Edit"))

    sidebarButton.content = .symbol("sidebar.left")
    sidebarButton.onClick = { [weak self] in self?.sidebarPressed() }
    sidebarButton.translatesAutoresizingMaskIntoConstraints = false
    sidebarButton.toolTip = L10n.tr("Show Sidebar")
    sidebarButton.setAccessibilityRole(.button)
    sidebarButton.setAccessibilityLabel(L10n.tr("Show Sidebar"))

    let footer = makeAccountFooter()
    root.addSubview(editButton)
    root.addSubview(sidebarButton)
    root.addSubview(scrollView)
    root.addSubview(footer)
    NSLayoutConstraint.activate([
      // 编辑 52×32 and 边栏 toggle 36×32, centred on the 52 pt titlebar (y = 26 pt) and
      // aligned with the traffic lights. Tight 6 pt gap keeps them a coherent cluster.
      editButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 108),
      editButton.centerYAnchor.constraint(equalTo: root.topAnchor, constant: 26),
      editButton.heightAnchor.constraint(equalToConstant: SidebarStyle.rowHeight),
      editButton.widthAnchor.constraint(equalToConstant: 52),
      sidebarButton.leadingAnchor.constraint(equalTo: editButton.trailingAnchor, constant: 6),
      sidebarButton.centerYAnchor.constraint(equalTo: editButton.centerYAnchor),
      sidebarButton.widthAnchor.constraint(equalToConstant: 36),
      sidebarButton.heightAnchor.constraint(equalToConstant: SidebarStyle.rowHeight),
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
    // Dev hook, mirroring `--page`: open directly in sidebar edit mode for inspection.
    if ProcessInfo.processInfo.arguments.contains("--edit-sidebar") {
      isEditingSidebar = true
      editButton.content = .title(L10n.tr("Done"))
      tableView.selectionHighlightStyle = .none
    }
    rebuildRows()
    tableView.reloadData()
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

  /// 编辑 ↔ 完成. In edit mode every configurable row shows a visibility
  /// check circle (left) and a reorder handle (right); Done hides them and
  /// renders only the enabled rows.
  private func toggleEditMode() {
    isEditingSidebar.toggle()
    editButton.content = .title(L10n.tr(isEditingSidebar ? "Done" : "Edit"))
    tableView.selectionHighlightStyle = isEditingSidebar ? .none : .regular
    let selected = currentSelectedItem()
    rebuildRows()
    tableView.reloadData()
    if isEditingSidebar {
      if let selected { selectRow(for: selected) }
    } else if let selected, selected != .search, selected != .home,
              !SidebarConfiguration.isVisible(selected) {
      // The page the user was on just got hidden: fall back to Home.
      selectRow(for: .home)
    } else if let selected {
      selectRow(for: selected)
    }
  }

  /// Toggles visibility of a configurable item without changing the selection.
  private func toggleVisibility(_ item: SidebarItem) {
    let nowVisible = !SidebarConfiguration.isVisible(item)
    SidebarConfiguration.setVisible(item, isVisible: nowVisible)
    let selected = currentSelectedItem()
    rebuildRows()
    tableView.reloadData()
    if let selected { selectRow(for: selected) }
  }

  private func currentSelectedItem() -> SidebarItem? {
    let row = tableView.selectedRow
    guard row >= 0, row < rows.count else { return nil }
    switch rows[row] {
    case .item(let item), .editable(let item): return item
    case .section: return nil
    }
  }

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
    let selected = currentSelectedItem()
    tableView.reloadData()
    if let selected {
      selectRow(for: selected)
    }
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
      switch $0 {
      case .item(let value), .editable(let value): return value == item
      case .section: return false
      }
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
    if case .section = rows[row] { return SidebarStyle.sectionRowHeight }
    return SidebarStyle.rowHeight
  }

  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    guard !self.tableView(tableView, isGroupRow: row) else { return nil }
    let rowView = SidebarRowView()
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
      let cell = tableView.makeView(withIdentifier: groupIdentifier, owner: self)
        as? SidebarSectionCellView ?? SidebarSectionCellView()
      cell.identifier = groupIdentifier
      cell.title = title
      return cell
    case .item(let item):
      let cell = tableView.makeView(withIdentifier: cellIdentifier, owner: self)
        as? SidebarCellView ?? SidebarCellView(frame: .zero)
      cell.identifier = cellIdentifier
      cell.configureNormal(item: item)
      return cell
    case .editable(let item):
      let cell = tableView.makeView(withIdentifier: editableIdentifier, owner: self)
        as? SidebarEditableCellView ?? SidebarEditableCellView(frame: .zero)
      cell.identifier = editableIdentifier
      cell.configureEdit(
        item: item,
        isVisible: SidebarConfiguration.isVisible(item),
        onToggle: { [weak self] in self?.toggleVisibility(item) }
      )
      return cell
    }
  }

  // MARK: - Drag reordering (Edit mode only)

  func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int)
    -> NSPasteboardWriting? {
    guard isEditingSidebar, case .editable = rows[row] else { return nil }
    let item = NSPasteboardItem()
    item.setString(String(row), forType: .string)
    return item
  }

  func tableView(
    _ tableView: NSTableView,
    validateDrop info: NSDraggingInfo,
    proposedRow row: Int,
    proposedDropOperation dropOperation: NSTableView.DropOperation
  )
    -> NSDragOperation {
    guard isEditingSidebar else { return [] }
    // Only allow drops inside the configurable block (never above Search/Home
    // or onto the section header).
    let start = editableStartIndex
    guard row >= start, row <= rows.count else { return [] }
    return .move
  }

  func tableView(
    _ tableView: NSTableView,
    acceptDrop info: NSDraggingInfo,
    row: Int,
    dropOperation: NSTableView.DropOperation
  )
    -> Bool {
    guard isEditingSidebar,
          let raw = info.draggingPasteboard.string(forType: .string),
          let sourceRow = Int(raw),
          sourceRow >= 0, sourceRow < rows.count,
          case .editable = rows[sourceRow] else { return false }

    // Translate the table row back to an index within the editable block.
    let start = editableStartIndex
    let sourceIndex = sourceRow - start
    let count = SidebarConfiguration.editingItems().count
    var targetIndex = row - start
    if targetIndex > sourceIndex { targetIndex -= 1 }
    targetIndex = min(max(targetIndex, 0), max(count - 1, 0))
    guard sourceIndex >= 0, sourceIndex < count else { return false }

    SidebarConfiguration.moveItem(from: sourceIndex, to: targetIndex)
    rebuildRows()
    tableView.reloadData()
    return true
  }

  // MARK: - NSTableViewDelegate

  func tableViewSelectionDidChange(_ notification: Notification) {
    let row = tableView.selectedRow
    guard row >= 0, row < rows.count else { return }
    // Edit mode is a configuration surface: selecting rows must not navigate.
    guard !isEditingSidebar else { return }
    if case .item(let item) = rows[row] {
      onSelectionChanged?(item)
    }
  }
}

// MARK: - SidebarCellView

@MainActor
class SidebarCellView: SidebarTableCellView {
  /// Edit-mode check circle. It is an optional overlay on the exact same base
  /// layout used in normal mode, so symbols, typography and row height never change.
  private let checkButton = CheckCircleButton()
  private var onToggle: (() -> Void)?

  convenience init() {
    self.init(frame: .zero)
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect, usesMediumText: false, supportsDragHandle: true)
    checkButton.translatesAutoresizingMaskIntoConstraints = false
    checkButton.target = self
    checkButton.action = #selector(checkTapped)
    addSubview(checkButton)
    NSLayoutConstraint.activate([
      checkButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      checkButton.centerYAnchor.constraint(equalTo: centerYAnchor),
      checkButton.widthAnchor.constraint(equalToConstant: 18),
      checkButton.heightAnchor.constraint(equalToConstant: 18),
    ])
    checkButton.isHidden = true
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  /// Edit mode reserves 34 pt before the icon (10 + 18 circle + 6 gap).
  var showsLeadingAccessory: Bool {
    get { !checkButton.isHidden }
    set {
      checkButton.isHidden = !newValue
      leadingInset = newValue ? 34 : SidebarStyle.iconLeading
    }
  }

  /// Configures the exact normal-mode layout: no check circle, no drag handle.
  func configureNormal(item: SidebarItem) {
    showsLeadingAccessory = false
    showsDragHandle = false
    apply(item: item)
  }

  /// Configures the same layout with edit-mode accessories only.
  func configureEdit(item: SidebarItem, isVisible: Bool, onToggle: @escaping () -> Void) {
    self.onToggle = onToggle
    showsLeadingAccessory = true
    showsDragHandle = true
    apply(item: item)
    checkButton.isOn = isVisible
  }

  private func apply(item: SidebarItem) {
    let isFavourite = item == .favoriteSongs || item == .favoriteAlbums ||
      item == .favoriteArtists
    configure(symbolName: item.symbolName, title: item.title, isFilled: isFavourite)
  }

  @objc private func checkTapped() {
    onToggle?()
  }
}

// MARK: - SidebarEditableCellView

/// Same class/metrics as normal rows, with the check circle visible by default.
@MainActor
private final class SidebarEditableCellView: SidebarCellView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    showsLeadingAccessory = true
    showsDragHandle = true
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }
}

// MARK: - CheckCircleButton

/// Red circular checkbox: filled red with a white check when enabled, hollow red
/// ring when disabled (mirrors Catalyst `checkmark.circle.fill` / `circle`).
@MainActor
private final class CheckCircleButton: NSButton {
  var isOn = false {
    didSet { needsDisplay = true }
  }

  private var isHovered = false

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    isBordered = false
    title = ""
    setButtonType(.momentaryChange)
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(
      NSTrackingArea(
        rect: bounds,
        options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
        owner: self,
        userInfo: nil
      )
    )
  }

  override func mouseEntered(with event: NSEvent) {
    isHovered = true
    needsDisplay = true
  }

  override func mouseExited(with event: NSEvent) {
    isHovered = false
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    let diameter: CGFloat = 18
    let rect = NSRect(
      x: (bounds.width - diameter) / 2,
      y: (bounds.height - diameter) / 2,
      width: diameter,
      height: diameter
    )
    let red = MacTheme.accentColor
    if isOn {
      red.setFill()
      NSBezierPath(ovalIn: rect).fill()
      let check = NSImage(
        systemSymbolName: "checkmark",
        accessibilityDescription: nil
      )?.withSymbolConfiguration(.init(pointSize: 10, weight: .bold))
      if let check {
        let tinted = NSImage(size: check.size, flipped: false) { r in
          check.draw(in: r)
          NSColor.white.set()
          r.fill(using: .sourceAtop)
          return true
        }
        let sz = tinted.size
        tinted.draw(in: NSRect(
          x: rect.midX - sz.width / 2,
          y: rect.midY - sz.height / 2,
          width: sz.width,
          height: sz.height
        ))
      }
    } else {
      (isHovered ? red.withAlphaComponent(0.12) : NSColor.clear).setFill()
      NSBezierPath(ovalIn: rect.insetBy(dx: -2, dy: -2)).fill()
      red.setStroke()
      let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 0.75, dy: 0.75))
      ring.lineWidth = 1.5
      ring.stroke()
    }
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
    refresh()
    // Split-view items don't always get `viewDidChangeEffectiveAppearance`, so also
    // repaint from the app's explicit appearance notification.
    NotificationCenter.default.addObserver(
      self, selector: #selector(refresh), name: .macAppearanceChanged, object: nil
    )
  }

  required init?(coder: NSCoder) {
    nil
  }

  deinit { NotificationCenter.default.removeObserver(self) }

  @objc private func refresh() {
    let appearance = window?.effectiveAppearance ?? NSApp.effectiveAppearance
    layer?.backgroundColor = MacTheme.cgColor(MacTheme.sidebarBackgroundColor, for: appearance)
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    refresh()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    refresh()
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
    refresh()
    NotificationCenter.default.addObserver(
      self, selector: #selector(refresh), name: .macAppearanceChanged, object: nil
    )
  }

  required init?(coder: NSCoder) {
    nil
  }

  deinit { NotificationCenter.default.removeObserver(self) }

  @objc private func refresh() {
    let appearance = window?.effectiveAppearance ?? NSApp.effectiveAppearance
    layer?.backgroundColor = MacTheme.cgColor(MacTheme.columnDividerColor, for: appearance)
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    refresh()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    refresh()
  }
}

// MARK: - SidebarTitleButton

/// Raised pill button drawn with `draw(_:)` instead of a layer-backed `NSButton`.
/// Inside the window's titlebar band macOS composites the sidebar through its glass
/// material, which downsamples/softens layer-backed subviews (the 编辑 / 边栏 labels
/// looked blurry). A plain, non-layer-backed `NSView` is rasterised by the window at
/// native resolution, so it stays crisp — verified side-by-side at 2×.
@MainActor
final class SidebarTitleButton: NSControl {
  enum Content {
    case title(String)
    case symbol(String)
  }

  var content: Content = .title("") { didSet { needsDisplay = true } }
  /// Pill fill. The sidebar's surface uses `MacTheme.sidebarButtonFillColor`; the content
  /// toolbar uses `MacTheme.searchFieldBackgroundColor` so the button stays visible on light
  /// and dark surfaces alike.
  var fillColor: NSColor = MacTheme.sidebarButtonFillColor { didSet { needsDisplay = true } }
  var onClick: (() -> Void)?

  private var isPressed = false {
    didSet { needsDisplay = true }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    // Deliberately NOT layer-backed: the titlebar glass blurs layer-backed content.
    wantsLayer = false
    // NSControl makes AppKit treat clicks as control hits instead of titlebar
    // double-clicks (Catalyst uses a UIBarButtonItem here, also a real control).
    target = self
    action = #selector(press)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(appearanceOrStyleChanged),
      name: .macGlassStyleChanged,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(appearanceOrStyleChanged),
      name: .macAppearanceChanged,
      object: nil
    )
  }

  required init?(coder: NSCoder) {
    nil
  }

  deinit { NotificationCenter.default.removeObserver(self) }

  @objc private func press() {
    onClick?()
  }

  @objc private func appearanceOrStyleChanged() {
    needsDisplay = true
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    needsDisplay = true
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }

  /// Height is fixed by constraints (32 pt); the radius follows to make a pill.
  override func draw(_ dirtyRect: NSRect) {
    let style = GlassStyleManager.configuration
    let appearance = window?.effectiveAppearance ?? effectiveAppearance
    let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    var resolvedFill = fillColor
    appearance.performAsCurrentDrawingAppearance {
      resolvedFill = fillColor.usingColorSpace(.sRGB) ?? fillColor
    }

    let r = bounds.insetBy(dx: 0.5, dy: 0.5)
    let path = NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)
    // The reference buttons have NO hard outline — a pill that fades into the
    // surface via a soft shadow and faint inner rim.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(
      isDark ? min(style.buttonShadowOpacity * 2.5, 0.35) : style.buttonShadowOpacity
    )
    shadow.shadowBlurRadius = 3
    shadow.shadowOffset = NSSize(width: 0, height: -0.5)
    shadow.set()
    let activeFill: NSColor
    if isPressed {
      activeFill = isDark
        ? NSColor.white.withAlphaComponent(0.18)
        : NSColor.black.withAlphaComponent(0.06)
    } else {
      // Multiply alpha rather than replacing it, so already-translucent dynamic colors
      // (like `searchFieldBackgroundColor` in dark mode) stay subtle instead of jumping to 0.90.
      activeFill = resolvedFill.withAlphaComponent(
        resolvedFill.alphaComponent * style.buttonFillAlpha
      )
    }
    activeFill.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    let rimColor = isDark
      ? NSColor.white.withAlphaComponent(min(style.buttonBorderAlpha * 2.0, 0.16))
      : NSColor.black.withAlphaComponent(style.buttonBorderAlpha)
    rimColor.setStroke()
    path.lineWidth = 0.5
    path.stroke()

    switch content {
    case let .title(text):
      let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        .foregroundColor: NSColor.labelColor,
      ]
      let s = NSAttributedString(string: text, attributes: attrs)
      let size = s.size()
      s.draw(at: NSPoint(
        x: ((bounds.width - size.width) / 2).rounded(),
        y: ((bounds.height - size.height) / 2).rounded()
      ))
    case let .symbol(name):
      guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
      else { return }
      let sz = img.size
      let tinted = NSImage(size: sz, flipped: false) { rect in
        img.draw(in: rect)
        NSColor.labelColor.set()
        rect.fill(using: .sourceAtop)
        return true
      }
      tinted.draw(in: NSRect(
        x: ((bounds.width - sz.width) / 2).rounded(),
        y: ((bounds.height - sz.height) / 2).rounded(),
        width: sz.width,
        height: sz.height
      ))
    }
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  override func mouseDown(with event: NSEvent) {
    isPressed = true
    window?.makeFirstResponder(self)
  }

  override func mouseUp(with event: NSEvent) {
    let wasPressed = isPressed
    isPressed = false
    let point = convert(event.locationInWindow, from: nil)
    if wasPressed, bounds.contains(point) {
      sendAction(action, to: target)
    }
  }

  override func accessibilityPerformPress() -> Bool {
    sendAction(action, to: target)
    return true
  }
}

