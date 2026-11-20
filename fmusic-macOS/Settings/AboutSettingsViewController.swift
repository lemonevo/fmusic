//
//  AboutSettingsViewController.swift
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

/// 关于: app identity, version/build and the GitHub issue link.
@MainActor
final class AboutSettingsViewController: SettingsPageViewController {
  private static let issueURL = URL(string: "https://github.com/lemonevo/fmusic/issues")

  init() {
    super.init(title: L10n.tr("About"))
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func buildForm() {
    let version = Bundle.main.object(
      forInfoDictionaryKey: "CFBundleShortVersionString"
    ) as? String ?? "—"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"

    addSection(rows: [makeAppHeader()])

    let versionRow = makeValueRow(title: L10n.tr("Version"), value: version)
    let buildRow = makeValueRow(title: L10n.tr("Build Number"), value: build)
    addSection(header: L10n.tr("About"), rows: [versionRow, buildRow])

    addButton(title: L10n.tr("Report an issue on GitHub")) {
      guard let url = Self.issueURL else { return }
      NSWorkspace.shared.open(url)
    }
  }

  // MARK: - Header

  private func makeAppHeader() -> NSView {
    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false

    let iconView = NSImageView()
    iconView.image = NSApp.applicationIconImage
      ?? NSImage(named: NSImage.applicationIconName)
    iconView.imageScaling = .scaleProportionallyUpOrDown
    iconView.translatesAutoresizingMaskIntoConstraints = false

    let nameLabel = NSTextField(labelWithString: "fmusic")
    nameLabel.font = .systemFont(ofSize: 24, weight: .bold)
    nameLabel.textColor = .labelColor

    let creditsLabel = NSTextField(
      wrappingLabelWithString: L10n
        .tr("This software contains additional third party software.")
    )
    creditsLabel.font = MacTheme.secondaryFont
    creditsLabel.textColor = .secondaryLabelColor
    creditsLabel.maximumNumberOfLines = 0
    // Page insets plus the icon column (16 + 56 + 16) and the trailing inset.
    trackWrappingLabel(creditsLabel, horizontalInsets: 40 * 2 + 104)

    let licenseLabel = NSTextField(labelWithString: "GNU General Public License v3.0")
    licenseLabel.font = MacTheme.secondaryFont
    licenseLabel.textColor = .secondaryLabelColor

    let textStack = NSStackView(views: [nameLabel, creditsLabel, licenseLabel])
    textStack.orientation = .vertical
    textStack.alignment = .leading
    textStack.spacing = 3
    textStack.translatesAutoresizingMaskIntoConstraints = false

    container.addSubview(iconView)
    container.addSubview(textStack)
    NSLayoutConstraint.activate([
      iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
      iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
      iconView.widthAnchor.constraint(equalToConstant: 56),
      iconView.heightAnchor.constraint(equalToConstant: 56),

      textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 16),
      textStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
      textStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
      textStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
    ])
    return container
  }
}
