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
  case display
  case playback
  case account
  case about

  var title: String {
    switch self {
    case .general: return L10n.tr("General")
    case .display: return L10n.tr("Display")
    case .playback: return L10n.tr("Playback")
    case .account: return L10n.tr("Account")
    case .about: return L10n.tr("About")
    }
  }

  var symbolName: String {
    switch self {
    case .general: return "gearshape"
    case .display: return "display"
    case .playback: return "play.circle"
    case .account: return "person.crop.circle"
    case .about: return "info.circle"
    }
  }

  /// Creates the page controller for this entry (views are loaded lazily on selection).
  func makeViewController() -> NSViewController {
    switch self {
    case .general: return GeneralSettingsViewController()
    case .display: return DisplaySettingsViewController()
    case .playback: return PlaybackSettingsViewController()
    case .account: return AccountSettingsViewController()
    case .about: return AboutSettingsViewController()
    }
  }
}
