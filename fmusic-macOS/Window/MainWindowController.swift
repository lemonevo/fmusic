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
final class MainWindowController: NSWindowController, NSToolbarDelegate {
  static let autosaveName = "fmusic.macOS.mainWindow"

  convenience init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "fmusic"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
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

    let toolbar = NSToolbar(identifier: "fmusic.mainToolbar")
    toolbar.delegate = self
    toolbar.displayMode = .iconOnly
    window.toolbar = toolbar
    window.toolbarStyle = .unified
  }

  // MARK: - NSToolbarDelegate

  private static let editItemIdentifier = NSToolbarItem.Identifier("fmusic.edit")
  private static let sidebarItemIdentifier = NSToolbarItem.Identifier("fmusic.sidebar")

  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [Self.sidebarItemIdentifier, Self.editItemIdentifier, .flexibleSpace]
  }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    toolbarDefaultItemIdentifiers(toolbar)
  }

  func toolbar(
    _ toolbar: NSToolbar,
    itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
    willBeInsertedIntoToolbar flag: Bool
  )
    -> NSToolbarItem? {
    let item = NSToolbarItem(itemIdentifier: itemIdentifier)
    switch itemIdentifier {
    case Self.sidebarItemIdentifier:
      item.label = L10n.tr("Show Sidebar")
      item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: nil)
      item.target = self
      item.action = #selector(toggleSidebarPressed)
    case Self.editItemIdentifier:
      item.label = L10n.tr("Edit")
      item.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)
      item.target = self
      item.action = #selector(editPressed)
    default:
      return nil
    }
    item.isBordered = true
    return item
  }

  @objc
  private func toggleSidebarPressed() {
    mainViewController?.toggleSidebar()
  }

  @objc
  private func editPressed() {
    mainViewController?.presentHomeEditor()
  }

  var mainViewController: MainViewController? {
    contentViewController as? MainViewController
  }
}
