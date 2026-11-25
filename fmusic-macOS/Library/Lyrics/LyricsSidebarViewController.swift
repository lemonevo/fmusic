//
//  LyricsSidebarViewController.swift
//  fmusic-macOS
//
//  Native AppKit port of Catalyst `LyricsVC` / `LyricsView` / `LyricTableCell`:
//  - Top & bottom 20% gradient fade mask (`fadeMask`)
//  - Half-height top/bottom content insets so the active line always centers
//  - Stable row heights measured at the active 29 pt bold font (zero reflow jitter)
//  - Gaussian-blurred inactive lines (24 pt semibold) vs sharp 29 pt bold active line
//    with 60 Hz progressive syllable fill (`LyricsSyllableMaskLayer`)
//  - Critically-damped spring scrolling with 5 s manual-scroll suppression and soft
//    realignment spring, plus click-to-seek and dark/light adaptive palette.
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

/// Lyrics side pane & large-player lyrics view, ported 1:1 from Catalyst `LyricsView`.
@MainActor
final class LyricsSidebarViewController: NSViewController, MusicPlayable,
  NSTableViewDataSource, NSTableViewDelegate {
  /// The large player draws its own gradient; the pane must stay transparent there.
  var usesTransparentBackground = false
  /// The large player packs lines closer than the 30 pt inspector spacing.
  var compactRows = false

  // Catalyst `LyricsView.lineSpacing` (30 pt) and `LyricTableCell` typography.
  private var rowSpacing: CGFloat { compactRows ? 14 : 30 }
  private static let sideInset: CGFloat = 22
  private static let maxTextColumnWidth: CGFloat = 560
  private static let activeFontSize: CGFloat = 29
  private static let inactiveFontSize: CGFloat = 24
  private static let translationFontSize: CGFloat = 17
  private static let translationSpacing: CGFloat = 6
  private static let autoScrollSuppressionInterval: TimeInterval = 5.0

  private let scrollContainer = NSView()
  private let scrollView = NSScrollView()
  private let tableView = NSTableView()
  private let statusLabel = NSTextField(labelWithString: "")
  private let cellIdentifier = NSUserInterfaceItemIdentifier("lyricsSidebarCell")
  private let columnIdentifier = NSUserInterfaceItemIdentifier("lyricsSidebarColumn")

  /// Apple Music style top & bottom 20% soft fade mask (mirrors Catalyst `LyricsView.fadeMask`).
  private let fadeMask: CAGradientLayer = {
    let mask = CAGradientLayer()
    mask.colors = [
      NSColor.white.withAlphaComponent(0).cgColor,
      NSColor.white.cgColor,
      NSColor.white.cgColor,
      NSColor.white.withAlphaComponent(0).cgColor,
    ]
    // AppKit layer coordinates have y=0 at bottom, y=1 at top; symmetric [0, 0.2, 0.8, 1]
    // fades both edges smoothly regardless of flippedness.
    mask.locations = [0, 0.2, 0.8, 1]
    return mask
  }()

  private var lyrics: StructuredLyrics?
  private var loadedSongID: String?
  private var currentLine = -1
  private var lastActiveTime: TimeInterval = -1
  private var seekHoldUntil: CFTimeInterval = 0
  private var syllableCache = [[LyricsSyllableTiming]]()
  private var cachedRowHeights = [CGFloat]()
  private var lastLayoutWidth: CGFloat = 0
  private var lastLayoutHeight: CGFloat = 0

  private var suppressAutoScrollUntil: Date?
  private var needsRealignAfterUserScroll = false
  private var isInitialScroll = true

  nonisolated(unsafe) private var syncTimer: Timer?
  private var isPaneVisible = false

  private var player: PlayerFacade { FmusicKit.shared.player }
  private var storage: PersistentStorage { FmusicKit.shared.storage }

  // MARK: - Lifecycle

  override func loadView() {
    let root: NSView
    if usesTransparentBackground {
      root = NSView()
      root.wantsLayer = true
    } else {
      root = LyricsPaneBackgroundView(
        frame: NSRect(x: 0, y: 0, width: 260, height: 730)
      )
    }

    scrollContainer.wantsLayer = true
    scrollContainer.layer?.mask = fadeMask
    scrollContainer.translatesAutoresizingMaskIntoConstraints = false

    tableView.headerView = nil
    tableView.backgroundColor = .clear
    tableView.rowHeight = 44
    tableView.intercellSpacing = NSSize(width: 0, height: 0)
    tableView.style = .plain
    tableView.selectionHighlightStyle = .none
    tableView.allowsEmptySelection = true
    tableView.allowsMultipleSelection = false
    tableView.focusRingType = .none
    // Explicit cached heights measured at the active font keep rows rock-steady
    // while emphasis animates in place (mirrors Catalyst `LyricTableCellModel.calcHeight`).
    tableView.usesAutomaticRowHeights = false
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
    scrollView.hasVerticalScroller = false
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = false
    scrollView.automaticallyAdjustsContentInsets = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    statusLabel.font = .systemFont(ofSize: 22, weight: .semibold)
    statusLabel.textColor = MacTheme.secondaryTextColor
    statusLabel.alignment = .center
    statusLabel.maximumNumberOfLines = 0
    statusLabel.translatesAutoresizingMaskIntoConstraints = false

    scrollContainer.addSubview(scrollView)
    root.addSubview(scrollContainer)
    root.addSubview(statusLabel)

    NSLayoutConstraint.activate([
      scrollContainer.topAnchor.constraint(equalTo: root.topAnchor),
      scrollContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      scrollContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      scrollContainer.bottomAnchor.constraint(equalTo: root.bottomAnchor),

      scrollView.topAnchor.constraint(equalTo: scrollContainer.topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: scrollContainer.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: scrollContainer.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: scrollContainer.bottomAnchor),

      statusLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
      statusLabel.centerYAnchor.constraint(equalTo: root.centerYAnchor),
      statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 24),
      statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -24),
    ])

    self.view = root
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    player.addNotifier(notifier: self)
    loadLyrics(force: true)
    updateActiveLine(force: true)
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
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(appearanceChanged),
      name: .macAppearanceChanged,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(userWillScroll),
      name: NSScrollView.willStartLiveScrollNotification,
      object: scrollView
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(userDidEndScroll),
      name: NSScrollView.didEndLiveScrollNotification,
      object: scrollView
    )
  }

  override func viewDidLayout() {
    super.viewDidLayout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    fadeMask.frame = scrollContainer.bounds
    CATransaction.commit()

    let width = scrollView.contentView.bounds.width
    let height = scrollView.contentView.bounds.height
    var needsRealign = false

    // Half-height top/bottom insets let the first and last lyric lines sit centered,
    // matching Catalyst `LyricsView.reloadInsets()`.
    let halfHeight = max(0, (height / 2).rounded())
    if abs(scrollView.contentInsets.top - halfHeight) > 0.5 ||
      abs(scrollView.contentInsets.bottom - halfHeight) > 0.5 {
      scrollView.contentInsets = NSEdgeInsets(top: halfHeight, left: 0, bottom: halfHeight, right: 0)
      needsRealign = true
    }

    if width > 0, abs(width - lastLayoutWidth) > 0.5 {
      lastLayoutWidth = width
      rebuildRowHeights()
      tableView.reloadData()
      needsRealign = true
    }
    if height > 0, abs(height - lastLayoutHeight) > 0.5 {
      lastLayoutHeight = height
      needsRealign = true
    }
    if needsRealign, currentLine >= 0 {
      scrollToRow(currentLine, animated: false)
    }
  }

  override func viewDidAppear() {
    super.viewDidAppear()
    startSyncTimerIfNeeded()
  }

  override func viewDidDisappear() {
    super.viewDidDisappear()
    stopSyncTimer()
  }

  func setPaneVisible(_ visible: Bool) {
    isPaneVisible = visible
    if visible {
      startSyncTimerIfNeeded()
      updateActiveLine(force: true)
    } else {
      stopSyncTimer()
    }
  }

  private func startSyncTimerIfNeeded() {
    guard isPaneVisible, syncTimer == nil, view.window != nil else { return }
    guard player.isPlaying || scrollTargetY != nil else { return }
    let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) {
      [weak self] _ in
      Task { @MainActor in self?.syncTick() }
    }
    RunLoop.main.add(timer, forMode: .common)
    syncTimer = timer
  }

  private func stopSyncTimer() {
    syncTimer?.invalidate()
    syncTimer = nil
  }

  deinit {
    syncTimer?.invalidate()
    NotificationCenter.default.removeObserver(self)
  }

  // MARK: - User scroll suppression

  @objc
  private func userWillScroll() {
    suppressAutoScrollUntil = Date().addingTimeInterval(Self.autoScrollSuppressionInterval)
    needsRealignAfterUserScroll = true
    scrollTargetY = nil
    scrollVelocity = 0
  }

  @objc
  private func userDidEndScroll() {
    suppressAutoScrollUntil = Date().addingTimeInterval(Self.autoScrollSuppressionInterval)
  }

  private var isAutoScrollAllowed: Bool {
    guard let until = suppressAutoScrollUntil else { return true }
    return Date() >= until
  }

  // MARK: - Lyrics loading

  private func loadLyrics(force: Bool = false) {
    guard let song = player.currentlyPlaying?.asSong else {
      loadedSongID = nil
      lyrics = nil
      syllableCache = []
      cachedRowHeights = []
      renderStatus(L10n.tr("Play a song to see the lyrics here."))
      return
    }
    let songID = song.id
    guard force || loadedSongID != songID else { return }
    loadedSongID = songID
    lyrics = nil
    currentLine = -1
    syllableCache = []
    cachedRowHeights = []
    isInitialScroll = true
    suppressAutoScrollUntil = nil
    needsRealignAfterUserScroll = false
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
    renderStatus(L10n.tr("Searching online lyrics…"))
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
  private func appearanceChanged() {
    tableView.reloadData()
    updateActiveLine(force: true)
  }

  @objc
  private func themeColorChanged() {
    tableView.reloadData()
  }

  // MARK: - Layout metrics

  private static func effectiveSideInset(for containerWidth: CGFloat) -> CGFloat {
    max(sideInset, (containerWidth - maxTextColumnWidth) / 2)
  }

  private func textColumnWidth() -> CGFloat {
    let containerWidth = max(scrollView.contentView.bounds.width, tableView.bounds.width)
    return max(80, containerWidth - 2 * Self.effectiveSideInset(for: containerWidth))
  }

  private func rebuildRowHeights() {
    guard let lyrics else {
      cachedRowHeights = []
      return
    }
    let width = textColumnWidth()
    let activeFont = NSFont.systemFont(ofSize: Self.activeFontSize, weight: .bold)
    let translationFont = NSFont.systemFont(ofSize: Self.translationFontSize, weight: .regular)
    let lineParagraph = LyricsPresentation.paragraphStyle(lineSpacing: 6)
    let translationParagraph = LyricsPresentation.paragraphStyle(lineSpacing: 3)

    cachedRowHeights = lyrics.line.map { line in
      let text = line.value.isEmpty ? " " : line.value
      let mainLayout = LyricsTextLayout(
        text: NSAttributedString(
          string: text,
          attributes: [.font: activeFont, .paragraphStyle: lineParagraph]
        ),
        width: width,
        maximumNumberOfLines: 6,
        lineBreakMode: .byWordWrapping
      )
      var total = rowSpacing + max(ceil(mainLayout.height), ceil(Self.activeFontSize * 1.3))
      let translation = line.translation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if !translation.isEmpty {
        let transLayout = LyricsTextLayout(
          text: NSAttributedString(
            string: translation,
            attributes: [.font: translationFont, .paragraphStyle: translationParagraph]
          ),
          width: width,
          maximumNumberOfLines: 6,
          lineBreakMode: .byWordWrapping
        )
        total += Self.translationSpacing + ceil(transLayout.height)
      }
      return max(44, ceil(total))
    }
  }

  // MARK: - Rendering

  private func apply(lyrics structuredLyrics: StructuredLyrics) {
    lyrics = structuredLyrics
    let durations = LyricsTimingMap.estimatedDurations(for: structuredLyrics.line)
    syllableCache = structuredLyrics.line.indices.map { index in
      LyricsTimingMap.syllables(
        for: structuredLyrics.line[index],
        estimatedDuration: durations.object(at: index) ?? 0
      )
    }
    statusLabel.isHidden = true
    currentLine = -1
    isInitialScroll = true
    suppressAutoScrollUntil = nil
    needsRealignAfterUserScroll = false
    rebuildRowHeights()
    tableView.reloadData()
    updateActiveLine(force: true)
  }

  private func renderStatus(_ text: String) {
    statusLabel.stringValue = text
    statusLabel.isHidden = text.isEmpty
    lyrics = nil
    syllableCache = []
    cachedRowHeights = []
    currentLine = -1
    tableView.reloadData()
  }

  @objc
  private func syncTick() {
    guard view.window != nil else { return }
    stepScrollSpring()
    if player.isPlaying {
      updateActiveLine(force: false)
    } else if scrollTargetY == nil {
      stopSyncTimer()
    }
  }

  private func updateActiveLine(force: Bool) {
    guard let lyrics, !lyrics.line.isEmpty else { return }
    if !force, CACurrentMediaTime() < seekHoldUntil {
      return
    }
    let time = player.elapsedTime
    guard force || abs(time - lastActiveTime) > 0.016 else { return }
    lastActiveTime = time

    let index = LyricsPresentation.currentLineIndex(
      lyrics: lyrics,
      elapsed: time,
      userOffsetMs: storage.settings.user.lyricsOffsetMs
    )
    let previous = currentLine
    let isFirst = isInitialScroll
    isInitialScroll = false

    if index != previous {
      currentLine = index
      refreshVisibleRows(animated: !isFirst)
      if index >= 0, isAutoScrollAllowed {
        let isRealigning = needsRealignAfterUserScroll
        needsRealignAfterUserScroll = false
        let soft = isRealigning || (previous >= 0 && abs(index - previous) > 1)
        scrollToRow(
          index,
          animated: storage.settings.user.isLyricsSmoothScrolling && !isFirst,
          soft: soft
        )
      }
    } else if index >= 0 {
      if isAutoScrollAllowed, needsRealignAfterUserScroll {
        needsRealignAfterUserScroll = false
        scrollToRow(
          index,
          animated: storage.settings.user.isLyricsSmoothScrolling,
          soft: true
        )
      }
      refreshActiveFill()
    }
  }

  private func refreshActiveFill() {
    guard let lyrics,
          lyrics.line.indices.contains(currentLine),
          let cell = tableView.view(
            atColumn: 0,
            row: currentLine,
            makeIfNecessary: false
          ) as? LyricsSidebarCellView
    else { return }
    cell.updateFill(
      syllables: syllableCache.indices.contains(currentLine)
        ? syllableCache[currentLine]
        : [],
      time: playbackLyricsTime()
    )
  }

  private func refreshVisibleRows(animated: Bool) {
    guard let lyrics else { return }
    let visible = tableView.rows(in: scrollView.contentView.bounds)
    guard visible.length > 0 else { return }
    let range = max(0, visible.location) ..< min(lyrics.line.count, visible.location + visible.length)
    for row in range {
      reconfigureRow(row, animated: animated)
    }
  }

  private func reconfigureRow(_ row: Int, animated: Bool = false) {
    guard let lyrics,
          lyrics.line.indices.contains(row),
          let cell = tableView.view(
            atColumn: 0,
            row: row,
            makeIfNecessary: false
          ) as? LyricsSidebarCellView
    else { return }
    let containerWidth = max(scrollView.contentView.bounds.width, tableView.bounds.width)
    let inset = Self.effectiveSideInset(for: containerWidth)
    cell.configure(
      line: lyrics.line[row],
      isActive: row == currentLine,
      syllables: syllableCache.indices.contains(row) ? syllableCache[row] : [],
      time: playbackLyricsTime(),
      inset: inset,
      contentWidth: max(80, containerWidth - 2 * inset),
      animated: animated
    )
  }

  private func playbackLyricsTime() -> TimeInterval {
    guard let lyrics else { return player.elapsedTime }
    return LyricsPresentation.playbackTime(
      elapsed: player.elapsedTime,
      lyricsOffsetMs: lyrics.offset,
      userOffsetMs: storage.settings.user.lyricsOffsetMs
    )
  }

  // MARK: - Spring scrolling (same constants as Catalyst LyricsView)

  private var scrollTargetY: CGFloat?
  private var scrollVelocity: CGFloat = 0
  private var scrollSpringIsSoft = false
  private var lastSpringTimestamp = CACurrentMediaTime()

  private func scrollTarget(for row: Int) -> CGFloat {
    let rowRect = tableView.rect(ofRow: row)
    let visible = scrollView.contentView.bounds.height
    let lower = -scrollView.contentInsets.top
    let upper = max(
      lower,
      tableView.bounds.height - visible + scrollView.contentInsets.bottom
    )
    let target = rowRect.midY - visible / 2
    return min(max(target, lower), upper)
  }

  private func scrollToRow(_ row: Int, animated: Bool, soft: Bool = false) {
    guard let lyrics, lyrics.line.indices.contains(row) else { return }
    let target = scrollTarget(for: row)
    let clip = scrollView.contentView
    guard animated,
          view.window != nil,
          !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
          abs(target - clip.bounds.origin.y) > 1.6
    else {
      scrollTargetY = nil
      scrollVelocity = 0
      clip.scroll(to: NSPoint(x: 0, y: target))
      scrollView.reflectScrolledClipView(clip)
      return
    }
    scrollTargetY = target
    scrollSpringIsSoft = soft
    lastSpringTimestamp = CACurrentMediaTime()
    startSyncTimerIfNeeded()
  }

  private func stepScrollSpring() {
    guard let target = scrollTargetY else { return }
    let now = CACurrentMediaTime()
    let deltaTime = now - lastSpringTimestamp
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
    // Normal line changes settle without overshoot; seeks / post-scroll realigns use the softer spring.
    let stiffness: CGFloat = scrollSpringIsSoft ? 90 : 190
    let damping: CGFloat = scrollSpringIsSoft ? 15 : 1.05 * 2 * sqrt(stiffness)
    let displacement = current - target
    scrollVelocity += (-stiffness * displacement - damping * scrollVelocity) *
      CGFloat(deltaTime)
    var newY = current + scrollVelocity * CGFloat(deltaTime)
    let lower = -scrollView.contentInsets.top
    let upper = max(
      lower,
      tableView.bounds.height - clip.bounds.height + scrollView.contentInsets.bottom
    )
    newY = min(max(newY, lower), upper)
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
    let offsetSeconds = (
      Double(lyrics.offset) + Double(storage.settings.user.lyricsOffsetMs)
    ) / 1000.0
    let targetSecond = max(0, Double(start) / 1000.0 - offsetSeconds)
    suppressAutoScrollUntil = nil
    needsRealignAfterUserScroll = false
    seekHoldUntil = CACurrentMediaTime() + 0.45
    lastActiveTime = targetSecond
    currentLine = row
    refreshVisibleRows(animated: true)
    scrollToRow(row, animated: true, soft: true)
    player.seek(toSecond: targetSecond)
  }

  // MARK: - NSTableViewDataSource

  func numberOfRows(in tableView: NSTableView) -> Int {
    lyrics?.line.count ?? 0
  }

  // MARK: - NSTableViewDelegate

  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    if cachedRowHeights.indices.contains(row) {
      return cachedRowHeights[row]
    }
    return 44
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
    cell.forcesDarkRaster = usesTransparentBackground

    let isActive = row == currentLine
    let syllables = syllableCache.indices.contains(row) ? syllableCache[row] : []
    let containerWidth = max(scrollView.contentView.bounds.width, tableView.bounds.width)
    let inset = Self.effectiveSideInset(for: containerWidth)
    cell.configure(
      line: lyrics.line[row],
      isActive: isActive,
      syllables: syllables,
      time: playbackLyricsTime(),
      inset: inset,
      contentWidth: max(80, containerWidth - 2 * inset)
    )
    return cell
  }

  // MARK: - MusicPlayable

  func didStartPlayingFromBeginning() {
    loadLyrics(force: true)
    startSyncTimerIfNeeded()
  }

  func didStartPlaying() {
    loadLyrics()
    updateActiveLine(force: true)
    startSyncTimerIfNeeded()
  }

  func didPause() {
    if scrollTargetY == nil {
      stopSyncTimer()
    }
  }

  func didStopPlaying() {
    stopSyncTimer()
    loadLyrics(force: true)
  }

  func didElapsedTimeChange() {}
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

