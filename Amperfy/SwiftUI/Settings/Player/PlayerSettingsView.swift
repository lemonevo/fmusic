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
  @EnvironmentObject
  private var settings: Settings

  private var isServerBackedAccount: Bool {
    appDelegate.storage.settings.accounts.getSetting(settings.activeAccountInfo).read
      .loginCredentials?.backendApi.asServerApiType != nil
  }

  private func updateBitrate(
    wifi: StreamingMaxBitratePreference? = nil,
    cellular: StreamingMaxBitratePreference? = nil
  ) {
    if let wifi = wifi {
      settings.streamingMaxBitrateWifiPreference = wifi
    }
    if let cellular = cellular {
      settings.streamingMaxBitrateCellularPreference = cellular
    }
    appDelegate.player.setStreamingMaxBitrates(
      to: StreamingMaxBitrates(
        wifi: settings.streamingMaxBitrateWifiPreference,
        cellular: settings.streamingMaxBitrateCellularPreference
      )
    )
  }

  private func updateFormatCell(_ format: StreamingFormatPreference) {
    settings.streamingFormatCellularPreference = format

    appDelegate.player.setStreamingTranscodings(to: StreamingTranscodings(
      wifi: settings.streamingFormatWifiPreference,
      cellular: settings.streamingFormatCellularPreference
    ))
  }

  private func updateFormatWifi(_ format: StreamingFormatPreference) {
    settings.streamingFormatWifiPreference = format

    appDelegate.player.setStreamingTranscodings(to: StreamingTranscodings(
      wifi: settings.streamingFormatWifiPreference,
      cellular: settings.streamingFormatCellularPreference
    ))
  }

  private func updateCacheFormat(_ format: CacheTranscodingFormatPreference) {
    settings.cacheTranscodingFormatPreference = format
  }

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

        // General Settings
        SettingsSection(
          content: {
            SettingsCheckBoxRow(
              title: L10n.tr("Auto-cache played tracks and download upcoming ones"),
              isOn: $settings.isPlayerAutoCachePlayedItems
            )
          },
          footer: L10n.tr(
            "Played tracks (songs and podcast episodes) are cached automatically. The next %d tracks are downloaded in advance.",
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

        // Streaming and transcoding only apply to server backed accounts
        if isServerBackedAccount {
          SettingsSection(
            content: {
              SettingsRow(title: L10n.tr("Cellular Streaming\nFormat (Transcoding)")) {
                Menu(settings.streamingFormatCellularPreference.description) {
                  ForEach(StreamingFormatPreference.allCases, id: \.self) { format in
                    Button(format.description) {
                      updateFormatCell(format)
                    }
                  }
                }
              }
            },
            footer: L10n.tr("Select a transcoding format for streaming while using Cellular. Transcoding is recommended for better compatibility.")
          )

          SettingsSection(
            content: {
              SettingsRow(title: L10n.tr("Cellular Streaming\nBitrate Limit")) {
                Menu(settings.streamingMaxBitrateCellularPreference.description) {
                  ForEach(StreamingMaxBitratePreference.allCases, id: \.self) { bitrate in
                    Button(bitrate.description) {
                      updateBitrate(cellular: bitrate)
                    }
                  }
                }
              }
            },
            footer: L10n.tr("Set the maximum streaming bitrate for Cellular.")
          )

          SettingsSection(
            content: {
              SettingsRow(title: L10n.tr("WiFi Streaming\nFormat (Transcoding)")) {
                Menu(settings.streamingFormatWifiPreference.description) {
                  ForEach(StreamingFormatPreference.allCases, id: \.self) { format in
                    Button(format.description) {
                      updateFormatWifi(format)
                    }
                  }
                }
              }
            },
            footer: L10n.tr("Select a transcoding format for streaming while on WiFi. Transcoding is recommended for better compatibility.")
          )
          // Streaming Bitrate Settings
          SettingsSection(
            content: {
              SettingsRow(title: L10n.tr("WiFi Streaming\nBitrate Limit")) {
                Menu(settings.streamingMaxBitrateWifiPreference.description) {
                  ForEach(StreamingMaxBitratePreference.allCases, id: \.self) { bitrate in
                    Button(bitrate.description) {
                      updateBitrate(wifi: bitrate)
                    }
                  }
                }
              }
            },
            footer: L10n.tr("Set the maximum streaming bitrate for WiFi.")
          )

          // Cache Format Settings
          SettingsSection(content: {
            SettingsRow(title: L10n.tr("Cache\nFormat (Transcoding)")) {
              Menu(settings.cacheTranscodingFormatPreference.description) {
                ForEach(CacheTranscodingFormatPreference.allCases, id: \.self) { format in
                  Button(format.description) {
                    updateCacheFormat(format)
                  }
                }
              }
            }
          }, footer: L10n.tr(
            "Select a transcoding format for cached songs. Changes will not apply to already downloaded songs; clear cache and redownload if needed."
          ))
        }
      }
    }
    .navigationTitle(L10n.tr("Player & Stream"))
    .navigationBarTitleDisplayMode(.inline)
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
