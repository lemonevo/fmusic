//
//  LyricsPageViewController.swift
//  fmusic-macOS
//
//  Dedicated full lyrics page for the currently playing song: large centred lyric
//  lines with the active line highlighted, smooth follow-the-playback scrolling,
//  click-to-seek and the shared lyrics timing offset controls.
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

/// Full window lyrics page. Has a plain `init()` and follows the shared player on
/// its own, so it can be pushed from a View menu action (see
/// `LyricsPageWindowController`) or embedded in the main window.
@MainActor
final class LyricsPageViewController: NSViewController, MusicPlayable, NSTableViewDataSource,
  NSTableViewDelegate {
  // MARK: - Layout constants

  fileprivate static let lineFont = NSFont.systemFont(ofSize: 21, weight: .regular)
  fileprivate static let currentLineFont = NSFont.systemFont(ofSize: 21, weight: .semibold)
  fileprivate static let translationFont = NSFont.systemFont(ofSize: 13, weight: .regular)
  fileprivate static let lineHorizontalInset: CGFloat = 56
  private static let offsetStepMs = 100

  // MARK: - Views

  private let songTitleLabel = NSTextField(labelWithString: "")
  private let artistLabel = NSTextField(labelWithString: "")
  private let scrollView = NSScrollView()
  private let tableView = LyricsPageTableView()
  private let statusStack = NSStackView()
  private let statusLabel = NSTextField(wrappingLabelWithString: "")
  private let spinner = NSProgressIndicator()
  private let offsetCaptionLabel = NSTextField(labelWithString: "")
  private let offsetMinusButton = NSButton()
  private let offsetValueLabel = NSTextField(labelWithString: "")
  private let offsetPlusButton = NSButton()
  private let offsetResetButton = NSButton()
  private let offsetStack = NSStackView()

  private enum Column {
    static let line = NSUserInterfaceItemIdentifier("lyricsPageLine")
  }

  // MARK: - State

  private let tracker = LyricsLineTracker()
  private var lyrics: StructuredLyrics?
  private var loadedSongID: String?
  private var resolvedSongID: String?
  private var highlightedLine = -1
  private var lastLayoutWidth: CGFloat = 0
  private var isUserScrolling = false

  // Smooth scrolling is implemented with a small timer so the page works on every
  // macOS version without relying on Core Animation on an NSScrollView clip view.
  nonisolated(unsafe) private var scrollTimer: Timer?
  private var scrollAnimationStart: CGFloat = 0
  private var scrollAnimationTarget: CGFloat = 0
  private var scrollAnimationStartTime: TimeInterval = 0
  private static let scrollAnimationDuration: TimeInterval = 0.32

  private var player: PlayerFacade { FmusicKit.shared.player }
  private var storage: PersistentStorage { FmusicKit.shared.storage }

  private var isPageVisible: Bool {
    isViewLoaded && view.window != nil && view.window?.isVisible == true
  }

  // MARK: - Lifecycle

  override func loadView() {
    let root = NSView()
    root.wantsLayer = true

    configureHeader()
    configureTable()
    configureStatus()
    configureOffsetBar()

    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    root.addSubview(songTitleLabel)
    root.addSubview(artistLabel)
    root.addSubview(scrollView)
    root.addSubview(statusStack)
    root.addSubview(offsetStack)

    NSLayoutConstraint.activate([
      songTitleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 22),
      songTitleLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
      songTitleLabel.leadingAnchor.constraint(
        greaterThanOrEqualTo: root.leadingAnchor,
        constant: 24
      ),
      songTitleLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: root.trailingAnchor,
        constant: -24
      ),

      artistLabel.topAnchor.constraint(equalTo: songTitleLabel.bottomAnchor, constant: 3),
      artistLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
      artistLabel.leadingAnchor.constraint(
        greaterThanOrEqualTo: root.leadingAnchor,
        constant: 24
      ),
      artistLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: root.trailingAnchor,
        constant: -24
      ),

      scrollView.topAnchor.constraint(equalTo: artistLabel.bottomAnchor, constant: 12),
      scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 36),
      scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -36),
      scrollView.bottomAnchor.constraint(equalTo: offsetStack.topAnchor, constant: -14),

      statusStack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
      statusStack.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
      statusStack.widthAnchor.constraint(lessThanOrEqualTo: scrollView.widthAnchor, constant: -40),

      offsetStack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
      offsetStack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
      offsetStack.leadingAnchor.constraint(
        greaterThanOrEqualTo: root.leadingAnchor,
        constant: 24
      ),
      offsetStack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -24),
    ])

    self.view = root
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    registerObservers()
    refreshOffsetControls()
    player.addNotifier(notifier: self)
    refreshSongIfNeeded(force: true)
  }

  override func viewDidAppear() {
    super.viewDidAppear()
    refreshSongIfNeeded()
    updateHighlight(force: true)
  }

  override func viewDidDisappear() {
    super.viewDidDisappear()
    stopScrollAnimation()
  }

  override func viewDidLayout() {
    super.viewDidLayout()
    offsetCaptionLabel.isHidden = view.bounds.width < 400
    let width = tableView.bounds.width
    guard abs(width - lastLayoutWidth) > 0.5 else { return }
    lastLayoutWidth = width
    tableView.sizeLastColumnToFit()
    let rows = lyrics?.line.count ?? 0
    guard rows > 0 else { return }
    tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<rows))
    if highlightedLine >= 0 {
      scrollToLine(highlightedLine, animated: false)
    }
  }

  deinit {
    scrollTimer?.invalidate()
    NotificationCenter.default.removeObserver(self)
  }

  // MARK: - View configuration

  private func configureHeader() {
    songTitleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
    songTitleLabel.alignment = .center
    songTitleLabel.lineBreakMode = .byTruncatingTail
    songTitleLabel.maximumNumberOfLines = 1
    songTitleLabel.translatesAutoresizingMaskIntoConstraints = false

    artistLabel.font = MacTheme.secondaryFont
    artistLabel.textColor = MacTheme.secondaryTextColor
    artistLabel.alignment = .center
    artistLabel.lineBreakMode = .byTruncatingTail
    artistLabel.maximumNumberOfLines = 1
    artistLabel.translatesAutoresizingMaskIntoConstraints = false
  }

  private func configureTable() {
    let column = NSTableColumn(identifier: Column.line)
    column.title = ""
    column.width = 800
    column.minWidth = 200
    column.resizingMask = .autoresizingMask
    tableView.addTableColumn(column)

    tableView.headerView = nil
    tableView.rowHeight = 44
    tableView.intercellSpacing = NSSize(width: 0, height: 0)
    tableView.backgroundColor = .clear
    tableView.selectionHighlightStyle = .none
    tableView.allowsEmptySelection = true
    tableView.allowsMultipleSelection = false
    tableView.focusRingType = .none
    tableView.dataSource = self
    tableView.delegate = self
    tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    tableView.usesAutomaticRowHeights = false
    tableView.translatesAutoresizingMaskIntoConstraints = false
    tableView.onClickRow = { [weak self] row in
      self?.seek(toRow: row)
    }
  }

  private func configureStatus() {
    spinner.style = .spinning
    spinner.controlSize = .regular
    spinner.isDisplayedWhenStopped = false
    spinner.isHidden = true
    spinner.translatesAutoresizingMaskIntoConstraints = false

    statusLabel.font = MacTheme.bodyFont
    statusLabel.textColor = MacTheme.secondaryTextColor
    statusLabel.alignment = .center
    statusLabel.translatesAutoresizingMaskIntoConstraints = false

    statusStack.orientation = .vertical
    statusStack.alignment = .centerX
    statusStack.spacing = 10
    statusStack.translatesAutoresizingMaskIntoConstraints = false
    statusStack.addArrangedSubview(spinner)
    statusStack.addArrangedSubview(statusLabel)
  }

  private func configureOffsetBar() {
    offsetCaptionLabel.stringValue = L10n.tr("Lyrics Offset")
    offsetCaptionLabel.font = MacTheme.secondaryFont
    offsetCaptionLabel.textColor = MacTheme.secondaryTextColor
    offsetCaptionLabel.translatesAutoresizingMaskIntoConstraints = false

    offsetMinusButton.title = "−0.1s"
    offsetMinusButton.target = self
    offsetMinusButton.action = #selector(offsetMinusPressed)
    offsetMinusButton.bezelStyle = .rounded
    offsetMinusButton.controlSize = .small
    offsetMinusButton.toolTip = L10n.tr("Lyrics behind by") + " 0.1s"

    offsetPlusButton.title = "+0.1s"
    offsetPlusButton.target = self
    offsetPlusButton.action = #selector(offsetPlusPressed)
    offsetPlusButton.bezelStyle = .rounded
    offsetPlusButton.controlSize = .small
    offsetPlusButton.toolTip = L10n.tr("Lyrics ahead by") + " 0.1s"

    offsetResetButton.title = "Reset"
    offsetResetButton.target = self
    offsetResetButton.action = #selector(offsetResetPressed)
    offsetResetButton.bezelStyle = .rounded
    offsetResetButton.controlSize = .small

    offsetValueLabel.font = MacTheme.tabularBodyFont
    offsetValueLabel.alignment = .center
    offsetValueLabel.translatesAutoresizingMaskIntoConstraints = false
    offsetValueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 56).isActive = true

    offsetStack.orientation = .horizontal
    offsetStack.alignment = .centerY
    offsetStack.spacing = 4
    offsetStack.translatesAutoresizingMaskIntoConstraints = false
    offsetStack.addArrangedSubview(offsetCaptionLabel)
    offsetStack.addArrangedSubview(offsetMinusButton)
    offsetStack.addArrangedSubview(offsetValueLabel)
    offsetStack.addArrangedSubview(offsetPlusButton)
    offsetStack.addArrangedSubview(offsetResetButton)
    // The side pane is only 260 pt wide: let the offset controls compress instead of
    // forcing the window bigger.
    for view in [offsetMinusButton, offsetPlusButton, offsetResetButton, offsetValueLabel]
      as [NSView] {
      view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
  }

  // MARK: - Observers

  private func registerObservers() {
    let center = NotificationCenter.default
    center.addObserver(
      self,
      selector: #selector(onlineLyricsDidUpdate(_:)),
      name: .onlineLyricsDidUpdate,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(lyricsOffsetChanged),
      name: .lyricsOffsetChanged,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(libraryChanged),
      name: .librarySongsSynced,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(libraryChanged),
      name: .accountActiveChanged,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(themeColorChanged),
      name: .macThemeColorChanged,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(scrollWillStartLiveScroll),
      name: NSScrollView.willStartLiveScrollNotification,
      object: scrollView
    )
    center.addObserver(
      self,
      selector: #selector(scrollDidEndLiveScroll),
      name: NSScrollView.didEndLiveScrollNotification,
      object: scrollView
    )
  }

  @objc
  private func onlineLyricsDidUpdate(_ notification: Notification) {
    guard let songID = notification.userInfo?["songID"] as? String,
          player.currentlyPlaying?.id == songID
    else { return }
    refreshSongIfNeeded(force: true)
  }

  @objc
  private func lyricsOffsetChanged() {
    refreshOffsetControls()
    updateHighlight(force: true)
  }

  @objc
  private func libraryChanged() {
    refreshSongIfNeeded(force: true)
  }

  @objc
  private func themeColorChanged() {
    tableView.reloadData()
    updateHighlight(force: true)
  }

  @objc
  private func scrollWillStartLiveScroll() {
    isUserScrolling = true
    stopScrollAnimation()
  }

  @objc
  private func scrollDidEndLiveScroll() {
    isUserScrolling = false
  }

  // MARK: - Lyrics loading

  private func refreshSongIfNeeded(force: Bool = false) {
    guard let playable = player.currentlyPlaying, let song = playable.asSong else {
      loadedSongID = nil
      resolvedSongID = nil
      lyrics = nil
      tracker.setLyrics(nil)
      highlightedLine = -1
      tableView.reloadData()
      songTitleLabel.stringValue = ""
      artistLabel.stringValue = ""
      renderStatus(L10n.tr("Play a song to see the lyrics here."))
      return
    }

    refreshHeader(for: song)

    let songID = song.id
    guard force || loadedSongID != songID else { return }
    loadedSongID = songID
    resolvedSongID = nil
    lyrics = nil
    tracker.setLyrics(nil)
    highlightedLine = -1
    tableView.reloadData()

    guard let account = song.account,
          let lyricsRelFilePath = song.lyricsRelFilePath
    else {
      resolvedSongID = songID
      requestOnlineLyricsIfPossible(for: song)
      return
    }

    renderStatus(L10n.tr("Loading lyrics…"), showsSpinner: true)
    Task { @MainActor [weak self] in
      guard let self else { return }
      let lyricsList = try? await FmusicKit.shared.getMeta(account.info)
        .librarySyncer.parseLyrics(relFilePath: lyricsRelFilePath)
      guard self.loadedSongID == songID else { return }
      self.resolvedSongID = songID
      guard let lyricsList,
            let structuredLyrics = lyricsList.getFirstSyncedLyricsOrUnsyncedAsDefault(),
            !structuredLyrics.line.isEmpty
      else {
        self.renderStatus(L10n.tr("No Lyrics"))
        return
      }
      self.apply(lyrics: structuredLyrics)
    }
  }

  private func requestOnlineLyricsIfPossible(for song: Song) {
    guard OnlineLyricsService.shared.canMatchLyrics(for: song) else {
      renderStatus(L10n.tr("No Lyrics"))
      return
    }
    renderStatus(L10n.tr("Searching online lyrics…"), showsSpinner: true)
    let songID = song.id
    Task { @MainActor [weak self] in
      let found = await OnlineLyricsService.shared.matchLyrics(for: song)
      guard let self,
            self.loadedSongID == songID,
            self.player.currentlyPlaying?.id == songID
      else { return }
      if !found {
        self.renderStatus(L10n.tr("No Lyrics"))
      }
      // A successful match posts `.onlineLyricsDidUpdate`, which reloads the page.
    }
  }

  private func apply(lyrics structuredLyrics: StructuredLyrics) {
    lyrics = structuredLyrics
    tracker.setLyrics(structuredLyrics)
    statusStack.isHidden = true
    scrollView.isHidden = false
    spinner.stopAnimation(nil)
    tableView.reloadData()
    tableView.sizeLastColumnToFit()
    updateHighlight(force: true)
    DispatchQueue.main.async { [weak self] in
      guard let self, self.highlightedLine >= 0 else { return }
      self.scrollToLine(self.highlightedLine, animated: false)
      self.updateHighlight(force: true)
    }
  }

  private func refreshHeader(for song: Song) {
    songTitleLabel.stringValue = song.title
    artistLabel.stringValue = song.creatorName
    artistLabel.isHidden = song.creatorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func renderStatus(_ text: String, showsSpinner: Bool = false) {
    lyrics = nil
    tracker.setLyrics(nil)
    highlightedLine = -1
    tableView.reloadData()

    stopScrollAnimation()
    scrollView.isHidden = true
    statusStack.isHidden = false
    statusLabel.stringValue = text
    if showsSpinner {
      spinner.isHidden = false
      spinner.startAnimation(nil)
    } else {
      spinner.stopAnimation(nil)
      spinner.isHidden = true
    }
  }

  // MARK: - Current line tracking

  private func updateHighlight(at seconds: Double? = nil, force: Bool = false) {
    guard isPageVisible else { return }
    guard let lyrics, lyrics.synced, !lyrics.line.isEmpty else {
      guard highlightedLine != -1 else { return }
      let previous = highlightedLine
      highlightedLine = -1
      reloadRows(previous: previous, current: -1)
      return
    }

    let time = seconds ?? player.elapsedTime
    let userOffsetMs = storage.settings.user.lyricsOffsetMs
    guard let snapshot = tracker.snapshot(at: time, userOffsetMs: userOffsetMs) else { return }

    let index = lineIndex(for: snapshot.currentText)
    guard force || index != highlightedLine else { return }
    let previous = highlightedLine
    highlightedLine = index
    reloadRows(previous: previous, current: index)
    scrollToLine(index, animated: !force)
  }

  /// Maps the tracker's current line text back to a row. Duplicate lines are
  /// resolved by walking outwards from the previously highlighted row, like the
  /// inline lyrics pane does.
  private func lineIndex(for currentText: String) -> Int {
    guard let lyrics, !lyrics.line.isEmpty else { return -1 }
    let count = lyrics.line.count
    let candidate = min(max(highlightedLine, 0), count - 1)
    if lyrics.line[candidate].value == currentText { return candidate }
    for index in candidate..<count where lyrics.line[index].value == currentText {
      return index
    }
    for index in stride(from: min(candidate, count - 1), through: 0, by: -1)
      where lyrics.line[index].value == currentText {
      return index
    }
    return candidate
  }

  private func reloadRows(previous: Int, current: Int) {
    guard let lyrics, !lyrics.line.isEmpty else { return }
    var indexes = IndexSet()
    for index in [previous, current] where index >= 0 && index < lyrics.line.count {
      indexes.insert(index)
    }
    guard !indexes.isEmpty else { return }
    tableView.reloadData(
      forRowIndexes: indexes,
      columnIndexes: IndexSet(integer: 0)
    )
  }

  // MARK: - Scrolling

  private func scrollToLine(_ index: Int, animated: Bool) {
    guard index >= 0, index < tableView.numberOfRows else { return }
    tableView.layoutSubtreeIfNeeded()

    let rowRect = tableView.rect(ofRow: index)
    let clipView = scrollView.contentView
    let visibleHeight = clipView.bounds.height
    guard visibleHeight > 0 else { return }
    let maxOriginY = max(0, tableView.bounds.height - visibleHeight)
    let targetY = min(max(0, rowRect.midY - visibleHeight / 2), maxOriginY)

    let shouldAnimate = animated &&
      storage.settings.user.isLyricsSmoothScrolling &&
      !isUserScrolling
    guard shouldAnimate else {
      stopScrollAnimation()
      clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: targetY))
      scrollView.reflectScrolledClipView(clipView)
      return
    }
    animateScroll(to: targetY)
  }

  private func animateScroll(to targetY: CGFloat) {
    stopScrollAnimation()
    let clipView = scrollView.contentView
    let startY = clipView.bounds.origin.y
    guard abs(targetY - startY) > 0.5 else { return }

    scrollAnimationStart = startY
    scrollAnimationTarget = targetY
    scrollAnimationStartTime = ProcessInfo.processInfo.systemUptime
    let timer = Timer(
      timeInterval: 1.0 / 60.0,
      target: self,
      selector: #selector(scrollAnimationTick),
      userInfo: nil,
      repeats: true
    )
    RunLoop.main.add(timer, forMode: .common)
    scrollTimer = timer
  }

  private func stopScrollAnimation() {
    scrollTimer?.invalidate()
    scrollTimer = nil
  }

  @objc
  private func scrollAnimationTick() {
    guard scrollTimer != nil else { return }
    let elapsed = ProcessInfo.processInfo.systemUptime - scrollAnimationStartTime
    let progress = min(1, max(0, elapsed / Self.scrollAnimationDuration))
    let eased = 1 - pow(1 - progress, 3)
    let y = scrollAnimationStart + (scrollAnimationTarget - scrollAnimationStart) * CGFloat(eased)

    let clipView = scrollView.contentView
    clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: y))
    scrollView.reflectScrolledClipView(clipView)

    if progress >= 1 {
      stopScrollAnimation()
    }
  }

  // MARK: - Seeking

  private func seek(toRow row: Int) {
    guard let lyrics, lyrics.synced, lyrics.line.indices.contains(row),
          let start = lyrics.line[row].start
    else { return }

    // The lyric line is shown `offset` later/earlier, so the audio position that
    // corresponds to the line start has to be corrected by the same amount.
    let offsetSeconds = (Double(lyrics.offset) + Double(storage.settings.user.lyricsOffsetMs))
      / 1_000
    let target = max(0, Double(start) / 1_000 - offsetSeconds)
    player.seek(toSecond: target)
    updateHighlight(at: target, force: true)
  }

  // MARK: - Offset controls

  private func refreshOffsetControls() {
    let offsetMs = storage.settings.user.lyricsOffsetMs
    offsetValueLabel.stringValue = Self.offsetDescription(offsetMs)
    offsetMinusButton.isEnabled = offsetMs > -5_000
    offsetPlusButton.isEnabled = offsetMs < 5_000
    offsetResetButton.isEnabled = offsetMs != 0
  }

  private static func offsetDescription(_ milliseconds: Int) -> String {
    guard milliseconds != 0 else { return L10n.tr("Synced") }
    let seconds = String(format: "%.1fs", abs(Double(milliseconds)) / 1_000)
    let direction = milliseconds > 0
      ? L10n.tr("Lyrics ahead by")
      : L10n.tr("Lyrics behind by")
    return "\(direction) \(seconds)"
  }

  private func adjustOffset(by deltaMs: Int) {
    var user = storage.settings.user
    let updated = min(5_000, max(-5_000, user.lyricsOffsetMs + deltaMs))
    guard updated != user.lyricsOffsetMs else {
      refreshOffsetControls()
      return
    }
    user.lyricsOffsetMs = updated
    storage.settings.user = user
    refreshOffsetControls()
    // Re-render every visible lyrics view (desktop overlay, inline panes, this page).
    NotificationCenter.default.post(name: .lyricsOffsetChanged, object: nil)
    updateHighlight(force: true)
  }

  @objc
  private func offsetMinusPressed() {
    adjustOffset(by: -Self.offsetStepMs)
  }

  @objc
  private func offsetPlusPressed() {
    adjustOffset(by: Self.offsetStepMs)
  }

  @objc
  private func offsetResetPressed() {
    guard storage.settings.user.lyricsOffsetMs != 0 else { return }
    var user = storage.settings.user
    user.lyricsOffsetMs = 0
    storage.settings.user = user
    refreshOffsetControls()
    NotificationCenter.default.post(name: .lyricsOffsetChanged, object: nil)
    updateHighlight(force: true)
  }

  // MARK: - NSTableViewDataSource

  func numberOfRows(in tableView: NSTableView) -> Int {
    lyrics?.line.count ?? 0
  }

  // MARK: - NSTableViewDelegate

  func tableView(
    _ tableView: NSTableView,
    viewFor tableColumn: NSTableColumn?,
    row: Int
  )
    -> NSView? {
    guard let lyrics, lyrics.line.indices.contains(row) else { return nil }
    let cell = tableView.makeView(withIdentifier: Column.line, owner: self) as?
      LyricsPageLineCellView ?? LyricsPageLineCellView()
    cell.identifier = Column.line
    let line = lyrics.line[row]
    let isCurrent = lyrics.synced && row == highlightedLine
    cell.configure(
      text: line.value,
      translation: line.translation,
      isCurrent: isCurrent,
      accentColor: MacTheme.accentColor
    )
    return cell
  }

  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    guard let lyrics, lyrics.line.indices.contains(row) else { return 44 }
    let width = max(
      160,
      tableView.bounds.width - Self.lineHorizontalInset * 2
    )
    let line = lyrics.line[row]
    let text = line.value.isEmpty ? " " : line.value
    var height = Self.textHeight(text, font: Self.currentLineFont, width: width)
    if let translation = line.translation, !translation.isEmpty {
      height += Self.textHeight(translation, font: Self.translationFont, width: width) + 2
    }
    return max(44, ceil(height) + 22)
  }

  private static func textHeight(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
    let bounds = (text as NSString).boundingRect(
      with: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      attributes: [.font: font]
    )
    return bounds.height
  }

  // MARK: - MusicPlayable

  func didStartPlayingFromBeginning() {
    refreshSongIfNeeded()
    updateHighlight(force: true)
  }

  func didStartPlaying() {
    refreshSongIfNeeded()
    updateHighlight(force: true)
  }

  func didPause() {
    updateHighlight(force: true)
  }

  func didStopPlaying() {
    refreshSongIfNeeded(force: true)
  }

  func didElapsedTimeChange() {
    updateHighlight()
  }

  func didLyricsTimeChange(time: CMTime) {
    guard isPageVisible else { return }
    updateHighlight(at: time.seconds)
  }

  func didPlaylistChange() {
    refreshSongIfNeeded()
    updateHighlight(force: true)
  }

  func didArtworkChange() {}

  func didNowPlayingInfoChange() {
    if let song = player.currentlyPlaying?.asSong {
      refreshHeader(for: song)
    }
  }

  func didShuffleChange() {}

  func didRepeatChange() {}

  func didPlaybackRateChange() {}
}

