//
//  NewestAlbumsViewController.swift
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
import fmusicKit

/// `.newestAlbums` — albums ordered by the library's "newest" index (date added, descending).
///
/// Mirrors the core API `getNewestAlbums(for:offset:count:)`; when the index is not
/// populated yet (e.g. right after a fresh import) it falls back to sorting by album year.
@MainActor
final class NewestAlbumsViewController: AlbumGridPageViewController {
  override var pageTitle: String { L10n.tr("Newest Albums") }
  override var emptyMessage: String { L10n.tr("No %@", L10n.tr("Newest Albums")) }
  override var targetItemWidth: CGFloat { 140 }
  override var maxColumnCount: Int { 7 }

  override func loadAlbums() -> [Album] {
    let storage = FmusicKit.shared.storage
    guard let accountInfo = storage.settings.accounts.active else { return [] }
    let library = storage.main.library
    let account = library.getAccount(info: accountInfo)

    let newest = library.getNewestAlbums(for: account, offset: 0, count: 100)
    if !newest.isEmpty {
      return newest
    }

    // Fallback for libraries whose denormalised "newest" index has not been written yet.
    return library.getAlbums(for: account).sorted { lhs, rhs in
      if lhs.year != rhs.year { return lhs.year > rhs.year }
      return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
  }
}
