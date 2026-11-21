//
//  LyricsPaneView.swift
//  fmusic-macOS
//
//  Reusable lyrics pane for the queue and now playing pages. Loads the current
//  song's lyrics the same way `LyricsOverlayController` does, tracks the current
//  line with `LyricsLineTracker` and highlights it in a read-only text view.
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

/// Small self-contained lyrics panel: follows the player's current song, shows the
/// full lyric text and highlights the line that is playing right now.
@MainActor
final class LyricsPaneView: NSView {
  private let scrollView = NSScrollView()
  private let textView = NSTextView()
  private let tracker = LyricsLineTracker()

  private var lyrics: StructuredLyrics?
  private var renderedSongID: String?
  private var loadedSongID: String?
  private var lastRenderedLine = -2
  private var lineLocations: [Int] = []
  private var renderedStatus: String?
  private var hasRegisteredObservers = false

  nonisolated(unsafe) private var clockTimer: Timer?

  private var player: PlayerFacade { FmusicKit.shared.player }

  // MARK: - Init

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    configure()
  }

  required init?(coder: NSCoder) {
    nil
  }

  deinit {
    clockTimer?.invalidate()
    NotificationCenter.default.removeObserver(self)
  }

  private func configure() {
    wantsLayer = true

    textView.isEditable = false
    textView.isSelectable = false
    textView.drawsBackground = false
    textView.textContainerInset = NSSize(width: 6, height: 8)
    textView.minSize = NSSize(width: 0, height: 0)
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    textView.textContainer?.containerSize = NSSize(
      width: 0,
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.textContainer?.widthTracksTextView = true

    scrollView.documentView = textView
    scrollView.hasVerticalScroller = true
    scrollView.drawsBackground = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(scrollView)
    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])

    renderStatus(L10n.tr("Play a song to see the lyrics here."))
  }

  // MARK: - Lifecycle

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window != nil {
      startClock()
      registerObserversIfNeeded()
      refreshSongIfNeeded()
      renderCurrentLine(force: true)
    } else {
      stopClock()
    }
  }

  private func registerObserversIfNeeded() {
    guard !hasRegisteredObservers else { return }
    hasRegisteredObservers = true
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
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(lyricsOffsetChanged),
      name: .lyricsOffsetChanged,
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
      selector: #selector(themeColorChanged),
      name: .macThemeColorChanged,
      object: nil
    )
  }

  private func startClock() {
    guard clockTimer == nil else { return }
    let timer = Timer(
      timeInterval: 0.25,
      target: self,
      selector: #selector(clockTick),
      userInfo: nil,
      repeats: true
    )
    RunLoop.main.add(timer, forMode: .common)
    clockTimer = timer
  }

  private func stopClock() {
    clockTimer?.invalidate()
    clockTimer = nil
  }

  @objc
  private func clockTick() {
    refreshSongIfNeeded()
    renderCurrentLine(force: false)
  }

  // MARK: - Notifications

  @objc
  private func libraryChanged() {
    // Lyrics files may have been written by the sync; reload the current song.
    loadedSongID = nil
    lyrics = nil
    tracker.setLyrics(nil)
    refreshSongIfNeeded()
    renderCurrentLine(force: true)
  }

  @objc
  private func lyricsOffsetChanged() {
    renderCurrentLine(force: true)
  }

  @objc
  private func themeColorChanged() {
    renderCurrentLine(force: true)
  }

  @objc
  private func onlineLyricsDidUpdate(_ notification: Notification) {
    guard let songID = notification.userInfo?["songID"] as? String,
          player.currentlyPlaying?.id == songID
    else { return }
    loadedSongID = nil
    lyrics = nil
    tracker.setLyrics(nil)
    refreshSongIfNeeded()
    renderCurrentLine(force: true)
  }

  // MARK: - Lyrics loading

  private func refreshSongIfNeeded() {
    guard let playable = player.currentlyPlaying, let song = playable.asSong else {
      loadedSongID = nil
      lyrics = nil
      tracker.setLyrics(nil)
        renderedSongID = nil
      lastRenderedLine = -2
      renderStatus(L10n.tr("Play a song to see the lyrics here."))
      return
    }

    let songID = song.id
    guard loadedSongID != songID else { return }
    loadedSongID = songID
    lyrics = nil
    tracker.setLyrics(nil)
    renderedSongID = nil
    lastRenderedLine = -2

    guard let account = song.account,
          let lyricsRelFilePath = song.lyricsRelFilePath
    else {
      renderStatus(L10n.tr("No Lyrics"))
      requestOnlineLyricsIfPossible(for: song)
      return
    }

    renderStatus(L10n.tr("Loading lyrics…"))
    Task { @MainActor [weak self] in
      guard let self else { return }
      guard let lyricsList = try? await FmusicKit.shared.getMeta(account.info)
        .librarySyncer.parseLyrics(relFilePath: lyricsRelFilePath),
        self.loadedSongID == songID
      else { return }
      guard let structuredLyrics = lyricsList.getFirstSyncedLyricsOrUnsyncedAsDefault()
      else {
        self.renderStatus(L10n.tr("No Lyrics"))
        return
      }
      self.lyrics = structuredLyrics
      self.tracker.setLyrics(structuredLyrics)
      self.renderLyrics()
    }
  }

  private func requestOnlineLyricsIfPossible(for song: Song) {
    guard OnlineLyricsService.shared.canMatchLyrics(for: song) else { return }
    Task { @MainActor in
      _ = await OnlineLyricsService.shared.matchLyrics(for: song)
    }
  }

  // MARK: - Rendering

  private func renderStatus(_ text: String) {
    guard renderedStatus != text || textView.string != text else { return }
    renderedStatus = text
    let attributed = NSAttributedString(string: text, attributes: [
      .font: NSFont.systemFont(ofSize: 13),
      .foregroundColor: NSColor.secondaryLabelColor,
    ])
    textView.textStorage?.setAttributedString(attributed)
    renderedSongID = nil
    lastRenderedLine = -2
    lineLocations = []
  }

  private func renderLyrics() {
    guard let lyrics, !lyrics.line.isEmpty else {
      renderStatus(L10n.tr("No Lyrics"))
      return
    }

    let currentIndex = max(0, currentSyncedLineIndex())
    let output = NSMutableAttributedString()
    lineLocations = []

    // Catalyst `LyricTableCell` sizes: 24 pt inactive, 29 pt bold active, 17 pt translation.
    let normalFont = NSFont.systemFont(ofSize: 24, weight: .semibold)
    let currentFont = NSFont.systemFont(ofSize: 29, weight: .bold)
    let translationFont = NSFont.systemFont(ofSize: 17)

    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 8

    for (index, line) in lyrics.line.enumerated() {
      lineLocations.append(output.length)
      let isCurrent = index == currentIndex
      let text = line.value.isEmpty ? " " : line.value
      var attributes: [NSAttributedString.Key: Any] = [
        .font: isCurrent ? currentFont : normalFont,
        .foregroundColor: isCurrent
          ? NSColor.white
          : NSColor.white.withAlphaComponent(0.72),
        .paragraphStyle: paragraph,
      ]
      output.append(NSAttributedString(string: text + "\n", attributes: attributes))

      if let translation = line.translation, !translation.isEmpty {
        output.append(NSAttributedString(
          string: translation + "\n",
          attributes: [
            .font: translationFont,
            .foregroundColor: NSColor.white.withAlphaComponent(0.45),
            .paragraphStyle: paragraph,
          ]
        ))
      }
    }

    textView.textStorage?.setAttributedString(output)
    renderedStatus = nil
    renderedSongID = player.currentlyPlaying?.id
    lastRenderedLine = currentIndex
    scrollToLine(currentIndex)
  }

  private func renderCurrentLine(force: Bool) {
    guard let lyrics, !lyrics.line.isEmpty else { return }
    let currentIndex = max(0, currentSyncedLineIndex())
    if !force, currentIndex == lastRenderedLine, renderedSongID == player.currentlyPlaying?.id {
      return
    }
    renderLyrics()
  }

  private func currentSyncedLineIndex() -> Int {
    guard let lyrics, lyrics.synced, !lyrics.line.isEmpty else { return -1 }
    guard let snapshot = tracker.snapshot(
      at: player.elapsedTime,
      userOffsetMs: FmusicKit.shared.storage.settings.user.lyricsOffsetMs
    ) else { return -1 }

    let target = snapshot.currentText
    let count = lyrics.line.count
    let index = min(max(lastRenderedLine, 0), count - 1)
    if lyrics.line[index].value == target { return index }
    for candidate in index..<count where lyrics.line[candidate].value == target {
      return candidate
    }
    for candidate in stride(from: min(index, count - 1), through: 0, by: -1)
      where lyrics.line[candidate].value == target
    {
      return candidate
    }
    return index
  }

  private func scrollToLine(_ lineIndex: Int) {
    guard lineIndex >= 0, lineIndex < lineLocations.count else { return }
    let location = lineLocations[lineIndex]
    guard let string = textView.textStorage?.string, location < string.utf16.count else { return }
    let range = NSRange(location: location, length: 0)
    textView.scrollRangeToVisible(range)
  }
}
