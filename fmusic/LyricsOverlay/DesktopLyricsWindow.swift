//
//  DesktopLyricsWindow.swift
//  fmusic
//
//  Floating, always-on-top lyrics overlay for macOS.
//
//  AppKit's window and view classes are not exposed to Mac Catalyst, so the panel is created
//  through the Objective-C runtime (the same approach as MacWindowHelper) and its content is
//  rendered by UIKit into a CGImage hosted by a CALayer.
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

  // MARK: - DesktopLyricsRenderer

  @MainActor
  enum DesktopLyricsRenderer {
    private static let horizontalInset: CGFloat = 28
    private static let topInset: CGFloat = 12
    private static let bottomInset: CGFloat = 10
    private static let gap: CGFloat = 3

    static func panelSize(pointSize: CGFloat) -> CGSize {
      let currentHeight = ceil(pointSize * 1.32)
      let nextHeight = ceil(max(13, pointSize * 0.5) * 1.4)
      return CGSize(
        width: 760,
        height: currentHeight + nextHeight + topInset + bottomInset + gap + 4
      )
    }

    static func render(
      content: DesktopLyricsContent,
      pointSize: CGFloat,
      size: CGSize,
      scale: CGFloat
    )
      -> CGImage? {
      guard size.width > 0, size.height > 0 else { return nil }

      let format = UIGraphicsImageRendererFormat()
      format.scale = max(scale, 1)
      format.opaque = false
      let renderer = UIGraphicsImageRenderer(size: size, format: format)

      return renderer.image { context in
        draw(
          content: content,
          pointSize: pointSize,
          size: size,
          context: context.cgContext
        )
      }.cgImage
    }

    private static func draw(
      content: DesktopLyricsContent,
      pointSize: CGFloat,
      size: CGSize,
      context: CGContext
    ) {
      let bounds = CGRect(origin: .zero, size: size)

      let card = UIBezierPath(
        roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
        cornerRadius: 16
      )
      UIColor(white: 0.04, alpha: 0.74).setFill()
      card.fill()
      UIColor.white.withAlphaComponent(0.12).setStroke()
      card.lineWidth = 1
      card.stroke()

      let contentWidth = max(0, size.width - 2 * horizontalInset)
      guard contentWidth > 0 else { return }

      let paragraph = NSMutableParagraphStyle()
      paragraph.alignment = .center
      paragraph.lineBreakMode = .byTruncatingTail

      let shadow = NSShadow()
      shadow.shadowColor = UIColor.black.withAlphaComponent(0.55)
      shadow.shadowBlurRadius = 5
      shadow.shadowOffset = CGSize(width: 0, height: 1)

      func attributes(color: UIColor) -> [NSAttributedString.Key: Any] {
        [
          .font: UIFont.systemFont(ofSize: pointSize, weight: .bold),
          .foregroundColor: color,
          .paragraphStyle: paragraph,
          .shadow: shadow,
        ]
      }

      let lineText = content.currentText.isEmpty ? "♪" : content.currentText
      let baseLayout = LyricsTextLayout(
        text: NSAttributedString(
          string: lineText,
          attributes: attributes(color: UIColor.white.withAlphaComponent(0.48))
        ),
        width: contentWidth,
        maximumNumberOfLines: 1,
        lineBreakMode: .byTruncatingTail
      )
      let highlightLayout = LyricsTextLayout(
        text: NSAttributedString(
          string: lineText,
          attributes: attributes(color: UIColor(white: 0.98, alpha: 1))
        ),
        width: contentWidth,
        maximumNumberOfLines: 1,
        lineBreakMode: .byTruncatingTail
      )

      let nextFont = UIFont.systemFont(
        ofSize: max(13, pointSize * 0.5),
        weight: .medium
      )
      let nextHeight = content.nextText == nil ? 0 : ceil(nextFont.lineHeight)
      let currentArea = max(
        0,
        size.height - topInset - bottomInset - nextHeight - gap
      )
      let currentOrigin = CGPoint(
        x: horizontalInset,
        y: topInset + max(0, (currentArea - baseLayout.height) / 2)
      )

      context.saveGState()
      context.translateBy(x: currentOrigin.x, y: currentOrigin.y)
      // Without timings (unsynced lyrics or the no-lyrics placeholder) there is nothing to
      // fill, so the line is drawn fully instead of in the dim unsung color.
      (content.syllables.isEmpty ? highlightLayout : baseLayout).draw()
      context.restoreGState()

      drawSungPortion(
        content: content,
        layout: highlightLayout,
        origin: currentOrigin
      )

      if let nextText = content.nextText {
        let nextParagraph = NSMutableParagraphStyle()
        nextParagraph.alignment = .center
        nextParagraph.lineBreakMode = .byTruncatingTail
        let nextAttributes: [NSAttributedString.Key: Any] = [
          .font: nextFont,
          .foregroundColor: UIColor.white.withAlphaComponent(0.42),
          .paragraphStyle: nextParagraph,
        ]
        let nextRect = CGRect(
          x: horizontalInset,
          y: size.height - bottomInset - nextHeight,
          width: contentWidth,
          height: nextHeight
        )
        (nextText as NSString).draw(in: nextRect, withAttributes: nextAttributes)
      }
    }

    private static func drawSungPortion(
      content: DesktopLyricsContent,
      layout: LyricsTextLayout,
      origin: CGPoint
    ) {
      let clipPath = UIBezierPath()
      for (index, syllable) in content.syllables.enumerated() {
        let progress = content.syllableProgress.object(at: index) ?? 0
        guard progress > 0.001 else { continue }
        for rect in layout.rects(for: syllable.range) {
          var sungRect = rect.offsetBy(dx: origin.x, dy: origin.y)
          if progress < 0.999 {
            sungRect.size.width *= progress
          }
          clipPath.append(UIBezierPath(rect: sungRect))
        }
      }
      guard !clipPath.isEmpty else { return }

      UIGraphicsGetCurrentContext()?.saveGState()
      clipPath.addClip()
      UIGraphicsGetCurrentContext()?.translateBy(x: origin.x, y: origin.y)
      layout.draw()
      UIGraphicsGetCurrentContext()?.restoreGState()
    }
  }

  // MARK: - DesktopLyricsPanelController

  @MainActor
  final class DesktopLyricsPanelController: NSObject {
    private static let frameDefaultsKey = "fmusic.desktopLyrics.frame"
    private static let windowLevelFloating = 3
    // canJoinAllSpaces (1) | fullScreenAuxiliary (16) | stationary (64)
    private static let collectionBehavior = 1 | 16 | 64

    private let window: NSObject
    private let contentLayer: CALayer
    private let contentView: NSObject

    private var currentPointSize = DesktopLyricsFontSize.medium.pointSize
    private var currentContent: DesktopLyricsContent?

    private init(window: NSObject, view: NSObject, layer: CALayer) {
      self.window = window
      contentView = view
      contentLayer = layer
      super.init()

      configureWindow()
      restoreFrame()
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(windowDidMove(_:)),
        name: NSNotification.Name("NSWindowDidMoveNotification"),
        object: window
      )
    }

    static func make() -> DesktopLyricsPanelController? {
      guard let created = makeWindow() else { return nil }
      return DesktopLyricsPanelController(
        window: created.window,
        view: created.view,
        layer: created.layer
      )
    }

    deinit {
      NotificationCenter.default.removeObserver(self)
    }

    // MARK: Public

    var isVisible: Bool {
      (window.value(forKey: "visible") as? Bool) ?? false
    }

    func show() {
      window.perform(NSSelectorFromString("orderFrontRegardless"))
    }

    func hide() {
      _ = window.perform(NSSelectorFromString("orderOut:"), with: nil)
    }

    func setPointSize(_ pointSize: CGFloat) {
      guard abs(pointSize - currentPointSize) > 0.5 else { return }
      currentPointSize = pointSize
      let size = DesktopLyricsRenderer.panelSize(pointSize: pointSize)
      var frame = currentFrame
      frame.size = size
      applyFrame(frame)
      renderCurrentContent()
    }

    func setLocked(_ locked: Bool) {
      window.setValue(locked, forKey: "ignoresMouseEvents")
    }

    func update(content: DesktopLyricsContent) {
      currentContent = content
      renderCurrentContent()
    }

    // MARK: Rendering

    private func renderCurrentContent() {
      guard let content = currentContent else { return }
      let size = currentFrame.size
      guard let image = DesktopLyricsRenderer.render(
        content: content,
        pointSize: currentPointSize,
        size: size,
        scale: screenScale
      )
      else { return }
      contentLayer.contents = image
    }

    private var screenScale: CGFloat {
      guard let screenClass = NSClassFromString("NSScreen") as? NSObject.Type,
            let screen = screenClass.perform(NSSelectorFromString("mainScreen"))?
            .takeUnretainedValue() as? NSObject,
            let number = screen.value(forKey: "backingScaleFactor") as? NSNumber
      else { return 2 }
      return CGFloat(number.doubleValue)
    }

    // MARK: Window setup

    private static func makeWindow()
      -> (window: NSObject, view: NSObject, layer: CALayer)? {
      guard let windowClass = NSClassFromString("NSWindow") as? NSObject.Type,
            let viewClass = NSClassFromString("NSView") as? NSObject.Type,
            let allocatedWindow = windowClass.perform(NSSelectorFromString("alloc"))?
            .takeUnretainedValue()
      else { return nil }

      let windowSelector = NSSelectorFromString(
        "initWithContentRect:styleMask:backing:defer:"
      )
      guard let windowMethod = class_getInstanceMethod(
        windowClass,
        windowSelector
      ) else {
        NSLog("[fmusic] desktop lyrics: NSWindow initializer missing")
        return nil
      }
      typealias InitWindowFunc = @convention(c)
        (AnyObject, Selector, CGRect, UInt, UInt, Bool) -> AnyObject?
      let initWindow = unsafeBitCast(
        method_getImplementation(windowMethod),
        to: InitWindowFunc.self
      )
      guard let window = initWindow(
        allocatedWindow,
        windowSelector,
        CGRect(x: 0, y: 0, width: 760, height: 110),
        0, // borderless
        2, // buffered
        false
      ) as? NSObject else {
        NSLog("[fmusic] desktop lyrics: NSWindow init failed")
        return nil
      }

      guard let view = createView(class: viewClass) else {
        NSLog("[fmusic] desktop lyrics: NSView creation failed")
        return nil
      }
      view.setValue(true, forKey: "wantsLayer")
      window.setValue(view, forKey: "contentView")

      guard let layer = view.value(forKey: "layer") as? CALayer else {
        NSLog("[fmusic] desktop lyrics: layer missing")
        return nil
      }
      layer.contentsGravity = .resize
      layer.magnificationFilter = .linear
      layer.isOpaque = false

      return (window, view, layer)
    }

    private static func createView(class viewClass: NSObject.Type) -> NSObject? {
      guard let allocated = viewClass.perform(NSSelectorFromString("alloc"))?
        .takeUnretainedValue()
      else { return nil }
      let selector = NSSelectorFromString("initWithFrame:")
      guard let method = class_getInstanceMethod(viewClass, selector) else { return nil }
      typealias InitViewFunc = @convention(c)
        (AnyObject, Selector, CGRect) -> AnyObject?
      let function = unsafeBitCast(method_getImplementation(method), to: InitViewFunc.self)
      return function(allocated, selector, .zero) as? NSObject
    }

    private func configureWindow() {
      window.setValue(NSNumber(value: Self.windowLevelFloating), forKey: "level")
      window.setValue(
        NSNumber(value: Self.collectionBehavior),
        forKey: "collectionBehavior"
      )
      window.setValue(true, forKey: "movableByWindowBackground")
      window.setValue(false, forKey: "hasShadow")
      window.setValue(false, forKey: "opaque")
      window.setValue(false, forKey: "hidesOnDeactivate")
      window.setValue(true, forKey: "excludedFromWindowsMenu")

      if let colorClass = NSClassFromString("NSColor") as? NSObject.Type,
         let clearColor = colorClass.perform(NSSelectorFromString("clearColor"))?
         .takeUnretainedValue() {
        window.setValue(clearColor, forKey: "backgroundColor")
      }
    }

    // MARK: Frame

    private var currentFrame: CGRect {
      (window.value(forKey: "frame") as? NSValue)?.cgRectValue ?? .zero
    }

    private func applyFrame(_ frame: CGRect) {
      window.setValue(NSValue(cgPoint: frame.origin), forKey: "frameOrigin")
      Self.setContentSize(frame.size, on: window)
      contentLayer.frame = CGRect(origin: .zero, size: frame.size)
    }

    private static func setContentSize(_ size: CGSize, on window: NSObject) {
      let selector = NSSelectorFromString("setContentSize:")
      guard let windowClass = object_getClass(window),
            let method = class_getInstanceMethod(windowClass, selector)
      else { return }
      typealias SetSizeFunc = @convention(c) (AnyObject, Selector, CGSize) -> Void
      let function = unsafeBitCast(method_getImplementation(method), to: SetSizeFunc.self)
      function(window, selector, size)
    }

    private func restoreFrame() {
      let size = DesktopLyricsRenderer.panelSize(pointSize: currentPointSize)
      var frame = CGRect(origin: Self.defaultOrigin(for: size), size: size)
      if let stored = UserDefaults.standard.array(forKey: Self.frameDefaultsKey) as? [Double],
         stored.count == 4 {
        let candidate = CGRect(
          x: stored[0],
          y: stored[1],
          width: size.width,
          height: size.height
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
