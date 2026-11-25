//
//  SettingsPageViewController.swift
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

/// Base class for the settings content pages.
///
/// Each page is an `NSScrollView` with a vertically laid out form: a large page title,
/// grouped cards (label + control rows with hairline separators) and optional footers.
/// Subclasses only describe their rows in `buildForm()`.
@MainActor
class SettingsPageViewController: NSViewController {
  private let scrollView = NSScrollView()
  private let documentView = SettingsFlippedView()
  private var lastAnchor: NSLayoutYAxisAnchor!
  private var wrappingLabels: [(label: NSTextField, horizontalInsets: CGFloat)] = []

  private let horizontalInset: CGFloat = 48
  private let topInset: CGFloat = 16
  private let bottomInset: CGFloat = 32

  private let pageTitleText: String

  init(title: String) {
    pageTitleText = title
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    nil
  }

  // MARK: - Lifecycle

  override func loadView() {
    let root = NSView()

    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.scrollerStyle = .overlay
    scrollView.drawsBackground = false
    scrollView.contentView.drawsBackground = false
    root.addSubview(scrollView)

    documentView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.documentView = documentView
    documentView.translatesAutoresizingMaskIntoConstraints = false

    let clipView = scrollView.contentView
    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: root.topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

      documentView.topAnchor.constraint(equalTo: clipView.topAnchor),
      documentView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
      documentView.widthAnchor.constraint(equalTo: clipView.widthAnchor),
    ])

    lastAnchor = documentView.topAnchor
    self.view = root
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    addPageTitle()
    buildForm()
    finishForm()
  }

  override func viewDidLayout() {
    super.viewDidLayout()
    // Wrapping `NSTextField`s need an explicit preferred width when laid out with
    // Auto Layout, otherwise the form would compute their height from a single line.
    let documentWidth = documentView.bounds.width
    guard documentWidth > 0 else { return }
    for entry in wrappingLabels {
      let width = max(0, documentWidth - entry.horizontalInsets)
      guard abs(entry.label.preferredMaxLayoutWidth - width) > 0.5 else { continue }
      entry.label.preferredMaxLayoutWidth = width
      entry.label.invalidateIntrinsicContentSize()
    }
  }

  /// Subclasses build their form sections here.
  func buildForm() {}

  /// Rebuilds the whole page in place.
  ///
  /// Used when the data the page shows changed outside of the controls (for example the
  /// account settings page after logout): the page keeps its scroll position and window,
  /// only the form content is recreated by calling `buildForm()` again.
  func reloadForm() {
    guard isViewLoaded, lastAnchor != nil else { return }

    for subview in documentView.subviews {
      subview.removeFromSuperview()
    }
    wrappingLabels.removeAll()
    lastAnchor = documentView.topAnchor

    addPageTitle()
    buildForm()
    finishForm()

    documentView.needsLayout = true
    view.needsLayout = true
  }

  // MARK: - Page title

  private func addPageTitle() {
    let titleLabel = NSTextField(labelWithString: pageTitleText)
    titleLabel.font = MacTheme.largeTitleFont
    titleLabel.textColor = .labelColor
    append(titleLabel, topSpacing: topInset)
  }

  // MARK: - Layout primitives

  func append(_ view: NSView, topSpacing: CGFloat, fillWidth: Bool = true) {
    view.translatesAutoresizingMaskIntoConstraints = false
    documentView.addSubview(view)

    var constraints = [
      view.leadingAnchor.constraint(
        equalTo: documentView.leadingAnchor,
        constant: horizontalInset
      ),
      view.topAnchor.constraint(equalTo: lastAnchor, constant: topSpacing),
    ]
    if fillWidth {
      constraints.append(
        view.trailingAnchor.constraint(
          equalTo: documentView.trailingAnchor,
          constant: -horizontalInset
        )
      )
    } else {
      constraints.append(
        view.trailingAnchor.constraint(
          lessThanOrEqualTo: documentView.trailingAnchor,
          constant: -horizontalInset
        )
      )
    }
    NSLayoutConstraint.activate(constraints)
    lastAnchor = view.bottomAnchor
  }

  private func finishForm() {
    lastAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -bottomInset)
      .isActive = true
  }

  // MARK: - Sections

  /// Appends a grouped card with the given rows plus optional header and footer text.
  /// Headers, footers and row labels share the same 16 pt horizontal guideline.
  func addSection(header: String? = nil, footer: String? = nil, rows: [NSView]) {
    if let header {
      appendIndented(makeGroupHeaderLabel(header), topSpacing: 22)
    }
    append(makeCard(rows: rows), topSpacing: header == nil ? 20 : 8)
    if let footer {
      appendIndented(makeFooterLabel(footer), topSpacing: 7)
    }
  }

  private func appendIndented(_ view: NSView, topSpacing: CGFloat) {
    let inset = horizontalInset + 16
    view.translatesAutoresizingMaskIntoConstraints = false
    documentView.addSubview(view)
    NSLayoutConstraint.activate([
      view.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: inset),
      view.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -inset),
      view.topAnchor.constraint(equalTo: lastAnchor, constant: topSpacing),
    ])
    lastAnchor = view.bottomAnchor
  }

  /// Flat container kept for custom callers that manage their own chrome.
  func makeFlatRows(_ rows: [NSView]) -> NSView {
    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false
    var previous = container.topAnchor
    for row in rows {
      row.translatesAutoresizingMaskIntoConstraints = false
      container.addSubview(row)
      NSLayoutConstraint.activate([
        row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        row.topAnchor.constraint(equalTo: previous),
      ])
      previous = row.bottomAnchor
    }
    previous.constraint(equalTo: container.bottomAnchor).isActive = true
    return container
  }

  private static var cardBackgroundColor: NSColor {
    NSColor(name: nil) { appearance in
      let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      return isDark
        ? NSColor.white.withAlphaComponent(0.055)
        : NSColor.black.withAlphaComponent(0.025)
    }
  }

  private static var cardBorderColor: NSColor {
    NSColor(name: nil) { appearance in
      let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      return isDark
        ? NSColor.white.withAlphaComponent(0.09)
        : NSColor.black.withAlphaComponent(0.07)
    }
  }

  private func makeCard(rows: [NSView]) -> NSView {
    let card = SettingsBackgroundView()
    card.backgroundColor = Self.cardBackgroundColor
    card.borderColor = Self.cardBorderColor
    card.borderWidth = 0.5
    card.cornerRadius = 10
    card.translatesAutoresizingMaskIntoConstraints = false

    var previousAnchor = card.topAnchor
    for (index, row) in rows.enumerated() {
      row.translatesAutoresizingMaskIntoConstraints = false
      card.addSubview(row)
      NSLayoutConstraint.activate([
        row.leadingAnchor.constraint(equalTo: card.leadingAnchor),
        row.trailingAnchor.constraint(equalTo: card.trailingAnchor),
        row.topAnchor.constraint(equalTo: previousAnchor),
      ])
      if index < rows.count - 1 {
        let separator = SettingsSeparatorView()
        card.addSubview(separator)
        NSLayoutConstraint.activate([
          separator.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
          separator.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
          separator.topAnchor.constraint(equalTo: row.bottomAnchor),
        ])
        previousAnchor = separator.bottomAnchor
      } else {
        previousAnchor = row.bottomAnchor
      }
    }
    previousAnchor.constraint(equalTo: card.bottomAnchor).isActive = true
    return card
  }

  private func makeGroupHeaderLabel(_ text: String) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = .systemFont(ofSize: 12, weight: .semibold)
    label.textColor = .secondaryLabelColor
    label.lineBreakMode = .byTruncatingTail
    return label
  }

  private func makeFooterLabel(_ text: String) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    label.font = MacTheme.secondaryFont
    label.textColor = .secondaryLabelColor
    label.maximumNumberOfLines = 0
    trackWrappingLabel(label, horizontalInsets: (horizontalInset + 16) * 2)
    return label
  }

  /// Registers a wrapping label whose `preferredMaxLayoutWidth` follows the form width.
  func trackWrappingLabel(_ label: NSTextField, horizontalInsets: CGFloat) {
    wrappingLabels.append((label, horizontalInsets))
  }

  // MARK: - Row factories

  func makeRow(title: String, control: NSView) -> NSView {
    SettingsRowView(title: title, control: control)
  }

  func makeRow(title: String, subtitle: String?, control: NSView) -> NSView {
    SettingsRowView(title: title, subtitle: subtitle, control: control)
  }

  func makeSwitchRow(
    title: String,
    subtitle: String? = nil,
    isOn: Bool,
    handler: @escaping (Bool) -> Void
  )
    -> NSView {
    SettingsRowView(
      title: title,
      subtitle: subtitle,
      control: SettingsSwitch(isOn: isOn, handler: handler)
    )
  }

  func makePopupRow(
    title: String,
    subtitle: String? = nil,
    titles: [String],
    selectedIndex: Int,
    handler: @escaping (Int) -> Void
  )
    -> NSView {
    SettingsRowView(
      title: title,
      subtitle: subtitle,
      control: SettingsPopUpButton(
        titles: titles,
        selectedIndex: selectedIndex,
        handler: handler
      )
    )
  }

  func makeSegmentedRow(
    title: String,
    subtitle: String? = nil,
    labels: [String],
    selectedIndex: Int,
    handler: @escaping (Int) -> Void
  )
    -> NSView {
    SettingsRowView(
      title: title,
      subtitle: subtitle,
      control: SettingsSegmentedControl(
        labels: labels,
        selectedIndex: selectedIndex,
        handler: handler
      )
    )
  }

  func makeSliderRow(
    title: String,
    subtitle: String? = nil,
    value: Double,
    range: ClosedRange<Double>,
    step: Double = 0,
    sliderWidth: CGFloat = 200,
    valueWidth: CGFloat = 60,
    valueFormatter: @escaping (Double) -> String,
    handler: @escaping (Double) -> Void
  )
    -> NSView {
    let slider = SettingsSliderControl(
      value: value,
      range: range,
      step: step,
      sliderWidth: sliderWidth,
      valueWidth: valueWidth,
      valueFormatter: valueFormatter,
      handler: handler
    )
    return SettingsRowView(title: title, subtitle: subtitle, control: slider)
  }

  func makeValueRow(title: String, value: String) -> NSView {
    let valueLabel = NSTextField(labelWithString: value)
    valueLabel.font = MacTheme.bodyFont
    valueLabel.textColor = .secondaryLabelColor
    valueLabel.alignment = .right
    valueLabel.lineBreakMode = .byTruncatingMiddle
    valueLabel.isSelectable = true
    valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    valueLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
    return SettingsRowView(title: title, control: valueLabel)
  }

  /// A card row that only shows text (empty states, notes).
  func makeTextRow(_ text: String) -> NSView {
    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false
    let label = NSTextField(wrappingLabelWithString: text)
    label.font = MacTheme.bodyFont
    label.textColor = .labelColor
    label.maximumNumberOfLines = 0
    label.translatesAutoresizingMaskIntoConstraints = false
    trackWrappingLabel(label, horizontalInsets: (horizontalInset + 16) * 2)
    container.addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
      label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
      label.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
      label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
    ])
    return container
  }

  /// Appends a footnote-style secondary label (aligned with card row titles).
  func addFootnote(_ text: String) {
    appendIndented(makeFooterLabel(text), topSpacing: 8)
  }

  /// Appends a standalone rounded push button (leading aligned, intrinsic width).
  func addButton(title: String, isEnabled: Bool = true, handler: @escaping () -> Void) {
    let button = SettingsButton(title: title, isEnabled: isEnabled, handler: handler)
    append(button, topSpacing: 14, fillWidth: false)
  }
}
