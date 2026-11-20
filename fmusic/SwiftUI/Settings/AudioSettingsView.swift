//
//  AudioSettingsView.swift
//  fmusic
//
//  ReplayGain and the equalizer, grouped as audio/effects settings.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import fmusicKit
import SwiftUI

// MARK: - AudioSettingsView

struct AudioSettingsView: View {
  enum Destination: Hashable {
    case equalizer
  }

  @EnvironmentObject
  private var settings: Settings

  var body: some View {
    ZStack {
      SettingsList {
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
          footer: L10n
            .tr(
              "Automatically normalize track volume based on replay gain information for consistent loudness."
            )
        )

        SettingsSection {
          NavigationLink(value: Destination.equalizer) {
            Text(L10n.tr("Equalizer"))
          }
        }
      }
    }
    .navigationTitle(L10n.tr("Audio & Effects"))
    .navigationBarTitleDisplayMode(.inline)
    .navigationDestination(for: Destination.self) { destination in
      switch destination {
      case .equalizer: EqualizerSettingsView()
      }
    }
  }
}
