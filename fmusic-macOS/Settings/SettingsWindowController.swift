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

/// Separate settings window (900×620, centered on the main window), mirroring the
/// Catalyst app behaviour: closing it destroys the window so reopening never shows
/// an empty shell.
@MainActor
final class SettingsWindowController: NSWindowController {
  convenience init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.title = L10n.tr("Settings")
    window.minSize = NSSize(width: 900, height: 620)
    window.isReleasedWhenClosed = false
    window.tabbingMode = .disallowed
    window.setFrameAutosaveName("fmusic.macOS.settingsWindow")

    self.init(window: window)

    if let mainWindow = AppDelegate.sharedAppDelegate?.mainWindowController?.window {
      let mainFrame = mainWindow.frame
      let origin = NSPoint(
        x: mainFrame.midX - window.frame.width / 2,
        y: mainFrame.midY - window.frame.height / 2
      )
      window.setFrameOrigin(origin)
    } else if !window.setFrameUsingName("fmusic.macOS.settingsWindow") {
      window.center()
    }

    window.contentViewController = SettingsViewController()
  }
}

/// Placeholder content replaced by the AppKit settings pages.
@MainActor
final class SettingsViewController: NSViewController {
  override func loadView() {
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 620))
    let label = NSTextField(labelWithString: L10n.tr("Settings"))
    label.font = .systemFont(ofSize: 20, weight: .semibold)
    label.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(label)
    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    ])
    self.view = view
  }
}
