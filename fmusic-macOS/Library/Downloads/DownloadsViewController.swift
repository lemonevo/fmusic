//
//  DownloadsViewController.swift
//  fmusic-macOS
//
//  Downloads page (sidebar `.downloads`): the active account's cached songs, with
//  the account's current cache size. Double-click plays a song from the cache.
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

/// Cached (downloaded) songs of the active account, using the flat song row style.
@MainActor
final class DownloadsViewController: NSViewController, NSTableViewDataSource,
  NSTableViewDelegate {
  private let titleLabel = NSTextField(labelWithString: L10n.tr("Downloads"))
  private let countLabel = NSTextField(labelWithString: "")
  private let removeDownloadsButton = NSButton()
  private let emptyLabel = NSTextField(wrappingLabelWithString: "")
  private let tableView = InteractiveTableView()
  private let scrollView = NSScrollView()

  private var songs: [Song] = []
  private var reloadGeneration = 0
  private var isRemovingDownloads = false

  private enum Column {
    static let artwork = NSUserInterfaceItemIdentifier("downloadArtwork")
    static let title = NSUserInterfaceItemIdentifier("downloadTitle")
    static let artist = NSUserInterfaceItemIdentifier("downloadArtist")
    static let album = NSUserInterfaceItemIdentifier("downloadAlbum")
    static let duration = NSUserInterfaceItemIdentifier("downloadDuration")
  }

  // MARK: - Lifecycle

  override func loadView() {
    let root = ThemedBackgroundView()

    titleLabel.font = MacTheme.largeTitleFont
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    countLabel.font = MacTheme.secondaryFont
    countLabel.textColor = MacTheme.secondaryTextColor
    countLabel.translatesAutoresizingMaskIntoConstraints = false

    removeDownloadsButton.title = L10n.tr("Remove Download")
    removeDownloadsButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
    removeDownloadsButton.imagePosition = .imageLeading
    removeDownloadsButton.bezelStyle = .rounded
    removeDownloadsButton.target = self
    removeDownloadsButton.action = #selector(removeSelectedDownloads)
    removeDownloadsButton.toolTip = L10n.tr(
      "Remove downloaded files from this Mac. The songs remain in your library."
    )
    removeDownloadsButton.isEnabled = false
    removeDownloadsButton.translatesAutoresizingMaskIntoConstraints = false

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
    root.addSubview(removeDownloadsButton)
    root.addSubview(scrollView)
    root.addSubview(emptyLabel)

    NSLayoutConstraint.activate([
      titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
      titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
      titleLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: removeDownloadsButton.leadingAnchor, constant: -16
      ),

      countLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      countLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
      countLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: removeDownloadsButton.leadingAnchor, constant: -16
      ),

      removeDownloadsButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
      removeDownloadsButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

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
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(reloadSongs),
      name: .downloadFinishedSuccess,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(themeDidChange),
      name: .macThemeColorChanged,
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
    titleColumn.title = L10n.tr("Title")
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
    tableView.onDelete = { [weak self] in
      self?.removeSelectedDownloads()
    }
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
    menu.addItem(.separator())
    let selectedIDs = selectedSongIDs
    let removeItem = NSMenuItem(
      title: L10n.tr(selectedIDs.count > 1 ? "Remove Downloads" : "Remove Download"),
      action: #selector(menuRemoveDownloads(_:)),
      keyEquivalent: ""
    )
    removeItem.target = self
    removeItem.representedObject = selectedIDs
    menu.addItem(removeItem)
    return menu
  }

  private var librarySetting: AccountSetting {
    FmusicKit.shared.storage.settings.accounts.activeSetting.read
  }

  // MARK: - Data

  @objc
  private func reloadSongs() {
    let storage = FmusicKit.shared.storage
    reloadGeneration += 1
    let generation = reloadGeneration
    guard let accountInfo = storage.settings.accounts.active else {
      songs = []
      tableView.reloadData()
      updateRemoveDownloadsButton()
      countLabel.stringValue = ""
      emptyLabel.stringValue = L10n.tr("No %@", L10n.tr("Downloads"))
      emptyLabel.isHidden = false
      return
    }
    let accountID = storage.main.library.getAccount(info: accountInfo).managedObject.objectID
    Task { [weak self] in
      guard let self else { return }
      let ids = try? await storage.async.performAndGet { companion
        -> [NSManagedObjectID] in
        let account = companion.library.getAccount(managedObjectId: accountID)
        return companion.library.getCachedSongs(for: account).map(\.managedObject.objectID)
      }
      guard generation == self.reloadGeneration,
            storage.settings.accounts.active == accountInfo else { return }
      let context = storage.main.context
      self.songs = (ids ?? [])
        .compactMap { context.object(with: $0) as? SongMO }
        .compactMap { Song(managedObject: $0) }
      var infoParts = [LibraryCountText.songs(self.songs.count)]
      let cacheSize = CacheFileManager.shared.getPlayableCacheSize(for: accountInfo)
      if cacheSize > 0 {
        infoParts.append(cacheSize.asByteString)
      }
      self.countLabel.stringValue = self.songs.isEmpty
        ? ""
        : infoParts.joined(separator: " · ")
      self.tableView.reloadData()
      self.updateRemoveDownloadsButton()
      self.emptyLabel.stringValue = L10n.tr("No %@", L10n.tr("Downloads"))
      self.emptyLabel.isHidden = !self.songs.isEmpty
    }
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
  private func menuPlaySong(_ sender: NSMenuItem) {
    play(row: sender.tag)
  }

  @objc
  private func menuQueueSong(_ sender: NSMenuItem) {
    guard sender.tag >= 0, sender.tag < songs.count else { return }
    FmusicKit.shared.player.insertUserQueue(playables: [songs[sender.tag]])
  }

  private var selectedSongIDs: [NSManagedObjectID] {
    tableView.selectedRowIndexes.compactMap { row in
      songs.indices.contains(row) ? songs[row].managedObject.objectID : nil
    }
  }

  private func updateRemoveDownloadsButton() {
    let count = selectedSongIDs.count
    removeDownloadsButton.title = L10n.tr(count > 1 ? "Remove Downloads" : "Remove Download")
    removeDownloadsButton.isEnabled = count > 0 && !isRemovingDownloads
  }

  @objc
  private func removeSelectedDownloads() {
    removeDownloads(with: selectedSongIDs)
  }

  @objc
  private func menuRemoveDownloads(_ sender: NSMenuItem) {
    guard let ids = sender.representedObject as? [NSManagedObjectID] else { return }
    removeDownloads(with: ids)
  }

  private func removeDownloads(with ids: [NSManagedObjectID]) {
    guard !ids.isEmpty, !isRemovingDownloads else { return }
    isRemovingDownloads = true
    updateRemoveDownloadsButton()
    let storage = FmusicKit.shared.storage
    Task { [weak self] in
      guard let self else { return }
      defer {
        self.isRemovingDownloads = false
        self.updateRemoveDownloadsButton()
        self.reloadSongs()
      }
      do {
        try await storage.async.performAndGet { companion in
          for id in ids {
            guard let song = try companion.context.existingObject(with: id) as? SongMO else {
              continue
            }
            companion.library.deleteCache(ofPlayable: Song(managedObject: song))
          }
        }
      } catch {
        let alert = NSAlert()
        alert.messageText = L10n.tr("Unable to Remove Downloads")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: L10n.tr("OK"))
        if let window = self.view.window {
          await alert.beginSheetModal(for: window)
        } else {
          alert.runModal()
        }
      }
    }
  }

  private func play(row: Int) {
    guard row >= 0, row < songs.count else { return }
    FmusicKit.shared.player.play(context: PlayContext(
      name: L10n.tr("Downloads"),
      index: row,
      playables: songs
    ))
  }

  // MARK: - NSTableViewDataSource

  func numberOfRows(in tableView: NSTableView) -> Int {
    songs.count
  }

  // MARK: - NSTableViewDelegate

  func tableViewSelectionDidChange(_ notification: Notification) {
    updateRemoveDownloadsButton()
  }

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
      cell.display(
        image: LMLibraryArtwork.image(for: song, setting: librarySetting),
        size: 32
      )
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
        text: song.asSong?.album?.name ?? "",
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
    cell.toolTip = text
    return cell
  }
}
