//
//  ArtistDetailViewController.swift
//  fmusic-macOS
//
//  Artist detail page in the Catalyst fmusic style: round artist image, name,
//  album/song counts, play & shuffle buttons, then the artist's albums and songs.
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

/// Detail page for a single artist.
@MainActor
final class ArtistDetailViewController: NSViewController, ContentSearchable,
  NSTableViewDataSource, NSTableViewDelegate {
  private let artist: Artist
  private let artworkView = NSImageView()
  private let nameLabel = NSTextField(labelWithString: "")
  private let infoLabel = NSTextField(labelWithString: "")
  private let playButton = NSButton()
  private let shuffleButton = NSButton()
  private let tableView = NSTableView()
  private let scrollView = NSScrollView()
  private let headerView = NSView()

  private var albums: [Album] = []
  private var songs: [AbstractPlayable] = []
  private var filterText = ""

  private enum Column {
    static let main = NSUserInterfaceItemIdentifier("artistDetailMain")
    static let detail = NSUserInterfaceItemIdentifier("artistDetailDetail")
    static let menu = NSUserInterfaceItemIdentifier("artistDetailMenu")
  }

  private enum Row {
    case album(Album)
    case song(AbstractPlayable, index: Int)
  }

  private var rows: [Row] = []

  init(artist: Artist) {
    self.artist = artist
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    nil
  }

  var contentSearchPlaceholder: String? {
    L10n.tr("Search in \"%@\"", L10n.tr("Artists"))
  }

  func contentSearchDidChange(text: String) {
    filterText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    applyFilter()
  }

  // MARK: - Lifecycle

  override func loadView() {
    let root = ThemedBackgroundView()

    artworkView.imageScaling = .scaleProportionallyUpOrDown
    artworkView.wantsLayer = true
    artworkView.layer?.cornerRadius = 90
    artworkView.layer?.masksToBounds = true
    artworkView.translatesAutoresizingMaskIntoConstraints = false

    nameLabel.font = .systemFont(ofSize: 26, weight: .bold)
    nameLabel.lineBreakMode = .byTruncatingTail
    nameLabel.translatesAutoresizingMaskIntoConstraints = false

    infoLabel.font = .systemFont(ofSize: 12.5, weight: .regular)
    infoLabel.textColor = MacTheme.secondaryTextColor
    infoLabel.translatesAutoresizingMaskIntoConstraints = false

    configurePlayButton(
      playButton,
      title: L10n.tr("Play"),
      symbol: "play.fill",
      filled: true
    )
    playButton.target = self
    playButton.action = #selector(playAll)
    configurePlayButton(
      shuffleButton,
      title: L10n.tr("Shuffle"),
      symbol: "shuffle",
      filled: false
    )
    shuffleButton.target = self
    shuffleButton.action = #selector(playShuffled)

    configureTableView()
    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    headerView.translatesAutoresizingMaskIntoConstraints = false
    headerView.addSubview(artworkView)
    headerView.addSubview(nameLabel)
    headerView.addSubview(infoLabel)
    headerView.addSubview(playButton)
    headerView.addSubview(shuffleButton)

    root.addSubview(headerView)
    root.addSubview(scrollView)

    NSLayoutConstraint.activate([
      headerView.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
      headerView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      headerView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      headerView.heightAnchor.constraint(equalToConstant: 200),

      artworkView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 36),
      artworkView.topAnchor.constraint(equalTo: headerView.topAnchor),
      artworkView.widthAnchor.constraint(equalToConstant: 180),
      artworkView.heightAnchor.constraint(equalToConstant: 180),

      nameLabel.leadingAnchor.constraint(equalTo: artworkView.trailingAnchor, constant: 28),
      nameLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -36),
      nameLabel.bottomAnchor.constraint(equalTo: artworkView.centerYAnchor, constant: -8),

      infoLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
      infoLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
      infoLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 6),

      playButton.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
      playButton.topAnchor.constraint(equalTo: infoLabel.bottomAnchor, constant: 18),

      shuffleButton.leadingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: 12),
      shuffleButton.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),

      scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 16),
      scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
    ])

    self.view = root
    reloadContent()
  }

  private func configurePlayButton(
    _ button: NSButton,
    title: String,
    symbol: String,
    filled: Bool
  ) {
    let accent = MacTheme.accentColor
    button.title = title
    button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    button.imagePosition = .imageLeading
    button.imageHugsTitle = true
    button.imageScaling = .scaleProportionallyDown
    // System push button with the accent bezel colour instead of a hand-drawn pill.
    button.isBordered = true
    button.bezelStyle = .push
    button.bezelColor = filled ? accent : accent.withAlphaComponent(0.28)
    button.contentTintColor = filled ? NSColor.white : accent
    button.font = .systemFont(ofSize: 13, weight: .medium)
    button.attributedTitle = NSAttributedString(
      string: title,
      attributes: [
        .foregroundColor: filled ? NSColor.white : accent,
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
      ]
    )
    button.translatesAutoresizingMaskIntoConstraints = false
    button.heightAnchor.constraint(equalToConstant: 34).isActive = true
    button.widthAnchor.constraint(greaterThanOrEqualToConstant: 96).isActive = true
  }
  private func configureTableView() {
    tableView.style = .inset
    tableView.backgroundColor = .clear
    tableView.headerView = nil
    tableView.rowHeight = 40
    tableView.intercellSpacing = NSSize(width: 0, height: 0)
    tableView.selectionHighlightStyle = .regular
    tableView.allowsMultipleSelection = false
    tableView.dataSource = self
    tableView.delegate = self
    tableView.target = self
    tableView.doubleAction = #selector(doubleClickedRow)
    tableView.translatesAutoresizingMaskIntoConstraints = false

    // Section headers are rendered as grouped rows so the table stays simple.
    let main = NSTableColumn(identifier: Column.main)
    main.width = 400
    main.title = ""
    tableView.addTableColumn(main)
    let detail = NSTableColumn(identifier: Column.detail)
    detail.width = 100
    detail.title = ""
    tableView.addTableColumn(detail)
    let menu = NSTableColumn(identifier: Column.menu)
    menu.width = 36
    menu.title = ""
    tableView.addTableColumn(menu)
  }

  // MARK: - Data

  private func reloadContent() {
    nameLabel.stringValue = artist.name
    artworkView.image = LibraryAppearance.artworkImage(for: artist)
    let albumText = artist.albumCount == 1
      ? L10n.tr("%d Album", artist.albumCount)
      : L10n.tr("%d Albums", artist.albumCount)
    let songText = artist.songCount == 1
      ? L10n.tr("%d Song", artist.songCount)
      : L10n.tr("%d Songs", artist.songCount)
    infoLabel.stringValue = "\(albumText) · \(songText)"

    albums = artist.albums
    songs = artist.playables
    applyFilter()
  }

  private func applyFilter() {
    let query = filterText.localizedLowercase
    let filteredAlbums = query.isEmpty
      ? albums
      : albums.filter { $0.name.localizedLowercase.contains(query) }
    let filteredSongs = query.isEmpty
      ? songs
      : songs.filter {
        $0.title.localizedLowercase.contains(query) ||
          $0.creatorName.localizedLowercase.contains(query)
      }
    rows = []
    filteredAlbums.forEach { rows.append(.album($0)) }
    for (index, song) in filteredSongs.enumerated() {
      rows.append(.song(song, index: index))
    }
    tableView.reloadData()
  }

  override func viewDidLayout() {
    super.viewDidLayout()
    let detailWidth: CGFloat = 100
    let menuWidth: CGFloat = 36
    let mainWidth = max(160, tableView.bounds.width - detailWidth - menuWidth)
    if let column = tableView.tableColumns.first(where: { $0.identifier == Column.main }) {
      column.width = mainWidth
    }
  }

  // MARK: - Actions

  @objc
  private func playAll() {
    guard !songs.isEmpty else { return }
    FmusicKit.shared.player.play(context: PlayContext(containable: artist))
  }

  @objc
  private func playShuffled() {
    guard !songs.isEmpty else { return }
    var shuffled = songs
    shuffled.shuffle()
    FmusicKit.shared.player.play(
      context: PlayContext(containable: artist, index: 0, playables: shuffled)
    )
  }

  @objc
  private func doubleClickedRow() {
    let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
    guard row >= 0, row < rows.count else { return }
    switch rows[row] {
    case let .album(album):
      MainViewController.current?.openAlbum(album)
    case let .song(song, _):
      FmusicKit.shared.player.play(
        context: PlayContext(containable: artist, index: 0, playables: [song])
      )
    }
  }

  @objc
  private func rowMenuPressed(_ sender: NSButton) {
    let row = sender.tag
    guard row >= 0, row < rows.count else { return }
    let menu = NSMenu()
    switch rows[row] {
    case let .album(album):
      let open = NSMenuItem(
        title: L10n.tr("Show Album"),
        action: #selector(menuOpenAlbum(_:)),
        keyEquivalent: ""
      )
      open.target = self
      open.tag = row
      menu.addItem(open)
      let play = NSMenuItem(
        title: L10n.tr("Play"),
        action: #selector(menuPlayAlbum(_:)),
        keyEquivalent: ""
      )
      play.target = self
      play.tag = row
      menu.addItem(play)
      _ = album
    case let .song(song, _):
      let play = NSMenuItem(
        title: L10n.tr("Play"),
        action: #selector(menuPlaySong(_:)),
        keyEquivalent: ""
      )
      play.target = self
      play.tag = row
      menu.addItem(play)
      let queue = NSMenuItem(
        title: L10n.tr("Add to Queue"),
        action: #selector(menuQueueSong(_:)),
        keyEquivalent: ""
      )
      queue.target = self
      queue.tag = row
      menu.addItem(queue)
      _ = song
    }
    menu.popUp(
      positioning: nil,
      at: NSPoint(x: sender.bounds.midX, y: sender.bounds.minY - 4),
      in: sender
    )
  }

  @objc
  private func menuOpenAlbum(_ sender: NSMenuItem) {
    guard sender.tag < rows.count, case let .album(album) = rows[sender.tag] else { return }
    MainViewController.current?.openAlbum(album)
  }

  @objc
  private func menuPlayAlbum(_ sender: NSMenuItem) {
    guard sender.tag < rows.count, case let .album(album) = rows[sender.tag] else { return }
    LibraryPlayback.play(album: album)
  }

  @objc
  private func menuPlaySong(_ sender: NSMenuItem) {
    guard sender.tag < rows.count,
          case let .song(song, _) = rows[sender.tag] else { return }
    FmusicKit.shared.player.play(
      context: PlayContext(containable: artist, index: 0, playables: [song])
    )
  }

  @objc
  private func menuQueueSong(_ sender: NSMenuItem) {
    guard sender.tag < rows.count,
          case let .song(song, _) = rows[sender.tag] else { return }
    FmusicKit.shared.player.insertUserQueue(playables: [song])
  }

  // MARK: - NSTableViewDataSource / Delegate

  func numberOfRows(in tableView: NSTableView) -> Int {
    rows.count
  }

  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    guard row < rows.count else { return 40 }
    switch rows[row] {
    case .album: return 52
    case .song: return 40
    }
  }

  func tableView(
    _ tableView: NSTableView,
    viewFor tableColumn: NSTableColumn?,
    row: Int
  )
    -> NSView? {
    guard row >= 0, row < rows.count, let tableColumn else { return nil }
    switch rows[row] {
    case let .album(album):
      switch tableColumn.identifier {
      case Column.main: return albumCell(album, row: row)
      case Column.detail:
        return textCell(
          identifier: "artistAlbumYear",
          text: album.year > 0 ? "\(album.year)" : "",
          color: MacTheme.secondaryTextColor,
          alignment: .right
        )
      case Column.menu: return menuButton(row: row)
      default: return nil
      }
    case let .song(song, index):
      switch tableColumn.identifier {
      case Column.main:
        return songCell(song, index: index)
      case Column.detail:
        return textCell(
          identifier: "artistSongDuration",
          text: ClockTime(timeInSeconds: song.duration).asShortString(),
          color: MacTheme.secondaryTextColor,
          alignment: .right
        )
      case Column.menu: return menuButton(row: row)
      default: return nil
      }
    }
  }

  private func albumCell(_ album: Album, row: Int) -> NSTableCellView {
    let identifier = NSUserInterfaceItemIdentifier("artistAlbumCell")
    let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as?
      NSTableCellView ?? makeAlbumCell(identifier: identifier)
    cell.textField?.stringValue = album.name
    cell.imageView?.image = LibraryAppearance.artworkImage(for: album)
    return cell
  }

  private func makeAlbumCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
    let cell = NSTableCellView()
    cell.identifier = identifier
    let image = NSImageView()
    image.imageScaling = .scaleProportionallyUpOrDown
    image.wantsLayer = true
    image.layer?.cornerRadius = 5
    image.layer?.masksToBounds = true
    image.translatesAutoresizingMaskIntoConstraints = false
    let label = NSTextField(labelWithString: "")
    label.font = .systemFont(ofSize: 13)
    label.lineBreakMode = .byTruncatingTail
    label.translatesAutoresizingMaskIntoConstraints = false
    cell.addSubview(image)
    cell.addSubview(label)
    cell.imageView = image
    cell.textField = label
    NSLayoutConstraint.activate([
      image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
      image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
      image.widthAnchor.constraint(equalToConstant: 40),
      image.heightAnchor.constraint(equalToConstant: 40),
      label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 10),
      label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
      label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
    ])
    return cell
  }

  private func songCell(_ song: AbstractPlayable, index: Int) -> NSTableCellView {
    let identifier = NSUserInterfaceItemIdentifier("artistSongCell")
    let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as?
      NSTableCellView ?? makeSongCell(identifier: identifier)
    cell.textField?.stringValue = "\(index + 1)   \(song.title)"
    return cell
  }

  private func makeSongCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
    let cell = NSTableCellView()
    cell.identifier = identifier
    let label = NSTextField(labelWithString: "")
    label.font = .systemFont(ofSize: 13)
    label.lineBreakMode = .byTruncatingTail
    label.translatesAutoresizingMaskIntoConstraints = false
    cell.addSubview(label)
    cell.textField = label
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
      label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
      label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
    ])
    return cell
  }

  private func menuButton(row: Int) -> NSView {
    let button = NSButton()
    button.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)
    button.isBordered = false
    button.bezelStyle = .regularSquare
    button.imagePosition = .imageOnly
    button.contentTintColor = .secondaryLabelColor
    button.target = self
    button.action = #selector(rowMenuPressed(_:))
    button.tag = row
    button.translatesAutoresizingMaskIntoConstraints = false
    button.widthAnchor.constraint(equalToConstant: 24).isActive = true
    button.heightAnchor.constraint(equalToConstant: 24).isActive = true
    let wrapper = NSView()
    wrapper.addSubview(button)
    NSLayoutConstraint.activate([
      button.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
      button.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
    ])
    return wrapper
  }

  private func textCell(
    identifier: String,
    text: String,
    color: NSColor,
    alignment: NSTextAlignment
  )
    -> NSTableCellView {
    let reuseIdentifier = NSUserInterfaceItemIdentifier(identifier)
    let cell = tableView.makeView(withIdentifier: reuseIdentifier, owner: nil) as?
      NSTableCellView ?? makeTextCell(identifier: reuseIdentifier)
    cell.textField?.stringValue = text
    cell.textField?.textColor = color
    cell.textField?.alignment = alignment
    return cell
  }

  private func makeTextCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
    let cell = NSTableCellView()
    cell.identifier = identifier
    let label = NSTextField(labelWithString: "")
    label.font = .systemFont(ofSize: 13)
    label.lineBreakMode = .byTruncatingTail
    label.translatesAutoresizingMaskIntoConstraints = false
    cell.addSubview(label)
    cell.textField = label
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
      label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
      label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
    ])
    return cell
  }
}
