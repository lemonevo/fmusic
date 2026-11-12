//
//  FileSourceLibraryWriter.swift
//  AmperfyKit
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

import CoreData
import CryptoKit
import Foundation

// MARK: - FileSourceMediaItem

protocol FileSourceMediaItem: Sendable {
  var songID: String { get }
  var albumID: String { get }
  var title: String { get }
  var artistName: String { get }
  var albumName: String { get }
  var genreName: String? { get }
  var year: Int { get }
  var track: Int { get }
  var duration: Int { get }
  var size: Int { get }
  var bitrate: Int { get }
  var contentType: String { get }
  var artwork: Data? { get }
  var lyrics: String? { get }
  var addedDate: Date { get }
  /// Path stored in `Song.url`: relative for local folders, remote for WebDAV.
  var playablePath: String { get }
  /// Source file for local folders, used to create the cache symlink.
  var localFileURL: URL? { get }
  /// Prefix for generated artist/genre IDs ("local" or "webdav").
  var idScope: String { get }
}

// MARK: - FileSourceLibraryWriter

/// Shared Core Data writer for file based sources.
enum FileSourceLibraryWriter {
  static func write<Item: FileSourceMediaItem>(
    items: [Item],
    account: Account,
    accountInfo: AccountInfo,
    library: LibraryStorage,
    cacheFileManager: CacheFileManager
  ) {
    var artistsByName = [String: Artist]()
    for artist in library.getArtists(for: account) {
      artistsByName[artist.name.lowercased()] = artist
    }
    var albumsByID = [String: Album]()
    for album in library.getAlbums(for: account) {
      albumsByID[album.id] = album
    }
    var genresByName = [String: Genre]()
    for genre in library.getGenres(for: account) {
      genresByName[genre.name.lowercased()] = genre
    }
    var artworkAlbumIDs = Set<String>()

    for item in items {
      let artistKey = item.artistName.lowercased()
      let artist: Artist
      if let existing = artistsByName[artistKey] {
        artist = existing
      } else {
        let created = library.createArtist(account: account)
        created.id = stableID(prefix: "\(item.idScope)_artist_", value: artistKey)
        created.name = item.artistName
        created.remoteStatus = .available
        artistsByName[artistKey] = created
        artist = created
      }

      let genre: Genre?
      if let genreName = item.genreName, !genreName.isEmpty {
        let genreKey = genreName.lowercased()
        if let existing = genresByName[genreKey] {
          genre = existing
        } else {
          let created = library.createGenre(account: account)
          created.id = stableID(prefix: "\(item.idScope)_genre_", value: genreKey)
          created.name = genreName
          created.remoteStatus = .available
          genresByName[genreKey] = created
          genre = created
        }
      } else {
        genre = nil
      }

      let album: Album
      if let existing = albumsByID[item.albumID] {
        album = existing
      } else {
        let created = library.createAlbum(account: account)
        created.id = item.albumID
        created.name = item.albumName
        created.remoteStatus = .available
        albumsByID[item.albumID] = created
        album = created
      }
      album.artist = artist
      album.genre = genre
      if album.year == 0 { album.year = item.year }
      album.isSongsMetaDataSynced = true

      let song: Song
      if let existing = library.getSong(for: account, id: item.songID) {
        song = existing
      } else {
        song = library.createSong(account: account)
        song.id = item.songID
      }
      song.title = item.title
      song.artist = artist
      song.album = album
      song.genre = genre
      song.track = item.track
      song.year = item.year
      song.remoteDuration = item.duration
      song.size = item.size
      song.bitrate = item.bitrate
      song.contentType = item.contentType
      song.url = item.playablePath
      song.addedDate = item.addedDate
      song.remoteStatus = .available

      if let sourceURL = item.localFileURL,
         let relFilePath = cacheFileManager.createRelPath(for: song),
         let absoluteFilePath = cacheFileManager
         .getAbsoluteAmperfyPath(relFilePath: relFilePath) {
        cacheFileManager.createDirectoryIfNeeded(at: absoluteFilePath.deletingLastPathComponent())
        if !FileManager.default.fileExists(atPath: absoluteFilePath.path) {
          try? FileManager.default.createSymbolicLink(
            at: absoluteFilePath,
            withDestinationURL: sourceURL
          )
        }
        song.relFilePath = relFilePath
      }

      if let lyrics = item.lyrics,
         let relFilePath = cacheFileManager.createRelPath(forLyricsOf: song),
         let absoluteFilePath = cacheFileManager
         .getAbsoluteAmperfyPath(relFilePath: relFilePath) {
        cacheFileManager.createDirectoryIfNeeded(at: absoluteFilePath.deletingLastPathComponent())
        try? lyrics.write(to: absoluteFilePath, atomically: true, encoding: .utf8)
        song.lyricsRelFilePath = relFilePath
      }

      if !artworkAlbumIDs.contains(item.albumID), let artworkData = item.artwork {
        let remoteInfo = ArtworkRemoteInfo(id: item.albumID, type: "album")
        let artwork = library.getArtwork(for: account, remoteInfo: remoteInfo)
          ?? library.createArtwork(account: account)
        artwork.remoteInfo = remoteInfo
        if let relFilePath = cacheFileManager.createRelPath(
          for: remoteInfo,
          account: accountInfo
        ),
          let absoluteFilePath = cacheFileManager
          .getAbsoluteAmperfyPath(relFilePath: relFilePath) {
          cacheFileManager
            .createDirectoryIfNeeded(at: absoluteFilePath.deletingLastPathComponent())
          try? cacheFileManager.writeDataExcludedFromBackup(
            data: artworkData,
            to: absoluteFilePath,
            accountInfo: accountInfo
          )
          artwork.relFilePath = relFilePath
          artwork.status = .CustomImage
        }
        album.artwork = artwork
        artist.artwork = artwork
        song.artwork = artwork
        artworkAlbumIDs.insert(item.albumID)
      } else if let artwork = album.artwork {
        song.artwork = artwork
      }
    }
  }

