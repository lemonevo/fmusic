//
//  DesktopLyricsWindow.swift
//  fmusic-macOS
//
//  Floating, always-on-top lyrics overlay for macOS, ported to real AppKit from the
//  Catalyst app's runtime-bridged `fmusic/LyricsOverlay/DesktopLyricsWindow.swift`.
//
//  The rendering follows the same three-layer split as LyricsX and Apple Music:
//
//    line     -> the panel (height, emphasis lift, arrival/departure motion)
//    syllable -> LyricsSyllableMaskLayer (which glyphs are sung at this instant)
//    glyph    -> pre-rasterized text images (never re-laid out while the clock runs)
//
//  The playback clock only moves mask sublayers, so the fill can run at the player's
//  60 Hz lyrics timer without re-typesetting anything.
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
import NaturalLanguage
import QuartzCore

// MARK: - DesktopLyricsContent

struct DesktopLyricsContent {
  /// "Title · Artist", shown in the small line at the top-left of the capsule.
  let headerText: String?
  let currentText: String
  let nextText: String?
  let syllables: [LyricsSyllableTiming]
  let syllableProgress: [CGFloat]
}

struct DesktopLyricsStyle: Equatable {
  var pointSize: CGFloat
  /// 0 = fully transparent background, 1 = opaque card
  var backgroundOpacity: Double
  var alignment: DesktopLyricsAlignment
  var showsNextLine: Bool
  /// Continuous greyscale for the control-strip glyphs (0 = white, 1 = black).
  var controlIconBrightness: Double = 0.0
}

/// One snapshot feeds the lyrics-sync panel: a per-song correction on top of
/// the global lyrics offset, mirroring LyricsX Next's overlay offset editor.
struct OverlayOffsetSnapshot {
  let songID: String
  let songMilliseconds: Int
  let globalMilliseconds: Int

  var totalMilliseconds: Int { songMilliseconds + globalMilliseconds }
}

// MARK: - Rendered lines

/// A line whose glyphs are already rasterized. Mask rectangles are in the glyph
/// layer's coordinate space (origin bottom-left) so they can be applied directly.
struct DesktopLyricsLineRender {
  let text: String
  let size: CGSize
  /// Only the per-line fallback needs whole-line images. Word-timed lines are
  /// drawn from their syllable layers, so those rasterizations are skipped.
  let dimImage: CGImage?
  let brightImage: CGImage?
  let syllables: [LyricsSyllableTiming]
  let maskRects: [[CGRect]]
  let syllableRenders: [DesktopLyricsSyllableRender]
  /// Syllable indices grouped by spoken word. LRC only carries line
  /// timestamps, so per-character cues would make every letter pulse on its
  /// own; the word group lets neighbours share one envelope and travel as a
  /// wave, matching LyricsX's WordCue rendering.
  let motionGroups: [[Int]]
}

/// One syllable's glyphs, rasterized on their own so the sung word can float
/// independently. The image is padded for the text shadow; `rect` is the
/// unpadded glyph box in the line's bottom-left coordinate space.
struct DesktopLyricsSyllableRender {
  let index: Int
  let duration: TimeInterval
  let rect: CGRect
  let imageSize: CGSize
  let dimImage: CGImage
  let brightImage: CGImage
  /// Unmasked white silhouette used only as the halo emitter, so the glow
  /// surrounds the whole glyph instead of only the part the wipe revealed.
  let glowImage: CGImage
  let glyphWidth: CGFloat
  let pad: CGFloat
}

struct DesktopLyricsNextRender {
  let text: String
  let image: CGImage
  let height: CGFloat
}

struct DesktopLyricsHeaderRender {
  let text: String
  let image: CGImage
  let height: CGFloat
}

// MARK: - Emphasis envelope

/// Long held notes swell and glow the way LyricsX emphasizes a sustained word.
/// The envelope only affects presentation; the karaoke reveal keeps its own timing.
enum DesktopLyricsEmphasis {
  static func value(progress: CGFloat, duration: TimeInterval) -> CGFloat {
    guard duration > 0.45, progress > 0, progress < 1 else { return 0 }
    let sustained = smooth((duration - 0.45) / 1.15)
    let swell = smoother(progress / 0.42) * (1 - smoother((progress - 0.70) / 0.30))
    return sustained * swell
  }

  static func smooth(_ value: CGFloat) -> CGFloat {
    let t = min(1, max(0, value))
    return t * t * (3 - 2 * t)
  }

  // Zero velocity at both ends, so short notes never kick.
  static func smoother(_ value: CGFloat) -> CGFloat {
    let t = min(1, max(0, value))
    return t * t * t * (t * (t * 6 - 15) + 10)
  }
}

extension DesktopLyricsEmphasis {
  /// LyricsX Next's per-word envelope: a 1.5% grow-in, a small sine bob while
  /// the syllable is being sung, and a stronger lift on sustained notes. Only
  /// scale/lift are returned; the karaoke reveal keeps its own timing.
  static func wave(
    progress: CGFloat,
    duration: TimeInterval,
    lineHeight: CGFloat
  )
    -> (scale: CGFloat, lift: CGFloat) {
    let p = min(1, max(0, progress))
    let grow = 0.985 + 0.015 * smoother(p / 0.22)
    let bob = pow(sin(Double.pi * p), 2) * 0.012
    let emphasis = value(progress: p, duration: duration)
    let scale = grow + CGFloat(bob) + 0.055 * emphasis
    let lift = (0.035 * emphasis + CGFloat(bob) * 0.5) * lineHeight
    return (scale, lift)
  }
}

// MARK: - Ink

/// LyricsX Next resolves the dark-glass palette from the saved primary color:
/// the sung seed stays white, while the unsung seed is clamped to 0.28 linear
/// luminance, i.e. solid #909090. The unsung glyphs are opaque grey rather
/// than translucent white; that, plus the stacked black shadows, is what
/// makes them read much darker than the sung run.
enum DesktopLyricsInk {
  static let sung = NSColor(white: 1, alpha: 1)
  static let unsung = NSColor(white: 144.0 / 255.0, alpha: 1)
  /// 0.85 preview opacity × 0.46 unsung alpha for the secondary surface.
  static let secondary = NSColor(white: 1, alpha: 0.85 * 0.46)
  /// The tight rim LyricsX keeps on the glyph itself; the broad drop shadow
  /// is applied by the layer so it is never clipped by the raster bounds.
  static let tightShadowAlpha: CGFloat = 0.98
  static let tightShadowBlur: CGFloat = 1.1
  static let broadShadowAlpha: Float = 0.7
  static let broadShadowBlur: CGFloat = 5
}

// MARK: - DesktopLyricsRenderer

@MainActor
enum DesktopLyricsRenderer {
  static let panelWidth: CGFloat = 620
  static let horizontalInset: CGFloat = 24
  static let topPadding: CGFloat = 10
  static let bottomPadding: CGFloat = 10
  static let lineGap: CGFloat = 3
  static let headerGap: CGFloat = 6

  static var contentWidth: CGFloat { panelWidth - horizontalInset * 2 }

  /// LyricsX Next's Liquid Glass panel uses one fixed 32pt corner radius.
  static let glassCornerRadius: CGFloat = 32

  // Hover control strip (top-right, appears while the pointer is over the panel).
  // Two rows: transport (open window / previous / play-pause / next) on top,
  // overlay controls (sync / lock / click-through / close) below.
  static let toolbarButtonSize: CGFloat = 30
  static let toolbarButtonSpacing: CGFloat = 2
  static let toolbarPadding: CGFloat = 4
  static let toolbarRowSpacing: CGFloat = 2
  static let toolbarRowCount = 1
  static let toolbarRowButtonCount = 8
  static let toolbarRowWidth = CGFloat(toolbarRowButtonCount) * toolbarButtonSize
    + CGFloat(toolbarRowButtonCount - 1) * toolbarButtonSpacing
  static let toolbarWidth = toolbarRowWidth + toolbarPadding * 2
  static let toolbarHeight = CGFloat(toolbarRowCount) * toolbarButtonSize
    + CGFloat(toolbarRowCount - 1) * toolbarRowSpacing
    + toolbarPadding * 2
  static let toolbarTopInset: CGFloat = 8
  static let toolbarRightInset: CGFloat = 14
  /// The control strip is much shorter than the lyric capsule, so a 32pt
  /// radius there reads as a full pill; ~28% of the height keeps it rounded
  /// without looking like a stadium.
  static var toolbarCornerRadius: CGFloat { 19 }
  static var minPanelHeight: CGFloat { toolbarHeight + 16 }

  static func displayText(_ text: String) -> String {
    text.isEmpty ? "♪" : text
  }

  static func normalizedNextText(_ text: String?) -> String? {
    guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty
    else { return nil }
    return trimmed
  }

  static func nextFontSize(_ style: DesktopLyricsStyle) -> CGFloat {
    // LyricsX previews the next line at nextLineFontSize (12 by default).
    max(11, (style.pointSize * 12 / 26).rounded())
  }

  static func headerFontSize(_ style: DesktopLyricsStyle) -> CGFloat {
    // LyricsX Next's pinned song header is 11 pt; keeping it smaller than the
    // lyric keeps the title row from competing with the current line.
    11
  }

  static func estimatedPanelHeight(style: DesktopLyricsStyle) -> CGFloat {
    let primary = ceil(style.pointSize * 1.34)
    let header = ceil(headerFontSize(style) * 1.35) + headerGap
    let next = style.showsNextLine ? lineGap + ceil(nextFontSize(style) * 1.34) : 0
    return topPadding + bottomPadding + header + primary + next
  }

  // MARK: Line rendering

  static func makeLine(
    text: String,
    syllables: [LyricsSyllableTiming],
    style: DesktopLyricsStyle,
    scale: CGFloat
  )
    -> DesktopLyricsLineRender? {
    let displayText = displayText(text)
    let width = contentWidth
    guard width > 0 else { return nil }

    let font = NSFont.systemFont(ofSize: style.pointSize, weight: .semibold)
    let paragraph = primaryParagraph(style: style)
    let shadow = primaryShadow()
    // One TextKit layout serves both inks. Color and shadow are drawn from the
    // text storage, but neither changes glyph placement, so the expensive
    // layout pass runs once per line instead of once per color variant.
    let text = NSAttributedString(
      string: displayText,
      attributes: primaryAttributes(
        font: font,
        color: DesktopLyricsInk.sung,
        paragraph: paragraph,
        shadow: shadow
      )
    )
    let layout = LyricsTextLayout(
      text: text,
      width: width,
      maximumNumberOfLines: 2,
      lineBreakMode: .byWordWrapping
    )

    let height = max(ceil(layout.height), ceil(fontLineHeight(font)))
    let size = CGSize(width: width, height: height)
    let masks = maskRects(
      for: layout,
      syllables: syllables,
      height: height
    )
    let syllableRenders = makeSyllableRenders(
      text: displayText,
      syllables: syllables,
      maskRects: masks,
      font: font,
      scale: scale
    )
    let dimImage: CGImage?
    let brightImage: CGImage?
    if syllableRenders.isEmpty {
      guard let dim = rasterize(
        layout,
        size: size,
        scale: scale,
        foregroundColor: DesktopLyricsInk.unsung,
        shadow: shadow
      ),
        let bright = rasterize(
          layout,
          size: size,
          scale: scale,
          foregroundColor: DesktopLyricsInk.sung,
          shadow: shadow
        )
      else { return nil }
      dimImage = dim
      brightImage = bright
    } else {
      dimImage = nil
      brightImage = nil
    }

    return DesktopLyricsLineRender(
      text: displayText,
      size: size,
      dimImage: dimImage,
      brightImage: brightImage,
      syllables: syllables,
      maskRects: masks,
      syllableRenders: syllableRenders,
      motionGroups: motionGroups(
        text: displayText,
        syllables: syllables
      )
    )
  }

