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
  var onBackToApp: (() -> ())?

  @State
  var selectedMenu: NavigationTarget = .general
  @State
  private var columnVisibility = NavigationSplitViewVisibility.doubleColumn
  @State
  private var detailPath = NavigationPath()
  @State
  private var hoveredMenu: NavigationTarget?
  @State
  private var isBackRowHovered = false
  @Environment(\.colorScheme)
  private var colorScheme

  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      List {
        if let onBackToApp {
          Button(action: onBackToApp) {
            HStack(spacing: 10) {
              Image(systemName: "chevron.left")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.secondary)
                .frame(width: 22, height: 22)
              Text(L10n.tr("Back to App"))
                .font(.system(size: 13))
                .foregroundStyle(Color.label)
                .lineLimit(1)
              Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
              RoundedRectangle(cornerRadius: 8)
                .fill(isBackRowHovered ? selectionColor.opacity(0.6) : .clear)
            )
            .contentShape(Rectangle())
            .onHover { isBackRowHovered = $0 }
            .padding(.vertical, 3)
          }
          .buttonStyle(.plain)
          .listRowInsets(EdgeInsets())
          .animation(.easeOut(duration: 0.1), value: isBackRowHovered)
        }

        ForEach(NavigationTarget.allCases, id: \.self) { menuElement in
          HStack(spacing: 10) {
            Image(uiImage: menuElement.icon)
              .foregroundStyle(Color.accentColor)
              .frame(width: 22, height: 22)
            Text(menuElement.displayName)
              .font(.system(size: 13))
              .foregroundStyle(Color.label)
              .lineLimit(1)
          }
          .padding(.horizontal, 8)
          .frame(height: 32)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(
            RoundedRectangle(cornerRadius: 8)
              .fill(rowBackgroundColor(for: menuElement))
          )
          .animation(.easeOut(duration: 0.14), value: selectedMenu)
          .animation(.easeOut(duration: 0.1), value: hoveredMenu)
          .contentShape(Rectangle())
          .onHover { isHovering in
            if isHovering {
              hoveredMenu = menuElement
            } else if hoveredMenu == menuElement {
              hoveredMenu = nil
            }
          }
          .onTapGesture { selectedMenu = menuElement }
          .padding(.vertical, 3)
          .listRowInsets(EdgeInsets())
        }
      }
      .listStyle(.sidebar)
      .environment(\.defaultMinListRowHeight, 32)
      .navigationSplitViewColumnWidth(min: 210, ideal: 210, max: 260)
    } detail: {
      NavigationStack(path: $detailPath) {
        AnyView(selectedMenu.view())
          .id(selectedMenu)
      }
      // Cross-fade between setting pages instead of swapping the content instantly.
      .animation(.easeInOut(duration: 0.18), value: selectedMenu)
      // Pop views pushed in the previous menu (e.g. Support -> Event Log) when another menu is
      // selected. This requires all pushes to be value based (NavigationLink(value:)).
      .onChange(of: selectedMenu) {
        detailPath = NavigationPath()
      }
    }
  }

  private func rowBackgroundColor(for menuElement: NavigationTarget) -> Color {
    if selectedMenu == menuElement {
      return selectionColor
    }
    if hoveredMenu == menuElement {
      return selectionColor.opacity(0.6)
    }
    return .clear
  }

  /// Same neutral selection as the main sidebar (Apple Music style).
  private var selectionColor: Color {
    colorScheme == .dark
      ? Color.white.opacity(0.12)
      : Color.black.opacity(0.07)
  }
}
