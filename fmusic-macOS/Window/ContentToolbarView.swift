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

  /// Leading inset of the back button / root title with the sidebar expanded.
  private static let expandedLeading: CGFloat = 20
  /// Collapsed layout, measured from the Catalyst window: the toolbar's sidebar
  /// toggle item starts 92 pt in (right of the 16 pt traffic lights at 18/41/64),
  /// and the page title starts at 136 pt, immediately after it.
  private static let collapsedToggleLeading: CGFloat = 92
  private static let collapsedLeading: CGFloat = 136

  private let backButton = NSButton()
  private let titleLabel = NSTextField(labelWithString: "")
  private let searchField = NSSearchField()
  private let searchIcon = NSImageView()
  /// Grey pill that hosts the bezel-less search field (matches the requested toolbar
  /// search box fill `#ECECEE`).
  private let searchFieldContainer = NSView()
  private let separator = NSView()
  /// Shown only while the library sidebar is collapsed, where the sidebar's own
  /// toggle is hidden along with its column (Catalyst moves its toolbar toggle here).
  private let sidebarToggleButton = SidebarTitleButton()
  /// Title pinned right after the back button (pushed pages).
  private var titleAfterBack: NSLayoutConstraint?
  /// Title pinned to the toolbar's leading edge (root pages, where the Catalyst
  /// app shows the title without reserving space for a hidden back button).
  private var titleAtLeading: NSLayoutConstraint?
  private var backLeading: NSLayoutConstraint?
  private var sidebarCollapsed = false

  var onBack: (() -> Void)?
  var onSearchChange: ((String) -> Void)?
  var onToggleSidebar: (() -> Void)?

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
    searchField.target = self
    searchField.action = #selector(searchSubmitted)
    searchField.translatesAutoresizingMaskIntoConstraints = false
    // Draw the field itself without a bezel and let the surrounding pill provide the
    // grey fill (NSSearchField's own bezel can't be tinted to #ECECEE reliably).
    searchField.isBezeled = false
    searchField.drawsBackground = false
    searchField.focusRingType = .none
    // The cell's built-in magnifier sticks at the field's left edge, while the field
    // editor (once focused) spans the full bounds and paints the placeholder under
    // it. Drop the built-in button and draw our own icon in the pill instead.
    (searchField.cell as? NSSearchFieldCell)?.searchButtonCell = nil

    searchIcon.image = NSImage(
      systemSymbolName: "magnifyingglass",
      accessibilityDescription: nil
    )?.withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
    // The system field draws its magnifier in the label colour, noticeably darker
    // than the placeholder text; keep that weight so the pill reads the same.
    searchIcon.contentTintColor = .labelColor
    searchIcon.imageScaling = .scaleProportionallyDown
    searchIcon.translatesAutoresizingMaskIntoConstraints = false

    searchFieldContainer.wantsLayer = true
    searchFieldContainer.layer?.cornerRadius = 10
    searchFieldContainer.layer?.cornerCurve = .continuous
    searchFieldContainer.layer?.backgroundColor =
      MacTheme.cgColor(MacTheme.searchFieldBackgroundColor, for: effectiveAppearance)
    searchFieldContainer.isHidden = true
    searchFieldContainer.translatesAutoresizingMaskIntoConstraints = false
    searchFieldContainer.addSubview(searchIcon)
    searchFieldContainer.addSubview(searchField)

    sidebarToggleButton.content = .symbol("sidebar.left")
    // White would vanish on the white content surface; the pill matches the search
    // field's grey, like the Catalyst toolbar's glass circle.
    sidebarToggleButton.fillColor = MacTheme.searchFieldBackgroundColor
    sidebarToggleButton.toolTip = L10n.tr("Show Sidebar")
    sidebarToggleButton.setAccessibilityRole(.button)
    sidebarToggleButton.setAccessibilityLabel(L10n.tr("Show Sidebar"))
    sidebarToggleButton.onClick = { [weak self] in self?.onToggleSidebar?() }
    sidebarToggleButton.isHidden = true
    sidebarToggleButton.translatesAutoresizingMaskIntoConstraints = false

    separator.isHidden = true
    separator.wantsLayer = true
    separator.translatesAutoresizingMaskIntoConstraints = false

    addSubview(sidebarToggleButton)
    addSubview(backButton)
    addSubview(titleLabel)
    addSubview(searchFieldContainer)
    addSubview(separator)

    let afterBack = titleLabel.leadingAnchor.constraint(
      equalTo: backButton.trailingAnchor,
      constant: 12
    )
    let atLeading = titleLabel.leadingAnchor.constraint(
      equalTo: leadingAnchor,
      constant: Self.expandedLeading
    )
    let backLeading = backButton.leadingAnchor.constraint(
      equalTo: leadingAnchor,
      constant: Self.expandedLeading
    )
    titleAfterBack = afterBack
    titleAtLeading = atLeading
    self.backLeading = backLeading

    NSLayoutConstraint.activate([
      sidebarToggleButton.leadingAnchor.constraint(
        equalTo: leadingAnchor,
        constant: Self.collapsedToggleLeading
      ),
      sidebarToggleButton.centerYAnchor.constraint(equalTo: centerYAnchor),
      sidebarToggleButton.widthAnchor.constraint(equalToConstant: 36),
      sidebarToggleButton.heightAnchor.constraint(equalToConstant: 32),

      backLeading,
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

      searchIcon.leadingAnchor.constraint(
        equalTo: searchFieldContainer.leadingAnchor,
        constant: 16
      ),
      searchIcon.centerYAnchor.constraint(equalTo: searchFieldContainer.centerYAnchor),
      searchIcon.widthAnchor.constraint(equalToConstant: 16),
      searchIcon.heightAnchor.constraint(equalToConstant: 16),

      searchField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 3),
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

  /// Re-lays the toolbar for the split view's collapsed primary column. With the
  /// sidebar hidden the page title moves next to the traffic lights and the circular
  /// sidebar toggle takes over the slot just right of them (Catalyst toolbar layout);
  /// with the sidebar open the sidebar column owns both, so the title returns to its
  /// 20 pt inset.
  func setSidebarCollapsed(_ collapsed: Bool) {
    guard collapsed != sidebarCollapsed else { return }
    sidebarCollapsed = collapsed
    sidebarToggleButton.isHidden = !collapsed
    let leading = collapsed ? Self.collapsedLeading : Self.expandedLeading
    backLeading?.constant = leading
    titleAtLeading?.constant = leading
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

  @objc
  private func searchSubmitted() {
    onSearchChange?(searchField.stringValue)
  }
}