  /// Re-renders each syllable as its own image so the sung word can scale and
  /// lift without moving the rest of the line. Rendering from the substring
  /// (rather than cropping the line image) keeps the text shadow intact and
  /// never pulls in a neighbor's glyphs.
  private static func makeSyllableRenders(
    text: String,
    syllables: [LyricsSyllableTiming],
    maskRects: [[CGRect]],
    font: NSFont,
    scale: CGFloat
  )
    -> [DesktopLyricsSyllableRender] {
    guard !syllables.isEmpty, syllables.count <= 64 else { return [] }
    let nsText = text as NSString
    let pad: CGFloat = 13
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .left
    paragraph.lineBreakMode = .byClipping
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(
      DesktopLyricsInk.tightShadowAlpha
    )
    shadow.shadowBlurRadius = DesktopLyricsInk.tightShadowBlur
    shadow.shadowOffset = .zero
    var result = [DesktopLyricsSyllableRender]()
    result.reserveCapacity(syllables.count)
    for (index, syllable) in syllables.enumerated() {
      guard index < maskRects.count,
            let rect = maskRects[index].first,
            syllable.range.location >= 0,
            syllable.range.location + syllable.range.length <= nsText.length
      else { continue }
      let part = nsText.substring(with: syllable.range)
      guard !part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else { continue }

      let attributed = NSAttributedString(
        string: part,
        attributes: [
          .font: font,
          .paragraphStyle: paragraph,
          .kern: -0.4,
          .shadow: shadow,
        ]
      )
      let width = max(rect.width + 12, 12)
      let imageSize = CGSize(
        width: ceil(rect.width + pad * 2 + 12),
        height: ceil(rect.height + pad * 2)
      )
      // All three variants share one glyph layout; only ink and shadow differ.
      let layout = LyricsTextLayout(
        text: attributed,
        width: width,
        maximumNumberOfLines: 1,
        lineBreakMode: .byClipping
      )
      let origin = CGPoint(x: pad, y: pad)
      guard let dimImage = rasterize(
        layout,
        size: imageSize,
        scale: scale,
        origin: origin,
        foregroundColor: DesktopLyricsInk.unsung,
        shadow: shadow
      ),
        let brightImage = rasterize(
          layout,
          size: imageSize,
          scale: scale,
          origin: origin,
          foregroundColor: DesktopLyricsInk.sung,
          shadow: shadow
        ),
        let glowImage = rasterize(
          layout,
          size: imageSize,
          scale: scale,
          origin: origin,
          foregroundColor: .white,
          shadow: nil
        )
      else { continue }
      result.append(DesktopLyricsSyllableRender(
        index: index,
        duration: max(syllable.end - syllable.start, 0),
        rect: rect,
        imageSize: imageSize,
        dimImage: dimImage,
        brightImage: brightImage,
        glowImage: glowImage,
        glyphWidth: max(rect.width, 1),
        pad: pad
      ))
    }
    return result
  }

  static func makeNextLine(
    text: String,
    style: DesktopLyricsStyle,
    scale: CGFloat
  )
    -> DesktopLyricsNextRender? {
    guard let text = normalizedNextText(text) else { return nil }
    let width = contentWidth
    guard width > 0 else { return nil }

    let font = NSFont.systemFont(ofSize: nextFontSize(style), weight: .semibold)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = textAlignment(style.alignment)
    paragraph.lineBreakMode = .byTruncatingTail
    paragraph.lineSpacing = 0

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(
      DesktopLyricsInk.tightShadowAlpha
    )
    shadow.shadowBlurRadius = DesktopLyricsInk.tightShadowBlur
    shadow.shadowOffset = .zero

    let attributed = NSAttributedString(
      string: text,
      attributes: [
        .font: font,
        .foregroundColor: DesktopLyricsInk.secondary,
        .paragraphStyle: paragraph,
        .kern: -0.4,
        .shadow: shadow,
      ]
    )
    let layout = LyricsTextLayout(
      text: attributed,
      width: width,
      maximumNumberOfLines: 1,
      lineBreakMode: .byTruncatingTail
    )
    let height = max(ceil(layout.height), ceil(fontLineHeight(font)))
    let size = CGSize(width: width, height: height)
    guard let image = rasterize(layout, size: size, scale: scale) else { return nil }
    return DesktopLyricsNextRender(text: text, image: image, height: height)
  }

  static func makeHeader(
    text: String,
    style: DesktopLyricsStyle,
    scale: CGFloat
  )
    -> DesktopLyricsHeaderRender? {
    guard let text = normalizedNextText(text) else { return nil }
    let width = contentWidth
    guard width > 0 else { return nil }

    let font = NSFont.systemFont(
      ofSize: headerFontSize(style),
      weight: .medium
    )
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .left
    paragraph.lineBreakMode = .byTruncatingTail

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.60)
    shadow.shadowBlurRadius = 1
    shadow.shadowOffset = CGSize(width: 0, height: 1)

    let attributed = NSAttributedString(
      string: text,
      attributes: [
        .font: font,
        .foregroundColor: NSColor.white.withAlphaComponent(0.92),
        .paragraphStyle: paragraph,
        .shadow: shadow,
      ]
    )
    let layout = LyricsTextLayout(
      text: attributed,
      width: width,
      maximumNumberOfLines: 1,
      lineBreakMode: .byTruncatingTail
    )
    let height = max(ceil(layout.height), ceil(fontLineHeight(font)))
    let size = CGSize(width: width, height: height)
    guard let image = rasterize(layout, size: size, scale: scale) else { return nil }
    return DesktopLyricsHeaderRender(text: text, image: image, height: height)
  }

  // MARK: Helpers

  private static func fontLineHeight(_ font: NSFont) -> CGFloat {
    font.ascender - font.descender + font.leading
  }

  private static func primaryParagraph(style: DesktopLyricsStyle) -> NSParagraphStyle {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = textAlignment(style.alignment)
    paragraph.lineBreakMode = .byWordWrapping
    // LyricsX's primaryLineSpacing is 0 by default; SwiftUI adds no extra
    // gap between a wrapped lyric's two rows.
    paragraph.lineSpacing = 0
    return paragraph
  }

  private static func primaryShadow() -> NSShadow {
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(
      DesktopLyricsInk.tightShadowAlpha
    )
    shadow.shadowBlurRadius = DesktopLyricsInk.tightShadowBlur
    shadow.shadowOffset = .zero
    return shadow
  }

  private static func primaryAttributes(
    font: NSFont,
    color: NSColor,
    paragraph: NSParagraphStyle,
    shadow: NSShadow
  )
    -> [NSAttributedString.Key: Any] {
    [
      .font: font,
      .foregroundColor: color,
      .paragraphStyle: paragraph,
      // OverlayLyricsContent applies .tracking(-0.4) to the whole surface.
      .kern: -0.4,
      .shadow: shadow,
    ]
  }

  private static func textAlignment(
    _ alignment: DesktopLyricsAlignment
  )
    -> NSTextAlignment {
    switch alignment {
    case .left: return .left
    case .center: return .center
    case .right: return .right
    }
  }

  private static func rasterize(
    _ layout: LyricsTextLayout,
    size: CGSize,
    scale: CGFloat,
    origin: CGPoint = .zero,
    foregroundColor: NSColor? = nil,
    shadow: NSShadow? = nil
  )
    -> CGImage? {
    LyricsRasterizer.image(
      layout: layout,
      size: size,
      scale: scale,
      origin: origin,
      foregroundColor: foregroundColor,
      shadow: shadow
    )
  }

  /// TextKit reports rectangles from the top of the text block; CALayer uses a
  /// bottom-left origin, so every syllable rectangle is flipped here once.
  private static func maskRects(
    for layout: LyricsTextLayout,
    syllables: [LyricsSyllableTiming],
    height: CGFloat
  )
    -> [[CGRect]] {
    syllables.map { syllable in
      layout.rects(for: syllable.range).map { rect in
        CGRect(
          x: rect.minX,
          y: height - rect.maxY,
          width: rect.width,
          height: rect.height
        )
      }
    }
  }

  /// LRC syllables are single characters. Group them into spoken words so
  /// the wave envelope is shared across a word instead of restarting on
  /// every letter. Word-synced (YRC) lines already have their own cue per
  /// syllable, so they are left alone.
  private static func motionGroups(
    text: String,
    syllables: [LyricsSyllableTiming]
  )
    -> [[Int]] {
    guard !syllables.isEmpty else { return [] }
    if syllables.contains(where: { $0.isWordTimed }) {
      return syllables.indices.map { [$0] }
    }

    let tokenizer = NLTokenizer(unit: .word)
    tokenizer.string = text
    var wordRanges = [NSRange]()
    tokenizer.enumerateTokens(in: text.startIndex ..< text.endIndex) {
      range,
        _ in
      wordRanges.append(NSRange(range, in: text))
      return true
    }
    guard !wordRanges.isEmpty else {
      return syllables.indices.map { [$0] }
    }

    var groups = [[Int]]()
    var current = [Int]()
    var wordIndex = 0
    var currentWord = -1
    for (index, syllable) in syllables.enumerated() {
      let start = syllable.range.location
      let end = start + syllable.range.length
      while wordIndex < wordRanges.count,
            NSMaxRange(wordRanges[wordIndex]) <= start {
        wordIndex += 1
      }
      var matchedWord = -1
      if wordIndex < wordRanges.count {
        let word = wordRanges[wordIndex]
        if word.location < end, NSMaxRange(word) > start {
          matchedWord = wordIndex
        }
      }
      if matchedWord >= 0, matchedWord != currentWord, !current.isEmpty {
        groups.append(current)
        current = []
      }
      if matchedWord >= 0 { currentWord = matchedWord }
      // Spaces and punctuation have no word token; keep them attached to
      // the word they follow so the mask and lift never leave a gap.
      current.append(index)
    }
    if !current.isEmpty { groups.append(current) }
    return groups
  }
}

// MARK: - DesktopLyricsWindow

/// Borderless, non-activating panel that hosts the lyrics overlay. It never becomes
/// key or main, so clicking the overlay (or its control strip) does not activate fmusic.
final class DesktopLyricsWindow: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

/// The lyric panel is nonactivating and cannot become key, so AppKit would otherwise
/// swallow the first click. `acceptsFirstMouse` restores the Catalyst behaviour where
/// the overlay buttons react immediately while another app is frontmost.
final class DesktopLyricsOverlayButton: NSButton {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - DesktopLyricsWindowController

@MainActor
final class DesktopLyricsWindowController: NSObject {
  private static let frameDefaultsKey = "fmusic.desktopLyrics.frame"
  private static let positionLockKey = "fmusic.desktopLyrics.positionLocked"

