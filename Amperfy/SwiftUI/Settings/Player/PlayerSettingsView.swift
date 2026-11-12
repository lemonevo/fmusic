//
//  PlayerSettingsView.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 15.09.22.
//  Copyright (c) 2022 Maximilian Bauer. All rights reserved.
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

import AmperfyKit
import SwiftUI

// MARK: - PlayerSettingsView

struct PlayerSettingsView: View {
  enum Destination: Hashable {
    case equalizer
  }

  @EnvironmentObject
  private var settings: Settings

  var body: some View {
    ZStack {
      SettingsList {
        // ReplayGain Settings
        SettingsSection(
          content: {
            SettingsCheckBoxRow(
              title: L10n.tr("Enable ReplayGain"),
              isOn: Binding(
                get: { settings.isReplayGainEnabled },
                set: { isEnabled in
                  settings.isReplayGainEnabled = isEnabled
                }
              )
            )
          },
          footer: L10n.tr("Automatically normalize track volume based on replay gain information for consistent loudness.")
        )

        // Crossfade
        SettingsSection(
          content: {
            SettingsRow(title: L10n.tr("Crossfade")) {
              Picker("", selection: $settings.crossfadeSeconds) {
                Text(L10n.tr("Off")).tag(0)
                Text(L10n.tr("%d seconds", 3)).tag(3)
                Text(L10n.tr("%d seconds", 5)).tag(5)
                Text(L10n.tr("%d seconds", 8)).tag(8)
              }
              .pickerStyle(.menu)
              .labelsHidden()
            }
          },
          footer: L10n.tr("Crossfade Footer")
        )

        // General Settings
        SettingsSection(
          content: {
            SettingsCheckBoxRow(
              title: L10n.tr("Auto-cache played tracks and download upcoming ones"),
              isOn: $settings.isPlayerAutoCachePlayedItems
            )
          },
          footer: L10n.tr(
            "Played tracks (songs) are cached automatically. The next %d tracks are downloaded in advance.",
            PlayerDownloadPreparationHandler.preDownloadCount
          )
        )

        SettingsSection(
          content: {
            SettingsCheckBoxRow(
              title: L10n.tr("Song Playback Resume"),
              isOn: $settings.isPlayerSongPlaybackResumeEnabled
            )
          },
          footer: L10n.tr("Keeps track of song progress so playback continues from the previously saved position.")
        )

        SettingsSection(content: {
          SettingsCheckBoxRow(
            title: L10n.tr("Manual Playback"),
            isOn: $settings.isPlaybackStartOnlyOnPlay
          )
        }, footer: L10n.tr("Enable to start playback only when the Play button is pressed."))

        SettingsSection(
          content: {
            SettingsCheckBoxRow(
              title: L10n.tr("Autoplay After End"),
              isOn: $settings.isAutoplayEnabled
            )
          },
          footer: L10n.tr("When the queue ends, automatically continue playback using Instant Mix to find similar songs.")
        )

        SettingsSection(
          content: {
            SettingsCheckBoxRow(
              title: L10n.tr("Music Player Skip Buttons"),
              isOn: $settings.isShowMusicPlayerSkipButtons
            )
          },
          footer:
          L10n.tr(
            "Add skip forward and skip backward buttons to the music player, along with the previous/next buttons."
          )
        )

        if let activeAccountInfo = settings.activeAccountInfo,
           appDelegate.storage.settings.accounts.getSetting(activeAccountInfo)
           .read.loginCredentials != nil {
          SettingsSection(
            content: {
              SettingsCheckBoxRow(
                title: L10n.tr("Lyrics Smooth Scrolling"),
                isOn: $settings.isLyricsSmoothScrolling
              )
            },
            footer:
            L10n.tr(
              "Lyrics are smoothly scrolled to next line. Deactivating will result in jumping from line to line."
            )
          )
        }

        SettingsSection(
          content: {
            SettingsCheckBoxRow(
              title: L10n.tr("Disable Player Shuffle Button"),
              isOn: Binding<Bool>(
                get: { !settings.isPlayerShuffleButtonEnabled },
                set: {
                  settings.isPlayerShuffleButtonEnabled = !$0
                  UIMenuSystem.main.setNeedsRebuild()
                }
              )
            )
          },
          footer:
          L10n.tr("The player shuffle button is displayed but non-interactive.")
        )

        #if !targetEnvironment(macCatalyst)
          SettingsSection(
            content: {
              SettingsCheckBoxRow(
                title: L10n.tr("Collapse Toolbar Player"),
                isOn: $settings.isToolbarPlayerAutoCollapse
              )
            },
            footer:
            L10n.tr("Collapse the toolbar player into a compact view when scrolling")
          )
        #endif

        SettingsSection {
          NavigationLink(value: Destination.equalizer) {
            Text(L10n.tr("Equalizer"))
          }
        }
      }
    }
    .navigationTitle(L10n.tr("Playback"))
    .navigationBarTitleDisplayMode(.inline)
    .navigationDestination(for: Destination.self) { destination in
      switch destination {
      case .equalizer: EqualizerSettingsView()
      }
    }
    .onAppear {
      appDelegate.userStatistics.visited(.settingsPlayer)
    }
  }
}

// MARK: - PlayerSettingsView_Previews

struct PlayerSettingsView_Previews: PreviewProvider {
  @State
  static var settings = Settings()

  static var previews: some View {
    PlayerSettingsView().environmentObject(settings)
  }
}
