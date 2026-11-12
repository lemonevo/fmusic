//
//  EventLogCellView.swift
//  Amperfy
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

import AmperfyKit
import SwiftUI

struct EventLogCellView: View {
  @State
  var entry: LogEntry

  var typeText: String {
    var typeLabelText = "\(entry.type.description)"
    if entry.type == .error, entry.statusCode > 1 {
      typeLabelText += " \(CommonString.oneMiddleDot) \(L10n.tr("Status code %d", entry.statusCode))"
    }
    return typeLabelText
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(entry.message)
        .font(.system(size: 13))
        .fixedSize(horizontal: false, vertical: true)
      HStack {
        Text(typeText)
        Spacer()
        Text("\(entry.creationDate.asIso8601String)")
          .monospacedDigit()
      }
      .font(.system(size: 11))
      .foregroundStyle(Color.secondaryLabel)
    }
    .padding(.vertical, 4)
    .contextMenu {
      Button(action: {
        UIPasteboard.general.string = entry.message
      }) {
        Text(L10n.tr("Copy to Clipboard"))
        Image(uiImage: .clipboard)
      }
    }
  }
}
