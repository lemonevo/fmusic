//
//  ArtworkGradientBackgroundView.swift
//  fmusic-macOS
//
//  Theme/artwork coloured vertical gradient used behind the now playing page
//  (mirrors the Catalyst player's dominant-colour background).
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
import QuartzCore
import fmusicKit

/// Background view that paints a vertical gradient from the artwork's dominant
/// colour (tinted for the current appearance) down to the content background.
@MainActor
final class ArtworkGradientBackgroundView: NSView {
  private let gradientLayer = CAGradientLayer()
  private var baseColor: NSColor = NSColor(white: 0.5, alpha: 1)

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    gradientLayer.startPoint = CGPoint(x: 0.5, y: 1)
    gradientLayer.endPoint = CGPoint(x: 0.5, y: 0)
    layer?.addSublayer(gradientLayer)
    rebuildGradient()
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    gradientLayer.frame = bounds
    CATransaction.commit()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    rebuildGradient()
  }

  /// Updates the gradient from the current artwork (falls back to the theme colour).
  func apply(artwork: NSImage?, accent: NSColor) {
    baseColor = Self.averageColor(of: artwork) ?? accent
    rebuildGradient()
  }

  private func rebuildGradient() {
    let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    var tinted = baseColor
    if isDark {
      tinted = tinted.blended(withFraction: 0.4, of: .black) ?? tinted
    } else {
      tinted = tinted.blended(withFraction: 0.55, of: .white) ?? tinted
    }

    effectiveAppearance.performAsCurrentDrawingAppearance {
      gradientLayer.colors = [
        tinted.cgColor,
        MacTheme.contentBackgroundColor.cgColor,
      ]
    }
  }

  // MARK: - Colour extraction

  /// Average colour of the artwork, computed by drawing it into a 1×1 bitmap.
  static func averageColor(of image: NSImage?) -> NSColor? {
    guard let image else { return nil }
    guard let representation = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: 1,
      pixelsHigh: 1,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 4,
      bitsPerPixel: 32
    ) else { return nil }
    representation.size = NSSize(width: 1, height: 1)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let context = NSGraphicsContext(bitmapImageRep: representation) else {
      return nil
    }
    NSGraphicsContext.current = context
    image.draw(
      in: NSRect(x: 0, y: 0, width: 1, height: 1),
      from: NSRect(origin: .zero, size: image.size),
      operation: .copy,
      fraction: 1
    )
    context.flushGraphics()
    return representation.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB)
  }
}