// MARK: - LyricsPageTableView

/// Headerless table that reports single clicks on a lyric row so the page can seek.
@MainActor
private final class LyricsPageTableView: NSTableView {
  var onClickRow: ((Int) -> Void)?

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    let clickedRow = row(at: point)
    if clickedRow >= 0 {
      onClickRow?(clickedRow)
    }
    super.mouseDown(with: event)
  }
}

// MARK: - LyricsPageLineCellView

/// One centred lyric line plus its optional translation.
@MainActor
private final class LyricsPageLineCellView: NSTableCellView {
  private let lineLabel = NSTextField(labelWithString: "")
  private let translationLabel = NSTextField(labelWithString: "")

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    for label in [lineLabel, translationLabel] {
      label.isEditable = false
      label.isSelectable = false
      label.drawsBackground = false
      label.isBordered = false
      label.alignment = .center
      label.lineBreakMode = .byWordWrapping
      label.maximumNumberOfLines = 0
      label.cell?.wraps = true
      label.cell?.isScrollable = false
      label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      label.translatesAutoresizingMaskIntoConstraints = false
      addSubview(label)
    }

    NSLayoutConstraint.activate([
      lineLabel.topAnchor.constraint(equalTo: topAnchor, constant: 9),
      lineLabel.leadingAnchor.constraint(
        equalTo: leadingAnchor,
        constant: LyricsPageViewController.lineHorizontalInset
      ),
      lineLabel.trailingAnchor.constraint(
        equalTo: trailingAnchor,
        constant: -LyricsPageViewController.lineHorizontalInset
      ),

      translationLabel.topAnchor.constraint(equalTo: lineLabel.bottomAnchor, constant: 2),
      translationLabel.leadingAnchor.constraint(equalTo: lineLabel.leadingAnchor),
      translationLabel.trailingAnchor.constraint(equalTo: lineLabel.trailingAnchor),
      translationLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -9),
    ])
  }

  required init?(coder: NSCoder) {
    nil
  }

  func configure(
    text: String,
    translation: String?,
    isCurrent: Bool,
    accentColor: NSColor
  ) {
    lineLabel.stringValue = text.isEmpty ? " " : text
    lineLabel.font = isCurrent
      ? LyricsPageViewController.currentLineFont
      : LyricsPageViewController.lineFont
    lineLabel.textColor = isCurrent ? accentColor : .labelColor

    let translationText = translation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    translationLabel.stringValue = translationText
    translationLabel.isHidden = translationText.isEmpty
    translationLabel.font = LyricsPageViewController.translationFont
    translationLabel.textColor = isCurrent
      ? accentColor.withAlphaComponent(0.75)
      : NSColor.secondaryLabelColor
  }
}
