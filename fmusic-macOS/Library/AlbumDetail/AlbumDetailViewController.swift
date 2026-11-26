//
//  AlbumDetailViewController.swift
//  fmusic-macOS
//
//  Album detail page in the style of the Catalyst fmusic app: large artwork,
//  title/artist/metadata with play & shuffle buttons, and the album's songs.
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

/// Detail page for a single album.
@MainActor
final class AlbumDetailViewController: NSViewController, ContentSearchable,
  NSTableViewDataSource, NSTableViewDelegate {
  private let album: Album
  private let artworkView = NSImageView()
  private let titleLabel = NSTextField(labelWithString: "")
  private let artistLabel = NSTextField(labelWithString: "")
  private let infoLabel = NSTextField(labelWithString: "")
  private let playButton = NSButton()
  private let shuffleButton = NSButton()
  private let tableView = InteractiveTableView()
  private let scrollView = NSScrollView()
  private let headerView = NSView()

  private var playables: [AbstractPlayable] = []
  private var filteredPlayables: [AbstractPlayable] = []
  private var filterText = ""

  private enum Column {
    static let number = NSUserInterfaceItemIdentifier("albumDetailNumber")
    static let title = NSUserInterfaceItemIdentifier("albumDetailTitle")
    static let artist = NSUserInterfaceItemIdentifier("albumDetailArtist")
    static let duration = NSUserInterfaceItemIdentifier("albumDetailDuration")
    static let menu = NSUserInterfaceItemIdentifier("albumDetailMenu")
  }

  init(album: Album) {
    self.album = album
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    nil
  }

  var contentSearchPlaceholder: String? {
    L10n.tr("Search in \"%@\"", L10n.tr("Albums"))
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
    artworkView.layer?.cornerRadius = 12
    artworkView.layer?.masksToBounds = true
    artworkView.translatesAutoresizingMaskIntoConstraints = false

    titleLabel.font = .systemFont(ofSize: 26, weight: .bold)
    titleLabel.lineBreakMode = .byTruncatingTail
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    artistLabel.font = .systemFont(ofSize: 18, weight: .regular)
    artistLabel.textColor = MacTheme.accentColor
    artistLabel.lineBreakMode = .byTruncatingTail
    artistLabel.translatesAutoresizingMaskIntoConstraints = false

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
    headerView.addSubview(titleLabel)
    headerView.addSubview(artistLabel)
    headerView.addSubview(infoLabel)
    headerView.addSubview(playButton)
    headerView.addSubview(shuffleButton)

    root.addSubview(headerView)
    root.addSubview(scrollView)

    NSLayoutConstraint.activate([
      headerView.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
      headerView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      headerView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      headerView.heightAnchor.constraint(equalToConstant: 240),

      artworkView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 36),
      artworkView.topAnchor.constraint(equalTo: headerView.topAnchor),
      artworkView.widthAnchor.constraint(equalToConstant: 224),
      artworkView.heightAnchor.constraint(equalToConstant: 224),

      titleLabel.leadingAnchor.constraint(equalTo: artworkView.trailingAnchor, constant: 28),
      titleLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -36),
      titleLabel.bottomAnchor.constraint(equalTo: artworkView.centerYAnchor, constant: -6),

      artistLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      artistLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
      artistLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),

      infoLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      infoLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
      infoLabel.topAnchor.constraint(equalTo: artistLabel.bottomAnchor, constant: 10),

      playButton.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      playButton.topAnchor.constraint(equalTo: infoLabel.bottomAnchor, constant: 20),

      shuffleButton.leadingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: 12),
      shuffleButton.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),

      scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 24),
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
    button.isBordered = false
    button.bezelStyle = .regularSquare
    button.font = .systemFont(ofSize: 13, weight: .medium)
    let foreground = filled ? NSColor.white : accent
    button.attributedTitle = NSAttributedString(
      string: title,
      attributes: [
        .foregroundColor: foreground,
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
      ]
    )
    button.contentTintColor = foreground
    button.wantsLayer = true
    button.layer?.backgroundColor = (filled ? accent : accent.withAlphaComponent(0.18))
      .cgColor
    button.layer?.cornerRadius = 17
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
    tableView.allowsMultipleSelection = true
    tableView.dataSource = self
    tableView.delegate = self
    tableView.target = self
    tableView.doubleAction = #selector(playRow)
    tableView.onReturn = { [weak self] in
      self?.playRow()
    }
    tableView.onContextMenu = { [weak self] row in
      self?.makeMenu(for: row)
    }
    tableView.translatesAutoresizingMaskIntoConstraints = false

    addColumn(Column.number, width: 48, title: "")
    addColumn(Column.title, width: 420, title: L10n.tr("Title"))
    addColumn(Column.artist, width: 190, title: L10n.tr("Artist"))
    addColumn(Column.duration, width: 64, title: L10n.tr("Duration"))
    addColumn(Column.menu, width: 36, title: "")
  }

  private func addColumn(
    _ identifier: NSUserInterfaceItemIdentifier,
    width: CGFloat,
    title: String
  ) {
    let column = NSTableColumn(identifier: identifier)
    column.width = width
    column.minWidth = 20
    column.title = title
    tableView.addTableColumn(column)
  }

  // MARK: - Data

  private func reloadContent() {
    titleLabel.stringValue = album.name
    artistLabel.stringValue = album.artist?.name ?? ""
    artworkView.image = LibraryAppearance.artworkImage(for: album)

    playables = album.playables
    let totalDuration = playables.reduce(0) { $0 + Int($1.duration) }
    let durationText = ClockTime(timeInSeconds: Int(totalDuration)).asShortString()
    infoLabel.stringValue = "\(playables.count) \(L10n.tr("Songs")) · \(durationText)"
    applyFilter()
  }

  private func applyFilter() {
    if filterText.isEmpty {
      filteredPlayables = playables
    } else {
      let query = filterText.localizedLowercase
      filteredPlayables = playables.filter {
        $0.title.localizedLowercase.contains(query) ||
          $0.creatorName.localizedLowercase.contains(query)
      }
    }
    tableView.reloadData()
  }

  override func viewDidLayout() {
    super.viewDidLayout()
    // The title column absorbs the remaining width.
    let fixedWidth: CGFloat = 48 + 190 + 64 + 36
    let available = max(scrollView.contentView.bounds.width, view.bounds.width)
    if let titleColumn = tableView.tableColumns.first(where: { $0.identifier == Column.title }) {
      titleColumn.width = max(120, available - fixedWidth)
    }
  }

  // MARK: - Actions

  @objc
  private func playAll() {
    guard !playables.isEmpty else { return }
    FmusicKit.shared.player.play(context: PlayContext(containable: album))
  }

  @objc
  private func playShuffled() {
    guard !playables.isEmpty else { return }
    var shuffled = playables
    shuffled.shuffle()
    FmusicKit.shared.player.play(
      context: PlayContext(containable: album, index: 0, playables: shuffled)
    )
  }

  @objc
  private func playRow() {
    let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
    guard row >= 0, row < filteredPlayables.count else { return }
    FmusicKit.shared.player.play(
      context: PlayContext(
        containable: album,
        index: row,
        playables: filteredPlayables
      )
    )
  }

  private func makeMenu(for row: Int) -> NSMenu? {
    guard row >= 0, row < filteredPlayables.count else { return nil }
    let menu = NSMenu()
    let play = NSMenuItem(
      title: L10n.tr("Play"),
      action: #selector(menuPlayRow(_:)),
      keyEquivalent: ""
    )
    play.target = self
    play.tag = row
    menu.addItem(play)
    let queue = NSMenuItem(
      title: L10n.tr("Add to Queue"),
      action: #selector(menuQueueRow(_:)),
      keyEquivalent: ""
    )
    queue.target = self
    queue.tag = row
    menu.addItem(queue)
    return menu
  }

  @objc
  private func rowMenuPressed(_ sender: NSButton) {
    guard let menu = makeMenu(for: sender.tag) else { return }
    menu.popUp(
      positioning: nil,
      at: NSPoint(x: sender.bounds.midX, y: sender.bounds.minY - 4),
      in: sender
    )
  }

  @objc
  private func menuPlayRow(_ sender: NSMenuItem) {
    let row = sender.tag
    guard row >= 0, row < filteredPlayables.count else { return }
    FmusicKit.shared.player.play(
      context: PlayContext(
        containable: album,
        index: row,
        playables: filteredPlayables
      )
    )
  }

  @objc
  private func menuQueueRow(_ sender: NSMenuItem) {
    let row = sender.tag
    guard row >= 0, row < filteredPlayables.count else { return }
    FmusicKit.shared.player.insertUserQueue(playables: [filteredPlayables[row]])
  }

  // MARK: - NSTableViewDataSource / Delegate

  func numberOfRows(in tableView: NSTableView) -> Int {
    filteredPlayables.count
  }

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
    guard row >= 0, row < filteredPlayables.count, let tableColumn else { return nil }
    let playable = filteredPlayables[row]
    switch tableColumn.identifier {
    case Column.number:
      return textCell(
        identifier: "albumDetailNumberCell",
        text: "\(row + 1)",
        color: MacTheme.secondaryTextColor,
        alignment: .right
      )
    case Column.title:
      return textCell(
        identifier: "albumDetailTitleCell",
        text: playable.title,
        color: .labelColor,
        alignment: .left
      )
    case Column.artist:
      return textCell(
        identifier: "albumDetailArtistCell",
        text: playable.creatorName,
        color: MacTheme.secondaryTextColor,
        alignment: .left
      )
    case Column.duration:
      return textCell(
        identifier: "albumDetailDurationCell",
        text: ClockTime(timeInSeconds: playable.duration).asShortString(),
        color: MacTheme.secondaryTextColor,
        alignment: .right
      )
    case Column.menu:
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
    default:
      return nil
    }
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
    if let label = cell.textField {
      label.stringValue = text
      label.textColor = color
      label.alignment = alignment
    }
    return cell
  }

  private func makeTextCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
    let cell = NSTableCellView()
    cell.identifier = identifier
    let label = NSTextField(labelWithString: "")
    label.font = .systemFont(ofSize: 13)
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
