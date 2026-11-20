//
//  LyricsOverlayController.swift
//  fmusic-macOS
//
//  Coordinator that owns the desktop lyrics panel and the menu bar lyrics item and
//  feeds both from the player clock, ported from the Catalyst app's
//  `LyricsOverlayManager`.
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

// MARK: - LyricsOverlayController

@MainActor
final class LyricsOverlayController: NSObject, MusicPlayable {
  private let player: PlayerFacade
  private let storage: PersistentStorage
  private let tracker = LyricsLineTracker()

  private var desktopPanel: DesktopLyricsWindowController?
  private var menuBarController: MenuBarLyricsController?
  private var loadedSongID: String?
  // Set once the lyrics lookup for the current song returned, so settings changes do not
  // re-read the same missing or empty lyrics file on every refresh.
  private var resolvedSongID: String?
  private var isLoadingLyrics = false
  private var isStarted = false
  private var hasRegisteredNotifier = false
  // Cached switch state: the 60 Hz playback clock must not re-read and decode
  // the whole settings blob just to discover that both overlays are off.
  private var isFeatureEnabled = false
  // The same applies to the overlay style: re-read settings only when a
  // setting change triggers refreshFromSettings().
  private var isDesktopLyricsShown = false
  private var isDesktopNextLineShown = true
  private var cachedGlobalOffsetMs = 0
  private var isLyricsOffsetObserverRegistered = false
  private static let songOffsetDefaultsKey = "fmusic.desktopLyrics.songOffsets"
  private var overlaySongOffsetsCache: [String: Int]?

  // MARK: State

  /// Mirrors `UserSettings.isDesktopLyricsEnabled` (the feature switch), like the
  /// Catalyst manager's `isDesktopLyricsShown`.
  private(set) var showDesktopLyrics = false
  /// True while a menu bar status item is installed.
  private(set) var showMenuBarLyrics = false

  /// Overrides the default "bring the main window to front" behaviour. The app
  /// bootstrap may leave these nil and rely on `AppDelegate`.
  var onOpenMainWindow: (() -> Void)?
  /// Called when the overlay itself flips a lyrics setting (lock/click-through or
  /// the "hide desktop lyrics" button), so a settings UI can refresh its controls.
  var onSettingsChanged: (() -> Void)?

  // MARK: - Init

  override init() {
    let fmusic = FmusicKit.shared
    self.player = fmusic.player
    self.storage = fmusic.storage
    super.init()
  }

  // MARK: - Lifecycle

  func start() {
    isStarted = true
    if !hasRegisteredNotifier {
      hasRegisteredNotifier = true
      player.addNotifier(notifier: self)
    }
    if !isLyricsOffsetObserverRegistered {
      isLyricsOffsetObserverRegistered = true
      let handler = FmusicKit.shared.notificationHandler
      handler.register(
        self,
        selector: #selector(onlineLyricsDidUpdate(_:)),
        name: .onlineLyricsDidUpdate,
        object: nil
      )
      handler.register(
        self,
        selector: #selector(lyricsOffsetDidChange(_:)),
        name: .lyricsOffsetChanged,
        object: nil
      )
    }
    refreshFromSettings()
  }

  func stop() {
    isStarted = false
    if isLyricsOffsetObserverRegistered {
      isLyricsOffsetObserverRegistered = false
      let handler = FmusicKit.shared.notificationHandler
      handler.remove(self, name: .onlineLyricsDidUpdate, object: nil)
      handler.remove(self, name: .lyricsOffsetChanged, object: nil)
    }
    desktopPanel?.hide()
    desktopPanel = nil
    menuBarController?.remove()
    menuBarController = nil
    tracker.setLyrics(nil)
    loadedSongID = nil
    resolvedSongID = nil
    isLoadingLyrics = false
    isFeatureEnabled = false
    showDesktopLyrics = false
    showMenuBarLyrics = false
  }

