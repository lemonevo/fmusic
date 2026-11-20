//
//  SearchViewController.swift
//  fmusic-macOS
//
//  Self-contained library search page: an in-page NSSearchField with a result list
//  for songs, albums and artists.
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

/// Search page for the sidebar's `.search` entry.
///
/// The search field lives inside the page (no window toolbar changes), so the Lead
/// only has to map the sidebar item to `SearchViewController()`.
@MainActor
final class SearchViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
  private enum Mode: Int {
    case songs = 0
    case albums = 1
    case artists = 2
  }

  private let titleLabel = NSTextField(labelWithString: L10n.tr("Search"))
  private let searchField = NSSearchField()
  private let modeControl = NSSegmentedControl(
    labels: [L10n.tr("Songs"), L10n.tr("Albums"), L10n.tr("Artists")],
    trackingMode: .selectOne,
    target: nil,
    action: nil
  )
  private let statusLabel = NSTextField(labelWithString: "")
  private let emptyLabel = NSTextField(wrappingLabelWithString: "")
  private let tableView = NSTableView()
  private let scrollView = NSScrollView()

  private var mode: Mode = .songs
  private var songs: [Song] = []
  private var albums: [Album] = []
  private var artists: [Artist] = []

  private enum Column {
    static let artwork = NSUserInterfaceItemIdentifier("searchArtwork")
    static let title = NSUserInterfaceItemIdentifier("searchTitle")
    static let subtitle = NSUserInterfaceItemIdentifier("searchSubtitle")
    static let extra = NSUserInterfaceItemIdentifier("searchExtra")
  }

  // MARK: - Lifecycle

  override func loadView() {
    let root = NSView()
    root.wantsLayer = true

    titleLabel.font = MacTheme.largeTitleFont
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    searchField.placeholderString = L10n.tr("Search")
    searchField.sendsSearchStringImmediately = true
    searchField.sendsWholeSearchString = false
    searchField.target = self
    searchField.action = #selector(searchChanged)
    searchField.translatesAutoresizingMaskIntoConstraints = false

    modeControl.selectedSegment = Mode.songs.rawValue
    modeControl.target = self
    modeControl.action = #selector(modeChanged)
    modeControl.translatesAutoresizingMaskIntoConstraints = false

    statusLabel.font = MacTheme.secondaryFont
    statusLabel.textColor = MacTheme.secondaryTextColor
    statusLabel.translatesAutoresizingMaskIntoConstraints = false

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
    root.addSubview(searchField)
    root.addSubview(modeControl)
    root.addSubview(statusLabel)
    root.addSubview(scrollView)
    root.addSubview(emptyLabel)

    NSLayoutConstraint.activate([
      titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
      titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),

      searchField.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      searchField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
      searchField.widthAnchor.constraint(equalToConstant: 320),

      modeControl.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 12),
      modeControl.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
      modeControl.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -24),

      statusLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      statusLabel.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),

      scrollView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
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
      selector: #selector(libraryChanged),
      name: .librarySongsSynced,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(libraryChanged),
      name: .accountActiveChanged,
      object: nil
    )
    reloadResults()
  }

  override func viewDidAppear() {
    super.viewDidAppear()
    view.window?.makeFirstResponder(searchField)
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
    titleColumn.title = L10n.tr("Title")
    titleColumn.width = 280
    titleColumn.minWidth = 160

    let subtitleColumn = NSTableColumn(identifier: Column.subtitle)
    subtitleColumn.title = L10n.tr("Artist")
    subtitleColumn.width = 200
    subtitleColumn.minWidth = 120

    let extraColumn = NSTableColumn(identifier: Column.extra)
    extraColumn.title = L10n.tr("Album")
    extraColumn.width = 200
    extraColumn.minWidth = 120

    [artworkColumn, titleColumn, subtitleColumn, extraColumn]
      .forEach(tableView.addTableColumn)

    tableView.rowHeight = 44
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

  // MARK: - Data

  private var librarySetting: AccountSetting {
    FmusicKit.shared.storage.settings.accounts.activeSetting.read
  }

  private var currentRowCount: Int {
    switch mode {
    case .songs: return songs.count
    case .albums: return albums.count
    case .artists: return artists.count
    }
  }

  @objc
  private func searchChanged() {
    reloadResults()
  }

  @objc
  private func modeChanged() {
    mode = Mode(rawValue: modeControl.selectedSegment) ?? .songs
    reloadResults()
  }

  @objc
  private func libraryChanged() {
    reloadResults()
  }

  private func reloadResults() {
    let storage = FmusicKit.shared.storage
    let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

    guard let accountInfo = storage.settings.accounts.active else {
      songs = []
      albums = []
      artists = []
      tableView.reloadData()
      statusLabel.stringValue = ""
      showEmptyState(query.isEmpty ? hintText : L10n.tr("No Results"))
      return
    }

    guard !query.isEmpty else {
      songs = []
      albums = []
      artists = []
      tableView.reloadData()
      statusLabel.stringValue = ""
      showEmptyState(hintText)
      return
    }

    let account = storage.main.library.getAccount(info: accountInfo)
    let library = storage.main.library

    switch mode {
    case .songs:
      songs = library.searchSongs(
        for: account,
        searchText: query,
        onlyCached: false,
        displayFilter: .all
      )
    case .albums:
      albums = library.searchAlbums(
        for: account,
        searchText: query,
        onlyCached: false,
        displayFilter: .all
      )
    case .artists:
      artists = library.searchArtists(
        for: account,
        searchText: query,
        onlyCached: false,
        displayFilter: .all
      )
    }

    tableView.reloadData()
    let count = currentRowCount
    if count == 0 {
      statusLabel.stringValue = ""
      showEmptyState(L10n.tr("No Results"))
    } else {
      let noun: String
      switch mode {
      case .songs: noun = L10n.tr("Songs")
      case .albums: noun = L10n.tr("Albums")
      case .artists: noun = L10n.tr("Artists")
      }
      statusLabel.stringValue = "\(count) \(noun)"
      emptyLabel.isHidden = true
    }
  }

  private var hintText: String {
    "\(L10n.tr("Search")): \(L10n.tr("Songs")) · \(L10n.tr("Albums")) · \(L10n.tr("Artists"))"
  }

  private func showEmptyState(_ text: String) {
    emptyLabel.stringValue = text
    emptyLabel.isHidden = false
  }

  // MARK: - Actions

  @objc
  private func handleDoubleClick() {
    let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
    play(row: row)
  }

  private func play(row: Int) {
    guard row >= 0 else { return }
    let player = FmusicKit.shared.player
    switch mode {
    case .songs:
      guard row < songs.count else { return }
      player.play(context: PlayContext(
        name: L10n.tr("Search"),
        index: row,
        playables: songs
      ))
    case .albums:
      guard row < albums.count else { return }
      let album = albums[row]
      guard !album.playables.isEmpty else { return }
      player.play(context: PlayContext(containable: album))
    case .artists:
      guard row < artists.count else { return }
      let artist = artists[row]
      guard !artist.playables.isEmpty else { return }
      player.play(context: PlayContext(containable: artist))
    }
  }

  // MARK: - NSTableViewDataSource

  func numberOfRows(in tableView: NSTableView) -> Int {
    currentRowCount
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
    guard let tableColumn else { return nil }

    switch tableColumn.identifier {
    case Column.artwork:
      let cell = tableView.makeView(withIdentifier: Column.artwork, owner: self) as?
        LMArtworkCellView ?? LMArtworkCellView()
      cell.identifier = Column.artwork
      cell.display(image: artworkImage(row: row))
      return cell
    case Column.title:
      return textCell(
        Column.title,
        text: titleText(row: row),
        font: MacTheme.titleFont,
        color: .labelColor
      )
    case Column.subtitle:
      return textCell(
        Column.subtitle,
        text: subtitleText(row: row),
        font: MacTheme.bodyFont,
        color: MacTheme.secondaryTextColor
      )
    case Column.extra:
      return textCell(
        Column.extra,
        text: extraText(row: row),
        font: MacTheme.bodyFont,
        color: MacTheme.secondaryTextColor
      )
    default:
      return nil
    }
  }

  private func artworkImage(row: Int) -> NSImage? {
    let setting = librarySetting
    switch mode {
    case .songs:
      guard row < songs.count else { return nil }
      return LMLibraryArtwork.image(for: songs[row], setting: setting)
    case .albums:
      guard row < albums.count else { return nil }
      return LMLibraryArtwork.image(for: albums[row], setting: setting)
    case .artists:
      guard row < artists.count else { return nil }
      return LMLibraryArtwork.image(for: artists[row], setting: setting)
    }
  }

  private func titleText(row: Int) -> String {
    switch mode {
    case .songs:
      return row < songs.count ? songs[row].title : ""
    case .albums:
      return row < albums.count ? albums[row].name : ""
    case .artists:
      return row < artists.count ? artists[row].name : ""
    }
  }

  private func subtitleText(row: Int) -> String {
    switch mode {
    case .songs:
      return row < songs.count ? songs[row].creatorName : ""
    case .albums:
      return row < albums.count ? (albums[row].artist?.name ?? "") : ""
    case .artists:
      if row < artists.count {
        return "\(artists[row].songCount) \(L10n.tr("Songs"))"
      }
      return ""
    }
  }

  private func extraText(row: Int) -> String {
    switch mode {
    case .songs:
      guard row < songs.count else { return "" }
      return songs[row].album?.name ?? ""
    case .albums:
      guard row < albums.count else { return "" }
      return "\(albums[row].songCount) \(L10n.tr("Songs"))"
    case .artists:
      return ""
    }
  }

  private func textCell(
    _ identifier: NSUserInterfaceItemIdentifier,
    text: String,
    font: NSFont,
    color: NSColor
  )
    -> NSView {
    let cell = tableView.makeView(withIdentifier: identifier, owner: self) as?
      LMTextCellView ?? LMTextCellView()
    cell.identifier = identifier
    cell.configure(text: text, font: font, color: color)
    return cell
  }
}
