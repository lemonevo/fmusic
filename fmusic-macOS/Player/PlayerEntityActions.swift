//
//  PlayerEntityActions.swift
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

/// Shared actions for the currently playing entity. The capsule and the Now Playing
/// page keep their own menu layouts, but availability checks and effects live here.
@MainActor
final class PlayerEntityActions {
  private var player: PlayerFacade { FmusicKit.shared.player }
  private var storage: PersistentStorage { FmusicKit.shared.storage }
  private var sharingPicker: NSSharingServicePicker?

  var currentSong: Song? { player.currentlyPlaying?.asSong }

  func instantMix() {
    if let url = URL(string: "fmusic://x-callback-url/playRandomSongs") {
      NSWorkspace.shared.open(url)
    }
  }

  func showAlbum() {
    guard let album = currentSong?.album else { return }
    AppDelegate.sharedAppDelegate?
      .mainWindowController?
      .mainViewController?
      .openAlbum(album)
  }

  func showArtist() {
    guard let artist = currentSong?.artist else { return }
    AppDelegate.sharedAppDelegate?
      .mainWindowController?
      .mainViewController?
      .openArtist(artist)
  }

  func toggleDesktopLyrics() {
    AppDelegate.sharedAppDelegate?.toggleDesktopLyrics(nil)
  }

  func matchOnlineLyrics() {
    guard let song = currentSong else { return }
    Task { @MainActor in
      _ = await OnlineLyricsService.shared.matchLyrics(for: song)
    }
  }

  func toggleFavorite() {
    guard let song = currentSong else { return }
    song.isFavorite.toggle()
    storage.main.saveContext()
  }

  func setRating(_ rating: Int) {
    guard let song = currentSong else { return }
    song.rating = rating
    storage.main.saveContext()
  }

  func canDownload(_ song: Song) -> Bool {
    guard let account = song.account,
          !storage.settings.user.isOfflineMode,
          song.isDownloadAvailable
    else { return false }
    return !song.isCached
  }

  func download(_ song: Song) {
    guard canDownload(song), let account = song.account else { return }
    FmusicKit.shared.getMeta(account.info).playableDownloadManager.download(object: song)
  }

  func addToPlaylistOptions(for song: Song) -> [(String, () -> Void)] {
    guard let accountInfo = storage.settings.accounts.active else { return [] }
    let library = storage.main.library
    let account = library.getAccount(info: accountInfo)
    var options: [(String, () -> Void)] = library.getPlaylists(for: account).map { playlist in
      (playlist.name, { playlist.append(playable: song) })
    }
    options.insert((L10n.tr("New Playlist"), {
      let playlist = library.createPlaylist(account: account)
      playlist.name = L10n.tr("New Playlist")
      playlist.append(playable: song)
      library.saveContext()
      FmusicKit.shared.notificationHandler.post(
        name: .librarySongsSynced,
        object: nil,
        userInfo: nil
      )
    }), at: 0)
    return options
  }

  func share(_ song: Song, relativeTo anchor: NSView) {
    let text = "\(song.title) — \(song.creatorName)"
    let picker = NSSharingServicePicker(items: [text])
    sharingPicker = picker
    picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
  }
}
