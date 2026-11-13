//
//  LyricsLineLayers.swift
//  fmusic
//
//  Three-layer lyric rendering, following Apple Music's split:
//    line    -> the table cell (position, scroll, emphasis)
//    syllable-> LyricsSyllableMaskLayer (which glyphs are sung right now)
//    glyph   -> LyricsGlyphView (text rasterization; never re-laid out per tick)
//

import fmusicKit
import UIKit

// MARK: - Timeline -> displayed text

/// One syllable of a line, already mapped onto the rendered string.
struct LyricsSyllableTiming {
  let start: TimeInterval
  let end: TimeInterval
  /// UTF-16 range inside `LyricsLine.value`, i.e. the text that is actually drawn.
  let range: NSRange

  func progress(at seconds: TimeInterval) -> CGFloat {
    let duration = end - start
    guard duration > 0.001 else { return seconds >= end ? 1 : 0 }
    return CGFloat(min(max((seconds - start) / duration, 0), 1))
  }
}

enum LyricsTimingMap {
  /// Estimated time a line stays highlighted. Font metrics are not available here, so the
  /// duration comes from the character count and the gap to the next timestamp.
  static func estimatedDurations(for lines: [LyricsLine]) -> [Double] {
    lines.indices.map { index in
      let line = lines[index]
      let characterCount = line.value.reduce(0) { $0 + ($1.isWhitespace ? 0 : 1) }
      let estimated = Double(characterCount) * 0.36
      guard let start = line.start else { return max(estimated, 0.4) }
      let nextStart = lines[(index + 1)...].first(where: { $0.start != nil })?.start
      guard let nextStart else { return max(estimated, 0.4) }
      let gap = Double(nextStart - start) / 1_000
      guard gap > 0 else { return max(estimated, 0.4) }
      return max(0.4, min(estimated, gap * 0.9))
    }
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
      result.append(LyricsSyllableTiming(start: start, end: end, range: range))
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

// MARK: - Glyph layout

/// TextKit layout shared by drawing and by the syllable mask, so the mask can never
/// drift away from the glyphs it is supposed to reveal.
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
    storage = NSTextStorage(attributedString: text)
    manager = NSLayoutManager()
    container = NSTextContainer(
      size: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude)
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

  /// Rectangles (view coordinates) covered by a UTF-16 range. A range that wraps
  /// returns one rectangle per visual line fragment.
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
}

// MARK: - Glyph layer

/// Draws an attributed string through TextKit. The layout is built once per width and
/// never rebuilt while the clock advances, so the fill can move at display rate.
final class LyricsGlyphView: UIView {
  private(set) var layout: LyricsTextLayout?
  private var layoutWidth: CGFloat = 0

  var text: NSAttributedString? {
    didSet {
      // New text means new glyphs: drop the cached layout so the next width query rebuilds it.
      layout = nil
      layoutWidth = 0
      setNeedsDisplay()
    }
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    isOpaque = false
    isUserInteractionEnabled = false
    contentMode = .redraw
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func updateLayoutIfNeeded(width: CGFloat) {
    guard width > 0 else { return }
    guard layout == nil || abs(width - layoutWidth) > 0.5 else { return }
    layoutWidth = width
    layout = text.map { LyricsTextLayout(text: $0, width: width) }
    invalidateIntrinsicContentSize()
    setNeedsDisplay()
  }

  var measuredHeight: CGFloat {
    layout?.height ?? 0
  }

  func rects(for range: NSRange) -> [CGRect] {
    layout?.rects(for: range) ?? []
  }

  override func draw(_ rect: CGRect) {
    layout?.draw()
  }
}

// MARK: - Syllable layer

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

  private static let white = UIColor.white.cgColor
  private static let clear = UIColor.white.withAlphaComponent(0).cgColor
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
      syllableRects = other.syllableRects
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
