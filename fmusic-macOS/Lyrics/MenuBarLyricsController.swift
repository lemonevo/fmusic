//
//  MenuBarLyricsController.swift
//  fmusic-macOS
//
//  Shows the currently sung lyric line in the macOS menu bar, ported from the
//  Catalyst app's runtime-bridged implementation (NSStatusBar used to be reached
//  through the Objective-C runtime because Catalyst does not expose it).
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

// MARK: - MenuBarLyricsController

@MainActor
final class MenuBarLyricsController: NSObject, NSMenuItemValidation {
  /// Apple Music shortens a long line instead of letting the status item grow
  /// across the menu bar; 48 characters is what the Catalyst overlay used.
  private static let maximumTitleLength = 48

  private let statusItem: NSStatusItem
  private var currentText = ""
  private var playPauseItem: NSMenuItem?

  var onOpenApp: (() -> Void)?

  private var player: PlayerFacade { FmusicKit.shared.player }

  override init() {
    statusItem = NSStatusBar.system.statusItem(
      withLength: NSStatusItem.variableLength
    )
    super.init()

    if let button = statusItem.button {
      button.title = "fmusic"
      button.toolTip = "fmusic"
      button.lineBreakMode = .byTruncatingTail
    }
    configureMenu()
  }

  func remove() {
    NSStatusBar.system.removeStatusItem(statusItem)
  }

  // MARK: - Title

  func update(title: String) {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let display = trimmed.isEmpty ? "fmusic" : trimmed
    guard display != currentText else { return }
    currentText = display
    let text = Self.truncated(display)
    if let button = statusItem.button {
      button.title = text
      // The tooltip keeps the untruncated line available on hover.
      button.toolTip = display
    }
  }

  /// Apple Music keeps a single menu-bar line and drops the tail of a long lyric.
  private static func truncated(_ text: String) -> String {
    guard text.count > maximumTitleLength else { return text }
    return String(text.prefix(maximumTitleLength - 1)) + "…"
  }

  // MARK: - Menu

  private func configureMenu() {
    let menu = NSMenu()
    menu.addItem(menuItem(L10n.tr("Previous Track"), #selector(previousPressed)))
    let playPause = menuItem(L10n.tr("Play"), #selector(togglePlayPausePressed))
    playPauseItem = playPause
    menu.addItem(playPause)
    menu.addItem(menuItem(L10n.tr("Next Track"), #selector(nextPressed)))
    menu.addItem(.separator())
    menu.addItem(menuItem(L10n.tr("Shuffle"), #selector(toggleShufflePressed)))
    menu.addItem(menuItem(L10n.tr("Repeat"), #selector(cycleRepeatPressed)))
    menu.addItem(.separator())
    menu.addItem(menuItem(L10n.tr("Show Main Window"), #selector(openAppPressed)))
    statusItem.menu = menu
  }

  private func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    return item
  }

  // MARK: - Menu validation

  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    switch menuItem.action {
    case #selector(togglePlayPausePressed):
      menuItem.title = player.isPlaying ? L10n.tr("Pause") : L10n.tr("Play")
      return player.currentlyPlaying != nil
    case #selector(previousPressed):
      return player.currentlyPlaying != nil
    case #selector(nextPressed):
      return player.currentlyPlaying != nil
    case #selector(toggleShufflePressed):
      menuItem.state = player.isShuffle ? .on : .off
      return true
    case #selector(cycleRepeatPressed):
      switch player.repeatMode {
      case .off: menuItem.state = .off
      case .all: menuItem.state = .on
      case .single: menuItem.state = .mixed
      }
      return true
    default:
      return true
    }
  }

  // MARK: - Actions

  @objc
  private func previousPressed() {
    player.playPreviousOrReplay()
  }

  @objc
  private func togglePlayPausePressed() {
    player.togglePlayPause()
  }

  @objc
  private func nextPressed() {
    player.playNext()
  }

  @objc
  private func toggleShufflePressed() {
    player.toggleShuffle()
  }

  @objc
  private func cycleRepeatPressed() {
    player.setRepeatMode(player.repeatMode.nextMode)
  }

  @objc
  private func openAppPressed() {
    onOpenApp?()
  }
}
