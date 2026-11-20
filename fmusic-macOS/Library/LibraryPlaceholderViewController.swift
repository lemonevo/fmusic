//
//  LibraryPlaceholderViewController.swift
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

/// Placeholder shown for library sections that are not ported to AppKit yet.
@MainActor
final class LibraryPlaceholderViewController: NSViewController {
  private let item: SidebarItem

  init(item: SidebarItem) {
    self.item = item
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func loadView() {
    let root = NSView()
    root.wantsLayer = true
    root.layer?.backgroundColor = MacTheme.contentBackgroundColor.cgColor

    let title = NSTextField(labelWithString: item.title)
    title.font = MacTheme.largeTitleFont
    title.translatesAutoresizingMaskIntoConstraints = false

    let subtitle = NSTextField(
      labelWithString: L10n.tr("Your %@ will appear here.", item.title)
    )
    subtitle.font = MacTheme.bodyFont
    subtitle.textColor = MacTheme.secondaryTextColor
    subtitle.translatesAutoresizingMaskIntoConstraints = false

    root.addSubview(title)
    root.addSubview(subtitle)
    NSLayoutConstraint.activate([
      title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
      title.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
      subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
      subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
      subtitle.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -24),
    ])
    self.view = root
  }
}
