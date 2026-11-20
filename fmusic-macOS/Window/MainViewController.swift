//
//  MainViewController.swift
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

/// Root content controller of the main window.
///
/// Layout (Apple Music style):
///   ┌────────────┬────────────────────────────┐
///   │ sidebar    │ library content            │
///   │ (210 pt)   │                            │
///   ├────────────┴────────────────────────────┤
///   │ player bar (72 pt)                      │
///   └─────────────────────────────────────────┘
///
/// The individual pieces land with the library/player tasks; this scaffold only
/// establishes the container hierarchy.
@MainActor
final class MainViewController: NSViewController {
  private(set) var sidebarViewController = SidebarViewController()
  private(set) var contentContainerViewController = NSViewController()
  private(set) var playerBarViewController = PlayerBarViewController()

  private let splitViewController = NSSplitViewController()

  override func loadView() {
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 1024, height: 768))
    root.wantsLayer = true

    // Sidebar + content.
    let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarViewController)
    sidebarItem.minimumThickness = 180
    sidebarItem.maximumThickness = 320
    sidebarItem.canCollapse = false
    sidebarItem.holdingPriority = NSLayoutConstraint.Priority(260)

    let contentItem = NSSplitViewItem(viewController: contentContainerViewController)
    contentItem.minimumThickness = 480

    splitViewController.addSplitViewItem(sidebarItem)
    splitViewController.addSplitViewItem(contentItem)
    splitViewController.splitView.dividerStyle = .thin

    // Player bar.
    addChild(playerBarViewController)

    for child in [splitViewController, playerBarViewController] as [NSViewController] {
      child.view.translatesAutoresizingMaskIntoConstraints = false
      root.addSubview(child.view)
    }
    addChild(splitViewController)

    NSLayoutConstraint.activate([
      splitViewController.view.topAnchor.constraint(equalTo: root.topAnchor),
      splitViewController.view.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      splitViewController.view.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      splitViewController.view.bottomAnchor.constraint(equalTo: playerBarViewController.view.topAnchor),

      playerBarViewController.view.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      playerBarViewController.view.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      playerBarViewController.view.bottomAnchor.constraint(equalTo: root.bottomAnchor),
      playerBarViewController.view.heightAnchor.constraint(equalToConstant: 76),
    ])

    self.view = root
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    sidebarViewController.onSelectionChanged = { [weak self] item in
      self?.show(item: item)
    }
    // Dev hook: `open fmusic.app --args --songs` opens the song list directly.
    let arguments = ProcessInfo.processInfo.arguments
    let initialItem: SidebarItem = arguments.contains("--songs") ? .songs : .home
    sidebarViewController.select(item: initialItem)
    show(item: initialItem)
  }

  private func show(item: SidebarItem) {
    let controller: NSViewController
    switch item {
    case .songs:
      controller = SongsViewController()
    default:
      controller = LibraryPlaceholderViewController(item: item)
    }
    for child in contentContainerViewController.children {
      child.view.removeFromSuperview()
      child.removeFromParent()
    }
    controller.view.translatesAutoresizingMaskIntoConstraints = false
    contentContainerViewController.view.addSubview(controller.view)
    NSLayoutConstraint.activate([
      controller.view.topAnchor.constraint(equalTo: contentContainerViewController.view.topAnchor),
      controller.view.leadingAnchor.constraint(equalTo: contentContainerViewController.view.leadingAnchor),
      controller.view.trailingAnchor.constraint(equalTo: contentContainerViewController.view.trailingAnchor),
      controller.view.bottomAnchor.constraint(equalTo: contentContainerViewController.view.bottomAnchor),
    ])
    contentContainerViewController.addChild(controller)
  }
}
