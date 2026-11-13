//
//  Settings.swift
//  fmusicKit
//
//  Created by Maximilian Bauer on 09.12.25.
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

import os.log
import UIKit

// MARK: - AppSettings

public struct AppSettings: Sendable, Codable {
  private var _isLibrarySyncInfoReadByUser: Bool = false
  public var isLibrarySyncInfoReadByUser: Bool {
    get { _isLibrarySyncInfoReadByUser }
    set { _isLibrarySyncInfoReadByUser = newValue }
  }

  private var _isLibrarySynced: Bool = false
  public var isLibrarySynced: Bool {
    get { _isLibrarySynced }
    set { _isLibrarySynced = newValue }
  }

  private var _librarySyncVersion: LibrarySyncVersion = .v6
  public var librarySyncVersion: LibrarySyncVersion {
    get { _librarySyncVersion }
    set { _librarySyncVersion = newValue }
  }

  private var _didMigrateToAppleMusicTheme: Bool?
  public var didMigrateToAppleMusicTheme: Bool {
    get { _didMigrateToAppleMusicTheme ?? false }
    set { _didMigrateToAppleMusicTheme = newValue }
  }
}

// MARK: - UserSettings

public enum AppLanguage: String, Sendable, Codable, CaseIterable {
  case system
  case english
  case simplifiedChinese
}

public struct UserSettings: Sendable, Codable {
  private var _isShowDetailedInfo: Bool = false
  public var isShowDetailedInfo: Bool {
    get { _isShowDetailedInfo }
    set { _isShowDetailedInfo = newValue }
  }

  private var _isShowSongDuration: Bool = false
  public var isShowSongDuration: Bool {
    get { _isShowSongDuration }
    set { _isShowSongDuration = newValue }
  }

  private var _isShowAlbumDuration: Bool = false
  public var isShowAlbumDuration: Bool {
    get { _isShowAlbumDuration }
    set { _isShowAlbumDuration = newValue }
  }

  private var _isShowArtistDuration: Bool = false
  public var isShowArtistDuration: Bool {
    get { _isShowArtistDuration }
    set { _isShowArtistDuration = newValue }
  }

  private var _isShowRating: Bool = false
  public var isShowRating: Bool {
    get { _isShowRating }
    set { _isShowRating = newValue }
  }

  private var _isPlayerShuffleButtonEnabled: Bool = true
  public var isPlayerShuffleButtonEnabled: Bool {
    get { _isPlayerShuffleButtonEnabled }
    set { _isPlayerShuffleButtonEnabled = newValue }
  }

  private var _isShowMusicPlayerSkipButtons: Bool = false
  public var isShowMusicPlayerSkipButtons: Bool {
    get { _isShowMusicPlayerSkipButtons }
    set { _isShowMusicPlayerSkipButtons = newValue }
  }

  private var _isToolbarPlayerAutoCollapse: Bool = true
  public var isToolbarPlayerAutoCollapse: Bool {
    get { _isToolbarPlayerAutoCollapse }
    set { _isToolbarPlayerAutoCollapse = newValue }
  }

  private var _isLyricsSmoothScrolling: Bool = true
  public var isLyricsSmoothScrolling: Bool {
    get { _isLyricsSmoothScrolling }
    set { _isLyricsSmoothScrolling = newValue }
  }

  private var _isDesktopLyricsEnabled: Bool = false
  public var isDesktopLyricsEnabled: Bool {
    get { _isDesktopLyricsEnabled }
    set { _isDesktopLyricsEnabled = newValue }
  }

  private var _desktopLyricsFontSize: DesktopLyricsFontSize = .defaultValue
  public var desktopLyricsFontSize: DesktopLyricsFontSize {
    get { _desktopLyricsFontSize }
    set { _desktopLyricsFontSize = newValue }
  }

