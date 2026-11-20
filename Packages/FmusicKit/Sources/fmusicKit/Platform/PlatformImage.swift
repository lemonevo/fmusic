//
//  PlatformImage.swift
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
import CoreImage
import Foundation

#if canImport(UIKit)
import UIKit
/// The platform bitmap type: `UIImage` on iOS/iPadOS/Mac Catalyst, `NSImage` on macOS.
public typealias PlatformImage = UIImage
/// The platform color type: `UIColor` on iOS/iPadOS/Mac Catalyst, `NSColor` on macOS.
public typealias PlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
/// The platform bitmap type: `UIImage` on iOS/iPadOS/Mac Catalyst, `NSImage` on macOS.
public typealias PlatformImage = NSImage
/// The platform color type: `UIColor` on iOS/iPadOS/Mac Catalyst, `NSColor` on macOS.
public typealias PlatformColor = NSColor
#endif

// MARK: - PlatformImages

/// Platform-neutral factories for the bitmap types used by the shared core.
///
/// Everything that has to know about UIKit or AppKit to create an image lives here,
/// so the rest of the package never imports a UI framework.
public enum PlatformImages {
  /// An empty image, used as a non-optional fallback where a symbol or asset is missing.
  public static var empty: PlatformImage {
    #if canImport(UIKit)
    return UIImage()
    #else
    return NSImage(size: .zero)
    #endif
  }

  /// A SF Symbol by name.
  @MainActor
  public static func symbol(_ systemName: String) -> PlatformImage {
    #if canImport(UIKit)
    return UIImage(systemName: systemName) ?? empty
    #else
    return NSImage(
      systemSymbolName: systemName,
      accessibilityDescription: nil
    ) ?? empty
    #endif
  }

  /// An image from the package asset catalog.
  @MainActor
  public static func asset(named name: String) -> PlatformImage? {
    #if canImport(UIKit)
    return UIImage(
      named: name,
      in: FmusicKitResources.bundle,
      compatibleWith: nil
    )
    #else
    return FmusicKitResources.bundle.image(forResource: name)
    #endif
  }

  /// An image from the package asset catalog, falling back to an empty image.
  @MainActor
  public static func asset(named name: String, fallback: PlatformImage) -> PlatformImage {
    asset(named: name) ?? fallback
  }

  /// Wraps a `CGImage` into the platform bitmap type.
  public static func bitmap(cgImage: CGImage, scale: CGFloat = 1) -> PlatformImage {
    #if canImport(UIKit)
    return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    #else
    return NSImage(
      cgImage: cgImage,
      size: CGSize(
        width: CGFloat(cgImage.width) / scale,
        height: CGFloat(cgImage.height) / scale
      )
    )
    #endif
  }

  /// Loads an image file from disk (used for the artwork cache).
  public static func file(atPath path: String) -> PlatformImage? {
    #if canImport(UIKit)
    return UIImage(contentsOfFile: path)
    #else
    return NSImage(contentsOfFile: path)
    #endif
  }

  /// Converts a `CGImage` returned by ImageIO into encoded JPEG bytes.
  public static func jpegData(from cgImage: CGImage, quality: CGFloat) -> Data? {
    #if canImport(UIKit)
    return UIImage(cgImage: cgImage).jpegData(compressionQuality: quality)
    #else
    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    return bitmap.representation(
      using: .jpeg,
      properties: [.compressionFactor: quality]
    )
    #endif
  }
}

// MARK: - PlatformImage helpers

public extension PlatformImage {
  /// The underlying bitmap, regardless of the platform image class.
  var platformCGImage: CGImage? {
    #if canImport(UIKit)
    return cgImage
    #else
    var rect = CGRect(origin: .zero, size: size)
    return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    #endif
  }

  /// Logical (point) size of the image.
  var platformSize: CGSize { size }

  /// PNG bytes of the image, if it can be encoded.
  func platformPNGData() -> Data? {
    #if canImport(UIKit)
    return pngData()
    #else
    guard let cgImage = platformCGImage else { return nil }
    return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    #endif
  }

  /// JPEG bytes of the image, if it can be encoded.
  func platformJPEGData(quality: CGFloat) -> Data? {
    #if canImport(UIKit)
    return jpegData(compressionQuality: quality)
    #else
    guard let cgImage = platformCGImage else { return nil }
    return PlatformImages.jpegData(from: cgImage, quality: quality)
    #endif
  }

  /// A copy of the image tinted with `color`, keeping the alpha channel.
  ///
  /// UIKit's `withTintColor(_:)` and AppKit drawing have different semantics, so the
  /// shared core uses this single entry point instead.
  func platformTinted(with color: PlatformColor) -> PlatformImage {
    #if canImport(UIKit)
    return withTintColor(color, renderingMode: .alwaysOriginal)
    #else
    let source = self
    let tinted = NSImage(size: size, flipped: false) { rect in
      source.draw(in: rect)
      color.set()
      rect.fill(using: .sourceAtop)
      return true
    }
    return tinted
    #endif
  }

  /// A copy of the image with all colors inverted (the playback "inverted" artwork).
  func invertedImage() -> PlatformImage {
    #if canImport(UIKit)
    guard let cgImage = cgImage else { return PlatformImage() }
    guard let inverted = Self.invertedCGImage(from: cgImage) else { return PlatformImage() }
    return PlatformImage(cgImage: inverted, scale: scale, orientation: .up)
    #else
    guard let cgImage = platformCGImage else { return PlatformImage(size: .zero) }
    guard let inverted = Self.invertedCGImage(from: cgImage) else {
      return PlatformImage(size: .zero)
    }
    return PlatformImage(cgImage: inverted, size: size)
    #endif
  }

  /// CoreImage based color inversion shared by both platform implementations.
  private static func invertedCGImage(from cgImage: CGImage) -> CGImage? {
    let ciImage = CoreImage.CIImage(cgImage: cgImage)
    guard let filter = CIFilter(name: "CIColorInvert") else { return nil }
    filter.setDefaults()
    filter.setValue(ciImage, forKey: kCIInputImageKey)
    let context = CIContext(options: nil)
    guard let outputImage = filter.outputImage else { return nil }
    return context.createCGImage(outputImage, from: outputImage.extent)
  }
}

// MARK: - PlatformColor helpers

public extension PlatformColor {
  /// An sRGB color built from components, independent of the platform color class.
  static func platform(
    red: CGFloat,
    green: CGFloat,
    blue: CGFloat,
    alpha: CGFloat = 1.0
  ) -> PlatformColor {
    #if canImport(UIKit)
    return UIColor(red: red, green: green, blue: blue, alpha: alpha)
    #else
    return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    #endif
  }

  /// A color from the package asset catalog.
  @MainActor
  static func fmusicAsset(named name: String) -> PlatformColor? {
    #if canImport(UIKit)
    return UIColor(named: name, in: FmusicKitResources.bundle, compatibleWith: nil)
    #else
    return NSColor(named: name, bundle: FmusicKitResources.bundle)
    #endif
  }

  /// The label color that keeps enough contrast on both light and dark backgrounds.
  @MainActor
  static var fmusicHardLabelColor: PlatformColor {
    #if canImport(UIKit)
    return fmusicAsset(named: "hardLabelColor") ?? .label
    #else
    return fmusicAsset(named: "hardLabelColor") ?? .labelColor
    #endif
  }
}
