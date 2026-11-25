//
//  SettingsComponents.swift
//  fmusic-macOS
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

// MARK: - SettingsFlippedView

/// Flipped container so the form is laid out from the top of the scroll document.
final class SettingsFlippedView: NSView {
  override var isFlipped: Bool { true }
}

// MARK: - SettingsBackgroundView

/// Layer backed view that resolves a dynamic `NSColor` against its current appearance.
///
/// `CALayer.backgroundColor` does not follow `NSAppearance` changes on its own, so the
/// colour is pushed into the layer from `updateLayer` whenever the appearance changes.
@MainActor
class SettingsBackgroundView: NSView {
  var backgroundColor: NSColor = .windowBackgroundColor {
    didSet { needsDisplay = true }
  }

  var cornerRadius: CGFloat = 0 {
    didSet { needsDisplay = true }
  }

  var borderColor: NSColor? {
    didSet { needsDisplay = true }
  }

  var borderWidth: CGFloat = 0 {
    didSet { needsDisplay = true }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
  }

  required init?(coder: NSCoder) {
    nil
  }

  override var wantsUpdateLayer: Bool { true }

  override func updateLayer() {
    var cgColor = backgroundColor.cgColor
    var resolvedBorder: CGColor?
    effectiveAppearance.performAsCurrentDrawingAppearance {
      cgColor = backgroundColor.cgColor
      resolvedBorder = borderColor?.cgColor
    }
    layer?.backgroundColor = cgColor
    layer?.cornerRadius = cornerRadius
    layer?.borderColor = resolvedBorder
    layer?.borderWidth = resolvedBorder != nil ? borderWidth : 0
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }
}

// MARK: - SettingsSeparatorView

/// One pixel hairline used between the rows of a settings card.
@MainActor
final class SettingsSeparatorView: SettingsBackgroundView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    backgroundColor = .separatorColor
    translatesAutoresizingMaskIntoConstraints = false
    heightAnchor.constraint(equalToConstant: 1).isActive = true
  }

  required init?(coder: NSCoder) {
    nil
  }
}

// MARK: - SettingsRowView

/// One form row: a label (optionally with a secondary subtitle) and a trailing control.
@MainActor
final class SettingsRowView: NSView {
  private let titleLabel = NSTextField(labelWithString: "")
  private let subtitleLabel = NSTextField(wrappingLabelWithString: "")
  private let labelStack = NSStackView()
  let control: NSView
  private var controlTrailing: NSLayoutConstraint?
  private var controlCenterY: NSLayoutConstraint?
  private var controlTop: NSLayoutConstraint?
  private var controlBottom: NSLayoutConstraint?
  private var controlLeading: NSLayoutConstraint?

