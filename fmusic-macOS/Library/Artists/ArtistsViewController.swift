//
//  ArtistsViewController.swift
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

/// `.artists` — artist list with circular artwork, name and album/song counts.
///
/// Double-click (or the context menu) starts playback of the whole artist. The list
/// respects the global `artistsFilterSetting` (all / album artists / favourites).
@MainActor
final class ArtistsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
  private let titleLabel = NSTextField(labelWithString: L10n.tr("Artists"))
  private let subtitleLabel = NSTextField(labelWithString: "")
  private let tableView = NSTableView()
  private let scrollView = NSScrollView()
  private let emptyLabel = NSTextField(labelWithString: "")

  private var artists: [Artist] = []

  private let columnIdentifier = NSUserInterfaceItemIdentifier("artistColumn")
  private let cellIdentifier = NSUserInterfaceItemIdentifier("artistCell")

  // MARK: - Lifecycle

  override func loadView() {
    let root = ThemedBackgroundView()

    titleLabel.font = MacTheme.largeTitleFont
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    subtitleLabel.font = MacTheme.secondaryFont
    subtitleLabel.textColor = MacTheme.secondaryTextColor
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

    configureTableView()
    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    emptyLabel.font = MacTheme.bodyFont
    emptyLabel.textColor = MacTheme.secondaryTextColor
    emptyLabel.alignment = .center
    emptyLabel.maximumNumberOfLines = 2
    emptyLabel.isHidden = true
    emptyLabel.translatesAutoresizingMaskIntoConstraints = false

    root.addSubview(titleLabel)
    root.addSubview(subtitleLabel)
    root.addSubview(scrollView)
    root.addSubview(emptyLabel)

    NSLayoutConstraint.activate([
      titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
      titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
      titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -24),

      subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
      subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -24),

      scrollView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 10),
      scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

      emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
      emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
      emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 24),
      emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -24),
    ])

    self.view = root
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    let center = NotificationCenter.default
    center.addObserver(
      self,
      selector: #selector(reloadArtists),
      name: .librarySongsSynced,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(reloadArtists),
      name: .accountActiveChanged,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(themeDidChange),
      name: .macThemeColorChanged,
      object: nil
    )
    reloadArtists()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  // MARK: - Configuration

  private func configureTableView() {
    let column = NSTableColumn(identifier: columnIdentifier)
    column.resizingMask = .autoresizingMask
    tableView.addTableColumn(column)
    tableView.headerView = nil
    tableView.style = .fullWidth
    tableView.rowSizeStyle = .custom
    tableView.rowHeight = GridMetrics.artistRowHeight
    tableView.intercellSpacing = NSSize(width: 0, height: 0)
    tableView.backgroundColor = .clear
    tableView.gridStyleMask = []
    tableView.selectionHighlightStyle = .regular
    tableView.allowsMultipleSelection = false
    tableView.allowsEmptySelection = true
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
  private func reloadArtists() {
    let storage = FmusicKit.shared.storage
    guard let accountInfo = storage.settings.accounts.active else {
      artists = []
      tableView.reloadData()
      subtitleLabel.stringValue = ""
      emptyLabel.stringValue = emptyMessage
      emptyLabel.isHidden = false
      return
    }

    let library = storage.main.library
    let account = library.getAccount(info: accountInfo)
    switch storage.settings.user.artistsFilterSetting {
    case .all:
      artists = library.getArtists(for: account)
    case .favorites:
      artists = library.getFavoriteArtists(for: account)
    case .albumArtists:
      artists = library.getAlbumArtists(for: account)
    }

    tableView.reloadData()
    subtitleLabel.stringValue = artists.isEmpty ? "" : LibraryCountText.artists(artists.count)
    emptyLabel.stringValue = emptyMessage
    emptyLabel.isHidden = !artists.isEmpty
  }

  @objc
  private func themeDidChange() {
    tableView.reloadData()
  }

  private var emptyMessage: String {
    L10n.tr("No %@", L10n.tr("Artists"))
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
    guard row >= 0, row < artists.count else { return }
    LibraryPlayback.play(artist: artists[row])
  }

  // MARK: - NSTableViewDataSource

  func numberOfRows(in tableView: NSTableView) -> Int {
    artists.count
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
    guard row >= 0, row < artists.count else { return nil }
    let cell = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as?
      ArtistCellView ?? ArtistCellView()
    cell.identifier = cellIdentifier
    cell.configure(artist: artists[row])
    return cell
  }
}

// MARK: - ArtistCellView

/// Row content: circular artist artwork, name and a "N Albums · N Songs" detail line.
@MainActor
private final class ArtistCellView: NSTableCellView {
  private let artworkView = NSImageView()
  private let nameLabel = NSTextField(labelWithString: "")
  private let detailLabel = NSTextField(labelWithString: "")

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    artworkView.translatesAutoresizingMaskIntoConstraints = false
    artworkView.imageScaling = .scaleProportionallyUpOrDown
    artworkView.wantsLayer = true
    artworkView.layer?.cornerRadius = GridMetrics.artistArtworkSize / 2
    artworkView.layer?.masksToBounds = true

    nameLabel.font = MacTheme.titleFont
    nameLabel.lineBreakMode = .byTruncatingTail
    nameLabel.maximumNumberOfLines = 1
    nameLabel.translatesAutoresizingMaskIntoConstraints = false

    detailLabel.font = MacTheme.secondaryFont
    detailLabel.textColor = MacTheme.secondaryTextColor
    detailLabel.lineBreakMode = .byTruncatingTail
    detailLabel.maximumNumberOfLines = 1
    detailLabel.translatesAutoresizingMaskIntoConstraints = false

    addSubview(artworkView)
    addSubview(nameLabel)
    addSubview(detailLabel)

    NSLayoutConstraint.activate([
      artworkView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      artworkView.centerYAnchor.constraint(equalTo: centerYAnchor),
      artworkView.widthAnchor.constraint(equalToConstant: GridMetrics.artistArtworkSize),
      artworkView.heightAnchor.constraint(equalToConstant: GridMetrics.artistArtworkSize),

      nameLabel.leadingAnchor.constraint(equalTo: artworkView.trailingAnchor, constant: 12),
      nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
      nameLabel.bottomAnchor.constraint(equalTo: centerYAnchor, constant: -1),

      detailLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
      detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
      detailLabel.topAnchor.constraint(equalTo: centerYAnchor, constant: 1),
    ])
  }

  required init?(coder: NSCoder) {
    nil
  }

  func configure(artist: Artist) {
    artworkView.image = LibraryAppearance.artworkImage(for: artist)
    nameLabel.stringValue = artist.name

    let albumCount = artist.albumCount > 0 ? artist.albumCount : artist.albums.count
    let songCount = artist.songCount > 0 ? artist.songCount : artist.songs.count
    detailLabel.stringValue = [
      LibraryCountText.albums(albumCount),
      LibraryCountText.songs(songCount),
    ].joined(separator: " · ")
  }
}
