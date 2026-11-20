//
//  LyricsSidebarViewController.swift
//  fmusic-macOS
//
//  Compact lyrics column shown next to the library (Catalyst fmusic style):
//  centered lines, current line highlighted, auto-scrolls with playback.
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

/// Lyrics side pane: a simple centered list that keeps the current line highlighted.
@MainActor
final class LyricsSidebarViewController: NSViewController, MusicPlayable {
  private let scrollView = NSScrollView()
  private let stackView = NSStackView()
  private let statusLabel = NSTextField(labelWithString: "")
  private var lineLabels: [NSTextField] = []

  private var lyrics: StructuredLyrics?
  private var loadedSongID: String?
  private var currentLine = -1

  nonisolated(unsafe) private var syncTimer: Timer?

  private var player: PlayerFacade { FmusicKit.shared.player }

  private static let lineFontSize: CGFloat = 13
  private static let currentFontSize: CGFloat = 14

  override func loadView() {
    let root = ThemedBackgroundView()

    stackView.orientation = .vertical
    stackView.alignment = .centerX
    stackView.spacing = 18
    stackView.edgeInsets = NSEdgeInsets(top: 24, left: 14, bottom: 90, right: 14)
    stackView.translatesAutoresizingMaskIntoConstraints = false

    scrollView.documentView = stackView
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    statusLabel.font = .systemFont(ofSize: 12)
    statusLabel.textColor = MacTheme.secondaryTextColor
    statusLabel.alignment = .center
    statusLabel.maximumNumberOfLines = 0
    statusLabel.translatesAutoresizingMaskIntoConstraints = false

    root.addSubview(scrollView)
    root.addSubview(statusLabel)

    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
      scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

      stackView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
      stackView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
      stackView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),

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
    // The player notifications are not guaranteed at a fixed rate, so a light timer
    // keeps the highlight glued to the audio position (like the Catalyst overlay).
    syncTimer = Timer(
      timeInterval: 0.15,
      target: self,
      selector: #selector(syncTick),
      userInfo: nil,
      repeats: true
    )
    if let syncTimer {
      RunLoop.main.add(syncTimer, forMode: .common)
    }
  }

  @objc
  private func syncTick() {
    updateHighlight()
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
      renderPlaceholder(L10n.tr("Play a song to see the lyrics here."))
      return
    }
    let songID = song.id
    guard force || loadedSongID != songID else { return }
    loadedSongID = songID
    lyrics = nil
    currentLine = -1
    renderPlaceholder("")

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
      renderPlaceholder(L10n.tr("No Lyrics"))
      return
    }
    Task { @MainActor [weak self] in
      let found = await OnlineLyricsService.shared.matchLyrics(for: song)
      guard let self, self.loadedSongID == song.id else { return }
      if !found, self.lyrics == nil {
        self.renderPlaceholder(L10n.tr("No Lyrics"))
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

  // MARK: - Rendering

  private func apply(lyrics structuredLyrics: StructuredLyrics) {
    lyrics = structuredLyrics
    statusLabel.isHidden = true
    currentLine = -1
    rebuildLines()
    updateHighlight(force: true)
  }

  private func renderPlaceholder(_ text: String) {
    statusLabel.stringValue = text
    statusLabel.isHidden = text.isEmpty
    lineLabels.forEach { $0.removeFromSuperview() }
    lineLabels.removeAll()
  }

  private func rebuildLines() {
    lineLabels.forEach { $0.removeFromSuperview() }
    lineLabels.removeAll()
    guard let lyrics else { return }

    for (index, line) in lyrics.line.enumerated() {
      let label = NSTextField(wrappingLabelWithString: line.value.isEmpty ? "♪" : line.value)
      label.font = .systemFont(ofSize: Self.lineFontSize)
      label.textColor = .labelColor
      label.alignment = .center
      label.maximumNumberOfLines = 0
      label.cell?.wraps = true
      label.isEditable = false
      label.isSelectable = false
      label.identifier = NSUserInterfaceItemIdentifier("\(index)")
      label.translatesAutoresizingMaskIntoConstraints = false
      label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      label.addGestureRecognizer(
        NSClickGestureRecognizer(target: self, action: #selector(lineClicked(_:)))
      )
      stackView.addArrangedSubview(label)
      label.widthAnchor.constraint(
        equalTo: scrollView.contentView.widthAnchor,
        constant: -28
      ).isActive = true
      lineLabels.append(label)
    }
    stackView.layoutSubtreeIfNeeded()
  }

  private func updateHighlight(force: Bool = false) {
    guard let lyrics else { return }
    let offsetSeconds = (Double(lyrics.offset) +
      Double(FmusicKit.shared.storage.settings.user.lyricsOffsetMs)) / 1000.0
    let position = player.elapsedTime + offsetSeconds
    var index = -1
    for (lineIndex, line) in lyrics.line.enumerated() {
      guard line.start != nil else { continue }
      if CMTimeGetSeconds(line.startTime) <= position {
        index = lineIndex
      } else {
        break
      }
    }
    guard index != currentLine || force else { return }
    currentLine = index
    let accent = MacTheme.accentColor
    for (lineIndex, label) in lineLabels.enumerated() {
      let isCurrent = lineIndex == index
      label.font = .systemFont(
        ofSize: isCurrent ? Self.currentFontSize : Self.lineFontSize,
        weight: isCurrent ? .semibold : .regular
      )
      label.textColor = isCurrent ? accent : .labelColor
    }
    scrollToCurrentLine(animated: true)
  }

  @objc
  private func lineClicked(_ recognizer: NSClickGestureRecognizer) {
    guard let label = recognizer.view as? NSTextField,
          let index = Int(label.identifier?.rawValue ?? ""),
          let lyrics,
          lyrics.line.indices.contains(index),
          let start = lyrics.line[index].start
    else { return }
    let seconds = Double(start) / 1000.0
    player.seek(toSecond: seconds)
    currentLine = index
    updateHighlight(force: true)
  }

  private func scrollToCurrentLine(animated: Bool) {
    guard currentLine >= 0, currentLine < lineLabels.count else { return }
    let label = lineLabels[currentLine]
    let targetY = label.frame.midY - scrollView.contentView.bounds.height / 2
    let maxY = max(0, (scrollView.documentView?.frame.height ?? 0) -
      scrollView.contentView.bounds.height)
    let y = min(max(0, targetY), maxY)
    if animated {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.25
        scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: y))
      }
    } else {
      scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
      scrollView.reflectScrolledClipView(scrollView.contentView)
    }
  }

  @objc
  private func themeColorChanged() {
    updateHighlight(force: true)
  }

  @objc
  private func lyricsOffsetChanged() {
    updateHighlight(force: true)
  }

  // MARK: - MusicPlayable

  func didStartPlayingFromBeginning() {
    loadLyrics(force: true)
  }

  func didStartPlaying() {
    loadLyrics()
    updateHighlight(force: true)
  }

  func didPause() {}

  func didStopPlaying() {
    loadLyrics(force: true)
  }

  func didElapsedTimeChange() {
    updateHighlight()
  }

  func didLyricsTimeChange(time: CMTime) {
    updateHighlight()
  }

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