  init(title: String, subtitle: String? = nil, control: NSView) {
    self.control = control
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    wantsLayer = true

    titleLabel.stringValue = title
    titleLabel.font = MacTheme.bodyFont
    titleLabel.textColor = .labelColor
    titleLabel.lineBreakMode = .byTruncatingTail
    titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    subtitleLabel.stringValue = subtitle ?? ""
    subtitleLabel.font = MacTheme.secondaryFont
    subtitleLabel.textColor = .secondaryLabelColor
    subtitleLabel.lineBreakMode = .byWordWrapping
    subtitleLabel.maximumNumberOfLines = 0
    subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    subtitleLabel.isHidden = (subtitle?.isEmpty ?? true)

    labelStack.addArrangedSubview(titleLabel)
    labelStack.addArrangedSubview(subtitleLabel)
    labelStack.orientation = .vertical
    labelStack.alignment = .leading
    labelStack.spacing = 3
    labelStack.translatesAutoresizingMaskIntoConstraints = false

    control.translatesAutoresizingMaskIntoConstraints = false
    control.setContentHuggingPriority(.required, for: .horizontal)
    control.setContentCompressionResistancePriority(.required, for: .horizontal)
    addSubview(labelStack)
    addSubview(control)

    let minimumHeight = heightAnchor.constraint(greaterThanOrEqualToConstant: 46)
    minimumHeight.priority = .required

    let trailing = control.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16)
    let centerY = control.centerYAnchor.constraint(equalTo: centerYAnchor)
    let top = control.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 10)
    let bottom = control.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10)
    let leading = control.leadingAnchor.constraint(
      greaterThanOrEqualTo: labelStack.trailingAnchor,
      constant: 16
    )
    controlTrailing = trailing
    controlCenterY = centerY
    controlTop = top
    controlBottom = bottom
    controlLeading = leading

    NSLayoutConstraint.activate([
      minimumHeight,

      labelStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      labelStack.centerYAnchor.constraint(equalTo: centerYAnchor),
      labelStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 10),
      labelStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10),

      trailing, centerY, top, bottom, leading,
    ])
  }

  /// Swaps in a freshly built control while keeping this row's position in the form.
  func updateControl(from other: NSView) {
    guard let replacement = (other as? SettingsRowView)?.control else { return }
    NSLayoutConstraint.deactivate([
      controlTrailing, controlCenterY, controlTop, controlBottom, controlLeading
    ].compactMap { $0 })
    control.removeFromSuperview()
    replacement.removeFromSuperview()
    addSubview(replacement)

    let trailing = replacement.trailingAnchor.constraint(
      equalTo: trailingAnchor, constant: -16
    )
    let centerY = replacement.centerYAnchor.constraint(equalTo: centerYAnchor)
    let top = replacement.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 8)
    let bottom = replacement.bottomAnchor.constraint(
      lessThanOrEqualTo: bottomAnchor, constant: -8
    )
    let leading = replacement.leadingAnchor.constraint(
      greaterThanOrEqualTo: labelStack.trailingAnchor,
      constant: 16
    )
    controlTrailing = trailing
    controlCenterY = centerY
    controlTop = top
    controlBottom = bottom
    controlLeading = leading
    NSLayoutConstraint.activate([trailing, centerY, top, bottom, leading])
  }

  required init?(coder: NSCoder) {
    nil
  }
}

// MARK: - Control wrappers

/// `NSSwitch` that reports its state through a closure.
@MainActor
final class SettingsSwitch: NSSwitch {
  private let handler: (Bool) -> Void

  init(isOn: Bool, handler: @escaping (Bool) -> Void) {
    self.handler = handler
    super.init(frame: .zero)
    state = isOn ? .on : .off
    target = self
    action = #selector(toggled)
  }

  required init?(coder: NSCoder) {
    nil
  }

  var isOn: Bool {
    get { state == .on }
    set { state = newValue ? .on : .off }
  }

  @objc
  private func toggled() {
    handler(isOn)
  }
}

/// `NSPopUpButton` that reports the selected index through a closure.
@MainActor
final class SettingsPopUpButton: NSPopUpButton {
  private let handler: (Int) -> Void

  init(titles: [String], selectedIndex: Int, handler: @escaping (Int) -> Void) {
    self.handler = handler
    super.init(frame: .zero, pullsDown: false)
    addItems(withTitles: titles)
    if !titles.isEmpty {
      selectItem(at: min(max(selectedIndex, 0), titles.count - 1))
    }
    font = MacTheme.bodyFont
    target = self
    action = #selector(selectionChanged)
  }

  required init?(coder: NSCoder) {
    nil
  }

  @objc
  private func selectionChanged() {
    handler(indexOfSelectedItem)
  }
}

/// `NSSegmentedControl` that reports the selected segment through a closure.
@MainActor
final class SettingsSegmentedControl: NSSegmentedControl {
  private let handler: (Int) -> Void

  init(labels: [String], selectedIndex: Int, handler: @escaping (Int) -> Void) {
    self.handler = handler
    super.init(frame: .zero)
    segmentCount = labels.count
    for (index, label) in labels.enumerated() {
      setLabel(label, forSegment: index)
    }
    trackingMode = .selectOne
    selectedSegment = selectedIndex
    target = self
    action = #selector(selectionChanged)
  }

  required init?(coder: NSCoder) {
    nil
  }

  @objc
  private func selectionChanged() {
    handler(selectedSegment)
  }
}

/// Rounded push button that reports a click through a closure.
@MainActor
final class SettingsButton: NSButton {
  private let handler: () -> Void

