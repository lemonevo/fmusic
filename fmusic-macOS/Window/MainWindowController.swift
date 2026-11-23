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
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    // Kill the hard hairline under the titlebar so the sidebar's top edge blends into
    // the page instead of showing a grey band (the reference has no separator here).
    window.titlebarSeparatorStyle = .none
    window.backgroundColor = MacTheme.contentBackgroundColor
    window.minSize = NSSize(width: 980, height: 540)
    window.isReleasedWhenClosed = false
    window.tabbingMode = .disallowed

    // A unified (empty) toolbar gives the generous 52 pt titlebar of the reference so
    // the traffic lights line up with the 编辑 / sidebar buttons. No items are added —
    // the app draws its own titlebar buttons over the sidebar.
    let toolbar = NSToolbar(identifier: "fmusic.mainToolbar")
    toolbar.displayMode = .iconOnly
    window.toolbar = toolbar
    window.toolbarStyle = .unified

    self.init(window: window)

    window.setFrameAutosaveName(Self.autosaveName)
    if !window.setFrameUsingName(Self.autosaveName) {
      window.center()
    }

    window.contentViewController = MainViewController()
  }

  var mainViewController: MainViewController? {
    contentViewController as? MainViewController
  }
}
