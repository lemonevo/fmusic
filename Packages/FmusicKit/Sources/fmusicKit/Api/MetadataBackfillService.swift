//
//  MetadataBackfillService.swift
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

import Foundation
import os.log

// MARK: - LibraryMetadataOverride

struct LibraryMetadataOverride: Codable, Sendable {
  var album: String?
  var title: String?
  var artist: String?
  var source: String
  var confidence: Int
  var updatedAt: Date
  var artworkURL: String?
  var artworkMissedAt: Date?
  var artworkAttempt: Int?
}

// MARK: - MetadataOverrideStore

/// Persists online album matches outside the library index, so a later full
/// WebDAV scan does not reset those songs to "Unknown Album".
final class MetadataOverrideStore: @unchecked Sendable {
  static let shared = MetadataOverrideStore()

  private static let missRetryInterval: TimeInterval = 7 * 24 * 60 * 60
  /// Bump to retry covers after the lookup strategy improves.
  private static let artworkAttemptVersion = 2
  private let lock = NSLock()
  private let fileURL: URL?
  private let log = OSLog(subsystem: "fmusic", category: "MetadataOverrides")
  private var entries = [String: LibraryMetadataOverride]()
  private var didLoad = false

  private init() {
    let support = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first
    self.fileURL = support?
      .appendingPathComponent("fmusic", isDirectory: true)
      .appendingPathComponent("metadata-overrides.json")
  }

  func override(for songID: String) -> LibraryMetadataOverride? {
    lock.lock()
    defer { lock.unlock() }
    loadIfNeeded()
    guard let value = entries[songID],
          value.album?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    else { return nil }
    return value
  }

  func hasFreshMiss(for songID: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    loadIfNeeded()
    guard let value = entries[songID], value.album == nil else { return false }
    return Date().timeIntervalSince(value.updatedAt) < Self.missRetryInterval
  }

  func shouldAttemptArtwork(for songID: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    loadIfNeeded()
    guard let value = entries[songID], value.album != nil else { return false }
    if (value.artworkAttempt ?? 0) < Self.artworkAttemptVersion { return true }
    if value.artworkURL != nil { return true }
    if let missed = value.artworkMissedAt,
       Date().timeIntervalSince(missed) < Self.missRetryInterval {
      return false
    }
    return true
  }

  func recordArtwork(_ url: URL?, for songID: String) {
    lock.lock()
    defer { lock.unlock() }
    loadIfNeeded()
    guard var value = entries[songID] else { return }
    if let url {
      value.artworkURL = url.absoluteString
      value.artworkMissedAt = nil
    } else {
      value.artworkMissedAt = Date()
    }
    value.artworkAttempt = Self.artworkAttemptVersion
    entries[songID] = value
    persist()
  }

  func recordMatch(
    album: String,
    source: String,
    confidence: Int,
    for songID: String
  ) {
    lock.lock()
    defer { lock.unlock() }
    loadIfNeeded()
    let previous = entries[songID]
    entries[songID] = LibraryMetadataOverride(
      album: album,
      title: nil,
      artist: nil,
      source: source,
      confidence: confidence,
      updatedAt: Date(),
      artworkURL: previous?.artworkURL,
      artworkMissedAt: previous?.artworkMissedAt,
      artworkAttempt: previous?.artworkAttempt
    )
    persist()
  }

  func recordMiss(for songID: String) {
    lock.lock()
    defer { lock.unlock() }
    loadIfNeeded()
    entries[songID] = LibraryMetadataOverride(
      album: nil,
      title: nil,
      artist: nil,
      source: "miss",
      confidence: 0,
      updatedAt: Date(),
      artworkURL: nil,
      artworkMissedAt: nil,
      artworkAttempt: nil
    )
    persist()
  }

  private func loadIfNeeded() {
    guard !didLoad else { return }
    didLoad = true
    guard let fileURL,
          let data = try? Data(contentsOf: fileURL)
    else { return }
    entries = (try? JSONDecoder().decode(
      [String: LibraryMetadataOverride].self,
      from: data
    )) ?? [:]
  }

  private func persist() {
    guard let fileURL else { return }
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let data = try JSONEncoder().encode(entries)
      try data.write(to: fileURL, options: .atomic)
    } catch {
      os_log(
        "Failed to persist metadata overrides: %{public}@",
        log: log,
        type: .error,
        error.localizedDescription
      )
    }
  }
}

