//
//  PlaylistDetailViewController.swift
//  fmusic-macOS
//
//  Playlist detail page: header (back, artwork, name, song count) plus the
//  playlist's songs. Double-click starts playback of the playlist.
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

/// Detail page pushed by `PlaylistsViewController` for one playlist.
@MainActor
final class PlaylistDetailViewController: NSViewController, NSTableViewDataSource,
  NSTableViewDelegate {
  var onBack: (() -> Void)?

  private let playlist: Playlist
  private let backButton = NSButton()
  private let artworkView = NSImageView()
  private let nameLabel = NSTextField(labelWithString: "")
  private let infoLabel = NSTextField(labelWithString: "")
  private let emptyLabel = NSTextField(wrappingLabelWithString: "")
  private let tableView = NSTableView()
  private let scrollView = NSScrollView()

  private var playables: [AbstractPlayable] = []

  private enum Column {
    static let artwork = NSUserInterfaceItemIdentifier("playlistDetailArtwork")
    static let title = NSUserInterfaceItemIdentifier("playlistDetailTitle")
    static let artist = NSUserInterfaceItemIdentifier("playlistDetailArtist")
    static let album = NSUserInterfaceItemIdentifier("playlistDetailAlbum")
    static let duration = NSUserInterfaceItemIdentifier("playlistDetailDuration")
  }

  init(playlist: Playlist) {
    self.playlist = playlist
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    nil
  }

  // MARK: - Lifecycle

  override func loadView() {
    let root = NSView()
    root.wantsLayer = true

    backButton.image = NSImage(
      systemSymbolName: "chevron.left",
      accessibilityDescription: L10n.tr("Playlists")
    )
    backButton.isBordered = false
    backButton.bezelStyle = .regularSquare
    backButton.imagePosition = .imageLeading
    backButton.title = L10n.tr("Playlists")
    backButton.font = MacTheme.bodyFont
    backButton.contentTintColor = MacTheme.accentColor
    backButton.target = self
    backButton.action = #selector(goBack)
    backButton.translatesAutoresizingMaskIntoConstraints = false

    artworkView.imageScaling = .scaleProportionallyUpOrDown
    artworkView.wantsLayer = true
    artworkView.layer?.cornerRadius = 8
    artworkView.layer?.masksToBounds = true
    artworkView.translatesAutoresizingMaskIntoConstraints = false

    nameLabel.font = .systemFont(ofSize: 24, weight: .bold)
    nameLabel.lineBreakMode = .byTruncatingTail
    nameLabel.translatesAutoresizingMaskIntoConstraints = false

    infoLabel.font = MacTheme.bodyFont
    infoLabel.textColor = MacTheme.secondaryTextColor
    infoLabel.translatesAutoresizingMaskIntoConstraints = false

    emptyLabel.font = .systemFont(ofSize: MacTheme.bodyFontSize)
    emptyLabel.textColor = MacTheme.secondaryTextColor
    emptyLabel.alignment = .center
    emptyLabel.translatesAutoresizingMaskIntoConstraints = false

    configureTableView()
    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.drawsBackground = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    let header = NSView()
    header.translatesAutoresizingMaskIntoConstraints = false

    root.addSubview(backButton)
    root.addSubview(header)
    header.addSubview(artworkView)
    header.addSubview(nameLabel)
    header.addSubview(infoLabel)
    root.addSubview(scrollView)
    root.addSubview(emptyLabel)

    NSLayoutConstraint.activate([
      backButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
      backButton.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),

      header.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 10),
      header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
      header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
      header.heightAnchor.constraint(equalToConstant: 120),

      artworkView.leadingAnchor.constraint(equalTo: header.leadingAnchor),
      artworkView.centerYAnchor.constraint(equalTo: header.centerYAnchor),
      artworkView.widthAnchor.constraint(equalToConstant: 120),
      artworkView.heightAnchor.constraint(equalToConstant: 120),

      nameLabel.leadingAnchor.constraint(equalTo: artworkView.trailingAnchor, constant: 18),
      nameLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor),
      nameLabel.bottomAnchor.constraint(equalTo: header.centerYAnchor, constant: -4),

      infoLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
      infoLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
      infoLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 6),

      scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
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

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  private func configureTableView() {
    let artworkColumn = NSTableColumn(identifier: Column.artwork)
    artworkColumn.title = ""
    artworkColumn.width = 46
    artworkColumn.minWidth = 46
    artworkColumn.maxWidth = 46

    let titleColumn = NSTableColumn(identifier: Column.title)
    titleColumn.title = L10n.tr("Songs")
    titleColumn.width = 300
    titleColumn.minWidth = 160

    let artistColumn = NSTableColumn(identifier: Column.artist)
    artistColumn.title = L10n.tr("Artist")
    artistColumn.width = 160
    artistColumn.minWidth = 120

    let albumColumn = NSTableColumn(identifier: Column.album)
    albumColumn.title = L10n.tr("Album")
    albumColumn.width = 200
    albumColumn.minWidth = 120

    let durationColumn = NSTableColumn(identifier: Column.duration)
    durationColumn.title = L10n.tr("Duration")
    durationColumn.width = 60
    durationColumn.minWidth = 56
    durationColumn.maxWidth = 80

    [artworkColumn, titleColumn, artistColumn, albumColumn, durationColumn]
      .forEach(tableView.addTableColumn)

    tableView.rowHeight = MacTheme.songRowHeight
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
  }

  private var librarySetting: AccountSetting {
    FmusicKit.shared.storage.settings.accounts.activeSetting.read
  }

  // MARK: - Data

  @objc
  private func reloadSongs() {
    let library = FmusicKit.shared.storage.main.library
    let items = library.getPlaylistItems(playlist: playlist)
    playables = items.compactMap {
      PlaylistItem(library: library, managedObject: $0).playable
    }

    nameLabel.stringValue = playlist.name
    infoLabel.stringValue = "\(playlist.songCount) \(L10n.tr("Songs"))"
    artworkView.image = LMLibraryArtwork.image(for: playlist, setting: librarySetting)

    tableView.reloadData()
    emptyLabel.stringValue = L10n.tr("No Results")
    emptyLabel.isHidden = !playables.isEmpty
  }

  // MARK: - Actions

  @objc
  private func goBack() {
    onBack?()
  }

  @objc
  private func handleDoubleClick() {
    let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
    play(row: row)
  }

  private func play(row: Int) {
    guard row >= 0, row < playables.count else { return }
    FmusicKit.shared.player.play(context: PlayContext(
      containable: playlist,
      index: row,
      playables: playables
    ))
  }

  // MARK: - NSTableViewDataSource

  func numberOfRows(in tableView: NSTableView) -> Int {
    playables.count
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
    guard row < playables.count, let tableColumn else { return nil }
    let playable = playables[row]

    switch tableColumn.identifier {
    case Column.artwork:
      let cell = tableView.makeView(withIdentifier: Column.artwork, owner: self) as?
        LMArtworkCellView ?? LMArtworkCellView()
      cell.identifier = Column.artwork
      cell.display(image: LMLibraryArtwork.image(for: playable, setting: librarySetting))
      return cell
    case Column.title:
      return textCell(
        Column.title,
        text: playable.title,
        font: MacTheme.titleFont,
        color: .labelColor,
        alignment: .left
      )
    case Column.artist:
      return textCell(
        Column.artist,
        text: playable.creatorName,
        font: MacTheme.bodyFont,
        color: MacTheme.secondaryTextColor,
        alignment: .left
      )
    case Column.album:
      return textCell(
        Column.album,
        text: playable.asSong?.album?.name ?? "",
        font: MacTheme.bodyFont,
        color: MacTheme.secondaryTextColor,
        alignment: .left
      )
    case Column.duration:
      return textCell(
        Column.duration,
        text: ClockTime(timeInSeconds: playable.duration).asShortString(),
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
