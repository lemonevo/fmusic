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

    let addAccount = NSMenuItem(
      title: L10n.tr("Add Account"),
      action: #selector(AppDelegate.addAccount(_:)),
      keyEquivalent: ""
    )
    addAccount.target = appDelegate
    menu.addItem(addAccount)
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

    let importM3U = NSMenuItem(
      title: L10n.tr("Import M3U Playlist"),
      action: #selector(M3UController.importM3UPlaylist(_:)),
      keyEquivalent: "i"
    )
    importM3U.keyEquivalentModifierMask = [.command, .shift]
    importM3U.target = M3UController.shared
    menu.addItem(importM3U)

    let exportM3U = NSMenuItem(
      title: L10n.tr("Export M3U"),
      action: #selector(M3UController.exportM3U(_:)),
      keyEquivalent: "e"
    )
    exportM3U.keyEquivalentModifierMask = [.command, .shift]
    exportM3U.target = M3UController.shared
    menu.addItem(exportM3U)

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
    // The delegate updates the sleep timer submenu title (remaining time) right
    // before the Playback menu is displayed.
    menu.delegate = sleepTimerMenuController

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

    menu.addItem(sleepTimerMenuItem())
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

    let lyrics = NSMenuItem(
      title: L10n.tr("Show Lyrics"),
      action: #selector(AppDelegate.toggleDesktopLyrics(_:)),
      keyEquivalent: "l"
    )
    lyrics.keyEquivalentModifierMask = [.command, .shift]
    lyrics.target = appDelegate
    menu.addItem(lyrics)


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

    let sidebar = NSMenuItem(
      title: L10n.tr("Show Sidebar"),
      action: #selector(AppDelegate.toggleSidebar(_:)),
      keyEquivalent: "s"
    )
    sidebar.keyEquivalentModifierMask = [.command, .shift]
    sidebar.target = appDelegate
    menu.addItem(sidebar)
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

    let miniPlayer = NSMenuItem(
      title: L10n.tr("Mini Player"),
      action: #selector(AppDelegate.showMiniPlayer(_:)),
      keyEquivalent: "m"
    )
    miniPlayer.keyEquivalentModifierMask = [.command, .shift]
    miniPlayer.target = appDelegate
    menu.addItem(miniPlayer)
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
    let xcallbackDocs = NSMenuItem(
      title: L10n.tr("X-Callback-URL Documentation"),
      action: #selector(AppDelegate.showXCallbackDocumentation(_:)),
      keyEquivalent: ""
    )
    xcallbackDocs.target = appDelegate
    menu.addItem(xcallbackDocs)
    menu.addItem(.separator())

    menu.addItem(
      withTitle: L10n.tr("Report an issue on GitHub"),
      action: #selector(NSWorkspace.open(_:)),
      keyEquivalent: ""
    ).target = nil
    NSApp.helpMenu = menu
    item.submenu = menu
    return item
  }

  // MARK: - Sleep timer

  /// One instance owns the dynamic sleep timer menu (it is the `NSMenuDelegate` of both
  /// the Playback menu and the sleep timer submenu, and refreshes their titles/check
  /// marks from `AppDelegate` right before they are displayed).
  static let sleepTimerMenuController = SleepTimerMenuController()

  /// Refreshes the sleep timer menu title/check marks immediately. Called by
  /// `AppDelegate` whenever the timer state changes.
  static func refreshSleepTimerMenu() {
    sleepTimerMenuController.refresh()
  }

  private static func sleepTimerMenuItem() -> NSMenuItem {
    let item = NSMenuItem(title: L10n.tr("Sleep Timer"), action: nil, keyEquivalent: "")
    let menu = NSMenu(title: L10n.tr("Sleep Timer"))
    menu.autoenablesItems = false

    let endOfSong = NSMenuItem(
      title: L10n.tr("End of Song"),
      action: #selector(AppDelegate.setSleepTimerToEndOfSong(_:)),
      keyEquivalent: ""
    )
    endOfSong.target = appDelegate
    endOfSong.tag = SleepTimerMenuController.endOfSongTag
    menu.addItem(endOfSong)

    for minutes in SleepTimerMenuController.minuteOptions {
      let timerItem = NSMenuItem(
        title: SleepTimerMenuController.title(forMinutes: minutes),
        action: #selector(AppDelegate.activateSleepTimer(_:)),
        keyEquivalent: ""
      )
      timerItem.target = appDelegate
      timerItem.tag = minutes
      menu.addItem(timerItem)
    }

    menu.addItem(.separator())

    let off = NSMenuItem(
      title: L10n.tr("Off"),
      action: #selector(AppDelegate.turnOffSleepTimer(_:)),
      keyEquivalent: ""
    )
    off.target = appDelegate
    off.tag = SleepTimerMenuController.offTag
    menu.addItem(off)

    menu.delegate = sleepTimerMenuController
    item.submenu = menu
    sleepTimerMenuController.attach(item: item, menu: menu)
    // The dynamic title/check marks are filled in by `menuNeedsUpdate` when the menu
    // opens, i.e. after the app bootstrap created the shared player.
    return item
  }
}

