//
//  SongsViewController.swift
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

/// Flat song list backed by `NSTableView` (Apple Music style rows with artwork).
@MainActor
final class SongsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
  private let tableView = NSTableView()
  private let scrollView = NSScrollView()
  private let titleLabel = NSTextField(labelWithString: L10n.tr("Songs"))
  private let countLabel = NSTextField(labelWithString: "")

  private var songs: [Song] = []

  private enum Column {
    static let artwork = NSUserInterfaceItemIdentifier("artwork")
    static let title = NSUserInterfaceItemIdentifier("title")
    static let artist = NSUserInterfaceItemIdentifier("artist")
    static let album = NSUserInterfaceItemIdentifier("album")
    static let duration = NSUserInterfaceItemIdentifier("duration")
  }

  override func loadView() {
    let root = NSView()
    root.wantsLayer = true

    titleLabel.font = MacTheme.largeTitleFont
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    countLabel.font = MacTheme.secondaryFont
    countLabel.textColor = MacTheme.secondaryTextColor
    countLabel.translatesAutoresizingMaskIntoConstraints = false

    configureTableView()
    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.drawsBackground = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    root.addSubview(titleLabel)
    root.addSubview(countLabel)
    root.addSubview(scrollView)

    NSLayoutConstraint.activate([
      titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
      titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),

      countLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      countLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),

      scrollView.topAnchor.constraint(equalTo: countLabel.bottomAnchor, constant: 12),
      scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
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

  // MARK: - Table view

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

  // MARK: - Data

  @objc
  private func reloadSongs() {
    let storage = FmusicKit.shared.storage
    guard let accountInfo = storage.settings.accounts.active else {
      songs = []
      tableView.reloadData()
      countLabel.stringValue = ""
      return
    }
    let account = storage.main.library.getAccount(info: accountInfo)
    songs = storage.main.library.getSongs(for: account)
    tableView.reloadData()
    countLabel.stringValue = songs.isEmpty ? "" : String(format: "%d", songs.count)
  }

  private var themePreference: ThemePreference {
    FmusicKit.shared.storage.settings.accounts.activeSetting.read.themePreference
  }

  private var artworkDisplayPreference: ArtworkDisplayPreference {
    FmusicKit.shared.storage.settings.accounts.activeSetting.read.artworkDisplayPreference
  }

  // MARK: - Actions

  @objc
  private func handleDoubleClick() {
    let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
    play(row: row)
  }

  @objc
  private func playSelectedRow() {
    play(row: tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow)
  }

  private func play(row: Int) {
    guard row >= 0, row < songs.count else { return }
    let context = PlayContext(name: L10n.tr("Songs"), index: row, playables: songs)
    FmusicKit.shared.player.play(context: context)
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
        SongArtworkCellView ?? SongArtworkCellView()
      cell.identifier = Column.artwork
      cell.display(
        song: song,
        themePreference: themePreference,
        artworkDisplayPreference: artworkDisplayPreference
      )
      return cell
    case Column.title:
      return textCell(
        identifier: Column.title,
        text: song.title,
        font: MacTheme.titleFont,
        color: .labelColor,
        alignment: .left
      )
    case Column.artist:
      return textCell(
        identifier: Column.artist,
        text: song.creatorName,
        font: MacTheme.bodyFont,
        color: MacTheme.secondaryTextColor,
        alignment: .left
      )
    case Column.album:
      return textCell(
        identifier: Column.album,
        text: song.asSong?.album?.name ?? "",
        font: MacTheme.bodyFont,
        color: MacTheme.secondaryTextColor,
        alignment: .left
      )
    case Column.duration:
      return textCell(
        identifier: Column.duration,
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
    identifier: NSUserInterfaceItemIdentifier,
    text: String,
    font: NSFont,
    color: NSColor,
    alignment: NSTextAlignment
  )
    -> NSView {
    let cell = tableView.makeView(withIdentifier: identifier, owner: self) as?
      SongTextCellView ?? SongTextCellView()
    cell.identifier = identifier
    cell.configure(text: text, font: font, color: color, alignment: alignment)
    return cell
  }
}

// MARK: - SongTextCellView

@MainActor
private final class SongTextCellView: NSTableCellView {
  private let label = NSTextField(labelWithString: "")

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.lineBreakMode = .byTruncatingTail
    addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
      label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
    self.textField = label
  }

  required init?(coder: NSCoder) {
    nil
  }

  func configure(
    text: String,
    font: NSFont,
    color: NSColor,
    alignment: NSTextAlignment
  ) {
    label.stringValue = text
    label.font = font
    label.textColor = color
    label.alignment = alignment
  }
}

// MARK: - SongArtworkCellView

@MainActor
private final class SongArtworkCellView: NSTableCellView {
  private let artworkView = NSImageView()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    artworkView.translatesAutoresizingMaskIntoConstraints = false
    artworkView.imageScaling = .scaleProportionallyUpOrDown
    artworkView.wantsLayer = true
    artworkView.layer?.cornerRadius = 4
    artworkView.layer?.masksToBounds = true
    addSubview(artworkView)
    NSLayoutConstraint.activate([
      artworkView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
      artworkView.centerYAnchor.constraint(equalTo: centerYAnchor),
      artworkView.widthAnchor.constraint(equalToConstant: 32),
      artworkView.heightAnchor.constraint(equalToConstant: 32),
    ])
    self.imageView = artworkView
  }

  required init?(coder: NSCoder) {
    nil
  }

  func display(
    song: Song,
    themePreference: ThemePreference,
    artworkDisplayPreference: ArtworkDisplayPreference
  ) {
    artworkView.image = ArtworkImageLoader.image(
      for: song,
      themePreference: themePreference,
      artworkDisplayPreference: artworkDisplayPreference
    )
  }
}
