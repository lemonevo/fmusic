//
//  ArtworkImageLoader.swift
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
import ImageIO

/// Platform-neutral artwork loading shared by the UIKit and AppKit front-ends.
///
/// Both apps render the same cached artwork files and the same generated placeholders,
/// so the decode/downsample/cache logic lives in the core and only returns
/// `PlatformImage` values.
@MainActor
public enum ArtworkImageLoader {
  private static let cache: NSCache<NSString, PlatformImage> = {
    let cache = NSCache<NSString, PlatformImage>()
    cache.countLimit = 300
    cache.totalCostLimit = 64 * 1024 * 1024
    return cache
  }()

  nonisolated private static let maxArtworkPixelSize = 1024

  /// Generated placeholder artwork from the package asset catalog (theme + entity type).
  public static func generatedImage(
    theme: ThemePreference,
    artworkType: ArtworkType
  )
    -> PlatformImage {
    PlatformImages.asset(named: "\(theme.description)\(artworkType.description)")
      ?? PlatformImages.empty
  }

  /// The image to display for a library entity: the cached artwork file when available,
  /// otherwise the generated placeholder for the entity's type.
  public static func image(
    for libraryEntity: AbstractLibraryEntity,
    themePreference: ThemePreference,
    artworkDisplayPreference: ArtworkDisplayPreference,
    useCache: Bool = true
  )
    -> PlatformImage {
    let entityImagePath = libraryEntity.imagePath(setting: artworkDisplayPreference)
    if let entityImagePath, let loaded = image(atPath: entityImagePath, useCache: useCache) {
      return loaded
    }
    return generatedImage(
      theme: themePreference,
      artworkType: libraryEntity.getDefaultArtworkType()
    )
  }

  /// The image for a raw artwork file path (no generated fallback).
  public static func image(atPath path: String, useCache: Bool = true) -> PlatformImage? {
    if useCache, let cached = cache.object(forKey: path as NSString) {
      return cached
    }
    guard let loaded = downsampledImage(atPath: path) else { return nil }
    if useCache {
      cache.setObject(loaded, forKey: path as NSString, cost: decodedCost(of: loaded))
    }
    return loaded
  }

  /// Loads an artwork file off the main thread (for image views that can update later).
  public static func imageAsync(atPath path: String, useCache: Bool = true) async
    -> PlatformImage? {
    if useCache, let cached = cache.object(forKey: path as NSString) {
      return cached
    }
    guard !Task.isCancelled else { return nil }
    let loaded = await Self.loadDownsampledImage(atPath: path)
    guard !Task.isCancelled, let loaded else { return nil }
    if useCache {
      cache.setObject(loaded, forKey: path as NSString, cost: decodedCost(of: loaded))
    }
    return loaded
  }

  /// Clears the shared artwork cache (memory pressure / account switch).
  public static func clearCache() {
    cache.removeAllObjects()
  }

  // MARK: - Decoding

  @concurrent
  private static func loadDownsampledImage(atPath path: String) async -> PlatformImage? {
    downsampledImage(atPath: path)
  }

  nonisolated private static func downsampledImage(atPath path: String) -> PlatformImage? {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
      return nil
    }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: maxArtworkPixelSize,
    ]
    guard let downsampled = CGImageSourceCreateThumbnailAtIndex(
      source,
      0,
      options as CFDictionary
    ) else {
      return PlatformImages.file(atPath: path)
    }
    return PlatformImages.bitmap(cgImage: downsampled)
  }

  nonisolated private static func decodedCost(of image: PlatformImage) -> Int {
    guard let cgImage = image.platformCGImage else { return 0 }
    return cgImage.bytesPerRow * cgImage.height
  }
}
