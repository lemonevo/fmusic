//
//  FavoriteArtistsViewController.swift
//  fmusic-macOS
//
//  `.favoriteArtists` — artists marked as favorite, reusing the artist list page.
//

import AppKit
import fmusicKit

@MainActor
final class FavoriteArtistsViewController: ArtistsViewController {
  override var pageTitle: String { L10n.tr("Favorite Artists") }
  override var forceFavoritesOnly: Bool { true }
  override var emptyMessage: String { L10n.tr("No %@", L10n.tr("Favorite Artists")) }
}