// MARK: - MetadataBackfillService

/// Fills albums that file and lyric tags could not provide. Matching uses the
/// same strict title/artist/duration identity checks as online lyrics.
@MainActor
public final class MetadataBackfillService {
  public struct BackfillResult: Sendable {
    public let matched: Int
    public let attempted: Int
    public var isEmpty: Bool { attempted == 0 }
  }

  public static let shared = MetadataBackfillService()
  private let log = OSLog(subsystem: "fmusic", category: "MetadataBackfill")
  private var activeTask: Task<BackfillResult, Never>?

  private init() {}

  public var isRunning: Bool { activeTask != nil }

  @discardableResult
  public func backfill(
    accountInfo: AccountInfo,
    album: Album? = nil,
    limit: Int = 60
  ) async
    -> BackfillResult {
    if let activeTask {
      return await activeTask.value
    }
    let task = Task { @MainActor [weak self] in
      guard let self else { return BackfillResult(matched: 0, attempted: 0) }
      return await perform(accountInfo: accountInfo, album: album, limit: limit)
    }
    activeTask = task
    defer { activeTask = nil }
    return await task.value
  }

  private func perform(
    accountInfo: AccountInfo,
    album: Album?,
    limit: Int
  ) async
    -> BackfillResult {
    let fmusic = FmusicKit.shared
    guard fmusic.settings.user.isOnlineMode,
          fmusic.networkMonitor.isConnectedToNetwork
    else { return BackfillResult(matched: 0, attempted: 0) }

    let storage = fmusic.storage
    let library = storage.main.library
    let account = library.getAccount(info: accountInfo)
    let unknownAlbumName = "Unknown Album"
    let songs: [Song]
    if let album {
      songs = album.songs.compactMap(\.asSong)
    } else {
      songs = library.getAlbums(for: account)
        .filter { $0.managedObject.name == unknownAlbumName }
        .flatMap(\.songs)
        .compactMap(\.asSong)
    }

    var matched = 0
    var attempted = 0
    for song in songs.prefix(limit) {
      if Task.isCancelled { break }
      guard song.album?.managedObject.name == unknownAlbumName else { continue }
      let songID = song.id
      if MetadataOverrideStore.shared.override(for: songID) != nil { continue }
      if MetadataOverrideStore.shared.hasFreshMiss(for: songID) { continue }

      attempted += 1
      guard let match = await OnlineLyricsService.shared.matchMetadata(for: song),
            apply(match, to: song, account: account, library: library)
      else {
        MetadataOverrideStore.shared.recordMiss(for: songID)
        continue
      }
      MetadataOverrideStore.shared.recordMatch(
        album: match.album,
        source: match.source.rawValue,
        confidence: match.score,
        for: songID
      )
      matched += 1
      os_log(
        "Matched album %{public}@ for %{public}@ (%d)",
        log: log,
        type: .info,
        match.album,
        song.title,
        match.score
      )
    }

    let artworkAdded = await fillMissingArtwork(
      accountInfo: accountInfo,
      account: account,
      library: library,
      limit: limit
    )

    if attempted > 0 {
      FileSourceLibraryWriter.updateDenormalizedValues(account: account, library: library)
    }
    if attempted > 0 || artworkAdded > 0 {
      library.saveContext()
      NotificationCenter.default.post(name: .librarySongsSynced, object: nil)
    }
    os_log(
      "Metadata backfill finished: %d matched, %d attempted, %d covers",
      log: log,
      type: .info,
      matched,
      attempted,
      artworkAdded
    )
    return BackfillResult(matched: matched, attempted: attempted)
  }

  /// Fetches covers for albums that were created by an online match but have no
  /// file or folder artwork. Misses are cached so a coverless album is not
  /// re-searched on every sync.
  private func fillMissingArtwork(
    accountInfo: AccountInfo,
    account: Account,
    library: LibraryStorage,
    limit: Int
  ) async
    -> Int {
    var added = 0
    var attempted = 0
    for album in library.getAlbums(for: account) {
      if attempted >= limit || Task.isCancelled { break }
      guard album.artwork?.imagePath == nil else { continue }
      let songs = album.songs.compactMap(\.asSong)
      guard let song = songs.first(where: {
        MetadataOverrideStore.shared.shouldAttemptArtwork(for: $0.id)
      })
      else { continue }
      attempted += 1
      guard let match = await OnlineLyricsService.shared.matchMetadata(for: song),
            Self.sameAlbum(match.album, album.managedObject.name),
            let artworkURL = match.artworkURL,
            await applyArtwork(
              artworkURL,
              to: album,
              account: account,
              accountInfo: accountInfo,
              library: library
            )
      else {
        MetadataOverrideStore.shared.recordArtwork(nil, for: song.id)
        continue
      }
      MetadataOverrideStore.shared.recordArtwork(artworkURL, for: song.id)
      added += 1
    }
    return added
  }

