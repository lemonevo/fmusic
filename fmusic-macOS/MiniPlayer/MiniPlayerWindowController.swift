//
//  MiniPlayerWindowController.swift
//  fmusic-macOS
//
//  Small borderless player window (Apple Music style mini player). It controls the
//  same shared `PlayerFacade` as the library window's player bar, can be closed
//  without stopping playback, and can expand back into the main library window.
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

/// Borderless window that may become key (so its sliders/buttons work) but never
/// becomes the main window: opening the mini player must not steal the library
/// window's main-window role.
@MainActor
final class MiniPlayerWindow: NSWindow {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

// MARK: - MiniPlayerWindowController

@MainActor
final class MiniPlayerWindowController: NSWindowController {
  static let autosaveName = "fmusic.macOS.miniPlayerWindow"
  static let contentSize = NSSize(width: 380, height: 140)

  /// Called by the mini player's expand button (the app delegate switches back to the
  /// library window and closes this one).
  var onExpand: (() -> Void)?

  init() {
    let window = MiniPlayerWindow(
      contentRect: NSRect(origin: .zero, size: Self.contentSize),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.title = L10n.tr("Mini Player")
    window.isReleasedWhenClosed = false
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true
    window.isMovableByWindowBackground = true
    window.hidesOnDeactivate = false
    window.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
    window.minSize = Self.contentSize
    window.maxSize = Self.contentSize

    super.init(window: window)

    let contentViewController = MiniPlayerViewController()
    contentViewController.onExpand = { [weak self] in self?.onExpand?() }
    contentViewController.onClose = { [weak self] in self?.close() }
    window.contentViewController = contentViewController

    // Remember where the user parked the window across launches.
    window.setFrameAutosaveName(Self.autosaveName)
    if !window.setFrameUsingName(Self.autosaveName) {
      positionNearMainWindow(window)
    } else if window.screen == nil {
      // The saved frame no longer maps to a connected display.
      window.center()
    }

    applyAlwaysOnTopSetting()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(playbackSettingsChanged),
      name: .macPlaybackSettingsChanged,
      object: nil
    )
  }

  required init?(coder: NSCoder) {
    nil
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  /// The user setting `storage.settings.user.isMiniPlayerAlwaysOnTop` selects between a
  /// floating panel (above other apps) and a normal window.
  func applyAlwaysOnTopSetting() {
    let alwaysOnTop = FmusicKit.shared.storage.settings.user.isMiniPlayerAlwaysOnTop
    window?.level = alwaysOnTop ? .floating : .normal
  }

  override func showWindow(_ sender: Any?) {
    applyAlwaysOnTopSetting()
    super.showWindow(sender)
  }

  @objc
  private func playbackSettingsChanged() {
    applyAlwaysOnTopSetting()
  }

  // MARK: - Placement

  private func positionNearMainWindow(_ window: NSWindow) {
    guard let mainFrame = AppDelegate.sharedAppDelegate?.mainWindowController?.window?.frame
    else {
      window.center()
      return
    }
    let origin = NSPoint(
      x: mainFrame.minX + 32,
      y: mainFrame.minY + 32
    )
    window.setFrameOrigin(origin)
  }
}
