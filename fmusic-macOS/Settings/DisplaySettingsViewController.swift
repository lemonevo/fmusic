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

/// 显示: theme colour, artwork preference, lyrics and desktop lyrics.
@MainActor
final class DisplaySettingsViewController: SettingsPageViewController {
  init() {
    super.init(title: L10n.tr("Display"))
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func buildForm() {
    let user = SettingsStore.user
    let hasActiveAccount = SettingsStore.activeAccount != nil
    let accountSetting = SettingsStore.activeAccountSetting

    // MARK: Theme color (account scoped, like the Catalyst app)

    let themeControl = SettingsThemeColorControl(
      selected: accountSetting.themePreference
    ) { preference in
      SettingsStore.updateActiveAccountSetting { $0.themePreference = preference }
    }
    themeControl.setEnabled(hasActiveAccount)
    let themeRow = makeRow(title: L10n.tr("Theme Color"), control: themeControl)

    // MARK: Artwork display preference (account scoped)

    let artworkPreferences = ArtworkDisplayPreference.allCases
    let artworkTitles = artworkPreferences.map(\.description)
    let artworkIndex = artworkPreferences.firstIndex(
      of: accountSetting.artworkDisplayPreference
    ) ?? 0
    let artworkPopup = SettingsPopUpButton(
      titles: artworkTitles,
      selectedIndex: artworkIndex
    ) { index in
      guard index >= 0, index < artworkPreferences.count else { return }
      let preference = artworkPreferences[index]
      SettingsStore.updateActiveAccountSetting { $0.artworkDisplayPreference = preference }
    }
    artworkPopup.isEnabled = hasActiveAccount
    let artworkRow = makeRow(title: L10n.tr("Artwork Display"), control: artworkPopup)

    addSection(rows: [themeRow, artworkRow])

    // MARK: Lyrics

    let smoothScrollingRow = makeSwitchRow(
      title: L10n.tr("Lyrics Smooth Scrolling"),
      isOn: user.isLyricsSmoothScrolling
    ) { isOn in
      SettingsStore.updateUser { $0.isLyricsSmoothScrolling = isOn }
    }
    addSection(
      footer: L10n.tr(
        "Lyrics are smoothly scrolled to next line. Deactivating will result in jumping from line to line."
      ),
      rows: [smoothScrollingRow]
    )

    // MARK: Desktop lyrics

    let desktopLyricsRow = makeSwitchRow(
      title: L10n.tr("Desktop Lyrics"),
      isOn: user.isDesktopLyricsEnabled
    ) { isOn in
      SettingsStore.updateUser { $0.isDesktopLyricsEnabled = isOn }
    }
    addSection(
      footer: L10n.tr(
        "Show the current lyric line in a floating window above all other windows. Drag it to move it."
      ),
      rows: [desktopLyricsRow]
    )

    let fontSizes = DesktopLyricsFontSize.allCases
    let fontSizeTitles = fontSizes.map(\.description)
    let fontSizeIndex = fontSizes.firstIndex(of: user.desktopLyricsFontSize) ?? 0
    let fontSizeRow = makePopupRow(
      title: L10n.tr("Desktop Lyrics Font Size"),
      titles: fontSizeTitles,
      selectedIndex: fontSizeIndex
    ) { index in
      guard index >= 0, index < fontSizes.count else { return }
      let fontSize = fontSizes[index]
      SettingsStore.updateUser { $0.desktopLyricsFontSize = fontSize }
    }

    let alignments = DesktopLyricsAlignment.allCases
    let alignmentTitles = alignments.map(\.description)
    let alignmentIndex = alignments.firstIndex(of: user.desktopLyricsAlignment) ?? 0
    let alignmentRow = makePopupRow(
      title: L10n.tr("Alignment"),
      titles: alignmentTitles,
      selectedIndex: alignmentIndex
    ) { index in
      guard index >= 0, index < alignments.count else { return }
      let alignment = alignments[index]
      SettingsStore.updateUser { $0.desktopLyricsAlignment = alignment }
    }

    let opacityRow = makeSliderRow(
      title: L10n.tr("Background Opacity"),
      value: Double(user.desktopLyricsBackgroundOpacity),
      range: 0 ... 100,
      step: 1,
      sliderWidth: 160,
      valueFormatter: { value in
        let percent = Int(value.rounded())
        return percent == 0 ? L10n.tr("Transparent") : "\(percent)%"
      }
    ) { value in
      SettingsStore.updateUser {
        $0.desktopLyricsBackgroundOpacity = Int(value.rounded())
      }
    }

    let nextLineRow = makeSwitchRow(
      title: L10n.tr("Show Next Line"),
      isOn: user.isDesktopLyricsNextLineShown
    ) { isOn in
      SettingsStore.updateUser { $0.isDesktopLyricsNextLineShown = isOn }
    }

    let alwaysOnTopRow = makeSwitchRow(
      title: L10n.tr("Always on Top"),
      isOn: user.isDesktopLyricsAlwaysOnTop
    ) { isOn in
      SettingsStore.updateUser { $0.isDesktopLyricsAlwaysOnTop = isOn }
    }

    addSection(
      header: L10n.tr("Options"),
      footer: L10n
        .tr("At 0% the background is fully transparent and only the lyrics remain."),
      rows: [
        fontSizeRow,
        alignmentRow,
        opacityRow,
        nextLineRow,
        alwaysOnTopRow,
      ]
    )

    let lockRow = makeSwitchRow(
      title: L10n.tr("Lock Desktop Lyrics"),
      isOn: user.isDesktopLyricsLocked
    ) { isOn in
      SettingsStore.updateUser { $0.isDesktopLyricsLocked = isOn }
    }
    addSection(
      footer: L10n.tr("Lock the desktop lyrics in place and let mouse clicks pass through."),
      rows: [lockRow]
    )
  }
}