  private func applyArtwork(
    _ url: URL,
    to album: Album,
    account: Account,
    accountInfo: AccountInfo,
    library: LibraryStorage
  ) async
    -> Bool {
    guard let data = await Self.downloadArtwork(url),
          let encoded = Self.resizedArtwork(data)
    else { return false }
    let remoteInfo = ArtworkRemoteInfo(id: album.id, type: "album")
    let artwork = library.getArtwork(for: account, remoteInfo: remoteInfo)
      ?? library.createArtwork(account: account)
    artwork.remoteInfo = remoteInfo
    guard let relFilePath = CacheFileManager.shared.createRelPath(
      for: remoteInfo,
      account: accountInfo
    ),
      let absoluteFilePath = CacheFileManager.shared
      .getAbsolutefmusicPath(relFilePath: relFilePath)
    else { return false }
    CacheFileManager.shared
      .createDirectoryIfNeeded(at: absoluteFilePath.deletingLastPathComponent())
    do {
      try CacheFileManager.shared.writeDataExcludedFromBackup(
        data: encoded,
        to: absoluteFilePath,
        accountInfo: accountInfo
      )
    } catch {
      return false
    }
    artwork.relFilePath = relFilePath
    artwork.status = .CustomImage
    album.artwork = artwork
    album.songs.forEach { $0.artwork = artwork }
    return true
  }

  private static func sameAlbum(_ lhs: String, _ rhs: String?) -> Bool {
    guard let rhs else { return false }
    let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
    let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
    return !left.isEmpty && left.compare(right, options: .caseInsensitive) == .orderedSame
  }

  private static func downloadArtwork(_ url: URL) async -> Data? {
    guard url.scheme == "https" else { return nil }
    var request = URLRequest(url: url)
    request.timeoutInterval = 12
    guard let (data, response) = try? await artworkSession.data(for: request),
          let http = response as? HTTPURLResponse,
          (200 ..< 300).contains(http.statusCode),
          data.count <= 12 * 1024 * 1024
    else { return nil }
    return data
  }

  /// The shared artwork path always ends in `.png`; ImageIO and UIImage sniff
  /// the bytes, so storing JPEG here keeps covers small without changing paths.
  private static func resizedArtwork(_ data: Data) -> Data? {
    ArtworkImageEncoder.encodedData(from: data)
  }

  private static let artworkSession: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 12
    configuration.timeoutIntervalForResource = 20
    configuration.httpMaximumConnectionsPerHost = 2
    return URLSession(configuration: configuration)
  }()

  private func apply(
    _ match: OnlineMetadataMatch,
    to song: Song,
    account: Account,
    library: LibraryStorage
  )
    -> Bool {
    guard let currentAlbum = song.album,
          let scope = Self.idScope(for: currentAlbum)
    else { return false }
    let albumName = match.album.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !albumName.isEmpty else { return false }

    let artistName = song.artist?.name ?? ""
    let albumKey = "tag:\(artistName.lowercased())\u{1F}\(albumName.lowercased())"
    let albumID = FileSourceLibraryWriter.stableID(
      prefix: "\(scope)_album_",
      value: albumKey
    )
    let album: Album
    if let existing = library.getAlbum(
      for: account,
      id: albumID,
      isDetailFaultResolution: false
    ) {
      album = existing
    } else {
      let created = library.createAlbum(account: account)
      created.id = albumID
      created.name = albumName
      created.remoteStatus = .available
      created.isSongsMetaDataSynced = true
      album = created
    }
    if album.artist == nil { album.artist = song.artist }
    song.album = album
    return true
  }

  private static func idScope(for album: Album) -> String? {
    if album.id.hasPrefix("webdav_album_") { return "webdav" }
    if album.id.hasPrefix("local_album_") { return "local" }
    return nil
  }
}