  private var _isDesktopLyricsLocked: Bool = false
  public var isDesktopLyricsLocked: Bool {
    get { _isDesktopLyricsLocked }
    set { _isDesktopLyricsLocked = newValue }
  }

  // 0 = fully transparent background, 100 = opaque card
  private var _desktopLyricsBackgroundOpacity: Int = 74
  public var desktopLyricsBackgroundOpacity: Int {
    get { _desktopLyricsBackgroundOpacity }
    set { _desktopLyricsBackgroundOpacity = min(100, max(0, newValue)) }
  }

  private var _isDesktopLyricsNextLineShown: Bool = true
  public var isDesktopLyricsNextLineShown: Bool {
    get { _isDesktopLyricsNextLineShown }
    set { _isDesktopLyricsNextLineShown = newValue }
  }

  private var _desktopLyricsAlignment: DesktopLyricsAlignment = .defaultValue
  public var desktopLyricsAlignment: DesktopLyricsAlignment {
    get { _desktopLyricsAlignment }
    set { _desktopLyricsAlignment = newValue }
  }

  private var _isDesktopLyricsAlwaysOnTop: Bool = true
  public var isDesktopLyricsAlwaysOnTop: Bool {
    get { _isDesktopLyricsAlwaysOnTop }
    set { _isDesktopLyricsAlwaysOnTop = newValue }
  }

  private var _isMenuBarLyricsEnabled: Bool = false
  public var isMenuBarLyricsEnabled: Bool {
    get { _isMenuBarLyricsEnabled }
    set { _isMenuBarLyricsEnabled = newValue }
  }

  // limit in byte
  private var _cacheLimit: Int = 0
  public var cacheLimit: Int {
    get { _cacheLimit }
    set { _cacheLimit = newValue }
  }

  // Manual lyrics timing offset in milliseconds; positive shows lyrics sooner.
  private var _lyricsOffsetMs: Int = 0
  public var lyricsOffsetMs: Int {
    get { _lyricsOffsetMs }
    set { _lyricsOffsetMs = min(5_000, max(-5_000, newValue)) }
  }

  // Crossfade duration in seconds between consecutive tracks; 0 disables crossfading.
  private var _crossfadeSeconds: Int = 0
  public var crossfadeSeconds: Int {
    get { _crossfadeSeconds }
    set { _crossfadeSeconds = min(8, max(0, newValue)) }
  }

  private var _isPlayerLyricsDisplayed: Bool = false
  public var isPlayerLyricsDisplayed: Bool {
    get { _isPlayerLyricsDisplayed }
    set { _isPlayerLyricsDisplayed = newValue }
  }

  private var _isPlayerQueueDisplayed: Bool = false
  public var isPlayerQueueDisplayed: Bool {
    get { _isPlayerQueueDisplayed }
    set { _isPlayerQueueDisplayed = newValue }
  }

  private var _isPlayerVisualizerDisplayed: Bool = false
  public var isPlayerVisualizerDisplayed: Bool {
    get { _isPlayerVisualizerDisplayed }
    set { _isPlayerVisualizerDisplayed = newValue }
  }

  private var _selectedVisualizerType: VisualizerType = .defaultValue
  public var selectedVisualizerType: VisualizerType {
    get { _selectedVisualizerType }
    set { _selectedVisualizerType = newValue }
  }

  private var _isOfflineMode: Bool = false
  public var isOfflineMode: Bool {
    get { _isOfflineMode }
    set { _isOfflineMode = newValue }
  }

  public var isOnlineMode: Bool {
    !_isOfflineMode
  }

  private var _isPlaybackStartOnlyOnPlay: Bool = false
  public var isPlaybackStartOnlyOnPlay: Bool {
    get { _isPlaybackStartOnlyOnPlay }
    set { _isPlaybackStartOnlyOnPlay = newValue }
  }

  private var _isPlayerSongPlaybackResumeEnabled: Bool = false
  public var isPlayerSongPlaybackResumeEnabled: Bool {
    get { _isPlayerSongPlaybackResumeEnabled }
    set { _isPlayerSongPlaybackResumeEnabled = newValue }
  }

