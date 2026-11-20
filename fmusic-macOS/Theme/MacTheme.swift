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
  static let sidebarRowHeight: CGFloat = 30
  static let sidebarSectionRowHeight: CGFloat = 26
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

  static var sidebarBackgroundColor: NSColor {
    NSColor(name: nil) { appearance in
      let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      return isDark
        ? NSColor(white: 0.12, alpha: 1)
        : NSColor(white: 0.96, alpha: 1)
    }
  }

  static var contentBackgroundColor: NSColor {
    NSColor(name: nil) { appearance in
      let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      return isDark ? NSColor(white: 0.08, alpha: 1) : .white
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

// MARK: - ThemedRowView

/// Table row view that paints the selection with the fmusic theme color instead of
/// the system accent color.
final class ThemedRowView: NSTableRowView {
  var cornerRadius: CGFloat = 6
  var horizontalInset: CGFloat = 6

  override func drawSelection(in dirtyRect: NSRect) {
    guard selectionHighlightStyle != .none else { return }
    let rect = bounds.insetBy(dx: horizontalInset, dy: 2)
    MacTheme.accentColor.withAlphaComponent(isEmphasized ? 0.22 : 0.14).setFill()
    NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
  }
}
