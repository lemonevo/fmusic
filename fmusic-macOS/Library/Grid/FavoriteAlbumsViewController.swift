//
//  FavoriteAlbumsViewController.swift
//  fmusic-macOS
//
//  `.favoriteAlbums` — albums marked as favorite, reusing the album grid page.
//

import AppKit
import fmusicKit

@MainActor
final class FavoriteAlbumsViewController: AlbumGridPageViewController {
  override var pageTitle: String { L10n.tr("Favorite Albums") }
  override var emptyMessage: String { L10n.tr("No %@", L10n.tr("Favorite Albums")) }

  override func loadAlbums() -> [Album] {
    let storage = FmusicKit.shared.storage
    guard let accountInfo = storage.settings.accounts.active else { return [] }
    let library = storage.main.library
    return library.getFavoriteAlbums(for: library.getAccount(info: accountInfo))
  }
}
