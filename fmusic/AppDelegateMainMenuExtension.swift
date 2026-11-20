//
//  AppDelegateMainMenuExtension.swift
//  fmusic
//
//  Created by Maximilian Bauer on 08.08.25.
//  Copyright (c) 2025 Maximilian Bauer. All rights reserved.
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

import fmusicKit
@preconcurrency import UIKit

extension AppDelegate {
  func configureMainMenu() {
    let config = UIMainMenuSystem.Configuration()
    config.newScenePreference = .removed
    config.documentPreference = .removed
    config.printingPreference = .removed
    config.findingPreference = .included
    config.findingConfiguration.style = .search
    config.toolbarPreference = .included
    config.sidebarPreference = .included
    config.inspectorPreference = .included
    config.textFormattingPreference = .removed

    UIMainMenuSystem.shared.setBuildConfiguration(config) { builder in
      self.buildMainMenu(with: builder)
    }
  }

  public func rebuildMainMenu() {
    UIMenuSystem.main.setNeedsRebuild()
  }

  private func buildMainMenu(with builder: any UIMenuBuilder) {
    guard builder.system == .main else { return }

    #if targetEnvironment(macCatalyst) // ok
      // Add File menu
      let fileMenus = [
        UIMenu(options: .displayInline, children: [
          UIAction(
            title: L10n.tr("Open Player Window"),
            image: fmusicImage.openPlayerWindow.asUIImage,
            attributes: isMainOrMiniPlayerPlayerOpen ? .disabled : []
          ) { _ in
            self.openMainWindow()
          },
          UIKeyCommand(
            title: L10n.tr("Close Player Window"),
            image: fmusicImage.xmark.asUIImage,
            action: #selector(closePlayerWindow),
            input: "W",
            modifierFlags: .command,
            attributes: !isMainOrMiniPlayerPlayerOpen ? .disabled : []
          ),
        ]),
        UIMenu(options: .displayInline, children: [
          UIAction(
            title: L10n.tr("Switch Library/Mini Player"),
            image: fmusicImage.switchPlayerWindow.asUIImage
          ) { _ in
            if self.isShowingMiniPlayer {
              self.closeMiniPlayer()
              // mini player close will automatically (in scene disconnect) open Main again
            } else {
              self.closeMainWindow()
              self.showMiniPlayer()
            }
          },
        ]),
      ]
      builder.insertChild(fileMenus[1], atStartOfMenu: .file)
      builder.insertChild(fileMenus[0], atStartOfMenu: .file)
      let openSettingsMenu = UIMenu(options: .displayInline, children: [
        UIKeyCommand(
          title: L10n.tr("Settings…"),
          image: fmusicImage.settings.asUIImage,
          action: #selector(showSettings),
          input: ",",
          modifierFlags: .command
        ),
      ])
      builder.insertSibling(openSettingsMenu, afterMenu: .about)
    #endif

    // Add media controls
    builder.insertSibling(
      UIMenu(title: L10n.tr("Controls"), children: buildControlsMenu()),
      afterMenu: .view
    )

    builder.insertChild(UIMenu(options: .displayInline, children: [
      UIAction(title: L10n.tr("Report an issue on GitHub")) { _ in
        if let url = URL(string: "https://github.com/lemonevo/fmusic/issues") {
          UIApplication.shared.open(url)
        }
      },
    ]), atStartOfMenu: .help)
  }

  @objc
  private func keyCommandPause() {
    player.pause()
  }

  @objc
  private func keyCommandPlay() {
    player.play()
  }

  @objc
  private func keyCommandStop() {
    player.stop()
  }

  @objc
  private func keyCommandNext() {
    player.playNext()
  }

  @objc
  private func keyCommandPrevious() {
    player.playPreviousOrReplay()
  }

  @objc
  private func keyCommandSkipForward() {
    player.skipForward(interval: player.skipForwardInterval)
  }

