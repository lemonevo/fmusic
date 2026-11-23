//
//  FavoriteAlbumsViewController.swift
//  fmusic-macOS
//
//  `.favoriteAlbums` — albums marked as favorite, reusing the album grid page.
//

import AppKit
import CoreData
import fmusicKit

@MainActor
final class FavoriteAlbumsViewController: AlbumGridPageViewController {
  override var pageTitle: String { L10n.tr("Favorite Albums") }
  override var emptyMessage: String { L10n.tr("No %@", L10n.tr("Favorite Albums")) }

  nonisolated override func loadAlbumIDs(
    in library: LibraryStorage,
    account: Account
  )
    -> [NSManagedObjectID] {
    library.getFavoriteAlbums(for: account).map(\.managedObject.objectID)
  }
}
