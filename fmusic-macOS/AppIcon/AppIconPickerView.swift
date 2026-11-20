//
//  AppIconPickerView.swift
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

/// Layout metrics shared by the app icon grid and its cells.
private enum AppIconGridMetrics {
  /// Number of previews per row, matching the Catalyst settings section.
  static let columnCount = 4
  static let cellWidth: CGFloat = 88
  static let cellSpacing: CGFloat = 12
  static let previewSize: CGFloat = 64
}

/// Grid of selectable app icon previews for the display settings page.
///
/// Pure AppKit counterpart of the Catalyst `AppIconSettingsSection`: the previews are
/// grouped by icon family, four per row, and the selected icon is outlined with the app
/// theme color. Selecting an icon hands its identifier to `handler`, which applies the
/// change through `AppIconManager`.
@MainActor
final class AppIconPickerView: NSView {
  private let handler: (String) -> Void
  private var cells: [AppIconCellView] = []
  private var selectedID: String

  init(selectedID: String, handler: @escaping (String) -> Void) {
    self.selectedID = selectedID
    self.handler = handler
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    buildContent()
    // The selected outline uses the account theme color, which can change while the page
    // is open (the theme row is on the same page).
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

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  // MARK: - Selection

  /// Re-reads the persisted selection (e.g. after another window changed it).
  func refreshSelection() {
    selectedID = AppIconManager.selectedIconID
    updateSelection()
  }

  @objc
  private func themeColorChanged() {
    updateSelection()
  }

  @objc
  private func cellClicked(_ sender: AppIconCellView) {
    guard sender.option.id != selectedID else { return }
    selectedID = sender.option.id
    updateSelection()
    handler(sender.option.id)
  }

  private func updateSelection() {
    for cell in cells {
      cell.setSelected(cell.option.id == selectedID)
    }
  }

  // MARK: - Content

  private func buildContent() {
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 18
    stack.translatesAutoresizingMaskIntoConstraints = false

    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
    ])

    for category in MacAppIconCategory.allCases {
      let options = AppIconManager.options(in: category)
      guard !options.isEmpty else { continue }

      let headerLabel = NSTextField(labelWithString: category.title)
      headerLabel.font = .systemFont(ofSize: MacTheme.secondaryFontSize, weight: .semibold)
      headerLabel.textColor = .secondaryLabelColor
      stack.addArrangedSubview(headerLabel)

      let familyStack = NSStackView()
      familyStack.orientation = .vertical
      familyStack.alignment = .leading
      familyStack.spacing = AppIconGridMetrics.cellSpacing

      let columnCount = AppIconGridMetrics.columnCount
      for start in stride(from: 0, to: options.count, by: columnCount) {
        let rowOptions = options[start ..< min(start + columnCount, options.count)]
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = AppIconGridMetrics.cellSpacing

        for option in rowOptions {
          let cell = AppIconCellView(
            option: option,
            image: AppIconManager.previewImage(for: option),
            selected: option.id == selectedID
          )
          cell.target = self
          cell.action = #selector(cellClicked(_:))
          cells.append(cell)
          row.addArrangedSubview(cell)
        }

        familyStack.addArrangedSubview(row)
      }

      stack.addArrangedSubview(familyStack)
    }
  }
}

// MARK: - AppIconCellView

/// One icon preview: rounded image, caption and a theme colored outline when selected.
@MainActor
private final class AppIconCellView: NSButton {
  let option: MacAppIconOption

  private let previewContainer = NSView()
  private let previewView = NSImageView()
  private let captionLabel = NSTextField(wrappingLabelWithString: "")
  private(set) var isSelected = false

  init(option: MacAppIconOption, image: NSImage?, selected: Bool) {
    self.option = option
    super.init(frame: .zero)

    translatesAutoresizingMaskIntoConstraints = false
    title = ""
    isBordered = false
    focusRingType = .none
    setButtonType(.momentaryChange)
    wantsLayer = true
    toolTip = option.localizedTitle

    previewContainer.wantsLayer = true
    previewContainer.layer?.cornerRadius = 14
    previewContainer.translatesAutoresizingMaskIntoConstraints = false
    addSubview(previewContainer)

    previewView.image = image
    previewView.imageScaling = .scaleProportionallyUpOrDown
    previewView.wantsLayer = true
    previewView.layer?.cornerRadius = 12
    previewView.layer?.masksToBounds = true
    previewView.translatesAutoresizingMaskIntoConstraints = false
    previewContainer.addSubview(previewView)

    captionLabel.stringValue = option.localizedTitle
    captionLabel.font = .systemFont(ofSize: MacTheme.secondaryFontSize)
    captionLabel.alignment = .center
    captionLabel.lineBreakMode = .byWordWrapping
    captionLabel.maximumNumberOfLines = 2
    captionLabel.translatesAutoresizingMaskIntoConstraints = false
    addSubview(captionLabel)

    NSLayoutConstraint.activate([
      widthAnchor.constraint(equalToConstant: AppIconGridMetrics.cellWidth),

      previewContainer.topAnchor.constraint(equalTo: topAnchor),
      previewContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
      previewContainer.widthAnchor.constraint(equalToConstant: AppIconGridMetrics.previewSize),
      previewContainer.heightAnchor.constraint(equalToConstant: AppIconGridMetrics.previewSize),

      previewView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
      previewView.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
      previewView.topAnchor.constraint(equalTo: previewContainer.topAnchor),
      previewView.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),

      captionLabel.topAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: 8),
      captionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
      captionLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
      captionLabel.heightAnchor.constraint(equalToConstant: 30),
      captionLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])

    setAccessibilityLabel(option.localizedTitle)
    setSelected(selected)
  }

  required init?(coder: NSCoder) {
    nil
  }

  // The preview and caption are plain subviews; make the whole cell one click target.
  override func hitTest(_ point: NSPoint) -> NSView? {
    guard super.hitTest(point) != nil else { return nil }
    return self
  }

  func setSelected(_ selected: Bool) {
    isSelected = selected
    previewContainer.layer?.borderWidth = selected ? 3 : 0
    previewContainer.layer?.borderColor = selected ? resolvedAccentCGColor() : nil
    captionLabel.textColor = selected ? MacTheme.accentColor : .labelColor
    setAccessibilityValue(selected ? L10n.tr("Selected") : "")
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    setSelected(isSelected)
  }

  private func resolvedAccentCGColor() -> CGColor {
    var cgColor = MacTheme.accentColor.cgColor
    effectiveAppearance.performAsCurrentDrawingAppearance {
      cgColor = MacTheme.accentColor.cgColor
    }
    return cgColor
  }
}
