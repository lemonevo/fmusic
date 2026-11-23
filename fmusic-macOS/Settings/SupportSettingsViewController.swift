//
//  SupportSettingsViewController.swift
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
import UniformTypeIdentifiers
import fmusicKit

/// 支持: the event log of the core `LogEntry` entities plus the support actions of the
/// Catalyst app (export log, report an issue on GitHub).
///
/// The log is read with the same fetch request the Catalyst event log uses
/// (`LogEntryMO.creationDateSortedFetchRequest`, newest first) and the export uses the same
/// `LogData.collectInformation(fmusicData:)` payload the Catalyst "Export log" action writes
/// as `fmusicLog.json`.
@MainActor
final class SupportSettingsViewController: SettingsPageViewController {
  private static let issueURL = URL(string: "https://github.com/lemonevo/fmusic/issues")
  private static let logFileName = "fmusicLog.json"

  /// Value copy of one log entry: the table only needs these fields and must not keep the
  /// Core Data managed object alive across fetches.
  private struct EventRow {
    let type: LogEntryType
    let statusCode: Int
    let date: Date
    let message: String

    /// Mirrors the Catalyst event log cell: the type plus the status code for errors.
    var typeText: String {
      var text = type.description
      if type == .error, statusCode > 1 {
        text += " \(CommonString.oneMiddleDot) \(L10n.tr("Status code %d", statusCode))"
      }
      return text
    }

    var isoTimestamp: String {
      date.asIso8601String
    }

    var copiedLine: String {
      "\(isoTimestamp)\t\(typeText)\t\(message)"
    }
  }

  private var rows: [EventRow] = []

  private let tableView = NSTableView()
  private var copySelectedButton: SettingsButton?

  private let typeColumnID = NSUserInterfaceItemIdentifier("SupportEventLogType")
  private let dateColumnID = NSUserInterfaceItemIdentifier("SupportEventLogDate")
  private let messageColumnID = NSUserInterfaceItemIdentifier("SupportEventLogMessage")

  init() {
    super.init(title: L10n.tr("Support"))
  }

  required init?(coder: NSCoder) {
    nil
  }

  // MARK: - Form

  override func buildForm() {
    rows = Self.loadEventRows()

    addButton(title: L10n.tr("Report an issue on GitHub")) {
      guard let url = Self.issueURL else { return }
      NSWorkspace.shared.open(url)
    }
    addButton(title: L10n.tr("Export log")) { [weak self] in
      self?.exportLog()
    }

    guard !rows.isEmpty else {
      addSection(
        header: L10n.tr("Event Log"),
        footer: L10n.tr("Errors and other events will be listed here."),
        rows: [makeTextRow(L10n.tr("No Events"))]
      )
      return
    }

    addSection(
      header: L10n.tr("Event Log"),
      footer: L10n.tr("%d Events", rows.count),
      rows: [makeEventLogTableRow(), makeEventLogActionsRow()]
    )
  }

  private static func loadEventRows() -> [EventRow] {
    FmusicKit.shared.storage.main.library.getAllLogEntries(limit: 300).map { entry in
      EventRow(
        type: entry.type,
        statusCode: entry.statusCode,
        date: entry.creationDate,
        message: entry.message
      )
    }
  }

  // MARK: - Event log table

  private func makeEventLogTableRow() -> NSView {
    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false
    container.heightAnchor.constraint(equalToConstant: 320).isActive = true

    configureTable()

    let scrollView = NSScrollView()
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.scrollerStyle = .overlay
    scrollView.drawsBackground = false
    scrollView.documentView = tableView
    scrollView.wantsLayer = true
    scrollView.layer?.cornerRadius = 10
    scrollView.layer?.masksToBounds = true

    container.addSubview(scrollView)
    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: container.topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
    return container
  }

  private func configureTable() {
    while let column = tableView.tableColumns.first {
      tableView.removeTableColumn(column)
    }

    let typeColumn = NSTableColumn(identifier: typeColumnID)
    typeColumn.title = L10n.tr("Type")
    typeColumn.width = 140
    typeColumn.minWidth = 100
    typeColumn.maxWidth = 240

    let dateColumn = NSTableColumn(identifier: dateColumnID)
    dateColumn.title = L10n.tr("Date")
    dateColumn.width = 180
    dateColumn.minWidth = 150
    dateColumn.maxWidth = 260

    let messageColumn = NSTableColumn(identifier: messageColumnID)
    messageColumn.title = L10n.tr("Message")
    messageColumn.width = 280
    messageColumn.minWidth = 120
    messageColumn.resizingMask = .autoresizingMask

    tableView.addTableColumn(typeColumn)
    tableView.addTableColumn(dateColumn)
    tableView.addTableColumn(messageColumn)

    tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    tableView.style = .plain
    tableView.rowHeight = 26
    tableView.intercellSpacing = NSSize(width: 8, height: 2)
    tableView.usesAlternatingRowBackgroundColors = false
    tableView.backgroundColor = .clear
    tableView.gridStyleMask = []
    tableView.selectionHighlightStyle = .regular
    tableView.allowsMultipleSelection = false
    tableView.allowsEmptySelection = true
    tableView.focusRingType = .none
    tableView.dataSource = self
    tableView.delegate = self
    tableView.target = self
    tableView.doubleAction = #selector(copySelectedEntry)
    tableView.menu = makeContextMenu()
  }

