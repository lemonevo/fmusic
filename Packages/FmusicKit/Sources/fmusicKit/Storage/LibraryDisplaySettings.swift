//
//  LibraryDisplaySettings.swift
//  fmusic
//
//  Created by Maximilian Bauer on 14.09.22.
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

import Foundation

// MARK: - LibraryDisplayType

@MainActor
public enum LibraryDisplayType: Int, CaseIterable, Sendable {
  case artists = 0
  case albums = 1
  case songs = 2
  case genres = 3
  case directories = 4
  case playlists = 5
  case downloads = 7
  case favoriteSongs = 8
  case favoriteAlbums = 9
  case favoriteArtists = 10
  case newestAlbums = 12
  case recentAlbums = 13
  case lyricsSearch = 14

  public static func createByDisplayName(name: String) -> LibraryDisplayType? {
    .allCases.first {
      $0.displayName == name
    }
  }

  /// Local folder and WebDAV sources have no server-side music folders, so
  /// the directories library type stays hidden.
  public static var supportedCases: [LibraryDisplayType] {
    allCases.filter { $0 != .directories }
  }

  public var displayName: String {
    switch self {
    case .artists:
      return L10n.tr("Artists")
    case .albums:
      return L10n.tr("Albums")
    case .songs:
      return L10n.tr("Songs")
    case .genres:
      return L10n.tr("Genres")
    case .directories:
      return L10n.tr("Directories")
    case .playlists:
      return L10n.tr("Playlists")
    case .downloads:
      return L10n.tr("Downloads")
    case .favoriteSongs:
      return L10n.tr("Favorite Songs")
    case .favoriteAlbums:
      return L10n.tr("Favorite Albums")
    case .favoriteArtists:
      return L10n.tr("Favorite Artists")
    case .newestAlbums:
      return L10n.tr("Newest Albums")
    case .recentAlbums:
      return L10n.tr("Recently Played Albums")
    case .lyricsSearch:
      return L10n.tr("Lyrics Search")
    }
  }

  public var image: PlatformImage {
    switch self {
    case .artists:
      return PlatformImage.artist
    case .albums:
      return PlatformImage.album
    case .songs:
      return PlatformImage.musicalNotes
    case .genres:
      return PlatformImage.genre
    case .directories:
      return PlatformImage.folder
    case .playlists:
      return PlatformImage.playlist
    case .downloads:
      return PlatformImage.download
    case .favoriteSongs:
      return PlatformImage.heartFill
    case .favoriteAlbums:
      return PlatformImage.heartFill
    case .favoriteArtists:
      return PlatformImage.heartFill
    case .newestAlbums:
      return PlatformImage.albumNewest
    case .recentAlbums:
      return PlatformImage.albumRecent
    case .lyricsSearch:
      return PlatformImages.symbol("text.magnifyingglass")
    }
  }
}

// MARK: - LibraryDisplaySettings

public struct LibraryDisplaySettings: Sendable, Codable {
  /// all library types (in use and not used) in the order arranged by the user
  public private(set) var order: [LibraryDisplayType]
  private var inUseTypes: Set<LibraryDisplayType>

  public var inUse: [LibraryDisplayType] {
    order.filter { inUseTypes.contains($0) }
  }

  public var notUsed: [LibraryDisplayType] {
    order.filter { !inUseTypes.contains($0) }
  }

  private enum CodingKeys: String, CodingKey {
    case combined
    case order
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    // combined: [inUse, notUsed], the stored format before the order was persisted
    let encodedCombined = [inUse, notUsed].map { $0.map { $0.rawValue } }
    try container.encode(encodedCombined, forKey: .combined)
    try container.encode(order.map { $0.rawValue }, forKey: .order)
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let decodedCombined = try container.decode([[Int]].self, forKey: .combined)
    // not present in settings stored before the order was persisted
    let decodedOrder = try container.decodeIfPresent([Int].self, forKey: .order)

    let mapped: [[LibraryDisplayType]] = decodedCombined.map { group in
      group.compactMap { LibraryDisplayType(rawValue: $0) }
    }

    if mapped.count == 2 {
      let storedOrder = decodedOrder?.compactMap { LibraryDisplayType(rawValue: $0) } ?? mapped[0] +
        mapped[1]
      let (order, inUse) = Self.migrated(order: storedOrder, inUse: Set(mapped[0]))
      self = LibraryDisplaySettings(order: order, inUse: inUse)
    } else if let first = mapped.first {
      // If only one group present, treat it as inUse and compute notUsed
      let (order, inUse) = Self.migrated(order: first, inUse: Set(first))
      self = LibraryDisplaySettings(order: order, inUse: inUse)
    } else {
      // Fallback to defaults if decoding produced no valid entries
      self = LibraryDisplaySettings(inUse: [])
    }
  }

  /// Settings stored before the lyrics search page existed do not mention it at all:
  /// add it once right after the songs entry so it is visible by default, while it
  /// can still be hidden or reordered afterwards.
  private static func migrated(
    order: [LibraryDisplayType],
    inUse: Set<LibraryDisplayType>
  )
    -> (order: [LibraryDisplayType], inUse: Set<LibraryDisplayType>) {
    guard !order.contains(.lyricsSearch) else { return (order, inUse) }
    var order = order
    if let index = order.firstIndex(of: .songs) {
      order.insert(.lyricsSearch, at: index + 1)
    }
    var inUse = inUse
    inUse.insert(.lyricsSearch)
    return (order, inUse)
  }

  public func isVisible(libraryType: LibraryDisplayType) -> Bool {
    inUseTypes.contains(libraryType)
  }

  /// The types not in use follow the ones in use, sorted by their raw value.
  public init(inUse: [LibraryDisplayType]) {
    let notUsed = Set(LibraryDisplayType.allCases).subtracting(Set(inUse))
      .sorted(by: { $0.rawValue < $1.rawValue })
    self.init(order: inUse + notUsed, inUse: Set(inUse))
  }

  /// Keeps the order arranged by the user; types missing in `order` (e.g. new ones) are appended.
  public init(order: [LibraryDisplayType], inUse: Set<LibraryDisplayType>) {
    self.order = order.completingOrder(with: LibraryDisplayType.allCases)
    self.inUseTypes = inUse
  }

  public static var defaultSettings: LibraryDisplaySettings {
    LibraryDisplaySettings(
      inUse: [
        .artists,
        .albums,
        .newestAlbums,
        .recentAlbums,
        .songs,
        .lyricsSearch,
        .favoriteSongs,
        .playlists,
      ]
    )
  }

  public static var addToPlaylistSettings: LibraryDisplaySettings {
    LibraryDisplaySettings(
      inUse: [
        .genres,
        .artists,
        .favoriteArtists,
        .albums,
        .favoriteAlbums,
        .newestAlbums,
        .recentAlbums,
        .songs,
        .favoriteSongs,
        .directories,
        .playlists,
      ]
    )
  }
}
