//
//  FavoriteSongsViewController.swift
//  fmusic-macOS
//
//  Favorite songs page (sidebar `.favoriteSongs`).
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

/// Flat list of the account's favorite songs, reusing the song-row look of
/// `SongsViewController`.
@MainActor
final class FavoriteSongsViewController: NSViewController, NSTableViewDataSource,
  NSTableViewDelegate {
  private let titleLabel = NSTextField(labelWithString: L10n.tr("Favorite Songs"))
  private let countLabel = NSTextField(labelWithString: "")
  private let emptyLabel = NSTextField(wrappingLabelWithString: "")
  private let tableView = InteractiveTableView()
  private let scrollView = NSScrollView()

  private var songs: [Song] = []
  private var reloadGeneration = 0

  private enum Column {
    static let artwork = NSUserInterfaceItemIdentifier("favoriteArtwork")
    static let title = NSUserInterfaceItemIdentifier("favoriteTitle")
    static let artist = NSUserInterfaceItemIdentifier("favoriteArtist")
    static let album = NSUserInterfaceItemIdentifier("favoriteAlbum")
    static let duration = NSUserInterfaceItemIdentifier("favoriteDuration")
  }

  // MARK: - Lifecycle

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
    scrollView.autohidesScrollers = true
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
      selector: #selector(reloadSongs),
      name: .librarySongsSynced,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(reloadSongs),
      name: .accountActiveChanged,
      object: nil
    )
    reloadSongs()
  }

  override func viewDidLayout() {
    super.viewDidLayout()
    fitColumnsToAvailableWidth()
  }

  private func fitColumnsToAvailableWidth() {
    let width = scrollView.contentView.bounds.width
    guard width > 0, tableView.tableColumns.count == 5 else { return }
    let columns = tableView.tableColumns
    // The full-width table style adds outer padding as well as intercell spacing.
    let padding = tableView.rect(ofColumn: columns.count - 1).maxX
      - columns.reduce(CGFloat.zero) { $0 + $1.width }
    let extra = max(0, width - padding - columns.reduce(CGFloat.zero) { $0 + $1.minWidth })
    let scale = view.window?.backingScaleFactor ?? 1
    let weights: [CGFloat] = [0, 0.5, 0.22, 0.28, 0]
    let widths = zip(columns, weights).map { column, weight in
      column.minWidth + floor(extra * weight * scale) / scale
    }
    for (column, targetWidth) in zip(columns, widths) where abs(column.width - targetWidth) > 0.5 {
      column.width = targetWidth
    }
    if abs(tableView.frame.width - width) > 0.5 {
      tableView.setFrameSize(NSSize(width: width, height: tableView.frame.height))
    }
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  // MARK: - Table view

  private func configureTableView() {
    let artworkColumn = NSTableColumn(identifier: Column.artwork)
    artworkColumn.title = ""
    artworkColumn.width = 46
    artworkColumn.minWidth = 46
    artworkColumn.maxWidth = 46
    artworkColumn.resizingMask = []

    let titleColumn = NSTableColumn(identifier: Column.title)
    titleColumn.title = L10n.tr("Songs")
    titleColumn.width = 280
    titleColumn.minWidth = 120

    let artistColumn = NSTableColumn(identifier: Column.artist)
    artistColumn.title = L10n.tr("Artist")
    artistColumn.width = 160
    artistColumn.minWidth = 80

    let albumColumn = NSTableColumn(identifier: Column.album)
    albumColumn.title = L10n.tr("Album")
    albumColumn.width = 200
    albumColumn.minWidth = 100

    let durationColumn = NSTableColumn(identifier: Column.duration)
    durationColumn.title = L10n.tr("Duration")
    durationColumn.width = 60
    durationColumn.minWidth = 60
    durationColumn.maxWidth = 60
    durationColumn.resizingMask = []

    [artworkColumn, titleColumn, artistColumn, albumColumn, durationColumn]
      .forEach(tableView.addTableColumn)

    tableView.rowHeight = MacTheme.songRowHeight
    tableView.style = .fullWidth
    tableView.selectionHighlightStyle = .regular
    tableView.allowsMultipleSelection = true
    tableView.allowsEmptySelection = true
    // Fit to the clip view explicitly: NSTableView otherwise keeps its wider
    // document frame when the lyrics split item shrinks the content column.
    tableView.columnAutoresizingStyle = .noColumnAutoresizing
    tableView.intercellSpacing = NSSize(width: 8, height: 0)
    tableView.autoresizingMask = [.width]
    tableView.usesAlternatingRowBackgroundColors = false
    tableView.backgroundColor = .clear
    tableView.gridStyleMask = []
    tableView.dataSource = self
    tableView.delegate = self
    tableView.doubleAction = #selector(handleDoubleClick)
    tableView.target = self
    tableView.onReturn = { [weak self] in
      guard let self else { return }
      self.play(row: self.tableView.selectedRow)
    }
    tableView.onContextMenu = { [weak self] row in
      self?.makeMenu(for: row)
    }
  }

  // MARK: - Data

  private var librarySetting: AccountSetting {
    FmusicKit.shared.storage.settings.accounts.activeSetting.read
  }

  @objc
  private func reloadSongs() {
    let storage = FmusicKit.shared.storage
    reloadGeneration += 1
    let generation = reloadGeneration
    guard let accountInfo = storage.settings.accounts.active else {
      songs = []
      tableView.reloadData()
      countLabel.stringValue = ""
      emptyLabel.stringValue = ""
      emptyLabel.isHidden = false
      return
    }
    let accountID = storage.main.library.getAccount(info: accountInfo).managedObject.objectID
    Task { [weak self] in
      guard let self else { return }
      let ids = try? await storage.async.performAndGet { companion
        -> [NSManagedObjectID] in
        let account = companion.library.getAccount(managedObjectId: accountID)
        return companion.library.getFavoriteSongs(for: account).map(\.managedObject.objectID)
      }
      guard generation == self.reloadGeneration,
            storage.settings.accounts.active == accountInfo else { return }
      let context = storage.main.context
      self.songs = (ids ?? [])
        .compactMap { context.object(with: $0) as? SongMO }
        .compactMap { Song(managedObject: $0) }
      self.tableView.reloadData()
      self.countLabel.stringValue = self.songs.isEmpty ? "" : "\(self.songs.count)"
      self.emptyLabel.stringValue = L10n.tr("No Results")
      self.emptyLabel.isHidden = !self.songs.isEmpty
    }
  }

  // MARK: - Actions

  @objc
  private func handleDoubleClick() {
    let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
    play(row: row)
  }

  private func play(row: Int) {
    guard row >= 0, row < songs.count else { return }
    FmusicKit.shared.player.play(context: PlayContext(
      name: L10n.tr("Favorite Songs"),
      index: row,
      playables: songs
    ))
  }

  private func makeMenu(for row: Int) -> NSMenu? {
    guard row >= 0, row < songs.count else { return nil }
    let menu = NSMenu()
    let playItem = NSMenuItem(
      title: L10n.tr("Play"),
      action: #selector(menuPlaySong(_:)),
      keyEquivalent: ""
    )
    playItem.target = self
    playItem.tag = row
    menu.addItem(playItem)
    let queueItem = NSMenuItem(
      title: L10n.tr("Add to Queue"),
      action: #selector(menuQueueSong(_:)),
      keyEquivalent: ""
    )
    queueItem.target = self
    queueItem.tag = row
    menu.addItem(queueItem)
    return menu
  }

  @objc
  private func menuPlaySong(_ sender: NSMenuItem) {
    play(row: sender.tag)
  }

  @objc
  private func menuQueueSong(_ sender: NSMenuItem) {
    guard sender.tag >= 0, sender.tag < songs.count else { return }
    FmusicKit.shared.player.insertUserQueue(playables: [songs[sender.tag]])
  }

  // MARK: - NSTableViewDataSource

  func numberOfRows(in tableView: NSTableView) -> Int {
    songs.count
  }

  // MARK: - NSTableViewDelegate

  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    let rowView = ThemedRowView()
    rowView.cornerRadius = 5
    rowView.horizontalInset = 10
    return rowView
  }

  func tableView(
    _ tableView: NSTableView,
    viewFor tableColumn: NSTableColumn?,
    row: Int
  )
    -> NSView? {
    guard row < songs.count, let tableColumn else { return nil }
    let song = songs[row]

    switch tableColumn.identifier {
    case Column.artwork:
      let cell = tableView.makeView(withIdentifier: Column.artwork, owner: self) as?
        LMArtworkCellView ?? LMArtworkCellView()
      cell.identifier = Column.artwork
      cell.display(image: LMLibraryArtwork.image(for: song, setting: librarySetting))
      return cell
    case Column.title:
      return textCell(
        Column.title,
        text: song.title,
        font: MacTheme.titleFont,
        color: .labelColor,
        alignment: .left
      )
    case Column.artist:
      return textCell(
        Column.artist,
        text: song.creatorName,
        font: MacTheme.bodyFont,
        color: MacTheme.secondaryTextColor,
        alignment: .left
      )
    case Column.album:
      return textCell(
        Column.album,
        text: song.album?.name ?? "",
        font: MacTheme.bodyFont,
        color: MacTheme.secondaryTextColor,
        alignment: .left
      )
    case Column.duration:
      return textCell(
        Column.duration,
        text: ClockTime(timeInSeconds: song.duration).asShortString(),
        font: MacTheme.tabularBodyFont,
        color: MacTheme.secondaryTextColor,
        alignment: .right
      )
    default:
      return nil
    }
  }

  private func textCell(
    _ identifier: NSUserInterfaceItemIdentifier,
    text: String,
    font: NSFont,
    color: NSColor,
    alignment: NSTextAlignment
  )
    -> NSView {
    let cell = tableView.makeView(withIdentifier: identifier, owner: self) as?
      LMTextCellView ?? LMTextCellView()
    cell.identifier = identifier
    cell.configure(text: text, font: font, color: color, alignment: alignment)
    return cell
  }
}
