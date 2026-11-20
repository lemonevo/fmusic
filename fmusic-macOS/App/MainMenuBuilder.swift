//
//  MainMenuBuilder.swift
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

/// Builds the whole main menu in code (the macOS app has no storyboard/nib).
@MainActor
enum MainMenuBuilder {
  private static var appDelegate: AppDelegate? { NSApp.delegate as? AppDelegate }

  static func build() -> NSMenu {
    let appName = "fmusic"
    let mainMenu = NSMenu()

    mainMenu.addItem(appMenu(appName: appName))
    mainMenu.addItem(fileMenu())
    mainMenu.addItem(editMenu())
    mainMenu.addItem(playbackMenu())
    mainMenu.addItem(viewMenu())
    mainMenu.addItem(windowMenu(appName: appName))
    mainMenu.addItem(helpMenu())
    return mainMenu
  }

  // MARK: - App

  private static func appMenu(appName: String) -> NSMenuItem {
    let item = NSMenuItem()
    let menu = NSMenu()
    menu.addItem(
      withTitle: "\(L10n.tr("About")) \(appName)",
      action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
      keyEquivalent: ""
    )
    menu.addItem(.separator())

    let settings = NSMenuItem(
      title: L10n.tr("Settings…"),
      action: #selector(AppDelegate.showSettings(_:)),
      keyEquivalent: ","
    )
    settings.target = appDelegate
    menu.addItem(settings)
    menu.addItem(.separator())

    let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
    let servicesMenu = NSMenu()
    servicesItem.submenu = servicesMenu
    NSApp.servicesMenu = servicesMenu
    menu.addItem(servicesItem)
    menu.addItem(.separator())

    menu.addItem(
      withTitle: "\(L10n.tr("Hide")) \(appName)",
      action: #selector(NSApplication.hide(_:)),
      keyEquivalent: "h"
    )
    let hideOthers = NSMenuItem(
      title: L10n.tr("Hide Others"),
      action: #selector(NSApplication.hideOtherApplications(_:)),
      keyEquivalent: "h"
    )
    hideOthers.keyEquivalentModifierMask = [.command, .option]
    menu.addItem(hideOthers)
    menu.addItem(
      withTitle: L10n.tr("Show All"),
      action: #selector(NSApplication.unhideAllApplications(_:)),
      keyEquivalent: ""
    )
    menu.addItem(.separator())

    menu.addItem(
      withTitle: "\(L10n.tr("Quit")) \(appName)",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    item.submenu = menu
    return item
  }

  // MARK: - File

  private static func fileMenu() -> NSMenuItem {
    let item = NSMenuItem()
    let menu = NSMenu(title: L10n.tr("File"))

    let open = NSMenuItem(
      title: L10n.tr("Open File"),
      action: #selector(AppDelegate.openAudioFile(_:)),
      keyEquivalent: "o"
    )
    open.target = appDelegate
    menu.addItem(open)
    menu.addItem(.separator())
    menu.addItem(
      withTitle: L10n.tr("Close"),
      action: #selector(NSWindow.performClose(_:)),
      keyEquivalent: "w"
    )

    item.submenu = menu
    return item
  }

  // MARK: - Edit

  private static func editMenu() -> NSMenuItem {
    let item = NSMenuItem()
    let menu = NSMenu(title: L10n.tr("Edit"))
    menu.addItem(withTitle: L10n.tr("Undo"), action: Selector(("undo:")), keyEquivalent: "z")
    let redo = NSMenuItem(
      title: L10n.tr("Redo"),
      action: Selector(("redo:")),
      keyEquivalent: "z"
    )
    redo.keyEquivalentModifierMask = [.command, .shift]
    menu.addItem(redo)
    menu.addItem(.separator())
    menu.addItem(withTitle: L10n.tr("Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    menu.addItem(
      withTitle: L10n.tr("Copy"),
      action: #selector(NSText.copy(_:)),
      keyEquivalent: "c"
    )
    menu.addItem(
      withTitle: L10n.tr("Paste"),
      action: #selector(NSText.paste(_:)),
      keyEquivalent: "v"
    )
    menu.addItem(
      withTitle: L10n.tr("Select All"),
      action: #selector(NSText.selectAll(_:)),
      keyEquivalent: "a"
    )
    item.submenu = menu
    return item
  }

  // MARK: - Playback

  private static func playbackMenu() -> NSMenuItem {
    let item = NSMenuItem()
    let menu = NSMenu(title: L10n.tr("Playback"))

    let playPause = NSMenuItem(
      title: L10n.tr("Play"),
      action: #selector(AppDelegate.togglePlayPause(_:)),
      keyEquivalent: " "
    )
    playPause.keyEquivalentModifierMask = []
    playPause.target = appDelegate
    menu.addItem(playPause)

    let next = NSMenuItem(
      title: L10n.tr("Next Track"),
      action: #selector(AppDelegate.playNext(_:)),
      keyEquivalent: String(UnicodeScalar(NSRightArrowFunctionKey)!)
    )
    next.keyEquivalentModifierMask = [.command]
    next.target = appDelegate
    menu.addItem(next)

    let previous = NSMenuItem(
      title: L10n.tr("Previous Track"),
      action: #selector(AppDelegate.playPrevious(_:)),
      keyEquivalent: String(UnicodeScalar(NSLeftArrowFunctionKey)!)
    )
    previous.keyEquivalentModifierMask = [.command]
    previous.target = appDelegate
    menu.addItem(previous)
    menu.addItem(.separator())

    let shuffle = NSMenuItem(
      title: L10n.tr("Shuffle"),
      action: #selector(AppDelegate.toggleShuffle(_:)),
      keyEquivalent: "s"
    )
    shuffle.target = appDelegate
    menu.addItem(shuffle)

    let repeatMode = NSMenuItem(
      title: L10n.tr("Repeat"),
      action: #selector(AppDelegate.cycleRepeatMode(_:)),
      keyEquivalent: "r"
    )
    repeatMode.target = appDelegate
    menu.addItem(repeatMode)
    menu.addItem(.separator())

    let volumeUp = NSMenuItem(
      title: L10n.tr("Volume") + " +",
      action: #selector(AppDelegate.adjustVolume(_:)),
      keyEquivalent: String(UnicodeScalar(NSUpArrowFunctionKey)!)
    )
    volumeUp.keyEquivalentModifierMask = [.command]
    volumeUp.tag = 1
    volumeUp.target = appDelegate
    menu.addItem(volumeUp)

    let volumeDown = NSMenuItem(
      title: L10n.tr("Volume") + " −",
      action: #selector(AppDelegate.adjustVolume(_:)),
      keyEquivalent: String(UnicodeScalar(NSDownArrowFunctionKey)!)
    )
    volumeDown.keyEquivalentModifierMask = [.command]
    volumeDown.tag = 0
    volumeDown.target = appDelegate
    menu.addItem(volumeDown)

    item.submenu = menu
    return item
  }

  // MARK: - View

  private static func viewMenu() -> NSMenuItem {
    let item = NSMenuItem()
    let menu = NSMenu(title: L10n.tr("View"))
    menu.addItem(
      withTitle: L10n.tr("Show Main Window"),
      action: #selector(AppDelegate.showMainWindow(_:)),
      keyEquivalent: "1"
    ).target = appDelegate

    let nowPlaying = NSMenuItem(
      title: L10n.tr("Now Playing"),
      action: #selector(AppDelegate.showNowPlaying(_:)),
      keyEquivalent: "p"
    )
    nowPlaying.keyEquivalentModifierMask = [.command, .shift]
    nowPlaying.target = appDelegate
    menu.addItem(nowPlaying)

    let queue = NSMenuItem(
      title: L10n.tr("Queue"),
      action: #selector(AppDelegate.showQueue(_:)),
      keyEquivalent: "q"
    )
    queue.keyEquivalentModifierMask = [.command, .shift]
    queue.target = appDelegate
    menu.addItem(queue)

    let search = NSMenuItem(
      title: L10n.tr("Search"),
      action: #selector(AppDelegate.focusSearch(_:)),
      keyEquivalent: "f"
    )
    search.target = appDelegate
    menu.addItem(search)
    menu.addItem(.separator())
    let fullScreen = NSMenuItem(
      title: L10n.tr("Enter Full Screen"),
      action: #selector(NSWindow.toggleFullScreen(_:)),
      keyEquivalent: "f"
    )
    fullScreen.keyEquivalentModifierMask = [.command, .control]
    menu.addItem(fullScreen)
    item.submenu = menu
    return item
  }

  // MARK: - Window

  private static func windowMenu(appName: String) -> NSMenuItem {
    let item = NSMenuItem()
    let menu = NSMenu(title: L10n.tr("Window"))
    menu.addItem(withTitle: L10n.tr("Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
    menu.addItem(withTitle: L10n.tr("Zoom"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
    menu.addItem(.separator())
    menu.addItem(withTitle: L10n.tr("Bring All to Front"), action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
    NSApp.windowsMenu = menu
    item.submenu = menu
    return item
  }

  // MARK: - Help

  private static func helpMenu() -> NSMenuItem {
    let item = NSMenuItem()
    let menu = NSMenu(title: L10n.tr("Help"))
    menu.addItem(
      withTitle: L10n.tr("Report an issue on GitHub"),
      action: #selector(NSWorkspace.open(_:)),
      keyEquivalent: ""
    ).target = nil
    NSApp.helpMenu = menu
    item.submenu = menu
    return item
  }
}
