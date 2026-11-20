//
//  PlaylistDetailViewController.swift
//  fmusic-macOS
//
//  Playlist detail page in the Catalyst fmusic style: large artwork, name,
//  song count / duration with play & shuffle buttons, then the playlist songs.
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
  private let artworkView = NSImageView()
  private let nameLabel = NSTextField(labelWithString: "")
  private let infoLabel = NSTextField(labelWithString: "")
  private let playButton = NSButton()
  private let shuffleButton = NSButton()
  private let emptyLabel = NSTextField(wrappingLabelWithString: "")
  private let tableView = NSTableView()
  private let scrollView = NSScrollView()
  private let headerView = NSView()

  private var playables: [AbstractPlayable] = []

  private enum Column {
    static let artwork = NSUserInterfaceItemIdentifier("playlistDetailArtwork")
    static let title = NSUserInterfaceItemIdentifier("playlistDetailTitle")
    static let artist = NSUserInterfaceItemIdentifier("playlistDetailArtist")
    static let album = NSUserInterfaceItemIdentifier("playlistDetailAlbum")
    static let duration = NSUserInterfaceItemIdentifier("playlistDetailDuration")
    static let menu = NSUserInterfaceItemIdentifier("playlistDetailMenu")
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
    let root = ThemedBackgroundView()

    artworkView.imageScaling = .scaleProportionallyUpOrDown
    artworkView.wantsLayer = true
    artworkView.layer?.cornerRadius = 12
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

    headerView.translatesAutoresizingMaskIntoConstraints = false
    headerView.addSubview(artworkView)
    headerView.addSubview(nameLabel)
    headerView.addSubview(infoLabel)
    headerView.addSubview(playButton)
    headerView.addSubview(shuffleButton)

    root.addSubview(headerView)
    root.addSubview(scrollView)
    root.addSubview(emptyLabel)

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
    button.isBordered = false
    button.bezelStyle = .regularSquare
    button.attributedTitle = NSAttributedString(
      string: title,
      attributes: [
        .foregroundColor: filled ? NSColor.white : accent,
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
      ]
    )
    button.contentTintColor = filled ? .white : accent
    button.wantsLayer = true
    button.layer?.backgroundColor = (filled ? accent : accent.withAlphaComponent(0.18))
      .cgColor
    button.layer?.cornerRadius = 17
    button.translatesAutoresizingMaskIntoConstraints = false
    button.heightAnchor.constraint(equalToConstant: 34).isActive = true
    button.widthAnchor.constraint(greaterThanOrEqualToConstant: 96).isActive = true
  }

  private func configureTableView() {
    let artworkColumn = NSTableColumn(identifier: Column.artwork)
    artworkColumn.title = ""
    artworkColumn.width = 46
    artworkColumn.minWidth = 46
    artworkColumn.maxWidth = 46

    let titleColumn = NSTableColumn(identifier: Column.title)
    titleColumn.title = L10n.tr("Title")
    titleColumn.width = 300
    titleColumn.minWidth = 140

    let artistColumn = NSTableColumn(identifier: Column.artist)
    artistColumn.title = L10n.tr("Artist")
    artistColumn.width = 160
    artistColumn.minWidth = 110

    let albumColumn = NSTableColumn(identifier: Column.album)
    albumColumn.title = L10n.tr("Album")
    albumColumn.width = 200
    albumColumn.minWidth = 120

    let durationColumn = NSTableColumn(identifier: Column.duration)
    durationColumn.title = L10n.tr("Duration")
    durationColumn.width = 60
    durationColumn.minWidth = 56
    durationColumn.maxWidth = 80

    let menuColumn = NSTableColumn(identifier: Column.menu)
    menuColumn.title = ""
    menuColumn.width = 36
    menuColumn.minWidth = 36
    menuColumn.maxWidth = 36

    [artworkColumn, titleColumn, artistColumn, albumColumn, durationColumn, menuColumn]
      .forEach(tableView.addTableColumn)

    tableView.rowHeight = MacTheme.songRowHeight
    tableView.style = .fullWidth
    tableView.columnAutoresizingStyle = .noColumnAutoresizing
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
    let totalDuration = playables.reduce(0) { $0 + Int($1.duration) }
    let durationText = ClockTime(timeInSeconds: totalDuration).asShortString()
    infoLabel.stringValue = "\(playlist.songCount) \(L10n.tr("Songs")) · \(durationText)"
    artworkView.image = LMLibraryArtwork.image(for: playlist, setting: librarySetting)

    tableView.reloadData()
    emptyLabel.stringValue = L10n.tr("No Results")
    emptyLabel.isHidden = !playables.isEmpty
  }

  override func viewDidLayout() {
    super.viewDidLayout()
    let width = scrollView.contentSize.width
    guard width > 240 else { return }
    let flexible = max(120, width - (46 + 60 + 36))
    for (identifier, fraction, minWidth) in [
      (Column.title, 0.42, 120.0),
      (Column.artist, 0.24, 80.0),
      (Column.album, 0.34, 90.0),
    ] {
      guard let column = tableView.tableColumns.first(where: { $0.identifier == identifier })
      else { continue }
      column.minWidth = minWidth
      column.width = flexible * fraction
    }
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

  @objc
  private func playAll() {
    guard !playables.isEmpty else { return }
    FmusicKit.shared.player.play(context: PlayContext(containable: playlist))
  }

  @objc
  private func playShuffled() {
    guard !playables.isEmpty else { return }
    var shuffled = playables
    shuffled.shuffle()
    FmusicKit.shared.player.play(
      context: PlayContext(containable: playlist, index: 0, playables: shuffled)
    )
  }

  private func play(row: Int) {
    guard row >= 0, row < playables.count else { return }
    FmusicKit.shared.player.play(context: PlayContext(
      containable: playlist,
      index: row,
      playables: playables
    ))
  }

  @objc
  private func rowMenuPressed(_ sender: NSButton) {
    let row = sender.tag
    guard row >= 0, row < playables.count else { return }
    let menu = NSMenu()
    let playItem = NSMenuItem(
      title: L10n.tr("Play"),
      action: #selector(menuPlay(_:)),
      keyEquivalent: ""
    )
    playItem.target = self
    playItem.tag = row
    menu.addItem(playItem)
    let queueItem = NSMenuItem(
      title: L10n.tr("Add to Queue"),
      action: #selector(menuQueue(_:)),
      keyEquivalent: ""
    )
    queueItem.target = self
    queueItem.tag = row
    menu.addItem(queueItem)
    menu.popUp(
      positioning: nil,
      at: NSPoint(x: sender.bounds.midX, y: sender.bounds.minY - 4),
      in: sender
    )
  }

  @objc
  private func menuPlay(_ sender: NSMenuItem) {
    play(row: sender.tag)
  }

  @objc
  private func menuQueue(_ sender: NSMenuItem) {
    guard sender.tag >= 0, sender.tag < playables.count else { return }
    FmusicKit.shared.player.insertUserQueue(playables: [playables[sender.tag]])
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
    case Column.menu:
      return menuButton(row: row)
    default:
      return nil
    }
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
    _ identifier: NSUserInterfaceItemIdentifier,
    text: String,
    font: NSFont,
    color: NSColor,
    alignment: NSTextAlignment
  )
    -> NSTableCellView {
    let cell = tableView.makeView(withIdentifier: identifier, owner: self) as?
      NSTableCellView ?? makeTextCell(identifier)
    if let label = cell.textField {
      label.stringValue = text
      label.font = font
      label.textColor = color
      label.alignment = alignment
    }
    return cell
  }

  private func makeTextCell(_ identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
    let cell = NSTableCellView()
    cell.identifier = identifier
    let label = NSTextField(labelWithString: "")
    label.font = MacTheme.bodyFont
    label.lineBreakMode = .byTruncatingTail
    label.maximumNumberOfLines = 1
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