  private var _isAutoplayEnabled: Bool = false
  public var isAutoplayEnabled: Bool {
    get { _isAutoplayEnabled }
    set { _isAutoplayEnabled = newValue }
  }

  private var _isHapticsEnabled: Bool = true
  public var isHapticsEnabled: Bool {
    get { _isHapticsEnabled }
    set { _isHapticsEnabled = newValue }
  }

  private var _isEqualizerEnabled: Bool = false
  public var isEqualizerEnabled: Bool {
    get { _isEqualizerEnabled }
    set { _isEqualizerEnabled = newValue }
  }

  private var _activeEqualizerSetting: EqualizerSetting = .off
  public var activeEqualizerSetting: EqualizerSetting {
    get { _activeEqualizerSetting }
    set { _activeEqualizerSetting = newValue }
  }

  private var _equalizerSettings: [EqualizerSetting] = []
  public var equalizerSettings: [EqualizerSetting] {
    get { _equalizerSettings }
    set { _equalizerSettings = newValue }
  }

  private var _isReplayGainEnabled: Bool = true
  public var isReplayGainEnabled: Bool {
    get { _isReplayGainEnabled }
    set { _isReplayGainEnabled = newValue }
  }

  private var _isMiniPlayerAlwaysOnTop: Bool = false
  public var isMiniPlayerAlwaysOnTop: Bool {
    get { _isMiniPlayerAlwaysOnTop }
    set { _isMiniPlayerAlwaysOnTop = newValue }
  }

  private var _playerVolume: Float = 1.0
  public var playerVolume: Float {
    get {
      (_playerVolume >= 0.0 && _playerVolume <= 1.0) ? _playerVolume : 1.0
    }
    set {
      guard newValue >= 0.0, newValue <= 1.0 else { return }
      _playerVolume = newValue
    }
  }

  private var _appearanceMode: UIUserInterfaceStyle = .unspecified
  public var appearanceMode: UIUserInterfaceStyle {
    get { _appearanceMode }
    set { _appearanceMode = newValue }
  }

  private var _appLanguage: AppLanguage = .system
  public var appLanguage: AppLanguage {
    get { _appLanguage }
    set { _appLanguage = newValue }
  }

  /// In-app text size, nil: system text size (iOS) / default text size (macOS, no Dynamic Type)
  private var _textSize: String?
  public var textSize: UIContentSizeCategory? {
    get { _textSize.map { UIContentSizeCategory(rawValue: $0) } }
    set { _textSize = newValue?.rawValue }
  }

  private var _screenLockPreventionPreference: ScreenLockPreventionPreference = .defaultValue
  public var screenLockPreventionPreference: ScreenLockPreventionPreference {
    get { _screenLockPreventionPreference }
    set { _screenLockPreventionPreference = newValue }
  }

  private var _playlistsSortSetting: PlaylistSortType = .defaultValue
  public var playlistsSortSetting: PlaylistSortType {
    get { _playlistsSortSetting }
    set { _playlistsSortSetting = newValue }
  }

  private var _artistsSortSetting: ArtistElementSortType = .defaultValue
  public var artistsSortSetting: ArtistElementSortType {
    get { _artistsSortSetting }
    set { _artistsSortSetting = newValue }
  }

  private var _albumsSortSetting: AlbumElementSortType = .defaultValue
  public var albumsSortSetting: AlbumElementSortType {
    get { _albumsSortSetting }
    set { _albumsSortSetting = newValue }
  }

  private var _swipeActionSettings: SwipeActionSettings = .defaultSettings
  public var swipeActionSettings: SwipeActionSettings {
    get { _swipeActionSettings }
    set { _swipeActionSettings = newValue }
  }