// MARK: - LyricsGlyphView

/// Two stacked glyph rasters: the dim line plus the bright line clipped by a
/// `LyricsSyllableMaskLayer`. The playback clock only moves the mask widths, so the
/// fill sweeps through each character with a soft gradient edge (Catalyst `LyricTableCell`).
@MainActor
private final class LyricsGlyphView: NSView {
  private let dimLayer = CALayer()
  private let brightLayer = CALayer()
  let syllableMask = LyricsSyllableMaskLayer()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.masksToBounds = false
    dimLayer.contentsGravity = .resize
    brightLayer.contentsGravity = .resize
    brightLayer.mask = syllableMask
    layer?.addSublayer(dimLayer)
    layer?.addSublayer(brightLayer)
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    dimLayer.frame = bounds
    brightLayer.frame = bounds
    syllableMask.setFrameWithoutAnimation(CGRect(origin: .zero, size: bounds.size))
    let scale = window?.backingScaleFactor ?? 2
    dimLayer.contentsScale = scale
    brightLayer.contentsScale = scale
    CATransaction.commit()
  }

  func setImages(dim: CGImage?, bright: CGImage?) {
    dimLayer.contents = dim
    brightLayer.contents = bright
    brightLayer.isHidden = bright == nil
  }

  func updateMask(rects: [[CGRect]]) {
    syllableMask.update(rects: rects)
  }

  func apply(progress: [CGFloat]) {
    syllableMask.apply(progress: progress)
  }
}

