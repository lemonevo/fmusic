//
//  LyricsOverlayManager.swift
//  fmusic
//
//  Feeds the desktop lyrics panel and the menu bar item from the player clock.
//

#if targetEnvironment(macCatalyst)

  import AppKit
  import CoreMedia
  import QuartzCore
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
    private var isLoadingLyrics = false
    private var isRegistered = false
    private var lastDesktopRenderTime: CFTimeInterval = 0

    init(player: PlayerFacade, storage: PersistentStorage) {
      self.player = player
      self.storage = storage
      super.init()
    }

    func start() {
      if !isRegistered {
        isRegistered = true
        player.addNotifier(notifier: self)
      }
      refreshFromSettings()
    }

    // MARK: Settings

    func refreshFromSettings() {
      let user = storage.settings.user
      let isAnyFeatureEnabled = user.isDesktopLyricsEnabled || user.isMenuBarLyricsEnabled

      if user.isDesktopLyricsEnabled {
        if desktopPanel == nil {
          desktopPanel = makeDesktopPanel()
        }
        if let panel = desktopPanel {
          panel.setPointSize(user.desktopLyricsFontSize.pointSize)
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
      loadLyricsIfNeeded()
      render(at: player.elapsedTime)
    }

    func didStartPlaying() {
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
      resetPlaybackState()
    }

    func didPause() {}

    func didLyricsTimeChange(time: CMTime) {
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
      storage.settings.user.isDesktopLyricsEnabled ||
        storage.settings.user.isMenuBarLyricsEnabled
    }

    private func resetPlaybackState() {
      tracker.setLyrics(nil)
      loadedSongID = nil
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
      if loadedSongID == songID, tracker.hasLyrics || isLoadingLyrics {
        return
      }
      loadedSongID = songID
      tracker.setLyrics(nil)

      guard let account = song.account,
            let lyricsRelFilePath = song.lyricsRelFilePath
      else {
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
        guard let lyricsList = try? await self.appDelegate.getMeta(account.info)
          .librarySyncer.parseLyrics(relFilePath: lyricsRelFilePath),
          self.loadedSongID == songID,
          let structuredLyrics = lyricsList.getFirstSyncedLyricsOrUnsyncedAsDefault()
        else { return }
        self.tracker.setLyrics(structuredLyrics)
        guard self.player.currentlyPlaying?.id == songID else { return }
        self.render(at: self.player.elapsedTime)
      }
    }

    // MARK: Rendering

    private func render(at seconds: Double) {
      guard isAnyFeatureEnabled else { return }
      let snapshot = tracker.snapshot(
        at: seconds,
        userOffsetMs: storage.settings.user.lyricsOffsetMs
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
            storage.settings.user.isDesktopLyricsEnabled
      else { return }
      guard let playable = player.currentlyPlaying else {
        desktopPanel.hide()
        return
      }

      let now = CACurrentMediaTime()
      guard now - lastDesktopRenderTime >= 1.0 / 30.0 else { return }
      lastDesktopRenderTime = now

      if !desktopPanel.isVisible {
        desktopPanel.show()
      }

      if let snapshot {
        desktopPanel.update(content: DesktopLyricsContent(
          currentText: snapshot.currentText,
          nextText: snapshot.nextText,
          syllables: snapshot.syllables,
          syllableProgress: snapshot.syllableProgress
        ))
      } else {
        desktopPanel.update(content: DesktopLyricsContent(
          currentText: playable.title,
          nextText: playable.creatorName.isEmpty ? nil : playable.creatorName,
          syllables: [],
          syllableProgress: []
        ))
      }
    }

    // MARK: Controllers

    private func makeDesktopPanel() -> DesktopLyricsPanelController? {
      DesktopLyricsPanelController.make()
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