  // MARK: Window & view

  private let panel: DesktopLyricsWindow
  private let rootView: NSView
  private let rootLayer: CALayer
  private var backgroundView: NSView?
  private var usesGlassMaterial = false

  // MARK: Background chrome

  private let scrimLayer = CAGradientLayer()
  private let solidLayer = CALayer()
  private let borderLayer = CALayer()
  private let contentLayer = CALayer()

  // MARK: Double-buffered primary line

  /// One complete primary-line layer stack. Two alternate so a departing line
  /// keeps its live masks and glow while the incoming line is built.
  private final class PrimarySurface {
    let container = CALayer()
    let base = CALayer()
    let sung = CALayer()
    let syllableMask = LyricsSyllableMaskLayer()
    let syllableContainer = CALayer()
    var syllableBundles: [SyllableLayerBundle] = []
    var motionGroupRuntimes: [MotionGroupRuntime] = []
    var line: DesktopLyricsLineRender?
    var lastProgress: [CGFloat] = []
  }

  private final class SyllableLayerBundle {
    let container: CALayer
    let glow: CALayer
    let bright: CALayer
    let mask: CAGradientLayer
    let glyphWidth: CGFloat
    let imageWidth: CGFloat
    let pad: CGFloat
    let syllableIndex: Int
    let groupRuntimeIndex: Int
    let groupPhase: CGFloat
    let groupDuration: TimeInterval
    // Last presentation state, so ticks where nothing moves skip Core
    // Animation entirely instead of re-setting identical values at 60 Hz.
    var lastScale: CGFloat?
    var lastLift: CGFloat?
    var maskIsFull = false

    init(
      container: CALayer,
      glow: CALayer,
      bright: CALayer,
      mask: CAGradientLayer,
      glyphWidth: CGFloat,
      imageWidth: CGFloat,
      pad: CGFloat,
      syllableIndex: Int,
      groupRuntimeIndex: Int,
      groupPhase: CGFloat,
      groupDuration: TimeInterval
    ) {
      self.container = container
      self.glow = glow
      self.bright = bright
      self.mask = mask
      self.glyphWidth = glyphWidth
      self.imageWidth = imageWidth
      self.pad = pad
      self.syllableIndex = syllableIndex
      self.groupRuntimeIndex = groupRuntimeIndex
      self.groupPhase = groupPhase
      self.groupDuration = groupDuration
    }
  }

  /// One spoken word: its syllables are averaged into a single envelope, and
  /// each member bundle reuses that average instead of recomputing it.
  private final class MotionGroupRuntime {
    let syllableIndices: [Int]
    let duration: TimeInterval
    var bundleIndices: [Int] = []

    init(syllableIndices: [Int], duration: TimeInterval) {
      self.syllableIndices = syllableIndices
      self.duration = duration
    }
  }

  private let surfaceA = PrimarySurface()
  private let surfaceB = PrimarySurface()
  private var currentSurfaceIsA = true
  private var departingSurfaceIsA: Bool?

  private var currentSurface: PrimarySurface {
    currentSurfaceIsA ? surfaceA : surfaceB
  }

  private var departingSurface: PrimarySurface? {
    departingSurfaceIsA.map { $0 ? surfaceA : surfaceB }
  }

  private let nextLayer = CALayer()
  private let headerLayer = CALayer()

  // MARK: Content state

  private var style = DesktopLyricsStyle(
    pointSize: DesktopLyricsFontSize.medium.pointSize,
    backgroundOpacity: 0.74,
    alignment: .defaultValue,
    showsNextLine: true
  )
  private var screenScale: CGFloat = 2
  private var lastContent: DesktopLyricsContent?
  private var nextLine: DesktopLyricsNextRender?
  private var headerLine: DesktopLyricsHeaderRender?
  private var departureHeight: CGFloat = 0
  private var departureToken = 0
  private var isPlaying = false

  // MARK: Hover control strip

  private var toolbarHost: NSView?
  private var toolbarButtons: [DesktopLyricsOverlayButton] = []
  nonisolated(unsafe) private var hoverTimer: Timer?
  private var isToolbarVisible = false
  private var toolbarToken = 0
  private var positionLocked = false
  private var clickThrough = false
  private var applyingClickThrough = false

  // MARK: Locked (click-through) control panel

  private var controlWindow: NSPanel?

  // MARK: Height spring

  private struct ActiveResize {
    let top: CGFloat
    let startHeight: CGFloat
    let height: CGFloat
    let started: CFTimeInterval
    let duration: TimeInterval
  }

  nonisolated(unsafe) private var resizeTimer: Timer?
  private var activeResize: ActiveResize?
  private var isAnimatingResize = false

  // MARK: Lyrics-sync panel

  private var offsetPanel: NSPanel?
  private var offsetSongID: String?
  private var offsetValueField: NSTextField?
  private var offsetDetailField: NSTextField?
  nonisolated(unsafe) private var offsetClickMonitor: Any?

  // MARK: Callbacks

  var onOpenMainWindow: (() -> Void)?
  var onHideDesktopLyrics: (() -> Void)?
  var onClickThroughChanged: ((Bool) -> Void)?
  var onPlayPrevious: (() -> Void)?
  var onPlayNext: (() -> Void)?
  var onTogglePlayPause: (() -> Void)?
  var offsetSnapshot: (() -> OverlayOffsetSnapshot?)?
  var adjustSongOffset: ((String, Int) -> OverlayOffsetSnapshot?)?
  var resetSongOffset: ((String) -> OverlayOffsetSnapshot?)?

  private static let syncButtonIndex = 4
  private static let lockButtonIndex = 5
  private static let clickThroughButtonIndex = 6
  private static let playPauseButtonIndex = 2

  // MARK: - Init

