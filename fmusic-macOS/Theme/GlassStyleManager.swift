//
//  GlassStyleManager.swift
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

extension Notification.Name {
  /// Posted after the global Liquid Glass preset changed.
  static let macGlassStyleChanged = Notification.Name("fmusic.mac.glassStyleChanged")
}

enum GlassMaterialKind {
  case regular
  case clear
}

/// One coherent set of glass parameters shared by every floating surface.
struct GlassStyleConfiguration {
  let material: GlassMaterialKind
  let glassAlpha: CGFloat
  let borderAlpha: CGFloat
  let sheenTopAlpha: CGFloat
  let sheenMidAlpha: CGFloat
  let shadowOpacity: CGFloat
  let shadowRadius: CGFloat
  let shadowOffset: CGSize
  let buttonFillAlpha: CGFloat
  let buttonBorderAlpha: CGFloat
  let buttonShadowOpacity: CGFloat
  /// Scales the user's desktop-lyrics background opacity without making text vanish.
  let desktopLyricsOpacityScale: CGFloat
}

/// App-wide Liquid Glass preset. Persisted independently from the package's
/// user-settings blob because only the AppKit front-end renders these surfaces.
@MainActor
enum GlassStyleManager {
  private static let defaultsKey = "fmusic.mac.glassStyleMode"

  static var mode: GlassStyleMode {
    let raw = UserDefaults.standard.object(forKey: defaultsKey) as? Int
      ?? GlassStyleMode.standard.rawValue
    return GlassStyleMode(rawValue: raw) ?? .standard
  }

  static var configuration: GlassStyleConfiguration {
    switch mode {
    case .soft:
      return GlassStyleConfiguration(
        material: .regular,
        glassAlpha: 1.0,
        borderAlpha: 0.20,
        sheenTopAlpha: 0.34,
        sheenMidAlpha: 0.10,
        shadowOpacity: 0.12,
        shadowRadius: 15,
        shadowOffset: CGSize(width: 0, height: -5),
        buttonFillAlpha: 0.96,
        buttonBorderAlpha: 0.05,
        buttonShadowOpacity: 0.08,
        desktopLyricsOpacityScale: 1.15
      )
    case .standard:
      return GlassStyleConfiguration(
        material: .regular,
        glassAlpha: 1.0,
        borderAlpha: 0.30,
        sheenTopAlpha: 0.24,
        sheenMidAlpha: 0.06,
        shadowOpacity: 0.18,
        shadowRadius: 18,
        shadowOffset: CGSize(width: 0, height: -6),
        buttonFillAlpha: 0.90,
        buttonBorderAlpha: 0.06,
        buttonShadowOpacity: 0.10,
        desktopLyricsOpacityScale: 1.0
      )
    case .translucent:
      return GlassStyleConfiguration(
        material: .clear,
        glassAlpha: 1.0,
        borderAlpha: 0.42,
        sheenTopAlpha: 0.12,
        sheenMidAlpha: 0.02,
        shadowOpacity: 0.20,
        shadowRadius: 20,
        shadowOffset: CGSize(width: 0, height: -6),
        buttonFillAlpha: 0.68,
        buttonBorderAlpha: 0.10,
        buttonShadowOpacity: 0.12,
        desktopLyricsOpacityScale: 0.72
      )
    }
  }

  static func setMode(_ mode: GlassStyleMode) {
    UserDefaults.standard.set(mode.rawValue, forKey: defaultsKey)
    NotificationCenter.default.post(name: .macGlassStyleChanged, object: nil)
  }
}

enum GlassStyleMode: Int, CaseIterable, Sendable {
  case soft
  case standard
  case translucent

  var title: String {
    switch self {
    case .soft: return L10n.tr("Soft")
    case .standard: return L10n.tr("Standard")
    case .translucent: return L10n.tr("Translucent")
    }
  }
}
