//
//  PlaylistListViewController.swift
//  fmusic-macOS
//
//  List half of the playlists page: artwork, name and song count per playlist.
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
import CoreData
import fmusicKit

/// Playlist list managed by `PlaylistsViewController`.
@MainActor
final class PlaylistListViewController: NSViewController, NSTableViewDataSource,
  NSTableViewDelegate {
  var onSelect: ((Playlist) -> Void)?

  private let titleLabel = NSTextField(labelWithString: L10n.tr("Playlists"))
  private let countLabel = NSTextField(labelWithString: "")
  private let emptyLabel = NSTextField(wrappingLabelWithString: "")
  private let tableView = InteractiveTableView()
  private let scrollView = NSScrollView()

  private var playlists: [Playlist] = []
  private var reloadGeneration = 0

  private enum Column {
    static let artwork = NSUserInterfaceItemIdentifier("playlistArtwork")
    static let name = NSUserInterfaceItemIdentifier("playlistName")
    static let count = NSUserInterfaceItemIdentifier("playlistCount")
  }

  override func loadView() {
    let root = NSView()
    root.wantsLayer = true

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
      selector: #selector(reloadPlaylists),
      name: .librarySongsSynced,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(reloadPlaylists),
      name: .accountActiveChanged,
      object: nil
    )
    reloadPlaylists()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  private func configureTableView() {
    let artworkColumn = NSTableColumn(identifier: Column.artwork)
    artworkColumn.title = ""
    artworkColumn.width = 64
    artworkColumn.minWidth = 64
    artworkColumn.maxWidth = 64

    let nameColumn = NSTableColumn(identifier: Column.name)
    nameColumn.title = L10n.tr("Playlists")
    nameColumn.width = 360
    nameColumn.minWidth = 180

    let countColumn = NSTableColumn(identifier: Column.count)
    countColumn.title = L10n.tr("Songs")
    countColumn.width = 100
    countColumn.minWidth = 80
    countColumn.maxWidth = 140

    [artworkColumn, nameColumn, countColumn].forEach(tableView.addTableColumn)

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
    tableView.onReturn = { [weak self] in
      guard let self else { return }
      let row = self.tableView.selectedRow
      guard row >= 0, row < self.playlists.count else { return }
      self.onSelect?(self.playlists[row])
    }
    tableView.onContextMenu = { [weak self] row in
      self?.makeMenu(for: row)
    }
  }

  private func makeMenu(for row: Int) -> NSMenu? {
    guard row >= 0, row < playlists.count else { return nil }
    let menu = NSMenu()
    let playItem = NSMenuItem(
      title: L10n.tr("Play"),
      action: #selector(menuPlayPlaylist(_:)),
      keyEquivalent: ""
    )
    playItem.target = self
    playItem.tag = row
    menu.addItem(playItem)
    return menu
  }

  private var librarySetting: AccountSetting {
    FmusicKit.shared.storage.settings.accounts.activeSetting.read
  }

  @objc
  private func reloadPlaylists() {
    let storage = FmusicKit.shared.storage
    reloadGeneration += 1
    let generation = reloadGeneration
    guard let accountInfo = storage.settings.accounts.active else {
      playlists = []
      tableView.reloadData()
      countLabel.stringValue = ""
      emptyLabel.stringValue = L10n.tr("No Results")
      emptyLabel.isHidden = false
      return
    }
    let accountID = storage.main.library.getAccount(info: accountInfo).managedObject.objectID
    Task { [weak self] in
      guard let self else { return }
      let ids = try? await storage.async.performAndGet { companion
        -> [NSManagedObjectID] in
        let account = companion.library.getAccount(managedObjectId: accountID)
        return companion.library.getPlaylists(for: account).map(\.managedObject.objectID)
      }
      guard generation == self.reloadGeneration,
            storage.settings.accounts.active == accountInfo else { return }
      let context = storage.main.context
      self.playlists = (ids ?? [])
        .compactMap { context.object(with: $0) as? PlaylistMO }
        .compactMap { Playlist(library: storage.main.library, managedObject: $0) }
      self.tableView.reloadData()
      self.countLabel.stringValue = self.playlists.isEmpty ? "" : "\(self.playlists.count)"
      self.emptyLabel.stringValue = L10n.tr("No Results")
      self.emptyLabel.isHidden = !self.playlists.isEmpty
    }
  }

  @objc
  private func handleDoubleClick() {
    let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
    guard row >= 0, row < playlists.count else { return }
    onSelect?(playlists[row])
  }

  @objc
  private func menuPlayPlaylist(_ sender: NSMenuItem) {
    guard sender.tag >= 0, sender.tag < playlists.count else { return }
    LibraryPlayback.play(playlist: playlists[sender.tag])
  }

  // MARK: - NSTableViewDataSource

  func numberOfRows(in tableView: NSTableView) -> Int {
    playlists.count
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
    guard row < playlists.count, let tableColumn else { return nil }
    let playlist = playlists[row]

    switch tableColumn.identifier {
    case Column.artwork:
      let cell = tableView.makeView(withIdentifier: Column.artwork, owner: self) as?
        LMArtworkCellView ?? LMArtworkCellView()
      cell.identifier = Column.artwork
      cell.display(
        image: LMLibraryArtwork.image(for: playlist, setting: librarySetting),
        size: 44
      )
      return cell
    case Column.name:
      let cell = tableView.makeView(withIdentifier: Column.name, owner: self) as?
        LMTextCellView ?? LMTextCellView()
      cell.identifier = Column.name
      cell.configure(
        text: playlist.name,
        font: .systemFont(ofSize: MacTheme.titleFontSize, weight: .medium),
        color: .labelColor
      )
      return cell
    case Column.count:
      let cell = tableView.makeView(withIdentifier: Column.count, owner: self) as?
        LMTextCellView ?? LMTextCellView()
      cell.identifier = Column.count
      cell.configure(
        text: "\(playlist.songCount) \(L10n.tr("Songs"))",
        font: MacTheme.bodyFont,
        color: MacTheme.secondaryTextColor,
        alignment: .right
      )
      return cell
    default:
      return nil
    }
  }
}
