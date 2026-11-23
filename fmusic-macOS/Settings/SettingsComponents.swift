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
    effectiveAppearance.performAsCurrentDrawingAppearance {
      cgColor = backgroundColor.cgColor
    }
    layer?.backgroundColor = cgColor
    layer?.cornerRadius = cornerRadius
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
  private let subtitleLabel = NSTextField(labelWithString: "")
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
    subtitleLabel.lineBreakMode = .byTruncatingTail
    subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    subtitleLabel.isHidden = subtitle == nil

    labelStack.addArrangedSubview(titleLabel)
    labelStack.addArrangedSubview(subtitleLabel)
    labelStack.orientation = .vertical
    labelStack.alignment = .leading
    labelStack.spacing = 2
    labelStack.translatesAutoresizingMaskIntoConstraints = false

    control.translatesAutoresizingMaskIntoConstraints = false
    addSubview(labelStack)
    addSubview(control)

    let minimumHeight = heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
    minimumHeight.priority = .required

    let trailing = control.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16)
    let centerY = control.centerYAnchor.constraint(equalTo: centerYAnchor)
    let top = control.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 8)
    let bottom = control.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8)
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
      labelStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 8),
      labelStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8),

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
    wantsLayer = true
    widthAnchor.constraint(equalToConstant: 24).isActive = true
    heightAnchor.constraint(equalToConstant: 24).isActive = true
  }

  required init?(coder: NSCoder) {
    nil
  }

  func setSelected(_ selected: Bool) {
    isSelected = selected
    if selected {
      image = NSImage(
        systemSymbolName: "checkmark",
        accessibilityDescription: L10n.tr("Selected")
      )?.withSymbolConfiguration(
        NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
      )
      contentTintColor = preference.contrastColor
    } else {
      image = nil
    }
  }

  override var wantsUpdateLayer: Bool { true }

  override func updateLayer() {
    var cgColor = preference.asColor.cgColor
    effectiveAppearance.performAsCurrentDrawingAppearance {
      cgColor = preference.asColor.cgColor
    }
    layer?.backgroundColor = cgColor
    layer?.cornerRadius = 12
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }
}
