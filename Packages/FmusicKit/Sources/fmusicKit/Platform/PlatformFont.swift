//
//  PlatformFont.swift
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

import CoreGraphics
import Foundation

#if canImport(UIKit)
import UIKit
/// The platform font type: `UIFont` on iOS/iPadOS/Mac Catalyst, `NSFont` on macOS.
public typealias PlatformFont = UIFont
#elseif canImport(AppKit)
import AppKit
/// The platform font type: `UIFont` on iOS/iPadOS/Mac Catalyst, `NSFont` on macOS.
public typealias PlatformFont = NSFont
#endif

// MARK: - PlatformFontWeight

/// Platform-neutral font weight, mapped to `UIFont.Weight` / `NSFont.Weight`.
public enum PlatformFontWeight: Sendable {
  case ultraLight
  case thin
  case light
  case regular
  case medium
  case semibold
  case bold
  case heavy
  case black
}

// MARK: - PlatformFonts

/// Platform-neutral font factories. The UI layers (UIKit iOS app and AppKit macOS app)
/// use these so shared metrics/typography code never has to import a UI framework.
public enum PlatformFonts {
  /// The system font at the given point size.
  public static func system(size: CGFloat, weight: PlatformFontWeight = .regular) -> PlatformFont {
    #if canImport(UIKit)
    return UIFont.systemFont(ofSize: size, weight: weight.uiFontWeight)
    #elseif canImport(AppKit)
    return NSFont.systemFont(ofSize: size, weight: weight.nsFontWeight)
    #endif
  }

  /// The system font at the given point size with tabular (monospaced) digits.
  public static func tabularDigits(size: CGFloat, weight: PlatformFontWeight = .regular)
    -> PlatformFont {
    #if canImport(UIKit)
    return .monospacedDigitSystemFont(ofSize: size, weight: weight.uiFontWeight)
    #elseif canImport(AppKit)
    return .monospacedDigitSystemFont(ofSize: size, weight: weight.nsFontWeight)
    #endif
  }

  /// The bold variant of the system font at the given point size.
  public static func systemBold(size: CGFloat) -> PlatformFont {
    system(size: size, weight: .bold)
  }
}

#if canImport(UIKit)
extension PlatformFontWeight {
  var uiFontWeight: UIFont.Weight {
    switch self {
    case .ultraLight: return .ultraLight
    case .thin: return .thin
    case .light: return .light
    case .regular: return .regular
    case .medium: return .medium
    case .semibold: return .semibold
    case .bold: return .bold
    case .heavy: return .heavy
    case .black: return .black
    }
  }
}
#elseif canImport(AppKit)
extension PlatformFontWeight {
  var nsFontWeight: NSFont.Weight {
    switch self {
    case .ultraLight: return .ultraLight
    case .thin: return .thin
    case .light: return .light
    case .regular: return .regular
    case .medium: return .medium
    case .semibold: return .semibold
    case .bold: return .bold
    case .heavy: return .heavy
    case .black: return .black
    }
  }
}
#endif
