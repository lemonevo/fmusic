//
//  DisplaySettingsView.swift
//  fmusic
//
//  Created by Maximilian Bauer on 30.12.23.
//  Copyright (c) 2023 Maximilian Bauer. All rights reserved.
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

// MARK: - DisplaySettingsView

struct DisplaySettingsView: View {
  enum Destination: Hashable {
    case swipe
  }

  @EnvironmentObject
  private var settings: Settings

  func setAppearanceMode(style: UIUserInterfaceStyle) {
    settings.appearanceMode = style
    appDelegate.setAppAppearanceMode(style: style)
  }

  var body: some View {
    ZStack {
      SettingsList {
        SettingsSection {
          SettingsRow(title: L10n.tr("Appearance")) {
            Menu(
              settings.appearanceMode == .unspecified
                ? L10n.tr("System")
                : (settings.appearanceMode == .light ? L10n.tr("Light") : L10n.tr("Dark"))
            ) {
              Button(L10n.tr("System")) {
                setAppearanceMode(style: .unspecified)
              }
              Button(L10n.tr("Light")) {
                setAppearanceMode(style: .light)
              }
              Button(L10n.tr("Dark")) {
                setAppearanceMode(style: .dark)
              }
            }
          }
        }

        // Mac Catalyst compiles alternate icons but doesn't support switching them
        // in our tests, so only show the picker when the system allows it.
        if UIApplication.shared.supportsAlternateIcons {
          AppIconSettingsSection()
        }

        #if !targetEnvironment(macCatalyst)
          SettingsSection(
            content: {
              SettingsCheckBoxRow(
                title: L10n.tr("Haptic Feedback"),
                isOn: $settings.isHapticsEnabled
              )
            },
            footer:
            L10n.tr(
              "Certain interactions provide haptic feedback. Long pressing to display the details menu will always trigger haptic feedback."
            )
          )
        #endif

        TextSizeSettingsSection()

        #if targetEnvironment(macCatalyst)
          SettingsSection(
            content: {
              SettingsCheckBoxRow(
                title: L10n.tr("Mini Player Always on Top"),
                isOn: $settings.isMiniPlayerAlwaysOnTop
              )
            },
            footer:
            L10n.tr("Keep the mini player window floating above all other windows.")
          )

          SettingsSection(
            content: {
              SettingsCheckBoxRow(
                title: L10n.tr("Desktop Lyrics"),
                isOn: $settings.isDesktopLyricsEnabled
              )
            },
            footer:
            L10n.tr("Show the current lyric line in a floating window above all other windows. Drag it to move it.")
          )

          if settings.isDesktopLyricsEnabled {
            SettingsSection(
              content: {
                SettingsRow(title: L10n.tr("Desktop Lyrics Font Size")) {
                  Picker("", selection: $settings.desktopLyricsFontSize) {
                    ForEach(DesktopLyricsFontSize.allCases, id: \.self) { size in
                      Text(size.description).tag(size)
                    }
                  }
                  .pickerStyle(.menu)
                  .labelsHidden()
                }
                SettingsCheckBoxRow(
                  title: L10n.tr("Lock Desktop Lyrics"),
                  isOn: $settings.isDesktopLyricsLocked
                )
              },
              footer:
              L10n.tr("Lock the desktop lyrics in place and let mouse clicks pass through.")
            )
          }

          SettingsSection(
            content: {
              SettingsCheckBoxRow(
                title: L10n.tr("Menu Bar Lyrics"),
                isOn: $settings.isMenuBarLyricsEnabled
              )
            },
            footer:
            L10n.tr("Show the current lyric line in the menu bar. When the menu bar is full, macOS keeps the item in the overflow area.")
          )
        #endif

        SettingsSection(
          content: {
            SettingsCheckBoxRow(
              title: L10n.tr("Detailed Information"),
              isOn: $settings.isShowDetailedInfo
            )
          },
          footer:
          L10n.tr(
            "Display detailed information (bitrate, ID) and button \"Copy ID to Clipboard\"."
          )
        )

        SettingsSection(
          content: {
            SettingsCheckBoxRow(
              title: L10n.tr("Song Duration"),
              isOn: $settings.isShowSongDuration
            )
          },
          footer:
          L10n.tr("Display song duration in table rows.")
        )

        SettingsSection(
          content: {
            SettingsCheckBoxRow(
              title: L10n.tr("Album Duration"),
              isOn: $settings.isShowAlbumDuration
            )
          },
          footer:
          L10n.tr("Display album duration in table rows.")
        )

        SettingsSection(
          content: {
            SettingsCheckBoxRow(
              title: L10n.tr("Artist Duration"),
              isOn: $settings.isShowArtistDuration
            )
          },
          footer:
          L10n.tr("Display artist duration in table rows.")
        )

        SettingsSection(
          content: {
            SettingsCheckBoxRow(
              title: L10n.tr("Show Star Rating"),
              isOn: $settings.isShowRating
            )
          },
          footer:
          L10n.tr("Display star rating in song cells and the currently playing view.")
        )

        SettingsSection {
          NavigationLink(value: Destination.swipe) {
            Text(L10n.tr("Swipe Actions"))
          }
        }
      }
    }
    .navigationTitle(L10n.tr("Display"))
    .navigationBarTitleDisplayMode(.inline)
    .navigationDestination(for: Destination.self) { destination in
      switch destination {
      case .swipe: SwipeSettingsView()
      }
    }
  }
}

// MARK: - DisplaySettingsView_Previews

struct DisplaySettingsView_Previews: PreviewProvider {
  @State
  static var settings = Settings()

  static var previews: some View {
    DisplaySettingsView().environmentObject(settings)
  }
}
