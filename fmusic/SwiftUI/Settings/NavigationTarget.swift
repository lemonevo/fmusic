//
//  NavigationTarget.swift
//  fmusic
//
//  Created by David Klopp on 15.08.24.
//  Copyright (c) 2024 Maximilian Bauer. All rights reserved.
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
import fmusicKit
import SwiftUI

@MainActor
enum NavigationTarget: String, CaseIterable, @MainActor Identifiable {
  case general
  case account
  case player
  case audio
  case lyrics
  case displayAndInteraction
  case storage
  case library
  case support
  case advanced
  // sub-pages (pushed from a parent page, not shown directly in the sidebar)
  case equalizer
  case swipe
  case artwork
  case license
  case xcallback
  case eventLog
  #if DEBUG
    case developer = "developer"
  #endif

  var id: String { rawValue }

  /// Sidebar entries. The remaining targets are pushed from these pages so the sidebar
  /// stays short (e.g. Equalizer lives inside Playback).
  static var sidebarItems: [NavigationTarget] {
    [
      .general,
      .account,
      .player,
      .audio,
      .lyrics,
      .displayAndInteraction,
      .storage,
      .library,
    ]
  }

  /// Builds the page as a concrete view instead of `AnyView` so SwiftUI keeps
  /// the static type and can diff/update it much more cheaply.
  @MainActor
  @ViewBuilder
  func view() -> some View {
    switch self {
    case .general: SettingsView()
    case .displayAndInteraction: DisplaySettingsView()
    case .account: AccountSettingsView()
    case .library: LibrarySettingsView()
    case .player: PlayerSettingsView()
    case .audio: AudioSettingsView()
    case .lyrics: LyricsSettingsView()
    case .storage: StorageSettingsView()
    case .advanced: AdvancedSettingsView()
    case .equalizer: EqualizerSettingsView()
    case .swipe: SwipeSettingsView()
    case .artwork: ArtworkSettingsView()
    case .support: SupportSettingsView()
    case .license: LicenseSettingsView()
    case .xcallback: XCallbackURLsSetttingsView()
    case .eventLog: EventLogSettingsView()
    #if DEBUG
      case .developer: DeveloperView()
    #endif
    }
  }

  var displayName: String {
    switch self {
    case .general: L10n.tr("General")
    case .displayAndInteraction: L10n.tr("Display")
    case .account: L10n.tr("Account")
    case .library: L10n.tr("Library")
    case .swipe: L10n.tr("Swipe Actions")
    case .artwork: L10n.tr("Artwork & Cache")
    case .support: L10n.tr("Support & About")
    case .license: L10n.tr("Third-Party Licenses")
    case .equalizer: L10n.tr("Equalizer")
    case .player: L10n.tr("Playback")
    case .audio: L10n.tr("Audio & Effects")
    case .lyrics: L10n.tr("Lyrics")
    case .storage: L10n.tr("Storage & Artwork")
    case .advanced: L10n.tr("Advanced")
    case .eventLog: L10n.tr("Event Log")
    case .xcallback: L10n.tr("X-Callback URL")
    #if DEBUG
      case .developer: L10n.tr("Developer Tools")
    #endif
    }
  }

  /// Filled variants sized like the main sidebar rows: SF Symbol 16 pt regular in a 22 pt box.
  @MainActor
  var icon: UIImage {
    let configuration = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
    let image = UIImage(systemName: systemImage, withConfiguration: configuration)
      ?? UIImage(
        systemName: systemImage.replacingOccurrences(of: ".fill", with: ""),
        withConfiguration: configuration
      )
    return (image ?? UIImage()).withRenderingMode(.alwaysTemplate)
  }

  var systemImage: String {
    switch self {
    case .general: "gearshape.fill"
    case .displayAndInteraction: "tv.fill"
    case .account: "person.fill"
    case .library: "music.note.house.fill"
    case .player: "play.circle.fill"
    case .audio: "waveform"
    case .lyrics: "quote.bubble.fill"
    case .storage: "internaldrive.fill"
    case .advanced: "slider.horizontal.3"
    case .eventLog: "list.bullet.rectangle"
    case .equalizer: "chart.bar.fill"
    case .swipe: "arrow.right.circle.fill"
    case .artwork: "photo.fill"
    case .support: "info.circle.fill"
    case .license: "doc.fill"
    case .xcallback: "arrowshape.turn.up.backward.circle.fill"
    #if DEBUG
      case .developer: "hammer.circle.fill"
    #endif
    }
  }
}
