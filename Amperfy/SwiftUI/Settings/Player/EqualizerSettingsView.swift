//
//  EqualizerSettingsView.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 19.07.25.
//  Copyright (c) 2025 Maximilian Bauer. All rights reserved.
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

// MARK: - EqualizerSettingsView

struct EqualizerSettingsView: View {
  @EnvironmentObject
  private var settings: Settings

  @State
  private var eqSettingToEdit: EqualizerSetting?
  @State
  private var eqSettingNameSaved: String = ""
  @State
  private var eqSettingName: String = ""
  @State
  var eqSettingGains: [CGFloat] = EqualizerSetting.frequencies.map { _ in 0.0 }
  @State
  var sliderLabel: [String] = EqualizerSetting.frequencies.map {
    if $0 < 1000 {
      return "\(Int($0))"
    } else {
      return "\(Int($0 / 1000))k"
    }
  }

  @State
  var isShowDeleteAlert = false

  var body: some View {
    ZStack {
      SettingsList {
        SettingsSection(content: {
          SettingsCheckBoxRow(
            title: L10n.tr("Enable Equalizer"),
            isOn: Binding(
              get: { settings.isEqualizerEnabled },
              set: { isEnabled in
                settings.isEqualizerEnabled = isEnabled
              }
            )
          )

          if settings.isEqualizerEnabled {
            SettingsRow(title: L10n.tr("Active Equalizer")) {
              Menu(L10n.tr(settings.activeEqualizerSetting.description)) {
                Button(L10n.tr(EqualizerSetting.off.description)) {
                  settings.activeEqualizerSetting = EqualizerSetting.off
                }
                ForEach(settings.equalizerSettings, id: \.self) { eqSetting in
                  Button(L10n.tr(eqSetting.description)) {
                    settings.activeEqualizerSetting = eqSetting
                  }
                }
              }
            }
          }
        })

        SettingsSection(content: {
          SettingsRow(title: L10n.tr("Equalizer")) {
            Menu((eqSettingToEdit != nil) ? eqSettingNameSaved : L10n.tr("Select")) {
              ForEach(settings.equalizerSettings, id: \.self) { eqSetting in
                Button(L10n.tr(eqSetting.description)) {
                  eqSettingToEdit = eqSetting
                  eqSettingName = eqSetting.name
                  eqSettingNameSaved = eqSetting.name
                  eqSettingGains = eqSetting.gains.compactMap { CGFloat($0) }
                }
              }
              Button(L10n.tr("Create new Equalizer")) {
                let newEQ = EqualizerSetting(name: L10n.tr("My new Equalizer"))
                var curEqSetting = settings.equalizerSettings
                curEqSetting.append(newEQ)
                settings.equalizerSettings = curEqSetting
                eqSettingToEdit = newEQ
                eqSettingName = newEQ.name
                eqSettingNameSaved = newEQ.name
                eqSettingGains = newEQ.gains.compactMap { CGFloat($0) }
              }
            }
          }

          if eqSettingToEdit != nil {
            SettingsRow(title: L10n.tr("Name")) {
              TextField(L10n.tr("Equalizer Name"), text: $eqSettingName)
                .multilineTextAlignment(.trailing)
            }

            EqualizerView(
              sliderLabels: $sliderLabel,
              sliderValues: $eqSettingGains,
              sliderTintColor: Color(settings.themePreference.asColor),
              gradientColors: [Color(settings.themePreference.asColor), .clear]
            )

            SettingsButtonRow(title: L10n.tr("Save")) {
              guard var eqSettingToEdit else { return }
              var curEqSetting = settings.equalizerSettings
              guard let index = curEqSetting.firstIndex(of: eqSettingToEdit) else { return }
              eqSettingToEdit.name = eqSettingName
              eqSettingNameSaved = eqSettingName
              eqSettingToEdit.gains = eqSettingGains.compactMap { Float($0) }
              self.eqSettingToEdit = eqSettingToEdit
              curEqSetting[index] = eqSettingToEdit
              settings.equalizerSettings = curEqSetting

              if settings.activeEqualizerSetting == eqSettingToEdit {
                settings.activeEqualizerSetting = eqSettingToEdit
              }
            }
            SettingsButtonRow(title: L10n.tr("Delete"), actionType: .destructive) {
              isShowDeleteAlert = true
            }.alert(isPresented: $isShowDeleteAlert) {
              Alert(
                title: Text(L10n.tr("Delete Equalizer")),
                message: Text(L10n.tr("Are you sure to delete this equalizer?")),
                primaryButton: .destructive(Text(L10n.tr("Delete"))) {
                  guard let eqSettingToEdit else { return }
                  var curEqSetting = settings.equalizerSettings
                  guard let index = curEqSetting.firstIndex(of: eqSettingToEdit) else { return }
                  curEqSetting.remove(at: index)
                  settings.equalizerSettings = curEqSetting

                  if settings.activeEqualizerSetting == eqSettingToEdit {
                    settings.activeEqualizerSetting = .off
                  }

                  self.eqSettingToEdit = nil
                },
                secondaryButton: .cancel()
              )
            }
          }

        }, header: L10n.tr("Equalizer Editor"))
      }
    }
    .navigationTitle(L10n.tr("Equalizer"))
    .navigationBarTitleDisplayMode(.inline)
  }
}

// MARK: - EqualizerSettingsView_Previews

struct EqualizerSettingsView_Previews: PreviewProvider {
  @State
  static var settings = Settings()

  static var previews: some View {
    EqualizerSettingsView().environmentObject(settings)
  }
}
