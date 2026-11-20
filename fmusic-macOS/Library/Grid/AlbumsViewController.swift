//
//  AlbumsViewController.swift
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

/// `.albums` — Apple Music style grid of every album of the active account.
///
/// Tiles show artwork, album title and artist; double-click plays the album. The column
/// count adapts to the window (`~5` columns at the default 1024 pt window width).
@MainActor
final class AlbumsViewController: AlbumGridPageViewController {
  override var pageTitle: String { L10n.tr("Albums") }
  override var emptyMessage: String { L10n.tr("No %@", L10n.tr("Albums")) }
  override var targetItemWidth: CGFloat { 140 }
  override var maxColumnCount: Int { 7 }

  override func loadAlbums() -> [Album] {
    let storage = FmusicKit.shared.storage
    guard let accountInfo = storage.settings.accounts.active else { return [] }
    let library = storage.main.library
    let account = library.getAccount(info: accountInfo)
    return library.getAlbums(for: account)
  }
}
