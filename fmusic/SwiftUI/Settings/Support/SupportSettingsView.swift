//
//  SupportSettingsView.swift
//  fmusic
//
//  Created by Maximilian Bauer on 19.09.22.
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

import fmusicKit
import SwiftUI

// MARK: - SupportSettingsView

struct SupportSettingsView: View {
  let splitPercentage = 0.15

  var body: some View {
    ZStack {
      SettingsList {
        SettingsSection {
          SettingsButtonRow(
            title: L10n.tr("Report an issue on GitHub"),
            splitPercentage: splitPercentage
          ) {
            if let url = URL(string: "https://github.com/lemonevo/fmusic/issues") {
              UIApplication.shared.open(url)
            }
          }
          ShareLink(
            item: fmusicLogExport(),
            preview: SharePreview(fmusicLogExport.fileName)
          ) {
            Text(L10n.tr("Export log"))
          }
        }

        SettingsSection(
          content: {
            SettingsRow(title: L10n.tr("Version")) {
              SecondaryText(AppDelegate.version)
            }
            SettingsRow(title: L10n.tr("Build Number")) {
              SecondaryText(AppDelegate.buildNumber)
            }
          },
          header: L10n.tr("About")
        )
      }
    }
    .navigationTitle(L10n.tr("Support & About"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      appDelegate.userStatistics.visited(.settingsSupport)
    }
  }
}

// MARK: - fmusicLogExport

/// The support log as `fmusicLog.json`, collected only when a share destination asks for it.
struct fmusicLogExport: Transferable {
  static let fileName = "fmusicLog.json"

  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(exportedContentType: .json) { _ in
      let data = await MainActor.run {
        LogData.collectInformation(fmusicData: FmusicKit.shared).asJSONData()
      }
      guard let data else { throw CocoaError(.fileWriteUnknown) }
      return data
    }
    .suggestedFileName(fileName)
  }
}

// MARK: - SupportSettingsView_Previews

struct SupportSettingsView_Previews: PreviewProvider {
  static var previews: some View {
    SupportSettingsView()
  }
}
