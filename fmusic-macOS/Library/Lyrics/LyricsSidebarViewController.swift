//
//  LyricsSidebarViewController.swift
//  fmusic-macOS
//
//  The lyrics side pane, ported 1:1 from the Catalyst `LyricsVC` / `LyricTableCell`:
//  left aligned lines (24 pt semibold, white at 60 %), the active line at 29 pt bold
//  with the sung characters filling in progressively, translations underneath,
//  click-to-seek and smooth scrolling that follows playback.
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

/// Lyrics side pane: same typography and word-fill behaviour as the Catalyst lyrics view.
@MainActor
final class LyricsSidebarViewController: NSViewController, MusicPlayable,
  NSTableViewDataSource, NSTableViewDelegate {
  // Catalyst `LyricsView.lineSpacing` (space above each row) and `LyricTableCell` fonts.
  private static let rowSpacing: CGFloat = 30
  private static let horizontalInset: CGFloat = 20
  private static let activeFontSize: CGFloat = 29
  private static let inactiveFontSize: CGFloat = 24
  private static let translationFontSize: CGFloat = 17
  private static let activeTextColor = NSColor.white
  private static let activeDimTextColor = NSColor.white.withAlphaComponent(0.55)
  private static let inactiveTextColor = NSColor.white.withAlphaComponent(0.60)
  private static let translationTextColor = NSColor.white.withAlphaComponent(0.72)

  private let scrollView = NSScrollView()
  private let tableView = NSTableView()
  private let statusLabel = NSTextField(labelWithString: "")
  private let cellIdentifier = NSUserInterfaceItemIdentifier("lyricsSidebarCell")
  private let columnIdentifier = NSUserInterfaceItemIdentifier("lyricsSidebarColumn")

  private var lyrics: StructuredLyrics?
  private var tracker = LyricsLineTracker()
  private var loadedSongID: String?
  private var currentLine = -1
  private var lastActiveTime: TimeInterval = -1
  private var syllableCache = [[LyricsSyllableTiming]]()

  nonisolated(unsafe) private var syncTimer: Timer?

  private var player: PlayerFacade { FmusicKit.shared.player }
  private var storage: PersistentStorage { FmusicKit.shared.storage }

  override func loadView() {
    let root = ThemedBackgroundView()

    tableView.headerView = nil
    tableView.backgroundColor = .clear
    tableView.rowHeight = 44
    tableView.intercellSpacing = NSSize(width: 0, height: 0)
    tableView.style = .plain
    tableView.selectionHighlightStyle = .none
    tableView.allowsEmptySelection = true
    tableView.allowsMultipleSelection = false
    tableView.focusRingType = .none
    tableView.usesAutomaticRowHeights = true
    tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    tableView.dataSource = self
    tableView.delegate = self
    tableView.target = self
    tableView.action = #selector(rowClicked)
    tableView.translatesAutoresizingMaskIntoConstraints = false

    let column = NSTableColumn(identifier: columnIdentifier)
    column.title = ""
    column.minWidth = 100
    column.resizingMask = .autoresizingMask
    tableView.addTableColumn(column)

    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    statusLabel.font = .systemFont(ofSize: 15)
    statusLabel.textColor = MacTheme.secondaryTextColor
    statusLabel.alignment = .center
    statusLabel.maximumNumberOfLines = 0
    statusLabel.translatesAutoresizingMaskIntoConstraints = false

    root.addSubview(scrollView)
    root.addSubview(statusLabel)

    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: root.topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

      statusLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
      statusLabel.centerYAnchor.constraint(equalTo: root.centerYAnchor),
      statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 16),
      statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -16),
    ])

    self.view = root
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    player.addNotifier(notifier: self)
    loadLyrics(force: true)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(themeColorChanged),
      name: .macThemeColorChanged,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(onlineLyricsDidUpdate(_:)),
      name: .onlineLyricsDidUpdate,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(lyricsOffsetChanged),
      name: .lyricsOffsetChanged,
      object: nil
    )

    // The player notifications are not delivered at a fixed rate; the Catalyst lyrics
    // view runs its own clock for the character fill, so mirror that here.
    syncTimer = Timer(
      timeInterval: 1.0 / 60.0,
      target: self,
      selector: #selector(syncTick),
      userInfo: nil,
      repeats: true
    )
    if let syncTimer {
      RunLoop.main.add(syncTimer, forMode: .common)
    }
  }

  deinit {
    syncTimer?.invalidate()
    NotificationCenter.default.removeObserver(self)
  }

  // MARK: - Lyrics loading

  private func loadLyrics(force: Bool = false) {
    guard let song = player.currentlyPlaying?.asSong else {
      loadedSongID = nil
      lyrics = nil
      tracker.setLyrics(nil)
      syllableCache = []
      renderStatus(L10n.tr("Play a song to see the lyrics here."))
      return
    }
    let songID = song.id
    guard force || loadedSongID != songID else { return }
    loadedSongID = songID
    lyrics = nil
    tracker.setLyrics(nil)
    currentLine = -1
    syllableCache = []
    renderStatus("")

    guard let account = song.account, let lyricsRelFilePath = song.lyricsRelFilePath else {
      requestOnlineLyrics(for: song)
      return
    }
    Task { @MainActor [weak self] in
      guard let self else { return }
      let lyricsList = try? await FmusicKit.shared.getMeta(account.info)
        .librarySyncer.parseLyrics(relFilePath: lyricsRelFilePath)
      guard self.loadedSongID == songID else { return }
      guard let structured = lyricsList?.getFirstSyncedLyricsOrUnsyncedAsDefault(),
            !structured.line.isEmpty
      else {
        self.requestOnlineLyrics(for: song)
        return
      }
      self.apply(lyrics: structured)
    }
  }

  private func requestOnlineLyrics(for song: Song) {
    guard OnlineLyricsService.shared.canMatchLyrics(for: song) else {
      renderStatus(L10n.tr("No Lyrics"))
      return
    }
    Task { @MainActor [weak self] in
      let found = await OnlineLyricsService.shared.matchLyrics(for: song)
      guard let self, self.loadedSongID == song.id else { return }
      if !found, self.lyrics == nil {
        self.renderStatus(L10n.tr("No Lyrics"))
      }
    }
  }

  @objc
  private func onlineLyricsDidUpdate(_ notification: Notification) {
    guard let songID = notification.userInfo?["songID"] as? String,
          player.currentlyPlaying?.id == songID
    else { return }
    loadLyrics(force: true)
  }

  @objc
  private func lyricsOffsetChanged() {
    updateActiveLine(force: true)
  }

  @objc
  private func themeColorChanged() {
    tableView.reloadData()
  }

  // MARK: - Rendering

  private func apply(lyrics structuredLyrics: StructuredLyrics) {
    lyrics = structuredLyrics
    tracker.setLyrics(structuredLyrics)
    // Same syllable tables the Catalyst cell model builds for the character fill.
    let durations = LyricsTimingMap.estimatedDurations(for: structuredLyrics.line)
    syllableCache = structuredLyrics.line.indices.map { index in
      LyricsTimingMap.syllables(
        for: structuredLyrics.line[index],
        estimatedDuration: durations.object(at: index) ?? 0
      )
    }
    statusLabel.isHidden = true
    currentLine = -1
    tableView.reloadData()
    updateActiveLine(force: true)
  }

  private func renderStatus(_ text: String) {
    statusLabel.stringValue = text
    statusLabel.isHidden = text.isEmpty
    lyrics = nil
    tracker.setLyrics(nil)
    syllableCache = []
    currentLine = -1
    tableView.reloadData()
  }

  @objc
  private func syncTick() {
    stepScrollSpring()
    updateActiveLine(force: false)
  }

  private func updateActiveLine(force: Bool) {
    guard let lyrics, !lyrics.line.isEmpty else { return }
    let time = player.elapsedTime
    guard force || abs(time - lastActiveTime) > 0.02 else { return }
    lastActiveTime = time

    let offsetSeconds = (Double(lyrics.offset) +
      Double(storage.settings.user.lyricsOffsetMs)) / 1000.0
    let position = max(0, time + offsetSeconds)
    var index = -1
    for (lineIndex, line) in lyrics.line.enumerated() {
      guard let start = line.start else { continue }
      if Double(start) / 1000.0 <= position {
        index = lineIndex
      } else {
        break
      }
    }
    let previous = currentLine
    if index != previous {
      currentLine = index
      if previous >= 0 {
        reconfigureRow(previous)
      }
      if index >= 0 {
        reconfigureRow(index)
        scrollTargetY = scrollTarget(for: index)
      }
    } else if index >= 0 {
      // Only this row's fill changes; never reload the table while the clock runs.
      reconfigureRow(index)
    }
  }

  private func reconfigureRow(_ row: Int) {
    guard let lyrics,
          lyrics.line.indices.contains(row),
          let cell = tableView.view(
            atColumn: 0,
            row: row,
            makeIfNecessary: false
          ) as? LyricsSidebarCellView
    else { return }
    cell.configure(
      line: lyrics.line[row],
      isActive: row == currentLine,
      syllables: syllableCache.indices.contains(row) ? syllableCache[row] : [],
      time: playbackLyricsTime(),
      rowSpacing: Self.rowSpacing,
      inset: Self.horizontalInset
    )
  }

  private func playbackLyricsTime() -> TimeInterval {
    guard let lyrics else { return player.elapsedTime }
    return player.elapsedTime + (
      Double(lyrics.offset) + Double(storage.settings.user.lyricsOffsetMs)
    ) / 1000.0
  }

  // MARK: - Spring scrolling (same constants as the Catalyst LyricsView)

  private var scrollTargetY: CGFloat?
  private var scrollVelocity: CGFloat = 0
  private var lastSpringTimestamp = CACurrentMediaTime()

  private func scrollTarget(for row: Int) -> CGFloat {
    let rowRect = tableView.rect(ofRow: row)
    let visible = scrollView.contentView.bounds.height
    let maxY = max(0, tableView.bounds.height - visible)
    return min(max(0, rowRect.midY - visible / 2), maxY)
  }

  private func stepScrollSpring() {
    guard let target = scrollTargetY else { return }
    let now = CACurrentMediaTime()
    var deltaTime = now - lastSpringTimestamp
    lastSpringTimestamp = now
    guard deltaTime > 0, deltaTime <= 0.1 else { return }

    let clip = scrollView.contentView
    let current = clip.bounds.origin.y
    if abs(target - current) <= 1.6, abs(scrollVelocity) < 40 {
      scrollTargetY = nil
      scrollVelocity = 0
      clip.scroll(to: NSPoint(x: 0, y: target))
      scrollView.reflectScrolledClipView(clip)
      return
    }
    let stiffness: CGFloat = 190
    let damping: CGFloat = 1.05 * 2 * sqrt(stiffness)
    let displacement = current - target
    scrollVelocity += (-stiffness * displacement - damping * scrollVelocity) *
      CGFloat(deltaTime)
    var newY = current + scrollVelocity * CGFloat(deltaTime)
    let maxY = max(0, tableView.bounds.height - clip.bounds.height)
    newY = min(max(newY, 0), maxY)
    if abs(target - newY) < 0.35, abs(scrollVelocity) < 4 {
      scrollTargetY = nil
      scrollVelocity = 0
      newY = target
    }
    clip.scroll(to: NSPoint(x: 0, y: newY))
    scrollView.reflectScrolledClipView(clip)
  }

  @objc
  private func rowClicked() {
    let row = tableView.clickedRow
    guard row >= 0,
          let lyrics,
          lyrics.line.indices.contains(row),
          let start = lyrics.line[row].start
    else { return }
    player.seek(toSecond: Double(start) / 1000.0)
    currentLine = row
    updateActiveLine(force: true)
  }

  // MARK: - NSTableViewDataSource

  func numberOfRows(in tableView: NSTableView) -> Int {
    lyrics?.line.count ?? 0
  }

  // MARK: - NSTableViewDelegate

  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    guard let lyrics, lyrics.line.indices.contains(row) else { return 0 }
    let line = lyrics.line[row]
    let isActive = row == currentLine
    let availableWidth = max(
      80,
      tableView.bounds.width - Self.horizontalInset * 2
    )
    let font = NSFont.systemFont(
      ofSize: isActive ? Self.activeFontSize : Self.inactiveFontSize,
      weight: isActive ? .bold : .semibold
    )
    var height = Self.rowSpacing + Self.textHeight(
      line.value.isEmpty ? " " : line.value,
      font: font,
      width: availableWidth
    )
    let translation = line.translation?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let translation, !translation.isEmpty {
      height += Self.textHeight(
        translation,
        font: .systemFont(ofSize: Self.translationFontSize),
        width: availableWidth
      ) + 6
    }
    return max(44, ceil(height))
  }

  func tableView(
    _ tableView: NSTableView,
    viewFor tableColumn: NSTableColumn?,
    row: Int
  )
    -> NSView? {
    guard let lyrics, lyrics.line.indices.contains(row) else { return nil }
    let cell = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as?
      LyricsSidebarCellView ?? LyricsSidebarCellView()
    cell.identifier = cellIdentifier

    let isActive = row == currentLine
    let syllables = syllableCache.indices.contains(row) ? syllableCache[row] : []
    let time = player.elapsedTime + (
      Double(lyrics.offset) + Double(storage.settings.user.lyricsOffsetMs)
    ) / 1000.0
    cell.configure(
      line: lyrics.line[row],
      isActive: isActive,
      syllables: syllables,
      time: time,
      rowSpacing: Self.rowSpacing,
      inset: Self.horizontalInset
    )
    return cell
  }

  private static func textHeight(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
    let bounds = (text as NSString).boundingRect(
      with: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      attributes: [.font: font]
    )
    return ceil(bounds.height)
  }

  // MARK: - MusicPlayable

  func didStartPlayingFromBeginning() {
    loadLyrics(force: true)
  }

  func didStartPlaying() {
    loadLyrics()
    updateActiveLine(force: true)
  }

  func didPause() {}

  func didStopPlaying() {
    loadLyrics(force: true)
  }

  func didElapsedTimeChange() {
    // The pane has its own clock; nothing to do here.
  }

  func didLyricsTimeChange(time: CMTime) {}

  func didPlaylistChange() {
    loadLyrics(force: true)
  }

  func didArtworkChange() {}

  func didNowPlayingInfoChange() {
    loadLyrics()
  }

  func didShuffleChange() {}

  func didRepeatChange() {}

  func didPlaybackRateChange() {}
}