  private var _songsSortSetting: SongElementSortType = .defaultValue
  public var songsSortSetting: SongElementSortType {
    get { _songsSortSetting }
    set {
      if newValue == SongElementSortType.starredDate {
        _songsSortSetting = .defaultValue
      } else {
        _songsSortSetting = newValue
      }
    }
  }

  private var _favoriteSongSortSetting: SongElementSortType = .defaultValueForFavorite
  public var favoriteSongSortSetting: SongElementSortType {
    get { _favoriteSongSortSetting }
    set { _favoriteSongSortSetting = newValue }
  }

  private var _artistsFilterSetting: ArtistCategoryFilter = .defaultValue
  public var artistsFilterSetting: ArtistCategoryFilter {
    get { _artistsFilterSetting }
    set { _artistsFilterSetting = newValue }
  }

  private var _albumsStyleSetting: AlbumsDisplayStyle = .defaultValue
  public var albumsStyleSetting: AlbumsDisplayStyle {
    get { _albumsStyleSetting }
    set { _albumsStyleSetting = newValue }
  }

  private var _podcastsShowSetting: PodcastsShowType = .defaultValue
  public var podcastsShowSetting: PodcastsShowType {
    get { _podcastsShowSetting }
    set { _podcastsShowSetting = newValue }
  }

  private var _playerDisplayStyle: PlayerDisplayStyle = .defaultValue
  public var playerDisplayStyle: PlayerDisplayStyle {
    get { _playerDisplayStyle }
    set { _playerDisplayStyle = newValue }
  }

  private var _albumsGridSizeSetting: Int?
  @MainActor
  public var albumsGridSizeSetting: Int {
    get {
      _albumsGridSizeSetting ?? ((UIDevice.current.userInterfaceIdiom == .pad) ? 4 : 3)
    }
    set { _albumsGridSizeSetting = newValue }
  }
}

// MARK: - AccountSetting

public struct AccountSetting: Sendable, Codable {
  private var _artworkDisplayPreference: ArtworkDisplayPreference = .defaultValue
  public var artworkDisplayPreference: ArtworkDisplayPreference {
    get { _artworkDisplayPreference }
    set { _artworkDisplayPreference = newValue }
  }

  private var _artworkDownloadSetting: ArtworkDownloadSetting = .defaultValue
  public var artworkDownloadSetting: ArtworkDownloadSetting {
    get { _artworkDownloadSetting }
    set { _artworkDownloadSetting = newValue }
  }

  // ordered visible Home Sections
  private var _homeSections: [HomeSection] = HomeSection.defaultValue
  public var homeSections: [HomeSection] {
    get { _homeSections.filter(HomeSection.supportedCases.contains) }
    set { _homeSections = newValue }
  }

  // all Home Sections (visible and hidden) in the order arranged by the user
  // optional: settings stored before this property existed must still decode
  private var _homeSectionOrder: [HomeSection]?
  public var homeSectionOrder: [HomeSection] {
    get {
      (_homeSectionOrder ?? _homeSections)
        .filter(HomeSection.supportedCases.contains)
        .completingOrder(with: HomeSection.supportedCases)
    }
    set { _homeSectionOrder = newValue }
  }

  private var _initialSyncCompletionStatus: SyncCompletionStatus = .defaultValue
  public var initialSyncCompletionStatus: SyncCompletionStatus {
    get { _initialSyncCompletionStatus }
    set { _initialSyncCompletionStatus = newValue }
  }


  private var _isAutoDownloadLatestSongsActive: Bool = false
  public var isAutoDownloadLatestSongsActive: Bool {
    get { _isAutoDownloadLatestSongsActive }
    set { _isAutoDownloadLatestSongsActive = newValue }
  }

  private var _libraryDisplaySettings: LibraryDisplaySettings = .defaultSettings
  public var libraryDisplaySettings: LibraryDisplaySettings {
    get { _libraryDisplaySettings }
    set { _libraryDisplaySettings = newValue }
  }

