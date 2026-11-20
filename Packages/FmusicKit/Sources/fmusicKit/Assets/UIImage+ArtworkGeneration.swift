//
//  UIImage+ArtworkGeneration.swift
//  fmusicKit
//
//  Created by Maximilian Bauer on 06.06.22.
//  Copyright (c) 2022 Maximilian Bauer. All rights reserved.
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

#if canImport(UIKit)
import Foundation
import UIKit

extension UIUserInterfaceStyle {
  public var asModeType: LightDarkModeType {
    switch self {
    case .unspecified:
      return .light
    case .light:
      return .light
    case .dark:
      return .dark
    @unknown default:
      return .light
    }
  }
}

@MainActor
public extension fmusicImage {
  /// UIKit alias kept for the existing app code; `asPlatformImage` is the
  /// platform-neutral entry point.
  var asUIImage: UIImage {
    asPlatformImage
  }
}

// MARK: - Generated artwork (UIKit only)

// Everything below builds bitmaps with UIGraphics/UIKit rendering, so it lives
// behind `canImport(UIKit)` and is unavailable to native macOS code (which uses
// the SwiftUI `fmusicImage.asImage` instead).
@MainActor
extension UIImage {
  public static let appIconTemplate = (PlatformImages.asset(named: "Icon-monocolor") ?? UIImage())
    .withRenderingMode(.alwaysTemplate)

  public static func userCircle(withConfiguration: UIImage.SymbolConfiguration? = nil) -> UIImage {
    UIImage(systemName: fmusicImage.account.systemName, withConfiguration: withConfiguration) ??
      UIImage()
  }

  public static func getGeneratedArtwork(
    theme: ThemePreference,
    artworkType: ArtworkType
  )
    -> UIImage {
    let resourceName = "\(theme.description)\(artworkType.description)"
    return PlatformImages.asset(named: resourceName) ?? UIImage()
  }

  public static func generateArtwork(
    theme: ThemePreference,
    lightDarkMode: LightDarkModeType,
    artworkType: ArtworkType
  )
    -> UIImage {
    var generatedArtwork: UIImage?
    switch artworkType {
    case .album, .artist, .folder, .genre, .podcast, .radio:
      generatedArtwork = UIImage.createArtwork(
        with: artworkType.image.asUIImage,
        iconSizeType: .big,
        theme: theme,
        lightDarkMode: lightDarkMode
      )
    case .podcastEpisode, .song:
      generatedArtwork = UIImage.createArtwork(
        with: artworkType.image.asUIImage,
        iconSizeType: .small,
        theme: theme,
        lightDarkMode: lightDarkMode
      )
    case .playlist:
      generatedArtwork = UIImage.createArtwork(
        with: UIImage.playlist,
        iconSizeType: .small,
        theme: theme,
        lightDarkMode: lightDarkMode,
        switchColors: true
      )
    }
    return generatedArtwork ?? UIImage()
  }

  private static func create(_ named: String) -> UIImage {
    PlatformImages.asset(named: named) ?? UIImage()
  }

  fileprivate static func create(systemName: String) -> UIImage {
    PlatformImages.symbol(systemName)
  }

  public static func createArtwork(
    with image: UIImage,
    iconSizeType: ArtworkIconSizeType,
    theme: ThemePreference,
    lightDarkMode: LightDarkModeType,
    switchColors: Bool = false
  )
    -> UIImage {
    let frame = CGRect(
      x: 0,
      y: 0,
      width: ArtworkIconSizeType.defaultSize,
      height: ArtworkIconSizeType.defaultSize
    )
    let buildView = EntityImageView(frame: frame)
    let grayScale = lightDarkMode == .light ? 0.85 : 0.15
    let artworkBackgroundColor = UIColor(
      red: grayScale,
      green: grayScale,
      blue: grayScale,
      alpha: 1
    )
    let imageTintColor = !switchColors ? theme.asColor : artworkBackgroundColor
    let backgroundColor = switchColors ? theme.asColor : artworkBackgroundColor
    buildView.configureStyling(
      image: image,
      imageSizeType: iconSizeType,
      imageTintColor: imageTintColor,
      backgroundColor: backgroundColor
    )
    buildView.layoutIfNeeded()
    return buildView.screenshot ?? UIImage()
  }

  private static func createEmptyImage(with size: CGSize) -> UIImage? {
    UIGraphicsBeginImageContext(size)
    let image = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return image
  }

  public static func numberToImage(number: Int) -> UIImage {
    let fontSize = 40.0
    let textFont = UIFont(name: "Helvetica Bold", size: fontSize)!

    let image = createEmptyImage(with: CGSize(width: 100.0, height: 100.0)) ?? UIImage()
    let scale = UITraitCollection.current.displayScale
    UIGraphicsBeginImageContextWithOptions(image.size, false, scale)

    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .center

    let textFontAttributes = [
      NSAttributedString.Key.font: textFont,
      NSAttributedString.Key.paragraphStyle: paragraphStyle,
      NSAttributedString.Key.foregroundColor: UIColor.lightGray,
    ] as [NSAttributedString.Key: Any]
    image.draw(in: CGRect(origin: CGPoint.zero, size: image.size))

    let textPoint = CGPoint(x: 0.0, y: 50.0 - (fontSize / 2))
    let rect = CGRect(origin: textPoint, size: image.size)
    number.description.draw(in: rect, withAttributes: textFontAttributes)

    let newImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()

    return newImage!
  }
}

// MARK: - PlayerBarIcon

/// Apple Music style player bar icons, fixed 36 x 36 pt images from the fmusicKit catalog.
@MainActor
public enum PlayerBarIcon {
  public static var lyrics: UIImage { image("player_bar_lyrics") }
  public static var queue: UIImage { image("player_bar_queue") }
  public static var airplay: UIImage { image("player_bar_airplay") }
  public static var volume: UIImage { image("player_bar_volume") }

  private static func image(_ name: String) -> UIImage {
    (PlatformImages.asset(named: name) ?? UIImage())
      .withRenderingMode(.alwaysTemplate)
  }
}

#endif