// MARK: - SleepTimerMenuController

/// Keeps the "睡眠定时器" submenu in sync with the shared player state:
///
/// * the submenu title shows the time remaining while a countdown runs,
/// * the items behave like a radio group (End of Song / 5…120 minutes / Off),
/// * "Off" shows the pause time when a countdown is active, like the Catalyst app.
@MainActor
final class SleepTimerMenuController: NSObject, NSMenuDelegate {
  static let endOfSongTag = -1
  static let offTag = -2
  static let minuteOptions = [5, 10, 15, 30, 45, 60, 120]

  private weak var sleepTimerItem: NSMenuItem?
  private weak var sleepTimerMenu: NSMenu?

  private var appDelegate: AppDelegate? { AppDelegate.sharedAppDelegate }
  private var player: PlayerFacade { FmusicKit.shared.player }

  func attach(item: NSMenuItem, menu: NSMenu) {
    sleepTimerItem = item
    sleepTimerMenu = menu
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    refresh()
  }

  func refresh() {
    guard let appDelegate, let sleepTimerMenu, let sleepTimerItem else { return }
    let fireDate = appDelegate.sleepTimerFireDate
    let isEndOfSongActive = player.isShouldPauseAfterFinishedPlaying

    if let fireDate {
      let remainingSeconds = max(0, Int(fireDate.timeIntervalSinceNow.rounded(.up)))
      sleepTimerItem.title = L10n.tr("Sleep Timer") + " · " + L10n.tr(
        "Remaining: %@",
        ClockTime(timeInSeconds: remainingSeconds).asShortString()
      )
    } else if isEndOfSongActive {
      sleepTimerItem.title = L10n.tr("Sleep Timer") + " · " + L10n.tr("End of Song")
    } else {
      sleepTimerItem.title = L10n.tr("Sleep Timer")
    }

    for item in sleepTimerMenu.items {
      switch item.tag {
      case Self.endOfSongTag:
        item.state = isEndOfSongActive ? .on : .off
      case Self.offTag:
        if let fireDate {
          item.title = L10n.tr("Turn Off (Pause at: %@)", fireDate.asShortHrMinString)
        } else {
          item.title = L10n.tr("Off")
        }
        item.state = (fireDate == nil && !isEndOfSongActive) ? .on : .off
      default:
        item.state = (
          fireDate != nil &&
            appDelegate.sleepTimerMinutes == item.tag
        ) ? .on : .off
      }
    }
  }

  static func title(forMinutes minutes: Int) -> String {
    switch minutes {
    case 5: return L10n.tr("5 Minutes")
    case 10: return L10n.tr("10 Minutes")
    case 15: return L10n.tr("15 Minutes")
    case 30: return L10n.tr("30 Minutes")
    case 45: return L10n.tr("45 Minutes")
    case 60: return L10n.tr("1 Hour")
    case 120: return L10n.tr("2 Hours")
    default: return "\(minutes) " + L10n.tr("Minutes")
    }
  }
}