  @objc
  private func keyCommandSkipBackward() {
    player.skipBackward(interval: player.skipBackwardInterval)
  }

  @objc
  private func keyCommandGoToCurrent() {
    let playable = player.currentlyPlaying
    guard let album = playable?.asSong?.album, let account = playable?.account else { return }
    appDelegate.userStatistics.usedAction(.alertGoToAlbum)
    let albumDetailVC = AppStoryboard.Main.segueToAlbumDetail(
      account: account,
      album: album,
      songToScrollTo: playable?.asSong
    )
    displayInLibraryTab(vc: albumDetailVC)
  }

  @objc
  private func keyCommandShuffleOn() {
    guard !player.isShuffle else { return }
    player.toggleShuffle()
  }

  @objc
  private func keyCommandShuffleOff() {
    guard player.isShuffle else { return }
    player.toggleShuffle()
  }

  private func buildControlsMenu() -> [UIMenuElement] {
    let isPlaying = player.isPlaying
    let isShuffle = player.isShuffle
    let isSkipAvailable = isPlaying && player.isSkipAvailable
    let hasAlbum = player.currentlyPlaying?.asSong?.album != nil

    let section1 = [
      UIKeyCommand(
        title: isPlaying ? (player.isStopInsteadOfPause ? L10n.tr("Stop") : L10n.tr("Pause")) : L10n
          .tr("Play"),
        image: isPlaying ? (player.isStopInsteadOfPause ? .stop : .pause) : .play,
        action: isPlaying ? #selector(keyCommandPause) : #selector(keyCommandPlay),
        input: " "
      ),
      UIKeyCommand(
        title: (isPlaying && player.isStopInsteadOfPause) ? L10n.tr("Stop Player") : L10n
          .tr("Stop"),
        image: .stop,
        action: #selector(keyCommandStop),
        input: ".",
        modifierFlags: .command,
        attributes: []
      ),
      UIKeyCommand(
        title: L10n.tr("Next Track"),
        image: .forwardMenu,
        action: #selector(keyCommandNext),
        input: UIKeyCommand.inputRightArrow,
        modifierFlags: .command,
        attributes: []
      ),
      UIKeyCommand(
        title: L10n.tr("Previous Track"),
        image: .backwardMenu,
        action: #selector(keyCommandPrevious),
        input: UIKeyCommand.inputLeftArrow,
        modifierFlags: .command,
        attributes: []
      ),
      UIKeyCommand(
        title: L10n.tr("Skip Forward: %@ sec.", String(Int(player.skipForwardInterval))),
        image: player.skipForwardIcon,
        action: #selector(keyCommandSkipForward),
        input: UIKeyCommand.inputRightArrow,
        modifierFlags: [.shift, .command],
        attributes: isSkipAvailable ? [] : [.disabled]
      ),
      UIKeyCommand(
        title: L10n.tr("Skip Backward: %@ sec.", String(Int(player.skipBackwardInterval))),
        image: player.skipBackwardIcon,
        action: #selector(keyCommandSkipBackward),
        input: UIKeyCommand.inputLeftArrow,
        modifierFlags: [.shift, .command],
        attributes: isSkipAvailable ? [] : [.disabled]
      ),
      UIKeyCommand(
        title: L10n.tr("Go to Current Song"),
        image: .currentSongMenu,
        action: #selector(keyCommandGoToCurrent),
        input: "L",
        modifierFlags: [.command],
        attributes: hasAlbum ? [] : [.disabled]
      ),
    ]

    var section2 = [
      UIMenu(
        title: L10n.tr("Playback Rate"),
        image: .playbackRate,
        children: PlaybackRate.allCases.map { rate in
          UIAction(
            title: rate.description,
            state: rate == self.player.playbackRate ? .on : .off
          ) { _ in
            self.player.setPlaybackRate(rate)
          }
        }
      ),
    ]

    if appDelegate.player.playerMode == .music {
      let repeatMenu = UIMenu(
        title: L10n.tr("Repeat"),
        image: .repeatMenu,
        children: RepeatMode.allCases.map { mode in
          UIAction(
            title: L10n.tr(mode.description),
            state: mode == self.player.repeatMode ? .on : .off
          ) { _ in
            self.player.setRepeatMode(mode)
          }
        }
      )
      section2.insert(repeatMenu, at: 0)
    }
    if appDelegate.player.playerMode == .music,
       appDelegate.storage.settings.user.isPlayerShuffleButtonEnabled {
      let shuffleMenu = UIMenu(title: L10n.tr("Shuffle"), image: .shuffleMenu, children: [
        UIAction(title: L10n.tr("On"), state: isShuffle ? .on : .off) { [weak self] _ in
          self?.keyCommandShuffleOn()
        },
        UIAction(title: L10n.tr("Off"), state: !isShuffle ? .on : .off) { [weak self] _ in
          self?.keyCommandShuffleOff()
        },
      ])
      section2.insert(shuffleMenu, at: 0)
    }

    let section3 = [
      createSleepTimerMenu(refreshCB: {
        self.rebuildMainMenu()
      }),
    ]

    let sections: [[UIMenuElement]] = [section1, section2, section3]

    return sections.reduce([]) { result, section in
      result + [UIMenu(options: .displayInline)] + section
    }
  }

