//
//  VolumeSlider.swift
//  fmusic
//
//  Apple Music's volume control is a thin track with a small round knob. UISlider under
//  the Mac idiom draws an oversized knob on a thick capsule, so the track is drawn here.
//

import UIKit

final class VolumeSlider: UIControl {
  private enum Metrics {
    static let trackHeight: CGFloat = 6
    // macOS 26 sliders use a horizontally stretched capsule knob, not a circle.
    static let knobSize = CGSize(width: 22, height: 16)
    static let activeKnobSize = CGSize(width: 24, height: 17)
  }

  private var storedValue: Float = 1

  /// Tint of track, fill and knob. The player sits on artwork, so its controls use white.
  var contentColor: UIColor = .label {
    didSet { setNeedsDisplay() }
  }

  var value: Float {
    get { storedValue }
    set {
      let clamped = min(max(newValue, 0), 1)
      guard clamped != storedValue else { return }
      storedValue = clamped
      setNeedsDisplay()
    }
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    isOpaque = false
    contentMode = .redraw
    isAccessibilityElement = true
    accessibilityTraits = .adjustable
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var intrinsicContentSize: CGSize {
    CGSize(width: 120, height: 24)
  }

  override func draw(_ rect: CGRect) {
    let inset = Metrics.knobSize.width / 2
    let trackRect = CGRect(
      x: inset,
      y: (bounds.height - Metrics.trackHeight) / 2,
      width: max(bounds.width - 2 * inset, 0),
      height: Metrics.trackHeight
    )
    let knobX = trackRect.minX + trackRect.width * CGFloat(storedValue)
    let cornerRadius = Metrics.trackHeight / 2

    contentColor.withAlphaComponent(0.3).setFill()
    UIBezierPath(roundedRect: trackRect, cornerRadius: cornerRadius).fill()

    let filledWidth = knobX - trackRect.minX
    if filledWidth > 0 {
      contentColor.setFill()
      UIBezierPath(
        roundedRect: CGRect(
          x: trackRect.minX,
          y: trackRect.minY,
          width: filledWidth,
          height: Metrics.trackHeight
        ),
        cornerRadius: cornerRadius
      ).fill()
    }

    let knobSize = isTracking ? Metrics.activeKnobSize : Metrics.knobSize
    contentColor.setFill()
    UIBezierPath(
      roundedRect: CGRect(
        x: knobX - knobSize.width / 2,
        y: bounds.midY - knobSize.height / 2,
        width: knobSize.width,
        height: knobSize.height
      ),
      cornerRadius: knobSize.height / 2
    ).fill()
  }

  override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
    updateValue(at: touch.location(in: self))
    return true
  }

  override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
    updateValue(at: touch.location(in: self))
    return true
  }

  override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
    setNeedsDisplay()
  }

  override func cancelTracking(with event: UIEvent?) {
    setNeedsDisplay()
  }

  private func updateValue(at point: CGPoint) {
    let inset = Metrics.knobSize.width / 2
    let usableWidth = max(bounds.width - 2 * inset, 1)
    let newValue = Float(min(max((point.x - inset) / usableWidth, 0), 1))
    guard newValue != storedValue else { return }
    storedValue = newValue
    setNeedsDisplay()
    sendActions(for: .valueChanged)
  }

  // MARK: - Accessibility

  override var accessibilityValue: String? {
    get { "\(Int((storedValue * 100).rounded()))%" }
    set {
      guard let text = newValue,
            let percentage = Float(text.replacingOccurrences(of: "%", with: ""))
      else { return }
      let clamped = min(max(percentage / 100, 0), 1)
      guard clamped != storedValue else { return }
      storedValue = clamped
      setNeedsDisplay()
      sendActions(for: .valueChanged)
    }
  }

  override func accessibilityIncrement() {
    adjustValue(by: 0.05)
  }

  override func accessibilityDecrement() {
    adjustValue(by: -0.05)
  }

  private func adjustValue(by delta: Float) {
    let clamped = min(max(storedValue + delta, 0), 1)
    guard clamped != storedValue else { return }
    storedValue = clamped
    setNeedsDisplay()
    sendActions(for: .valueChanged)
  }
}