  /// Re-reads every lyrics overlay setting. Call after the settings UI writes
  /// `storage.settings.user` (the old app called `updateLyricsOverlays()`).
  func settingsChanged() {
    guard isStarted else { return }
    refreshFromSettings()
  }

  // MARK: - Settings

  private func refreshFromSettings() {
    let user = storage.settings.user
    let isAnyFeatureEnabled = user.isDesktopLyricsEnabled || user.isMenuBarLyricsEnabled
    isFeatureEnabled = isAnyFeatureEnabled
    isDesktopLyricsShown = user.isDesktopLyricsEnabled
    isDesktopNextLineShown = user.isDesktopLyricsNextLineShown
    cachedGlobalOffsetMs = user.lyricsOffsetMs
    showDesktopLyrics = user.isDesktopLyricsEnabled

    if user.isDesktopLyricsEnabled {
      if desktopPanel == nil {
        desktopPanel = makeDesktopPanel()
      }
      if let panel = desktopPanel {
        panel.apply(style: DesktopLyricsStyle(
          pointSize: user.desktopLyricsFontSize.pointSize,
          backgroundOpacity: Double(user.desktopLyricsBackgroundOpacity) / 100.0,
          alignment: user.desktopLyricsAlignment,
          showsNextLine: user.isDesktopLyricsNextLineShown,
          controlIconBrightness: Double(user.desktopLyricsControlIconBrightness) / 100.0
        ))
        panel.setAlwaysOnTop(user.isDesktopLyricsAlwaysOnTop)
        panel.setLocked(user.isDesktopLyricsLocked)
        if player.currentlyPlaying != nil {
          panel.show()
        } else {
          panel.hide()
        }
      }
    } else {
      desktopPanel?.hide()
    }

    if user.isMenuBarLyricsEnabled {
      if menuBarController == nil {
        menuBarController = makeMenuBarController()
      }
    } else {
      menuBarController?.remove()
      menuBarController = nil
    }
    showMenuBarLyrics = menuBarController != nil

    guard isAnyFeatureEnabled else { return }
    loadLyricsIfNeeded()
    render(at: player.elapsedTime)
  }

  // MARK: - MusicPlayable

  func didStartPlayingFromBeginning() {
    guard isStarted else { return }
    desktopPanel?.setPlaying(true)
    loadLyricsIfNeeded()
    render(at: player.elapsedTime)
  }

  func didStartPlaying() {
    guard isStarted else { return }
    desktopPanel?.setPlaying(true)
    guard let songID = player.currentlyPlaying?.id else {
      resetPlaybackState()
      return
    }
    if songID != loadedSongID {
      loadLyricsIfNeeded()
    }
    render(at: player.elapsedTime)
  }

  func didStopPlaying() {
    guard isStarted else { return }
    desktopPanel?.setPlaying(false)
    resetPlaybackState()
  }

  func didPause() {
    guard isStarted else { return }
    desktopPanel?.setPlaying(false)
  }

  func didLyricsTimeChange(time: CMTime) {
    guard isStarted, isFeatureEnabled else { return }
    render(at: time.seconds)
  }

  func didElapsedTimeChange() {}

  func didNowPlayingInfoChange() {}

  func didPlaylistChange() {
    guard isStarted else { return }
    loadLyricsIfNeeded()
    render(at: player.elapsedTime)
  }

  func didArtworkChange() {}
  func didShuffleChange() {}
  func didRepeatChange() {}
  func didPlaybackRateChange() {}

  // MARK: - Lyrics loading

  private var isAnyFeatureEnabled: Bool {
    isFeatureEnabled
  }

  private func resetPlaybackState() {
    tracker.setLyrics(nil)
    loadedSongID = nil
    resolvedSongID = nil
    isLoadingLyrics = false
    desktopPanel?.hide()
    menuBarController?.update(title: "fmusic")
  }

