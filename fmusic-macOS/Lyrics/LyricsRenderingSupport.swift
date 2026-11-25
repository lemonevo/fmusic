//
//  LyricsRenderingSupport.swift
//  fmusic-macOS
//
//  Shared lyric rendering primitives for the desktop lyrics overlay.
//
//  The Catalyst app keeps these in `fmusic/Screens/View/Lyrics/LyricsLineLayers.swift`
//  (UIKit flavour). This is the AppKit port used by fmusic-macOS/Lyrics:
//
//    line    -> the panel (height, emphasis lift, arrival/departure motion)
//    syllable -> LyricsSyllableMaskLayer (which glyphs are sung at this instant)
//    glyph    -> pre-rasterized text images (never re-laid out while the clock runs)
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
import CoreGraphics
import fmusicKit

// MARK: - LyricsSyllableTiming

/// One syllable of a line, already mapped onto the rendered string.
struct LyricsSyllableTiming: Equatable {
  let start: TimeInterval
  let end: TimeInterval
  /// UTF-16 range inside `LyricsLine.value`, i.e. the text that is actually drawn.
  let range: NSRange
  /// True when this cue came from word-level timing (YRC). Such cues are their
  /// own motion unit; only LRC's synthetic per-character timings get regrouped
  /// into words.
  let isWordTimed: Bool

  init(
    start: TimeInterval,
    end: TimeInterval,
    range: NSRange,
    isWordTimed: Bool = false
  ) {
    self.start = start
    self.end = end
    self.range = range
    self.isWordTimed = isWordTimed
  }

  var duration: TimeInterval { max(0, end - start) }

  func progress(at seconds: TimeInterval) -> CGFloat {
    let duration = end - start
    guard duration > 0.001 else { return seconds >= end ? 1 : 0 }
    return CGFloat(min(max((seconds - start) / duration, 0), 1))
  }

  /// Sustained-note glow intensity (0...1), inspired by LyricsX-Next:
  /// activates above ~0.45 s, clearly visible around 1.0 s, peaks at ~1.6 s,
  /// with a smooth attack and gentle release after the note ends.
  func glowIntensity(at seconds: TimeInterval) -> CGFloat {
    guard isWordTimed else { return 0 }
    let dur = duration
    guard dur > 0.45 else { return 0 }
    let durationFactor = CGFloat(min(max((dur - 0.45) / (1.60 - 0.45), 0), 1))
    let p = progress(at: seconds)
    guard p > 0.001 else { return 0 }
    if seconds <= end {
      let attack = min(p / 0.25, 1)
      return durationFactor * attack
    } else {
      let decay = CGFloat(max(0, 1 - (seconds - end) / 0.30))
      return durationFactor * decay
    }
  }
}

// MARK: - LyricsTimingMap

enum LyricsTimingMap {
  /// Estimated time a line stays highlighted. Font metrics are not available here, so the
  /// duration comes from the character count and the gap to the next timestamp. The next
  /// timestamp is resolved in one reverse pass instead of scanning forward per line.
  static func estimatedDurations(for lines: [LyricsLine]) -> [Double] {
    var result = [Double](repeating: 0, count: lines.count)
    var nextStart: Int?
    for index in lines.indices.reversed() {
      let line = lines[index]
      let characterCount = line.value.reduce(0) { $0 + ($1.isWhitespace ? 0 : 1) }
      let estimated = max(Double(characterCount) * 0.36, 0.4)
      if let start = line.start, let upcomingStart = nextStart {
        let gap = Double(upcomingStart - start) / 1_000
        result[index] = gap > 0 ? max(0.4, min(estimated, gap * 0.9)) : estimated
      } else {
        result[index] = estimated
      }
      if let start = line.start { nextStart = start }
    }
    return result
  }

