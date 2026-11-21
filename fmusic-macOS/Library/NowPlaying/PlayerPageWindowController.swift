//
//  PlayerPageWindowController.swift
//  fmusic-macOS
//
//  Opens the queue / now playing pages in their own window so the Lead can wire a
//  menu action (e.g. View ▸ Now Playing) without touching MainViewController.
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

/// Single reusable window hosting the queue page.
///
/// The Now Playing page is *not* hosted here: it is a full-window overlay inside the
/// main window (`MainViewController.presentNowPlayingOverlay`), so resizing, full
/// screen and key-window focus behave natively.
@MainActor
final class PlayerPageWindowController: NSWindowController {
  private static var shared: PlayerPageWindowController?

  /// Shows the queue page in the player window, reusing the window when it is open.
  static func presentQueue() {
    let controller = shared ?? PlayerPageWindowController()
    shared = controller
    controller.showQueue()
  }

  init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.minSize = NSSize(width: 900, height: 640)
    window.isReleasedWhenClosed = false
    window.center()
    super.init(window: window)
  }

  required init?(coder: NSCoder) {
    nil
  }

  private func showQueue() {
    window?.contentViewController = QueueViewController()
    window?.title = L10n.tr("Queue")
    showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }
}