  private func loadLyricsIfNeeded() {
    guard isAnyFeatureEnabled else { return }
    guard let playable = player.currentlyPlaying,
          let song = playable.asSong
    else {
      if player.currentlyPlaying == nil {
        resetPlaybackState()
      } else {
        tracker.setLyrics(nil)
        loadedSongID = player.currentlyPlaying?.id
        render(at: player.elapsedTime)
      }
      return
    }

    let songID = song.id
    if loadedSongID == songID,
       tracker.hasLyrics || isLoadingLyrics || resolvedSongID == songID {
      return
    }
    loadedSongID = songID
    resolvedSongID = nil
    tracker.setLyrics(nil)

    guard let account = song.account,
          let lyricsRelFilePath = song.lyricsRelFilePath
    else {
      resolvedSongID = songID
      requestOnlineLyricsIfPossible(for: song)
      render(at: player.elapsedTime)
      return
    }

    isLoadingLyrics = true
    Task { @MainActor in
      defer {
        if self.loadedSongID == songID {
          self.isLoadingLyrics = false
        }
      }
      // A failed read may be transient, so only a completed lookup marks the song as
      // resolved; an empty result (no lyrics file) is a valid answer.
      guard let lyricsList = try? await FmusicKit.shared.getMeta(account.info)
        .librarySyncer.parseLyrics(relFilePath: lyricsRelFilePath),
        self.loadedSongID == songID
      else { return }
      self.resolvedSongID = songID
      guard let structuredLyrics = lyricsList.getFirstSyncedLyricsOrUnsyncedAsDefault()
      else { return }
      self.tracker.setLyrics(structuredLyrics)
      guard self.player.currentlyPlaying?.id == songID else { return }
      self.render(at: self.player.elapsedTime)
    }
  }

  private func requestOnlineLyricsIfPossible(for song: Song) {
    guard OnlineLyricsService.shared.canMatchLyrics(for: song) else { return }
    Task { @MainActor in
      _ = await OnlineLyricsService.shared.matchLyrics(for: song)
    }
  }

  @objc
  private func onlineLyricsDidUpdate(_ notification: Notification) {
    guard isAnyFeatureEnabled,
          let songID = notification.userInfo?["songID"] as? String,
          player.currentlyPlaying?.id == songID
    else { return }
    resolvedSongID = nil
    loadLyricsIfNeeded()
    render(at: player.elapsedTime)
  }

  @objc
  private func lyricsOffsetDidChange(_ notification: Notification) {
    guard isFeatureEnabled else { return }
    cachedGlobalOffsetMs = storage.settings.user.lyricsOffsetMs
    render(at: player.elapsedTime)
  }

  // MARK: - Rendering

  private func render(at seconds: Double) {
    guard isFeatureEnabled else { return }
    // The overlay adds a per-song correction to the global lyrics offset so
    // the sync panel can tune one track without touching every song.
    let songOffset = player.currentlyPlaying
      .flatMap { overlaySongOffsets[$0.id] } ?? 0
    let snapshot = tracker.snapshot(
      at: seconds,
      userOffsetMs: cachedGlobalOffsetMs + songOffset
    )
    updateMenuBar(with: snapshot)
    updateDesktopPanel(with: snapshot)
  }

  private func updateMenuBar(with snapshot: LyricsSnapshot?) {
    guard let menuBarController else { return }
    let line = snapshot?.currentText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !line.isEmpty {
      menuBarController.update(title: "♪ \(line)")
    } else if let title = player.currentlyPlaying?.title {
      menuBarController.update(title: "♪ \(title)")
    } else {
      menuBarController.update(title: "fmusic")
    }
  }

