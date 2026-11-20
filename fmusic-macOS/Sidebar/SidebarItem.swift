//
//  SidebarItem.swift
//  fmusic-macOS
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
import fmusicKit

/// Entries of the main window sidebar (Apple Music style order).
enum SidebarItem: String, CaseIterable, Sendable {
  case search
  case home
  case songs
  case artists
  case albums
  case newestAlbums
  case recentlyPlayed
  case lyricsSearch
  case favoriteSongs
  case playlists
  case podcasts
  case directories
  case radios
  case downloads

  var title: String {
    switch self {
    case .search: return L10n.tr("Search")
    case .home: return L10n.tr("Home")
    case .songs: return L10n.tr("Songs")
    case .artists: return L10n.tr("Artists")
    case .albums: return L10n.tr("Albums")
    case .newestAlbums: return L10n.tr("Newest Albums")
    case .recentlyPlayed: return L10n.tr("Recently Played Albums")
    case .lyricsSearch: return L10n.tr("Lyrics Search")
    case .favoriteSongs: return L10n.tr("Favorite Songs")
    case .playlists: return L10n.tr("Playlists")
    case .podcasts: return L10n.tr("Podcasts")
    case .directories: return L10n.tr("Directories")
    case .radios: return L10n.tr("Radios")
    case .downloads: return L10n.tr("Downloads")
    }
  }

  var symbolName: String {
    switch self {
    case .search: return "magnifyingglass"
    case .home: return "house"
    case .songs: return "music.note"
    case .artists: return "music.mic"
    case .albums: return "square.stack"
    case .newestAlbums: return "sparkles"
    case .recentlyPlayed: return "clock"
    case .lyricsSearch: return "quote.bubble"
    case .favoriteSongs: return "heart"
    case .playlists: return "music.note.list"
    case .podcasts: return "mic"
    case .directories: return "folder"
    case .radios: return "dot.radiowaves.left.and.right"
    case .downloads: return "arrow.down.circle"
    }
  }
}