  private func makeContextMenu() -> NSMenu {
    let menu = NSMenu()
    let item = NSMenuItem(
      title: L10n.tr("Copy to Clipboard"),
      action: #selector(copyClickedEntry),
      keyEquivalent: ""
    )
    item.target = self
    menu.addItem(item)
    return menu
  }

  private func makeEventLogActionsRow() -> NSView {
    let copyButton = SettingsButton(
      title: L10n.tr("Copy to Clipboard"),
      isEnabled: false
    ) { [weak self] in
      self?.copySelectedEntry()
    }
    copySelectedButton = copyButton

    let copyAllButton = SettingsButton(title: L10n.tr("Copy All")) { [weak self] in
      self?.copyAllEntries()
    }

    let stack = NSStackView(views: [copyButton, copyAllButton])
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 8
    stack.translatesAutoresizingMaskIntoConstraints = false

    return SettingsRowView(title: "", control: stack)
  }

  // MARK: - Copy actions

  private func entry(at row: Int) -> EventRow? {
    guard row >= 0, row < rows.count else { return nil }
    return rows[row]
  }

  private func selectedEntry() -> EventRow? {
    entry(at: tableView.selectedRow)
  }

  @objc
  private func copySelectedEntry() {
    guard let entry = selectedEntry() else { return }
    copyToPasteboard(entry.message)
  }

  /// Context menu action: right clicking a row does not necessarily change the selection,
  /// so the clicked row wins over the selected row.
  @objc
  private func copyClickedEntry() {
    let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
    guard let entry = entry(at: row) else { return }
    copyToPasteboard(entry.message)
  }

  @objc
  private func copyAllEntries() {
    guard !rows.isEmpty else { return }
    copyToPasteboard(rows.map(\.copiedLine).joined(separator: "\n"))
  }

  private func copyToPasteboard(_ text: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
  }

  // MARK: - Export log

  private func exportLog() {
    guard let data = LogData.collectInformation(fmusicData: FmusicKit.shared)
      .asJSONData() else {
      presentError(
        message: L10n.tr("Export log"),
        details: L10n.tr("The log could not be created.")
      )
      return
    }

    let panel = NSSavePanel()
    panel.nameFieldStringValue = Self.logFileName
    panel.allowedContentTypes = [.json]
    panel.canCreateDirectories = true

    if let window = view.window {
      panel.beginSheetModal(for: window) { [weak self] response in
        self?.handleExportResponse(response, panel: panel, data: data)
      }
    } else {
      handleExportResponse(panel.runModal(), panel: panel, data: data)
    }
  }

  private func handleExportResponse(
    _ response: NSApplication.ModalResponse,
    panel: NSSavePanel,
    data: Data
  ) {
    guard response == .OK, let url = panel.url else { return }
    do {
      try data.write(to: url, options: .atomic)
    } catch {
      presentError(message: L10n.tr("Export log"), details: error.localizedDescription)
    }
  }

  private func presentError(message: String, details: String) {
    let alert = NSAlert()
    alert.messageText = message
    alert.informativeText = details
    alert.alertStyle = .warning
    alert.addButton(withTitle: L10n.tr("OK"))
    if let window = view.window {
      alert.beginSheetModal(for: window)
    } else {
      alert.runModal()
    }
  }
}

// MARK: - NSTableViewDataSource

extension SupportSettingsViewController: NSTableViewDataSource {
  func numberOfRows(in tableView: NSTableView) -> Int {
    rows.count
  }
}

// MARK: - NSTableViewDelegate

extension SupportSettingsViewController: NSTableViewDelegate {
  func tableView(
    _ tableView: NSTableView,
    viewFor tableColumn: NSTableColumn?,
    row: Int
  )
    -> NSView? {
    guard row >= 0, row < rows.count, let columnID = tableColumn?.identifier else { return nil }
    let entry = rows[row]

    let cell = tableView.makeView(withIdentifier: columnID, owner: self) as? EventLogCellView
      ?? EventLogCellView()
    cell.identifier = columnID

    switch columnID {
    case typeColumnID:
      cell.configure(
        text: entry.typeText,
        color: Self.color(for: entry.type),
        toolTip: entry.typeText
      )
    case dateColumnID:
      cell.configure(
        text: entry.isoTimestamp,
        color: .secondaryLabelColor,
        monospaced: true,
        toolTip: entry.isoTimestamp
      )
    default:
      cell.configure(
        text: entry.message,
        color: .labelColor,
        toolTip: entry.message
      )
    }
    return cell
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    copySelectedButton?.isEnabled = selectedEntry() != nil
  }

  private static func color(for type: LogEntryType) -> NSColor {
    switch type {
    case .apiError: return .systemOrange
    case .error: return .systemRed
    case .info: return .secondaryLabelColor
    case .debug: return .tertiaryLabelColor
    }
  }
}

// MARK: - EventLogCellView

@MainActor
private final class EventLogCellView: NSTableCellView {
  private let label = NSTextField(labelWithString: "")

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    label.font = .systemFont(ofSize: 12)
    label.textColor = .labelColor
    label.lineBreakMode = .byTruncatingTail
    label.translatesAutoresizingMaskIntoConstraints = false
    addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
      label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
    textField = label
  }

  required init?(coder: NSCoder) {
    nil
  }

  func configure(
    text: String,
    color: NSColor,
    monospaced: Bool = false,
    toolTip: String? = nil
  ) {
    label.stringValue = text
    label.textColor = color
    label.font = monospaced
      ? .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
      : .systemFont(ofSize: 12)
    self.toolTip = toolTip
  }
}
