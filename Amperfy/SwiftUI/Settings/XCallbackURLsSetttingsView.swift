//
//  XCallbackURLsSetttingsView.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 18.09.22.
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

// MARK: - XCallbackURLsSetttingsView

struct XCallbackURLsSetttingsView: View {
  var body: some View {
    ZStack {
      SettingsList {
        Section {
          Text(
            L10n.tr(
              "Amperfy's X-Callback-URL API can be used to perform actions from other Apps or via Siri Shortcuts. All available actions with their detail information can be found below:"
            )
          )
          .font(.system(size: 11))
        }
        ForEach(appDelegate.intentManager.documentation, id: \.self) { actionDocu in
          Section {
            VStack(alignment: .leading) {
              Text(actionDocu.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.accentColor)
                .padding([.top], 8)
              Text("\(actionDocu.description)")
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
                .padding([.top, .bottom], 8)
              Text(L10n.tr("Action: %@", actionDocu.action))
                .font(.system(size: 11))
                .padding([.bottom], 8)
              Text(L10n.tr("Example URLs:"))
                .font(.system(size: 11))
                .underline()
                .padding([.bottom], 4)
              ForEach(actionDocu.exampleURLs, id: \.self) { url in
                HStack {
                  Text("- " + url)
                    .font(.system(size: 11))
                    .padding([.leading, .bottom], 8)
                  Spacer()
                  copyToPasteBoardButton(for: url)
                }
              }

              if !actionDocu.parameters.isEmpty {
                Text(L10n.tr("Parameters:"))
                  .font(.system(size: 11))
                  .underline()
                  .padding([.top], 8)
              }
              ForEach(actionDocu.parameters, id: \.self) { para in
                Text("\(para.name) \(para.isMandatory ? L10n.tr("(mandatory)") : "")")
                  .font(.system(size: 11))
                  .fontWeight(.bold)
                  .padding([.top], 4)
                Text(L10n.tr("Type: %@", para.type))
                  .font(.system(size: 11))
                  .padding([.leading], 8)
                Text(L10n.tr("Description: %@", para.description))
                  .font(.system(size: 11))
                  .padding([.leading], 8)
                if !para.isMandatory, let defaultValue = para.defaultIfNotGiven {
                  Text(L10n.tr("Default: %@", defaultValue))
                    .font(.system(size: 11))
                    .padding([.leading], 8)
                }
              }
            }
          }
        }
      }
    }
    .navigationTitle(L10n.tr("X-Callback-URL Documentation"))
    .navigationBarTitleDisplayMode(.inline)
  }
}

extension XCallbackURLsSetttingsView {
  /// Generates a button with an action to set the given URL to the system pasteBoard.
  func copyToPasteBoardButton(for url: String) -> some View {
    Button(action: {
      copyToPasteBoard(url: url)
    }, label: {
      AmperfyImage.documents.asImage
    })
    .buttonStyle(.borderless)
  }

  private func copyToPasteBoard(url: String) {
    UIPasteboard.general.string = url
  }
}

// MARK: - XCallbackURLsSetttingsView_Previews

struct XCallbackURLsSetttingsView_Previews: PreviewProvider {
  static var previews: some View {
    XCallbackURLsSetttingsView()
  }
}