// MARK: - LyricsSidebarCellView

/// One lyric row: 24 pt semibold passive lines, 29 pt bold active line whose sung
/// characters fill in progressively, translation underneath (Catalyst `LyricTableCell`).
@MainActor
private final class LyricsSidebarCellView: NSTableCellView {
  private let lineLabel = NSTextField(wrappingLabelWithString: "")
  private let translationLabel = NSTextField(wrappingLabelWithString: "")
  private var lineTopConstraint: NSLayoutConstraint?
  private var lineLeadingConstraint: NSLayoutConstraint?
  private var lineTrailingConstraint: NSLayoutConstraint?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    lineLabel.isEditable = false
    lineLabel.isSelectable = false
    lineLabel.drawsBackground = false
    lineLabel.maximumNumberOfLines = 0
    lineLabel.lineBreakMode = .byWordWrapping
    lineLabel.cell?.wraps = true
    lineLabel.cell?.isScrollable = false
    lineLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    lineLabel.translatesAutoresizingMaskIntoConstraints = false

    translationLabel.isEditable = false
    translationLabel.isSelectable = false
    translationLabel.drawsBackground = false
    translationLabel.maximumNumberOfLines = 0
    translationLabel.lineBreakMode = .byWordWrapping
    translationLabel.cell?.wraps = true
    translationLabel.cell?.isScrollable = false
    translationLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    translationLabel.translatesAutoresizingMaskIntoConstraints = false