  override init() {
    let panel = DesktopLyricsWindow(
      contentRect: NSRect(origin: .zero, size: CGSize(
        width: DesktopLyricsRenderer.panelWidth,
        height: DesktopLyricsRenderer.estimatedPanelHeight(
          style: DesktopLyricsStyle(
            pointSize: DesktopLyricsFontSize.medium.pointSize,
            backgroundOpacity: 0.74,
            alignment: .defaultValue,
            showsNextLine: true
          )
        )
      )),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    let rootView = NSView(frame: .zero)
    rootView.wantsLayer = true
    panel.contentView = rootView
    self.panel = panel
    self.rootView = rootView
    self.rootLayer = rootView.layer ?? CALayer()
    super.init()

    configureWindow()
    screenScale = Self.currentScreenScale(for: panel)
    installBackground()
    installLayers()
    installToolbar()
    positionLocked = UserDefaults.standard.bool(forKey: Self.positionLockKey)
    setPositionLocked(positionLocked)
    updateToolbarImages()
    updateChrome()
    restoreFrame()

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowDidMove(_:)),
      name: NSWindow.didMoveNotification,
      object: panel
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowDidChangeScreen(_:)),
      name: NSWindow.didChangeScreenNotification,
      object: panel
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(applicationDidResignActive(_:)),
      name: NSApplication.didResignActiveNotification,
      object: nil
    )
  }

  deinit {
    hoverTimer?.invalidate()
    resizeTimer?.invalidate()
    if let offsetClickMonitor {
      NSEvent.removeMonitor(offsetClickMonitor)
    }
    NotificationCenter.default.removeObserver(self)
  }

  // MARK: - Public

  var isVisible: Bool {
    panel.isVisible
  }

  func show() {
    screenScale = Self.currentScreenScale(for: panel)
    // The panel follows the current appearance, which may have flipped while
    // it was hidden, so refresh the chrome before it appears again.
    updateChrome()
    panel.orderFrontRegardless()
    startHoverTracking()
  }

  func hide() {
    stopHoverTracking()
    closeOffsetPanel()
    controlWindow?.orderOut(nil)
    panel.orderOut(nil)
  }

  func setAlwaysOnTop(_ isAlwaysOnTop: Bool) {
    panel.level = isAlwaysOnTop ? .floating : .normal
    controlWindow?.level = NSWindow.Level(rawValue: panel.level.rawValue + 1)
    offsetPanel?.level = NSWindow.Level(rawValue: panel.level.rawValue + 2)
  }

  /// The settings switch "Lock Desktop Lyrics" and the toolbar cursor button
  /// share one state: clicks pass through and the control strip moves into its
  /// own panel so the overlay can still be unlocked or hidden.
  func setLocked(_ locked: Bool) {
    setClickThrough(locked, notify: false)
  }

  func apply(style: DesktopLyricsStyle) {
    guard style != self.style else { return }
    self.style = style
    updateChrome()
    guard let content = lastContent else {
      resizePanel()
      layoutLayers()
      return
    }
    reload(content: content)
  }

  /// Reflects the live player state on the transport row (play icon and, if a
  /// song is playing, that the overlay should be visible).
  func setPlaying(_ playing: Bool) {
    guard playing != isPlaying else { return }
    isPlaying = playing
    updateToolbarImages()
  }

  func update(content: DesktopLyricsContent) {
    if offsetSongID != nil, offsetSnapshot?()?.songID != offsetSongID {
      closeOffsetPanel()
    }
    lastContent = content
    let text = DesktopLyricsRenderer.displayText(content.currentText)
    let nextText = style.showsNextLine
      ? DesktopLyricsRenderer.normalizedNextText(content.nextText)
      : nil
    let headerText = DesktopLyricsRenderer.normalizedNextText(content.headerText)
    let previousNext = nextLine?.text
    // Remember where the preview row actually sat, so a promoted line can
    // grow out of that exact spot instead of popping in at primary size.
    // Store it as a top inset: the panel keeps its top edge while its height
    // changes, so raw layer coordinates shift with a resize.
    let previousContentHeight = contentLayer.bounds.height
    let previousPreviewTop = nextLine == nil
      ? nil
      : previousContentHeight - nextLayer.frame.midY
    let previewScale = DesktopLyricsRenderer.nextFontSize(style)
      / max(style.pointSize, 1)
    var arrival: (promoted: Bool, previewTop: CGFloat?, previewScale: CGFloat)?
    var needsLayout = false

    if (headerText ?? "") != (headerLine?.text ?? "") {
      headerLine = headerText.flatMap {
        DesktopLyricsRenderer.makeHeader(
          text: $0,
          style: style,
          scale: screenScale
        )
      }
      installHeaderImage(animated: isVisible && headerLine != nil)
      needsLayout = true
    }

    // A repeated lyric can keep the same text while carrying new cue times,
    // so compare the syllables too or the old masks keep the previous pass.
    if text != currentSurface.line?.text
      || content.syllables != currentSurface.line?.syllables {
      let animated = isVisible && currentSurface.line != nil
      let promoted = animated && previousNext == text
      let line = DesktopLyricsRenderer.makeLine(
        text: text,
        syllables: content.syllables,
        style: style,
        scale: screenScale
      )
      let target = preparePrimarySurface(animated: animated)
      installPrimary(line, into: target)
      needsLayout = true
      if animated {
        arrival = (promoted, promoted ? previousPreviewTop : nil, previewScale)
      }
    }

    if (nextText ?? "") != (nextLine?.text ?? "") {
      nextLine = nextText.flatMap {
        DesktopLyricsRenderer.makeNextLine(
          text: $0,
          style: style,
          scale: screenScale
        )
      }
      installNextImage(animated: isVisible)
      needsLayout = true
    }

    if needsLayout {
      resizePanel()
      layoutLayers()
    }
    applyProgress(content.syllableProgress)
    if let arrival {
      animateArrival(
        promoted: arrival.promoted,
        previewTop: arrival.previewTop,
        previewScale: arrival.previewScale
      )
    }
  }

  // MARK: - Content installation

  private func reload(content: DesktopLyricsContent) {
    let line = DesktopLyricsRenderer.makeLine(
      text: DesktopLyricsRenderer.displayText(content.currentText),
      syllables: content.syllables,
      style: style,
      scale: screenScale
    )
    nextLine = style.showsNextLine
      ? DesktopLyricsRenderer.normalizedNextText(content.nextText).flatMap {
        DesktopLyricsRenderer.makeNextLine(
          text: $0,
          style: style,
          scale: screenScale
        )
      }
      : nil
    headerLine = DesktopLyricsRenderer.normalizedNextText(content.headerText)
      .flatMap {
        DesktopLyricsRenderer.makeHeader(
          text: $0,
          style: style,
          scale: screenScale
        )
      }
    // A style or screen-scale change rebuilds everything on a clean surface.
    resetSurface(surfaceA)
    resetSurface(surfaceB)
    currentSurfaceIsA = true
    departingSurfaceIsA = nil
    departureHeight = 0
    installPrimary(line, into: surfaceA)
    installNextImage(animated: false)
    installHeaderImage(animated: false)
    resizePanel()
    layoutLayers()
    applyProgress(content.syllableProgress, force: true)
  }

  private func resetSurface(_ surface: PrimarySurface) {
    surface.container.removeAllAnimations()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    surface.container.isHidden = true
    surface.container.opacity = 1
    surface.container.transform = CATransform3DIdentity
    surface.container.zPosition = 2
    surface.base.contents = nil
    surface.sung.contents = nil
    surface.base.isHidden = false
    surface.sung.isHidden = true
    CATransaction.commit()
    surface.syllableMask.reset()
    surface.syllableContainer.sublayers?.forEach { $0.removeFromSuperlayer() }
    surface.syllableBundles.removeAll(keepingCapacity: true)
    surface.motionGroupRuntimes.removeAll(keepingCapacity: true)
    surface.line = nil
    surface.lastProgress = []
  }

  /// Chooses the surface for the incoming line. For an animated line change
  /// the current surface is left untouched so its live wipe and glow can fade
  /// out; the other surface is cleared and reused for the new line.
  private func preparePrimarySurface(animated: Bool) -> PrimarySurface {
    if animated, currentSurface.line != nil {
      let outgoing = currentSurface
      if let departingSurface, departingSurface !== outgoing {
        resetSurface(departingSurface)
      }
      departingSurfaceIsA = currentSurfaceIsA
      startDeparture(of: outgoing)
      currentSurfaceIsA.toggle()
      resetSurface(currentSurface)
      return currentSurface
    }
    resetSurface(currentSurface)
    if let departingSurface, departingSurface !== currentSurface {
      resetSurface(departingSurface)
    }
    departingSurfaceIsA = nil
    departureHeight = 0
    return currentSurface
  }

  private func installPrimary(
    _ line: DesktopLyricsLineRender?,
    into surface: PrimarySurface
  ) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    surface.container.removeAnimation(forKey: "arrival")
    surface.container.removeAnimation(forKey: "arrivalFade")
    surface.container.transform = CATransform3DIdentity
    surface.container.opacity = 1
    surface.container.zPosition = 2
    surface.line = line
    surface.lastProgress = []
    defer { CATransaction.commit() }

    guard let line else {
      surface.container.isHidden = true
      surface.syllableMask.reset()
      clearSyllableLayers(in: surface)
      return
    }
    surface.container.isHidden = false
    if line.syllableRenders.isEmpty {
      guard let dimImage = line.dimImage, let brightImage = line.brightImage
      else {
        surface.container.isHidden = true
        return
      }
      surface.base.contents = line.syllables.isEmpty ? brightImage : dimImage
      surface.base.isHidden = false
      surface.sung.contents = brightImage
      surface.sung.isHidden = line.syllables.isEmpty
      clearSyllableLayers(in: surface)
      surface.syllableMask.update(rects: line.maskRects)
      surface.syllableMask.reset()
    } else {
      surface.base.isHidden = true
      surface.base.contents = nil
      surface.sung.isHidden = true
      surface.sung.contents = nil
      surface.syllableMask.reset()
      installSyllableLayers(line, into: surface)
    }
  }

  private func clearSyllableLayers(in surface: PrimarySurface) {
    surface.syllableBundles.removeAll(keepingCapacity: true)
    surface.motionGroupRuntimes.removeAll(keepingCapacity: true)
    surface.syllableContainer.sublayers?.forEach { $0.removeFromSuperlayer() }
  }

  private func installSyllableLayers(
    _ line: DesktopLyricsLineRender,
    into surface: PrimarySurface
  ) {
    clearSyllableLayers(in: surface)
    surface.syllableContainer.frame = surface.container.bounds
    var groupIndexBySyllable = [Int: Int]()
    var runtimes = [MotionGroupRuntime]()
    for group in line.motionGroups {
      let valid = group.filter { $0 >= 0 && $0 < line.syllables.count }
      guard let first = valid.first, let last = valid.last else { continue }
      let duration = max(line.syllables[last].end - line.syllables[first].start, 0)
      for index in valid {
        groupIndexBySyllable[index] = runtimes.count
      }
      runtimes.append(MotionGroupRuntime(
        syllableIndices: valid,
        duration: duration
      ))
    }
    for render in line.syllableRenders {
      let runtimeIndex: Int
      if let existing = groupIndexBySyllable[render.index] {
        runtimeIndex = existing
      } else {
        runtimes.append(MotionGroupRuntime(
          syllableIndices: [render.index],
          duration: render.duration
        ))
        runtimeIndex = runtimes.count - 1
        groupIndexBySyllable[render.index] = runtimeIndex
      }
      let runtime = runtimes[runtimeIndex]
      let position = runtime.syllableIndices.firstIndex(of: render.index) ?? 0
      let container = CALayer()
      container.frame = render.rect
      container.anchorPoint = CGPoint(x: 0.5, y: 0)
      container.position = CGPoint(x: render.rect.midX, y: render.rect.minY)
      container.masksToBounds = false
      // Broad drop shadow belongs to the whole glyph stack and is drawn
      // behind the halo; putting it on the dim layer would grey out the
      // white bloom that sits underneath.
      container.shadowColor = NSColor.black.cgColor
      container.shadowOpacity = DesktopLyricsInk.broadShadowAlpha
      container.shadowRadius = DesktopLyricsInk.broadShadowBlur
      container.shadowOffset = CGSize(width: 0, height: -1)

      let bright = CALayer()
      bright.frame = CGRect(
        x: -render.pad,
        y: -render.pad,
        width: render.imageSize.width,
        height: render.imageSize.height
      )
      // Halo emitter: full glyph silhouette, independent of the wipe mask.
      // LyricsX blooms the whole slice even while its karaoke reveal is
      // still partway through, which is why the glow can precede the white
      // letter. Drawn behind the dim glyph so the unsung ink stays grey.
      let glow = CALayer()
      glow.frame = bright.frame
      glow.contents = render.glowImage
      glow.contentsGravity = .resize
      glow.magnificationFilter = .linear
      glow.contentsScale = screenScale
      glow.shadowColor = NSColor.white.withAlphaComponent(0.82).cgColor
      glow.shadowOffset = .zero
      glow.shadowRadius = min(9, max(3, line.size.height * 0.24)) * 0.72
      glow.shadowOpacity = 1
      glow.opacity = 0
      glow.isHidden = true

      // The dim glyph travels with the bright one. Without it the static
      // whole-line dim image stays behind and the lifted white glyph reads
      // as a double image instead of a clean highlight.
      let dim = CALayer()
      dim.frame = bright.frame
      dim.contents = render.dimImage
      dim.contentsGravity = .resize
      dim.magnificationFilter = .linear
      dim.contentsScale = screenScale

      bright.contents = render.brightImage
      bright.contentsGravity = .resize
      bright.magnificationFilter = .linear
      bright.contentsScale = screenScale
      bright.isHidden = true

      let mask = CAGradientLayer()
      mask.frame = bright.bounds
      mask.startPoint = CGPoint(x: 0, y: 0.5)
      mask.endPoint = CGPoint(x: 1, y: 0.5)
      mask.colors = [Self.whiteColor, Self.whiteColor]
      mask.locations = [0, 1]
      bright.mask = mask

      container.addSublayer(glow)
      container.addSublayer(dim)
      container.addSublayer(bright)
      surface.syllableContainer.addSublayer(container)
      let bundle = SyllableLayerBundle(
        container: container,
        glow: glow,
        bright: bright,
        mask: mask,
        glyphWidth: render.glyphWidth,
        imageWidth: render.imageSize.width,
        pad: render.pad,
        syllableIndex: render.index,
        groupRuntimeIndex: runtimeIndex,
        groupPhase: CGFloat(position) / CGFloat(max(runtime.syllableIndices.count, 1)),
        groupDuration: runtime.duration
      )
      runtimes[runtimeIndex].bundleIndices.append(surface.syllableBundles.count)
      surface.syllableBundles.append(bundle)
    }
    surface.motionGroupRuntimes = runtimes
  }

  private func installNextImage(animated: Bool) {
    nextLayer.removeAnimation(forKey: "nextArrival")
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    nextLayer.contents = nextLine?.image
    nextLayer.isHidden = nextLine == nil
    nextLayer.opacity = 1
    nextLayer.transform = CATransform3DIdentity
    CATransaction.commit()
    guard animated, nextLine != nil else { return }

    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 0
    fade.toValue = 1
    fade.duration = 0.30
    fade.timingFunction = CAMediaTimingFunction(
      controlPoints: 0.22, 0, 0.2, 1
    )
    nextLayer.add(fade, forKey: "nextArrival")
  }

  private func installHeaderImage(animated: Bool) {
    headerLayer.removeAnimation(forKey: "headerArrival")
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    headerLayer.contents = headerLine?.image
    headerLayer.isHidden = headerLine == nil
    headerLayer.opacity = 1
    CATransaction.commit()
    guard animated else { return }

    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 0
    fade.toValue = 1
    fade.duration = 0.30
    fade.timingFunction = CAMediaTimingFunction(
      controlPoints: 0.22, 0, 0.2, 1
    )
    headerLayer.add(fade, forKey: "headerArrival")
  }

  // MARK: - Hover control strip

  private func installToolbar() {
    let host = NSView(frame: .zero)
    host.wantsLayer = true
    host.layer?.zPosition = 10
    host.isHidden = true
    rootView.addSubview(host)
    toolbarHost = host

    // Row 1 (transport): open window, previous, play/pause, next.
    // Row 2 (overlay): sync, lock, click-through, hide.
    let specs: [(String, String, Selector)] = [
      ("arrow.up.left.and.arrow.down.right", "打开主窗口", #selector(toolbarOpenPressed)),
      ("backward.fill", "上一首", #selector(toolbarPreviousPressed)),
      ("pause.fill", "暂停", #selector(toolbarPlayPausePressed)),
      ("forward.fill", "下一首", #selector(toolbarNextPressed)),
      ("timer", "调节歌词同步", #selector(toolbarSyncPressed)),
      ("lock.open", "锁定位置", #selector(toolbarLockPressed)),
      ("cursorarrow.slash", "开启点击穿透", #selector(toolbarClickThroughPressed)),
      ("xmark", "隐藏悬浮歌词", #selector(toolbarClosePressed)),
    ]
    for (index, spec) in specs.enumerated() {
      let button = DesktopLyricsOverlayButton(frame: Self.toolbarButtonFrame(at: index))
      button.isBordered = false
      button.focusRingType = .none
      button.imagePosition = .imageOnly
      button.imageScaling = .scaleNone
      button.image = Self.symbolImage(spec.0)
      button.contentTintColor = NSColor(white: 1, alpha: 0.92)
      button.toolTip = spec.1
      button.target = self
      button.action = spec.2
      button.wantsLayer = true
      host.addSubview(button)
      toolbarButtons.append(button)
    }
  }

  private static func symbolImage(_ name: String, pointSize: CGFloat = 13) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: nil)?
      .withSymbolConfiguration(
        NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
      )
  }

  /// Two centred rows. Row 1 (transport, 4 buttons) is the widest and defines
  /// the capsule width; row 2 (overlay controls, 4 buttons) sits below it.
  private static func toolbarButtonFrame(at index: Int) -> CGRect {
    let size = DesktopLyricsRenderer.toolbarButtonSize
    let spacing = DesktopLyricsRenderer.toolbarButtonSpacing
    let rowWidth = CGFloat(DesktopLyricsRenderer.toolbarRowButtonCount) * size
      + CGFloat(DesktopLyricsRenderer.toolbarRowButtonCount - 1) * spacing
    let x = (DesktopLyricsRenderer.toolbarWidth - rowWidth) / 2
      + CGFloat(index) * (size + spacing)
    let y = (DesktopLyricsRenderer.toolbarHeight - size) / 2
    return CGRect(x: x, y: y, width: size, height: size)
  }

  private func updateToolbarImages() {
    guard toolbarButtons.count >= 8 else { return }
    let locked = positionLocked
    changeSymbol(
      of: toolbarButtons[Self.lockButtonIndex],
      to: locked ? "lock.fill" : "lock.open"
    )
    Self.setActive(locked, on: toolbarButtons[Self.lockButtonIndex])
    toolbarButtons[Self.lockButtonIndex].toolTip = locked ? "解锁并恢复拖动" : "锁定位置"
    let through = clickThrough
    // crossing arrows (rays) = click-through on; slashed arrow = click-through off.
    changeSymbol(
      of: toolbarButtons[Self.clickThroughButtonIndex],
      to: through ? "cursorarrow.rays" : "cursorarrow.slash"
    )
    Self.setActive(through, on: toolbarButtons[Self.clickThroughButtonIndex])
    toolbarButtons[Self.clickThroughButtonIndex].toolTip = through
      ? "关闭点击穿透" : "开启点击穿透"
    changeSymbol(
      of: toolbarButtons[Self.playPauseButtonIndex],
      to: isPlaying ? "pause.fill" : "play.fill"
    )
    toolbarButtons[Self.playPauseButtonIndex].toolTip = isPlaying ? "暂停" : "播放"
  }

  /// Applies the configured glyph color (SF Symbols tint). 0 = white, 1 = black,
  /// so the slider reads as "how dark". Alpha is kept high so the glyphs stay solid.
  private func applyControlIconColor() {
    let white = CGFloat(1 - min(1, max(0, style.controlIconBrightness)))
    let color = NSColor(white: white, alpha: 0.98)
    for button in toolbarButtons {
      button.contentTintColor = color
    }
  }

  private static func setActive(_ active: Bool, on button: NSButton) {
    guard let layer = button.layer else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.cornerRadius = DesktopLyricsRenderer.toolbarButtonSize / 2
    layer.backgroundColor = active
      ? NSColor(white: 1, alpha: 0.10).cgColor
      : NSColor.clear.cgColor
    CATransaction.commit()
  }

  private func changeSymbol(of button: NSButton, to name: String) {
    if let image = Self.symbolImage(name) {
      button.image = image
    }
  }

  @objc
  private func toolbarSyncPressed() {
    toggleOffsetPanel()
  }

  @objc
  private func toolbarOpenPressed() {
    onOpenMainWindow?()
  }

  @objc
  private func toolbarPreviousPressed() {
    onPlayPrevious?()
  }

  @objc
  private func toolbarPlayPausePressed() {
    // Optimistic flip so the icon reacts immediately; the manager refreshes
    // the real state via setPlaying(_:) on the next playback notification.
    setPlaying(!isPlaying)
    onTogglePlayPause?()
  }

  @objc
  private func toolbarNextPressed() {
    onPlayNext?()
  }

  @objc
  private func toolbarLockPressed() {
    // Unlocking also releases click-through, matching LyricsX Next.
    if positionLocked, clickThrough {
      setClickThrough(false, notify: true)
    }
    positionLocked.toggle()
    UserDefaults.standard.set(positionLocked, forKey: Self.positionLockKey)
    setPositionLocked(positionLocked)
    updateToolbarImages()
  }

  @objc
  private func toolbarClickThroughPressed() {
    setClickThrough(!clickThrough, notify: true)
  }

  @objc
  private func toolbarClosePressed() {
    onHideDesktopLyrics?()
  }

  private func setPositionLocked(_ locked: Bool) {
    panel.isMovableByWindowBackground = !locked
  }

  // MARK: - Click-through

  /// Clicks must pass through the lyric panel while its control strip remains
  /// usable, so the strip leaves for its own panel one level above. Enabling
  /// click-through also locks the position, as LyricsX Next does.
  private func setClickThrough(_ enabled: Bool, notify: Bool) {
    // The change notification refreshes settings synchronously; that refresh
    // must not move the control strip back while this change is applying.
    guard !applyingClickThrough, enabled != clickThrough else { return }
    applyingClickThrough = true
    defer { applyingClickThrough = false }
    clickThrough = enabled
    if enabled {
      if !positionLocked {
        positionLocked = true
        UserDefaults.standard.set(true, forKey: Self.positionLockKey)
        setPositionLocked(true)
      }
      if controlWindow == nil {
        let window = Self.makeBorderlessPanel(size: CGSize(
          width: DesktopLyricsRenderer.toolbarWidth,
          height: DesktopLyricsRenderer.toolbarHeight
        ))
        window.level = NSWindow.Level(rawValue: panel.level.rawValue + 1)
        window.ignoresMouseEvents = false
        controlWindow = window
      }
      positionControlWindow()
      if let host = toolbarHost {
        host.removeFromSuperview()
        host.autoresizingMask = [.width, .height]
        host.frame = CGRect(
          x: 0,
          y: 0,
          width: DesktopLyricsRenderer.toolbarWidth,
          height: DesktopLyricsRenderer.toolbarHeight
        )
        controlWindow?.contentView = host
      }
    } else {
      controlWindow?.orderOut(nil)
      controlWindow?.contentView = nil
      if let host = toolbarHost {
        host.removeFromSuperview()
        host.autoresizingMask = []
        rootView.addSubview(host)
      }
    }
    panel.ignoresMouseEvents = enabled
    updateToolbarImages()
    if notify {
      onClickThroughChanged?(enabled)
    }
    isToolbarVisible = false
    toolbarHost?.isHidden = true
    layoutLayers()
    hoverTick()
  }

  private func positionControlWindow() {
    guard clickThrough, let controlWindow else { return }
    let frame = currentFrame
    let origin = CGPoint(
      x: frame.maxX - DesktopLyricsRenderer.toolbarWidth
        - DesktopLyricsRenderer.toolbarRightInset,
      y: frame.midY - DesktopLyricsRenderer.toolbarHeight / 2
    )
    controlWindow.setFrameOrigin(origin)
  }

  // MARK: - Hover tracking

  private func startHoverTracking() {
    guard hoverTimer == nil else { return }
    let timer = Timer(
      timeInterval: 0.05,
      target: self,
      selector: #selector(hoverTick),
      userInfo: nil,
      repeats: true
    )
    RunLoop.main.add(timer, forMode: .common)
    hoverTimer = timer
    hoverTick()
  }

  private func stopHoverTracking() {
    hoverTimer?.invalidate()
    hoverTimer = nil
    setToolbarVisible(false)
  }

  @objc
  private func hoverTick() {
    guard isVisible else { return }
    let point = NSEvent.mouseLocation
    var isInside = currentFrame.contains(point)
    if !isInside, let editor = offsetPanel {
      isInside = editor.frame.contains(point)
    }
    setToolbarVisible(isInside)
  }

  private func setToolbarVisible(_ visible: Bool) {
    guard visible != isToolbarVisible, let host = toolbarHost
    else { return }
    isToolbarVisible = visible
    toolbarToken += 1
    let token = toolbarToken
    if visible {
      host.isHidden = false
      if clickThrough {
        positionControlWindow()
        controlWindow?.orderFrontRegardless()
      }
      // Re-sample the wallpaper only when the strip appears, so the automatic
      // contrast adapts to whatever moved behind it without per-frame cost.
      applyControlIconColor()
    }
    // Fade the transparent host, not the capsule chip: the chip's own alpha
    // is reserved for the panel background-opacity linkage (updateChrome).
    guard let layer = host.layer else {
      host.isHidden = !visible
      if !visible, clickThrough {
        controlWindow?.orderOut(nil)
      }
      return
    }

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.opacity = visible ? 1 : 0
    CATransaction.commit()

    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = visible ? 0 : 1
    fade.toValue = visible ? 1 : 0
    fade.duration = 0.16
    fade.timingFunction = CAMediaTimingFunction(
      controlPoints: 0.22, 0, 0.2, 1
    )
    layer.add(fade, forKey: "toolbarFade")

    guard !visible else { return }
    Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 200_000_000)
      guard let self, toolbarToken == token, !self.isToolbarVisible
      else { return }
      self.toolbarHost?.isHidden = true
      if self.clickThrough {
        self.controlWindow?.orderOut(nil)
      }
    }
  }

  // MARK: - Lyrics sync panel

  /// LyricsX Next adjusts a per-song offset from the timer button and shows
  /// the global and combined values below it. fmusic keeps the same split:
  /// the song correction lives with the overlay, the global offset stays in
  /// UserSettings and the player's lyrics-offset menu.
  private func toggleOffsetPanel() {
    if offsetPanel != nil {
      closeOffsetPanel()
      return
    }
    guard let snapshot = offsetSnapshot?() else { return }
    offsetSongID = snapshot.songID
    let size = CGSize(width: 340, height: 176)
    let panel = Self.makeBorderlessPanel(size: size)
    panel.level = NSWindow.Level(rawValue: self.panel.level.rawValue + 2)
    panel.setAccessibilityLabel("歌词同步调节")
    let content = makeOffsetPanelContent(size: size)
    panel.contentView = content
    offsetPanel = panel
    refreshOffsetFields(snapshot)
    positionOffsetPanel()
    panel.orderFrontRegardless()
    installOffsetMonitors(for: panel)
  }

  private func installOffsetMonitors(for panel: NSPanel) {
    _ = panel
    offsetClickMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown]
    ) { [weak self] event in
      guard let self else { return event }
      let point = NSEvent.mouseLocation
      if let panelFrame = self.offsetPanel?.frame, panelFrame.contains(point) {
        return event
      }
      if let toolbarFrame = self.toolbarScreenFrame(),
         toolbarFrame.contains(point) {
        return event
      }
      self.closeOffsetPanel()
      return event
    }
  }

  @objc
  private func applicationDidResignActive(_ notification: Notification) {
    closeOffsetPanel()
  }

  private func makeOffsetPanelContent(size: CGSize) -> NSView? {
    let background = NSVisualEffectView(
      frame: CGRect(origin: .zero, size: size)
    )
    background.material = .popover
    background.blendingMode = .behindWindow
    background.state = .active
    background.appearance = NSAppearance(named: .darkAqua)
    background.wantsLayer = true
    if let layer = background.layer {
      layer.cornerRadius = 24
      layer.cornerCurve = .continuous
      layer.masksToBounds = true
      layer.borderWidth = 0.5
      layer.borderColor = NSColor(white: 1, alpha: 0.16).cgColor
    }

    let shade = NSView(frame: CGRect(origin: .zero, size: size))
    shade.wantsLayer = true
    shade.autoresizingMask = [.width, .height]
    shade.layer?.backgroundColor = NSColor(white: 0, alpha: 0.55).cgColor
    background.addSubview(shade)

    addLabel(
      "歌词同步",
      frame: CGRect(x: 16, y: 146, width: 220, height: 18),
      size: 13,
      weight: .semibold,
      monospaced: false,
      to: background
    )
    if let close = Self.makeToolbarButton(
      symbol: "xmark",
      tooltip: "关闭歌词同步调节",
      target: self,
      action: #selector(closeOffsetPressed)
    ) {
      close.frame = CGRect(x: 298, y: 141, width: 26, height: 26)
      background.addSubview(close)
    }

    offsetValueField = addLabel(
      "",
      frame: CGRect(x: 16, y: 108, width: 308, height: 20),
      size: 15,
      weight: .semibold,
      monospaced: true,
      to: background
    )
    offsetDetailField = addLabel(
      "",
      frame: CGRect(x: 16, y: 88, width: 308, height: 16),
      size: 11,
      weight: .regular,
      monospaced: true,
      to: background
    )
    offsetDetailField?.textColor = .secondaryLabelColor

    if let button = makeOffsetButton(
      "延后 0.1 秒",
      frame: CGRect(x: 16, y: 51, width: 98, height: 24),
      action: #selector(offsetLaterPressed)
    ) {
      background.addSubview(button)
    }
    if let button = makeOffsetButton(
      "提前 0.1 秒",
      frame: CGRect(x: 117, y: 51, width: 98, height: 24),
      action: #selector(offsetEarlyPressed)
    ) {
      background.addSubview(button)
    }
    if let button = makeOffsetButton(
      "重置",
      frame: CGRect(x: 218, y: 51, width: 106, height: 24),
      action: #selector(offsetResetPressed)
    ) {
      background.addSubview(button)
    }

    let caption = addLabel(
      "此处只调整或重置单曲偏移；通用偏移请在播放器的歌词偏移菜单中调整。",
      frame: CGRect(x: 16, y: 12, width: 308, height: 32),
      size: 11,
      weight: .regular,
      monospaced: false,
      to: background
    )
    caption.textColor = .secondaryLabelColor
    caption.lineBreakMode = .byWordWrapping
    caption.usesSingleLineMode = false
    caption.maximumNumberOfLines = 2
    return background
  }

  @discardableResult
  private func addLabel(
    _ text: String,
    frame: CGRect,
    size: CGFloat,
    weight: NSFont.Weight,
    monospaced: Bool,
    to parent: NSView
  )
    -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = Self.nsFont(size: size, weight: weight, monospaced: monospaced)
    field.alignment = .left
    field.frame = frame
    parent.addSubview(field)
    return field
  }

  private func makeOffsetButton(
    _ title: String,
    frame: CGRect,
    action: Selector
  )
    -> NSButton? {
    let button = DesktopLyricsOverlayButton(frame: frame)
    button.title = title
    button.bezelStyle = .rounded
    button.controlSize = .small
    button.setButtonType(.momentaryPushIn)
    button.target = self
    button.action = action
    button.font = Self.nsFont(size: 11, weight: .regular, monospaced: false)
    return button
  }

  private static func nsFont(
    size: CGFloat,
    weight: NSFont.Weight,
    monospaced: Bool
  )
    -> NSFont {
    monospaced
      ? .monospacedDigitSystemFont(ofSize: size, weight: weight)
      : .systemFont(ofSize: size, weight: weight)
  }

  private static func makeToolbarButton(
    symbol: String,
    tooltip: String,
    target: AnyObject,
    action: Selector
  )
    -> DesktopLyricsOverlayButton? {
    let button = DesktopLyricsOverlayButton(frame: .zero)
    button.isBordered = false
    button.focusRingType = .none
    button.imagePosition = .imageOnly
    button.imageScaling = .scaleNone
    button.image = symbolImage(symbol)
    button.contentTintColor = NSColor(white: 1, alpha: 0.92)
    button.toolTip = tooltip
    button.target = target
    button.action = action
    button.wantsLayer = true
    return button
  }

  private func refreshOffsetFields(_ snapshot: OverlayOffsetSnapshot) {
    offsetValueField?.stringValue = String(
      format: "单曲偏移 %+.1f 秒",
      Double(snapshot.songMilliseconds) / 1_000
    )
    offsetDetailField?.stringValue = String(
      format: "通用 %+.3f 秒 · 合计 %+.3f 秒",
      Double(snapshot.globalMilliseconds) / 1_000,
      Double(snapshot.totalMilliseconds) / 1_000
    )
  }

  @objc
  private func offsetLaterPressed() {
    adjustOffset(by: -100)
  }

  @objc
  private func offsetEarlyPressed() {
    adjustOffset(by: 100)
  }

  @objc
  private func offsetResetPressed() {
    guard let songID = offsetSongID,
          let updated = resetSongOffset?(songID)
    else { return }
    refreshOffsetFields(updated)
  }

  @objc
  private func closeOffsetPressed() {
    closeOffsetPanel()
  }

  private func adjustOffset(by milliseconds: Int) {
    guard let songID = offsetSongID,
          let snapshot = offsetSnapshot?(),
          snapshot.songID == songID,
          let updated = adjustSongOffset?(
            songID,
            snapshot.songMilliseconds + milliseconds
          )
    else { return }
    refreshOffsetFields(updated)
  }

  private func positionOffsetPanel() {
    guard let panel = offsetPanel else { return }
    let size = CGSize(width: 340, height: 176)
    let main = currentFrame
    var origin = CGPoint(
      x: main.maxX - size.width,
      y: main.minY - size.height - 4
    )
    if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame {
      if origin.y < visible.minY {
        origin.y = main.maxY + 4
      }
      origin.x = min(max(visible.minX, origin.x), visible.maxX - size.width)
      origin.y = min(max(visible.minY, origin.y), visible.maxY - size.height)
    }
    panel.setFrameOrigin(origin)
  }

  private func closeOffsetPanel() {
    if let offsetClickMonitor {
      NSEvent.removeMonitor(offsetClickMonitor)
    }
    offsetClickMonitor = nil
    offsetSongID = nil
    offsetValueField = nil
    offsetDetailField = nil
    guard let panel = offsetPanel else { return }
    offsetPanel = nil
    panel.orderOut(nil)
    panel.contentView = nil
    panel.close()
  }

  private func toolbarScreenFrame() -> CGRect? {
    if clickThrough, let controlWindow {
      return controlWindow.frame
    }
    guard let host = toolbarHost, let window = host.window else { return nil }
    return window.convertToScreen(host.convert(host.bounds, to: nil))
  }

  // MARK: - Borderless panels

  private static func makeBorderlessPanel(size: CGSize) -> NSPanel {
    let panel = DesktopLyricsWindow(
      contentRect: CGRect(origin: .zero, size: size),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    panel.isOpaque = false
    panel.hasShadow = false
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.isExcludedFromWindowsMenu = true
    panel.isMovableByWindowBackground = false
    panel.backgroundColor = .clear
    panel.appearance = NSAppearance(named: .darkAqua)
    panel.isFloatingPanel = true
    return panel
  }

  // MARK: - Clock

  private func applyProgress(_ progress: [CGFloat], force: Bool = false) {
    let surface = currentSurface
    guard let line = surface.line else { return }
    if !force, progress == surface.lastProgress { return }
    surface.lastProgress = progress

    guard !line.syllables.isEmpty else {
      surface.syllableMask.reset()
      surface.sung.isHidden = true
      clearSyllableLayers(in: surface)
      return
    }
    if surface.syllableBundles.isEmpty {
      surface.sung.isHidden = false
      surface.syllableMask.apply(progress: progress)
    } else {
      surface.sung.isHidden = true
      applySyllableWave(progress, in: surface)
    }
  }

  private func applySyllableWave(
    _ progress: [CGFloat],
    in surface: PrimarySurface
  ) {
    let lineHeight = surface.line?.size.height ?? 0
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for runtime in surface.motionGroupRuntimes {
      // Share the word's envelope across its letters; the small phase delay
      // makes adjacent clusters overlap instead of pulsing one at a time.
      var sum: CGFloat = 0
      var count = 0
      for syllableIndex in runtime.syllableIndices where syllableIndex < progress.count {
        sum += progress[syllableIndex]
        count += 1
      }
      let groupProgress = count > 0 ? sum / CGFloat(count) : 0
      for bundleIndex in runtime.bundleIndices {
        applyWave(
          to: &surface.syllableBundles[bundleIndex],
          groupProgress: groupProgress,
          progress: progress,
          lineHeight: lineHeight
        )
      }
    }
    CATransaction.commit()
  }

  private func applyWave(
    to bundle: inout SyllableLayerBundle,
    groupProgress: CGFloat,
    progress: [CGFloat],
    lineHeight: CGFloat
  ) {
    let value = bundle.syllableIndex < progress.count
      ? progress[bundle.syllableIndex] : 0
    let delay = 0.22 * min(1, max(0, bundle.groupPhase))
    let motionProgress = min(
      1,
      max(0, (groupProgress - delay) / max(0.001, 1 - delay))
    )
    let wave = DesktopLyricsEmphasis.wave(
      progress: motionProgress,
      duration: bundle.groupDuration,
      lineHeight: lineHeight
    )
    if bundle.lastScale != wave.scale || bundle.lastLift != wave.lift {
      bundle.lastScale = wave.scale
      bundle.lastLift = wave.lift
      bundle.container.transform = CATransform3DConcat(
        CATransform3DMakeScale(wave.scale, wave.scale, 1),
        CATransform3DMakeTranslation(0, wave.lift, 0)
      )
    }
    let brightHidden = value <= 0.0001
    if bundle.bright.isHidden != brightHidden {
      bundle.bright.isHidden = brightHidden
    }
    // LyricsX multiplies the halo by the local reveal progress, so the
    // glow enters with the glyph instead of pre-lighting unsung text.
    let emphasis = DesktopLyricsEmphasis.value(
      progress: motionProgress,
      duration: bundle.groupDuration
    ) * DesktopLyricsEmphasis.smoother(value)
    let bloom = Float(emphasis)
    if bundle.glow.opacity != bloom {
      bundle.glow.opacity = bloom
    }
    let glowHidden = bloom <= 0.001
    if bundle.glow.isHidden != glowHidden {
      bundle.glow.isHidden = glowHidden
    }
    guard !brightHidden else { return }
    if value >= 0.999 {
      guard !bundle.maskIsFull else { return }
      bundle.maskIsFull = true
      bundle.mask.colors = [Self.whiteColor, Self.whiteColor]
      bundle.mask.locations = [0, 1]
    } else {
      bundle.maskIsFull = false
      let filled = max(0.5, bundle.glyphWidth * value)
      // LyricsX feathers only the 3 pt at the reveal edge. A gradient that
      // fades from the boundary to the image's right edge would light the
      // whole character at once and read as "white letters appearing".
      let feather: CGFloat = 3
      let edge = bundle.pad + filled
      let start = min(1, edge / bundle.imageWidth)
      let end = min(1, (edge + feather) / bundle.imageWidth)
      bundle.mask.colors = [
        Self.whiteColor, Self.whiteColor, Self.clearColor, Self.clearColor,
      ]
      bundle.mask.locations = [
        0, NSNumber(value: Float(start)), NSNumber(value: Float(end)), 1,
      ]
    }
  }

  // MARK: - Line motion

  /// Fades the outgoing surface exactly as it stands. The live masks and glow
  /// stay on screen, so no snapshot has to be rasterized on the main thread.
  private func startDeparture(of surface: PrimarySurface) {
    departureToken += 1
    let token = departureToken
    departureHeight = surface.container.bounds.height
    surface.container.removeAllAnimations()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    surface.container.isHidden = false
    surface.container.opacity = 1
    surface.container.transform = CATransform3DIdentity
    surface.container.zPosition = 3
    CATransaction.commit()

    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 1
    fade.toValue = 0
    fade.duration = 0.20
    // OverlayCueDeparture uses smootherstep; ease-in-out keeps the old row
    // from lingering under the incoming one.
    fade.timingFunction = CAMediaTimingFunction(
      controlPoints: 0.45, 0, 0.55, 1
    )
    surface.container.add(fade, forKey: "departure")

    // LyricsX lifts the old row only 2–4 pt while it fades; a large rise
    // collides with the growing incoming row.
    let rise = CABasicAnimation(keyPath: "transform.translation.y")
    rise.fromValue = 0
    rise.toValue = 3
    rise.duration = 0.20
    rise.timingFunction = CAMediaTimingFunction(
      controlPoints: 0.3, 0, 0.6, 1
    )
    surface.container.add(rise, forKey: "departureRise")

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    surface.container.opacity = 0
    surface.container.transform = CATransform3DMakeTranslation(0, 3, 0)
    CATransaction.commit()

    Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 260_000_000)
      guard let self, departureToken == token else { return }
      resetSurface(surface)
      if departingSurface === surface {
        departingSurfaceIsA = nil
        departureHeight = 0
      }
    }
  }

  private func animateArrival(
    promoted: Bool,
    previewTop: CGFloat?,
    previewScale: CGFloat
  ) {
    let from: CATransform3D
    let moveDuration: TimeInterval
    let fadeFrom: Float
    if promoted, let previewTop {
      // LyricsX Next promotes the surface that is already on screen: the
      // incoming primary starts at the preview's centre and scale and grows
      // into place. Without that, two full-size rows cross-fade on top of
      // each other and every line reads as a new sentence being written.
      let finalCenter = CGPoint(
        x: currentSurface.container.frame.midX,
        y: currentSurface.container.frame.midY
      )
      let previewCenterY = contentLayer.bounds.height - previewTop
      let scale = max(0.2, min(1, previewScale))
      from = CATransform3DConcat(
        CATransform3DMakeTranslation(0, previewCenterY - finalCenter.y, 0),
        CATransform3DMakeScale(scale, scale, 1)
      )
      moveDuration = 0.62
      fadeFrom = 0.85
    } else {
      from = CATransform3DConcat(
        CATransform3DMakeTranslation(0, -10, 0),
        CATransform3DMakeScale(0.985, 0.985, 1)
      )
      moveDuration = 0.5
      fadeFrom = 0.7
    }

    let move = CABasicAnimation(keyPath: "transform")
    move.fromValue = NSValue(caTransform3D: from)
    move.toValue = NSValue(caTransform3D: CATransform3DIdentity)
    move.duration = moveDuration
    // LyricMotion.overlayArrivalCurve: bezier(0.28, 0, 0.30, 1).
    move.timingFunction = CAMediaTimingFunction(
      controlPoints: 0.28, 0, 0.30, 1
    )

    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = fadeFrom
    fade.toValue = 1
    fade.duration = promoted ? 0.50 : 0.40
    fade.timingFunction = CAMediaTimingFunction(name: .easeOut)

    let container = currentSurface.container
    container.removeAnimation(forKey: "arrival")
    container.removeAnimation(forKey: "arrivalFade")
    container.add(move, forKey: "arrival")
    container.add(fade, forKey: "arrivalFade")
  }

  // MARK: - Chrome

  private func updateChrome() {
    let opacity = min(1, max(0, style.backgroundOpacity))
    let hasChrome = opacity > 0.001
    let reduceTransparency = Self.reduceTransparencyEnabled()
    // LyricsX Next's Liquid Glass tint: a top-weighted black shade that
    // leaves the lower edge fully refractive. Its glass tint opacity is
    // derived from the same slider value (0.60 at full strength), which is
    // what keeps the panel visually smoked over light windows instead of
    // washing out to near-white.
    let shade = 0.60 * opacity
    let glassActive = usesGlassMaterial && !reduceTransparency

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    scrimLayer.isHidden = !hasChrome || reduceTransparency
    if reduceTransparency {
      solidLayer.isHidden = !hasChrome
      solidLayer.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor
      solidLayer.opacity = Float(opacity)
    } else {
      solidLayer.isHidden = true
      scrimLayer.colors = [
        NSColor.black.withAlphaComponent(shade).cgColor,
        NSColor.black.withAlphaComponent(shade * 0.66).cgColor,
        NSColor.black.withAlphaComponent(shade * 0.28).cgColor,
        NSColor.black.withAlphaComponent(0).cgColor,
      ]
    }
    // Clear Liquid Glass draws its own refraction highlight along the rim.
    borderLayer.isHidden = !hasChrome || glassActive
    borderLayer.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
    CATransaction.commit()

    applyControlIconColor()

    if let backgroundView {
      backgroundView.isHidden = !hasChrome || reduceTransparency
      // A visible glass view is fully blurred at any alpha; scaling the whole
      // backdrop makes the slider progress from clear to frosted instead of
      // getting blurriest in the middle.
      backgroundView.alphaValue = opacity
    }
  }

  /// AppKit builds a light backdrop independently of our fixed white ink when
  /// the system switches themes; pin the backdrop to dark like LyricsX Next.
  private static func fixedGlassAppearance(_ view: NSView) {
    view.appearance = NSAppearance(named: .darkAqua)
  }

  private static func reduceTransparencyEnabled() -> Bool {
    NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
  }

  // MARK: - Layout

  private func desiredHeight() -> CGFloat {
    let primary = currentSurface.line?.size.height
      ?? ceil(style.pointSize * 1.34)
    let header = headerLine.map {
      DesktopLyricsRenderer.headerGap + $0.height
    } ?? 0
    let next = nextLine.map { DesktopLyricsRenderer.lineGap + $0.height } ?? 0
    return DesktopLyricsRenderer.topPadding
      + DesktopLyricsRenderer.bottomPadding
      + header
      + primary
      + next
  }

  /// The top edge stays fixed while the height follows the current and preview
  /// lines, so wrapped lines grow downwards like Apple Music's overlay.
  private func resizePanel() {
    let height = max(desiredHeight(), DesktopLyricsRenderer.minPanelHeight)
    let frame = currentFrame
    guard abs(frame.height - height) > 0.5 else { return }
    guard isVisible else {
      applyResize(from: frame, to: height)
      return
    }
    animateResize(from: frame, to: height)
  }

  private func applyResize(from frame: CGRect, to height: CGFloat) {
    guard abs(frame.height - height) > 0.5 else { return }
    var newFrame = frame
    newFrame.origin.y += frame.height - height
    newFrame.size.height = height
    applyFrame(newFrame)
    saveFrame()
  }

  /// LyricsX Next springs its native panel between one- and two-row lyric
  /// heights instead of snapping. AppKit owns the rounded glass, so the
  /// height is stepped here while every text layer stays anchored to the
  /// fixed top edge.
  private func animateResize(from frame: CGRect, to height: CGFloat) {
    resizeTimer?.invalidate()
    resizeTimer = nil
    guard abs(frame.height - height) > 0.5 else {
      activeResize = nil
      isAnimatingResize = false
      return
    }
    let delta = height - frame.height
    activeResize = ActiveResize(
      top: frame.maxY,
      startHeight: frame.height,
      height: height,
      started: CACurrentMediaTime(),
      duration: delta > 0 ? 0.34 : 0.48
    )
    isAnimatingResize = true
    let timer = Timer(
      timeInterval: 1.0 / 60.0,
      target: self,
      selector: #selector(resizeTick(_:)),
      userInfo: nil,
      repeats: true
    )
    RunLoop.main.add(timer, forMode: .common)
    resizeTimer = timer
  }

  @objc
  private func resizeTick(_ timer: Timer) {
    guard let resize = activeResize else {
      timer.invalidate()
      resizeTimer = nil
      isAnimatingResize = false
      return
    }
    let progress = min(
      1,
      max(0, (CACurrentMediaTime() - resize.started) / resize.duration)
    )
    let eased = DesktopLyricsEmphasis.smoother(CGFloat(progress))
    let height = resize.startHeight
      + (resize.height - resize.startHeight) * eased
    var frame = currentFrame
    frame.origin.y = resize.top - height
    frame.size.height = height
    applyFrame(frame)
    guard progress >= 1 else { return }
    timer.invalidate()
    resizeTimer = nil
    activeResize = nil
    isAnimatingResize = false
    saveFrame()
  }

  private func layoutLayers() {
    let bounds = CGRect(origin: .zero, size: panel.frame.size)
    let inset = DesktopLyricsRenderer.horizontalInset
    let width = DesktopLyricsRenderer.contentWidth
    let top = bounds.height - DesktopLyricsRenderer.topPadding
    let radius = DesktopLyricsRenderer.glassCornerRadius

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    scrimLayer.frame = bounds
    scrimLayer.cornerRadius = radius
    solidLayer.frame = bounds
    solidLayer.cornerRadius = radius
    borderLayer.frame = bounds
    borderLayer.cornerRadius = radius
    updateBackgroundRadius(radius)
    contentLayer.frame = bounds
    backgroundView?.frame = bounds

    if let toolbarHost, !clickThrough {
      let toolbarRect = CGRect(
        x: bounds.width - DesktopLyricsRenderer.toolbarRightInset
          - DesktopLyricsRenderer.toolbarWidth,
        y: (bounds.height - DesktopLyricsRenderer.toolbarHeight) / 2,
        width: DesktopLyricsRenderer.toolbarWidth,
        height: DesktopLyricsRenderer.toolbarHeight
      )
      toolbarHost.frame = toolbarRect
    }

    headerLayer.contentsScale = screenScale
    nextLayer.contentsScale = screenScale
    for surface in [surfaceA, surfaceB] {
      surface.base.contentsScale = screenScale
      surface.sung.contentsScale = screenScale
    }

    var cursor = top
    if let header = headerLine {
      headerLayer.frame = CGRect(
        x: inset,
        y: cursor - header.height,
        width: width,
        height: header.height
      )
      cursor -= header.height + DesktopLyricsRenderer.headerGap
    }

    if let line = currentSurface.line {
      currentSurface.container.frame = CGRect(
        x: inset,
        y: cursor - line.size.height,
        width: width,
        height: line.size.height
      )
      currentSurface.base.frame = currentSurface.container.bounds
      currentSurface.sung.frame = currentSurface.container.bounds
      currentSurface.syllableContainer.frame = currentSurface.container.bounds
      currentSurface.syllableMask.setFrameWithoutAnimation(currentSurface.sung.bounds)
      cursor -= line.size.height
    }

    if let next = nextLine {
      nextLayer.frame = CGRect(
        x: inset,
        y: cursor - DesktopLyricsRenderer.lineGap - next.height,
        width: width,
        height: next.height
      )
    }

    if let departing = departingSurface,
       !departing.container.isHidden,
       departureHeight > 0 {
      let primaryTop = top
        - (headerLine.map { $0.height + DesktopLyricsRenderer.headerGap } ?? 0)
      departing.container.frame = CGRect(
        x: inset,
        y: primaryTop - departureHeight,
        width: width,
        height: departureHeight
      )
    }
    CATransaction.commit()
    positionControlWindow()
    positionOffsetPanel()
  }

  private func updateBackgroundRadius(_ radius: CGFloat) {
    guard let backgroundView else { return }
    if #available(macOS 26.0, *), let glass = backgroundView as? NSGlassEffectView {
      glass.cornerRadius = radius
    } else if let layer = backgroundView.layer {
      layer.cornerRadius = radius
      layer.cornerCurve = .continuous
    }
  }

  // MARK: - Window content

  private func installBackground() {
    let view: NSView
    if let glass = Self.makeGlassView() {
      view = glass
      usesGlassMaterial = true
    } else {
      view = Self.makeEffectView()
      usesGlassMaterial = false
    }
    backgroundView = view
    view.autoresizingMask = [.width, .height]
    rootView.addSubview(view)
    // AppKit creates the backing layer lazily, which can insert it above the
    // lyric sublayers added below. Pin it behind them explicitly.
    view.layer?.zPosition = 0
  }

  /// Clear Liquid Glass, matching LyricsX Next's desktop lyrics: AppKit owns
  /// refraction, the scrim supplies a light contrast tint, and a fixed dark
  /// appearance keeps white lyrics readable over bright desktops.
  private static func makeGlassView() -> NSView? {
    guard #available(macOS 26.0, *) else { return nil }
    let view = NSGlassEffectView(frame: .zero)
    view.style = .clear
    fixedGlassAppearance(view)
    view.cornerRadius = DesktopLyricsRenderer.glassCornerRadius
    view.wantsLayer = true
    return view
  }

  private static func makeEffectView() -> NSView {
    let view = NSVisualEffectView(frame: .zero)
    view.material = .popover
    view.blendingMode = .behindWindow
    view.state = .active
    view.appearance = NSAppearance(named: .darkAqua)
    view.wantsLayer = true
    if let layer = view.layer {
      layer.cornerCurve = .continuous
      layer.masksToBounds = true
    }
    return view
  }

  private func installLayers() {
    // Layer order: background is already in place, then scrim, hairline and text.
    scrimLayer.cornerCurve = .continuous
    scrimLayer.masksToBounds = true
    scrimLayer.startPoint = CGPoint(x: 0.5, y: 1)
    scrimLayer.endPoint = CGPoint(x: 0.5, y: 0)
    scrimLayer.locations = [0, 0.38, 0.76, 1]
    scrimLayer.zPosition = 1

    borderLayer.cornerCurve = .continuous
    borderLayer.borderWidth = 1
    borderLayer.backgroundColor = NSColor.clear.cgColor
    borderLayer.zPosition = 2

    contentLayer.masksToBounds = false
    contentLayer.zPosition = 3
    headerLayer.masksToBounds = false
    nextLayer.masksToBounds = false
    headerLayer.zPosition = 0
    nextLayer.zPosition = 1

    for layer in [headerLayer, nextLayer] {
      layer.contentsGravity = .resize
      layer.magnificationFilter = .linear
      layer.isOpaque = false
    }

    // LyricsX stacks a tight black rim on the glyph and a broad drop shadow
    // on the whole surface. The rim is baked into the raster; applying the
    // broad shadow here keeps it outside the image bounds instead of being
    // clipped by them.
    nextLayer.shadowColor = NSColor.black.cgColor
    nextLayer.shadowOpacity = DesktopLyricsInk.broadShadowAlpha
    nextLayer.shadowRadius = DesktopLyricsInk.broadShadowBlur
    nextLayer.shadowOffset = CGSize(width: 0, height: -1)

    for surface in [surfaceA, surfaceB] {
      surface.container.masksToBounds = false
      surface.container.zPosition = 2
      surface.base.masksToBounds = false
      surface.sung.masksToBounds = false
      surface.syllableContainer.masksToBounds = false
      for layer in [surface.base, surface.sung] {
        layer.contentsGravity = .resize
        layer.magnificationFilter = .linear
        layer.isOpaque = false
      }
      surface.base.shadowColor = NSColor.black.cgColor
      surface.base.shadowOpacity = DesktopLyricsInk.broadShadowAlpha
      surface.base.shadowRadius = DesktopLyricsInk.broadShadowBlur
      surface.base.shadowOffset = CGSize(width: 0, height: -1)
      surface.sung.mask = surface.syllableMask
      surface.container.addSublayer(surface.base)
      surface.container.addSublayer(surface.syllableContainer)
      surface.container.addSublayer(surface.sung)
      contentLayer.addSublayer(surface.container)
    }

    contentLayer.addSublayer(headerLayer)
    contentLayer.addSublayer(nextLayer)
    solidLayer.cornerCurve = .continuous
    solidLayer.masksToBounds = true
    solidLayer.isHidden = true
    solidLayer.zPosition = 0.5
    // The tint sits above the glass so the clear material keeps refracting;
    // embedding it as the glass content view makes AppKit add a light fill.
    scrimLayer.zPosition = 1
    rootLayer.addSublayer(scrimLayer)
    rootLayer.addSublayer(solidLayer)
    rootLayer.addSublayer(borderLayer)
    rootLayer.addSublayer(contentLayer)

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    headerLayer.isHidden = true
    nextLayer.isHidden = true
    surfaceA.container.isHidden = true
    surfaceB.container.isHidden = true
    CATransaction.commit()
  }

  // MARK: - Window setup

  private func configureWindow() {
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    panel.isMovableByWindowBackground = true
    panel.hasShadow = false
    panel.isOpaque = false
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.isExcludedFromWindowsMenu = true
    panel.becomesKeyOnlyIfNeeded = true
    panel.isFloatingPanel = true
    panel.backgroundColor = .clear
    // A nonactivating panel never becomes key; AppKit would render Liquid Glass
    // as an inactive light wash. Pin the panel to dark so the clear refractive
    // surface stays readable while another app is frontmost.
    panel.appearance = NSAppearance(named: .darkAqua)
  }

  // MARK: - Frame

  private var currentFrame: CGRect {
    panel.frame
  }

  private func applyFrame(_ frame: CGRect) {
    panel.setFrame(frame, display: true)
    layoutLayers()
  }

  private func restoreFrame() {
    let size = CGSize(
      width: DesktopLyricsRenderer.panelWidth,
      height: DesktopLyricsRenderer.estimatedPanelHeight(style: style)
    )
    var frame = CGRect(
      origin: Self.defaultOrigin(for: size),
      size: size
    )
    if let stored = UserDefaults.standard.array(
      forKey: Self.frameDefaultsKey
    ) as? [Double],
      stored.count == 4 {
      let storedHeight = stored[3]
      let height = (44 ... 400).contains(storedHeight)
        ? storedHeight
        : size.height
      let candidate = CGRect(
        x: stored[0],
        y: stored[1],
        width: size.width,
        height: height
      )
      if Self.isOnAnyScreen(candidate) {
        frame = candidate
      }
    }
    applyFrame(frame)
  }

  private func saveFrame() {
    let frame = currentFrame
    UserDefaults.standard.set(
      [frame.origin.x, frame.origin.y, frame.width, frame.height],
      forKey: Self.frameDefaultsKey
    )
  }

  @objc
  private func windowDidMove(_ notification: Notification) {
    // The height spring moves the window origin at 60 Hz; the resting frame
    // is written once when it settles.
    if isAnimatingResize { return }
    saveFrame()
    if clickThrough {
      positionControlWindow()
      if isToolbarVisible {
        controlWindow?.orderFrontRegardless()
      }
    }
    positionOffsetPanel()
    let scale = Self.currentScreenScale(for: panel)
    if abs(scale - screenScale) > 0.01 {
      screenScale = scale
      reloadCurrentContent()
    }
  }

  @objc
  private func windowDidChangeScreen(_ notification: Notification) {
    let scale = Self.currentScreenScale(for: panel)
    guard abs(scale - screenScale) > 0.01 else { return }
    screenScale = scale
    reloadCurrentContent()
  }

  private func reloadCurrentContent() {
    guard let content = lastContent else { return }
    reload(content: content)
  }

  private static func currentScreenScale(for window: NSWindow) -> CGFloat {
    (window.screen ?? NSScreen.main)?.backingScaleFactor ?? 2
  }

  private static func defaultOrigin(for size: CGSize) -> CGPoint {
    guard let frame = mainScreenVisibleFrame() else {
      return CGPoint(x: 160, y: 140)
    }
    return CGPoint(
      x: frame.midX - size.width / 2,
      y: frame.minY + 110
    )
  }

  private static func isOnAnyScreen(_ frame: CGRect) -> Bool {
    NSScreen.screens.contains { screen in
      screen.visibleFrame.intersects(frame.insetBy(dx: 60, dy: 30))
    }
  }

  private static func mainScreenVisibleFrame() -> CGRect? {
    NSScreen.main?.visibleFrame
  }

  // MARK: - Colors

  private static let whiteColor = CGColor(gray: 1, alpha: 1)
  private static let clearColor = CGColor(gray: 1, alpha: 0)
}
