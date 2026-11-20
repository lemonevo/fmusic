//
//  AppearanceMode.swift
//  fmusicKit
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

import Foundation

/// Platform-independent replacement for `UIUserInterfaceStyle` in the shared core.
///
/// The raw values match `UIUserInterfaceStyle` on purpose: the value is persisted in
/// the settings JSON as its raw `Int`, so existing settings files keep decoding.
public enum AppearanceMode: Int, CaseIterable, Sendable, Codable {
  case unspecified = 0
  case light = 1
  case dark = 2

  public static let defaultValue: AppearanceMode = .unspecified

  public var description: String {
    switch self {
    case .unspecified: return "System"
    case .light: return "Light"
    case .dark: return "Dark"
    }
  }
}

#if canImport(UIKit)
import UIKit

extension AppearanceMode {
  /// Maps the system style to the persisted appearance mode.
  public init(userInterfaceStyle: UIUserInterfaceStyle) {
    switch userInterfaceStyle {
    case .unspecified: self = .unspecified
    case .light: self = .light
    case .dark: self = .dark
    @unknown default: self = .unspecified
    }
  }

  /// The UIKit style matching this appearance mode.
  public var uiUserInterfaceStyle: UIUserInterfaceStyle {
    switch self {
    case .unspecified: return .unspecified
    case .light: return .light
    case .dark: return .dark
    }
  }
}
#endif