  /// Maps word timings onto the displayed characters. YRC words concatenate to the line,
  /// so ranges are exact; if they ever diverge the words share the line proportionally.
  /// LRC has no word data, so characters get an even share of the estimated duration.
  static func syllables(
    for line: LyricsLine,
    estimatedDuration: TimeInterval
  )
    -> [LyricsSyllableTiming] {
    let text = line.value as NSString
    guard text.length > 0, let lineStart = line.start else { return [] }
    let start = Double(lineStart) / 1_000

    if !line.words.isEmpty {
      return wordSyllables(line.words, textLength: text.length)
    }

    let duration = max(estimatedDuration, 0.4)
    var characterRanges = [NSRange]()
    var index = 0
    while index < text.length {
      let range = text.rangeOfComposedCharacterSequence(at: index)
      characterRanges.append(range)
      index = range.location + range.length
    }
    guard !characterRanges.isEmpty else { return [] }

    let step = duration / Double(characterRanges.count)
    return characterRanges.enumerated().map { offset, range in
      LyricsSyllableTiming(
        start: start + (Double(offset) * step),
        end: start + (Double(offset + 1) * step),
        range: range
      )
    }
  }

  private static func wordSyllables(
    _ words: [LyricWord],
    textLength: Int
  )
    -> [LyricsSyllableTiming] {
    var ranges = [NSRange]()
    var offset = 0
    for word in words {
      let length = (word.value as NSString).length
      ranges.append(NSRange(location: offset, length: length))
      offset += length
    }

    if offset != textLength {
      ranges = proportionalRanges(lengths: ranges.map(\.length), total: textLength)
    }

    var result = [LyricsSyllableTiming]()
    for (index, word) in words.enumerated() {
      let range = ranges[index]
      guard range.length > 0 else { continue }
      let start = Double(word.start) / 1_000
      let end = max(Double(word.end) / 1_000, start + 0.02)
      result.append(LyricsSyllableTiming(
        start: start,
        end: end,
        range: range,
        isWordTimed: true
      ))
    }
    return result
  }

  private static func proportionalRanges(lengths: [Int], total: Int) -> [NSRange] {
    let sum = lengths.reduce(0, +)
    guard sum > 0 else { return lengths.map { _ in NSRange(location: 0, length: 0) } }
    var result = [NSRange]()
    var consumed = 0
    var cursor = 0
    for length in lengths {
      consumed += length
      let end = Int((Double(consumed) / Double(sum) * Double(total)).rounded())
      result.append(NSRange(location: cursor, length: max(0, end - cursor)))
      cursor = end
    }
    return result
  }
}

// MARK: - LyricsTextLayout

/// TextKit layout shared by drawing and by the syllable mask, so the mask can never
/// drift away from the glyphs it is supposed to reveal.
@MainActor
final class LyricsTextLayout {
  static let maxLines = 5

  let storage: NSTextStorage
  let manager: NSLayoutManager
  let container: NSTextContainer

  init(
    text: NSAttributedString,
    width: CGFloat,
    maximumNumberOfLines: Int = LyricsTextLayout.maxLines,
    lineBreakMode: NSLineBreakMode = .byWordWrapping
  ) {
    self.storage = NSTextStorage(attributedString: text)
    self.manager = NSLayoutManager()
    self.container = NSTextContainer(
      size: CGSize(width: max(width, 1), height: CGFloat.greatestFiniteMagnitude)
    )
    container.lineFragmentPadding = 0
    container.maximumNumberOfLines = maximumNumberOfLines
    container.lineBreakMode = lineBreakMode
    storage.addLayoutManager(manager)
    manager.addTextContainer(container)
    manager.ensureLayout(for: container)
  }

  var height: CGFloat {
    ceil(manager.usedRect(for: container).height)
  }

  /// Rectangles (TextKit coordinates, origin top-left) covered by a UTF-16 range. A range
  /// that wraps returns one rectangle per visual line fragment.
  func rects(for range: NSRange) -> [CGRect] {
    guard range.length > 0,
          range.location >= 0,
          range.location + range.length <= storage.length
    else { return [] }
    let glyphRange = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
    guard glyphRange.length > 0 else { return [] }
    var result = [CGRect]()
    manager.enumerateEnclosingRects(
      forGlyphRange: glyphRange,
      withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
      in: container
    ) { rect, _ in
      if rect.width > 0.01, rect.height > 0.01 {
        result.append(rect)
      }
    }
    return result
  }

  func draw() {
    guard manager.numberOfGlyphs > 0 else { return }
    manager.drawGlyphs(
      forGlyphRange: NSRange(location: 0, length: manager.numberOfGlyphs),
      at: .zero
    )
  }

