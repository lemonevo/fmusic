//
//  MacTheme.swift
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

/// Shared design tokens for the pure-AppKit UI (Apple Music metrics).
@MainActor
enum MacTheme {
  // MARK: - Metrics

  static let sidebarWidth: CGFloat = 210
  static let playerBarHeight: CGFloat = 76
  static let songRowHeight: CGFloat = 40
  /// Matches the Catalyst sidebar list: 13 pt text with 8 pt vertical padding above and
  /// below, i.e. ~38 pt rows (measured from the original window).
  static let sidebarRowHeight: CGFloat = 38
  static let sidebarSectionRowHeight: CGFloat = 34
  static let largeTitleFontSize: CGFloat = 22
  static let titleFontSize: CGFloat = 15
  static let bodyFontSize: CGFloat = 13
  static let secondaryFontSize: CGFloat = 11

  // MARK: - Fonts

  static var largeTitleFont: NSFont { .systemFont(ofSize: largeTitleFontSize, weight: .bold) }
  static var titleFont: NSFont { .systemFont(ofSize: titleFontSize, weight: .regular) }
  static var bodyFont: NSFont { .systemFont(ofSize: bodyFontSize, weight: .regular) }
  static var secondaryFont: NSFont { .systemFont(ofSize: secondaryFontSize, weight: .regular) }
  static var tabularBodyFont: NSFont { .monospacedDigitSystemFont(ofSize: bodyFontSize, weight: .regular) }

  // MARK: - Colors

  static var accentColor: NSColor {
    FmusicKit.shared.storage.settings.accounts.activeSetting.read.themePreference.asColor
  }

  /// The Catalyst app uses `UIColor.secondarySystemBackground` for the sidebar
  /// (SideBarVC) and `UIColor.systemBackground` for the content area. These are
  /// the exact UIKit values expressed as AppKit dynamic colours.
  static var sidebarBackgroundColor: NSColor {
    NSColor(name: nil) { appearance in
      let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      return isDark
        ? NSColor(srgbRed: 0x26 / 255, green: 0x25 / 255, blue: 0x24 / 255, alpha: 1)
        : NSColor(srgbRed: 234 / 255, green: 233 / 255, blue: 232 / 255, alpha: 1)
    }
  }

  static var contentBackgroundColor: NSColor {
    NSColor(name: nil) { appearance in
      let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      return isDark ? NSColor(white: 0.118, alpha: 1) : .white
    }
  }

  static var secondaryTextColor: NSColor { .secondaryLabelColor }

  // MARK: - Appearance

  /// Applies the app-wide appearance mode from the shared settings.
  static func applyAppearanceMode() {
    switch FmusicKit.shared.storage.settings.user.appearanceMode {
    case .unspecified:
      NSApp.appearance = nil
    case .light:
      NSApp.appearance = NSAppearance(named: .aqua)
    case .dark:
      NSApp.appearance = NSAppearance(named: .darkAqua)
    }
  }
}

// MARK: - Notifications

extension Notification.Name {
  /// Posted when the account's theme colour changed (settings window).
  static let macThemeColorChanged = Notification.Name("fmusic.mac.themeColorChanged")
  /// Posted after the app-wide light/dark appearance was applied.
  static let macAppearanceChanged = Notification.Name("fmusic.mac.appearanceChanged")
  /// Posted when playback related user settings (volume, …) changed.
  static let macPlaybackSettingsChanged = Notification.Name(
    "fmusic.mac.playbackSettingsChanged"
  )
}

// MARK: - ThemedRowView

/// Table row view with a rounded selection plate. The sidebar and library lists in the
/// Catalyst app select with a neutral grey (measured 66,64,64 in dark mode), not with
/// the theme accent, so the plate uses a semantic fill instead of `accentColor`.
final class ThemedRowView: NSTableRowView {
  var cornerRadius: CGFloat = 6
  var horizontalInset: CGFloat = 6
  /// Whether to tint the plate with the theme accent (used by pages that want it).
  var usesAccentColor = false

  override func drawSelection(in dirtyRect: NSRect) {
    guard selectionHighlightStyle != .none else { return }
    let rect = bounds.insetBy(dx: horizontalInset, dy: 2)
    let color = usesAccentColor
      ? MacTheme.accentColor.withAlphaComponent(isEmphasized ? 0.22 : 0.14)
      : NSColor.labelColor.withAlphaComponent(isEmphasized ? 0.13 : 0.09)
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
  }
}