  init(title: String, isEnabled: Bool = true, handler: @escaping () -> Void) {
    self.handler = handler
    super.init(frame: .zero)
    self.title = title
    bezelStyle = .rounded
    self.isEnabled = isEnabled
    target = self
    action = #selector(clicked)
  }

  required init?(coder: NSCoder) {
    nil
  }

  @objc
  private func clicked() {
    handler()
  }
}

// MARK: - SettingsSliderControl

/// A slider plus a monospaced value label, used for volume and desktop lyrics opacity.
@MainActor
final class SettingsSliderControl: NSView {
  private let slider = NSSlider()
  private let valueLabel = NSTextField(labelWithString: "")
  private let formatter: (Double) -> String
  private let handler: (Double) -> Void
  private let step: Double

  init(
    value: Double,
    range: ClosedRange<Double>,
    step: Double = 0,
    sliderWidth: CGFloat = 200,
    valueWidth: CGFloat = 60,
    isContinuous: Bool = true,
    valueFormatter: @escaping (Double) -> String,
    handler: @escaping (Double) -> Void
  ) {
    self.formatter = valueFormatter
    self.handler = handler
    self.step = step
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false

    slider.minValue = range.lowerBound
    slider.maxValue = range.upperBound
    slider.doubleValue = min(max(value, range.lowerBound), range.upperBound)
    slider.isContinuous = isContinuous
    slider.target = self
    slider.action = #selector(valueChanged)
    slider.translatesAutoresizingMaskIntoConstraints = false
    slider.widthAnchor.constraint(equalToConstant: sliderWidth).isActive = true

    valueLabel.font = MacTheme.tabularBodyFont
    valueLabel.textColor = .secondaryLabelColor
    valueLabel.alignment = .right
    valueLabel.stringValue = formatter(slider.doubleValue)
    valueLabel.translatesAutoresizingMaskIntoConstraints = false
    valueLabel.widthAnchor.constraint(equalToConstant: valueWidth).isActive = true

    let stack = NSStackView(views: [slider, valueLabel])
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 10
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: topAnchor),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  required init?(coder: NSCoder) {
    nil
  }

  /// Updates the slider and its value label without triggering the handler (used to reset
  /// a whole row of controls in one go).
  func setValue(_ value: Double) {
    let clamped = min(max(value, slider.minValue), slider.maxValue)
    slider.doubleValue = clamped
    valueLabel.stringValue = formatter(clamped)
  }

  @objc
  private func valueChanged() {
    var value = slider.doubleValue
    if step > 0 {
      value = (value / step).rounded() * step
      slider.doubleValue = value
    }
    valueLabel.stringValue = formatter(value)
    handler(value)
  }
}

// MARK: - SettingsTextField

/// A single-line `NSTextField` that reports its text through a closure.
@MainActor
final class SettingsTextField: NSTextField, NSTextFieldDelegate {
  private let handler: (String) -> Void

  init(
    text: String,
    placeholder: String,
    width: CGFloat = 200,
    handler: @escaping (String) -> Void
  ) {
    self.handler = handler
    super.init(frame: .zero)
    stringValue = text
    placeholderString = placeholder
    font = MacTheme.bodyFont
    lineBreakMode = .byTruncatingTail
    translatesAutoresizingMaskIntoConstraints = false
    widthAnchor.constraint(equalToConstant: width).isActive = true
    delegate = self
    target = self
    action = #selector(commit)
  }

  required init?(coder: NSCoder) {
    nil
  }

  func controlTextDidChange(_ notification: Notification) {
    handler(stringValue)
  }

  @objc
  private func commit() {
    handler(stringValue)
  }
}

// MARK: - SettingsThemeColorControl

/// The six `ThemePreference` colours as selectable swatches (Apple Music theme picker).
@MainActor
final class SettingsThemeColorControl: NSView {
  private let handler: (ThemePreference) -> Void
  private var buttons: [SettingsThemeSwatchButton] = []