  /// Draws with a different ink or shadow. Both are presentation-only attributes,
  /// so the glyph layout is reused instead of built again for every variant.
  func draw(foregroundColor: NSColor, shadow: NSShadow?) {
    guard storage.length > 0 else { return }
    let range = NSRange(location: 0, length: storage.length)
    storage.beginEditing()
    storage.addAttribute(.foregroundColor, value: foregroundColor, range: range)
    if let shadow {
      storage.addAttribute(.shadow, value: shadow, range: range)
    } else {
      storage.removeAttribute(.shadow, range: range)
    }
    storage.endEditing()
    draw()
  }
}

// MARK: - LyricsRasterizer

/// Off-screen text rasterization for the lyrics overlay.
///
/// `NSBitmapImageRep` is used instead of a layer-backed view so a line can be rendered
/// once (per ink variant) and then only its mask sublayers move while the clock runs.
@MainActor
enum LyricsRasterizer {
  /// Renders the layout into a transparent bitmap of `size` (points) at `scale`.
  /// The resulting `CGImage` is upright: TextKit reports glyph boxes from the top of the
  /// text block, so the context is flipped here exactly like `UIGraphicsImageRenderer`
  /// does on the Catalyst side.
  static func image(
    layout: LyricsTextLayout,
    size: CGSize,
    scale: CGFloat,
    origin: CGPoint = .zero,
    foregroundColor: NSColor? = nil,
    shadow: NSShadow? = nil
  )
    -> CGImage? {
    guard size.width > 0, size.height > 0, scale > 0 else { return nil }
    let pixelWidth = max(1, Int((size.width * scale).rounded(.up)))
    let pixelHeight = max(1, Int((size.height * scale).rounded(.up)))
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let cgContext = CGContext(
      data: nil,
      width: pixelWidth,
      height: pixelHeight,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: bitmapInfo
    )
    else { return nil }

    // The context is *declared* flipped (top-left origin, y down) and the CTM is flipped
    // to match, exactly like a flipped NSView. TextKit then draws the layout top-down
    // into the bitmap; without the `flipped: true` marker AppKit would compensate again
    // and the rasterized glyphs would be mirrored.
    let context = NSGraphicsContext(cgContext: cgContext, flipped: true)
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = context

    cgContext.clear(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
    // Bitmap contexts are in pixels; scale up so all drawing stays in points.
    cgContext.scaleBy(x: scale, y: scale)
    cgContext.translateBy(x: 0, y: size.height)
    cgContext.scaleBy(x: 1, y: -1)
    cgContext.translateBy(x: origin.x, y: origin.y)

    if let foregroundColor {
      layout.draw(foregroundColor: foregroundColor, shadow: shadow)
    } else {
      layout.draw()
    }
    return cgContext.makeImage()
  }
}

// MARK: - LyricsSyllableMaskLayer

/// Reveals the sung glyphs. Every syllable owns gradient sublayers; the clock only
/// changes their widths, never the text layout.
final class LyricsSyllableMaskLayer: CALayer {
  private struct Entry {
    let syllableIndex: Int
    let rect: CGRect
    let layer: CAGradientLayer
  }

  private var entries = [Entry]()
  private var syllableRects = [[CGRect]]()

  private static let white = CGColor(gray: 1, alpha: 1)
  private static let clear = CGColor(gray: 1, alpha: 0)
  private static let feather: CGFloat = 2.5

  override init() {
    super.init()
    masksToBounds = false
    isOpaque = false
  }

