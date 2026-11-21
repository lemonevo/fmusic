//
//  SettingsStore.swift
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

/// Small persistence facade shared by the settings pages.
///
/// The settings live in the package's `fmusicSettings` struct: every mutation is done on a
/// local copy and written back so the packaged property observer (which encodes the value
/// into `UserDefaults`) runs exactly once per change. That is the same pattern the Catalyst
/// app uses, so both front-ends share one settings store.
@MainActor
enum SettingsStore {
  static var storage: PersistentStorage { FmusicKit.shared.storage }
  static var player: PlayerFacade { FmusicKit.shared.player }

  // MARK: - User settings

  static var user: UserSettings { storage.settings.user }

  static func updateUser(_ update: (inout UserSettings) -> Void) {
    var user = storage.settings.user
    update(&user)
    storage.settings.user = user
    NotificationCenter.default.post(name: .macPlaybackSettingsChanged, object: nil)
  }

  // MARK: - Account settings

  static var activeAccount: AccountInfo? { storage.settings.accounts.active }

  static var activeAccountSetting: AccountSetting {
    storage.settings.accounts.activeSetting.read
  }

  static func updateActiveAccountSetting(_ update: (inout AccountSetting) -> Void) {
    guard let accountInfo = storage.settings.accounts.active else { return }
    storage.settings.accounts.updateSetting(accountInfo) { accountSetting in
      update(&accountSetting)
    }
    NotificationCenter.default.post(name: .macThemeColorChanged, object: nil)
  }

  // MARK: - Effects

  /// Applies the persisted appearance mode to every window immediately.
  static func applyAppearance() {
    MacTheme.applyAppearanceMode()
    NotificationCenter.default.post(name: .macAppearanceChanged, object: nil)
  }

  /// Tells the package that offline mode changed so downloaders and network code react.
  static func notifyOfflineModeChanged() {
    FmusicKit.shared.notificationHandler.post(
      name: .offlineModeChanged,
      object: nil,
      userInfo: nil
    )
  }

  /// The app reads `AppleLanguages` while launching, so a new language is only picked up on
  /// the next start. Keeping the override in the app's own defaults leaves the system
  /// language alone (mirrors the Catalyst app).
  static func applyAppLanguage(_ language: AppLanguage) {
    switch language {
    case .system:
      UserDefaults.standard.removeObject(forKey: "AppleLanguages")
    case .english:
      UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
    case .simplifiedChinese:
      UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
    }
  }

  static func setAppLanguage(_ language: AppLanguage) {
    guard storage.settings.user.appLanguage != language else { return }
    updateUser { $0.appLanguage = language }
    applyAppLanguage(language)
  }
}
