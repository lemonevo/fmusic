//
//  AppDelegate.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 06.06.22.
//  Copyright (c) 2022 Maximilian Bauer. All rights reserved.
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

import AmperfyKit
import BackgroundTasks
import Intents
import MediaPlayer
import os.log
@preconcurrency import UIKit

let windowSettingsTitle = "Settings"
let windowMiniPlayerTitle = "MiniPlayer"

let settingsWindowActivityType = "amperfy.settings"
let miniPlayerWindowActivityType = "amperfy.miniplayer"
let defaultWindowActivityType = "amperfy.main"

// MARK: - AppDelegate

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
  static let name = "Amperfy"
  static var version: String {
    (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
  }

  static var buildNumber: String {
    (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? ""
  }

  static let maxPlayablesDownloadsToAddAtOnceWithoutWarning = 200

  var window: UIWindow?
  var focusedWindowTitle: String?
  var accountSwitcherDismissHandler: (() -> ())?
  var audioOutputPickerDismissHandler: (() -> ())?
  private var lastWebDAVIncrementalScanAttempt: Date?
  private static let webDAVIncrementalScanMinimumInterval: TimeInterval = 15

  lazy var player: PlayerFacade = {
    UIApplication.shared.beginReceivingRemoteControlEvents()
    return AmperKit.shared.player
  }()

  public lazy var log = {
    AmperKit.shared.log
  }()

  public lazy var storage = {
    AmperKit.shared.storage
  }()

  public var networkMonitor: NetworkMonitorFacade { AmperKit.shared.networkMonitor }

  public lazy var eventLogger: EventLogger = {
    AmperKit.shared.eventLogger
  }()

  public lazy var notificationHandler: EventNotificationHandler = {
    AmperKit.shared.notificationHandler
  }()

  public var libraryUpdater: LibraryUpdater { AmperKit.shared.libraryUpdater }

  public lazy var userStatistics = {
    AmperKit.shared.userStatistics
  }()

  public func getMeta(_ accountInfo: AccountInfo) -> MetaManager {
    AmperKit.shared.getMeta(accountInfo)
  }

  public func resetMeta(_ accountInfo: AccountInfo) {
    AmperKit.shared.resetMeta(accountInfo)
  }

  public lazy var intentManager = {
    IntentManager(
      storage: storage,
      getLibrarySyncerCB: { accountInfo in
        self.getMeta(accountInfo).librarySyncer
      },
      getPlayableDownloadManagerCB: { accountInfo in
        self.getMeta(accountInfo).playableDownloadManager
      },
      library: storage.main.library,
      getActiveAccountCallback: {
        guard let activeAccountInfo = self.storage.settings.accounts.active else { return nil }
        return self.storage.main.library.getAccount(info: activeAccountInfo)
      },
      player: player, networkMonitor: networkMonitor,
      eventLogger: eventLogger
    )
  }()

  public lazy var quickActionsManager = {
    QuickActionsHandler(
      storage: self.storage,
      player: self.player,
      application: UIApplication.shared,
      displaySearchTabCB: self.displaySearchTab
    )
  }()

  var miniPlayerSceneSession: UISceneSession?

  var sleepTimer: Timer?

  var isKeepScreenAlive: Bool {
    get { UIApplication.shared.isIdleTimerDisabled }
    set { UIApplication.shared.isIdleTimerDisabled = newValue }
  }

  func configureDefaultNavigationBarStyle() {
    UINavigationBar.appearance().shadowImage = UIImage()
  }

  func configureBatteryMonitoring() {
    UIDevice.current.isBatteryMonitoringEnabled =
      (AmperKit.shared.storage.settings.user.screenLockPreventionPreference == .onlyIfCharging)
    configureLockScreenPrevention()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(batteryStateDidChange),
      name: UIDevice.batteryStateDidChangeNotification,
      object: nil
    )
  }

  @objc
  private func batteryStateDidChange(notification: NSNotification) {
    configureLockScreenPrevention()
  }

  func configureLockScreenPrevention() {
    os_log(
      "Device Battery Status: %s",
      log: self.log,
      type: .info,
      UIDevice.current.batteryState.description
    )
    switch AmperKit.shared.storage.settings.user.screenLockPreventionPreference {
    case .always:
      isKeepScreenAlive = true
    case .never:
      isKeepScreenAlive = false
    case .onlyIfCharging:
      isKeepScreenAlive = UIDevice.current.batteryState != .unplugged
    }
    os_log("Lock Screen Prevention: %s", log: self.log, type: .info, isKeepScreenAlive.description)
  }

  func initEventLogger() {
    AmperKit.shared.eventLogger.alertDisplayer = self
  }

  func stopForInit() {
    sleepTimer?.invalidate()
    sleepTimer = nil
    player.stop()
  }

  // deprecated
  var isNormalInteraction: Bool {
    storage.settings.accounts.active != nil && !libraryUpdater
      .isVisualUpadateNeeded
  }

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  )
    -> Bool {
    if let options = launchOptions {
      os_log("application launch with options:", log: self.log, type: .info)
      options
        .forEach { os_log("- key: %s", log: self.log, type: .info, $0.key.rawValue.description) }
    } else {
      os_log("application launch", log: self.log, type: .info)
    }

    storage.applyMultiAccountSettingsUpdateIfNeeded()
    libraryUpdater.performAccountCleanUpIfNeccessaryInBackground()

    if !storage.settings.app.didMigrateToAppleMusicTheme {
      for accountInfo in storage.settings.accounts.allAccounts {
        storage.settings.accounts.updateSetting(accountInfo) { accountSettings in
          accountSettings.themePreference = .red
        }
      }
      storage.settings.app.didMigrateToAppleMusicTheme = true
    }

    configureDefaultNavigationBarStyle()
    configureBatteryMonitoring()
    initEventLogger()

    guard let activeAccountInfo = appDelegate.storage.settings.accounts.active else {
      return true
    }

    setAppTheme(
      color: storage.settings.accounts.getSetting(activeAccountInfo).read.themePreference
        .asColor
    )

    guard AmperKit.shared.storage.settings.app.isLibrarySynced else {
      return true
    }

    os_log(
      "Amperfy Cache Location: %s",
      log: self.log,
      type: .info,
      CacheFileManager.shared.getAmperfyPath() ?? "-"
    )
    libraryUpdater.performSmallBlockingLibraryUpdatesIfNeeded()
    // start manager only if no visual indicated updates are needed
    if !libraryUpdater.isVisualUpadateNeeded {
      startManagerForNormalOperation()
    }
    userStatistics.sessionStarted()

    return true
  }

  private var isAlreadyRegisteredToPlayer = false
  func startManagerAfterSync() {
    os_log("Start background manager after sync", log: self.log, type: .info)
    configureMainMenu()
    intentManager.registerXCallbackURLs()
    if !isAlreadyRegisteredToPlayer {
      isAlreadyRegisteredToPlayer = true
      player.addNotifier(notifier: self)
    }
  }

  func startManagerForNormalOperation() {
    os_log("Start background manager for normal operation", log: self.log, type: .info)
    configureMainMenu()
    intentManager.registerXCallbackURLs()
    for accountInfo in storage.settings.accounts.allAccounts {
      getMeta(accountInfo).startManagerForNormalOperation(player: appDelegate.player)
    }
    isAlreadyRegisteredToPlayer = true
    player.addNotifier(notifier: self)
  }

  func setAppTheme(color: UIColor) {
    UIView.appearance().tintColor = color
  }

  // the following applies the tint color to already loaded views in all windows (UIKit)
  func applyAppThemeToAlreadyLoadedViews() {
    let windowScene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let windows = windowScene.flatMap { $0.windows }

    for window in windows {
      for view in window.subviews {
        view.removeFromSuperview()
        window.addSubview(view)
      }
    }
  }

  func switchAccount(accountInfo: AccountInfo) {
    storage.settings.accounts.switchActiveAccount(accountInfo)
    notificationHandler.post(
      name: .accountActiveChanged,
      object: nil,
      userInfo: nil
    )
    let account = appDelegate.storage.main.library.getAccount(info: accountInfo)
    lastWebDAVIncrementalScanAttempt = nil
    triggerWebDAVIncrementalScanIfNeeded(force: true)

    closeAllButActiveMainTabs()
    setAppTheme(
      color: appDelegate.storage.settings.accounts.getSetting(accountInfo)
        .read.themePreference.asColor
    )
    applyAppThemeToAlreadyLoadedViews()
    AmperfyAppShortcuts.updateAppShortcutParameters()
    guard let mainScene = AppDelegate.mainSceneDelegate else { return }
    mainScene
      .replaceMainRootViewController(
        vc: AppStoryboard.Main
          .segueToMainWindow(account: account)
      )
  }

  func removeAccount(accountInfo: AccountInfo) {
    closeAllButActiveMainTabs()
    if storage.settings.accounts.allAccounts.count <= 1 {
      stopForInit()
    }

    let meta = getMeta(accountInfo)
    meta.stopManager()
    resetMeta(accountInfo)

    // delete cached files
    CacheFileManager.shared.deleteAccountCache(accountInfo: accountInfo)
    // reset login credentials -> at new start the login view is presented to auth and resync library
    storage.settings.accounts.logout(accountInfo)
    notificationHandler.post(name: .accountDeleted, object: nil, userInfo: nil)
    notificationHandler.post(name: .accountActiveChanged, object: nil, userInfo: nil)

    // reset quick actions
    quickActionsManager.configureQuickActions()
    configureMainMenu()

    storage.settings.user.isOfflineMode = false
    let account = storage.main.library.getAccount(info: accountInfo)
    player.logout(account: account)
    if let newActiveAccountInfo = storage.settings.accounts.active {
      let newActiveAccount = storage.main.library.getAccount(info: newActiveAccountInfo)
      closeAllButActiveMainTabs()
      setAppTheme(
        color: storage.settings.accounts.getSetting(newActiveAccountInfo)
          .read.themePreference.asColor
      )
      applyAppThemeToAlreadyLoadedViews()
      guard let mainScene = AppDelegate.mainSceneDelegate else { return }
      mainScene
        .replaceMainRootViewController(
          vc: AppStoryboard.Main
            .segueToMainWindow(account: newActiveAccount)
        )
    } else {
      // No other account: Behave like initial App start
      // force resync after login
      storage.settings.app.isLibrarySynced = false
      let loginVC = AppStoryboard.Main.segueToLogin()
      AppDelegate.mainSceneDelegate?.replaceMainRootViewController(vc: loginVC)
    }
  }

  func switchOnlineOfflineMode(isOfflineMode: Bool) {
    appDelegate.storage.settings.user.isOfflineMode = isOfflineMode
    appDelegate.notificationHandler.post(
      name: .offlineModeChanged,
      object: nil,
      userInfo: nil
    )
  }

  func switchToolbarCollapseMode(isToolbarPlayerAutoCollapse: Bool) {
    appDelegate.storage.settings.user.isToolbarPlayerAutoCollapse = isToolbarPlayerAutoCollapse
    appDelegate.notificationHandler.post(
      name: .autoCollapseToolbarPlayerChanged,
      object: nil,
      userInfo: nil
    )
  }

  func setAppAppearanceMode(style: UIUserInterfaceStyle) {
    if #available(iOS 13.0, *) {
      UIApplication.shared.connectedScenes
        .forEach {
          if let windowScene = $0 as? UIWindowScene {
            windowScene.windows.forEach { window in
              window.overrideUserInterfaceStyle = style
              window.rootViewController?.overrideUserInterfaceStyle = style
            }
          }
        }
    }
  }

  /// The app reads `AppleLanguages` while launching, so the new language only shows up after a
  /// restart. Keeping the override in the app's own defaults leaves the system language alone.
  func applyAppLanguage(_ language: AppLanguage) {
    switch language {
    case .system:
      UserDefaults.standard.removeObject(forKey: "AppleLanguages")
    case .english:
      UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
    case .simplifiedChinese:
      UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
    }
  }

  /// Applies the in-app text size (see `TextScaling`) to the app and all windows
  func applyTextSize() {
    let textSize = storage.settings.user.textSize
    TextScaling.textSize = textSize
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .forEach { window in
        if let textSize {
          window.traitOverrides.preferredContentSizeCategory = textSize
        } else {
          window.traitOverrides.remove(UITraitPreferredContentSizeCategory.self)
        }
      }
  }

  func applicationWillResignActive(_ application: UIApplication) {
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    os_log("applicationWillResignActive", log: self.log, type: .info)
  }

  func applicationDidEnterBackground(_ application: UIApplication) {
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    os_log("applicationDidEnterBackground", log: self.log, type: .info)
  }

  func applicationWillEnterForeground(_ application: UIApplication) {
    // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    os_log("applicationWillEnterForeground", log: self.log, type: .info)
  }

  func applicationDidBecomeActive(_ application: UIApplication) {
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    os_log("applicationDidBecomeActive", log: self.log, type: .info)
    triggerWebDAVIncrementalScanIfNeeded()
  }

  /// WebDAV has no file system events, so changes are discovered by re-running the incremental
  /// indexer when the app becomes active. It compares size and modification date per file and
  /// only fetches metadata for new or changed entries.
  func triggerWebDAVIncrementalScanIfNeeded(force: Bool = false) {
    guard storage.settings.app.isLibrarySynced,
          !storage.settings.user.isOfflineMode,
          let accountInfo = storage.settings.accounts.active
    else { return }
    let account = storage.main.library.getAccount(info: accountInfo)
    guard account.apiType == .webdav,
          storage.settings.accounts.getSetting(accountInfo).read
          .initialSyncCompletionStatus != .aborted
    else { return }
    if !force, let lastAttempt = lastWebDAVIncrementalScanAttempt,
       Date().timeIntervalSince(lastAttempt) < Self.webDAVIncrementalScanMinimumInterval {
      return
    }
    lastWebDAVIncrementalScanAttempt = Date()
    let librarySyncer = getMeta(accountInfo).librarySyncer
    Task { @MainActor in
      do {
        try await librarySyncer.syncInitial(statusNotifyier: nil)
        self.notificationHandler.post(name: .librarySongsSynced, object: nil, userInfo: nil)
        os_log("WebDAV incremental scan finished", log: self.log, type: .info)
      } catch {
        os_log(
          "WebDAV incremental scan failed: %s",
          log: self.log,
          type: .error,
          error.localizedDescription
        )
      }
    }
  }

  func applicationWillTerminate(_ application: UIApplication) {
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    os_log("applicationWillTerminate", log: self.log, type: .info)
    for meta in AmperKit.shared.allActiveMetas {
      meta.value.backgroundLibrarySyncer.stop()
    }
    storage.main.saveContext()
  }

  func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @Sendable @escaping () -> ()
  ) {
    os_log("handleEventsForBackgroundURLSession: %s", log: self.log, type: .info, identifier)
    let responsibleMeta = AmperKit.shared.allActiveMetas
      .first(where: { $0.value.playableDownloadManager.urlSessionIdentifier == identifier })
    responsibleMeta?.value.playableDownloadManager
      .setBackgroundFetchCompletionHandler(completionHandler)
  }

  func application(
    _ application: UIApplication,
    configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  )
    -> UISceneConfiguration {
    guard connectingSceneSession.role != .carTemplateApplication else {
      let config = UISceneConfiguration(
        name: "CarPlay Configuration",
        sessionRole: .carTemplateApplication
      )
      config.delegateClass = CarPlaySceneDelegate.self
      return config
    }

    if options.userActivities.filter({ $0.activityType == settingsWindowActivityType })
      .first != nil {
      let config = UISceneConfiguration(name: "Settings", sessionRole: .windowApplication)
      config.delegateClass = SettingsSceneDelegate.self
      return config
    }

    if options.userActivities.filter({ $0.activityType == miniPlayerWindowActivityType })
      .first != nil {
      let config = UISceneConfiguration(name: "MiniPlayer", sessionRole: .windowApplication)
      config.delegateClass = MiniPlayerSceneDelegate.self
      return config
    }

    let config = UISceneConfiguration(
      name: "Default Configuration",
      sessionRole: .windowApplication
    )
    config.delegateClass = SceneDelegate.self
    return config
  }

  func application(
    _ application: UIApplication,
    didDiscardSceneSessions sceneSessions: Set<UISceneSession>
  ) {
    os_log("didDiscardSceneSessions", log: self.log, type: .info)
  }

  func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any? {
    os_log("application handlerFor intent", log: self.log, type: .info)
    // This is the default implementation.  If you want different objects to handle different intents,
    // you can override this and return the handler you want for that particular intent.
    if intent is INPlayMediaIntent {
      return PlayMediaIntentHandler(intentManager: intentManager)
    }
    return nil
  }
}
