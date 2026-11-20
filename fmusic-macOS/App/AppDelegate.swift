//
//  AppDelegate.swift
//  fmusic-macOS
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
import UniformTypeIdentifiers

/// Pure-AppKit application delegate. Owns the library window, the settings window and the
/// app level bootstrap of the shared FmusicKit core.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  static var sharedAppDelegate: AppDelegate? { NSApp.delegate as? AppDelegate }

  private(set) var mainWindowController: MainWindowController?
  private var settingsWindowController: SettingsWindowController?

  var fmusic: FmusicKit { FmusicKit.shared }
  var storage: PersistentStorage { FmusicKit.shared.storage }
  var player: PlayerFacade { FmusicKit.shared.player }

  // MARK: - Lifecycle

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.mainMenu = MainMenuBuilder.build()

    bootstrapCore()

    let controller = MainWindowController()
    mainWindowController = controller
    controller.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)

    // Dev hook: `open fmusic.app --args --play` resumes playback for smoke tests.
    if ProcessInfo.processInfo.arguments.contains("--play") {
      player.play()
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    openAudioFiles(urls)
  }

  // MARK: - Bootstrap

  private func bootstrapCore() {
    let storage = fmusic.storage
    storage.applyMultiAccountSettingsUpdateIfNeeded()
    fmusic.libraryUpdater.performAccountCleanUpIfNeccessaryInBackground()
    OpenedFileLibrary.shared.activateBookmarks()

    // Creating the player restores the queue, the audio engine and the now playing state.
    let player = self.player

    guard storage.settings.app.isLibrarySynced,
          storage.settings.accounts.active != nil else { return }

    fmusic.libraryUpdater.performSmallBlockingLibraryUpdatesIfNeeded()
    for accountInfo in storage.settings.accounts.allAccounts {
      fmusic.getMeta(accountInfo).startManagerForNormalOperation(player: player)
    }
    fmusic.userStatistics.sessionStarted()
  }

  // MARK: - Windows

  @objc
  func showSettings(_ sender: Any?) {
    if settingsWindowController == nil {
      settingsWindowController = SettingsWindowController()
    }
    guard let settingsWindow = settingsWindowController?.window else { return }
    if let mainWindow = mainWindowController?.window,
       settingsWindow.frame.isEmpty {
      settingsWindow.center()
    }
    settingsWindowController?.showWindow(sender)
    settingsWindow.makeKeyAndOrderFront(sender)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc
  func showMainWindow(_ sender: Any?) {
    if mainWindowController == nil {
      mainWindowController = MainWindowController()
    }
    mainWindowController?.showWindow(sender)
    mainWindowController?.window?.makeKeyAndOrderFront(sender)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc
  func closeMainWindow(_ sender: Any?) {
    mainWindowController?.close()
  }

  // MARK: - Files

  @objc
  func openAudioFile(_ sender: Any?) {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowedContentTypes = [.audio, .mp3, .mpeg4Audio, .wav, .aiff, .midi]
    panel.begin { [weak self] response in
      guard response == .OK else { return }
      self?.openAudioFiles(panel.urls)
    }
  }

  private func openAudioFiles(_ urls: [URL]) {
    let fileURLs = urls.filter(\.isFileURL)
    guard !fileURLs.isEmpty else { return }
    let storage = self.storage
    Task { @MainActor in
      let songs = await OpenedFileLibrary.shared.importFiles(
        fileURLs: fileURLs,
        storage: storage
      )
      guard !songs.isEmpty else {
        let name = fileURLs.first?.lastPathComponent ?? ""
        self.fmusic.eventLogger.report(
          topic: L10n.tr("Open File"),
          error: OpenedFileError.unreadableFile(name),
          displayPopup: true
        )
        return
      }
      self.player.play(context: PlayContext(name: L10n.tr("Opened Files"), playables: songs))
    }
  }

  // MARK: - Playback

  @objc
  func togglePlayPause(_ sender: Any?) {
    player.togglePlayPause()
  }

  @objc
  func playNext(_ sender: Any?) {
    player.playNext()
  }

  @objc
  func playPrevious(_ sender: Any?) {
    player.playPreviousOrReplay()
  }

  @objc
  func toggleShuffle(_ sender: Any?) {
    player.toggleShuffle()
  }

  @objc
  func cycleRepeatMode(_ sender: Any?) {
    player.setRepeatMode(player.repeatMode.nextMode)
  }

  @objc
  func adjustVolume(_ sender: NSMenuItem) {
    let delta: Float = sender.tag == 1 ? 0.05 : -0.05
    let player = FmusicKit.shared.player
    player.volume = min(max(player.volume + delta, 0), 1)
  }
}

// MARK: - MenuValidation

extension AppDelegate: NSMenuItemValidation {
  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    switch menuItem.action {
    case #selector(togglePlayPause(_:)):
      menuItem.title = player.isPlaying ? L10n.tr("Pause") : L10n.tr("Play")
      return true
    case #selector(toggleShuffle(_:)):
      menuItem.state = player.isShuffle ? .on : .off
      return true
    case #selector(cycleRepeatMode(_:)):
      switch player.repeatMode {
      case .off: menuItem.state = .off
      case .all: menuItem.state = .on
      case .single: menuItem.state = .mixed
      }
      return true
    default:
      return true
    }
  }
}