    addSubview(lineLabel)
    addSubview(translationLabel)

    let top = lineLabel.topAnchor.constraint(equalTo: topAnchor)
    let leading = lineLabel.leadingAnchor.constraint(equalTo: leadingAnchor)
    let trailing = lineLabel.trailingAnchor.constraint(equalTo: trailingAnchor)
    lineTopConstraint = top
    lineLeadingConstraint = leading
    lineTrailingConstraint = trailing
    NSLayoutConstraint.activate([
      top,
      leading,
      trailing,
      translationLabel.leadingAnchor.constraint(equalTo: lineLabel.leadingAnchor),
      translationLabel.trailingAnchor.constraint(equalTo: lineLabel.trailingAnchor),
      translationLabel.topAnchor.constraint(equalTo: lineLabel.bottomAnchor, constant: 6),
      translationLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
    ])
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    lineLabel.attributedStringValue = NSAttributedString(string: "")
    translationLabel.attributedStringValue = NSAttributedString(string: "")
  }

  func configure(
    line: LyricsLine,
    isActive: Bool,
    syllables: [LyricsSyllableTiming],
    time: TimeInterval,
    rowSpacing: CGFloat,
    inset: CGFloat
  ) {
    lineTopConstraint?.constant = rowSpacing
    lineLeadingConstraint?.constant = inset
    lineTrailingConstraint?.constant = -inset

    let fontSize = isActive ? 29.0 : 24.0
    let weight: NSFont.Weight = isActive ? .bold : .semibold
    let font = NSFont.systemFont(ofSize: fontSize, weight: weight)

    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 6
    paragraph.lineBreakMode = .byWordWrapping
    paragraph.alignment = .left

    let text = line.value.isEmpty ? " " : line.value
    let attributed = NSMutableAttributedString(
      string: text,
      attributes: [
        .font: font,
        .foregroundColor: isActive
          ? NSColor.white.withAlphaComponent(0.55)
          : NSColor.white.withAlphaComponent(0.60),
        .paragraphStyle: paragraph,
      ]
    )

    if isActive, !syllables.isEmpty {
      // Fill sung glyph ranges in white; partially sung syllables reveal their
      // leading characters first, mirroring the Catalyst character fill.
      for syllable in syllables {
        let progress = syllable.progress(at: time)
        guard progress > 0, syllable.range.location + syllable.range.length <= (text as NSString).length
        else { continue }
        let length = syllable.range.length
        let filledCount = progress >= 1
          ? length
          : Int((CGFloat(length) * progress).rounded(.down))
        guard filledCount > 0 else { continue }
        let fillRange = NSRange(location: syllable.range.location, length: filledCount)
        attributed.addAttribute(.foregroundColor, value: NSColor.white, range: fillRange)
      }
    }

    lineLabel.attributedStringValue = attributed

    let translationText = line.translation?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if translationText.isEmpty {
      translationLabel.attributedStringValue = NSAttributedString(string: "")
      translationLabel.isHidden = true
    } else {
      translationLabel.isHidden = false
      let translationParagraph = NSMutableParagraphStyle()
      translationParagraph.lineSpacing = 3
      translationParagraph.lineBreakMode = .byWordWrapping
      translationParagraph.alignment = .left
      translationLabel.attributedStringValue = NSAttributedString(
        string: translationText,
        attributes: [
          .font: NSFont.systemFont(ofSize: 17, weight: .regular),
          .foregroundColor: NSColor.white.withAlphaComponent(0.72),
          .paragraphStyle: translationParagraph,
        ]
      )
    }
  }
}
