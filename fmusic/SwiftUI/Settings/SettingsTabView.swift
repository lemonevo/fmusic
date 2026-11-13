//
//  SettingsTabView.swift
//  fmusic
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

import fmusicKit
import SwiftUI

// MARK: - SettingsSearchItem

private struct SettingsSearchItem: Identifiable {
  let id: String
  let title: String
  let page: NavigationTarget
  let keywords: [String]

  init(_ title: String, _ page: NavigationTarget, keywords: [String] = []) {
    self.id = "\(page.rawValue)/\(title)"
    self.title = title
    self.page = page
    self.keywords = keywords
  }
}

// MARK: - SettingsSearchCatalog

/// Mirrors the rows of the settings pages: the sidebar search has no way to inspect
/// pages that are not on screen, so the searchable names live here next to the menu.
@MainActor
private enum SettingsSearchCatalog {
  static let items: [SettingsSearchItem] = [
    // General
    .init(L10n.tr("Language"), .general, keywords: ["language", "语言", "中文", "english"]),
    .init(L10n.tr("Offline Mode"), .general, keywords: ["offline", "离线"]),
    .init(
      L10n.tr("Prevent Screen Lock"),
      .general,
      keywords: ["screen lock", "sleep", "锁屏", "防止屏幕锁定"]
    ),

    // Account
    .init("URL", .account, keywords: ["server", "服务器", "地址"]),
    .init(L10n.tr("Username"), .account, keywords: ["username", "用户名"]),
    .init(L10n.tr("Theme Color"), .account, keywords: ["theme", "color", "主题", "颜色"]),
    .init(L10n.tr("Newest Songs"), .account, keywords: ["newest", "cache", "最新歌曲", "自动缓存"]),
    .init(L10n.tr("Backend API"), .account, keywords: ["backend", "api", "后端"]),
    .init(
      L10n.tr("Server API Version"),
      .account,
      keywords: ["server api", "服务器 api"]
    ),
    .init(
      L10n.tr("Client API Version"),
      .account,
      keywords: ["client api", "客户端 api"]
    ),
    .init(
      L10n.tr("Manage Server URLs"),
      .account,
      keywords: ["server urls", "服务器地址"]
    ),
    .init(
      L10n.tr("Custom HTTP Headers"),
      .account,
      keywords: ["http", "headers", "请求头"]
    ),
    .init(L10n.tr("Update Password"), .account, keywords: ["password", "密码"]),
    .init(
      L10n.tr("Resync Library"),
      .account,
      keywords: ["resync", "scan", "重新同步", "扫描"]
    ),
    .init(L10n.tr("Logout"), .account, keywords: ["logout", "退出登录"]),

    // Playback
    .init(
      L10n.tr("Enable ReplayGain"),
      .player,
      keywords: ["replaygain", "loudness", "响度"]
    ),
    .init(L10n.tr("Crossfade"), .player, keywords: ["crossfade", "fade", "淡入淡出"]),
    .init(
      L10n.tr("Auto-cache played tracks and download upcoming ones"),
      .player,
      keywords: ["cache", "download", "缓存", "预下载"]
    ),
    .init(
      L10n.tr("Song Playback Resume"),
      .player,
      keywords: ["resume", "续播", "记忆播放"]
    ),
    .init(L10n.tr("Manual Playback"), .player, keywords: ["manual", "手动播放"]),
    .init(
      L10n.tr("Autoplay After End"),
      .player,
      keywords: ["autoplay", "instant mix", "自动播放"]
    ),
    .init(
      L10n.tr("Music Player Skip Buttons"),
      .player,
      keywords: ["skip", "快进", "快退"]
    ),
    .init(
      L10n.tr("Lyrics Smooth Scrolling"),
      .player,
      keywords: ["lyrics", "scroll", "歌词", "滚动"]
    ),
    .init(
      L10n.tr("Disable Player Shuffle Button"),
      .player,
      keywords: ["shuffle", "random", "随机", "随机播放"]
    ),
    .init(L10n.tr("Equalizer"), .player, keywords: ["equalizer", "eq", "均衡器"]),

    // Display
    .init(
      L10n.tr("Appearance"),
      .displayAndInteraction,
      keywords: ["appearance", "dark", "light", "外观", "深色", "浅色"]
    ),
    .init(
      L10n.tr("Text Size"),
      .displayAndInteraction,
      keywords: ["text size", "font", "文字大小", "字体"]
    ),
    .init(
      L10n.tr("Mini Player Always on Top"),
      .displayAndInteraction,
      keywords: ["mini player", "top", "迷你播放器", "置顶"]
    ),
    .init(
      L10n.tr("Desktop Lyrics"),
      .displayAndInteraction,
      keywords: ["desktop lyrics", "lyrics", "桌面歌词"]
    ),
    .init(
      L10n.tr("Desktop Lyrics Font Size"),
      .displayAndInteraction,
      keywords: ["font size", "字号", "字体大小"]
    ),
    .init(L10n.tr("Alignment"), .displayAndInteraction, keywords: ["align", "对齐"]),
    .init(
      L10n.tr("Background Opacity"),
      .displayAndInteraction,
      keywords: ["opacity", "transparent", "透明度", "背景"]
    ),
    .init(
      L10n.tr("Show Next Line"),
      .displayAndInteraction,
      keywords: ["next line", "下一句"]
    ),
    .init(
      L10n.tr("Always on Top"),
      .displayAndInteraction,
      keywords: ["always on top", "置顶"]
    ),
    .init(
      L10n.tr("Lock Desktop Lyrics"),
      .displayAndInteraction,
      keywords: ["lock", "click through", "锁定", "鼠标穿透"]
    ),
    .init(
      L10n.tr("Menu Bar Lyrics"),
      .displayAndInteraction,
      keywords: ["menu bar", "lyrics", "菜单栏歌词"]
    ),
    .init(
      L10n.tr("Detailed Information"),
      .displayAndInteraction,
      keywords: ["details", "bitrate", "详细信息", "码率"]
    ),
    .init(
      L10n.tr("Song Duration"),
      .displayAndInteraction,
      keywords: ["duration", "歌曲时长"]
    ),
    .init(
      L10n.tr("Album Duration"),
      .displayAndInteraction,
      keywords: ["duration", "专辑时长"]
    ),
    .init(
      L10n.tr("Artist Duration"),
      .displayAndInteraction,
      keywords: ["duration", "艺人时长"]
    ),
    .init(
      L10n.tr("Show Star Rating"),
      .displayAndInteraction,
      keywords: ["rating", "stars", "评分", "星级"]
    ),
    .init(
      L10n.tr("Swipe Actions"),
      .displayAndInteraction,
      keywords: ["swipe", "gesture", "轻扫", "滑动"]
    ),

    // Library
    .init(L10n.tr("Playlists"), .library, keywords: ["playlists", "播放列表"]),
    .init(L10n.tr("Artists"), .library, keywords: ["artists", "艺人"]),
    .init(L10n.tr("Albums"), .library, keywords: ["albums", "专辑"]),
    .init(L10n.tr("Songs"), .library, keywords: ["songs", "歌曲"]),
    .init(L10n.tr("Initial Sync"), .library, keywords: ["sync", "同步"]),
    .init(L10n.tr("Progress"), .library, keywords: ["progress", "进度"]),
    .init(L10n.tr("Cached Songs"), .library, keywords: ["cached", "缓存"]),
    .init(
      L10n.tr("Complete Cache Size"),
      .library,
      keywords: ["cache size", "缓存大小"]
    ),
    .init(
      L10n.tr("Cache Size Limit"),
      .library,
      keywords: ["cache limit", "缓存上限"]
    ),
    .init(
      L10n.tr("Download all songs in library"),
      .library,
      keywords: ["download all", "全部下载"]
    ),
    .init(
      L10n.tr("Delete downloaded songs"),
      .library,
      keywords: ["delete", "cache", "删除缓存"]
    ),
    .init(
      L10n.tr("Artwork & Cache"),
      .library,
      keywords: ["artwork", "cover", "封面", "缓存"]
    ),

    // Support
    .init(
      L10n.tr("Report an issue on GitHub"),
      .support,
      keywords: ["issue", "github", "反馈", "报告问题"]
    ),
    .init(L10n.tr("Export log"), .support, keywords: ["log", "导出日志"]),
    .init(L10n.tr("Event Log"), .support, keywords: ["event log", "事件日志"]),
    .init(
      L10n.tr("Third-Party Licenses"),
      .support,
      keywords: ["license", "third party", "第三方许可"]
    ),
    .init(
      L10n.tr("X-Callback URL"),
      .support,
      keywords: ["xcallback", "x-callback", "url"]
    ),
    .init(L10n.tr("Version"), .support, keywords: ["version", "版本"]),
    .init(L10n.tr("Build Number"), .support, keywords: ["build", "构建版本"]),
  ]
}

