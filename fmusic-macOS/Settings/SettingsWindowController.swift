//
//  SettingsWindowController.swift
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

/// Separate settings window (900×620 content), mirroring the Catalyst app behaviour:
/// closing it destroys the page hierarchy so a reopen rebuilds from the persisted
/// settings (and is still instant because the window itself is kept alive).
@MainActor
final class SettingsWindowController: NSWindowController {
  static let autosaveName = "fmusic.macOS.settingsWindow"

  convenience init() {
    let contentSize = SettingsViewController.contentSize
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: contentSize),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = L10n.tr("Settings")
    window.contentMinSize = contentSize
    window.minSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize))
      .size
    window.isReleasedWhenClosed = false
    window.tabbingMode = .disallowed
    window.contentViewController = SettingsViewController()

    self.init(window: window)

    window.setFrameAutosaveName(Self.autosaveName)
    if !window.setFrameUsingName(Self.autosaveName) {
      center(window)
    } else if window.screen == nil {
      // The saved frame no longer maps to a connected display.
      center(window)
    }

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowWillClose(_:)),
      name: NSWindow.willCloseNotification,
      object: window
    )
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  /// Rebuilds the page hierarchy after the window was closed (the window itself stays
  /// alive thanks to `isReleasedWhenClosed = false`).
  override func showWindow(_ sender: Any?) {
    if window?.contentViewController == nil {
      window?.contentViewController = SettingsViewController()
    }
    super.showWindow(sender)
  }

  @objc
  private func windowWillClose(_ notification: Notification) {
    // Drop the sidebar/pages so the next open reflects settings changed elsewhere.
    window?.contentViewController = nil
  }

  // MARK: - Centering

  private func center(_ window: NSWindow) {
    guard let mainWindow = AppDelegate.sharedAppDelegate?.mainWindowController?.window else {
      window.center()
      return
    }
    let mainFrame = mainWindow.frame
    let origin = NSPoint(
      x: mainFrame.midX - window.frame.width / 2,
      y: mainFrame.midY - window.frame.height / 2
    )
    window.setFrameOrigin(origin)
  }
}