  init(selected: ThemePreference, handler: @escaping (ThemePreference) -> Void) {
    self.handler = handler
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false

    let stack = NSStackView()
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: topAnchor),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])

    for preference in ThemePreference.allCases {
      let button = SettingsThemeSwatchButton(preference: preference)
      button.target = self
      button.action = #selector(swatchClicked(_:))
      button.setSelected(preference == selected)
      buttons.append(button)
      stack.addArrangedSubview(button)
    }
  }

  required init?(coder: NSCoder) {
    nil
  }

  var selectedPreference: ThemePreference? {
    buttons.first(where: \.isSelected)?.preference
  }

  func select(_ preference: ThemePreference) {
    for button in buttons {
      button.setSelected(button.preference == preference)
    }
  }

  func setEnabled(_ isEnabled: Bool) {
    for button in buttons {
      button.isEnabled = isEnabled
    }
  }

  @objc
  private func swatchClicked(_ sender: SettingsThemeSwatchButton) {
    select(sender.preference)
    handler(sender.preference)
  }
}

// MARK: - SettingsThemeSwatchButton

/// A single round theme colour swatch with a contrast checkmark when selected.
@MainActor
final class SettingsThemeSwatchButton: NSButton {
  let preference: ThemePreference
  private(set) var isSelected = false

  init(preference: ThemePreference) {
    self.preference = preference
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    title = ""
    isBordered = false
    focusRingType = .none
    setButtonType(.momentaryChange)
    imagePosition = .imageOnly
    imageScaling = .scaleProportionallyDown
    // Draw the swatch ourselves so selecting it never changes NSButton's image
    // geometry or the circle's aspect ratio.
    wantsLayer = false
    widthAnchor.constraint(equalToConstant: 24).isActive = true
    heightAnchor.constraint(equalToConstant: 24).isActive = true
  }

  required init?(coder: NSCoder) {
    nil
  }

  func setSelected(_ selected: Bool) {
    isSelected = selected
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    let diameter = min(bounds.width, bounds.height)
    let circle = NSRect(
      x: bounds.midX - diameter / 2,
      y: bounds.midY - diameter / 2,
      width: diameter,
      height: diameter
    )
    preference.asColor.setFill()
    NSBezierPath(ovalIn: circle).fill()

    guard isSelected,
          let check = NSImage(
            systemSymbolName: "checkmark",
            accessibilityDescription: L10n.tr("Selected")
          )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
          )
    else { return }
    let tinted = NSImage(size: check.size, flipped: false) { rect in
      check.draw(in: rect)
      self.preference.contrastColor.set()
      rect.fill(using: .sourceAtop)
      return true
    }
    let size = tinted.size
    tinted.draw(in: NSRect(
      x: circle.midX - size.width / 2,
      y: circle.midY - size.height / 2,
      width: size.width,
      height: size.height
    ))
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }
}

// MARK: - SettingsAppearancePickerControl

/// Visual macOS-style appearance picker with Auto / Light / Dark preview cards.
@MainActor
final class SettingsAppearancePickerControl: NSView {
  private let handler: (AppearanceMode) -> Void
  private var cards: [SettingsAppearanceCardButton] = []

  init(selected: AppearanceMode, handler: @escaping (AppearanceMode) -> Void) {
    self.handler = handler
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false

    let stack = NSStackView()
    stack.orientation = .horizontal
    stack.alignment = .top
    stack.spacing = 14
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
    ])

    let orderedModes: [AppearanceMode] = [.unspecified, .light, .dark]
    for mode in orderedModes {
      let card = SettingsAppearanceCardButton(mode: mode)
      card.setSelected(mode == selected)
      card.onSelect = { [weak self] chosen in
        self?.select(chosen)
        self?.handler(chosen)
      }
      cards.append(card)
      stack.addArrangedSubview(card)
    }

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(themeColorChanged),
      name: .macThemeColorChanged,
      object: nil
    )
  }

  required init?(coder: NSCoder) {
    nil
  }

  deinit { NotificationCenter.default.removeObserver(self) }

  func select(_ mode: AppearanceMode) {
    for card in cards {
      card.setSelected(card.mode == mode)
    }
  }

  @objc private func themeColorChanged() {
    for card in cards {
      card.refreshAccent()
    }
  }
}

// MARK: - SettingsAppearanceCardButton

@MainActor
private final class SettingsAppearanceCardButton: NSControl {
  let mode: AppearanceMode
  var onSelect: ((AppearanceMode) -> Void)?