  private var _libraryIndexVersion: Int?
  public var libraryIndexVersion: Int? {
    get { _libraryIndexVersion }
    set { _libraryIndexVersion = newValue }
  }

  private var _loginCredentials: LoginCredentials? = nil
  public var loginCredentials: LoginCredentials? {
    get { _loginCredentials }
    set { _loginCredentials = newValue }
  }

  private var _themePreference: ThemePreference = .defaultValue
  public var themePreference: ThemePreference {
    get { _themePreference }
    set { _themePreference = newValue }
  }
}

// MARK: - ReadOnlyAccountSetting

public struct ReadOnlyAccountSetting {
  public let read: AccountSetting
}

// MARK: - AccountSettings

public struct AccountSettings: Sendable, Codable {
  fileprivate var _accounts: [AccountInfo: AccountSetting] = [:]
  fileprivate var _activeAccount: AccountInfo?

  public mutating func switchActiveAccount(_ accountInfo: AccountInfo) {
    _activeAccount = accountInfo
  }

  public mutating func login(_ loginCredentials: LoginCredentials) {
    let accountInfo = Account.createInfo(credentials: loginCredentials)
    let newTheme = themeColorForNextNewAccount
    updateSetting(accountInfo) { accountSettings in
      accountSettings.loginCredentials = loginCredentials
      accountSettings.themePreference = newTheme
    }
    _activeAccount = accountInfo
  }

  public func getSetting(_ accountInfo: AccountInfo?) -> ReadOnlyAccountSetting {
    // Settings Priority:
    // 1.: provided account settings (if not nil)
    // 2.: active account settings (if logged in)
    // 3.: default settings
    if let info = accountInfo ?? _activeAccount, let accountSettings = _accounts[info] {
      return ReadOnlyAccountSetting(read: accountSettings)
    } else {
      return ReadOnlyAccountSetting(read: AccountSetting())
    }
  }

  public mutating func logout(_ accountInfo: AccountInfo) {
    _accounts[accountInfo] = nil
    if _activeAccount == accountInfo {
      _activeAccount = _accounts.first?.key
    }
  }

  public mutating func updateSetting(
    _ accountInfo: AccountInfo,
    _ update: (inout AccountSetting) -> ()
  ) {
    var setting = _accounts[accountInfo] ?? AccountSetting()
    update(&setting)
    _accounts[accountInfo] = setting
  }

  public var active: AccountInfo? {
    _activeAccount
  }

  public var activeSetting: ReadOnlyAccountSetting {
    guard let _activeAccount else { return ReadOnlyAccountSetting(read: AccountSetting()) }
    return ReadOnlyAccountSetting(read: _accounts[_activeAccount] ?? AccountSetting())
  }

  public var allAccounts: [AccountInfo] {
    _accounts.compactMap { $0.key }.sorted(by: {
      guard let cred0 = getSetting($0).read.loginCredentials,
            let cred1 = getSetting($1).read.loginCredentials
      else { return false }

      if cred0.displayServerUrl != cred1.displayServerUrl {
        return cred0.displayServerUrl < cred1.displayServerUrl
      } else {
        return cred0.username < cred1.username
      }
    })
  }

  private var themeColorForNextNewAccount: ThemePreference {
    // Apple Music uses one fixed accent color for every account.
    .red
  }
}

// MARK: - fmusicSettings

public struct fmusicSettings: Sendable, Codable {
  // MARK: - Persistence

  private static let decoder: JSONDecoder = .init()
  private static let encoder: JSONEncoder = {
    let e = JSONEncoder()
    e.outputFormatting = []
    return e
  }()

