//
//  PlaylistsViewController.swift
//  fmusic-macOS
//
//  Playlists page container: shows the playlist list and swaps in a detail page
//  (own child view controller) when a playlist is opened.
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

/// Container for the sidebar's `.playlists` entry.
///
/// The list page pushes `PlaylistDetailViewController` into this container and the
/// detail page calls back to the list, so the Lead only has to map the sidebar item
/// to `PlaylistsViewController()`.
@MainActor
final class PlaylistsViewController: NSViewController {
  private let contentView = NSView()
  private var currentChild: NSViewController?

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
    showList()
  }

  // MARK: - Navigation

  private func showList() {
    let list = PlaylistListViewController()
    list.onSelect = { [weak self] playlist in
      self?.showDetail(playlist)
    }
    install(list)
  }

  private func showDetail(_ playlist: Playlist) {
    let detail = PlaylistDetailViewController(playlist: playlist)
    detail.onBack = { [weak self] in
      self?.showList()
    }
    install(detail)
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
