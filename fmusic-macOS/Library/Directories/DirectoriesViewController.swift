//
//  DirectoriesViewController.swift
//  fmusic-macOS
//
//  Directories page container: drill-down browser for the account's music folders,
//  directories and the songs stored in them. Owns the navigation path and swaps a
//  `DirectoryContentViewController` page per level (with back navigation).
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

// MARK: - DirectoryNode

/// One folder level of the directory browser (a music folder or a subdirectory).
@MainActor
enum DirectoryNode {
  case musicFolder(MusicFolder)
  case directory(Directory)

  var name: String {
    switch self {
    case .musicFolder(let musicFolder): return musicFolder.name
    case .directory(let directory): return directory.name
    }
  }
}

// MARK: - DirectoriesViewController

/// Container for the sidebar's `.directories` entry.
///
/// The root page lists the account's music folders; double-clicking a folder drills
/// into its directories and songs, with a back button that walks the path up again.
@MainActor
final class DirectoriesViewController: NSViewController {
  private let contentView = NSView()
  private var currentChild: NSViewController?

  /// Current drill-down path; empty means the music folder overview.
  private var path: [DirectoryNode] = []

  override func loadView() {
    let root = NSView()
    root.wantsLayer = true

    contentView.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(contentView)
    NSLayoutConstraint.activate([
      contentView.topAnchor.constraint(equalTo: root.topAnchor),
      contentView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      contentView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      contentView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
    ])

    self.view = root
    showRoot()
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(accountChanged),
      name: .accountActiveChanged,
      object: nil
    )
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  // MARK: - Navigation

  @objc
  private func accountChanged() {
    // A different account has its own folders: start over at the top level.
    showRoot()
  }

  private func showRoot() {
    path = []
    showPage()
  }

  private func open(_ node: DirectoryNode) {
    path.append(node)
    showPage()
  }

  private func goBack() {
    guard !path.isEmpty else { return }
    path.removeLast()
    showPage()
  }

  private func showPage() {
    let node = path.last
    let backTitle: String? = path.isEmpty
      ? nil
      : (path.count >= 2 ? path[path.count - 2].name : L10n.tr("Directories"))
    let page = DirectoryContentViewController(node: node, backTitle: backTitle)
    page.onBack = path.isEmpty ? nil : { [weak self] in
      self?.goBack()
    }
    page.onOpenFolder = { [weak self] node in
      self?.open(node)
    }
    install(page)
  }

  private func install(_ controller: NSViewController) {
    currentChild?.view.removeFromSuperview()
    currentChild?.removeFromParent()

    controller.view.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(controller.view)
    NSLayoutConstraint.activate([
      controller.view.topAnchor.constraint(equalTo: contentView.topAnchor),
      controller.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      controller.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      controller.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
    ])
    addChild(controller)
    currentChild = controller
  }
}
