//
//  MainWindowController.swift
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

/// The main library window (Apple Music style: 1024×768 default, 980×540 minimum).
@MainActor
final class MainWindowController: NSWindowController {
  static let autosaveName = "fmusic.macOS.mainWindow"

  convenience init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.title = "fmusic"
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.backgroundColor = MacTheme.contentBackgroundColor
    window.minSize = NSSize(width: 980, height: 540)
    window.isReleasedWhenClosed = false
    window.tabbingMode = .disallowed

    self.init(window: window)

    window.setFrameAutosaveName(Self.autosaveName)
    if !window.setFrameUsingName(Self.autosaveName) {
      window.center()
    }

    window.contentViewController = MainViewController()

    DispatchQueue.main.async { [weak self] in
      self?.nudgeTrafficLights()
    }
    NotificationCenter.default.addObserver(
      forName: NSWindow.didResizeNotification,
      object: window,
      queue: .main
    ) { [weak self] _ in
      self?.nudgeTrafficLights()
    }
  }

  /// Catalyst leaves a little more breathing room around the window buttons.
  private func nudgeTrafficLights() {
    guard let window else { return }
    let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
    for type in buttons {
      guard let button = window.standardWindowButton(type) else { continue }
      var frame = button.frame
      frame.origin.x += 14
      frame.origin.y -= 1
      button.frame = frame
    }
  }

  var mainViewController: MainViewController? {
    contentViewController as? MainViewController
  }
}
