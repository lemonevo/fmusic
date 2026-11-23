//
//  RecentlyPlayedViewController.swift
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

import AppKit
import CoreData
import fmusicKit

/// `.recentlyPlayed` — albums ordered by the library's "recent" index.
///
/// The core exposes `getRecentAlbums(for:offset:count:)` (the same order the Catalyst app
/// shows under this sidebar entry). There is no dedicated `getRecentlyPlayedAlbums` API, so
/// when the recent index is empty the page falls back to the albums' own `lastTimePlayed`
/// (`playCount`) fields.
@MainActor
final class RecentlyPlayedViewController: AlbumGridPageViewController {
  override var pageTitle: String { L10n.tr("Recently Played Albums") }
  override var emptyMessage: String { L10n.tr("No %@", L10n.tr("Recently Played Albums")) }
  override var targetItemWidth: CGFloat { 140 }
  override var maxColumnCount: Int { 7 }

  nonisolated override func loadAlbumIDs(
    in library: LibraryStorage,
    account: Account
  )
    -> [NSManagedObjectID] {
    let recent = library.getRecentAlbums(for: account, offset: 0, count: 100)
    if !recent.isEmpty {
      return recent.map(\.managedObject.objectID)
    }
    return library.getAlbums(for: account)
      .filter { $0.lastTimePlayed != nil || $0.playCount > 0 }
      .sorted { lhs, rhs in
        let lhsDate = lhs.lastTimePlayed ?? .distantPast
        let rhsDate = rhs.lastTimePlayed ?? .distantPast
        if lhsDate != rhsDate { return lhsDate > rhsDate }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
      }
      .map(\.managedObject.objectID)
  }
}