  private func updateDesktopPanel(with snapshot: LyricsSnapshot?) {
    guard let desktopPanel,
          isDesktopLyricsShown
    else { return }
    guard let playable = player.currentlyPlaying else {
      desktopPanel.hide()
      return
    }

    if !desktopPanel.isVisible {
      desktopPanel.show()
    }

    let showsNextLine = isDesktopNextLineShown
    let header = playable.creatorName.isEmpty
      ? playable.title
      : "\(playable.title) · \(playable.creatorName)"
    if let snapshot {
      // The small preview row doubles as the translation row for bilingual lyrics.
      let nextText = showsNextLine
        ? (snapshot.currentTranslation ?? snapshot.nextText)
        : nil
      desktopPanel.update(content: DesktopLyricsContent(
        headerText: header,
        currentText: snapshot.currentText,
        nextText: nextText,
        syllables: snapshot.syllables,
        syllableProgress: snapshot.syllableProgress
      ))
    } else {
      desktopPanel.update(content: DesktopLyricsContent(
        headerText: nil,
        currentText: playable.title,
        nextText: showsNextLine && !playable.creatorName.isEmpty
          ? playable.creatorName
          : nil,
        syllables: [],
        syllableProgress: []
      ))
    }
  }

  // MARK: - Controllers

  private func makeDesktopPanel() -> DesktopLyricsWindowController {
    let panel = DesktopLyricsWindowController()
    panel.onOpenMainWindow = { [weak self] in
      self?.openMainWindow()
    }
    panel.onHideDesktopLyrics = { [weak self] in
      guard let self else { return }
      storage.settings.user.isDesktopLyricsEnabled = false
      self.settingsChanged()
      self.onSettingsChanged?()
    }
    panel.offsetSnapshot = { [weak self] in
      self?.overlayOffsetSnapshot()
    }
    panel.adjustSongOffset = { [weak self] songID, milliseconds in
      self?.setOverlaySongOffset(milliseconds, for: songID)
    }
    panel.resetSongOffset = { [weak self] songID in
      self?.setOverlaySongOffset(0, for: songID)
    }
    panel.onClickThroughChanged = { [weak self] enabled in
      guard let self else { return }
      storage.settings.user.isDesktopLyricsLocked = enabled
      self.settingsChanged()
      self.onSettingsChanged?()
    }
    panel.onPlayPrevious = { [weak self] in
      self?.player.playPrevious()
    }
    panel.onPlayNext = { [weak self] in
      self?.player.playNext()
    }
    panel.onTogglePlayPause = { [weak self] in
      self?.player.togglePlayPause()
    }
    panel.setPlaying(player.isPlaying)
    return panel
  }

  private func makeMenuBarController() -> MenuBarLyricsController {
    let controller = MenuBarLyricsController()
    controller.onOpenApp = { [weak self] in
      self?.openMainWindow()
    }
    return controller
  }

  private func openMainWindow() {
    if let onOpenMainWindow {
      onOpenMainWindow()
      return
    }
    AppDelegate.sharedAppDelegate?.showMainWindow(nil)
  }

  // MARK: - Overlay lyrics offset

  private var overlaySongOffsets: [String: Int] {
    get {
      if let cache = overlaySongOffsetsCache { return cache }
      let loaded = UserDefaults.standard.dictionary(
        forKey: Self.songOffsetDefaultsKey
      ) as? [String: Int] ?? [:]
      overlaySongOffsetsCache = loaded
      return loaded
    }
    set {
      overlaySongOffsetsCache = newValue
      UserDefaults.standard.set(newValue, forKey: Self.songOffsetDefaultsKey)
    }
  }

  private func overlayOffsetSnapshot() -> OverlayOffsetSnapshot? {
    guard let playable = player.currentlyPlaying else { return nil }
    return OverlayOffsetSnapshot(
      songID: playable.id,
      songMilliseconds: overlaySongOffsets[playable.id] ?? 0,
      globalMilliseconds: cachedGlobalOffsetMs
    )
  }

  private func setOverlaySongOffset(
    _ milliseconds: Int,
    for songID: String
  )
    -> OverlayOffsetSnapshot? {
    var offsets = overlaySongOffsets
    let clamped = min(5_000, max(-5_000, milliseconds))
    if clamped == 0 {
      offsets.removeValue(forKey: songID)
    } else {
      offsets[songID] = clamped
    }
    overlaySongOffsets = offsets
    render(at: player.elapsedTime)
    return overlayOffsetSnapshot()
  }
}
