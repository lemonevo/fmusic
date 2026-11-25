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
  /// Bump to retry covers and album misses after the lookup strategy improves.
  private static let artworkAttemptVersion = 7
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
    if (value.artworkAttempt ?? 0) < Self.artworkAttemptVersion { return false }
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

  func shouldAttemptAlbumArtwork(for albumID: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    loadIfNeeded()
    let key = "album:\(albumID)"
    guard let value = entries[key] else { return true }
    if (value.artworkAttempt ?? 0) < Self.artworkAttemptVersion { return true }
    if value.artworkURL != nil { return true }
    if let missed = value.artworkMissedAt,
       Date().timeIntervalSince(missed) < Self.missRetryInterval {
      return false
    }
    return true
  }

  func hasOutdatedOnlineArtwork(forAlbumID albumID: String, songIDs: [String]) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    loadIfNeeded()
    if let value = entries["album:\(albumID)"],
       value.artworkURL != nil,
       (value.artworkAttempt ?? 0) < Self.artworkAttemptVersion {
      return true
    }
    return songIDs.contains { songID in
      guard let value = entries[songID] else { return false }
      return value.artworkURL != nil && (value.artworkAttempt ?? 0) < Self.artworkAttemptVersion
    }
  }

  func recordAlbumArtwork(_ url: URL?, for albumID: String) {
    lock.lock()
    defer { lock.unlock() }
    loadIfNeeded()
    let key = "album:\(albumID)"
    entries[key] = LibraryMetadataOverride(
      album: nil,
      title: nil,
      artist: nil,
      source: "artwork",
      confidence: url == nil ? 0 : 100,
      updatedAt: Date(),
      artworkURL: url?.absoluteString,
      artworkMissedAt: url == nil ? Date() : nil,
      artworkAttempt: Self.artworkAttemptVersion
    )
    persist()
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
    artist: String? = nil,
    source: String,
    confidence: Int,
    for songID: String
  ) {
    lock.lock()
    defer { lock.unlock() }
    loadIfNeeded()
    let previous = entries[songID]
    let cleanArtist = artist?.trimmingCharacters(in: .whitespacesAndNewlines)
    entries[songID] = LibraryMetadataOverride(
      album: album,
      title: nil,
      artist: (cleanArtist?.isEmpty == false) ? cleanArtist : previous?.artist,
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
      artworkAttempt: Self.artworkAttemptVersion
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
  private var pendingRun: (accountInfo: AccountInfo, album: Album?, limit: Int)?

  private init() {}

  public var isRunning: Bool { activeTask != nil }

  @discardableResult
  public func backfill(
    accountInfo: AccountInfo,
    album: Album? = nil,
    limit: Int = 200
  ) async
    -> BackfillResult {
    if let activeTask {
      // Queue one follow-up pass so newly synced songs arriving during an
      // in-flight backfill are not skipped until the next app launch.
      pendingRun = (accountInfo, album, limit)
      let firstResult = await activeTask.value
      guard let next = pendingRun, self.activeTask == nil else {
        return firstResult
      }
      pendingRun = nil
      return await backfill(
        accountInfo: next.accountInfo,
        album: next.album,
        limit: next.limit
      )
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
            let resolvedArtist = apply(
              match,
              to: song,
              account: account,
              library: library,
              replaceDirtyArtist: true
            )
      else {
        MetadataOverrideStore.shared.recordMiss(for: songID)
        continue
      }
      MetadataOverrideStore.shared.recordMatch(
        album: match.album,
        artist: resolvedArtist,
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

    if matched > 0 {
      FileSourceLibraryWriter.mergeAlbumsByName(account: account, library: library)
    }

    let artworkAdded = await fillMissingArtwork(
      accountInfo: accountInfo,
      account: account,
      library: library,
      limit: limit
    )

    let lyricsAdded = await fillMissingLyrics(
      account: account,
      library: library,
      limit: min(limit, 40)
    )

    if attempted > 0 || artworkAdded > 0 || lyricsAdded > 0 {
      if artworkAdded > 0 {
        ArtworkImageLoader.clearCache()
      }
      FileSourceLibraryWriter.mergeAlbumsByName(account: account, library: library)
      FileSourceLibraryWriter.updateDenormalizedValues(account: account, library: library)
      library.saveContext()
      NotificationCenter.default.post(name: .librarySongsSynced, object: nil)
    }
    os_log(
      "Metadata backfill finished: %d matched, %d attempted, %d covers, %d lyrics",
      log: log,
      type: .info,
      matched,
      attempted,
      artworkAdded,
      lyricsAdded
    )
    return BackfillResult(matched: matched, attempted: attempted)
  }

  /// Automatically backfills online lyrics in the background for songs that
  /// have no local/sidecar lyrics file yet (e.g. newly synced WebDAV tracks).
  private func fillMissingLyrics(
    account: Account,
    library: LibraryStorage,
    limit: Int
  ) async
    -> Int {
    guard limit > 0 else { return 0 }
    var matched = 0
    var attempted = 0
    let missingSongs = library.getSongs(for: account)
      .filter { $0.lyricsRelFilePath == nil && OnlineLyricsService.shared.canMatchLyrics(for: $0) }
    for song in missingSongs {
      if attempted >= limit || Task.isCancelled { break }
      attempted += 1
      if await OnlineLyricsService.shared.matchLyrics(for: song) {
        matched += 1
      }
    }
    return matched
  }

  /// Force-rematches online metadata (album, artist, cover, and missing lyrics)
  /// for a single song and merges its album with any existing album of the same name.
  @discardableResult
  public func rematchMetadata(for song: Song, accountInfo: AccountInfo) async -> Bool {
    let fmusic = FmusicKit.shared
    guard fmusic.settings.user.isOnlineMode,
          fmusic.networkMonitor.isConnectedToNetwork
    else { return false }

    let library = fmusic.storage.main.library
    let account = library.getAccount(info: accountInfo)
    var changed = false

    if let match = await OnlineLyricsService.shared.matchMetadata(
      for: song,
      ignoreExistingAlbum: true
    ),
      let resolvedArtist = apply(
        match,
        to: song,
        account: account,
        library: library,
        replaceDirtyArtist: true,
        forceReplaceArtist: true
      ) {
      MetadataOverrideStore.shared.recordMatch(
        album: match.album,
        artist: resolvedArtist,
        source: match.source.rawValue,
        confidence: match.score,
        for: song.id
      )
      changed = true
      if let targetAlbum = song.album {
        for artworkURL in match.artworkURLs {
          if await applyArtwork(
            artworkURL,
            to: targetAlbum,
            account: account,
            accountInfo: accountInfo,
            library: library,
            overwriteArtistArtwork: true
          ) {
            MetadataOverrideStore.shared.recordAlbumArtwork(artworkURL, for: targetAlbum.id)
            MetadataOverrideStore.shared.recordArtwork(artworkURL, for: song.id)
            break
          }
        }
      }
    } else if let album = song.album, album.managedObject.name != "Unknown Album" {
      let artworkURLs = await OnlineLyricsService.shared.matchArtworkURLs(
        for: song,
        expectedAlbum: album.managedObject.name
      )
      for artworkURL in artworkURLs {
        if await applyArtwork(
          artworkURL,
          to: album,
          account: account,
          accountInfo: accountInfo,
          library: library,
          overwriteArtistArtwork: true
        ) {
          MetadataOverrideStore.shared.recordAlbumArtwork(artworkURL, for: album.id)
          MetadataOverrideStore.shared.recordArtwork(artworkURL, for: song.id)
          changed = true
          break
        }
      }
    }

    if song.lyricsRelFilePath == nil {
      if await OnlineLyricsService.shared.matchLyrics(for: song, force: true) {
        changed = true
      }
    }

    if changed {
      ArtworkImageLoader.clearCache()
      FileSourceLibraryWriter.mergeAlbumsByName(account: account, library: library)
      FileSourceLibraryWriter.updateDenormalizedValues(account: account, library: library)
      library.saveContext()
      NotificationCenter.default.post(name: .librarySongsSynced, object: nil)
    }
    return changed
  }

  /// Force-rematches the online cover for a single album, replacing any
  /// previously downloaded or embedded cover. If no online match is available
  /// and the existing cover is non-standard, normalizes the local cover instead.
  @discardableResult
  public func rematchArtwork(for album: Album, accountInfo: AccountInfo) async -> Bool {
    let fmusic = FmusicKit.shared
    if album.managedObject.name == "Unknown Album" {
      var anyMatched = false
      for song in Array(album.songs.compactMap(\.asSong).prefix(20)) {
        if await rematchMetadata(for: song, accountInfo: accountInfo) {
          anyMatched = true
        }
      }
      return anyMatched
    }
    let candidateSongs = Array(album.songs.compactMap(\.asSong).prefix(3))
    guard !candidateSongs.isEmpty else { return false }
    let library = fmusic.storage.main.library
    let account = library.getAccount(info: accountInfo)
    let existingPath = album.artwork?.imagePath
    let hasNonStandardLocalCover = existingPath.map { !Self.hasStandardSquareCover(atPath: $0) }
      ?? false

    if fmusic.settings.user.isOnlineMode,
       fmusic.networkMonitor.isConnectedToNetwork {
      for candidateSong in candidateSongs {
        let artworkURLs = await OnlineLyricsService.shared.matchArtworkURLs(
          for: candidateSong,
          expectedAlbum: album.managedObject.name
        )
        for artworkURL in artworkURLs {
          if await applyArtwork(
            artworkURL,
            to: album,
            account: account,
            accountInfo: accountInfo,
            library: library,
            overwriteArtistArtwork: true
          ) {
            MetadataOverrideStore.shared.recordAlbumArtwork(artworkURL, for: album.id)
            MetadataOverrideStore.shared.recordArtwork(artworkURL, for: candidateSong.id)
            ArtworkImageLoader.clearCache()
            FileSourceLibraryWriter.updateDenormalizedValues(account: account, library: library)
            library.saveContext()
            NotificationCenter.default.post(name: .librarySongsSynced, object: nil)
            return true
          }
        }
      }
    }

    if hasNonStandardLocalCover,
       let existingPath,
       normalizeExistingArtwork(
         atPath: existingPath,
         for: album,
         account: account,
         accountInfo: accountInfo,
         library: library,
         overwriteArtistArtwork: true
       ) {
      MetadataOverrideStore.shared.recordAlbumArtwork(nil, for: album.id)
      ArtworkImageLoader.clearCache()
      FileSourceLibraryWriter.updateDenormalizedValues(account: account, library: library)
      library.saveContext()
      NotificationCenter.default.post(name: .librarySongsSynced, object: nil)
      return true
    }
    return false
  }

  /// Fetches covers for albums with missing or non-standard (non-square / tiny)
  /// artwork. For non-standard covers, tries online metadata matching for a
  /// standard square cover first, and falls back to center-cropping / scaling
  /// the existing local cover so every album tile stays visually uniform.
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
      guard album.managedObject.name != "Unknown Album" else { continue }
      let songs = album.songs.compactMap(\.asSong)
      guard let song = songs.first else { continue }
      let needsUpgrade = MetadataOverrideStore.shared.hasOutdatedOnlineArtwork(
        forAlbumID: album.id,
        songIDs: songs.map(\.id)
      )
      let existingPath = album.artwork?.imagePath
      if existingPath != nil, let albumArtwork = album.artwork {
        for s in songs where s.artwork?.imagePath == nil {
          s.artwork = albumArtwork
        }
      }
      let hasNonStandardCover = existingPath.map { !Self.hasStandardSquareCover(atPath: $0) }
        ?? false
      guard existingPath == nil || needsUpgrade || hasNonStandardCover else { continue }

      let shouldAttempt = needsUpgrade
        || MetadataOverrideStore.shared.shouldAttemptAlbumArtwork(for: album.id)
        || songs.contains { MetadataOverrideStore.shared.shouldAttemptArtwork(for: $0.id) }
      guard shouldAttempt else { continue }
      attempted += 1

      var matchedURL: URL?
      var matchedSong = song
      for candidateSong in songs.prefix(3) {
        let artworkURLs = await OnlineLyricsService.shared.matchArtworkURLs(
          for: candidateSong,
          expectedAlbum: album.managedObject.name
        )
        for artworkURL in artworkURLs {
          if await applyArtwork(
            artworkURL,
            to: album,
            account: account,
            accountInfo: accountInfo,
            library: library,
            requireStandardSize: hasNonStandardCover
          ) {
            matchedURL = artworkURL
            matchedSong = candidateSong
            break
          }
        }
        if matchedURL != nil { break }
      }

      if let matchedURL {
        MetadataOverrideStore.shared.recordAlbumArtwork(matchedURL, for: album.id)
        MetadataOverrideStore.shared.recordArtwork(matchedURL, for: matchedSong.id)
        added += 1
        continue
      }

      if hasNonStandardCover,
         let existingPath,
         normalizeExistingArtwork(
           atPath: existingPath,
           for: album,
           account: account,
           accountInfo: accountInfo,
           library: library
         ) {
        MetadataOverrideStore.shared.recordAlbumArtwork(nil, for: album.id)
        MetadataOverrideStore.shared.recordArtwork(nil, for: song.id)
        added += 1
        continue
      }

      MetadataOverrideStore.shared.recordAlbumArtwork(nil, for: album.id)
      MetadataOverrideStore.shared.recordArtwork(nil, for: song.id)
    }
    return added
  }

  private func applyArtwork(
    _ url: URL,
    to album: Album,
    account: Account,
    accountInfo: AccountInfo,
    library: LibraryStorage,
    overwriteArtistArtwork: Bool = false,
    requireStandardSize: Bool = false
  ) async
    -> Bool {
    guard let data = await Self.downloadArtwork(url) else { return false }
    let size = ArtworkImageEncoder.pixelSize(from: data)
    let isStandard = size.map(ArtworkImageEncoder.isStandardSquareCover) ?? false
    if requireStandardSize, !isStandard {
      return false
    }
    let encoded = isStandard
      ? Self.resizedArtwork(data)
      : ArtworkImageEncoder.normalizedSquareData(from: data)
    guard let encoded else { return false }
    return storeArtworkData(
      encoded,
      to: album,
      account: account,
      accountInfo: accountInfo,
      library: library,
      overwriteArtistArtwork: overwriteArtistArtwork
    )
  }

  private func normalizeExistingArtwork(
    atPath path: String,
    for album: Album,
    account: Account,
    accountInfo: AccountInfo,
    library: LibraryStorage,
    overwriteArtistArtwork: Bool = false
  )
    -> Bool {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let normalized = ArtworkImageEncoder.normalizedSquareData(from: data)
    else { return false }
    return storeArtworkData(
      normalized,
      to: album,
      account: account,
      accountInfo: accountInfo,
      library: library,
      overwriteArtistArtwork: overwriteArtistArtwork
    )
  }

  private func storeArtworkData(
    _ encoded: Data,
    to album: Album,
    account: Account,
    accountInfo: AccountInfo,
    library: LibraryStorage,
    overwriteArtistArtwork: Bool = false
  )
    -> Bool {
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
    if overwriteArtistArtwork || album.artist?.artwork?.imagePath == nil {
      album.artist?.artwork = artwork
    }
    album.songs.forEach { $0.artwork = artwork }
    return true
  }

  private static func hasStandardSquareCover(atPath path: String) -> Bool {
    guard let size = ArtworkImageEncoder.pixelSize(atPath: path) else { return false }
    return ArtworkImageEncoder.isStandardSquareCover(size)
  }

  private static func sameAlbum(_ lhs: String, _ rhs: String?) -> Bool {
    guard let rhs else { return false }
    let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
    let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
    return !left.isEmpty && left.compare(right, options: .caseInsensitive) == .orderedSame
  }

  private static func downloadArtwork(_ url: URL) async -> Data? {
    guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
      return nil
    }
    var secureURL = url
    if scheme == "http", var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
      components.scheme = "https"
      secureURL = components.url ?? url
    }
    var request = URLRequest(url: secureURL)
    request.timeoutInterval = 12
    request.setValue("image/*", forHTTPHeaderField: "Accept")
    request.setValue(
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
      forHTTPHeaderField: "User-Agent"
    )
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
    library: LibraryStorage,
    replaceDirtyArtist: Bool = false,
    forceReplaceArtist: Bool = false
  )
    -> String? {
    guard let scope = Self.idScope(for: song) else { return nil }
    let albumName = match.album.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !albumName.isEmpty else { return nil }

    let oldAlbum = song.album
    let oldArtist = song.artist

    var resolvedArtistName: String?
    let currentArtistName = oldArtist?.managedObject.name?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let isDirtyArtist = currentArtistName.isEmpty
      || currentArtistName == "Unknown Artist"
      || currentArtistName == "未知艺人"
      || currentArtistName.contains("[")
      || currentArtistName.contains("(")
      || currentArtistName.contains("【")
    let candidateArtist = match.artist.trimmingCharacters(in: .whitespacesAndNewlines)
    if !candidateArtist.isEmpty, (forceReplaceArtist || (replaceDirtyArtist && isDirtyArtist)) {
      let artistKey = candidateArtist.lowercased()
      let artistID = FileSourceLibraryWriter.stableID(
        prefix: "\(scope)_artist_",
        value: artistKey
      )
      let artist = library.getArtists(for: account)
        .first { $0.id == artistID || $0.name.caseInsensitiveCompare(candidateArtist) == .orderedSame }
        ?? {
          let created = library.createArtist(account: account)
          created.id = artistID
          created.name = candidateArtist
          created.remoteStatus = .available
          return created
        }()
      song.artist = artist
      resolvedArtistName = artist.name
    }

    let albumKey = FileSourceLibraryWriter.albumKey(
      albumName: albumName,
      fallbackDirectoryPath: ""
    )
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
    if album.artist == nil || album.artist?.managedObject.name == "Unknown Artist" {
      album.artist = song.artist
    }
    song.album = album
    if let albumArtwork = album.artwork, albumArtwork.imagePath != nil {
      song.artwork = albumArtwork
    } else if oldAlbum?.managedObject.name == "Unknown Album" {
      song.artwork = nil
    }

    if let oldAlbum, oldAlbum.managedObject.objectID != album.managedObject.objectID {
      if oldAlbum.managedObject.name == "Unknown Album" {
        oldAlbum.artwork = nil
      }
      if oldAlbum.songs.isEmpty {
        library.deleteAlbum(album: oldAlbum)
      }
    }
    if let oldArtist,
       oldArtist.managedObject.objectID != song.artist?.managedObject.objectID,
       oldArtist.albums.isEmpty && oldArtist.songs.isEmpty {
      library.deleteArtist(artist: oldArtist)
    }

    return resolvedArtistName ?? song.artist?.name
  }

  private static func idScope(for song: Song) -> String? {
    if let album = song.album {
      if album.id.hasPrefix("webdav_album_") { return "webdav" }
      if album.id.hasPrefix("local_album_") { return "local" }
    }
    if song.id.hasPrefix("webdav_song_") { return "webdav" }
    if song.id.hasPrefix("local_song_") { return "local" }
    return nil
  }
}
