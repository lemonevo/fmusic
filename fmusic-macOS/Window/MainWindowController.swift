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
    let window = FmusicMainWindow(
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
  }

  var mainViewController: MainViewController? {
    contentViewController as? MainViewController
  }
}


// MARK: - FmusicMainWindow

/// The Catalyst window keeps the traffic lights further from the corner than a
/// standard AppKit window. AppKit re-lays them out on every titlebar layout, so
/// the positions are re-applied here after the superclass layout pass.
final class FmusicMainWindow: NSWindow {
  override func layoutIfNeeded() {
    super.layoutIfNeeded()
    positionWindowButtonsIfNeeded()
  }

  private func positionWindowButtonsIfNeeded() {
    guard let close = standardWindowButton(.closeButton),
          let mini = standardWindowButton(.miniaturizeButton),
          let zoom = standardWindowButton(.zoomButton)
    else { return }
    // The sidebar button row is centred at 26 pt from the window top; align the
    // traffic lights with it and give them a little breathing room from the corner.
    let flipped = close.superview?.isFlipped ?? false
    let targetCenter: CGFloat = 26
    let h = close.frame.height
    let y = flipped
      ? targetCenter - h / 2
      : (close.superview?.bounds.height ?? h) - targetCenter - h / 2
    close.frame.origin = NSPoint(x: 24, y: y)
    mini.frame.origin = NSPoint(x: 48, y: y)
    zoom.frame.origin = NSPoint(x: 72, y: y)
  }
}