// MARK: - SettingsSearchGroup

private struct SettingsSearchGroup: Identifiable {
  let page: NavigationTarget
  let items: [SettingsSearchItem]

  var id: String { page.rawValue }
}

@MainActor
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
  private var hoveredSearchResultID: String?
  @State
  private var isBackRowHovered = false
  @State
  private var searchText = ""
  @FocusState
  private var isSearchFocused: Bool
  @Environment(\.colorScheme)
  private var colorScheme

  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      VStack(spacing: 0) {
        sidebarHeader
        sidebarList
      }
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

  // MARK: Sidebar header

  private var sidebarHeader: some View {
    VStack(spacing: 4) {
      if let onBackToApp {
        Button(action: onBackToApp) {
          HStack(spacing: 7) {
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
          .padding(.leading, 18)
          .padding(.trailing, 8)
          .frame(height: 32)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(
            RoundedRectangle(cornerRadius: 8)
              .fill(isBackRowHovered ? selectionColor.opacity(0.6) : .clear)
          )
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isBackRowHovered = $0 }
        .animation(.easeOut(duration: 0.1), value: isBackRowHovered)
        .padding(.horizontal, 10)
        .padding(.top, 2)
      }

      searchField
    }
    .padding(.bottom, 4)
  }

  private var searchField: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Color.secondary)
      TextField(L10n.tr("Search Settings"), text: $searchText)
        .textFieldStyle(.plain)
        .font(.system(size: 13))
        .focused($isSearchFocused)
        .onSubmit { openFirstSearchResult() }
      if !searchText.isEmpty {
        Button {
          searchText = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 12))
            .foregroundStyle(Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.tr("Clear"))
      }
    }
    .padding(.horizontal, 8)
    .frame(height: 28)
    .background(
      RoundedRectangle(cornerRadius: 7, style: .continuous)
        .fill(searchFieldFill)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 7, style: .continuous)
        .strokeBorder(
          isSearchFocused ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.08),
          lineWidth: isSearchFocused ? 1 : 0.5
        )
    )
    .padding(.horizontal, 10)
    .padding(.top, 2)
    .accessibilityElement(children: .contain)
  }

  private var searchFieldFill: Color {
    colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.85)
  }

  // MARK: Sidebar list

  private var sidebarList: some View {
    List {
      if searchQuery.isEmpty {
        menuRows
      } else {
        searchResultRows
      }
    }
    .listStyle(.sidebar)
    .scrollContentBackground(.hidden)
    .environment(\.defaultMinListRowHeight, 32)
    .frame(maxHeight: .infinity)
  }

  @ViewBuilder
  private var menuRows: some View {
    sectionHeader(L10n.tr("Settings"))
    ForEach(appMenuItems, id: \.self) { menuElement in
      menuRow(menuElement)
    }
    sectionHeader(L10n.tr("Support"))
    if let supportItem = NavigationTarget.sidebarItems.first(where: { $0 == .support }) {
      menuRow(supportItem)
    }
  }

  private var appMenuItems: [NavigationTarget] {
    NavigationTarget.sidebarItems.filter { $0 != .support }
  }

  private func sectionHeader(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(Color.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.leading, 6)
      .padding(.top, 14)
      .padding(.bottom, 2)
      .listRowInsets(EdgeInsets())
      .listRowBackground(Color.clear)
  }

  private func menuRow(_ menuElement: NavigationTarget) -> some View {
    HStack(spacing: 7) {
      Image(uiImage: menuElement.icon)
        .foregroundStyle(Color.accentColor)
        .frame(width: 22, height: 22)
      Text(menuElement.displayName)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Color.label)
        .lineLimit(1)
      Spacer(minLength: 0)
    }
    .padding(.leading, 18)
    .padding(.trailing, 8)
    .frame(height: 32)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 8)
        .fill(rowBackgroundColor(for: menuElement))
    )
    .padding(.vertical, 3)
    .contentShape(Rectangle())
    .animation(.easeOut(duration: 0.14), value: selectedMenu)
    .animation(.easeOut(duration: 0.1), value: hoveredMenu)
    .onHover { isHovering in
      if isHovering {
        hoveredMenu = menuElement
      } else if hoveredMenu == menuElement {
        hoveredMenu = nil
      }
    }
    .onTapGesture { selectedMenu = menuElement }
    .listRowInsets(EdgeInsets())
    .listRowBackground(Color.clear)
  }

  // MARK: Search

  private var searchQuery: String {
    searchText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var searchGroups: [SettingsSearchGroup] {
    let query = searchQuery
    guard !query.isEmpty else { return [] }
    let groups = NavigationTarget.sidebarItems.compactMap { page -> SettingsSearchGroup? in
      let pageItems = SettingsSearchCatalog.items.filter { $0.page == page }
      let matches = page.displayName.localizedStandardContains(query)
        ? pageItems
        : pageItems.filter { item in
          item.title.localizedStandardContains(query) ||
            item.keywords.contains { $0.localizedStandardContains(query) }
        }
      return matches.isEmpty ? nil : SettingsSearchGroup(page: page, items: matches)
    }
    // Pages whose name matches the query lead the results; row matches keep sidebar order.
    let pageMatches = groups.filter { $0.page.displayName.localizedStandardContains(query) }
    let itemMatches = groups.filter { !$0.page.displayName.localizedStandardContains(query) }
    return pageMatches + itemMatches
  }

  @ViewBuilder
  private var searchResultRows: some View {
    let groups = searchGroups
    if groups.isEmpty {
      Text(L10n.tr("No Settings Found"))
        .font(.system(size: 13))
        .foregroundStyle(Color.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 18)
        .padding(.top, 18)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    } else {
      ForEach(groups) { group in
        sectionHeader(group.page.displayName)
        ForEach(group.items) { item in
          searchResultRow(item)
        }
      }
    }
  }

  private func searchResultRow(_ item: SettingsSearchItem) -> some View {
    Text(item.title)
      .font(.system(size: 13))
      .foregroundStyle(Color.label)
      .lineLimit(1)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.leading, 18)
      .padding(.trailing, 8)
      .frame(height: 30)
      .background(
        RoundedRectangle(cornerRadius: 8)
          .fill(
            hoveredSearchResultID == item.id
              ? selectionColor.opacity(0.6)
              : .clear
          )
      )
      .padding(.horizontal, 10)
      .padding(.vertical, 1)
      .contentShape(Rectangle())
      .onHover { isHovering in
        if isHovering {
          hoveredSearchResultID = item.id
        } else if hoveredSearchResultID == item.id {
          hoveredSearchResultID = nil
        }
      }
      .onTapGesture { openSearchResult(item) }
      .listRowInsets(EdgeInsets())
      .listRowBackground(Color.clear)
  }

  private func openSearchResult(_ item: SettingsSearchItem) {
    selectedMenu = item.page
    detailPath = NavigationPath()
    searchText = ""
    isSearchFocused = false
  }

  private func openFirstSearchResult() {
    guard let page = searchGroups.first?.page else { return }
    selectedMenu = page
    detailPath = NavigationPath()
    searchText = ""
    isSearchFocused = false
  }

  // MARK: Styling

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
