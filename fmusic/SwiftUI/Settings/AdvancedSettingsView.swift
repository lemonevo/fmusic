//
//  AdvancedSettingsView.swift
//  fmusic
//
//  Diagnostics and integration options previously nested under Support.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import fmusicKit
import SwiftUI

// MARK: - AdvancedSettingsView

struct AdvancedSettingsView: View {
  enum Destination: Hashable {
    case eventLog
    case license
    case xcallback
    #if DEBUG
      case developer
    #endif
  }

  var body: some View {
    ZStack {
      SettingsList {
        SettingsSection(
          content: {
            NavigationLink(value: Destination.eventLog) {
              Text(L10n.tr("Event Log"))
            }
            NavigationLink(value: Destination.license) {
              Text(L10n.tr("Third-Party Licenses"))
            }
            NavigationLink(value: Destination.xcallback) {
              Text(L10n.tr("X-Callback URL"))
            }
            #if DEBUG
              NavigationLink(value: Destination.developer) {
                Text(L10n.tr("Developer Tools"))
              }
            #endif
          },
          footer: L10n.tr("Diagnostics, integrations and third-party notices.")
        )
      }
    }
    .navigationTitle(L10n.tr("Advanced"))
    .navigationBarTitleDisplayMode(.inline)
    .navigationDestination(for: Destination.self) { destination in
      switch destination {
      case .eventLog: EventLogSettingsView()
      case .license: LicenseSettingsView()
      case .xcallback: XCallbackURLsSetttingsView()
      #if DEBUG
        case .developer: DeveloperView()
      #endif
      }
    }
  }
}
