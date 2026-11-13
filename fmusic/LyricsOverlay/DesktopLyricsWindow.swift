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

  import QuartzCore
  import UIKit
  import fmusicKit

  // MARK: - DesktopLyricsContent

  struct DesktopLyricsContent {
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

  // MARK: - Rendered lines

  /// A line whose glyphs are already rasterized. Mask rectangles are in the glyph
  /// layer's coordinate space (origin bottom-left) so they can be applied directly.
  struct DesktopLyricsLineRender {
    let text: String
    let layout: LyricsTextLayout
    let size: CGSize
    let dimImage: CGImage
    let brightImage: CGImage
    let syllables: [LyricsSyllableTiming]
    let maskRects: [[CGRect]]
  }

  struct DesktopLyricsNextRender {
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

  // MARK: - DesktopLyricsRenderer

  @MainActor
  enum DesktopLyricsRenderer {
    static let panelWidth: CGFloat = 760
    static let horizontalInset: CGFloat = 30
    static let topPadding: CGFloat = 12
    static let bottomPadding: CGFloat = 12
    static let lineGap: CGFloat = 4
    static let cornerRadius: CGFloat = 20

    static var contentWidth: CGFloat { panelWidth - horizontalInset * 2 }

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
      max(13, style.pointSize * 0.5)
    }

    static func estimatedPanelHeight(style: DesktopLyricsStyle) -> CGFloat {
      let primary = ceil(style.pointSize * 1.34)
      let next = style.showsNextLine ? lineGap + ceil(nextFontSize(style) * 1.34) : 0
      return topPadding + bottomPadding + primary + next
    }

    // MARK: Line rendering

    static func makeLine(
      text: String,
      syllables: [LyricsSyllableTiming],
      style: DesktopLyricsStyle,
      scale: CGFloat
    ) -> DesktopLyricsLineRender? {
      let displayText = displayText(text)
      let width = contentWidth
      guard width > 0 else { return nil }

      let font = UIFont.systemFont(ofSize: style.pointSize, weight: .bold)
      let paragraph = primaryParagraph(style: style)

      let dimText = NSAttributedString(
        string: displayText,
        attributes: primaryAttributes(
          font: font,
          color: UIColor.white.withAlphaComponent(0.46),
          paragraph: paragraph,
          shadowAlpha: 0.62,
          shadowBlur: 8
        )
      )
      let brightText = NSAttributedString(
        string: displayText,
        attributes: primaryAttributes(
          font: font,
          color: UIColor(white: 0.98, alpha: 1),
          paragraph: paragraph,
          shadowAlpha: 0.52,
          shadowBlur: 6
        )
      )

      let brightLayout = LyricsTextLayout(
        text: brightText,
        width: width,
        maximumNumberOfLines: 2,
        lineBreakMode: .byWordWrapping
      )
      let dimLayout = LyricsTextLayout(
        text: dimText,
        width: width,
        maximumNumberOfLines: 2,
        lineBreakMode: .byWordWrapping
      )

      let height = max(ceil(brightLayout.height), ceil(font.lineHeight))
      let size = CGSize(width: width, height: height)
      guard let dimImage = rasterize(dimLayout, size: size, scale: scale),
            let brightImage = rasterize(brightLayout, size: size, scale: scale)
      else { return nil }

      return DesktopLyricsLineRender(
        text: displayText,
        layout: brightLayout,
        size: size,
        dimImage: dimImage,
        brightImage: brightImage,
        syllables: syllables,
        maskRects: maskRects(
          for: brightLayout,
          syllables: syllables,
          height: height
        )
      )
    }

    static func makeNextLine(
      text: String,
      style: DesktopLyricsStyle,
      scale: CGFloat
    ) -> DesktopLyricsNextRender? {
      guard let text = normalizedNextText(text) else { return nil }
      let width = contentWidth
      guard width > 0 else { return nil }

      let font = UIFont.systemFont(ofSize: nextFontSize(style), weight: .medium)
      let paragraph = NSMutableParagraphStyle()
      paragraph.alignment = textAlignment(style.alignment)
      paragraph.lineBreakMode = .byTruncatingTail

      let shadow = NSShadow()
      shadow.shadowColor = UIColor.black.withAlphaComponent(0.55)
      shadow.shadowBlurRadius = 4
      shadow.shadowOffset = CGSize(width: 0, height: 1)

      let attributed = NSAttributedString(
        string: text,
        attributes: [
          .font: font,
          .foregroundColor: UIColor.white.withAlphaComponent(0.62),
          .paragraphStyle: paragraph,
          .kern: -0.2,
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

    // MARK: Snapshots

    /// Composes the line as it looks right now, so a departing line keeps its
    /// highlight instead of flashing back to the unsung color.
    static func snapshot(
      line: DesktopLyricsLineRender,
      progress: [CGFloat],
      scale: CGFloat
    )
      -> CGImage? {
      guard !line.syllables.isEmpty else { return line.brightImage }
      let format = UIGraphicsImageRendererFormat()
      format.scale = max(scale, 1)
      format.opaque = false
      let renderer = UIGraphicsImageRenderer(size: line.size, format: format)
      return renderer.image { context in
        let bounds = CGRect(origin: .zero, size: line.size)
        UIImage(cgImage: line.dimImage).draw(in: bounds)
        let path = CGMutablePath()
        var hasSung = false
        for (index, syllable) in line.syllables.enumerated() {
          let value = index < progress.count ? progress[index] : 0
          guard value > 0.001 else { continue }
          for rect in line.layout.rects(for: syllable.range) {
            var sungRect = rect
            if value < 0.999 {
              sungRect.size.width *= value
            }
            path.addRect(sungRect)
            hasSung = true
          }
        }
        guard hasSung else { return }
        context.cgContext.saveGState()
        context.cgContext.addPath(path)
        context.cgContext.clip()
        UIImage(cgImage: line.brightImage).draw(in: bounds)
        context.cgContext.restoreGState()
      }.cgImage
    }

    // MARK: Helpers

    private static func primaryParagraph(style: DesktopLyricsStyle) -> NSParagraphStyle {
      let paragraph = NSMutableParagraphStyle()
      paragraph.alignment = textAlignment(style.alignment)
      paragraph.lineBreakMode = .byWordWrapping
      paragraph.lineSpacing = max(2, style.pointSize * 0.12)
      return paragraph
    }

    private static func primaryAttributes(
      font: UIFont,
      color: UIColor,
      paragraph: NSParagraphStyle,
      shadowAlpha: CGFloat,
      shadowBlur: CGFloat
    ) -> [NSAttributedString.Key: Any] {
      let shadow = NSShadow()
      shadow.shadowColor = UIColor.black.withAlphaComponent(shadowAlpha)
      shadow.shadowBlurRadius = shadowBlur
      shadow.shadowOffset = CGSize(width: 0, height: 1)
      return [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph,
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
      scale: CGFloat
    )
      -> CGImage? {
      guard size.width > 0, size.height > 0 else { return nil }
      let format = UIGraphicsImageRendererFormat()
      format.scale = max(scale, 1)
      format.opaque = false
      let renderer = UIGraphicsImageRenderer(size: size, format: format)
      return renderer.image { _ in layout.draw() }.cgImage
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
  }

  // MARK: - DesktopLyricsPanelController

  @MainActor
  final class DesktopLyricsPanelController: NSObject {
    private static let frameDefaultsKey = "fmusic.desktopLyrics.frame"
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
    private let borderLayer = CALayer()
    private let contentLayer = CALayer()
    private let previousLayer = CALayer()
    private let primaryContainer = CALayer()
    private let glowLayer = CAGradientLayer()
    private let baseLayer = CALayer()
    private let sungLayer = CALayer()
    private let syllableMask = LyricsSyllableMaskLayer()
    private let nextLayer = CALayer()

    private var style = DesktopLyricsStyle(
      pointSize: DesktopLyricsFontSize.medium.pointSize,
      backgroundOpacity: 0.74,
      alignment: .defaultValue,
      showsNextLine: true
    )
    private var screenScale: CGFloat = 2
    private var lastContent: DesktopLyricsContent?
    private var primaryLine: DesktopLyricsLineRender?
    private var nextLine: DesktopLyricsNextRender?
    private var lastProgress: [CGFloat] = []
    private var departureHeight: CGFloat = 0
    private var departureToken = 0

    private init(window: NSObject, contentView: NSObject, rootLayer: CALayer) {
      self.window = window
      self.contentView = contentView
      self.rootLayer = rootLayer
      super.init()

      configureWindow()
      screenScale = Self.currentScreenScale(for: window)
      installBackground()
      installLayers()
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
      window.perform(NSSelectorFromString("orderFrontRegardless"))
    }

    func hide() {
      _ = window.perform(NSSelectorFromString("orderOut:"), with: nil)
    }

    func setAlwaysOnTop(_ isAlwaysOnTop: Bool) {
      setWindowValue(
        NSNumber(value: isAlwaysOnTop ? Self.windowLevelFloating : 0),
        forKey: "level",
        selector: "setLevel:"
      )
    }

    func setLocked(_ locked: Bool) {
      setWindowValue(
        locked,
        forKey: "ignoresMouseEvents",
        selector: "setIgnoresMouseEvents:"
      )
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
      lastContent = content
      let text = DesktopLyricsRenderer.displayText(content.currentText)
      let nextText = style.showsNextLine
        ? DesktopLyricsRenderer.normalizedNextText(content.nextText)
        : nil
      let previousNext = nextLine?.text
      var needsLayout = false

      if text != primaryLine?.text {
        let animated = isVisible && primaryLine != nil
        let promoted = animated && previousNext == text
        if animated, let old = primaryLine {
          beginDeparture(of: old, progress: lastProgress)
        }
        primaryLine = DesktopLyricsRenderer.makeLine(
          text: text,
          syllables: content.syllables,
          style: style,
          scale: screenScale
        )
        installPrimaryImages()
        lastProgress = []
        needsLayout = true
        if animated {
          animateArrival(promoted: promoted)
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
    }

    // MARK: Content installation

    private func reload(content: DesktopLyricsContent) {
      primaryLine = DesktopLyricsRenderer.makeLine(
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
      previousLayer.isHidden = true
      previousLayer.contents = nil
      departureHeight = 0
      installPrimaryImages()
      installNextImage(animated: false)
      lastProgress = []
      resizePanel()
      layoutLayers()
      applyProgress(content.syllableProgress, force: true)
    }

    private func installPrimaryImages() {
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      defer { CATransaction.commit() }

      primaryContainer.removeAnimation(forKey: "arrival")
      primaryContainer.removeAnimation(forKey: "arrivalFade")
      primaryContainer.transform = CATransform3DIdentity
      primaryContainer.opacity = 1
      glowLayer.isHidden = true

      guard let line = primaryLine else {
        primaryContainer.isHidden = true
        syllableMask.reset()
        return
      }
      primaryContainer.isHidden = false
      baseLayer.contents = line.syllables.isEmpty ? line.brightImage : line.dimImage
      sungLayer.contents = line.brightImage
      sungLayer.isHidden = line.syllables.isEmpty
      syllableMask.update(rects: line.maskRects)
      syllableMask.reset()
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

    // MARK: Clock

    private func applyProgress(_ progress: [CGFloat], force: Bool = false) {
      guard let line = primaryLine else { return }
      if !force, progress == lastProgress { return }
      lastProgress = progress

      guard !line.syllables.isEmpty else {
        syllableMask.reset()
        sungLayer.isHidden = true
        return
      }
      sungLayer.isHidden = false
      syllableMask.apply(progress: progress)
      updateEmphasis(progress: progress, syllables: line.syllables)
    }

    private func updateEmphasis(
      progress: [CGFloat],
      syllables: [LyricsSyllableTiming]
    ) {
      var bestValue: CGFloat = 0
      var bestIndex: Int?
      for (index, syllable) in syllables.enumerated() where index < progress.count {
        let value = DesktopLyricsEmphasis.value(
          progress: progress[index],
          duration: syllable.end - syllable.start
        )
        if value > bestValue {
          bestValue = value
          bestIndex = index
        }
      }

      CATransaction.begin()
      CATransaction.setDisableActions(true)
      if let index = bestIndex,
         bestValue > 0.001,
         let line = primaryLine,
         index < line.maskRects.count,
         let union = union(of: line.maskRects[index]) {
        let size = CGSize(
          width: max(120, union.width + 110),
          height: max(60, union.height + 80)
        )
        glowLayer.frame = CGRect(
          x: union.midX - size.width / 2,
          y: union.midY - size.height / 2,
          width: size.width,
          height: size.height
        )
        glowLayer.isHidden = false
        glowLayer.opacity = Float(0.55 * bestValue)
        let scale = 1 + 0.02 * bestValue
        primaryContainer.transform = CATransform3DConcat(
          CATransform3DMakeScale(scale, scale, 1),
          CATransform3DMakeTranslation(0, 1.2 * bestValue, 0)
        )
      } else {
        glowLayer.isHidden = true
        primaryContainer.transform = CATransform3DIdentity
      }
      CATransaction.commit()
    }

    private func union(of rects: [CGRect]) -> CGRect? {
      var result: CGRect?
      for rect in rects {
        result = result.map { $0.union(rect) } ?? rect
      }
      return result
    }

    // MARK: Line motion

    private func beginDeparture(of line: DesktopLyricsLineRender, progress: [CGFloat]) {
      guard let snapshot = DesktopLyricsRenderer.snapshot(
        line: line,
        progress: progress,
        scale: screenScale
      )
      else { return }
      departureToken += 1
      let token = departureToken
      departureHeight = line.size.height

      CATransaction.begin()
      CATransaction.setDisableActions(true)
      previousLayer.contents = snapshot
      previousLayer.frame = primaryContainer.frame
      previousLayer.opacity = 1
      previousLayer.transform = CATransform3DIdentity
      previousLayer.isHidden = false
      CATransaction.commit()

      let fade = CABasicAnimation(keyPath: "opacity")
      fade.fromValue = 1
      fade.toValue = 0
      fade.duration = 0.20
      fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
      previousLayer.add(fade, forKey: "departure")

      let rise = CABasicAnimation(keyPath: "transform.translation.y")
      rise.fromValue = 0
      rise.toValue = 9
      rise.duration = 0.24
      rise.timingFunction = CAMediaTimingFunction(
        controlPoints: 0.3, 0, 0.6, 1
      )
      previousLayer.add(rise, forKey: "departureRise")

      CATransaction.begin()
      CATransaction.setDisableActions(true)
      previousLayer.opacity = 0
      previousLayer.transform = CATransform3DMakeTranslation(0, 9, 0)
      CATransaction.commit()

      Task { @MainActor [weak self] in
        try? await Task.sleep(nanoseconds: 260_000_000)
        guard let self, self.departureToken == token else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.previousLayer.isHidden = true
        self.previousLayer.contents = nil
        CATransaction.commit()
      }
    }

    private func animateArrival(promoted: Bool) {
      let offset: CGFloat = promoted ? -16 : -10
      let initialScale: CGFloat = promoted ? 0.96 : 0.985
      let from = CATransform3DConcat(
        CATransform3DMakeScale(initialScale, initialScale, 1),
        CATransform3DMakeTranslation(0, offset, 0)
      )

      let move = CABasicAnimation(keyPath: "transform")
      move.fromValue = NSValue(caTransform3D: from)
      move.toValue = NSValue(caTransform3D: CATransform3DIdentity)
      move.duration = promoted ? 0.42 : 0.34
      move.timingFunction = CAMediaTimingFunction(
        controlPoints: 0.22, 0, 0.18, 1
      )

      let fade = CABasicAnimation(keyPath: "opacity")
      fade.fromValue = 0
      fade.toValue = 1
      fade.duration = promoted ? 0.36 : 0.30
      fade.timingFunction = CAMediaTimingFunction(
        controlPoints: 0.22, 0, 0.2, 1
      )

      primaryContainer.removeAnimation(forKey: "arrival")
      primaryContainer.removeAnimation(forKey: "arrivalFade")
      primaryContainer.add(move, forKey: "arrival")
      primaryContainer.add(fade, forKey: "arrivalFade")
    }

    // MARK: Chrome

    private func updateChrome() {
      let opacity = min(1, max(0, style.backgroundOpacity))
      let hasChrome = opacity > 0.001
      // LyricsX tints only the upper edge of the glass and leaves the lower edge
      // refractive, so the surface reads as one material instead of a dim card.
      let shade = 0.62 * opacity
      let clear = UIColor.clear.cgColor

      CATransaction.begin()
      CATransaction.setDisableActions(true)
      scrimLayer.isHidden = !hasChrome
      borderLayer.isHidden = !hasChrome
      scrimLayer.colors = [
        UIColor.black.withAlphaComponent(shade).cgColor,
        UIColor.black.withAlphaComponent(shade * 0.66).cgColor,
        UIColor.black.withAlphaComponent(shade * 0.28).cgColor,
        clear,
      ]
      borderLayer.borderColor = UIColor.white.withAlphaComponent(
        0.10 + 0.06 * opacity
      ).cgColor
      CATransaction.commit()

      if let backgroundView,
         backgroundView.responds(to: NSSelectorFromString("setHidden:")) {
        backgroundView.setValue(!hasChrome, forKey: "hidden")
      }
    }

    // MARK: Layout

    private func desiredHeight() -> CGFloat {
      let primary = primaryLine?.size.height
        ?? ceil(style.pointSize * 1.34)
      let next = nextLine.map { DesktopLyricsRenderer.lineGap + $0.height } ?? 0
      return DesktopLyricsRenderer.topPadding
        + DesktopLyricsRenderer.bottomPadding
        + primary
        + next
    }

    /// The top edge stays fixed while the height follows the current and preview
    /// lines, so wrapped lines grow downwards like Apple Music's overlay.
    private func resizePanel() {
      let height = max(desiredHeight(), 44)
      let frame = currentFrame
      guard abs(frame.height - height) > 0.5 else { return }
      var newFrame = frame
      newFrame.origin.y += frame.height - height
      newFrame.size.height = height
      applyFrame(newFrame)
      saveFrame()
    }

    private func layoutLayers() {
      let bounds = CGRect(origin: .zero, size: currentFrame.size)
      let inset = DesktopLyricsRenderer.horizontalInset
      let width = DesktopLyricsRenderer.contentWidth
      let top = bounds.height - DesktopLyricsRenderer.topPadding

      CATransaction.begin()
      CATransaction.setDisableActions(true)
      scrimLayer.frame = bounds
      borderLayer.frame = bounds
      contentLayer.frame = bounds
      if let backgroundView {
        backgroundView.setValue(NSValue(cgRect: bounds), forKey: "frame")
      }

      for layer in [baseLayer, sungLayer, nextLayer, previousLayer] {
        layer.contentsScale = screenScale
      }

      if let line = primaryLine {
        primaryContainer.frame = CGRect(
          x: inset,
          y: top - line.size.height,
          width: width,
          height: line.size.height
        )
        baseLayer.frame = primaryContainer.bounds
        sungLayer.frame = primaryContainer.bounds
        syllableMask.setFrameWithoutAnimation(sungLayer.bounds)
      }

      if let next = nextLine {
        let primaryTop = primaryLine.map { top - $0.size.height } ?? top
        nextLayer.frame = CGRect(
          x: inset,
          y: primaryTop - DesktopLyricsRenderer.lineGap - next.height,
          width: width,
          height: next.height
        )
      }

      if !previousLayer.isHidden, departureHeight > 0 {
        previousLayer.frame = CGRect(
          x: inset,
          y: top - departureHeight,
          width: width,
          height: departureHeight
        )
      }
      CATransaction.commit()
    }

    // MARK: Window content

    private func installBackground() {
      guard let view = Self.makeBackgroundView(
        radius: DesktopLyricsRenderer.cornerRadius
      )
      else { return }
      backgroundView = view
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
      scrimLayer.cornerRadius = DesktopLyricsRenderer.cornerRadius
      scrimLayer.cornerCurve = .continuous
      scrimLayer.masksToBounds = true
      scrimLayer.startPoint = CGPoint(x: 0.5, y: 1)
      scrimLayer.endPoint = CGPoint(x: 0.5, y: 0)
      scrimLayer.locations = [0, 0.34, 0.67, 1]
      scrimLayer.zPosition = 1

      borderLayer.cornerRadius = DesktopLyricsRenderer.cornerRadius
      borderLayer.cornerCurve = .continuous
      borderLayer.borderWidth = 1
      borderLayer.backgroundColor = UIColor.clear.cgColor
      borderLayer.zPosition = 2

      contentLayer.masksToBounds = false
      contentLayer.zPosition = 3
      previousLayer.masksToBounds = false
      primaryContainer.masksToBounds = false
      baseLayer.masksToBounds = false
      sungLayer.masksToBounds = false
      nextLayer.masksToBounds = false

      for layer in [baseLayer, sungLayer, nextLayer, previousLayer] {
        layer.contentsGravity = .resize
        layer.magnificationFilter = .linear
        layer.isOpaque = false
      }

      glowLayer.type = .radial
      glowLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
      glowLayer.endPoint = CGPoint(x: 1, y: 1)
      glowLayer.colors = [
        UIColor.white.withAlphaComponent(0.30).cgColor,
        UIColor.white.withAlphaComponent(0).cgColor,
      ]
      glowLayer.locations = [0, 1]
      glowLayer.isHidden = true
      glowLayer.masksToBounds = false

      sungLayer.mask = syllableMask

      primaryContainer.addSublayer(glowLayer)
      primaryContainer.addSublayer(baseLayer)
      primaryContainer.addSublayer(sungLayer)
      contentLayer.addSublayer(nextLayer)
      contentLayer.addSublayer(primaryContainer)
      contentLayer.addSublayer(previousLayer)
      rootLayer.addSublayer(scrimLayer)
      rootLayer.addSublayer(borderLayer)
      rootLayer.addSublayer(contentLayer)

      CATransaction.begin()
      CATransaction.setDisableActions(true)
      previousLayer.isHidden = true
      nextLayer.isHidden = true
      primaryContainer.isHidden = true
      CATransaction.commit()
    }

    // MARK: Window setup

    private static func makePanel()
      -> (window: NSObject, contentView: NSObject, layer: CALayer)? {
      guard let panelClass = NSClassFromString("NSPanel") as? NSObject.Type,
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
      Self.forceDarkAppearance(on: window)
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

    private static func makeBackgroundView(radius: CGFloat) -> NSObject? {
      if let glass = makeGlassView(radius: radius) {
        return glass
      }
      return makeEffectView(radius: radius)
    }

    /// Liquid Glass when the OS provides it (macOS 26+); the regular style keeps
    /// the desktop visible through the panel like LyricsX's overlay.
    private static func makeGlassView(radius: CGFloat) -> NSObject? {
      guard let glassClass = NSClassFromString("NSGlassEffectView") as? NSObject.Type,
            let allocated = glassClass.perform(NSSelectorFromString("alloc"))?
            .takeUnretainedValue(),
            let view = initWithFrame(allocated, class: glassClass, frame: .zero)
      else { return nil }
      forceDarkAppearance(on: view)
      if view.responds(to: NSSelectorFromString("setStyle:")) {
        // Clear keeps native refraction without filling the panel with the
        // regular variant's light frosting; the scrim supplies the tint.
        view.setValue(NSNumber(value: 1), forKey: "style")
      }
      if view.responds(to: NSSelectorFromString("setCornerRadius:")) {
        view.setValue(NSNumber(value: radius), forKey: "cornerRadius")
      }
      view.setValue(true, forKey: "wantsLayer")
      return view
    }

    private static func makeEffectView(radius: CGFloat) -> NSObject? {
      guard let effectClass = NSClassFromString("NSVisualEffectView") as? NSObject.Type,
            let allocated = effectClass.perform(NSSelectorFromString("alloc"))?
            .takeUnretainedValue(),
            let view = initWithFrame(allocated, class: effectClass, frame: .zero)
      else { return nil }
      if view.responds(to: NSSelectorFromString("setMaterial:")) {
        view.setValue(NSNumber(value: 13), forKey: "material") // hudWindow
      }
      if view.responds(to: NSSelectorFromString("setBlendingMode:")) {
        view.setValue(NSNumber(value: 0), forKey: "blendingMode") // behindWindow
      }
      if view.responds(to: NSSelectorFromString("setState:")) {
        view.setValue(NSNumber(value: 1), forKey: "state") // active
      }
      view.setValue(true, forKey: "wantsLayer")
      if let layer = view.value(forKey: "layer") as? CALayer {
        layer.cornerRadius = radius
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
      }
      forceDarkAppearance(on: view)
      return view
    }

    /// White lyrics need the dark variant of the material even when the rest of
    /// the system is in light mode.
    private static func forceDarkAppearance(on view: NSObject) {
      guard view.responds(to: NSSelectorFromString("setAppearance:")),
            let appearanceClass = NSClassFromString("NSAppearance") as? NSObject.Type,
            let dark = appearanceClass.perform(
              NSSelectorFromString("appearanceNamed:"),
              with: "NSAppearanceNameDarkAqua"
            )?.takeUnretainedValue()
      else { return }
      view.setValue(dark, forKey: "appearance")
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
        (AnyObject, Selector, CGRect, Bool) -> Void
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
        let height = (44...400).contains(storedHeight)
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
      saveFrame()
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
