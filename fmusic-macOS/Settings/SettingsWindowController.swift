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

private final class EventMonitor {
  var handler: ((NSEvent) -> NSEvent?)?
  private var monitor: Any?

  init() {
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      self?.handler?(event) ?? event
    }
  }

  deinit {
    if let monitor { NSEvent.removeMonitor(monitor) }
  }
}

/// Separate settings window (900×620 content), mirroring the Catalyst app behaviour:
/// closing it destroys the page hierarchy so a reopen rebuilds from the persisted
/// settings (and is still instant because the window itself is kept alive).
@MainActor
final class SettingsWindowController: NSWindowController {
  static let autosaveName = "fmusic.macOS.settingsWindow"

  private let escapeMonitor = EventMonitor()

  convenience init() {
    let contentSize = SettingsViewController.contentSize
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: contentSize),
      styleMask: [
        .titled, .closable, .miniaturizable, .resizable, .fullSizeContentView
      ],
      backing: .buffered,
      defer: false
    )
    window.title = L10n.tr("Settings")
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.titlebarSeparatorStyle = .none
    window.backgroundColor = MacTheme.contentBackgroundColor
    window.contentMinSize = contentSize
    window.minSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize))
      .size
    window.isReleasedWhenClosed = false
    window.tabbingMode = .disallowed

    // The Catalyst settings scene has a transparent titlebar: an empty unified toolbar
    // gives the traffic lights the same breathing room as the main window instead of
    // squeezing them against the top edge.
    let toolbar = NSToolbar(identifier: "fmusic.settingsToolbar")
    toolbar.displayMode = .iconOnly
    window.toolbar = toolbar
    window.toolbarStyle = .unified
    window.isRestorable = false

    self.init(window: window)
    // Assign after NSWindowController init: doing it before was cleared by the
    // controller initialization and produced an empty settings window.
    window.contentViewController = SettingsViewController()

    // Esc closes the settings window now that the explicit “Back to App” row is gone.
    // A local monitor keeps normal Escape handling (text fields, popovers) intact:
    // only an unhandled Escape with the settings window key closes it.
    escapeMonitor.handler = { [weak self] event in
      guard let window = self?.window, window.isKeyWindow,
            event.keyCode == 53 else { return nil }
      window.performClose(nil)
      return nil
    }

    center(window)

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
  /// alive thanks to `isReleasedWhenClosed = false`), and centers over the main window
  /// with a subtle fade + rise transition so opening Settings never feels abrupt.
  override func showWindow(_ sender: Any?) {
    guard let window else {
      super.showWindow(sender)
      return
    }
    if window.contentViewController == nil {
      window.contentViewController = SettingsViewController()
    }
    let wasVisible = window.isVisible
    if !wasVisible {
      center(window)
    }
    guard !wasVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
      window.alphaValue = 1
      super.showWindow(sender)
      return
    }
    let targetOrigin = window.frame.origin
    window.setFrameOrigin(NSPoint(x: targetOrigin.x, y: targetOrigin.y - 10))
    window.alphaValue = 0
    super.showWindow(sender)
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.18
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      window.animator().alphaValue = 1
      window.animator().setFrameOrigin(targetOrigin)
    }
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
    var origin = NSPoint(
      x: mainFrame.midX - window.frame.width / 2,
      y: mainFrame.midY - window.frame.height / 2
    )
    if let visible = (mainWindow.screen ?? NSScreen.main)?.visibleFrame {
      origin.x = min(max(origin.x, visible.minX), max(visible.minX, visible.maxX - window.frame.width))
      origin.y = min(max(origin.y, visible.minY), max(visible.minY, visible.maxY - window.frame.height))
    }
    window.setFrameOrigin(origin)
  }
}
