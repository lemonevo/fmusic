//
//  GeneralSettingsViewController.swift
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

/// 通用: appearance, language and offline mode.
@MainActor
final class GeneralSettingsViewController: SettingsPageViewController {
  init() {
    super.init(title: L10n.tr("General"))
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    // The window shell applies the persisted appearance on every open so the setting is
    // effective even though the app applies it lazily at bootstrap.
    SettingsStore.applyAppearance()
  }

  override func buildForm() {
    let user = SettingsStore.user

    // MARK: Language

    let languageOptions: [AppLanguage] = [.system, .simplifiedChinese, .english]
    let languageTitles = languageOptions.map { language -> String in
      switch language {
      case .system: return L10n.tr("Match System")
      case .simplifiedChinese: return L10n.tr("Simplified Chinese")
      case .english: return "English"
      }
    }
    let selectedLanguage = languageOptions.firstIndex(of: user.appLanguage) ?? 0
    let languageRow = makePopupRow(
      title: L10n.tr("Language"),
      titles: languageTitles,
      selectedIndex: selectedLanguage
    ) { [weak self] index in
      guard index >= 0, index < languageOptions.count else { return }
      let chosen = languageOptions[index]
      guard SettingsStore.user.appLanguage != chosen else { return }
      SettingsStore.setAppLanguage(chosen)
      self?.promptRestartForLanguageChange()
    }

    addSection(
      footer: L10n.tr("Language changes take effect after restarting fmusic."),
      rows: [languageRow]
    )

    // MARK: Offline mode

    let screenLockOptions = ScreenLockPreventionPreference.allCases
    let screenLockTitles = screenLockOptions.map(\.description)
    let selectedScreenLock = screenLockOptions.firstIndex(
      of: SettingsStore.screenLockPreventionPreference
    ) ?? 0
    let screenLockRow = makePopupRow(
      title: L10n.tr("Prevent Screen Lock"),
      titles: screenLockTitles,
      selectedIndex: selectedScreenLock
    ) { index in
      guard index >= 0, index < screenLockOptions.count else { return }
      SettingsStore.screenLockPreventionPreference = screenLockOptions[index]
    }

    let offlineRow = makeSwitchRow(
      title: L10n.tr("Offline Mode"),
      isOn: user.isOfflineMode
    ) { isOn in
      SettingsStore.updateUser { $0.isOfflineMode = isOn }
      SettingsStore.notifyOfflineModeChanged()
    }
    addSection(
      footer: L10n.tr(
        "Songs and artworks won’t download offline. Searches are limited to the device, and playlists won’t sync with the server."
      ),
      rows: [offlineRow]
    )
    append(makeFlatRows([screenLockRow]), topSpacing: 32)
  }

  private func promptRestartForLanguageChange() {
    let alert = NSAlert()
    alert.messageText = L10n.tr("Language")
    alert.informativeText = L10n.tr("Restart fmusic to apply the new language.")
    alert.addButton(withTitle: L10n.tr("Restart Now"))
    alert.addButton(withTitle: L10n.tr("Later"))

    let handle: (NSApplication.ModalResponse) -> Void = { response in
      guard response == .alertFirstButtonReturn else { return }
      let config = NSWorkspace.OpenConfiguration()
      config.createsNewApplicationInstance = true
      NSWorkspace.shared.openApplication(
        at: Bundle.main.bundleURL,
        configuration: config
      ) { _, _ in
        DispatchQueue.main.async {
          NSApp.terminate(nil)
        }
      }
    }

    if let window = view.window {
      alert.beginSheetModal(for: window, completionHandler: handle)
    } else {
      handle(alert.runModal())
    }
  }
}
