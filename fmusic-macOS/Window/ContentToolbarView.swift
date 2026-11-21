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
  private let separator = NSView()

  var onBack: (() -> Void)?
  var onSearchChange: ((String) -> Void)?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = MacTheme.contentBackgroundColor.cgColor

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

    titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
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
    searchField.isHidden = true

    separator.isHidden = true
    separator.wantsLayer = true
    separator.translatesAutoresizingMaskIntoConstraints = false

    addSubview(backButton)
    addSubview(titleLabel)
    addSubview(searchField)
    addSubview(separator)

    NSLayoutConstraint.activate([
      backButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
      backButton.centerYAnchor.constraint(equalTo: centerYAnchor),
      backButton.widthAnchor.constraint(equalToConstant: 32),
      backButton.heightAnchor.constraint(equalToConstant: 32),

      titleLabel.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 12),
      titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
      titleLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: searchField.leadingAnchor,
        constant: -16
      ),
      titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 460),

      searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
      searchField.centerYAnchor.constraint(equalTo: centerYAnchor),
      searchField.widthAnchor.constraint(equalToConstant: 260),

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
    layer?.backgroundColor = MacTheme.contentBackgroundColor.cgColor
  }

  func configure(title: String, showsBack: Bool, searchPlaceholder: String?) {
    titleLabel.stringValue = title
    backButton.isHidden = !showsBack
    // Keep the title aligned with pages that have no back button.
    backButton.alphaValue = showsBack ? 1 : 0
    backButton.isEnabled = showsBack
    if let searchPlaceholder, !searchPlaceholder.isEmpty {
      searchField.isHidden = false
      searchField.placeholderString = searchPlaceholder
      searchField.stringValue = ""
    } else {
      searchField.isHidden = true
      searchField.stringValue = ""
    }
  }

  @objc
  private func backPressed() {
    onBack?()
  }

  // MARK: - NSSearchFieldDelegate

  func controlTextDidChange(_ obj: Notification) {
    onSearchChange?(searchField.stringValue)
  }
}