  @objc
  func closePlayerWindow(sender: Any) {
    if isMainWindowOpen {
      closeMainWindow()
    } else if isShowingMiniPlayer {
      closeMiniPlayer()
    }
    rebuildMainMenu()
  }

  /// Settings open in their own window scene (like Apple Music's Preferences):
  /// a separate window smaller than the main window. Re-open raises the existing
  /// one instead of stacking duplicates.
  var settingsSceneSession: UISceneSession? {
    UIApplication.shared.connectedScenes
      .first(where: { $0.delegate is SettingsSceneDelegate })?
      .session
  }

  var isShowingSettings: Bool {
    settingsSceneSession != nil
  }

  var settingsSceneDelegate: SettingsSceneDelegate? {
    UIApplication.shared.connectedScenes
      .compactMap { $0.delegate as? SettingsSceneDelegate }
      .first
  }

  /// The window of the settings scene, if it is open. Used to present follow-up
  /// UI (e.g. the sync progress) on top of the settings window rather than the
  /// main window, which the settings window would cover.
  var settingsWindow: UIWindow? { settingsSceneDelegate?.window }

  @objc
  func showSettings(sender: Any) {
    #if targetEnvironment(macCatalyst)
      // Raise the existing settings window if one is already open; otherwise
      // create a fresh scene. Closing destroys the scene, so this never leaves
      // an empty window behind.
      if let existing = settingsSceneSession {
        UIApplication.shared.requestSceneSessionActivation(
          existing,
          userActivity: nil,
          options: nil,
          errorHandler: nil
        )
        MacWindowHelper.activateApplication()
        return
      }
      let settingsActivity = NSUserActivity(activityType: settingsWindowActivityType)
      UIApplication.shared.requestSceneSessionActivation(
        nil,
        userActivity: settingsActivity,
        options: nil,
        errorHandler: nil
      )
      // A freshly created scene also needs the app brought forward.
      MacWindowHelper.activateApplication()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
        MacWindowHelper.activateApplication()
      }
    #endif
  }

  var isShowingMiniPlayer: Bool {
    UIApplication.shared.connectedScenes.contains(where: { $0.session == miniPlayerSceneSession })
  }

  @objc
  func showMiniPlayer(sender: Any? = nil) {
    let miniPlayerActivity = NSUserActivity(activityType: miniPlayerWindowActivityType)
    UIApplication.shared.requestSceneSessionActivation(
      miniPlayerSceneSession,
      userActivity: miniPlayerActivity,
      options: nil,
      errorHandler: nil
    )
  }

  func closeMiniPlayer() {
    UIApplication.shared.connectedScenes
      .filter { $0.session == miniPlayerSceneSession }
      .forEach {
        let options = UIWindowSceneDestructionRequestOptions()
        options.windowDismissalAnimation = .standard
        UIApplication.shared.requestSceneSessionDestruction(
          $0.session,
          options: options,
          errorHandler: nil
        )
      }
  }

  func updateMiniPlayerAlwaysOnTop() {
    #if targetEnvironment(macCatalyst)
      MacWindowHelper.setAlwaysOnTop(
        storage.settings.user.isMiniPlayerAlwaysOnTop,
        sceneTitle: MiniPlayerSceneDelegate.sceneTitle
      )
    #endif
  }

  func updateLyricsOverlays() {
    #if targetEnvironment(macCatalyst)
      lyricsOverlayManager.start()
    #endif
  }

  func createSleepTimerMenu(refreshCB: VoidFunctionCallback?) -> UIMenuElement {
    if let timer = sleepTimer {
      let actionTitle = L10n.tr("Turn Off (Pause at: %@)", timer.fireDate.asShortHrMinString)
      let deactivate = UIAction(title: actionTitle, image: nil, handler: { _ in
        self.sleepTimer?.invalidate()
        self.sleepTimer = nil
        refreshCB?()
      })
      return UIMenu(
        title: L10n.tr("Sleep Timer"),
        subtitle: L10n.tr("Pause at: %@", timer.fireDate.asShortHrMinString),
        image: .sleep,
        children: [deactivate]
      )
    } else if player.isShouldPauseAfterFinishedPlaying {
      let actionTitle = L10n.tr(
        "Turn Off (Pause at end of %@)",
        player.playerMode.playableName
      )
      let deactivate = UIAction(title: actionTitle, image: nil, handler: { _ in
        self.player.isShouldPauseAfterFinishedPlaying = false
        refreshCB?()
      })
      return UIMenu(
        title: L10n.tr("Sleep Timer"),
        subtitle: L10n.tr("Pause at end of %@", player.playerMode.playableName),
        children: [deactivate]
      )
    } else {
      let endOfTrack = UIAction(
        title: L10n.tr("End of Song"),
        image: nil,
        handler: { _ in
          self.player.isShouldPauseAfterFinishedPlaying = true
          refreshCB?()
        }
      )
      let sleep5 = UIAction(title: L10n.tr("5 Minutes"), image: nil, handler: { _ in
        self.activateSleepTimer(timeInterval: TimeInterval(5 * 60))
        refreshCB?()
      })
      let sleep10 = UIAction(title: L10n.tr("10 Minutes"), image: nil, handler: { _ in
        self.activateSleepTimer(timeInterval: TimeInterval(10 * 60))
        refreshCB?()
      })
      let sleep15 = UIAction(title: L10n.tr("15 Minutes"), image: nil, handler: { _ in
        self.activateSleepTimer(timeInterval: TimeInterval(15 * 60))
        refreshCB?()
      })
      let sleep30 = UIAction(title: L10n.tr("30 Minutes"), image: nil, handler: { _ in
        self.activateSleepTimer(timeInterval: TimeInterval(30 * 60))
        refreshCB?()
      })
      let sleep45 = UIAction(title: L10n.tr("45 Minutes"), image: nil, handler: { _ in
        self.activateSleepTimer(timeInterval: TimeInterval(45 * 60))
        refreshCB?()
      })
      let sleep60 = UIAction(title: L10n.tr("1 Hour"), image: nil, handler: { _ in
        self.activateSleepTimer(timeInterval: TimeInterval(60 * 60))
        refreshCB?()
      })
      let sleep120 = UIAction(title: L10n.tr("2 Hours"), image: nil, handler: { _ in
        self.activateSleepTimer(timeInterval: TimeInterval(2 * 60 * 60))
        refreshCB?()
      })
      let sleep240 = UIAction(title: L10n.tr("4 Hours"), image: nil, handler: { _ in
        self.activateSleepTimer(timeInterval: TimeInterval(4 * 60 * 60))
        refreshCB?()
      })
      return UIMenu(
        title: L10n.tr("Sleep Timer"),
        image: .sleep,
        children: [
          endOfTrack,
          sleep5,
          sleep10,
          sleep15,
          sleep30,
          sleep45,
          sleep60,
          sleep120,
          sleep240,
        ]
      )
    }
  }

  private func activateSleepTimer(timeInterval: TimeInterval) {
    appDelegate.sleepTimer?.invalidate()
    appDelegate.sleepTimer = Timer
      .scheduledTimer(withTimeInterval: timeInterval, repeats: false) { _ in
        Task { @MainActor in
          self.appDelegate.player.pause()
          self.appDelegate.eventLogger.info(
            topic: "Sleep Timer",
            message: L10n.tr("Sleep Timer paused playback.")
          )
          self.appDelegate.sleepTimer?.invalidate()
          self.appDelegate.sleepTimer = nil
        }
      }
  }

  var isMainOrMiniPlayerPlayerOpen: Bool {
    isMainWindowOpen || isShowingMiniPlayer
  }

  var isMainWindowOpen: Bool {
    !UIApplication.shared.connectedScenes
      .flatMap { ($0 as? UIWindowScene)?.windows ?? [] }
      .filter { ($0.rootViewController as? MainSceneHostingViewController) != nil }
      .isEmpty
  }

  func closeMainWindow() {
    // Close all main sessions (this might be more than one with multiple tabs open)
    UIApplication.shared.connectedScenes
      .flatMap { ($0 as? UIWindowScene)?.windows ?? [] }
      .filter { ($0.rootViewController as? MainSceneHostingViewController) != nil }
      .compactMap { $0.windowScene?.session }
      .forEach {
        let options = UIWindowSceneDestructionRequestOptions()
        options.windowDismissalAnimation = .standard
        UIApplication.shared.requestSceneSessionDestruction(
          $0,
          options: options,
          errorHandler: nil
        )
      }
  }

  func openMainWindow() {
    // If a main window already exists, bring its existing scene to the front
    // instead of requesting a brand-new one (passing a nil session to
    // requestSceneSessionActivation makes Catalyst create a new window every
    // time). Only create a window when none is open.
    if isMainWindowOpen,
       let mainSession = AppDelegate.mainSceneDelegate?.window?.windowScene?.session {
      #if targetEnvironment(macCatalyst)
        // The overlay's controls live on a nonactivating panel, so clicking them
        // never activates fmusic; activate the app explicitly, otherwise the
        // window only rises within fmusic and stays behind the frontmost app.
        MacWindowHelper.activateApplication()
      #endif
      UIApplication.shared.requestSceneSessionActivation(
        mainSession,
        userActivity: nil,
        options: nil,
        errorHandler: nil
      )
      return
    }
    let defaultActivity = NSUserActivity(activityType: defaultWindowActivityType)
    UIApplication.shared.requestSceneSessionActivation(
      nil,
      userActivity: defaultActivity,
      options: nil,
      errorHandler: nil
    )
    #if targetEnvironment(macCatalyst)
      // A freshly created scene also needs the app brought forward.
      MacWindowHelper.activateApplication()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
        MacWindowHelper.activateApplication()
      }
    #endif
  }
}

// MARK: - AppDelegate + MusicPlayable

extension AppDelegate: MusicPlayable {
  func didStartPlaying() {
    rebuildMainMenu()
  }

  func didPause() {
    rebuildMainMenu()
  }

  func didStopPlaying() {
    rebuildMainMenu()
  }

  func didShuffleChange() {
    rebuildMainMenu()
  }

  func didRepeatChange() {
    rebuildMainMenu()
  }

  func didPlaybackRateChange() {
    rebuildMainMenu()
  }

  func didStartPlayingFromBeginning() {}
  func didElapsedTimeChange() {}
  func didPlaylistChange() {}
  func didArtworkChange() {}
}