  /// Core Animation copies a layer to build its presentation layer for implicit
  /// animations; a subclass without this initializer traps.
  override init(layer: Any) {
    super.init(layer: layer)
    if let other = layer as? LyricsSyllableMaskLayer {
      self.syllableRects = other.syllableRects
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func setFrameWithoutAnimation(_ newFrame: CGRect) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    frame = newFrame
    CATransaction.commit()
  }

  func update(rects: [[CGRect]]) {
    guard rects != syllableRects else { return }
    syllableRects = rects
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    entries.forEach { $0.layer.removeFromSuperlayer() }
    entries = rects.enumerated().flatMap { syllableIndex, syllableRectangles in
      syllableRectangles.map { rect in
        let layer = CAGradientLayer()
        layer.startPoint = CGPoint(x: 0, y: 0.5)
        layer.endPoint = CGPoint(x: 1, y: 0.5)
        layer.colors = [Self.white, Self.white]
        layer.locations = [0, 1]
        layer.frame = rect
        layer.isHidden = true
        addSublayer(layer)
        return Entry(syllableIndex: syllableIndex, rect: rect, layer: layer)
      }
    }
    CATransaction.commit()
  }

  func apply(progress: [CGFloat]) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for entry in entries {
      let value = entry.syllableIndex < progress.count ? progress[entry.syllableIndex] : 0
      let layer = entry.layer
      let rect = entry.rect
      guard value > 0.001 else {
        layer.isHidden = true
        continue
      }
      layer.isHidden = false
      if value >= 0.999 {
        layer.frame = rect
        layer.colors = [Self.white, Self.white]
        layer.locations = [0, 1]
      } else {
        let filled = max(0.5, rect.width * value)
        let feather = min(Self.feather, filled)
        layer.frame = CGRect(
          x: rect.minX,
          y: rect.minY,
          width: filled + feather,
          height: rect.height
        )
        let stop = NSNumber(value: Float(filled / (filled + feather)))
        layer.colors = [Self.white, Self.white, Self.clear]
        layer.locations = [0, stop, 1]
      }
    }
    CATransaction.commit()
  }

  func reset() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    entries.forEach { $0.layer.isHidden = true }
    CATransaction.commit()
  }
}

// MARK: - LyricsGlowMaskLayer

/// Reveals a soft, feathered glow raster only behind sustained-note syllables whose
/// `glowIntensity(at:)` is above zero. Uses a radial gradient mask per syllable so
/// the glow hugs the individual glyph smoothly without hard rectangular clipping or
/// bleeding into neighboring characters.
final class LyricsGlowMaskLayer: CALayer {
  private struct Entry {
    let syllableIndex: Int
    let layer: CAGradientLayer
  }

  private var entries = [Entry]()
  private var syllableRects = [[CGRect]]()
  private static let haloPadding: CGFloat = 6
  private static let white = CGColor(gray: 1, alpha: 1)
  private static let midWhite = CGColor(gray: 1, alpha: 0.75)
  private static let clear = CGColor(gray: 1, alpha: 0)

  override init() {
    super.init()
    masksToBounds = false
    isOpaque = false
  }

  override init(layer: Any) {
    super.init(layer: layer)
    if let other = layer as? LyricsGlowMaskLayer {
      self.syllableRects = other.syllableRects
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func setFrameWithoutAnimation(_ newFrame: CGRect) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    frame = newFrame
    CATransaction.commit()
  }

  func update(rects: [[CGRect]]) {
    guard rects != syllableRects else { return }
    syllableRects = rects
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    entries.forEach { $0.layer.removeFromSuperlayer() }
    entries = rects.enumerated().flatMap { syllableIndex, syllableRectangles in
      syllableRectangles.map { rect in
        let layer = CAGradientLayer()
        layer.type = .radial
        layer.startPoint = CGPoint(x: 0.5, y: 0.5)
        layer.endPoint = CGPoint(x: 1.0, y: 1.0)
        layer.colors = [Self.white, Self.midWhite, Self.clear]
        layer.locations = [0.0, 0.55, 1.0]
        layer.frame = rect.insetBy(dx: -Self.haloPadding, dy: -Self.haloPadding)
        layer.opacity = 0
        layer.isHidden = true
        addSublayer(layer)
        return Entry(syllableIndex: syllableIndex, layer: layer)
      }
    }
    CATransaction.commit()
  }

  func apply(intensities: [CGFloat]) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for entry in entries {
      let value = entry.syllableIndex < intensities.count ? intensities[entry.syllableIndex] : 0
      if value <= 0.005 {
        entry.layer.isHidden = true
        entry.layer.opacity = 0
      } else {
        entry.layer.isHidden = false
        // Cap opacity so the glow stays a crisp luminance around the glyph strokes.
        entry.layer.opacity = Float(min(max(value, 0), 1) * 0.72)
      }
    }
    CATransaction.commit()
  }

  func reset() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for entry in entries {
      entry.layer.isHidden = true
      entry.layer.opacity = 0
    }
    CATransaction.commit()
  }
}