// MARK: - LyricsSidebarCellView

/// One lyric row centered vertically inside its stable row box:
/// blurred inactive raster (24 pt semibold) or sharp active dim+bright rasters (29 pt bold)
/// plus an optional translation label underneath.
@MainActor
private final class LyricsSidebarCellView: NSTableCellView {
  /// The large Now Playing host is always dark; the inspector follows the window.
  var forcesDarkRaster = false

  private static let activeFontSize: CGFloat = 29
  private static let inactiveFontSize: CGFloat = 24
  private static let translationFontSize: CGFloat = 17
  private static let translationSpacing: CGFloat = 6

  private static let activeBrightColor = NSColor(
    name: "lyricsActiveBright",
    dynamicProvider: { appearance in
      LyricsSidebarCellView.isDark(appearance) ? .white : NSColor(white: 0.32, alpha: 1)
    }
  )
  private static let activeDimColor = NSColor(
    name: "lyricsActiveDim",
    dynamicProvider: { appearance in
      LyricsSidebarCellView.isDark(appearance)
        ? NSColor.white.withAlphaComponent(0.55)
        : NSColor(white: 0.32, alpha: 0.55)
    }
  )
  private static let inactiveColor = NSColor(
    name: "lyricsInactive",
    dynamicProvider: { appearance in
      LyricsSidebarCellView.isDark(appearance)
        ? NSColor.white.withAlphaComponent(0.60)
        : NSColor(white: 0.5, alpha: 1)
    }
  )
  private static let activeTranslationColor = NSColor(
    name: "lyricsActiveTranslation",
    dynamicProvider: { appearance in
      LyricsSidebarCellView.isDark(appearance)
        ? NSColor.white.withAlphaComponent(0.72)
        : NSColor(white: 0.34, alpha: 0.82)
    }
  )