  /// Settings saved by an older app version lack the fields added since. Decoding them would
  /// fail, so fill those fields in from `defaults` and keep everything that was saved.
  private static func decodeFillingMissingKeys<T: Codable>(
    _ type: T.Type,
    from data: Data,
    defaults: T
  ) throws
    -> T {
    if let settings = try? decoder.decode(type, from: data) {
      return settings
    }
    guard let saved = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let defaultValues = try JSONSerialization
          .jsonObject(with: encoder.encode(defaults)) as? [String: Any]
    else {
      return try decoder.decode(type, from: data)
    }
    let merged = defaultValues.merging(saved) { _, savedValue in savedValue }
    return try decoder.decode(type, from: JSONSerialization.data(withJSONObject: merged))
  }

  /// Decoded settings are cached per stored blob: the getters run for every list cell and on
  /// every playback tick, and decoding the JSON plus hashing the credentials there is expensive.
  /// The cache is keyed by the raw `Data` so copies of this struct still see later changes.
  private static let decodeCache = SettingsDecodeCache()

  private static func settingsData(for key: PersistentStorage.UserDefaultsKey) -> Data? {
    UserDefaults.standard.data(forKey: key.rawValue)
  }

  private var _appSettings: AppSettings = .init()
  public var app: AppSettings {
    get {
      guard let data = Self.settingsData(for: .SettingsApp) else { return _appSettings }
      return Self.decodeCache.value(key: .SettingsApp, data: data) {
        try Self.decodeFillingMissingKeys(AppSettings.self, from: $0, defaults: .init())
      } ?? _appSettings
    }
    set {
      _appSettings = newValue
      do {
        let data = try Self.encoder.encode(_appSettings)
        UserDefaults.standard.set(
          data,
          forKey: PersistentStorage.UserDefaultsKey.SettingsApp.rawValue
        )
        Self.decodeCache.store(key: .SettingsApp, data: data, value: newValue)
      } catch {}
    }
  }

  private var _userSettings: UserSettings = .init()
  public var user: UserSettings {
    get {
      guard let data = Self.settingsData(for: .SettingsUser) else { return _userSettings }
      return Self.decodeCache.value(key: .SettingsUser, data: data) {
        try Self.decodeFillingMissingKeys(UserSettings.self, from: $0, defaults: .init())
      } ?? _userSettings
    }
    set {
      _userSettings = newValue
      do {
        let data = try Self.encoder.encode(_userSettings)
        UserDefaults.standard.set(
          data,
          forKey: PersistentStorage.UserDefaultsKey.SettingsUser.rawValue
        )
        Self.decodeCache.store(key: .SettingsUser, data: data, value: newValue)
      } catch {}
    }
  }

  private var _accountSettings: AccountSettings = .init()
  public var accounts: AccountSettings {
    get {
      guard let data = Self.settingsData(for: .SettingsAccount) else { return _accountSettings }
      return Self.decodeCache.value(key: .SettingsAccount, data: data) {
        try Self.decoder.decode(AccountSettings.self, from: $0)
      } ?? _accountSettings
    }
    set {
      _accountSettings = newValue
      do {
        let data = try Self.encoder.encode(_accountSettings)
        UserDefaults.standard.set(
          data,
          forKey: PersistentStorage.UserDefaultsKey.SettingsAccount.rawValue
        )
        Self.decodeCache.store(key: .SettingsAccount, data: data, value: newValue)
      } catch {}
    }
  }
}

private final class SettingsDecodeCache: @unchecked Sendable {
  private let lock = NSLock()
  private var entries: [PersistentStorage.UserDefaultsKey: (data: Data, value: Any)] = [:]

  func value<T>(
    key: PersistentStorage.UserDefaultsKey,
    data: Data,
    decode: (Data) throws -> T
  )
    -> T? {
    lock.lock()
    if let entry = entries[key], entry.data == data, let cached = entry.value as? T {
      lock.unlock()
      return cached
    }
    lock.unlock()
    guard let decoded = try? decode(data) else { return nil }
    store(key: key, data: data, value: decoded)
    return decoded
  }

  func store(key: PersistentStorage.UserDefaultsKey, data: Data, value: Any) {
    lock.lock()
    entries[key] = (data, value)
    lock.unlock()
  }
}