  private var isSelected = false
  private var isHovered = false
  private var trackingArea: NSTrackingArea?

  private let previewWidth: CGFloat = 72
  private let previewHeight: CGFloat = 46

  init(mode: AppearanceMode) {
    self.mode = mode
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    wantsLayer = false
    target = self
    action = #selector(clicked)
    setAccessibilityRole(.radioButton)
    setAccessibilityLabel(title)
    NSLayoutConstraint.activate([
      widthAnchor.constraint(equalToConstant: previewWidth + 4),
      heightAnchor.constraint(equalToConstant: previewHeight + 24),
    ])
  }

  required init?(coder: NSCoder) {
    nil
  }

  private var title: String {
    switch mode {
    case .unspecified: return L10n.tr("Automatic")
    case .light: return L10n.tr("Light")
    case .dark: return L10n.tr("Dark")
    }
  }

  func setSelected(_ selected: Bool) {
    isSelected = selected
    setAccessibilityValue(selected ? 1 : 0)
    needsDisplay = true
  }

  func refreshAccent() {
    needsDisplay = true
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea {
      removeTrackingArea(trackingArea)
    }
    let area = NSTrackingArea(
      rect: bounds,
      options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(area)
    trackingArea = area
  }

  override func mouseEntered(with event: NSEvent) {
    isHovered = true
    needsDisplay = true
  }

  override func mouseExited(with event: NSEvent) {
    isHovered = false
    needsDisplay = true
  }

  override func mouseDown(with event: NSEvent) {
    sendAction(action, to: target)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }

  @objc private func clicked() {
    onSelect?(mode)
  }

  override func draw(_ dirtyRect: NSRect) {
    let previewRect = NSRect(
      x: 2,
      y: bounds.height - previewHeight - 2,
      width: previewWidth,
      height: previewHeight
    )
    let cornerRadius: CGFloat = 8
    let clipPath = NSBezierPath(
      roundedRect: previewRect,
      xRadius: cornerRadius,
      yRadius: cornerRadius
    )

    NSGraphicsContext.saveGraphicsState()
    clipPath.addClip()
    switch mode {
    case .light:
      drawScene(in: previewRect, isDark: false)
    case .dark:
      drawScene(in: previewRect, isDark: true)
    case .unspecified:
      let leftHalf = NSRect(
        x: previewRect.minX,
        y: previewRect.minY,
        width: previewRect.width / 2,
        height: previewRect.height
      )
      let rightHalf = NSRect(
        x: previewRect.midX,
        y: previewRect.minY,
        width: previewRect.width / 2,
        height: previewRect.height
      )
      NSGraphicsContext.saveGraphicsState()
      NSBezierPath(rect: leftHalf).addClip()
      drawScene(in: previewRect, isDark: false)
      NSGraphicsContext.restoreGraphicsState()

      NSGraphicsContext.saveGraphicsState()
      NSBezierPath(rect: rightHalf).addClip()
      drawScene(in: previewRect, isDark: true)
      NSGraphicsContext.restoreGraphicsState()
    }
    NSGraphicsContext.restoreGraphicsState()

    // Border / selection ring
    if isSelected {
      let ringRect = previewRect.insetBy(dx: -0.75, dy: -0.75)
      let ringPath = NSBezierPath(
        roundedRect: ringRect,
        xRadius: cornerRadius + 0.75,
        yRadius: cornerRadius + 0.75
      )
      MacTheme.accentColor.setStroke()
      ringPath.lineWidth = 2.5
      ringPath.stroke()
    } else {
      let borderPath = NSBezierPath(
        roundedRect: previewRect.insetBy(dx: 0.5, dy: 0.5),
        xRadius: cornerRadius - 0.5,
        yRadius: cornerRadius - 0.5
      )
      NSColor.labelColor.withAlphaComponent(isHovered ? 0.32 : 0.16).setStroke()
      borderPath.lineWidth = 1
      borderPath.stroke()
    }

    // Label below thumbnail
    let textColor: NSColor = isSelected ? .labelColor : .secondaryLabelColor
    let font = NSFont.systemFont(ofSize: 12, weight: isSelected ? .medium : .regular)
    let attrs: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: textColor,
    ]
    let attributed = NSAttributedString(string: title, attributes: attrs)
    let textSize = attributed.size()
    attributed.draw(at: NSPoint(
      x: ((bounds.width - textSize.width) / 2).rounded(),
      y: 2
    ))
  }