  private static func isDark(_ appearance: NSAppearance) -> Bool {
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
  }

  private static let blurContext = CIContext(options: nil)
  private static let rasterCache: NSCache<NSString, NSImage> = {
    let cache = NSCache<NSString, NSImage>()
    cache.countLimit = 240
    cache.totalCostLimit = 16 * 1024 * 1024
    return cache
  }()

  private let contentContainer = NSView()
  private let glyphView = LyricsGlyphView()
  private let translationLabel = NSTextField(wrappingLabelWithString: "")

  private var containerLeading: NSLayoutConstraint?
  private var containerTrailing: NSLayoutConstraint?
  private var glyphHeightConstraint: NSLayoutConstraint?
  private var translationTopConstraint: NSLayoutConstraint?
  private var isActiveLine = false

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.masksToBounds = false

    contentContainer.wantsLayer = true
    contentContainer.layer?.masksToBounds = false
    contentContainer.translatesAutoresizingMaskIntoConstraints = false

    glyphView.translatesAutoresizingMaskIntoConstraints = false
    translationLabel.isEditable = false
    translationLabel.isSelectable = false
    translationLabel.drawsBackground = false
    translationLabel.maximumNumberOfLines = 0
    translationLabel.lineBreakMode = .byWordWrapping
    translationLabel.cell?.wraps = true
    translationLabel.translatesAutoresizingMaskIntoConstraints = false

