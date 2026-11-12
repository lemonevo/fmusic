//
//  SettingsView.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 14.09.22.
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

// MARK: - SettingsView

struct SettingsView: View {
  @EnvironmentObject
  private var settings: Settings

  @State
  private var isShowingLanguageAlert = false

  private var languageName: String {
    switch settings.appLanguage {
    case .system: L10n.tr("Match System")
    case .english: "English"
    case .simplifiedChinese: L10n.tr("Simplified Chinese")
    }
  }

  private func setAppLanguage(_ language: AppLanguage) {
    guard settings.appLanguage != language else { return }
    settings.appLanguage = language
    isShowingLanguageAlert = true
  }

  func screenLockPreventionOffPressed() {
    settings.screenLockPreventionPreference = .never
    UIDevice.current.isBatteryMonitoringEnabled = false
    appDelegate.configureLockScreenPrevention()
  }

  func screenLockPreventionOnPressed() {
    settings.screenLockPreventionPreference = .always
    UIDevice.current.isBatteryMonitoringEnabled = false
    appDelegate.configureLockScreenPrevention()
  }

  func screenLockPreventionChargingPressed() {
    settings.screenLockPreventionPreference = .onlyIfCharging
    UIDevice.current.isBatteryMonitoringEnabled = true
    appDelegate.configureLockScreenPrevention()
  }

  func navigationLink(_ item: NavigationTarget) -> some View {
    NavigationLink(value: item) {
      Text(item.displayName)
    }
  }

  var body: some View {
    let list =
      SettingsList {
        SettingsSection(
          content: {
            SettingsRow(title: L10n.tr("Language")) {
              Menu(languageName) {
                Button(L10n.tr("Match System")) { setAppLanguage(.system) }
                Button(L10n.tr("Simplified Chinese")) { setAppLanguage(.simplifiedChinese) }
                Button("English") { setAppLanguage(.english) }
              }
            }
          },
          footer: L10n.tr("Language changes take effect after restarting Amperfy.")
        )

        SettingsSection(
          content: {
            SettingsCheckBoxRow(
              title: L10n.tr("Offline Mode"),
              isOn: $settings.isOfflineMode
            )
          },
          footer:
          L10n.tr(
            "Songs and artworks won’t download offline. Searches are limited to the device, and playlists won’t sync with the server."
          )
        )

        SettingsSection {
          SettingsRow(title: L10n.tr("Prevent Screen Lock")) {
            Menu(settings.screenLockPreventionPreference.description) {
              Button(
                ScreenLockPreventionPreference.never.description,
                action: screenLockPreventionOffPressed
              )
              Button(
                ScreenLockPreventionPreference.always.description,
                action: screenLockPreventionOnPressed
              )
              Button(
                ScreenLockPreventionPreference.onlyIfCharging.description,
                action: screenLockPreventionChargingPressed
              )
            }
          }
        }

        #if !targetEnvironment(macCatalyst) // ok
          SettingsSection {
            ForEach(NavigationTarget.sidebarItems.filter { $0 != .general }, id: \.self) {
              navigationLink($0)
            }
          }
        #endif
      }
      .alert(isPresented: $isShowingLanguageAlert) {
        Alert(
          title: Text(L10n.tr("Language")),
          message: Text(L10n.tr("Restart Amperfy to apply the new language.")),
          dismissButton: .default(Text(L10n.tr("OK")))
        )
      }

    #if targetEnvironment(macCatalyst) // ok
      ZStack {
        list
      }
      .navigationTitle(L10n.tr("General"))
      .navigationBarTitleDisplayMode(.inline)
    #else
      NavigationStack {
        list
          .navigationTitle(L10n.tr("Settings"))
          // All pushes in this stack must be value based. Mixing view based links
          // (NavigationLink(destination:)) with the value based links of the sub pages
          // results in a navigation loop.
          .navigationDestination(for: NavigationTarget.self) { item in
            AnyView(item.view())
          }
      }
    #endif
  }
}

// MARK: - SettingsView_Previews

struct SettingsView_Previews: PreviewProvider {
  static var previews: some View {
    SettingsView()
  }
}
