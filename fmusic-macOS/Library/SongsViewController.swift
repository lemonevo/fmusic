//
//  SongsViewController.swift
//  fmusic-macOS
//
//  Flat song list, single custom row cell (Catalyst `PlayableTableCell` style):
//  artwork, title, artist · album, duration and a per-row ··· menu.
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

/// Flat song list backed by `NSTableView` with one flexible custom row cell.
@MainActor
final class SongsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
  private let tableView = NSTableView()
  private let scrollView = NSScrollView()
  private let titleLabel = NSTextField(labelWithString: L10n.tr("Songs"))
  private let countLabel = NSTextField(labelWithString: "")

  private var songs: [Song] = []
  private let cellIdentifier = NSUserInterfaceItemIdentifier("songListCell")
  private let columnIdentifier = NSUserInterfaceItemIdentifier("songListColumn")

  override func loadView() {
    let root = ThemedBackgroundView()

    titleLabel.font = MacTheme.largeTitleFont
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    countLabel.font = MacTheme.secondaryFont
    countLabel.textColor = MacTheme.secondaryTextColor
    countLabel.translatesAutoresizingMaskIntoConstraints = false

    configureTableView()
    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    root.addSubview(titleLabel)
    root.addSubview(countLabel)
    root.addSubview(scrollView)

    NSLayoutConstraint.activate([
      titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 32),
      titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
      countLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      countLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
      scrollView.topAnchor.constraint(equalTo: countLabel.bottomAnchor, constant: 12),
      scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
      scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
      scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),
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
    let column = NSTableColumn(identifier: columnIdentifier)
    column.title = ""
    column.minWidth = 200
    column.resizingMask = .autoresizingMask
    tableView.addTableColumn(column)
    tableView.headerView = nil
    tableView.rowHeight = 44
    tableView.intercellSpacing = NSSize(width: 0, height: 0)
    tableView.style = .plain
    tableView.backgroundColor = .clear
    tableView.selectionHighlightStyle = .regular
    tableView.allowsMultipleSelection = false
    tableView.allowsEmptySelection = true
    tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    tableView.dataSource = self
    tableView.delegate = self
    tableView.target = self
    tableView.doubleAction = #selector(handleDoubleClick)
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

  private var librarySetting: AccountSetting {
    FmusicKit.shared.storage.settings.accounts.activeSetting.read
  }

  // MARK: - Actions

  @objc
  private func handleDoubleClick() {
    let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
    play(row: row)
  }

  private func play(row: Int) {
    guard row >= 0, row < songs.count else { return }
    let context = PlayContext(name: L10n.tr("Songs"), index: row, playables: songs)
    FmusicKit.shared.player.play(context: context)
  }

  @objc
  private func rowMenuPressed(_ sender: NSButton) {
    let row = sender.tag
    guard row >= 0, row < songs.count else { return }
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
    menu.popUp(
      positioning: nil,
      at: NSPoint(x: sender.bounds.midX, y: sender.bounds.minY - 4),
      in: sender
    )
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
    guard row >= 0, row < songs.count else { return nil }
    let cell = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as?
      SongListCellView ?? SongListCellView()
    cell.identifier = cellIdentifier
    cell.configure(
      playable: songs[row],
      setting: librarySetting,
      row: row,
      target: self,
      menuAction: #selector(rowMenuPressed(_:))
    )
    return cell
  }
}

// MARK: - SongListCellView

/// One song row: artwork, title, artist · album, duration and the ··· menu.
@MainActor
final class SongListCellView: NSTableCellView {
  private let artworkView = NSImageView()
  private let titleLabel = NSTextField(labelWithString: "")
  private let detailLabel = NSTextField(labelWithString: "")
  private let durationLabel = NSTextField(labelWithString: "")
  private let menuButton = NSButton()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    artworkView.imageScaling = .scaleProportionallyUpOrDown
    artworkView.wantsLayer = true
    artworkView.layer?.cornerRadius = 5
    artworkView.layer?.masksToBounds = true
    artworkView.translatesAutoresizingMaskIntoConstraints = false

    titleLabel.font = .systemFont(ofSize: 13.5)
    titleLabel.lineBreakMode = .byTruncatingTail
    titleLabel.maximumNumberOfLines = 1
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    detailLabel.font = .systemFont(ofSize: 11)
    detailLabel.textColor = MacTheme.secondaryTextColor
    detailLabel.lineBreakMode = .byTruncatingTail
    detailLabel.maximumNumberOfLines = 1
    detailLabel.translatesAutoresizingMaskIntoConstraints = false

    durationLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    durationLabel.textColor = MacTheme.secondaryTextColor
    durationLabel.alignment = .right
    durationLabel.translatesAutoresizingMaskIntoConstraints = false
    durationLabel.setContentHuggingPriority(.required, for: .horizontal)
    durationLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

    menuButton.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)
    menuButton.isBordered = false
    menuButton.bezelStyle = .regularSquare
    menuButton.imagePosition = .imageOnly
    menuButton.contentTintColor = .secondaryLabelColor
    menuButton.translatesAutoresizingMaskIntoConstraints = false

    addSubview(artworkView)
    addSubview(titleLabel)
    addSubview(detailLabel)
    addSubview(durationLabel)
    addSubview(menuButton)

    NSLayoutConstraint.activate([
      artworkView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
      artworkView.centerYAnchor.constraint(equalTo: centerYAnchor),
      artworkView.widthAnchor.constraint(equalToConstant: 36),
      artworkView.heightAnchor.constraint(equalToConstant: 36),

      menuButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
      menuButton.centerYAnchor.constraint(equalTo: centerYAnchor),
      menuButton.widthAnchor.constraint(equalToConstant: 24),
      menuButton.heightAnchor.constraint(equalToConstant: 24),

      durationLabel.trailingAnchor.constraint(equalTo: menuButton.leadingAnchor, constant: -8),
      durationLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

      titleLabel.leadingAnchor.constraint(equalTo: artworkView.trailingAnchor, constant: 10),
      titleLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: durationLabel.leadingAnchor,
        constant: -12
      ),
      titleLabel.bottomAnchor.constraint(equalTo: centerYAnchor, constant: -1),

      detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      detailLabel.trailingAnchor.constraint(equalTo: durationLabel.leadingAnchor, constant: -12),
      detailLabel.topAnchor.constraint(equalTo: centerYAnchor, constant: 1),
    ])
  }

  required init?(coder: NSCoder) {
    nil
  }

  func configure(
    playable: AbstractPlayable,
    setting: AccountSetting,
    row: Int,
    target: AnyObject,
    menuAction: Selector
  ) {
    titleLabel.stringValue = playable.title
    let artist = playable.creatorName
    let album = playable.asSong?.album?.name ?? ""
    detailLabel.stringValue = album.isEmpty ? artist : "\(artist) · \(album)"
    durationLabel.stringValue = ClockTime(timeInSeconds: playable.duration).asShortString()
    artworkView.image = LMLibraryArtwork.image(for: playable, setting: setting)
    menuButton.target = target
    menuButton.action = menuAction
    menuButton.tag = row
  }
}