    contentContainer.addSubview(glyphView)
    contentContainer.addSubview(translationLabel)
    addSubview(contentContainer)

    let leading = contentContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22)
    let trailing = contentContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22)
    let glyphHeight = glyphView.heightAnchor.constraint(equalToConstant: 36)
    let transTop = translationLabel.topAnchor.constraint(
      equalTo: glyphView.bottomAnchor,
      constant: Self.translationSpacing
    )
    containerLeading = leading
    containerTrailing = trailing
    glyphHeightConstraint = glyphHeight
    translationTopConstraint = transTop

    NSLayoutConstraint.activate([
      leading,
      trailing,
      contentContainer.centerYAnchor.constraint(equalTo: centerYAnchor),

      glyphView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
      glyphView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
      glyphView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
      glyphHeight,

      transTop,
      translationLabel.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
      translationLabel.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
      translationLabel.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
    ])
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    glyphView.setImages(dim: nil, bright: nil)
    translationLabel.stringValue = ""
    contentContainer.layer?.removeAllAnimations()
    contentContainer.layer?.transform = CATransform3DIdentity
  }

  func configure(
    line: LyricsLine,
    isActive: Bool,
    syllables: [LyricsSyllableTiming],
    time: TimeInterval,
    inset: CGFloat,
    contentWidth: CGFloat,
    animated: Bool = false
  ) {
    containerLeading?.constant = inset
    containerTrailing?.constant = -inset

    let wasActive = isActiveLine
    isActiveLine = isActive
    let fontSize = isActive ? Self.activeFontSize : Self.inactiveFontSize
    let weight: NSFont.Weight = isActive ? .bold : .semibold
    let font = NSFont.systemFont(ofSize: fontSize, weight: weight)
    let paragraph = LyricsPresentation.paragraphStyle(lineSpacing: 6)

    let text = line.value.isEmpty ? " " : line.value
    let width = max(80, contentWidth)
    let layout = LyricsTextLayout(
      text: NSAttributedString(
        string: text,
        attributes: [
          .font: font,
          .foregroundColor: NSColor.white,
          .paragraphStyle: paragraph,
        ]
      ),
      width: width,
      maximumNumberOfLines: 6,
      lineBreakMode: .byWordWrapping
    )
    let imageHeight = max(ceil(layout.height), ceil(fontSize * 1.3))
    glyphHeightConstraint?.constant = imageHeight
    let scale = window?.backingScaleFactor ?? 2
    let size = CGSize(width: width, height: imageHeight)

    let isDark = Self.isDark(effectiveAppearance) || forcesDarkRaster
    // Catalyst `LyricTableCell.updateBlurredImageIfNeeded`: inactive lines get a soft
    // Core Image Gaussian blur while the active line stays razor sharp.
    let blurRadius = isActive ? 0 : 1.6 * scale
    let dimColor = isActive ? Self.activeDimColor : Self.inactiveColor
    let dimImage = Self.raster(
      text: text,
      width: width,
      layout: layout,
      size: size,
      scale: scale,
      color: dimColor,
      blurRadius: blurRadius,
      isDark: isDark
    )
    if isActive {
      let brightImage = Self.raster(
        text: text,
        width: width,
        layout: layout,
        size: size,
        scale: scale,
        color: Self.activeBrightColor,
        blurRadius: 0,
        isDark: isDark
      )
      glyphView.setImages(dim: dimImage, bright: brightImage)
      glyphView.updateMask(rects: Self.maskRects(
        layout: layout,
        syllables: syllables,
        height: imageHeight
      ))
      glyphView.apply(progress: syllables.map { $0.progress(at: time) })
    } else {
      glyphView.setImages(dim: dimImage, bright: nil)
      glyphView.updateMask(rects: [])
    }

    let translationText = line.translation?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if translationText.isEmpty {
      translationLabel.stringValue = ""
      translationLabel.isHidden = true
      translationTopConstraint?.constant = 0
    } else {
      translationLabel.isHidden = false
      translationTopConstraint?.constant = Self.translationSpacing
      let translationParagraph = LyricsPresentation.paragraphStyle(lineSpacing: 3)
      translationLabel.attributedStringValue = NSAttributedString(
        string: translationText,
        attributes: [
          .font: NSFont.systemFont(ofSize: Self.translationFontSize, weight: .regular),
          .foregroundColor: isActive ? Self.activeTranslationColor : Self.inactiveColor,
          .paragraphStyle: translationParagraph,
        ]
      )
    }

    let targetScale: CGFloat = isActive ? 1.0 : 0.97
    let targetTransform = CATransform3DMakeScale(targetScale, targetScale, 1)
    if animated, wasActive != isActive,
       !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      let spring = CASpringAnimation(keyPath: "transform.scale")
      spring.fromValue = isActive ? 0.97 : 1.0
      spring.toValue = targetScale
      spring.mass = 1
      spring.stiffness = 220
      spring.damping = 20
      spring.initialVelocity = 0.2
      spring.duration = spring.settlingDuration
      contentContainer.layer?.add(spring, forKey: "lineScale")
      contentContainer.layer?.transform = targetTransform

      let fade = CABasicAnimation(keyPath: "opacity")
      fade.fromValue = isActive ? 0.65 : 1.0
      fade.toValue = 1.0
      fade.duration = 0.18
      fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
      contentContainer.layer?.add(fade, forKey: "lineFade")
    } else {
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      contentContainer.layer?.transform = targetTransform
      CATransaction.commit()
    }
  }

  /// Called at display rate: only the syllable mask widths change.
  func updateFill(syllables: [LyricsSyllableTiming], time: TimeInterval) {
    guard isActiveLine else { return }
    glyphView.apply(progress: syllables.map { $0.progress(at: time) })
  }

  private static func raster(
    text: String,
    width: CGFloat,
    layout: LyricsTextLayout,
    size: CGSize,
    scale: CGFloat,
    color: NSColor,
    blurRadius: CGFloat,
    isDark: Bool
  )
    -> CGImage? {
    let key = "v2|\(isDark)|\(width)|\(scale)|\(blurRadius)|\(color.description)|\(text)" as NSString
    if let cached = rasterCache.object(forKey: key),
       let cgImage = cached.cgImage(forProposedRect: nil, context: nil, hints: nil) {
      return cgImage
    }
    guard let sharp = LyricsRasterizer.image(
      layout: layout,
      size: size,
      scale: scale,
      foregroundColor: color
    )
    else { return nil }
    let result: CGImage?
    if blurRadius > 0 {
      result = blurred(sharp, radius: blurRadius)
    } else {
      result = sharp
    }
    if let result {
      let pixelCost = Int(size.width * size.height * scale * scale * 4)
      rasterCache.setObject(
        NSImage(cgImage: result, size: size),
        forKey: key,
        cost: pixelCost
      )
    }
    return result
  }

  private static func blurred(_ image: CGImage, radius: CGFloat) -> CGImage? {
    let input = CIImage(cgImage: image)
    let output = input
      .clampedToExtent()
      .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
      .cropped(to: input.extent)
    return blurContext.createCGImage(output, from: input.extent)
  }

  private static func maskRects(
    layout: LyricsTextLayout,
    syllables: [LyricsSyllableTiming],
    height: CGFloat
  )
    -> [[CGRect]] {
    syllables.map { syllable in
      layout.rects(for: syllable.range).map { rect in
        CGRect(
          x: rect.minX,
          y: height - rect.maxY,
          width: max(rect.width, 1),
          height: max(rect.height, 1)
        )
      }
    }
  }
}

