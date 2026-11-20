//
//  LyricsPageWindowController.swift
//  fmusic-macOS
//
//  Hosts `LyricsPageViewController` in its own window so a View menu item can open
//  the full lyrics page with a single call.
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

/// Single reusable window hosting the full lyrics page.
///
/// Wiring from a menu action (owned by `AppDelegate`):
///
/// ```swift
/// @objc func showLyricsPage(_ sender: Any?) {
///   LyricsPageWindowController.present()
/// }
/// ```
@MainActor
final class LyricsPageWindowController: NSWindowController, NSWindowDelegate {
  private static var shared: LyricsPageWindowController?

  /// Opens (or re-focuses) the full lyrics window for the currently playing song.
  static func present() {
    let controller = shared ?? LyricsPageWindowController()
    shared = controller
    controller.showPage()
  }

  init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 860, height: 700),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.minSize = NSSize(width: 600, height: 460)
    window.isReleasedWhenClosed = false
    window.title = L10n.tr("Lyrics")
    window.center()
    super.init(window: window)
    window.delegate = self
  }

  required init?(coder: NSCoder) {
    nil
  }

  private func showPage() {
    window?.contentViewController = LyricsPageViewController()
    showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }

  func windowWillClose(_ notification: Notification) {
    Self.shared = nil
  }
}
