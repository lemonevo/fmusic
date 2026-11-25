//
//  LyricsSettingsViewController.swift
//  fmusic-macOS
//
//  Native AppKit port of Catalyst `LyricsSettingsView`. Reuses the same
//  `UserSettings` bindings as the previous combined Display page.
//

import AppKit
import fmusicKit

@MainActor
final class LyricsSettingsViewController: SettingsPageViewController {
  init() {
    super.init(title: L10n.tr("Lyrics"))
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func buildForm() {
    let user = SettingsStore.user

    let smoothScrollingRow = makeSwitchRow(
      title: L10n.tr("Lyrics Smooth Scrolling"),
      subtitle: L10n.tr(
        "Lyrics are smoothly scrolled to next line. Deactivating will result in jumping from line to line."
      ),
      isOn: user.isLyricsSmoothScrolling
    ) { isOn in
      SettingsStore.updateUser { $0.isLyricsSmoothScrolling = isOn }
    }
    addSection(header: L10n.tr("Lyrics"), rows: [smoothScrollingRow])

    let desktopLyricsRow = makeSwitchRow(
      title: L10n.tr("Desktop Lyrics"),
      subtitle: L10n.tr(
        "Show the current lyric line in a floating window above all other windows. Drag it to move it."
      ),
      isOn: user.isDesktopLyricsEnabled
    ) { isOn in
      SettingsStore.updateUser { $0.isDesktopLyricsEnabled = isOn }
    }

    let lockRow = makeSwitchRow(
      title: L10n.tr("Lock Desktop Lyrics"),
      subtitle: L10n.tr("Lock the desktop lyrics in place and let mouse clicks pass through."),
      isOn: user.isDesktopLyricsLocked
    ) { isOn in
      SettingsStore.updateUser { $0.isDesktopLyricsLocked = isOn }
    }

    let fontSizes = DesktopLyricsFontSize.allCases
    let fontSizeRow = makePopupRow(
      title: L10n.tr("Desktop Lyrics Font Size"),
      titles: fontSizes.map(\.description),
      selectedIndex: fontSizes.firstIndex(of: user.desktopLyricsFontSize) ?? 0
    ) { index in
      guard index >= 0, index < fontSizes.count else { return }
      SettingsStore.updateUser { $0.desktopLyricsFontSize = fontSizes[index] }
    }

    let alignments = DesktopLyricsAlignment.allCases
    let alignmentRow = makePopupRow(
      title: L10n.tr("Alignment"),
      titles: alignments.map(\.description),
      selectedIndex: alignments.firstIndex(of: user.desktopLyricsAlignment) ?? 0
    ) { index in
      guard index >= 0, index < alignments.count else { return }
      SettingsStore.updateUser { $0.desktopLyricsAlignment = alignments[index] }
    }

    let opacityRow = makeSliderRow(
      title: L10n.tr("Background Opacity"),
      subtitle: L10n.tr("At 0% the background is fully transparent and only the lyrics remain."),
      value: Double(user.desktopLyricsBackgroundOpacity),
      range: 0 ... 100,
      step: 1,
      sliderWidth: 160,
      valueFormatter: { value in
        let percent = Int(value.rounded())
        return percent == 0 ? L10n.tr("Transparent") : "\(percent)%"
      }
    ) { value in
      SettingsStore.updateUser { $0.desktopLyricsBackgroundOpacity = Int(value.rounded()) }
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
      header: L10n.tr("Desktop Lyrics"),
      rows: [
        desktopLyricsRow,
        lockRow,
        fontSizeRow,
        alignmentRow,
        opacityRow,
        nextLineRow,
        alwaysOnTopRow,
      ]
    )

    let menuBarLyricsRow = makeSwitchRow(
      title: L10n.tr("Menu Bar Lyrics"),
      subtitle: L10n.tr(
        "Show the current lyric line in the menu bar. When the menu bar is full, macOS keeps the item in the overflow area."
      ),
      isOn: user.isMenuBarLyricsEnabled
    ) { isOn in
      SettingsStore.updateUser { $0.isMenuBarLyricsEnabled = isOn }
    }
    addSection(header: L10n.tr("Menu Bar Lyrics"), rows: [menuBarLyricsRow])
  }
}
