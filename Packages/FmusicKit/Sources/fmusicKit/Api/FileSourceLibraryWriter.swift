//
//  FileSourceLibraryWriter.swift
//  fmusicKit
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
    // Loading the existing songs once turns the per-item lookup below into a
    // dictionary hit; a full scan otherwise issued one fetch per file.
    var songsByID = [String: Song]()
    for song in library.getSongs(for: account) {
      songsByID[song.id] = song
    }
    var artworkAlbumIDs = Set<String>()

    for item in items {
      let metadata = resolvedMetadata(for: item)
      let artistKey = metadata.artistName.lowercased()
      let artist: Artist
      if let existing = artistsByName[artistKey] {
        artist = existing
      } else {
        let created = library.createArtist(account: account)
        created.id = stableID(prefix: "\(item.idScope)_artist_", value: artistKey)
        created.name = metadata.artistName
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
      if let existing = albumsByID[metadata.albumID] {
        album = existing
        // The album identity is derived from the tag or folder path, so its name is stable too.
        if album.name != metadata.albumName {
          album.name = metadata.albumName
        }
      } else {
        let created = library.createAlbum(account: account)
        created.id = metadata.albumID
        created.name = metadata.albumName
        created.remoteStatus = .available
        albumsByID[metadata.albumID] = created
        album = created
      }
      album.artist = artist
      album.genre = genre
      if album.year == 0 { album.year = item.year }
      album.isSongsMetaDataSynced = true

      let song: Song
      if let existing = songsByID[item.songID] {
        song = existing
      } else {
        song = library.createSong(account: account)
        song.id = item.songID
        songsByID[item.songID] = song
      }
      song.title = metadata.title
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
         .getAbsolutefmusicPath(relFilePath: relFilePath) {
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
         .getAbsolutefmusicPath(relFilePath: relFilePath) {
        cacheFileManager.createDirectoryIfNeeded(at: absoluteFilePath.deletingLastPathComponent())
        try? lyrics.write(to: absoluteFilePath, atomically: true, encoding: .utf8)
        song.lyricsRelFilePath = relFilePath
      }

      if !artworkAlbumIDs.contains(metadata.albumID), let artworkData = item.artwork {
        let remoteInfo = ArtworkRemoteInfo(id: metadata.albumID, type: "album")
        let artwork = library.getArtwork(for: account, remoteInfo: remoteInfo)
          ?? library.createArtwork(account: account)
        artwork.remoteInfo = remoteInfo
        if let relFilePath = cacheFileManager.createRelPath(
          for: remoteInfo,
          account: accountInfo
        ),
          let absoluteFilePath = cacheFileManager
          .getAbsolutefmusicPath(relFilePath: relFilePath) {
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
        artworkAlbumIDs.insert(metadata.albumID)
      } else if let artwork = album.artwork {
        song.artwork = artwork
      }
    }
  }

  private struct ResolvedMetadata {
    let title: String
    let artistName: String
    let albumName: String
    let albumID: String
  }

  /// A persisted online result fills an unknown album on later full scans.
  /// Real file or lyric tags always win, so a corrected file is never held
  /// back by an old lookup.
  private static func resolvedMetadata(for item: FileSourceMediaItem) -> ResolvedMetadata {
    guard let override = MetadataOverrideStore.shared.override(for: item.songID),
          item.albumName.isEmpty || item.albumName == "Unknown Album",
          let albumName = override.album?
          .trimmingCharacters(in: .whitespacesAndNewlines),
          !albumName.isEmpty
    else {
      return ResolvedMetadata(
        title: item.title,
        artistName: item.artistName,
        albumName: item.albumName,
        albumID: item.albumID
      )
    }
    func cleaned(_ value: String?) -> String? {
      let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed?.isEmpty == false ? trimmed : nil
    }
    let artistName = cleaned(override.artist) ?? item.artistName
    let title = cleaned(override.title) ?? item.title
    let albumKey = Self.albumKey(albumName: albumName, fallbackDirectoryPath: "")
    return ResolvedMetadata(
      title: title,
      artistName: artistName,
      albumName: albumName,
      albumID: stableID(prefix: "\(item.idScope)_album_", value: albumKey)
    )
  }

  static func removeStaleEntries(
    library: LibraryStorage,
    account: Account,
    activeSongPaths: Set<String>,
    cacheFileManager: CacheFileManager
  ) {
    for song in library.getSongs(for: account) {
      guard let url = song.url, !activeSongPaths.contains(url) else { continue }
      // Songs opened directly from Finder are not part of the scanned folder;
      // keep them while the underlying local file still exists, and prune them once deleted.
      if let openedFileURL = OpenedFileSource.fileURL(from: url) {
        if FileManager.default.fileExists(atPath: openedFileURL.path) {
          continue
        }
        OpenedFileBookmarkStore.shared.forget(fileURL: openedFileURL)
      }
      if let relFilePath = song.relFilePath,
         let absoluteFilePath = cacheFileManager.getAbsolutefmusicPath(relFilePath: relFilePath) {
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
      if let albumArtwork = album.artwork, albumArtwork.imagePath != nil {
        for song in album.songs where song.artwork?.imagePath == nil {
          song.artwork = albumArtwork
        }
      }
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
      if artist.artwork?.imagePath == nil {
        artist.artwork = artist.albums.first { $0.artwork?.imagePath != nil }?.artwork
          ?? artist.songs.first { $0.artwork?.imagePath != nil }?.artwork
      }
    }

    for genre in library.getGenres(for: account) {
      genre.managedObject.songCount = Int16(clamping: genre.songs.count)
      genre.managedObject.albumCount = Int16(clamping: genre.albums.count)
      genre.managedObject.artistCount = Int16(clamping: genre.artists.count)
    }
  }

  /// Normalizes an album name for merging across multiple artists/compilations.
  /// Returns `nil` for blank or placeholder names so untagged tracks stay grouped by folder.
  static func normalizedAlbumName(_ name: String?) -> String? {
    guard let name else { return nil }
    let collapsed = name
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
      .lowercased()
    guard !collapsed.isEmpty,
          collapsed != "unknown album",
          collapsed != "未知专辑"
    else { return nil }
    return collapsed
  }

  /// Builds a stable album identity key that merges tracks by album name
  /// (regardless of track artist), falling back to folder path when untagged.
  static func albumKey(albumName: String?, fallbackDirectoryPath: String) -> String {
    if let normalized = normalizedAlbumName(albumName) {
      return "album:\(normalized)"
    }
    return "path:\(fallbackDirectoryPath)"
  }

  /// Merges existing albums in the account that share the same normalized album name
  /// (e.g. legacy albums previously split by per-track artist), keeping the best
  /// artwork/metadata and deleting the now-empty duplicates.
  static func mergeAlbumsByName(account: Account, library: LibraryStorage) {
    var groups = [String: [Album]]()
    for album in library.getAlbums(for: account) {
      guard let key = normalizedAlbumName(album.managedObject.name) else { continue }
      groups[key, default: []].append(album)
    }

    for albums in groups.values where albums.count > 1 {
      let sorted = albums.sorted { lhs, rhs in
        let lhsHasArt = lhs.artwork?.imagePath != nil
        let rhsHasArt = rhs.artwork?.imagePath != nil
        if lhsHasArt != rhsHasArt { return lhsHasArt }
        if lhs.songs.count != rhs.songs.count { return lhs.songs.count > rhs.songs.count }
        return lhs.id < rhs.id
      }
      guard let primary = sorted.first else { continue }
      for duplicate in sorted.dropFirst() {
        if primary.artwork?.imagePath == nil, let dupArtwork = duplicate.artwork,
           dupArtwork.imagePath != nil {
          primary.artwork = dupArtwork
        }
        for song in duplicate.songs.compactMap(\.asSong) {
          song.album = primary
          if song.artwork?.imagePath == nil, let primaryArtwork = primary.artwork {
            song.artwork = primaryArtwork
          }
        }
        if primary.year == 0, duplicate.year > 0 {
          primary.year = duplicate.year
        }
        if primary.genre == nil, let dupGenre = duplicate.genre {
          primary.genre = dupGenre
        }
        library.deleteAlbum(album: duplicate)
      }
    }
  }

  /// Removes duplicate songs in the account that can be left behind by overlapping
  /// resyncs or URL-encoding changes, keeping the richest copy (downloaded/cached,
  /// lyrics, favorite/rating, artwork) and deleting redundant Core Data rows.
  static func deduplicateSongs(account: Account, library: LibraryStorage) {
    func rank(_ song: Song) -> (Int, Int, Int, Int, Int) {
      (
        song.isCached ? 1 : 0,
        song.lyricsRelFilePath != nil ? 1 : 0,
        (song.isFavorite || song.rating > 0) ? 1 : 0,
        song.artwork?.imagePath != nil ? 1 : 0,
        song.playCount
      )
    }

    func normalizedURL(_ url: String?) -> String? {
      guard let url, !url.isEmpty else { return nil }
      let decoded = url.removingPercentEncoding ?? url
      return decoded.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
    }

    func pruneGroup(_ group: [Song]) {
      guard group.count > 1 else { return }
      let sorted = group.sorted { lhs, rhs in
        let rL = rank(lhs)
        let rR = rank(rhs)
        if rL != rR { return rL > rR }
        return lhs.managedObject.objectID.uriRepresentation().absoluteString <
          rhs.managedObject.objectID.uriRepresentation().absoluteString
      }
      guard let primary = sorted.first else { return }
      for duplicate in sorted.dropFirst() {
        if primary.lyricsRelFilePath == nil, let lyricsPath = duplicate.lyricsRelFilePath {
          primary.lyricsRelFilePath = lyricsPath
        }
        if primary.artwork?.imagePath == nil, let art = duplicate.artwork, art.imagePath != nil {
          primary.artwork = art
        }
        if !primary.isFavorite, duplicate.isFavorite {
          primary.isFavorite = true
        }
        if primary.rating == 0, duplicate.rating > 0 {
          primary.rating = duplicate.rating
        }
        library.deleteSong(duplicate)
      }
    }

    // Pass 1: exact duplicate song IDs.
    var byID = [String: [Song]]()
    for song in library.getSongs(for: account) where !song.id.isEmpty {
      byID[song.id, default: []].append(song)
    }
    for group in byID.values where group.count > 1 {
      pruneGroup(group)
    }

    // Pass 2: duplicate normalized remote/local paths.
    var byURL = [String: [Song]]()
    for song in library.getSongs(for: account) {
      guard let key = normalizedURL(song.url) else { continue }
      byURL[key, default: []].append(song)
    }
    for group in byURL.values where group.count > 1 {
      pruneGroup(group)
    }

    // Pass 3: duplicate identical tracks inside the same album (same title, artist,
    // duration, and positive file size).
    var byAlbumFingerprint = [String: [Song]]()
    for song in library.getSongs(for: account) {
      guard let albumID = song.album?.id, song.size > 0 else { continue }
      let titleKey = song.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      let artistKey = (song.artist?.name ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
      let dur = song.duration > 0 ? song.duration : song.remoteDuration
      let fingerprint = "\(albumID)|\(titleKey)|\(artistKey)|\(dur)|\(song.size)"
      byAlbumFingerprint[fingerprint, default: []].append(song)
    }
    for group in byAlbumFingerprint.values where group.count > 1 {
      pruneGroup(group)
    }
  }

  static func stableID(prefix: String, value: String) -> String {
    let digest = SHA256.hash(data: Data(value.utf8))
    let hex = digest.prefix(10).map { String(format: "%02x", $0) }.joined()
    return prefix + hex
  }
}
