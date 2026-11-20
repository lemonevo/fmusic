//
//  LyricsOverlayManager.swift
//  fmusic
//
//  Feeds the desktop lyrics panel and the menu bar item from the player clock.
//

#if targetEnvironment(macCatalyst)

  import AppKit
  import CoreMedia
  import fmusicKit

  // MARK: - LyricsOverlayManager

  @MainActor
  final class LyricsOverlayManager: NSObject, MusicPlayable {
    private let player: PlayerFacade
    private let storage: PersistentStorage
    private let tracker = LyricsLineTracker()

    private var desktopPanel: DesktopLyricsPanelController?
    private var menuBarController: MenuBarLyricsController?
    private var loadedSongID: String?
    // Set once the lyrics lookup for the current song returned, so settings changes do not
    // re-read the same missing or empty lyrics file on every refresh.
    private var resolvedSongID: String?
    private var isLoadingLyrics = false
    private var isRegistered = false
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

    init(player: PlayerFacade, storage: PersistentStorage) {
      self.player = player
      self.storage = storage
      super.init()
    }

    func start() {
      if !isRegistered {
        isRegistered = true
        player.addNotifier(notifier: self)
        appDelegate.notificationHandler.register(
          self,
          selector: #selector(onlineLyricsDidUpdate(_:)),
          name: .onlineLyricsDidUpdate,
          object: nil
        )
        if !isLyricsOffsetObserverRegistered {
          isLyricsOffsetObserverRegistered = true
          appDelegate.notificationHandler.register(
            self,
            selector: #selector(lyricsOffsetDidChange(_:)),
            name: .lyricsOffsetChanged,
            object: nil
          )
        }
      }
      refreshFromSettings()
    }

    // MARK: Settings

    private func refreshFromSettings() {
      let user = storage.settings.user
      let isAnyFeatureEnabled = user.isDesktopLyricsEnabled || user.isMenuBarLyricsEnabled
      isFeatureEnabled = isAnyFeatureEnabled
      isDesktopLyricsShown = user.isDesktopLyricsEnabled
      isDesktopNextLineShown = user.isDesktopLyricsNextLineShown
      cachedGlobalOffsetMs = user.lyricsOffsetMs

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

      guard isAnyFeatureEnabled else { return }
      loadLyricsIfNeeded()
      render(at: player.elapsedTime)
    }

    // MARK: MusicPlayable

    func didStartPlayingFromBeginning() {
      desktopPanel?.setPlaying(true)
      loadLyricsIfNeeded()
      render(at: player.elapsedTime)
    }

    func didStartPlaying() {
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
      desktopPanel?.setPlaying(false)
      resetPlaybackState()
    }

    func didPause() {
      desktopPanel?.setPlaying(false)
    }

    func didLyricsTimeChange(time: CMTime) {
      guard isFeatureEnabled else { return }
      render(at: time.seconds)
    }

    func didElapsedTimeChange() {}

    func didPlaylistChange() {
      loadLyricsIfNeeded()
      render(at: player.elapsedTime)
    }

    func didArtworkChange() {}
    func didShuffleChange() {}
    func didRepeatChange() {}
    func didPlaybackRateChange() {}

    // MARK: Lyrics loading

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
        guard let lyricsList = try? await self.appDelegate.getMeta(account.info)
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

    // MARK: Rendering

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

    // MARK: Controllers

    private func makeDesktopPanel() -> DesktopLyricsPanelController? {
      guard let panel = DesktopLyricsPanelController.make() else { return nil }
      panel.onOpenMainWindow = { [weak self] in
        self?.appDelegate.openMainWindow()
      }
      panel.onHideDesktopLyrics = { [weak self] in
        guard let self else { return }
        storage.settings.user.isDesktopLyricsEnabled = false
        appDelegate.updateLyricsOverlays()
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
        appDelegate.updateLyricsOverlays()
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

    // MARK: Overlay lyrics offset

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

    private func makeMenuBarController() -> MenuBarLyricsController? {
      guard let controller = MenuBarLyricsController.make() else { return nil }
      controller.onOpenApp = { [weak self] in
        self?.appDelegate.openMainWindow()
      }
      return controller
    }
  }

#endif
