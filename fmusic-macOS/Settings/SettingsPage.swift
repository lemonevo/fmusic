//
//  SettingsPage.swift
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

/// Pages of the settings window sidebar.
@MainActor
enum SettingsPage: Int, CaseIterable, Sendable {
  case general
  case lyrics
  case displayInteraction
  case playback
  case equalizer
  case library
  case storage
  case account
  case support
  case developer
  case about

  var title: String {
    switch self {
    case .general: return L10n.tr("General")
    case .lyrics: return L10n.tr("Lyrics")
    case .displayInteraction: return L10n.tr("Display")
    case .playback: return L10n.tr("Playback")
    case .equalizer: return L10n.tr("Audio & Effects")
    case .library: return L10n.tr("Library")
    case .storage: return L10n.tr("Storage & Artwork")
    case .account: return L10n.tr("Account")
    case .support: return L10n.tr("Support")
    case .developer: return L10n.tr("Developer")
    case .about: return L10n.tr("About")
    }
  }

  var symbolName: String {
    switch self {
    case .general: return "gearshape"
    case .lyrics: return "quote.bubble"
    case .displayInteraction: return "display"
    case .playback: return "play.circle"
    case .equalizer: return "chart.bar"
    case .library: return "music.note.house"
    case .storage: return "internaldrive"
    case .account: return "person"
    case .support: return "info.circle"
    case .developer: return "hammer"
    case .about: return "doc"
    }
  }

  /// Creates the page controller for this entry (views are loaded lazily on selection).
  func makeViewController() -> NSViewController {
    switch self {
    case .general: return GeneralSettingsViewController()
    case .lyrics: return LyricsSettingsViewController()
    case .displayInteraction: return DisplaySettingsViewController()
    case .playback: return PlaybackSettingsViewController()
    case .equalizer: return EqualizerSettingsViewController()
    case .library: return LibrarySettingsViewController()
    case .storage: return StorageSettingsViewController()
    case .account: return AccountSettingsViewController()
    case .support: return SupportSettingsViewController()
    case .developer: return DeveloperSettingsViewController()
    case .about: return AboutSettingsViewController()
    }
  }
}
