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
  private(set) var lyricsOverlay: LyricsOverlayController?
  private(set) var miniPlayerWindowController: MiniPlayerWindowController?

  /// Handles `fmusic://x-callback-url/...` URLs (script / Stream Deck / Shortcuts automation).
  private(set) lazy var xCallbackManager = XCallbackManager()

  /// URLs that arrived before the X-Callback actions were registered at launch.
  private var pendingXCallbackURLs = [URL]()

  /// One-shot timer behind Playback ▸ Sleep Timer. Kept on the delegate so it keeps
  /// running while the library window is closed and the app stays in the background.
  private var sleepTimer: Timer?
  private(set) var sleepTimerMinutes: Int?

  var fmusic: FmusicKit { FmusicKit.shared }
  var storage: PersistentStorage { FmusicKit.shared.storage }
  var player: PlayerFacade { FmusicKit.shared.player }

  // MARK: - Lifecycle

  func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    true
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    MacTheme.applyAppearanceMode()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(appearanceChanged),
      name: .macAppearanceChanged,
      object: nil
    )
    AppIconManager.applySavedIcon()
    NSApp.mainMenu = MainMenuBuilder.build()

    bootstrapCore()

    // Register `fmusic://x-callback-url/...` actions before the window appears so a URL that
    // launched the app (or arrives while the app is running) is handled immediately.
    xCallbackManager.registerXCallbackURLs()
    flushPendingXCallbackURLs()

    let controller = MainWindowController()
    mainWindowController = controller
    controller.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)

    // Fresh install or last account logged out: ask for an account (otherwise the
    // library window is empty and the macOS app has no other way to sign in).
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(accountActiveChanged),
      name: .accountActiveChanged,
      object: nil
    )
    LoginWindowController.presentLoginIfNeeded()

    // Dev hooks for smoke tests from the command line.
    let arguments = ProcessInfo.processInfo.arguments
    if arguments.contains("--play") {
      player.play()
    }
    if arguments.contains("--settings") {
      showSettings(nil)
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // A music player keeps running when its library window is closed (Apple Music behaviour);
    // playback and the lyrics overlays continue.
    false
  }

  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  )
    -> Bool {
    if !flag {
      showMainWindow(nil)
    }
    return true
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    handleIncomingURLs(urls)
  }

  // MARK: - X-Callback-URLs

  /// Routes the URLs AppKit hands to the app: audio files are imported into the library,
  /// `fmusic://x-callback-url/...` URLs are dispatched to the `XCallbackManager`.
  func handleIncomingURLs(_ urls: [URL]) {
    var fileURLs = [URL]()
    var didHandleXCallback = false
    for url in urls {
      if url.isFileURL {
        fileURLs.append(url)
      } else if handleIncomingXCallbackURL(url) {
        didHandleXCallback = true
      }
    }
    if didHandleXCallback {
      // The URL came from an automation client; make sure the user sees the app react.
      NSApp.activate(ignoringOtherApps: true)
    }
    openAudioFiles(fileURLs)
  }

  /// Handles a single `fmusic://` URL. Exposed for menu items / AppleScript hooks and used by
  /// `application(_:open:)` for URLs sent by the system.
  ///
  /// - Returns: `true` when the URL was a `fmusic://x-callback-url/...` URL handled by the
  ///   registered actions.
  @discardableResult
  func handleIncomingXCallbackURL(_ url: URL) -> Bool {
    guard !url.isFileURL, url.scheme?.lowercased() == "fmusic" else { return false }
    guard url.host?.lowercased() == "x-callback-url" else {
      // Other `fmusic://` URLs are not handled (yet), but they are still ours.
      return false
    }
    guard xCallbackManager.isRegistered else {
      pendingXCallbackURLs.append(url)
      return true
    }
    return xCallbackManager.handleIncoming(url: url)
  }

  private func flushPendingXCallbackURLs() {
    guard !pendingXCallbackURLs.isEmpty else { return }
    let urls = pendingXCallbackURLs
    pendingXCallbackURLs.removeAll()
    for url in urls {
      _ = xCallbackManager.handleIncoming(url: url)
    }
  }

  /// Shows the list of supported X-Callback-URL actions (helper for a future "Help ▸ X-Callback
  /// URLs" menu item; the actions are documented in the Catalyst settings page).
  @objc
  func showXCallbackDocumentation(_ sender: Any?) {
    let alert = NSAlert()
    alert.messageText = L10n.tr("X-Callback-URLs")
    alert.informativeText = xCallbackManager.documentationText
    alert.addButton(withTitle: L10n.tr("OK"))
    alert.runModal()
  }

  // MARK: - Bootstrap

  @objc
  private func lyricsSettingsChanged() {
    lyricsOverlay?.settingsChanged()
  }

  func applicationWillTerminate(_ notification: Notification) {
    sleepTimer?.invalidate()
    sleepTimer = nil
    lyricsOverlay?.stop()
    lyricsOverlay = nil
  }

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

    let overlay = LyricsOverlayController()
    overlay.onOpenMainWindow = { [weak self] in self?.showMainWindow(nil) }
    overlay.start()
    lyricsOverlay = overlay
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(lyricsSettingsChanged),
      name: .macPlaybackSettingsChanged,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(lyricsSettingsChanged),
      name: .macThemeColorChanged,
      object: nil
    )
  }

  @objc
  func toggleDesktopLyrics(_ sender: Any?) {
    SettingsStore.updateUser { $0.isDesktopLyricsEnabled.toggle() }
    NotificationCenter.default.post(name: .macPlaybackSettingsChanged, object: nil)
  }

  @objc
  private func appearanceChanged() {
    for window in NSApp.windows {
      // Transparent panels (desktop lyrics, mini player, Now Playing overlay) keep
      // their own background; painting them here turns them into opaque rectangles.
      guard window.isOpaque else { continue }
      window.backgroundColor = MacTheme.contentBackgroundColor
      window.contentView?.needsDisplay = true
      window.contentView?.needsLayout = true
    }
  }

  @objc
  func toggleSidebar(_ sender: Any?) {
    mainWindowController?.mainViewController?.toggleSidebar()
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

  // MARK: - Mini player

  /// The mini player window is open (visible) — used for the Window menu check mark.
  var isMiniPlayerVisible: Bool {
    miniPlayerWindowController?.window?.isVisible ?? false
  }

  /// Opens (or brings to the front) the small floating player window without closing
  /// or replacing the library window. Playback keeps running if the library window is
  /// closed afterwards, because the app does not terminate after the last window.
  @objc
  func showMiniPlayer(_ sender: Any?) {
    let controller: MiniPlayerWindowController
    if let existing = miniPlayerWindowController {
      controller = existing
    } else {
      controller = MiniPlayerWindowController()
      controller.onExpand = { [weak self] in self?.expandMiniPlayerToMainWindow() }
      miniPlayerWindowController = controller
    }
    controller.applyAlwaysOnTopSetting()
    controller.showWindow(sender)
    NSApp.activate(ignoringOtherApps: true)
    controller.window?.makeKeyAndOrderFront(sender)
  }

  /// Closes the mini player (the app keeps running, like closing the library window).
  @objc
  func closeMiniPlayer(_ sender: Any?) {
    miniPlayerWindowController?.close()
  }

  /// "Expand" inside the mini player: bring the library window back and close the
  /// compact window (Apple Music's switch between library and mini player).
  func expandMiniPlayerToMainWindow() {
    showMainWindow(nil)
    miniPlayerWindowController?.close()
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
  private func accountActiveChanged() {
    LoginWindowController.presentLoginIfNeeded()
  }

  @objc
  func addAccount(_ sender: Any?) {
    LoginWindowController.presentLogin()
  }

  @objc
  func showLyricsPage(_ sender: Any?) {
    LyricsPageWindowController.present()
  }

  @objc
  func showNowPlaying(_ sender: Any?) {
    showMainWindow(nil)
    mainWindowController?.mainViewController?.presentNowPlayingOverlay()
  }

  @objc
  func showQueue(_ sender: Any?) {
    PlayerPageWindowController.presentQueue()
  }

  /// ⌘1…⌘9: jump to the corresponding sidebar entry.
  @objc
  func selectSidebarSlot(_ sender: NSMenuItem) {
    let items = SidebarItem.allCases
    guard items.indices.contains(sender.tag) else { return }
    showMainWindow(nil)
    mainWindowController?.mainViewController?.select(item: items[sender.tag])
  }

  @objc
  func focusSearch(_ sender: Any?) {
    showMainWindow(sender)
    (mainWindowController?.contentViewController as? MainViewController)?.select(item: .search)
    (mainWindowController?.contentViewController as? MainViewController)?.focusToolbarSearch()
  }

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

  // MARK: - Sleep timer

  /// Fire date of the running sleep timer, or nil when no minute-based timer is armed.
  var sleepTimerFireDate: Date? { sleepTimer?.fireDate }

  /// Arms the countdown sleep timer. The timer lives on the app delegate, so it also
  /// fires when the library window is closed; the next callback pauses playback.
  func startSleepTimer(minutes: Int) {
    guard minutes > 0 else { return }
    stopSleepTimer()
    // Radio semantics: a countdown replaces "end of song" and vice versa.
    player.isShouldPauseAfterFinishedPlaying = false
    let timer = Timer(
      timeInterval: TimeInterval(minutes * 60),
      target: self,
      selector: #selector(sleepTimerDidFire(_:)),
      userInfo: nil,
      repeats: false
    )
    RunLoop.main.add(timer, forMode: .common)
    sleepTimer = timer
    sleepTimerMinutes = minutes
    MainMenuBuilder.refreshSleepTimerMenu()
  }

  /// Playback menu action: `sender.tag` is the number of minutes.
  @objc
  func activateSleepTimer(_ sender: NSMenuItem) {
    startSleepTimer(minutes: sender.tag)
  }

  /// Pause when the current song ends (`player.isShouldPauseAfterFinishedPlaying`).
  @objc
  func setSleepTimerToEndOfSong(_ sender: Any?) {
    stopSleepTimer()
    player.isShouldPauseAfterFinishedPlaying = true
    MainMenuBuilder.refreshSleepTimerMenu()
  }

  /// "Off" in the sleep timer menu: drops both the countdown and end-of-song pause.
  @objc
  func turnOffSleepTimer(_ sender: Any?) {
    stopSleepTimer()
    player.isShouldPauseAfterFinishedPlaying = false
    MainMenuBuilder.refreshSleepTimerMenu()
  }

  private func stopSleepTimer() {
    sleepTimer?.invalidate()
    sleepTimer = nil
    sleepTimerMinutes = nil
  }

  @objc
  private func sleepTimerDidFire(_ timer: Timer) {
    stopSleepTimer()
    player.pause()
    fmusic.eventLogger.info(
      topic: "Sleep Timer",
      message: L10n.tr("Sleep Timer paused playback."),
      displayPopup: false
    )
    MainMenuBuilder.refreshSleepTimerMenu()
  }
}

// MARK: - MenuValidation

extension AppDelegate: NSMenuItemValidation {
  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    // ⌘←/⌘→ etc. belong to the text system while a field editor is active.
    if NSApp.keyWindow?.firstResponder is NSTextView {
      let playbackActions: Set<Selector> = [
        #selector(playNext(_:)), #selector(playPrevious(_:)),
        #selector(toggleShuffle(_:)), #selector(cycleRepeatMode(_:)),
      ]
      if let action = menuItem.action, playbackActions.contains(action) {
        return false
      }
    }
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
    case #selector(showMiniPlayer(_:)):
      menuItem.state = isMiniPlayerVisible ? .on : .off
      return true
    default:
      return true
    }
  }
}
