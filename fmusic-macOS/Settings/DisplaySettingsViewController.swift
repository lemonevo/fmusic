//
//  DisplaySettingsViewController.swift
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

/// 显示与交互: appearance, theme colour, artwork preference and app icon.
@MainActor
final class DisplaySettingsViewController: SettingsPageViewController {
  init() {
    super.init(title: L10n.tr("Display"))
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func buildForm() {
    let accountSetting = SettingsStore.activeAccountSetting
    let hasActiveAccount = SettingsStore.activeAccount != nil

    let appearanceLabels = AppearanceMode.allCases.map { mode -> String in
      switch mode {
      case .unspecified: return L10n.tr("System")
      case .light: return L10n.tr("Light")
      case .dark: return L10n.tr("Dark")
      }
    }
    let appearanceRow = makeSegmentedRow(
      title: L10n.tr("Appearance"),
      labels: appearanceLabels,
      selectedIndex: SettingsStore.user.appearanceMode.rawValue
    ) { index in
      guard let mode = AppearanceMode(rawValue: index) else { return }
      SettingsStore.updateUser { $0.appearanceMode = mode }
      SettingsStore.applyAppearance()
    }
    let glassLabels = GlassStyleMode.allCases.map(\.title)
    let glassRow = makeRow(
      title: L10n.tr("Liquid Glass"),
      subtitle: L10n.tr(
        "Adjust the transparency and depth of the app's glass surfaces."
      ),
      control: SettingsSegmentedControl(
        labels: glassLabels,
        selectedIndex: GlassStyleManager.mode.rawValue
      ) { index in
        guard let mode = GlassStyleMode(rawValue: index) else { return }
        GlassStyleManager.setMode(mode)
      }
    )
    addSection(header: L10n.tr("Appearance"), rows: [appearanceRow, glassRow])

    let themeControl = SettingsThemeColorControl(
      selected: accountSetting.themePreference
    ) { preference in
      SettingsStore.updateActiveAccountSetting { $0.themePreference = preference }
    }
    themeControl.setEnabled(hasActiveAccount)
    let themeRow = makeRow(title: L10n.tr("Theme Color"), control: themeControl)

    let artworkPreferences = ArtworkDisplayPreference.allCases
    let artworkPopup = SettingsPopUpButton(
      titles: artworkPreferences.map(\.description),
      selectedIndex: artworkPreferences.firstIndex(
        of: accountSetting.artworkDisplayPreference
      ) ?? 0
    ) { index in
      guard index >= 0, index < artworkPreferences.count else { return }
      SettingsStore.updateActiveAccountSetting {
        $0.artworkDisplayPreference = artworkPreferences[index]
      }
    }
    artworkPopup.isEnabled = hasActiveAccount
    let artworkRow = makeRow(title: L10n.tr("Artwork Display"), control: artworkPopup)
    addSection(header: L10n.tr("Theme & Artwork"), rows: [themeRow, artworkRow])

    let appIconPicker = AppIconPickerView(selectedID: AppIconManager.selectedIconID) { iconID in
      AppIconManager.apply(iconID: iconID)
    }
    let iconContainer = NSView()
    iconContainer.translatesAutoresizingMaskIntoConstraints = false
    appIconPicker.translatesAutoresizingMaskIntoConstraints = false
    iconContainer.addSubview(appIconPicker)
    NSLayoutConstraint.activate([
      appIconPicker.topAnchor.constraint(equalTo: iconContainer.topAnchor, constant: 12),
      appIconPicker.leadingAnchor.constraint(equalTo: iconContainer.leadingAnchor, constant: 16),
      appIconPicker.trailingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: -16),
      appIconPicker.bottomAnchor.constraint(equalTo: iconContainer.bottomAnchor, constant: -12),
    ])
    addSection(header: L10n.tr("App Icon"), rows: [iconContainer])
  }
}
