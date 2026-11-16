//
//  DesktopLyricsWindow.swift
//  fmusic
//
//  Floating, always-on-top lyrics overlay for macOS.
//
//  AppKit's window and view classes are not exposed to Mac Catalyst, so the panel is created
//  through the Objective-C runtime (the same approach as MacWindowHelper).
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

#if targetEnvironment(macCatalyst)

  import fmusicKit
  import NaturalLanguage
  import QuartzCore
  import UIKit

  // MARK: - DesktopLyricsContent

  struct DesktopLyricsContent {
    // "Title · Artist", shown in the small line at the top-left of the capsule.
    let headerText: String?
    let currentText: String
    let nextText: String?
    let syllables: [LyricsSyllableTiming]
    let syllableProgress: [CGFloat]
  }

  struct DesktopLyricsStyle: Equatable {
    var pointSize: CGFloat
    // 0 = fully transparent background, 1 = opaque card
    var backgroundOpacity: Double
    var alignment: DesktopLyricsAlignment
    var showsNextLine: Bool
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
    static let sung = UIColor(white: 1, alpha: 1)
    static let unsung = UIColor(white: 144.0 / 255.0, alpha: 1)
    /// 0.85 preview opacity × 0.46 unsung alpha for the secondary surface.
    static let secondary = UIColor(white: 1, alpha: 0.85 * 0.46)
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
    // These measurements match OverlayControlLayout in LyricsX Next.
    static let toolbarHeight: CGFloat = 34
    static let toolbarButtonSize: CGFloat = 30
    static let toolbarButtonSpacing: CGFloat = 2
    static let toolbarPadding: CGFloat = 4
    static let toolbarTopInset: CGFloat = 8
    static let toolbarRightInset: CGFloat = 14
    static let toolbarButtonCount = 5
    static let toolbarWidth = CGFloat(toolbarButtonCount) * toolbarButtonSize
      + CGFloat(toolbarButtonCount - 1) * toolbarButtonSpacing
      + toolbarPadding * 2

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

      let font = UIFont.systemFont(ofSize: style.pointSize, weight: .semibold)
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

      let height = max(ceil(layout.height), ceil(font.lineHeight))
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
      font: UIFont,
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
      shadow.shadowColor = UIColor.black.withAlphaComponent(
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

      let font = UIFont.systemFont(ofSize: nextFontSize(style), weight: .semibold)
      let paragraph = NSMutableParagraphStyle()
      paragraph.alignment = textAlignment(style.alignment)
      paragraph.lineBreakMode = .byTruncatingTail
      paragraph.lineSpacing = 0

      let shadow = NSShadow()
      shadow.shadowColor = UIColor.black.withAlphaComponent(
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
      let height = max(ceil(layout.height), ceil(font.lineHeight))
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

      let font = UIFont.systemFont(
        ofSize: headerFontSize(style),
        weight: .medium
      )
      let paragraph = NSMutableParagraphStyle()
      paragraph.alignment = .left
      paragraph.lineBreakMode = .byTruncatingTail

      let shadow = NSShadow()
      shadow.shadowColor = UIColor.black.withAlphaComponent(0.60)
      shadow.shadowBlurRadius = 1
      shadow.shadowOffset = CGSize(width: 0, height: 1)

      let attributed = NSAttributedString(
        string: text,
        attributes: [
          .font: font,
          .foregroundColor: UIColor.white.withAlphaComponent(0.92),
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
      let height = max(ceil(layout.height), ceil(font.lineHeight))
      let size = CGSize(width: width, height: height)
      guard let image = rasterize(layout, size: size, scale: scale) else { return nil }
      return DesktopLyricsHeaderRender(text: text, image: image, height: height)
    }

    // MARK: Helpers

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
      shadow.shadowColor = UIColor.black.withAlphaComponent(
        DesktopLyricsInk.tightShadowAlpha
      )
      shadow.shadowBlurRadius = DesktopLyricsInk.tightShadowBlur
      shadow.shadowOffset = .zero
      return shadow
    }

    private static func primaryAttributes(
      font: UIFont,
      color: UIColor,
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
      foregroundColor: UIColor? = nil,
      shadow: NSShadow? = nil
    )
      -> CGImage? {
      guard size.width > 0, size.height > 0 else { return nil }
      let format = UIGraphicsImageRendererFormat()
      format.scale = max(scale, 1)
      format.opaque = false
      let renderer = UIGraphicsImageRenderer(size: size, format: format)
      return renderer.image { context in
        context.cgContext.translateBy(x: origin.x, y: origin.y)
        if let foregroundColor {
          layout.draw(foregroundColor: foregroundColor, shadow: shadow)
        } else {
          layout.draw()
        }
      }.cgImage
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

  // MARK: - DesktopLyricsPanelController

  @MainActor
  final class DesktopLyricsPanelController: NSObject {
    private static let frameDefaultsKey = "fmusic.desktopLyrics.frame"
    private static let positionLockKey = "fmusic.desktopLyrics.positionLocked"
    private static let windowLevelFloating = 3
    // canJoinAllSpaces (1) | fullScreenAuxiliary (16) | stationary (64)
    private static let collectionBehavior = 1 | 16 | 64
    // nonactivatingPanel (128): clicking the overlay never activates fmusic.
    private static let panelStyleMask: UInt = 1 << 7

    private let window: NSObject
    private let contentView: NSObject
    private let rootLayer: CALayer
    private var backgroundView: NSObject?

    private let scrimLayer = CAGradientLayer()
    private let solidLayer = CALayer()
    private let borderLayer = CALayer()
    private let contentLayer = CALayer()
    private static let whiteColor = UIColor.white.cgColor
    private static let clearColor = UIColor.white.withAlphaComponent(0).cgColor

    private struct SyllableLayerBundle {
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
    }

    /// One spoken word: its syllables are averaged into a single envelope, and
    /// each member bundle reuses that average instead of recomputing it.
    private struct MotionGroupRuntime {
      let syllableIndices: [Int]
      let duration: TimeInterval
      var bundleIndices: [Int]
    }

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

    private var toolbarContainer: NSObject?
    private var toolbarButtons: [NSObject] = []
    private var hoverTimer: Timer?
    private var isToolbarVisible = false
    private var positionLocked = false
    private var clickThrough = false
    private var applyingClickThrough = false
    private var usesGlassMaterial = false
    private var toolbarToken = 0
    private struct ActiveResize {
      let top: CGFloat
      let startHeight: CGFloat
      let height: CGFloat
      let started: CFTimeInterval
      let duration: TimeInterval
    }

    private var resizeTimer: Timer?
    private var activeResize: ActiveResize?
    private var isAnimatingResize = false
    private var controlWindow: NSObject?
    private var offsetPanel: NSObject?
    private var offsetSongID: String?
    private var offsetValueField: NSObject?
    private var offsetDetailField: NSObject?
    private var offsetClickMonitor: Any?
    private var offsetGlobalMonitor: Any?

    var onOpenMainWindow: (() -> ())?
    var onHideDesktopLyrics: (() -> ())?
    var onClickThroughChanged: ((Bool) -> ())?
    var offsetSnapshot: (() -> OverlayOffsetSnapshot?)?
    var adjustSongOffset: ((String, Int) -> OverlayOffsetSnapshot?)?
    var resetSongOffset: ((String) -> OverlayOffsetSnapshot?)?

    private init(window: NSObject, contentView: NSObject, rootLayer: CALayer) {
      self.window = window
      self.contentView = contentView
      self.rootLayer = rootLayer
      super.init()

      configureWindow()
      self.screenScale = Self.currentScreenScale(for: window)
      installBackground()
      installLayers()
      installToolbar()
      self.positionLocked = UserDefaults.standard.bool(forKey: Self.positionLockKey)
      setPositionLocked(positionLocked)
      updateToolbarImages()
      updateChrome()
      restoreFrame()

      NotificationCenter.default.addObserver(
        self,
        selector: #selector(windowDidMove(_:)),
        name: NSNotification.Name("NSWindowDidMoveNotification"),
        object: window
      )
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(windowDidChangeScreen(_:)),
        name: NSNotification.Name("NSWindowDidChangeScreenNotification"),
        object: window
      )
    }

    deinit {
      NotificationCenter.default.removeObserver(self)
    }

    static func make() -> DesktopLyricsPanelController? {
      guard let created = makePanel() else { return nil }
      return DesktopLyricsPanelController(
        window: created.window,
        contentView: created.contentView,
        rootLayer: created.layer
      )
    }

    // MARK: Public

    var isVisible: Bool {
      (window.value(forKey: "visible") as? Bool) ?? false
    }

    func show() {
      screenScale = Self.currentScreenScale(for: window)
      // The panel follows the current appearance, which may have flipped while
      // it was hidden, so refresh the chrome before it appears again.
      updateChrome()
      window.perform(NSSelectorFromString("orderFrontRegardless"))
      startHoverTracking()
    }

    func hide() {
      stopHoverTracking()
      closeOffsetPanel()
      controlWindow?.perform(NSSelectorFromString("orderOut:"), with: nil)
      _ = window.perform(NSSelectorFromString("orderOut:"), with: nil)
    }

    func setAlwaysOnTop(_ isAlwaysOnTop: Bool) {
      let level = isAlwaysOnTop ? Self.windowLevelFloating : 0
      setWindowValue(
        NSNumber(value: level),
        forKey: "level",
        selector: "setLevel:"
      )
      controlWindow?.setValue(NSNumber(value: level + 1), forKey: "level")
      offsetPanel?.setValue(NSNumber(value: level + 2), forKey: "level")
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

    // MARK: Content installation

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
          duration: duration,
          bundleIndices: []
        ))
      }
      for render in line.syllableRenders {
        let runtimeIndex: Int
        if let existing = groupIndexBySyllable[render.index] {
          runtimeIndex = existing
        } else {
          runtimes.append(MotionGroupRuntime(
            syllableIndices: [render.index],
            duration: render.duration,
            bundleIndices: []
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
        container.shadowColor = UIColor.black.cgColor
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
        glow.shadowColor = UIColor.white.withAlphaComponent(0.82).cgColor
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
        let bundleIndex = surface.syllableBundles.count
        surface.syllableBundles.append(SyllableLayerBundle(
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
        ))
        runtimes[runtimeIndex].bundleIndices.append(bundleIndex)
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

    // MARK: Hover control strip

    private func installToolbar() {
      guard let container = Self.makeToolbarBackground() else { return }
      if let layer = container.value(forKey: "layer") as? CALayer {
        layer.zPosition = 10
      }
      container.setValue(true, forKey: "hidden")
      contentView.perform(NSSelectorFromString("addSubview:"), with: container)
      toolbarContainer = container

      // Matches LyricsX Next: sync, open window, lock, click-through, hide.
      let specs: [(String, String, Selector)] = [
        ("timer", "调节歌词同步", #selector(toolbarSyncPressed)),
        ("arrow.up.left.and.arrow.down.right", "打开主窗口", #selector(toolbarOpenPressed)),
        ("lock.open", "锁定位置", #selector(toolbarLockPressed)),
        ("cursorarrow.rays", "开启点击穿透", #selector(toolbarClickThroughPressed)),
        ("xmark", "隐藏悬浮歌词", #selector(toolbarClosePressed)),
      ]
      for (index, spec) in specs.enumerated() {
        guard let button = Self.makeToolbarButton(
          symbol: spec.0,
          tooltip: spec.1,
          target: self,
          action: spec.2
        )
        else { continue }
        button.setValue(
          NSValue(cgRect: Self.toolbarButtonFrame(at: index)),
          forKey: "frame"
        )
        container.perform(NSSelectorFromString("addSubview:"), with: button)
        toolbarButtons.append(button)
      }
    }

    /// A regular-material capsule with a dark ink tint, like the SwiftUI control
    /// strip in LyricsX Next. A second clear glass would refract the glyphs.
    private static func makeToolbarBackground() -> NSObject? {
      if let effectClass = NSClassFromString("NSVisualEffectView") as? NSObject.Type,
         let allocated = effectClass.perform(NSSelectorFromString("alloc"))?
         .takeUnretainedValue(),
         let view = initWithFrame(allocated, class: effectClass, frame: .zero) {
        // HUD material stays dark over light desktops, so white glyphs keep
        // the contrast LyricsX Next's control strip has.
        setValueIfSupported(NSNumber(value: 13), forKey: "material", on: view)
        setValueIfSupported(NSNumber(value: 0), forKey: "blendingMode", on: view)
        setValueIfSupported(NSNumber(value: 1), forKey: "state", on: view)
        applyDarkAppearance(to: view)
        view.setValue(true, forKey: "wantsLayer")
        if let layer = view.value(forKey: "layer") as? CALayer {
          layer.cornerRadius = DesktopLyricsRenderer.toolbarHeight / 2
          layer.cornerCurve = .continuous
          layer.masksToBounds = true
          layer.borderWidth = 0.5
          layer.borderColor = cgColor(white: 1, alpha: 0.16)
        }
        if let tint = makePlainView() {
          tint.setValue(true, forKey: "wantsLayer")
          if let layer = tint.value(forKey: "layer") as? CALayer {
            layer.backgroundColor = cgColor(white: 0, alpha: 0.22)
          }
          tint.setValue(NSNumber(value: 2 | 16), forKey: "autoresizingMask")
          tint.setValue(NSValue(cgRect: CGRect(
            x: 0,
            y: 0,
            width: DesktopLyricsRenderer.toolbarWidth,
            height: DesktopLyricsRenderer.toolbarHeight
          )), forKey: "frame")
          view.perform(NSSelectorFromString("addSubview:"), with: tint)
        }
        return view
      }
      guard let container = makePlainView() else { return nil }
      container.setValue(true, forKey: "wantsLayer")
      if let layer = container.value(forKey: "layer") as? CALayer {
        layer.backgroundColor = UIColor(white: 0.10, alpha: 0.62).cgColor
        layer.cornerRadius = DesktopLyricsRenderer.toolbarHeight / 2
        layer.cornerCurve = .continuous
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
      }
      return container
    }

    private static func makePlainView() -> NSObject? {
      guard let viewClass = NSClassFromString("NSView") as? NSObject.Type,
            let allocated = viewClass.perform(NSSelectorFromString("alloc"))?
            .takeUnretainedValue()
      else { return nil }
      return initWithFrame(allocated, class: viewClass, frame: .zero)
    }

    /// The lyric panel is nonactivating and cannot become key, so AppKit would
    /// otherwise swallow the first click. LyricsX hosts SwiftUI controls, which
    /// receive it; an NSButton subclass restores the same behavior.
    private static func overlayButtonClass() -> AnyClass? {
      let name = "FMOverlayButton"
      if let existing = NSClassFromString(name) { return existing }
      guard let superclass: AnyClass = NSClassFromString("NSButton"),
            let subclass = objc_allocateClassPair(superclass, name, 0)
      else { return nil }
      typealias FirstMouseBlock = @convention(block) (AnyObject, AnyObject) -> Bool
      let accepts: FirstMouseBlock = { _, _ in true }
      class_addMethod(
        subclass,
        NSSelectorFromString("acceptsFirstMouse:"),
        imp_implementationWithBlock(accepts),
        "B@:@"
      )
      objc_registerClassPair(subclass)
      return subclass
    }

    private static func makeToolbarButton(
      symbol: String,
      tooltip: String,
      target: NSObject,
      action: Selector
    )
      -> NSObject? {
      guard let buttonClass = overlayButtonClass() as? NSObject.Type,
            let allocated = buttonClass.perform(NSSelectorFromString("alloc"))?
            .takeUnretainedValue(),
            let button = initWithFrame(allocated, class: buttonClass, frame: .zero)
      else { return nil }
      setValueIfSupported(false, forKey: "bordered", on: button)
      setValueIfSupported(NSNumber(value: 1), forKey: "focusRingType", on: button)
      setValueIfSupported(NSNumber(value: 1), forKey: "imagePosition", on: button)
      setValueIfSupported(NSNumber(value: 0), forKey: "imageScaling", on: button)
      button.setValue(true, forKey: "wantsLayer")
      if let image = symbolImage(symbol) {
        setValueIfSupported(image, forKey: "image", on: button)
      }
      if let ink = nsColor(white: 1, alpha: 0.92) {
        setValueIfSupported(ink, forKey: "contentTintColor", on: button)
      }
      setValueIfSupported(tooltip, forKey: "toolTip", on: button)
      setValueIfSupported(target, forKey: "target", on: button)
      setAction(action, on: button)
      return button
    }

    private static func symbolImage(_ name: String, pointSize: CGFloat = 15) -> NSObject? {
      guard let imageClass = NSClassFromString("NSImage") as? NSObject.Type
      else { return nil }
      let selector = NSSelectorFromString(
        "imageWithSystemSymbolName:accessibilityDescription:"
      )
      guard imageClass.responds(to: selector) else { return nil }
      guard let base = imageClass.perform(selector, with: name, with: nil)?
        .takeUnretainedValue() as? NSObject
      else { return nil }
      let configSelector = NSSelectorFromString("configurationWithPointSize:weight:")
      guard let configClass: AnyClass = NSClassFromString("NSImageSymbolConfiguration"),
            let method = class_getClassMethod(configClass, configSelector),
            base.responds(to: NSSelectorFromString("imageWithSymbolConfiguration:"))
      else { return base }
      typealias ConfigFunc = @convention(c)
        (AnyObject, Selector, CGFloat, CGFloat) -> AnyObject?
      let configure = unsafeBitCast(
        method_getImplementation(method),
        to: ConfigFunc.self
      )
      guard let configuration = configure(
        configClass as AnyObject,
        configSelector,
        pointSize,
        0.23 // NSFontWeightMedium
      ) else { return base }
      return base.perform(
        NSSelectorFromString("imageWithSymbolConfiguration:"),
        with: configuration
      )?.takeUnretainedValue() as? NSObject
    }

    private static func nsColor(white: CGFloat, alpha: CGFloat) -> NSObject? {
      guard let colorClass: AnyClass = NSClassFromString("NSColor") else { return nil }
      let selector = NSSelectorFromString("colorWithWhite:alpha:")
      guard let method = class_getClassMethod(colorClass, selector) else { return nil }
      typealias ColorFunc = @convention(c)
        (AnyObject, Selector, CGFloat, CGFloat) -> AnyObject?
      let function = unsafeBitCast(
        method_getImplementation(method),
        to: ColorFunc.self
      )
      return function(colorClass as AnyObject, selector, white, alpha) as? NSObject
    }

    private static func cgColor(white: CGFloat, alpha: CGFloat) -> CGColor {
      UIColor(white: white, alpha: alpha).cgColor
    }

    private static func applyDarkAppearance(to view: NSObject) {
      guard let appearanceClass = NSClassFromString("NSAppearance") as? NSObject.Type,
            let dark = appearanceClass.perform(
              NSSelectorFromString("appearanceNamed:"),
              with: "NSAppearanceNameDarkAqua"
            )?.takeUnretainedValue()
      else { return }
      setValueIfSupported(dark, forKey: "appearance", on: view)
    }

    private static func setAction(_ action: Selector, on target: NSObject) {
      let selector = NSSelectorFromString("setAction:")
      guard let method = class_getInstanceMethod(type(of: target), selector)
      else { return }
      typealias SetActionFunc = @convention(c) (AnyObject, Selector, Selector) -> ()
      let function = unsafeBitCast(
        method_getImplementation(method),
        to: SetActionFunc.self
      )
      function(target, selector, action)
    }

    private static func setValueIfSupported(
      _ value: Any?,
      forKey key: String,
      on object: NSObject?
    ) {
      guard let object else { return }
      let setter = "set" + key.prefix(1).uppercased()
        + String(key.dropFirst()) + ":"
      guard object.responds(to: NSSelectorFromString(setter)) else { return }
      object.setValue(value, forKey: key)
    }

    private static func toolbarButtonFrame(at index: Int) -> CGRect {
      let size = DesktopLyricsRenderer.toolbarButtonSize
      return CGRect(
        x: DesktopLyricsRenderer.toolbarPadding
          + CGFloat(index) * (size + DesktopLyricsRenderer.toolbarButtonSpacing),
        y: (DesktopLyricsRenderer.toolbarHeight - size) / 2,
        width: size,
        height: size
      )
    }

    private func updateToolbarImages() {
      guard toolbarButtons.count >= 5 else { return }
      let locked = positionLocked
      changeSymbol(of: toolbarButtons[2], to: locked ? "lock.fill" : "lock.open")
      Self.setActive(locked, on: toolbarButtons[2])
      Self.setValueIfSupported(
        locked ? "解锁并恢复拖动" : "锁定位置",
        forKey: "toolTip",
        on: toolbarButtons[2]
      )
      let through = clickThrough
      changeSymbol(
        of: toolbarButtons[3],
        to: through ? "cursorarrow.slash" : "cursorarrow.rays"
      )
      Self.setActive(through, on: toolbarButtons[3])
      Self.setValueIfSupported(
        through ? "关闭点击穿透" : "开启点击穿透",
        forKey: "toolTip",
        on: toolbarButtons[3]
      )
    }

    private static func setActive(_ active: Bool, on button: NSObject) {
      guard let layer = button.value(forKey: "layer") as? CALayer else { return }
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      layer.cornerRadius = DesktopLyricsRenderer.toolbarButtonSize / 2
      layer.backgroundColor = active
        ? cgColor(white: 1, alpha: 0.10)
        : UIColor.clear.cgColor
      CATransaction.commit()
    }

    private func changeSymbol(of button: NSObject, to name: String) {
      if let image = Self.symbolImage(name) {
        Self.setValueIfSupported(image, forKey: "image", on: button)
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
      setWindowValue(
        !locked,
        forKey: "movableByWindowBackground",
        selector: "setMovableByWindowBackground:"
      )
    }

    // MARK: Click-through

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
          controlWindow = Self.makeBorderlessPanel(size: CGSize(
            width: DesktopLyricsRenderer.toolbarWidth,
            height: DesktopLyricsRenderer.toolbarHeight
          ))
          controlWindow?.setValue(
            NSNumber(value: Self.windowLevelFloating + 1),
            forKey: "level"
          )
          controlWindow?.setValue(false, forKey: "ignoresMouseEvents")
        }
        positionControlWindow()
        if let container = toolbarContainer {
          container.perform(NSSelectorFromString("removeFromSuperview"))
          container.setValue(
            NSNumber(value: 2 | 16),
            forKey: "autoresizingMask"
          )
          container.setValue(
            NSValue(cgRect: CGRect(
              x: 0,
              y: 0,
              width: DesktopLyricsRenderer.toolbarWidth,
              height: DesktopLyricsRenderer.toolbarHeight
            )),
            forKey: "frame"
          )
          controlWindow?.setValue(container, forKey: "contentView")
        }
      } else {
        controlWindow?.perform(NSSelectorFromString("orderOut:"), with: nil)
        controlWindow?.setValue(nil, forKey: "contentView")
        if let container = toolbarContainer {
          container.perform(NSSelectorFromString("removeFromSuperview"))
          container.setValue(NSNumber(value: 0), forKey: "autoresizingMask")
          contentView.perform(NSSelectorFromString("addSubview:"), with: container)
        }
      }
      setWindowValue(
        enabled,
        forKey: "ignoresMouseEvents",
        selector: "setIgnoresMouseEvents:"
      )
      updateToolbarImages()
      if notify {
        onClickThroughChanged?(enabled)
      }
      isToolbarVisible = false
      toolbarContainer?.setValue(true, forKey: "hidden")
      layoutLayers()
      hoverTick()
    }

    private func positionControlWindow() {
      guard clickThrough, let controlWindow else { return }
      let frame = currentFrame
      let origin = CGPoint(
        x: frame.maxX - DesktopLyricsRenderer.toolbarWidth
          - DesktopLyricsRenderer.toolbarRightInset,
        y: frame.maxY - DesktopLyricsRenderer.toolbarHeight
          - DesktopLyricsRenderer.toolbarTopInset
      )
      Self.setFrameOrigin(origin, on: controlWindow)
    }

    // MARK: Hover tracking

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
      let point = Self.mouseLocationOnScreen()
      var isInside = point.map { currentFrame.contains($0) } ?? false
      if !isInside, let point, let editor = offsetPanel,
         let editorFrame = Self.frame(of: editor) {
        isInside = editorFrame.contains(point)
      }
      setToolbarVisible(isInside)
    }

    private static let mouseLocationProvider: (() -> CGPoint)? = {
      let selector = NSSelectorFromString("mouseLocation")
      guard let eventClass: AnyClass = NSClassFromString("NSEvent"),
            let method = class_getClassMethod(eventClass, selector)
      else { return nil }
      typealias LocationFunc = @convention(c) (AnyObject, Selector) -> CGPoint
      let function = unsafeBitCast(
        method_getImplementation(method),
        to: LocationFunc.self
      )
      return { function(eventClass as AnyObject, selector) }
    }()

    private static func mouseLocationOnScreen() -> CGPoint? {
      mouseLocationProvider?()
    }

    private func setToolbarVisible(_ visible: Bool) {
      guard visible != isToolbarVisible, let container = toolbarContainer
      else { return }
      isToolbarVisible = visible
      toolbarToken += 1
      let token = toolbarToken
      if visible {
        container.setValue(false, forKey: "hidden")
        if clickThrough {
          positionControlWindow()
          controlWindow?.perform(NSSelectorFromString("orderFrontRegardless"))
        }
      }
      guard let layer = container.value(forKey: "layer") as? CALayer else {
        container.setValue(!visible, forKey: "hidden")
        if !visible, clickThrough {
          controlWindow?.perform(NSSelectorFromString("orderOut:"), with: nil)
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
        toolbarContainer?.setValue(true, forKey: "hidden")
        if clickThrough {
          controlWindow?.perform(NSSelectorFromString("orderOut:"), with: nil)
        }
      }
    }

    // MARK: Lyrics sync panel

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
      guard let panel = Self.makeBorderlessPanel(size: size) else { return }
      panel.setValue(
        NSNumber(value: (
          window.value(forKey: "level") as? Int
            ?? Self.windowLevelFloating
        ) + 2),
        forKey: "level"
      )
      Self.setValueIfSupported("歌词同步调节", forKey: "accessibilityLabel", on: panel)
      guard let content = makeOffsetPanelContent(size: size) else { return }
      panel.setValue(content, forKey: "contentView")
      offsetPanel = panel
      refreshOffsetFields(snapshot)
      positionOffsetPanel()
      panel.perform(NSSelectorFromString("orderFrontRegardless"))
      installOffsetMonitors(for: panel)
    }

    private func installOffsetMonitors(for panel: NSObject) {
      guard let eventClass: AnyClass = NSClassFromString("NSEvent") else { return }
      let localSelector = NSSelectorFromString(
        "addLocalMonitorForEventsMatchingMask:handler:"
      )
      if let method = class_getClassMethod(eventClass, localSelector) {
        typealias LocalBlock = @convention(block) (AnyObject) -> AnyObject?
        let block: LocalBlock = { [weak self] event in
          guard let self else { return event }
          guard let point = Self.mouseLocationOnScreen() else { return event }
          if let panelFrame = Self.frame(of: panel), panelFrame.contains(point) {
            return event
          }
          if let toolbarFrame = toolbarScreenFrame(),
             toolbarFrame.contains(point) {
            return event
          }
          closeOffsetPanel()
          return event
        }
        typealias AddMonitorFunc = @convention(c)
          (AnyObject, Selector, UInt64, AnyObject) -> AnyObject?
        let function = unsafeBitCast(
          method_getImplementation(method),
          to: AddMonitorFunc.self
        )
        offsetClickMonitor = function(
          eventClass as AnyObject,
          localSelector,
          Self.mouseDownMask,
          block as AnyObject
        )
      }
      let globalSelector = NSSelectorFromString(
        "addGlobalMonitorForEventsMatchingMask:handler:"
      )
      if let method = class_getClassMethod(eventClass, globalSelector) {
        typealias GlobalBlock = @convention(block) (AnyObject) -> ()
        let block: GlobalBlock = { [weak self] _ in
          Task { @MainActor in self?.closeOffsetPanel() }
        }
        typealias AddMonitorFunc = @convention(c)
          (AnyObject, Selector, UInt64, AnyObject) -> AnyObject?
        let function = unsafeBitCast(
          method_getImplementation(method),
          to: AddMonitorFunc.self
        )
        offsetGlobalMonitor = function(
          eventClass as AnyObject,
          globalSelector,
          Self.mouseDownMask,
          block as AnyObject
        )
      }
    }

    // leftMouseDown (1 << 1) | rightMouseDown (1 << 3) in AppKit.
    private static let mouseDownMask: UInt64 = (1 << 1) | (1 << 3)

    private static func removeEventMonitor(_ monitor: Any) {
      guard let object = monitor as? NSObject,
            let eventClass: AnyClass = NSClassFromString("NSEvent")
      else { return }
      let selector = NSSelectorFromString("removeMonitor:")
      guard let method = class_getClassMethod(eventClass, selector) else { return }
      typealias RemoveFunc = @convention(c)
        (AnyObject, Selector, AnyObject) -> ()
      let function = unsafeBitCast(
        method_getImplementation(method),
        to: RemoveFunc.self
      )
      function(eventClass as AnyObject, selector, object)
    }

    private func makeOffsetPanelContent(size: CGSize) -> NSObject? {
      guard let effectClass = NSClassFromString("NSVisualEffectView") as? NSObject.Type,
            let allocated = effectClass.perform(NSSelectorFromString("alloc"))?
            .takeUnretainedValue(),
            let background = Self.initWithFrame(
              allocated,
              class: effectClass,
              frame: CGRect(origin: .zero, size: size)
            )
      else { return nil }
      Self.setValueIfSupported(NSNumber(value: 6), forKey: "material", on: background)
      Self.setValueIfSupported(NSNumber(value: 0), forKey: "blendingMode", on: background)
      Self.setValueIfSupported(NSNumber(value: 1), forKey: "state", on: background)
      Self.applyDarkAppearance(to: background)
      background.setValue(true, forKey: "wantsLayer")
      if let layer = background.value(forKey: "layer") as? CALayer {
        layer.cornerRadius = 24
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        layer.borderWidth = 0.5
        layer.borderColor = Self.cgColor(white: 1, alpha: 0.16)
      }
      if let shade = Self.makePlainView() {
        shade.setValue(true, forKey: "wantsLayer")
        shade.setValue(NSNumber(value: 2 | 16), forKey: "autoresizingMask")
        shade.setValue(NSValue(cgRect: CGRect(origin: .zero, size: size)), forKey: "frame")
        if let layer = shade.value(forKey: "layer") as? CALayer {
          layer.backgroundColor = Self.cgColor(white: 0, alpha: 0.55)
        }
        background.perform(NSSelectorFromString("addSubview:"), with: shade)
      }

      addLabel(
        "歌词同步",
        frame: CGRect(x: 16, y: 146, width: 220, height: 18),
        size: 13,
        weight: 0.30,
        monospaced: false,
        to: background
      )
      if let close = Self.makeToolbarButton(
        symbol: "xmark",
        tooltip: "关闭歌词同步调节",
        target: self,
        action: #selector(closeOffsetPressed)
      ) {
        close.setValue(
          NSValue(cgRect: CGRect(x: 298, y: 141, width: 26, height: 26)),
          forKey: "frame"
        )
        background.perform(NSSelectorFromString("addSubview:"), with: close)
      }

      offsetValueField = addLabel(
        "",
        frame: CGRect(x: 16, y: 108, width: 308, height: 20),
        size: 15,
        weight: 0.30,
        monospaced: true,
        to: background
      )
      offsetDetailField = addLabel(
        "",
        frame: CGRect(x: 16, y: 88, width: 308, height: 16),
        size: 11,
        weight: 0,
        monospaced: true,
        to: background
      )
      if let detail = offsetDetailField, let secondary = Self.secondaryLabelColor() {
        Self.setValueIfSupported(secondary, forKey: "textColor", on: detail)
      }

      if let button = makeOffsetButton(
        "延后 0.1 秒",
        frame: CGRect(x: 16, y: 51, width: 98, height: 24),
        action: #selector(offsetLaterPressed)
      ) {
        background.perform(NSSelectorFromString("addSubview:"), with: button)
      }
      if let button = makeOffsetButton(
        "提前 0.1 秒",
        frame: CGRect(x: 117, y: 51, width: 98, height: 24),
        action: #selector(offsetEarlyPressed)
      ) {
        background.perform(NSSelectorFromString("addSubview:"), with: button)
      }
      if let button = makeOffsetButton(
        "重置",
        frame: CGRect(x: 218, y: 51, width: 106, height: 24),
        action: #selector(offsetResetPressed)
      ) {
        background.perform(NSSelectorFromString("addSubview:"), with: button)
      }

      let caption = addLabel(
        "此处只调整或重置单曲偏移；通用偏移请在播放器的歌词偏移菜单中调整。",
        frame: CGRect(x: 16, y: 12, width: 308, height: 32),
        size: 11,
        weight: 0,
        monospaced: false,
        to: background
      )
      if let caption, let secondary = Self.secondaryLabelColor() {
        Self.setValueIfSupported(secondary, forKey: "textColor", on: caption)
        if let cell = caption.value(forKey: "cell") as? NSObject {
          Self.setValueIfSupported(NSNumber(value: 0), forKey: "lineBreakMode", on: cell)
          Self.setValueIfSupported(true, forKey: "wraps", on: cell)
          Self.setValueIfSupported(false, forKey: "usesSingleLineMode", on: cell)
        }
        Self.setValueIfSupported(NSNumber(value: 2), forKey: "maximumNumberOfLines", on: caption)
      }
      return background
    }

    @discardableResult
    private func addLabel(
      _ text: String,
      frame: CGRect,
      size: CGFloat,
      weight: CGFloat,
      monospaced: Bool,
      to parent: NSObject
    )
      -> NSObject? {
      guard let fieldClass = NSClassFromString("NSTextField") as? NSObject.Type,
            let field = fieldClass.perform(
              NSSelectorFromString("labelWithString:"),
              with: text
            )?.takeUnretainedValue() as? NSObject
      else { return nil }
      if let font = Self.nsFont(size: size, weight: weight, monospaced: monospaced) {
        Self.setValueIfSupported(font, forKey: "font", on: field)
      }
      Self.setValueIfSupported(NSNumber(value: 0), forKey: "alignment", on: field)
      field.setValue(NSValue(cgRect: frame), forKey: "frame")
      parent.perform(NSSelectorFromString("addSubview:"), with: field)
      return field
    }

    private func makeOffsetButton(
      _ title: String,
      frame: CGRect,
      action: Selector
    )
      -> NSObject? {
      guard let buttonClass = Self.overlayButtonClass() as? NSObject.Type,
            let allocated = buttonClass.perform(NSSelectorFromString("alloc"))?
            .takeUnretainedValue(),
            let button = Self.initWithFrame(allocated, class: buttonClass, frame: frame)
      else { return nil }
      Self.setValueIfSupported(title, forKey: "title", on: button)
      Self.setValueIfSupported(NSNumber(value: 1), forKey: "bezelStyle", on: button)
      Self.setValueIfSupported(NSNumber(value: 1), forKey: "controlSize", on: button)
      Self.setValueIfSupported(NSNumber(value: 0), forKey: "buttonType", on: button)
      Self.setValueIfSupported(self, forKey: "target", on: button)
      Self.setAction(action, on: button)
      if let font = Self.nsFont(size: 11, weight: 0, monospaced: false) {
        Self.setValueIfSupported(font, forKey: "font", on: button)
      }
      return button
    }

    private static func nsFont(
      size: CGFloat,
      weight: CGFloat,
      monospaced: Bool
    )
      -> NSObject? {
      guard let fontClass: AnyClass = NSClassFromString("NSFont") else { return nil }
      let selector = NSSelectorFromString(
        monospaced ? "monospacedDigitSystemFontOfSize:weight:"
          : "systemFontOfSize:weight:"
      )
      guard let method = class_getClassMethod(fontClass, selector) else { return nil }
      typealias FontFunc = @convention(c)
        (AnyObject, Selector, CGFloat, CGFloat) -> AnyObject?
      let function = unsafeBitCast(
        method_getImplementation(method),
        to: FontFunc.self
      )
      return function(fontClass as AnyObject, selector, size, weight) as? NSObject
    }

    private static func secondaryLabelColor() -> NSObject? {
      guard let colorClass = NSClassFromString("NSColor") as? NSObject.Type,
            let color = colorClass.perform(
              NSSelectorFromString("secondaryLabelColor")
            )?.takeUnretainedValue()
      else { return nil }
      return color as? NSObject
    }

    private func refreshOffsetFields(_ snapshot: OverlayOffsetSnapshot) {
      Self.setValueIfSupported(
        String(
          format: "单曲偏移 %+.1f 秒",
          Double(snapshot.songMilliseconds) / 1_000
        ),
        forKey: "stringValue",
        on: offsetValueField
      )
      Self.setValueIfSupported(
        String(
          format: "通用 %+.3f 秒 · 合计 %+.3f 秒",
          Double(snapshot.globalMilliseconds) / 1_000,
          Double(snapshot.totalMilliseconds) / 1_000
        ),
        forKey: "stringValue",
        on: offsetDetailField
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
      if let screen = window.value(forKey: "screen") as? NSObject,
         let visible = (screen.value(forKey: "visibleFrame") as? NSValue)?
         .cgRectValue {
        if origin.y < visible.minY {
          origin.y = main.maxY + 4
        }
        origin.x = min(max(visible.minX, origin.x), visible.maxX - size.width)
        origin.y = min(max(visible.minY, origin.y), visible.maxY - size.height)
      }
      Self.setFrameOrigin(origin, on: panel)
    }

    private func closeOffsetPanel() {
      if let offsetClickMonitor {
        Self.removeEventMonitor(offsetClickMonitor)
      }
      if let offsetGlobalMonitor {
        Self.removeEventMonitor(offsetGlobalMonitor)
      }
      offsetClickMonitor = nil
      offsetGlobalMonitor = nil
      offsetSongID = nil
      offsetValueField = nil
      offsetDetailField = nil
      guard let panel = offsetPanel else { return }
      offsetPanel = nil
      panel.perform(NSSelectorFromString("orderOut:"), with: nil)
      panel.setValue(nil, forKey: "contentView")
      _ = panel.perform(NSSelectorFromString("close"))
    }

    private func toolbarScreenFrame() -> CGRect? {
      if clickThrough, let controlWindow {
        return Self.frame(of: controlWindow)
      }
      guard let container = toolbarContainer,
            let main = window.value(forKey: "frame") as? NSValue,
            let toolbar = container.value(forKey: "frame") as? NSValue
      else { return nil }
      return toolbar.cgRectValue.offsetBy(
        dx: main.cgRectValue.minX,
        dy: main.cgRectValue.minY
      )
    }

    private static func frame(of window: NSObject) -> CGRect? {
      (window.value(forKey: "frame") as? NSValue)?.cgRectValue
    }

    // MARK: Borderless panels

    private static func makeBorderlessPanel(size: CGSize) -> NSObject? {
      guard let panelClass = NSClassFromString("NSPanel") as? NSObject.Type,
            let allocated = panelClass.perform(NSSelectorFromString("alloc"))?
            .takeUnretainedValue()
      else { return nil }
      let selector = NSSelectorFromString(
        "initWithContentRect:styleMask:backing:defer:"
      )
      guard let method = class_getInstanceMethod(panelClass, selector) else {
        return nil
      }
      typealias InitPanelFunc = @convention(c)
        (AnyObject, Selector, CGRect, UInt, UInt, Bool) -> AnyObject?
      let initPanel = unsafeBitCast(
        method_getImplementation(method),
        to: InitPanelFunc.self
      )
      guard let window = initPanel(
        allocated,
        selector,
        CGRect(origin: .zero, size: size),
        panelStyleMask,
        2,
        false
      ) as? NSObject else { return nil }
      let windowSettings: [(String, String, Any)] = [
        ("collectionBehavior", "setCollectionBehavior:", collectionBehavior),
        ("opaque", "setOpaque:", false),
        ("hasShadow", "setHasShadow:", false),
        ("hidesOnDeactivate", "setHidesOnDeactivate:", false),
        ("releasedWhenClosed", "setReleasedWhenClosed:", false),
        ("excludedFromWindowsMenu", "setExcludedFromWindowsMenu:", true),
        ("becomesKeyOnlyIfNeeded", "setBecomesKeyOnlyIfNeeded:", true),
        ("movableByWindowBackground", "setMovableByWindowBackground:", false),
      ]
      for (key, name, value) in windowSettings {
        guard window.responds(to: NSSelectorFromString(name)) else { continue }
        window.setValue(value, forKey: key)
      }
      if let colorClass = NSClassFromString("NSColor") as? NSObject.Type,
         let clear = colorClass.perform(NSSelectorFromString("clearColor"))?
         .takeUnretainedValue() {
        window.setValue(clear, forKey: "backgroundColor")
      }
      applyDarkAppearance(to: window)
      setValueIfSupported(true, forKey: "floatingPanel", on: window)
      return window
    }

    private static func setFrameOrigin(_ origin: CGPoint, on window: NSObject) {
      let selector = NSSelectorFromString("setFrameOrigin:")
      guard let method = class_getInstanceMethod(type(of: window), selector)
      else { return }
      typealias SetOriginFunc = @convention(c)
        (AnyObject, Selector, CGPoint) -> ()
      let function = unsafeBitCast(
        method_getImplementation(method),
        to: SetOriginFunc.self
      )
      function(window, selector, origin)
    }

    // MARK: Clock

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

    // MARK: Line motion

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

    // MARK: Chrome

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
        solidLayer.backgroundColor = Self.cgColor(white: 0.12, alpha: 1)
        solidLayer.opacity = Float(opacity)
      } else {
        solidLayer.isHidden = true
        scrimLayer.colors = [
          UIColor.black.withAlphaComponent(shade).cgColor,
          UIColor.black.withAlphaComponent(shade * 0.66).cgColor,
          UIColor.black.withAlphaComponent(shade * 0.28).cgColor,
          UIColor.black.withAlphaComponent(0).cgColor,
        ]
      }
      // Clear Liquid Glass draws its own refraction highlight along the rim.
      borderLayer.isHidden = !hasChrome || glassActive
      borderLayer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
      CATransaction.commit()

      if let backgroundView,
         backgroundView.responds(to: NSSelectorFromString("setHidden:")) {
        backgroundView.setValue(
          !hasChrome || reduceTransparency,
          forKey: "hidden"
        )
        // A visible glass view is fully blurred at any alpha; scaling the whole
        // backdrop makes the slider progress from clear to frosted instead of
        // getting blurriest in the middle.
        if backgroundView.responds(to: NSSelectorFromString("setAlphaValue:")) {
          backgroundView.setValue(NSNumber(value: opacity), forKey: "alphaValue")
        }
      }
    }

    /// AppKit builds a light backdrop independently of our fixed white ink when
    /// the system switches themes; disable that adaptation like LyricsX Next.
    private static func fixedGlassAppearance(_ view: NSObject) {
      applyDarkAppearance(to: view)
      setValueIfSupported(
        NSNumber(value: 1),
        forKey: "_adaptiveAppearance",
        on: view
      )
    }

    private static func reduceTransparencyEnabled() -> Bool {
      guard let workspaceClass = NSClassFromString("NSWorkspace") as? NSObject.Type,
            let workspace = workspaceClass.perform(
              NSSelectorFromString("sharedWorkspace")
            )?.takeUnretainedValue() as? NSObject
      else { return false }
      return (workspace.value(
        forKey: "accessibilityDisplayShouldReduceTransparency"
      ) as? Bool) ?? false
    }

    // MARK: Layout

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
      let height = max(desiredHeight(), 44)
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
      let bounds = CGRect(origin: .zero, size: currentFrame.size)
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
      if let backgroundView {
        backgroundView.setValue(NSValue(cgRect: bounds), forKey: "frame")
      }

      if let toolbarContainer, !clickThrough {
        toolbarContainer.setValue(
          NSValue(cgRect: CGRect(
            x: bounds.width - DesktopLyricsRenderer.toolbarRightInset
              - DesktopLyricsRenderer.toolbarWidth,
            y: bounds.height - DesktopLyricsRenderer.toolbarTopInset
              - DesktopLyricsRenderer.toolbarHeight,
            width: DesktopLyricsRenderer.toolbarWidth,
            height: DesktopLyricsRenderer.toolbarHeight
          )),
          forKey: "frame"
        )
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
      if backgroundView.responds(to: NSSelectorFromString("setCornerRadius:")) {
        backgroundView.setValue(NSNumber(value: radius), forKey: "cornerRadius")
      } else if let layer = backgroundView.value(forKey: "layer") as? CALayer {
        layer.cornerRadius = radius
        layer.cornerCurve = .continuous
      }
    }

    // MARK: Window content

    private func installBackground() {
      guard let view = Self.makeBackgroundView() else { return }
      backgroundView = view
      usesGlassMaterial = view.responds(to: NSSelectorFromString("setStyle:"))
      if view.responds(to: NSSelectorFromString("setAutoresizingMask:")) {
        // width | height
        view.setValue(NSNumber(value: 2 | 16), forKey: "autoresizingMask")
      }
      contentView.perform(NSSelectorFromString("addSubview:"), with: view)
      // AppKit creates the backing layer lazily, which can insert it above the
      // lyric sublayers added below. Pin it behind them explicitly.
      if let layer = view.value(forKey: "layer") as? CALayer {
        layer.zPosition = 0
      }
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
      borderLayer.backgroundColor = UIColor.clear.cgColor
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
      nextLayer.shadowColor = UIColor.black.cgColor
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
        surface.base.shadowColor = UIColor.black.cgColor
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

    // MARK: Window setup

    /// A nonactivating panel never becomes key, and AppKit renders Liquid Glass
    /// as an inactive light wash whenever its window is not active. LyricsX Next
    /// overrides these private activity queries so the desktop lyrics keep their
    /// clear, refractive surface while another app is frontmost.
    private static func glassPanelClass() -> AnyClass? {
      let name = "FMDesktopLyricsPanel"
      if let existing = NSClassFromString(name) { return existing }
      guard let superclass: AnyClass = NSClassFromString("NSPanel"),
            let subclass = objc_allocateClassPair(superclass, name, 0)
      else { return nil }
      typealias ActivityQuery = @convention(block) (AnyObject) -> Bool
      let active: ActivityQuery = { _ in true }
      class_addMethod(
        subclass,
        NSSelectorFromString("_hasActiveAppearance"),
        imp_implementationWithBlock(active),
        "B@:"
      )
      let activeIgnoringFocus: ActivityQuery = { _ in true }
      class_addMethod(
        subclass,
        NSSelectorFromString("_hasActiveAppearanceIgnoringKeyFocus"),
        imp_implementationWithBlock(activeIgnoringFocus),
        "B@:"
      )
      objc_registerClassPair(subclass)
      return subclass
    }

    private static func makePanel()
      -> (window: NSObject, contentView: NSObject, layer: CALayer)? {
      guard let panelClass = (glassPanelClass() as? NSObject.Type)
        ?? (NSClassFromString("NSPanel") as? NSObject.Type),
        let viewClass = NSClassFromString("NSView") as? NSObject.Type,
        let allocatedPanel = panelClass.perform(NSSelectorFromString("alloc"))?
        .takeUnretainedValue()
      else {
        NSLog("[fmusic] desktop lyrics: NSPanel unavailable")
        return nil
      }

      let panelSelector = NSSelectorFromString(
        "initWithContentRect:styleMask:backing:defer:"
      )
      guard let panelMethod = class_getInstanceMethod(panelClass, panelSelector)
      else {
        NSLog("[fmusic] desktop lyrics: NSPanel initializer missing")
        return nil
      }
      typealias InitPanelFunc = @convention(c)
        (AnyObject, Selector, CGRect, UInt, UInt, Bool) -> AnyObject?
      let initPanel = unsafeBitCast(
        method_getImplementation(panelMethod),
        to: InitPanelFunc.self
      )
      guard let window = initPanel(
        allocatedPanel,
        panelSelector,
        .zero,
        panelStyleMask,
        2, // buffered
        false
      ) as? NSObject else {
        NSLog("[fmusic] desktop lyrics: NSPanel init failed")
        return nil
      }

      guard let allocatedView = viewClass.perform(NSSelectorFromString("alloc"))?
        .takeUnretainedValue(),
        let contentView = initWithFrame(
          allocatedView,
          class: viewClass,
          frame: .zero
        )
      else {
        NSLog("[fmusic] desktop lyrics: NSView creation failed")
        return nil
      }
      contentView.setValue(true, forKey: "wantsLayer")
      window.setValue(contentView, forKey: "contentView")

      guard let layer = contentView.value(forKey: "layer") as? CALayer else {
        NSLog("[fmusic] desktop lyrics: layer missing")
        return nil
      }
      return (window, contentView, layer)
    }

    private static func initWithFrame(
      _ allocated: AnyObject,
      class objectClass: NSObject.Type,
      frame: CGRect
    )
      -> NSObject? {
      let selector = NSSelectorFromString("initWithFrame:")
      guard let method = class_getInstanceMethod(objectClass, selector)
      else { return nil }
      typealias InitViewFunc = @convention(c)
        (AnyObject, Selector, CGRect) -> AnyObject?
      let function = unsafeBitCast(
        method_getImplementation(method),
        to: InitViewFunc.self
      )
      return function(allocated, selector, frame) as? NSObject
    }

    private func configureWindow() {
      setWindowValue(
        NSNumber(value: Self.windowLevelFloating),
        forKey: "level",
        selector: "setLevel:"
      )
      setWindowValue(
        NSNumber(value: Self.collectionBehavior),
        forKey: "collectionBehavior",
        selector: "setCollectionBehavior:"
      )
      setWindowValue(
        true,
        forKey: "movableByWindowBackground",
        selector: "setMovableByWindowBackground:"
      )
      setWindowValue(false, forKey: "hasShadow", selector: "setHasShadow:")
      setWindowValue(false, forKey: "opaque", selector: "setOpaque:")
      setWindowValue(
        false,
        forKey: "hidesOnDeactivate",
        selector: "setHidesOnDeactivate:"
      )
      setWindowValue(
        true,
        forKey: "excludedFromWindowsMenu",
        selector: "setExcludedFromWindowsMenu:"
      )
      setWindowValue(
        true,
        forKey: "becomesKeyOnlyIfNeeded",
        selector: "setBecomesKeyOnlyIfNeeded:"
      )

      if window.responds(to: NSSelectorFromString("setBackgroundColor:")),
         let colorClass = NSClassFromString("NSColor") as? NSObject.Type,
         let clearColor = colorClass.perform(NSSelectorFromString("clearColor"))?
         .takeUnretainedValue() {
        window.setValue(clearColor, forKey: "backgroundColor")
      }
    }

    private func setWindowValue(
      _ value: Any,
      forKey key: String,
      selector name: String
    ) {
      guard window.responds(to: NSSelectorFromString(name)) else { return }
      window.setValue(value, forKey: key)
    }

    // MARK: Background surface

    private static func makeBackgroundView() -> NSObject? {
      if let glass = makeGlassView() {
        return glass
      }
      return makeEffectView()
    }

    /// Clear Liquid Glass, matching LyricsX Next's desktop lyrics: AppKit owns
    /// refraction, the scrim supplies a light contrast tint, and a fixed dark
    /// appearance keeps white lyrics readable over bright desktops.
    private static func makeGlassView() -> NSObject? {
      guard let glassClass = NSClassFromString("NSGlassEffectView") as? NSObject.Type,
            let allocated = glassClass.perform(NSSelectorFromString("alloc"))?
            .takeUnretainedValue(),
            let view = initWithFrame(allocated, class: glassClass, frame: .zero)
      else { return nil }
      if view.responds(to: NSSelectorFromString("setStyle:")) {
        view.setValue(NSNumber(value: 1), forKey: "style") // clear
      }
      fixedGlassAppearance(view)
      if view.responds(to: NSSelectorFromString("setCornerRadius:")) {
        view.setValue(
          NSNumber(value: DesktopLyricsRenderer.glassCornerRadius),
          forKey: "cornerRadius"
        )
      }
      view.setValue(true, forKey: "wantsLayer")
      return view
    }

    private static func makeEffectView() -> NSObject? {
      guard let effectClass = NSClassFromString("NSVisualEffectView") as? NSObject.Type,
            let allocated = effectClass.perform(NSSelectorFromString("alloc"))?
            .takeUnretainedValue(),
            let view = initWithFrame(allocated, class: effectClass, frame: .zero)
      else { return nil }
      if view.responds(to: NSSelectorFromString("setMaterial:")) {
        view.setValue(NSNumber(value: 6), forKey: "material") // popover
      }
      if view.responds(to: NSSelectorFromString("setBlendingMode:")) {
        view.setValue(NSNumber(value: 0), forKey: "blendingMode") // behindWindow
      }
      if view.responds(to: NSSelectorFromString("setState:")) {
        view.setValue(NSNumber(value: 1), forKey: "state") // active
      }
      view.setValue(true, forKey: "wantsLayer")
      if let layer = view.value(forKey: "layer") as? CALayer {
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
      }
      return view
    }

    // MARK: Frame

    private var currentFrame: CGRect {
      (window.value(forKey: "frame") as? NSValue)?.cgRectValue ?? .zero
    }

    private func applyFrame(_ frame: CGRect) {
      Self.setFrame(frame, on: window)
      layoutLayers()
    }

    private static func setFrame(_ frame: CGRect, on window: NSObject) {
      let selector = NSSelectorFromString("setFrame:display:")
      guard let windowClass = object_getClass(window),
            let method = class_getInstanceMethod(windowClass, selector)
      else { return }
      typealias SetFrameFunc = @convention(c)
        (AnyObject, Selector, CGRect, Bool) -> ()
      let function = unsafeBitCast(
        method_getImplementation(method),
        to: SetFrameFunc.self
      )
      function(window, selector, frame, true)
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
          controlWindow?.perform(NSSelectorFromString("orderFrontRegardless"))
        }
      }
      positionOffsetPanel()
      let scale = Self.currentScreenScale(for: window)
      if abs(scale - screenScale) > 0.01 {
        screenScale = scale
        reloadCurrentContent()
      }
    }

    @objc
    private func windowDidChangeScreen(_ notification: Notification) {
      let scale = Self.currentScreenScale(for: window)
      guard abs(scale - screenScale) > 0.01 else { return }
      screenScale = scale
      reloadCurrentContent()
    }

    private func reloadCurrentContent() {
      guard let content = lastContent else { return }
      reload(content: content)
    }

    private static func currentScreenScale(for window: NSObject) -> CGFloat {
      let screen = (window.value(forKey: "screen") as? NSObject)
        ?? (NSClassFromString("NSScreen") as? NSObject.Type)?
        .perform(NSSelectorFromString("mainScreen"))?
        .takeUnretainedValue() as? NSObject
      guard let number = screen?.value(forKey: "backingScaleFactor") as? NSNumber
      else { return 2 }
      return CGFloat(number.doubleValue)
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
      guard let screenClass = NSClassFromString("NSScreen") as? NSObject.Type,
            let screens = screenClass.perform(NSSelectorFromString("screens"))?
            .takeUnretainedValue() as? [NSObject]
      else { return true }
      return screens.contains { screen in
        guard let value = screen.value(forKey: "visibleFrame") as? NSValue else {
          return false
        }
        return value.cgRectValue.intersects(frame.insetBy(dx: 60, dy: 30))
      }
    }

    private static func mainScreenVisibleFrame() -> CGRect? {
      guard let screenClass = NSClassFromString("NSScreen") as? NSObject.Type,
            let screen = screenClass.perform(NSSelectorFromString("mainScreen"))?
            .takeUnretainedValue() as? NSObject,
            let value = screen.value(forKey: "visibleFrame") as? NSValue
      else { return nil }
      return value.cgRectValue
    }
  }

#endif
