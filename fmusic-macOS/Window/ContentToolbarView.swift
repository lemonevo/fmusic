//
//  ContentToolbarView.swift
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

/// A page that can be filtered by the content toolbar's search field.
@MainActor
protocol ContentSearchable: AnyObject {
  /// Placeholder shown in the search field, `nil` hides the field.
  var contentSearchPlaceholder: String? { get }
  func contentSearchDidChange(text: String)
}

/// Top toolbar of the content column (Catalyst fmusic style): circular back button,
/// page title and a pill search field on the right.
@MainActor
final class ContentToolbarView: NSView, NSSearchFieldDelegate {
  static let height: CGFloat = 52

  private let backButton = NSButton()
  private let titleLabel = NSTextField(labelWithString: "")
  private let searchField = NSSearchField()
  /// Grey pill that hosts the bezel-less search field (matches the requested toolbar
  /// search box fill `#ECECEE`).
  private let searchFieldContainer = NSView()
  private let separator = NSView()
  /// Title pinned right after the back button (pushed pages).
  private var titleAfterBack: NSLayoutConstraint?
  /// Title pinned to the toolbar's leading edge (root pages, where the Catalyst
  /// app shows the title without reserving space for a hidden back button).
  private var titleAtLeading: NSLayoutConstraint?

  var onBack: (() -> Void)?
  var onSearchChange: ((String) -> Void)?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = MacTheme.cgColor(MacTheme.toolbarBackgroundColor, for: effectiveAppearance)

    backButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil)
    backButton.isBordered = false
    backButton.bezelStyle = .regularSquare
    backButton.imagePosition = .imageOnly
    backButton.contentTintColor = .labelColor
    backButton.target = self
    backButton.action = #selector(backPressed)
    backButton.wantsLayer = true
    backButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
    backButton.layer?.cornerRadius = 16
    backButton.translatesAutoresizingMaskIntoConstraints = false

    // Measured from the original window: the toolbar title renders 28×14 pt of ink,
    // which is 15 pt regular (17 pt semibold was visibly larger).
    titleLabel.font = .systemFont(ofSize: 15, weight: .regular)
    titleLabel.lineBreakMode = .byTruncatingTail
    titleLabel.maximumNumberOfLines = 1
    // Long album names must truncate instead of stretching across the toolbar.
    titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    searchField.placeholderString = ""
    searchField.controlSize = .large
    searchField.delegate = self
    searchField.sendsSearchStringImmediately = true
    searchField.translatesAutoresizingMaskIntoConstraints = false
    // Draw the field itself without a bezel and let the surrounding pill provide the
    // grey fill (NSSearchField's own bezel can't be tinted to #ECECEE reliably).
    searchField.isBezeled = false
    searchField.drawsBackground = false
    searchField.focusRingType = .none

    searchFieldContainer.wantsLayer = true
    searchFieldContainer.layer?.cornerRadius = 10
    searchFieldContainer.layer?.cornerCurve = .continuous
    searchFieldContainer.layer?.backgroundColor =
      MacTheme.cgColor(MacTheme.searchFieldBackgroundColor, for: effectiveAppearance)
    searchFieldContainer.isHidden = true
    searchFieldContainer.translatesAutoresizingMaskIntoConstraints = false
    searchFieldContainer.addSubview(searchField)

    separator.isHidden = true
    separator.wantsLayer = true
    separator.translatesAutoresizingMaskIntoConstraints = false

    addSubview(backButton)
    addSubview(titleLabel)
    addSubview(searchFieldContainer)
    addSubview(separator)

    let afterBack = titleLabel.leadingAnchor.constraint(
      equalTo: backButton.trailingAnchor,
      constant: 12
    )
    let atLeading = titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20)
    titleAfterBack = afterBack
    titleAtLeading = atLeading

    NSLayoutConstraint.activate([
      backButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
      backButton.centerYAnchor.constraint(equalTo: centerYAnchor),
      backButton.widthAnchor.constraint(equalToConstant: 32),
      backButton.heightAnchor.constraint(equalToConstant: 32),

      // Root pages use the leading pin; pushed pages swap in `afterBack`.
      atLeading,
      titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
      titleLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: searchFieldContainer.leadingAnchor,
        constant: -16
      ),
      titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 460),

      searchFieldContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
      searchFieldContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
      // Matches the Catalyst integrated search field width.
      searchFieldContainer.widthAnchor.constraint(equalToConstant: 325),
      searchFieldContainer.heightAnchor.constraint(equalToConstant: 32),

      searchField.leadingAnchor.constraint(equalTo: searchFieldContainer.leadingAnchor, constant: 12),
      searchField.trailingAnchor.constraint(equalTo: searchFieldContainer.trailingAnchor, constant: -12),
      searchField.centerYAnchor.constraint(equalTo: searchFieldContainer.centerYAnchor),

      separator.leadingAnchor.constraint(equalTo: leadingAnchor),
      separator.trailingAnchor.constraint(equalTo: trailingAnchor),
      separator.bottomAnchor.constraint(equalTo: bottomAnchor),
      separator.heightAnchor.constraint(equalToConstant: 0.5),
    ])
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    layer?.backgroundColor = MacTheme.cgColor(MacTheme.toolbarBackgroundColor, for: effectiveAppearance)
    searchFieldContainer.layer?.backgroundColor =
      MacTheme.cgColor(MacTheme.searchFieldBackgroundColor, for: effectiveAppearance)
  }

  func configure(title: String, showsBack: Bool, searchPlaceholder: String?) {
    titleLabel.stringValue = title
    backButton.isHidden = !showsBack
    // Keep the title aligned with pages that have no back button: root pages pin it to
    // the leading edge instead of leaving the 32 pt button + 12 pt gap as dead space.
    titleAfterBack?.isActive = showsBack
    titleAtLeading?.isActive = !showsBack
    if let searchPlaceholder, !searchPlaceholder.isEmpty {
      searchFieldContainer.isHidden = false
      searchField.isHidden = false
      searchField.placeholderString = searchPlaceholder
      searchField.stringValue = ""
    } else {
      searchFieldContainer.isHidden = true
      searchField.isHidden = true
      searchField.stringValue = ""
    }
  }

  @objc
  private func backPressed() {
    onBack?()
  }

  /// Focuses the toolbar search field (⌘F).
  @objc
  func focusSearchField() {
    window?.makeFirstResponder(searchField)
  }

  // MARK: - NSSearchFieldDelegate

  func controlTextDidChange(_ obj: Notification) {
    onSearchChange?(searchField.stringValue)
  }
}
