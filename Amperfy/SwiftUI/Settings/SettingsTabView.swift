//
//  SettingsTabView.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 11.08.25.
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

struct SettingsTabView: View {
  @State
  var selectedMenu: NavigationTarget = .general
  @State
  private var columnVisibility = NavigationSplitViewVisibility.doubleColumn
  @State
  private var detailPath = NavigationPath()
  @Environment(\.colorScheme)
  private var colorScheme

  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      List(NavigationTarget.allCases, id: \.self) { menuElement in
        HStack(spacing: 10) {
          Image(uiImage: menuElement.icon.withRenderingMode(.alwaysTemplate))
            .font(.system(size: 16))
            .foregroundStyle(Color.accentColor)
            .frame(width: 22, height: 22)
          Text(menuElement.displayName)
            .font(.system(size: 13))
            .foregroundStyle(Color.label)
            .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowInsets(EdgeInsets())
        .background(
          RoundedRectangle(cornerRadius: 8)
            .fill(selectedMenu == menuElement ? selectionColor : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { selectedMenu = menuElement }
      }
      .listStyle(.sidebar)
      .environment(\.defaultMinListRowHeight, 32)
      .navigationSplitViewColumnWidth(min: 210, ideal: 210, max: 260)
    } detail: {
      NavigationStack(path: $detailPath) {
        AnyView(selectedMenu.view())
      }
      // Pop views pushed in the previous menu (e.g. Support -> Event Log) when another menu is
      // selected. This requires all pushes to be value based (NavigationLink(value:)).
      .onChange(of: selectedMenu) {
        detailPath = NavigationPath()
      }
    }
  }

  /// Same neutral selection as the main sidebar (Apple Music style).
  private var selectionColor: Color {
    colorScheme == .dark
      ? Color.white.opacity(0.12)
      : Color.black.opacity(0.07)
  }
}
