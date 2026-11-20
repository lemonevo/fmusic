//
//  RadiosViewController.swift
//  fmusic-macOS
//
//  Radio list page (sidebar `.radios`): every radio station of the active account.
//  Double-click starts the stream through the shared player.
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

/// Radio stations of the active account, played on double-click.
@MainActor
final class RadiosViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
  private let titleLabel = NSTextField(labelWithString: L10n.tr("Radios"))
  private let countLabel = NSTextField(labelWithString: "")
  private let emptyLabel = NSTextField(wrappingLabelWithString: "")
  private let tableView = NSTableView()
  private let scrollView = NSScrollView()

  private var radios: [Radio] = []

  private enum Column {
    static let artwork = NSUserInterfaceItemIdentifier("radioArtwork")
    static let name = NSUserInterfaceItemIdentifier("radioName")
    static let site = NSUserInterfaceItemIdentifier("radioSite")
  }

  // MARK: - Lifecycle

  override func loadView() {
    let root = ThemedBackgroundView()

    titleLabel.font = MacTheme.largeTitleFont
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    countLabel.font = MacTheme.secondaryFont
    countLabel.textColor = MacTheme.secondaryTextColor
    countLabel.translatesAutoresizingMaskIntoConstraints = false

    emptyLabel.font = .systemFont(ofSize: MacTheme.bodyFontSize)
    emptyLabel.textColor = MacTheme.secondaryTextColor
    emptyLabel.alignment = .center
    emptyLabel.translatesAutoresizingMaskIntoConstraints = false

    configureTableView()
    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.drawsBackground = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    root.addSubview(titleLabel)
    root.addSubview(countLabel)
    root.addSubview(scrollView)
    root.addSubview(emptyLabel)

    NSLayoutConstraint.activate([
      titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
      titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),

      countLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      countLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),

      scrollView.topAnchor.constraint(equalTo: countLabel.bottomAnchor, constant: 12),
      scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

      emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
      emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
      emptyLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
    ])

    self.view = root
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(reloadRadios),
      name: .librarySongsSynced,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(reloadRadios),
      name: .accountActiveChanged,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(themeDidChange),
      name: .macThemeColorChanged,
      object: nil
    )
    reloadRadios()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  // MARK: - Table view

  private func configureTableView() {
    let artworkColumn = NSTableColumn(identifier: Column.artwork)
    artworkColumn.title = ""
    artworkColumn.width = 64
    artworkColumn.minWidth = 64
    artworkColumn.maxWidth = 64

    let nameColumn = NSTableColumn(identifier: Column.name)
    nameColumn.title = L10n.tr("Radios")
    nameColumn.width = 320
    nameColumn.minWidth = 180

    let siteColumn = NSTableColumn(identifier: Column.site)
    siteColumn.title = ""
    siteColumn.width = 240
    siteColumn.minWidth = 120

    [artworkColumn, nameColumn, siteColumn].forEach(tableView.addTableColumn)

    tableView.rowHeight = 56
    tableView.style = .fullWidth
    tableView.selectionHighlightStyle = .regular
    tableView.allowsMultipleSelection = false
    tableView.allowsEmptySelection = true
    tableView.usesAlternatingRowBackgroundColors = false
    tableView.backgroundColor = .clear
    tableView.gridStyleMask = []
    tableView.dataSource = self
    tableView.delegate = self
    tableView.doubleAction = #selector(handleDoubleClick)
    tableView.target = self
    tableView.menu = makeContextMenu()
  }

  private func makeContextMenu() -> NSMenu {
    let menu = NSMenu()
    let play = NSMenuItem(
      title: L10n.tr("Play"),
      action: #selector(playSelectedRow),
      keyEquivalent: ""
    )
    play.target = self
    menu.addItem(play)
    return menu
  }

  private var librarySetting: AccountSetting {
    FmusicKit.shared.storage.settings.accounts.activeSetting.read
  }

  // MARK: - Data

  @objc
  private func reloadRadios() {
    let storage = FmusicKit.shared.storage
    guard let accountInfo = storage.settings.accounts.active else {
      radios = []
      tableView.reloadData()
      countLabel.stringValue = ""
      emptyLabel.stringValue = L10n.tr("No Radios")
      emptyLabel.isHidden = false
      return
    }
    let account = storage.main.library.getAccount(info: accountInfo)
    radios = storage.main.library.getRadios(for: account)
    tableView.reloadData()
    countLabel.stringValue = radios.isEmpty ? "" : L10n.tr("%d Radios", radios.count)
    emptyLabel.stringValue = L10n.tr("No Radios")
    emptyLabel.isHidden = !radios.isEmpty
  }

  @objc
  private func themeDidChange() {
    tableView.reloadData()
  }

  // MARK: - Actions

  @objc
  private func handleDoubleClick() {
    play(row: tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow)
  }

  @objc
  private func playSelectedRow() {
    play(row: tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow)
  }

  private func play(row: Int) {
    guard row >= 0, row < radios.count else { return }
    let radio = radios[row]
    // `Radio` is a plain playable (not a PlayableContainable): stream it as a single
    // item music context, which the shared player detects via `isRadio`.
    FmusicKit.shared.player.play(context: PlayContext(
      name: radio.title,
      index: 0,
      playables: [radio]
    ))
  }

  // MARK: - NSTableViewDataSource

  func numberOfRows(in tableView: NSTableView) -> Int {
    radios.count
  }

  // MARK: - NSTableViewDelegate

  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    let rowView = ThemedRowView()
    rowView.cornerRadius = 6
    rowView.horizontalInset = 10
    return rowView
  }

  func tableView(
    _ tableView: NSTableView,
    viewFor tableColumn: NSTableColumn?,
    row: Int
  )
    -> NSView? {
    guard row < radios.count, let tableColumn else { return nil }
    let radio = radios[row]

    switch tableColumn.identifier {
    case Column.artwork:
      let cell = tableView.makeView(withIdentifier: Column.artwork, owner: self) as?
        LMArtworkCellView ?? LMArtworkCellView()
      cell.identifier = Column.artwork
      cell.display(
        image: LMLibraryArtwork.image(for: radio, setting: librarySetting),
        size: 44
      )
      return cell
    case Column.name:
      let cell = tableView.makeView(withIdentifier: Column.name, owner: self) as?
        LMTextCellView ?? LMTextCellView()
      cell.identifier = Column.name
      cell.configure(
        text: radio.title,
        font: .systemFont(ofSize: MacTheme.titleFontSize, weight: .medium),
        color: .labelColor
      )
      return cell
    case Column.site:
      let cell = tableView.makeView(withIdentifier: Column.site, owner: self) as?
        LMTextCellView ?? LMTextCellView()
      cell.identifier = Column.site
      cell.configure(
        text: radio.siteURL?.host ?? "",
        font: MacTheme.bodyFont,
        color: MacTheme.secondaryTextColor
      )
      return cell
    default:
      return nil
    }
  }
}