  /// Draws a miniature macOS desktop + floating window scene for light or dark mode.
  private func drawScene(in rect: NSRect, isDark: Bool) {
    // Wallpaper gradient
    let colors: [NSColor] = isDark
      ? [
          NSColor(srgbRed: 0.34, green: 0.25, blue: 0.62, alpha: 1),
          NSColor(srgbRed: 0.11, green: 0.24, blue: 0.52, alpha: 1),
          NSColor(srgbRed: 0.05, green: 0.12, blue: 0.28, alpha: 1),
        ]
      : [
          NSColor(srgbRed: 0.85, green: 0.92, blue: 1.0, alpha: 1),
          NSColor(srgbRed: 0.45, green: 0.68, blue: 0.98, alpha: 1),
          NSColor(srgbRed: 0.26, green: 0.51, blue: 0.94, alpha: 1),
        ]
    let gradient = NSGradient(colors: colors)
    gradient?.draw(in: rect, angle: -35)

    // Subtle top menu bar
    let menuBar = NSRect(x: rect.minX, y: rect.maxY - 7, width: rect.width, height: 7)
    (isDark ? NSColor.black.withAlphaComponent(0.32) : NSColor.white.withAlphaComponent(0.62))
      .setFill()
    menuBar.fill()

    // Tiny Apple-like dot in menu bar
    let dotRect = NSRect(x: rect.minX + 5, y: rect.maxY - 5, width: 3, height: 3)
    (isDark ? NSColor.white.withAlphaComponent(0.75) : NSColor.white).setFill()
    NSBezierPath(ovalIn: dotRect).fill()

    // Upper-left background window / widget card
    let bgCard = NSRect(x: rect.minX + 4, y: rect.maxY - 23, width: 38, height: 14)
    let bgCardPath = NSBezierPath(roundedRect: bgCard, xRadius: 3.5, yRadius: 3.5)
    (isDark
      ? NSColor(srgbRed: 0.12, green: 0.16, blue: 0.28, alpha: 0.85)
      : NSColor.white.withAlphaComponent(0.75)).setFill()
    bgCardPath.fill()

    let pillBar = NSRect(x: bgCard.minX + 4, y: bgCard.midY - 3, width: 26, height: 6)
    NSColor(srgbRed: 0.16, green: 0.49, blue: 0.98, alpha: 1).setFill()
    NSBezierPath(roundedRect: pillBar, xRadius: 2.5, yRadius: 2.5).fill()

    // Foreground window overlapping bottom-right
    let winRect = NSRect(x: rect.minX + 16, y: rect.minY - 4, width: rect.width - 14, height: 24)
    let winPath = NSBezierPath(roundedRect: winRect, xRadius: 5, yRadius: 5)
    (isDark
      ? NSColor(srgbRed: 0.13, green: 0.13, blue: 0.15, alpha: 1)
      : NSColor.white).setFill()
    winPath.fill()

    (isDark
      ? NSColor.white.withAlphaComponent(0.14)
      : NSColor.black.withAlphaComponent(0.08)).setStroke()
    winPath.lineWidth = 0.75
    winPath.stroke()

    // Traffic light dots inside foreground window
    let trafficColors: [NSColor] = [
      NSColor(srgbRed: 1.0, green: 0.37, blue: 0.34, alpha: 1),
      NSColor(srgbRed: 1.0, green: 0.74, blue: 0.18, alpha: 1),
      NSColor(srgbRed: 0.16, green: 0.78, blue: 0.25, alpha: 1),
    ]
    for (idx, color) in trafficColors.enumerated() {
      let tlRect = NSRect(
        x: winRect.minX + 6 + CGFloat(idx) * 8,
        y: winRect.maxY - 12,
        width: 5,
        height: 5
      )
      color.setFill()
      NSBezierPath(ovalIn: tlRect).fill()
    }
  }
}
