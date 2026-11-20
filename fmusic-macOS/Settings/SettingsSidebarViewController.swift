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

/// 210 pt source list of the settings window (Apple Music style sidebar).
@MainActor
final class SettingsSidebarViewController: NSViewController {
  var onSelectionChanged: ((SettingsPage) -> Void)?

  private let pages = SettingsPage.allCases
  private let tableView = NSTableView()
  private let scrollView = NSScrollView()

  private let cellIdentifier = NSUserInterfaceItemIdentifier("SettingsSidebarCell")
  private let columnIdentifier = NSUserInterfaceItemIdentifier("SettingsSidebarColumn")

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

    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = false
    scrollView.drawsBackground = false
    scrollView.automaticallyAdjustsContentInsets = false
    scrollView.contentInsets = NSEdgeInsets(top: 12, left: 0, bottom: 8, right: 0)
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    root.addSubview(scrollView)
    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: root.topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
    ])

    self.view = root
  }

  // MARK: - Selection

  func select(page: SettingsPage) {
    let row = pages.firstIndex(of: page) ?? 0
    tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
  }
}

// MARK: - NSTableViewDataSource

extension SettingsSidebarViewController: NSTableViewDataSource {
  func numberOfRows(in tableView: NSTableView) -> Int {
    pages.count
  }

  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    32
  }

  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    let rowView = ThemedRowView()
    rowView.cornerRadius = 6
    rowView.horizontalInset = 8
    return rowView
  }

  func tableView(
    _ tableView: NSTableView,
    viewFor tableColumn: NSTableColumn?,
    row: Int
  )
    -> NSView? {
    guard row >= 0, row < pages.count else { return nil }
    let cell = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as?
      SettingsSidebarCellView ?? SettingsSidebarCellView()
    cell.identifier = cellIdentifier
    cell.configure(page: pages[row])
    return cell
  }
}

// MARK: - NSTableViewDelegate

extension SettingsSidebarViewController: NSTableViewDelegate {
  func tableViewSelectionDidChange(_ notification: Notification) {
    let row = tableView.selectedRow
    guard row >= 0, row < pages.count else { return }
    onSelectionChanged?(pages[row])
  }
}

// MARK: - SettingsSidebarCellView

@MainActor
private final class SettingsSidebarCellView: NSTableCellView {
  private let iconView = NSImageView()
  private let titleField = NSTextField(labelWithString: "")

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    iconView.contentTintColor = MacTheme.accentColor
    iconView.imageScaling = .scaleProportionallyDown
    iconView.translatesAutoresizingMaskIntoConstraints = false
    titleField.font = MacTheme.bodyFont
    titleField.lineBreakMode = .byTruncatingTail
    titleField.translatesAutoresizingMaskIntoConstraints = false
    addSubview(iconView)
    addSubview(titleField)
    NSLayoutConstraint.activate([
      iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
      iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
      iconView.widthAnchor.constraint(equalToConstant: 16),
      iconView.heightAnchor.constraint(equalToConstant: 16),

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

  func configure(page: SettingsPage) {
    iconView.image = NSImage(
      systemSymbolName: page.symbolName,
      accessibilityDescription: nil
    )
    titleField.stringValue = page.title
  }
}