// MARK: - LyricsPaneBackgroundView

/// Opaque inspector surface following the window appearance: warm grey in light mode,
/// graphite in dark mode (matches the left sidebar surface).
@MainActor
private final class LyricsPaneBackgroundView: NSView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.contentsGravity = .resize
    refresh()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(refresh),
      name: .macAppearanceChanged,
      object: nil
    )
  }

  required init?(coder: NSCoder) {
    nil
  }

  deinit { NotificationCenter.default.removeObserver(self) }

  static var paneColor: NSColor {
    NSColor(name: nil) { appearance in
      var resolved = MacTheme.sidebarBackgroundColor
      appearance.performAsCurrentDrawingAppearance {
        resolved = MacTheme.sidebarBackgroundColor.usingColorSpace(.sRGB)
          ?? MacTheme.sidebarBackgroundColor
      }
      return resolved
    }
  }

  @objc private func refresh() {
    let appearance = effectiveAppearance
    var resolved = Self.paneColor.cgColor
    appearance.performAsCurrentDrawingAppearance {
      resolved = Self.paneColor.cgColor
    }
    layer?.backgroundColor = resolved
    needsDisplay = true
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    refresh()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    refresh()
  }

  override func draw(_ dirtyRect: NSRect) {
    Self.paneColor.setFill()
    dirtyRect.fill()
  }
}