  static func removeStaleEntries(
    library: LibraryStorage,
    account: Account,
    activeSongPaths: Set<String>,
    cacheFileManager: CacheFileManager
  ) {
    for song in library.getSongs(for: account) {
      guard let url = song.url, !activeSongPaths.contains(url) else { continue }
      if let relFilePath = song.relFilePath,
         let absoluteFilePath = cacheFileManager.getAbsoluteAmperfyPath(relFilePath: relFilePath) {
        try? FileManager.default.removeItem(at: absoluteFilePath)
      }
      library.deleteSong(song)
    }
    for album in library.getAlbums(for: account) where album.songs.isEmpty {
      library.deleteAlbum(album: album)
    }
    for artist in library.getArtists(for: account)
      where artist.albums.isEmpty && artist.songs.isEmpty {
      library.deleteArtist(artist: artist)
    }
    for genre in library.getGenres(for: account)
      where genre.albums.isEmpty && genre.songs.isEmpty {
      library.deleteGenre(genre)
    }
  }

  static func updateDenormalizedValues(account: Account, library: LibraryStorage) {
    let albums = library.getAlbums(for: account)
    for album in albums {
      album.remoteDuration = album.songs.reduce(0) { $0 + $1.duration }
      album.managedObject.songCount = Int16(clamping: album.songs.count)
    }

    let sortedAlbums = albums.sorted { lhs, rhs in
      let lhsDate = lhs.songs.compactMap { $0.asSong?.addedDate }.max() ?? .distantPast
      let rhsDate = rhs.songs.compactMap { $0.asSong?.addedDate }.max() ?? .distantPast
      return lhsDate > rhsDate
    }
    for (index, album) in sortedAlbums.enumerated() {
      album.updateIsNewestInfo(index: index + 1)
      album.updateIsRecentInfo(index: index + 1)
    }

    let artists = library.getArtists(for: account)
    for artist in artists {
      artist.remoteAlbumCount = artist.albums.count
      artist.remoteDuration = artist.songs.reduce(0) { $0 + $1.duration }
      artist.managedObject.albumCount = Int16(clamping: artist.albums.count)
      artist.managedObject.songCount = Int16(clamping: artist.songs.count)
    }

    for genre in library.getGenres(for: account) {
      genre.managedObject.songCount = Int16(clamping: genre.songs.count)
      genre.managedObject.albumCount = Int16(clamping: genre.albums.count)
      genre.managedObject.artistCount = Int16(clamping: genre.artists.count)
    }
  }

  static func stableID(prefix: String, value: String) -> String {
    let digest = SHA256.hash(data: Data(value.utf8))
    let hex = digest.prefix(10).map { String(format: "%02x", $0) }.joined()
    return prefix + hex
  }
}
