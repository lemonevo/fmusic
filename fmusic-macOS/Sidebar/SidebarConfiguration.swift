//
//  SidebarConfiguration.swift
//  fmusic-macOS
//
//  Mirrors the Catalyst `LibraryDisplaySettings` sidebar editor model
//  (an ordered list plus a hidden set), persisted locally so the AppKit
//  front-end can reorder every item — including entries such as Directories
//  that have no server-side `LibraryDisplayType`.
//

import AppKit
import fmusicKit

extension Notification.Name {
  /// Posted after the AppKit sidebar order/visibility changed.
  static let macSidebarConfigurationChanged = Notification.Name(
    "fmusic.mac.sidebarConfigurationChanged"
  )
}

@MainActor
enum SidebarConfiguration {
  /// Fixed entries are always shown and cannot be hidden/reordered.
  static let fixedItems: [SidebarItem] = [.search, .home]

  /// Configurable entries. Radio/podcast are intentionally absent: they are
  /// streaming-only sections, not part of the local/WebDAV library.
  static let configurableItems: [SidebarItem] = [
    .songs,
    .artists,
    .albums,
    .newestAlbums,
    .recentlyPlayed,
    .lyricsSearch,
    .favoriteSongs,
    .playlists,
    .genres,
    .favoriteAlbums,
    .favoriteArtists,
    .directories,
    .downloads,
  ]

  /// Core local/WebDAV entries shown by default. Everything else starts hidden
  /// until the user enables it in Edit mode.
  private static let defaultVisible: Set<SidebarItem> = [
    .songs,
    .artists,
    .albums,
    .favoriteSongs,
    .playlists,
    .directories,
    .downloads,
  ]

  private struct State: Codable {
    var order: [String]
    var hidden: [String]
  }

  private static let defaultsKey = "fmusic.mac.sidebarState"

  private static func loadState() -> State {
    if let data = UserDefaults.standard.data(forKey: defaultsKey),
       let state = try? JSONDecoder().decode(State.self, from: data) {
      return normalized(state)
    }
    return seedState()
  }

  private static func saveState(_ state: State) {
    if let data = try? JSONEncoder().encode(normalized(state)) {
      UserDefaults.standard.set(data, forKey: defaultsKey)
    }
    NotificationCenter.default.post(name: .macSidebarConfigurationChanged, object: nil)
  }

  /// Drops entries that no longer exist and appends newly added ones.
  private static func normalized(_ state: State) -> State {
    let valid = configurableItems.map(\.rawValue)
    var order: [String] = []
    for raw in state.order where valid.contains(raw) && !order.contains(raw) {
      order.append(raw)
    }
    var hidden = state.hidden.filter { valid.contains($0) }
    for raw in valid where !order.contains(raw) {
      order.append(raw)
      // Newly added entries follow the default visibility policy.
      if let item = SidebarItem(rawValue: raw), !defaultVisible.contains(item) {
        hidden.append(raw)
      }
    }
    return State(order: order, hidden: hidden)
  }

  private static func seedState() -> State {
    let order = configurableItems.map(\.rawValue)
    let hidden = configurableItems
      .filter { !defaultVisible.contains($0) }
      .map(\.rawValue)
    let state = State(order: order, hidden: hidden)
    saveState(state)
    return state
  }

  private static func items(from state: State) -> [SidebarItem] {
    state.order.compactMap(SidebarItem.init(rawValue:))
  }

  /// Visible configurable items in their saved order (view mode).
  static func visibleItems() -> [SidebarItem] {
    let state = loadState()
    let hidden = Set(state.hidden)
    return items(from: state).filter { !hidden.contains($0.rawValue) }
  }

  /// All configurable items in saved order (edit mode, both shown and hidden).
  static func editingItems() -> [SidebarItem] {
    items(from: loadState())
  }

  static func isVisible(_ item: SidebarItem) -> Bool {
    !loadState().hidden.contains(item.rawValue)
  }

  static func setVisible(_ item: SidebarItem, isVisible: Bool) {
    var state = loadState()
    if isVisible {
      state.hidden.removeAll { $0 == item.rawValue }
    } else if !state.hidden.contains(item.rawValue) {
      state.hidden.append(item.rawValue)
    }
    saveState(state)
  }

  /// Moves a configurable item from one index to another in the saved order.
  static func moveItem(from source: Int, to destination: Int) {
    var state = loadState()
    guard source >= 0, source < state.order.count,
          destination >= 0, destination < state.order.count,
          source != destination else { return }
    let raw = state.order.remove(at: source)
    state.order.insert(raw, at: destination)
    saveState(state)
  }
}
