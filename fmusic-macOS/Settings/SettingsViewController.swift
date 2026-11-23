//
//  SettingsViewController.swift
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

/// Root of the settings window: 210 pt sidebar plus the selected form page.
@MainActor
final class SettingsViewController: NSViewController {
  static let contentSize = NSSize(width: 900, height: 620)
  static let sidebarWidth: CGFloat = 210

  private let sidebarViewController = SettingsSidebarViewController()
  private let contentBackground = SettingsBackgroundView()
  private let separatorView = SettingsBackgroundView()

  private var currentPage: SettingsPage?
  private var currentPageViewController: NSViewController?

  override func loadView() {
    let root = NSView(frame: NSRect(origin: .zero, size: Self.contentSize))
    root.wantsLayer = true

    contentBackground.backgroundColor = MacTheme.contentBackgroundColor
    contentBackground.translatesAutoresizingMaskIntoConstraints = false

    separatorView.backgroundColor = MacTheme.columnDividerColor
    separatorView.translatesAutoresizingMaskIntoConstraints = false
    separatorView.widthAnchor.constraint(equalToConstant: 1).isActive = true

    addChild(sidebarViewController)
    sidebarViewController.view.translatesAutoresizingMaskIntoConstraints = false

    root.addSubview(contentBackground)
    root.addSubview(sidebarViewController.view)
    root.addSubview(separatorView)

    let sidebarLeading = sidebarViewController.view.leadingAnchor.constraint(
      equalTo: root.leadingAnchor
    )
    let contentLeading = contentBackground.leadingAnchor.constraint(
      equalTo: separatorView.trailingAnchor
    )
    NSLayoutConstraint.activate([
      sidebarViewController.view.topAnchor.constraint(equalTo: root.topAnchor),
      sidebarLeading,
      sidebarViewController.view.bottomAnchor.constraint(equalTo: root.bottomAnchor),
      sidebarViewController.view.widthAnchor.constraint(
        equalToConstant: Self.sidebarWidth
      ),

      separatorView.topAnchor.constraint(equalTo: root.topAnchor),
      separatorView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
      separatorView.leadingAnchor.constraint(
        equalTo: sidebarViewController.view.trailingAnchor
      ),

      contentBackground.topAnchor.constraint(equalTo: root.topAnchor),
      contentLeading,
      contentBackground.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      contentBackground.bottomAnchor.constraint(equalTo: root.bottomAnchor),
    ])
    self.view = root
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    sidebarViewController.onSelectionChanged = { [weak self] page in
      self?.show(page: page)
    }
    sidebarViewController.select(page: .general)
    show(page: .general)
  }

  // MARK: - Page switching

  private func show(page: SettingsPage) {
    guard currentPage != page else { return }
    currentPage = page

    if let current = currentPageViewController {
      current.view.removeFromSuperview()
      current.removeFromParent()
      currentPageViewController = nil
    }

    let controller = page.makeViewController()
    controller.view.translatesAutoresizingMaskIntoConstraints = false
    contentBackground.addSubview(controller.view)
    NSLayoutConstraint.activate([
      controller.view.topAnchor.constraint(equalTo: contentBackground.topAnchor),
      controller.view.leadingAnchor.constraint(equalTo: contentBackground.leadingAnchor),
      controller.view.trailingAnchor.constraint(equalTo: contentBackground.trailingAnchor),
      controller.view.bottomAnchor.constraint(equalTo: contentBackground.bottomAnchor),
    ])
    addChild(controller)
    currentPageViewController = controller
  }
}
