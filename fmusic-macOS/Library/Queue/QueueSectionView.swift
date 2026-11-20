//
//  QueueSectionView.swift
//  fmusic-macOS
//
//  Up-next queue list shared by the queue page and the now playing page.
//  Double-clicking a row plays that queue entry through the player facade.
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
import CoreMedia
import fmusicKit

/// Scrollable up-next queue: the user queue first, then the context queue.
@MainActor
final class QueueSectionView: NSView, NSTableViewDataSource, NSTableViewDelegate,
  MusicPlayable {
  private enum Row {
    case header(String)
    case track(AbstractPlayable, PlayerIndex)
  }

  private let tableView = NSTableView()
  private let scrollView = NSScrollView()
  private let placeholderLabel = NSTextField(wrappingLabelWithString: "")

  private var rows: [Row] = []
  private var hasRegisteredNotifier = false

  private enum Column {
    static let item = NSUserInterfaceItemIdentifier("queueItem")
    static let header = NSUserInterfaceItemIdentifier("queueHeader")
  }

  private var player: PlayerFacade { FmusicKit.shared.player }

  // MARK: - Init

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    configure()
  }

  required init?(coder: NSCoder) {
    nil
  }

  private func configure() {
    let column = NSTableColumn(identifier: Column.item)
    column.resizingMask = .autoresizingMask
    tableView.addTableColumn(column)
    tableView.headerView = nil
    tableView.style = .fullWidth
    tableView.selectionHighlightStyle = .regular
    tableView.backgroundColor = .clear
    tableView.dataSource = self
    tableView.delegate = self
    tableView.doubleAction = #selector(handleDoubleClick)
    tableView.target = self

    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.drawsBackground = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    placeholderLabel.font = .systemFont(ofSize: 13)
    placeholderLabel.textColor = .secondaryLabelColor
    placeholderLabel.alignment = .center
    placeholderLabel.translatesAutoresizingMaskIntoConstraints = false

    addSubview(scrollView)
    addSubview(placeholderLabel)
    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

      placeholderLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
      placeholderLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
      placeholderLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
    ])
  }

  // MARK: - Lifecycle

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window != nil {
      if !hasRegisteredNotifier {
        hasRegisteredNotifier = true
        player.addNotifier(notifier: self)
      }
      reload()
    }
  }

  // MARK: - Data

  func reload() {
    var newRows: [Row] = []

    let userQueue = player.getAllUserQueueItems()
    if !userQueue.isEmpty {
      newRows.append(.header(L10n.tr("Next in Queue")))
      for (index, playable) in userQueue.enumerated() {
        newRows.append(.track(playable, PlayerIndex(queueType: .user, index: index)))
      }
    }

    let nextQueue = player.getAllNextQueueItems()
    if !nextQueue.isEmpty {
      newRows.append(.header(L10n.tr("Next from: %@", player.contextName)))
      for (index, playable) in nextQueue.enumerated() {
        newRows.append(.track(playable, PlayerIndex(queueType: .next, index: index)))
      }
    }

    rows = newRows
    tableView.reloadData()
    placeholderLabel.stringValue = L10n.tr("No items in queue")
    placeholderLabel.isHidden = !rows.isEmpty
    scrollView.isHidden = rows.isEmpty
  }

  // MARK: - Actions

  @objc
  private func handleDoubleClick() {
    let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
    guard row >= 0, row < rows.count, case .track(_, let playerIndex) = rows[row] else {
      return
    }
    player.play(playerIndex: playerIndex)
  }

  // MARK: - NSTableViewDataSource

  func numberOfRows(in tableView: NSTableView) -> Int {
    rows.count
  }

  // MARK: - NSTableViewDelegate

  func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
    guard row < rows.count else { return false }
    if case .header = rows[row] { return true }
    return false
  }

  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    guard row < rows.count else { return 44 }
    if case .header = rows[row] { return 26 }
    return 44
  }

  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    guard row < rows.count else { return nil }
    if case .header = rows[row] { return nil }
    let rowView = ThemedRowView()
    rowView.cornerRadius = 5
    rowView.horizontalInset = 8
    return rowView
  }

  func tableView(
    _ tableView: NSTableView,
    viewFor tableColumn: NSTableColumn?,
    row: Int
  )
    -> NSView? {
    guard row < rows.count else { return nil }

    switch rows[row] {
    case .header(let title):
      let cell = tableView.makeView(withIdentifier: Column.header, owner: self) as?
        LMTextCellView ?? LMTextCellView()
      cell.identifier = Column.header
      cell.configure(
        text: title,
        font: .systemFont(ofSize: MacTheme.secondaryFontSize, weight: .semibold),
        color: MacTheme.secondaryTextColor
      )
      return cell
    case .track(let playable, _):
      let cell = tableView.makeView(withIdentifier: Column.item, owner: self) as?
        LMPlayableRowCellView ?? LMPlayableRowCellView()
      cell.identifier = Column.item
      cell.configure(
        image: LMLibraryArtwork.image(for: playable, setting: librarySetting),
        title: playable.title,
        subtitle: playable.creatorName,
        trailing: ClockTime(timeInSeconds: playable.duration).asShortString(),
        artworkSize: 30
      )
      return cell
    }
  }

  private var librarySetting: AccountSetting {
    FmusicKit.shared.storage.settings.accounts.activeSetting.read
  }

  // MARK: - MusicPlayable

  func didStartPlayingFromBeginning() {}

  func didStartPlaying() {
    reload()
  }

  func didPause() {}

  func didStopPlaying() {
    reload()
  }

  func didElapsedTimeChange() {}

  func didLyricsTimeChange(time: CMTime) {}

  func didPlaylistChange() {
    reload()
  }

  func didArtworkChange() {}

  func didNowPlayingInfoChange() {}

  func didShuffleChange() {
    reload()
  }

  func didRepeatChange() {
    reload()
  }

  func didPlaybackRateChange() {}
}
