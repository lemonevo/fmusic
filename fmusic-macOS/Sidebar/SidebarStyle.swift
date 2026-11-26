//
//  SidebarStyle.swift
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

/// Shared Apple Music-style visual language for the main and settings sidebars.
/// The two sidebars keep their own data sources and controllers; only the
/// presentation (metrics, row plate, icons, group headers) is unified here.
@MainActor
enum SidebarStyle {
  /// Catalyst `LibraryNavigatorConfigurator` / `SettingsTabView`: 13 pt text,
  /// 16 pt regular symbols, a 22 pt icon slot and 38 pt rows.
  static let rowHeight: CGFloat = 38
  static let sectionRowHeight: CGFloat = 34
  static let iconLeading: CGFloat = 16
  static let iconSize: CGFloat = 22
  static let symbolPointSize: CGFloat = 16
  static let iconTextSpacing: CGFloat = 8
  static let selectionHorizontalInset: CGFloat = 8
  static let selectionCornerRadius: CGFloat = 8

  static var bodyFont: NSFont { .systemFont(ofSize: 13, weight: .regular) }
  static var titleFont: NSFont { .systemFont(ofSize: 13, weight: .medium) }
  static var sectionFont: NSFont { .systemFont(ofSize: 11, weight: .semibold) }

  /// Resolves suffixed symbol names (`foo.fill`) to the plain outline variant.
  static func outlineSymbolName(_ name: String) -> String {
    var result = name
    for suffix in [".fill", ".circle.fill", ".square.fill"] where result.hasSuffix(suffix) {
      result = String(result.dropLast(suffix.count))
      if suffix == ".circle.fill" { result += ".circle" }
      if suffix == ".square.fill" { result += ".square" }
      break
    }
    return result
  }

  static func image(named name: String) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: symbolPointSize, weight: .regular))
  }
}

/// A row view that keeps the neutral grey capsule and never inverts text/icon
/// colours to white on selection (Catalyst keeps dark text and a red icon).
/// Inherits rounded hover feedback from `ThemedRowView` for both sidebars.
@MainActor
class SidebarRowView: ThemedRowView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    cornerRadius = SidebarStyle.selectionCornerRadius
    horizontalInset = SidebarStyle.selectionHorizontalInset
    solidSelectionColor = MacTheme.sidebarSelectionColor
    hoverColor = MacTheme.sidebarHoverColor
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    hoverColor = MacTheme.sidebarHoverColor
  }

  override var isEmphasized: Bool {
    get { false }
    set { super.isEmphasized = false }
  }
}

/// Shared cell for one sidebar row. `usesMediumText` differentiates the grouped
/// settings rows from the main library list while keeping metrics identical.
@MainActor
private final class SidebarDragHandleView: NSImageView {}

@MainActor
class SidebarTableCellView: NSTableCellView {
  private let iconView = NSImageView()
  private let titleField = NSTextField(labelWithString: "")
  private var iconLeadingConstraint: NSLayoutConstraint!
  private let usesMediumText: Bool
  private let showsDragHandleView: Bool

  /// Optional left accessory (edit-mode check circle) shifts the icon right.
  var leadingInset: CGFloat = SidebarStyle.iconLeading {
    didSet { iconLeadingConstraint.constant = leadingInset }
  }

  var showsDragHandle: Bool {
    get { !dragHandle.isHidden }
    set { dragHandle.isHidden = !newValue || !showsDragHandleView }
  }

  private let dragHandle = SidebarDragHandleView()

  override init(frame frameRect: NSRect) {
    self.usesMediumText = false
    self.showsDragHandleView = false
    super.init(frame: frameRect)
    configureSharedViews()
  }

  init(frame frameRect: NSRect, usesMediumText: Bool, supportsDragHandle: Bool) {
    self.usesMediumText = usesMediumText
    self.showsDragHandleView = supportsDragHandle
    super.init(frame: frameRect)
    configureSharedViews()
  }

  required init?(coder: NSCoder) {
    self.usesMediumText = false
    self.showsDragHandleView = false
    super.init(coder: coder)
    configureSharedViews()
  }

  private func configureSharedViews() {
    iconView.contentTintColor = MacTheme.accentColor
    iconView.imageScaling = .scaleProportionallyDown
    iconView.translatesAutoresizingMaskIntoConstraints = false
    titleField.font = usesMediumText ? SidebarStyle.titleFont : SidebarStyle.bodyFont
    titleField.textColor = .labelColor
    titleField.lineBreakMode = .byTruncatingTail
    titleField.translatesAutoresizingMaskIntoConstraints = false
    addSubview(iconView)
    addSubview(titleField)

    dragHandle.image = NSImage(
      systemSymbolName: "line.3.horizontal",
      accessibilityDescription: L10n.tr("Reorder")
    )?.withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
    dragHandle.contentTintColor = .tertiaryLabelColor
    dragHandle.isHidden = !showsDragHandleView
    dragHandle.translatesAutoresizingMaskIntoConstraints = false
    addSubview(dragHandle)

    iconLeadingConstraint = iconView.leadingAnchor.constraint(
      equalTo: leadingAnchor,
      constant: SidebarStyle.iconLeading
    )
    NSLayoutConstraint.activate([
      iconLeadingConstraint,
      iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
      iconView.widthAnchor.constraint(equalToConstant: SidebarStyle.iconSize),
      iconView.heightAnchor.constraint(equalToConstant: SidebarStyle.iconSize),

      titleField.leadingAnchor.constraint(
        equalTo: iconView.trailingAnchor,
        constant: SidebarStyle.iconTextSpacing
      ),
      titleField.trailingAnchor.constraint(
        lessThanOrEqualTo: dragHandle.leadingAnchor,
        constant: -6
      ),
      titleField.centerYAnchor.constraint(equalTo: centerYAnchor),

      dragHandle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
      dragHandle.centerYAnchor.constraint(equalTo: centerYAnchor),
      dragHandle.widthAnchor.constraint(equalToConstant: 16),
      dragHandle.heightAnchor.constraint(equalToConstant: 16),
    ])
    // Do not assign `textField`/`imageView`: NSTableCellView would repaint them
    // white on selection, while Catalyst keeps dark text and a red icon.
  }

  /// `isFilled` is reserved for favourite / status semantics; ordinary items
  /// use the outline symbol even when the source name carries a `.fill` suffix.
  func configure(symbolName: String, title: String, isFilled: Bool = false) {
    let name = isFilled ? symbolName : Self.outlineSymbolName(symbolName)
    iconView.image = Self.image(named: name)
    // Theme colour is a concrete value, not a dynamic system colour, so reused
    // cells must re-read it after a theme change.
    iconView.contentTintColor = MacTheme.accentColor
    titleField.stringValue = title
  }

  static func image(named name: String) -> NSImage? {
    SidebarStyle.image(named: name)
  }

  static func outlineSymbolName(_ name: String) -> String {
    SidebarStyle.outlineSymbolName(name)
  }
}

/// Shared non-selectable group header used by both sidebars.
@MainActor
final class SidebarSectionCellView: NSTableCellView {
  var title: String = "" {
    didSet { label.stringValue = title }
  }

  private let label = NSTextField(labelWithString: "")

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    label.font = SidebarStyle.sectionFont
    label.textColor = .secondaryLabelColor
    label.translatesAutoresizingMaskIntoConstraints = false
    addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(
        equalTo: leadingAnchor,
        constant: SidebarStyle.iconLeading
      ),
      label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
    ])
  }

  required init?(coder: NSCoder) {
    nil
  }
}
