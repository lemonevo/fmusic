//
//  WebDAVLibraryIndexer.swift
//  AmperfyKit
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import AVFoundation
import CoreData
import Foundation
import os.log

// MARK: - WebDAVFileItem

private struct WebDAVFileItem: Sendable {
  let remotePath: String
  let songID: String
  let albumID: String
  let title: String
  let artistName: String
  let albumName: String
  let genreName: String?
  let year: Int
  let track: Int
  let duration: Int
  let size: Int
  let bitrate: Int
  let contentType: String
  var artwork: Data?
  let lyrics: String?
  let addedDate: Date
}

extension WebDAVFileItem: FileSourceMediaItem {
  var playablePath: String { remotePath }
  var localFileURL: URL? { nil }
  var idScope: String { "webdav" }
}

private struct ExistingFileInfo: Sendable {
  let size: Int
  let lastModified: Date
}

// MARK: - WebDAVLibraryIndexer

@MainActor
final class WebDAVLibraryIndexer: LibrarySyncer {
  nonisolated private static let audioExtensions: Set<String> = [
    "flac", "mp3", "m4a", "mp4", "aac", "wav", "aiff", "aif", "ogg", "oga", "opus",
  ]
  nonisolated private static let coverFileNames = [
    "cover.jpg", "cover.jpeg", "cover.png",
    "folder.jpg", "folder.jpeg", "folder.png",
    "front.jpg", "front.jpeg", "front.png",
  ]
  nonisolated private static let metadataHeadBytes = 2 * 1024 * 1024
  nonisolated private static let maximumEntryCount = 100_000
  /// Bump when indexing or metadata parsing changes so unchanged files are re-read once.
  nonisolated private static let indexVersion = 3
  nonisolated private static let metadataFetchConcurrency = 6

  private let accountObjectId: NSManagedObjectID
  private let accountInfo: AccountInfo
  private let storage: PersistentStorage
  private let credentials: LoginCredentials?
  private let log = OSLog(subsystem: "Amperfy", category: "WebDAVLibraryIndexer")

  init(account: Account, storage: PersistentStorage, credentials: LoginCredentials?) {
    self.accountObjectId = account.managedObject.objectID
    self.accountInfo = account.info
    self.storage = storage
    self.credentials = credentials
  }

  func requestSimilarSongs(song: Song, count: Int) async throws -> [Song] {
    let account = storage.main.library.getAccount(info: accountInfo)
    return storage.main.library.getSimilarSongs(for: account, to: song, count: count)
  }

  func syncInitial(statusNotifyier: SyncCallbacks?) async throws {
    let syncStart = Date()
    guard let credentials,
          let baseURL = URL(string: credentials.activeBackendServerUrl)
    else { throw WebDAVError.invalidBaseURL }
    let client = WebDAVClient(baseURL: baseURL, credentials: credentials)

    os_log("WebDAV indexing started: %s", log: log, type: .info, baseURL.absoluteString)
    let entries = try await Self.enumerate(client: client, limit: Self.maximumEntryCount)
    let reachedEntryLimit = entries.count >= Self.maximumEntryCount
    let filesByPath = Dictionary(
      entries.filter { !$0.isDirectory }.map { ($0.relativePath, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    let audioFiles = entries
      .filter { !$0.isDirectory && Self.audioExtensions.contains($0.fileExtension) }
      .sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }

    statusNotifyier?.notifySyncStarted(ofType: .song, totalCount: audioFiles.count)

    let accountObjectId = accountObjectId
    let accountInfo = accountInfo
    let isIncremental = storage.settings.accounts.getSetting(accountInfo).read
      .libraryIndexVersion == Self.indexVersion
    let existingFiles: [String: ExistingFileInfo]
    if isIncremental {
      existingFiles = try await storage.async.performAndGet { asyncCompanion in
        let account = asyncCompanion.library.getAccount(managedObjectId: accountObjectId)
        var result = [String: ExistingFileInfo]()
        for song in asyncCompanion.library.getSongs(for: account) {
          guard let url = song.url, let addedDate = song.addedDate else { continue }
          result[url] = ExistingFileInfo(size: song.size, lastModified: addedDate)
        }
        return result
      }
    } else {
      existingFiles = [:]
    }

    var filesToRead = [WebDAVEntry]()
    filesToRead.reserveCapacity(audioFiles.count)
    for file in audioFiles {
      if let existing = existingFiles[file.relativePath],
         existing.size == file.size,
         let lastModified = file.lastModified,
         abs(existing.lastModified.timeIntervalSince(lastModified)) < 1 {
        statusNotifyier?.notifyParsedObject(ofType: .song)
      } else {
        filesToRead.append(file)
      }
    }
    os_log(
      "WebDAV index: %d unchanged, %d to read (incremental: %d, existing: %d)",
      log: log,
      type: .info,
      audioFiles.count - filesToRead.count,
      filesToRead.count,
      isIncremental ? 1 : 0,
      existingFiles.count
    )

    var coverDataByDirectory = [String: Data]()
    for directory in Set(filesToRead.map(\.directoryPath)) {
      if let cover = await Self.fetchCover(
        directory: directory,
        filesByPath: filesByPath,
        client: client
      ) {
        coverDataByDirectory[directory] = cover
      }
    }

    var items = [WebDAVFileItem]()
    items.reserveCapacity(filesToRead.count)
    var artworkAlbumIDs = Set<String>()
    let rootAlbumName = baseURL.lastPathComponent
    let coverDataSnapshot = coverDataByDirectory
    let filesByPathSnapshot = filesByPath
    var start = 0
    while start < filesToRead.count {
      let end = min(start + Self.metadataFetchConcurrency, filesToRead.count)
      let batch = Array(filesToRead[start ..< end])
      let baseIndex = start
      let results = await withTaskGroup(
        of: (Int, WebDAVFileItem?).self
      ) { group -> [(Int, WebDAVFileItem?)] in
        for (offset, file) in batch.enumerated() {
          group.addTask {
            let item = await Self.read(
              entry: file,
              filesByPath: filesByPathSnapshot,
              rootAlbumName: rootAlbumName,
              coverData: coverDataSnapshot[file.directoryPath],
              client: client
            )
            return (baseIndex + offset, item)
          }
        }
        var collected = [(Int, WebDAVFileItem?)]()
        collected.reserveCapacity(batch.count)
        for await result in group { collected.append(result) }
        return collected.sorted { $0.0 < $1.0 }
      }
      for (_, result) in results {
        guard var item = result else {
          statusNotifyier?.notifyParsedObject(ofType: .song)
          continue
        }
        // Keep one artwork copy per album instead of one per song.
        if item.artwork != nil, !artworkAlbumIDs.insert(item.albumID).inserted {
          item.artwork = nil
        }
        items.append(item)
        statusNotifyier?.notifyParsedObject(ofType: .song)
      }
      start = end
    }

    let itemsToWrite = items
    let activeSongPaths = Set(audioFiles.map(\.relativePath))
    let cacheFileManager = CacheFileManager.shared
    try await storage.async.perform { asyncCompanion in
      let account = asyncCompanion.library.getAccount(managedObjectId: accountObjectId)
      FileSourceLibraryWriter.write(
        items: itemsToWrite,
        account: account,
        accountInfo: accountInfo,
        library: asyncCompanion.library,
        cacheFileManager: cacheFileManager
      )
      if !audioFiles.isEmpty, !reachedEntryLimit {
        FileSourceLibraryWriter.removeStaleEntries(
          library: asyncCompanion.library,
          account: account,
          activeSongPaths: activeSongPaths,
          cacheFileManager: cacheFileManager
        )
      }
      FileSourceLibraryWriter.updateDenormalizedValues(
        account: account,
        library: asyncCompanion.library
      )
      asyncCompanion.saveContext()
    }
    storage.settings.accounts.updateSetting(accountInfo) { accountSettings in
      accountSettings.libraryIndexVersion = Self.indexVersion
    }
    os_log(
      "WebDAV indexing finished: %d songs in %.1fs",
      log: log,
      type: .info,
      itemsToWrite.count,
      Date().timeIntervalSince(syncStart)
    )
  }

  // MARK: Enumeration

  private nonisolated static func enumerate(
    client: WebDAVClient,
    limit: Int
  ) async throws
    -> [WebDAVEntry] {
    var level = [""]
    var visited = Set<String>()
    var entries = [WebDAVEntry]()

    while !level.isEmpty {
      var nextLevel = [String]()
      var index = 0
      while index < level.count {
        let end = min(index + Self.metadataFetchConcurrency, level.count)
        let batch = Array(level[index ..< end])
        let responses = try await withThrowingTaskGroup(
          of: [WebDAVEntry].self
        ) { group -> [[WebDAVEntry]] in
          for directory in batch {
            group.addTask {
              try await client.propfind(relativePath: directory, depth: 1)
            }
          }
          var collected = [[WebDAVEntry]]()
          collected.reserveCapacity(batch.count)
          for try await response in group { collected.append(response) }
          return collected
        }
        for response in responses {
          for entry in response {
            entries.append(entry)
            if entry.isDirectory, !entry.relativePath.isEmpty,
               visited.insert(entry.relativePath).inserted {
              nextLevel.append(entry.relativePath)
            }
          }
        }
        if entries.count >= limit { return entries }
        index = end
      }
      level = nextLevel
    }
    return entries
  }

  private nonisolated static func fetchCover(
    directory: String,
    filesByPath: [String: WebDAVEntry],
    client: WebDAVClient
  ) async
    -> Data? {
    for coverName in coverFileNames {
      let path = directory.isEmpty ? coverName : "\(directory)/\(coverName)"
      guard filesByPath[path] != nil else { continue }
      if let data = try? await client.fetchData(relativePath: path), !data.isEmpty {
        return data
      }
    }
    return nil
  }

  // MARK: Metadata

  private nonisolated static func read(
    entry: WebDAVEntry,
    filesByPath: [String: WebDAVEntry],
    rootAlbumName: String,
    coverData: Data?,
    client: WebDAVClient
  ) async
    -> WebDAVFileItem? {
    let extensionName = entry.fileExtension
    guard !extensionName.isEmpty,
          let headData = try? await client.fetchData(
            relativePath: entry.relativePath,
            range: 0 ... (metadataHeadBytes - 1)
          ),
          !headData.isEmpty
    else { return nil }

    var flacTags: FlacTags?
    var mp3Tags: MP3Tags?
    var avDuration = 0
    let temporaryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension(extensionName)
    defer { try? FileManager.default.removeItem(at: temporaryURL) }
    if (try? headData.write(to: temporaryURL)) != nil {
      if extensionName == "flac" {
        flacTags = FlacTagReader.read(url: temporaryURL)
      } else if extensionName == "mp3" {
        mp3Tags = MP3TagReader.read(url: temporaryURL)
      }
      if flacTags?.duration == nil {
        let asset = AVURLAsset(url: temporaryURL)
        if let duration = try? await asset.load(.duration) {
          let seconds = CMTimeGetSeconds(duration)
          if seconds.isFinite, seconds > 0 { avDuration = Int(seconds.rounded()) }
        }
      }
    }

    let duration = flacTags?.duration ?? avDuration
    let fileName = entry.fileNameWithoutExtension
    let (trackFromName, nameWithoutTrack) = trackNumber(from: fileName)
    let nameParts = nameWithoutTrack.components(separatedBy: " - ")
    let title = flacTags?.title ?? mp3Tags?.title
      ?? (nameParts.count >= 2 ? nameParts.dropFirst().joined(separator: " - ") : nameWithoutTrack)
    let artistName = flacTags?.artist ?? mp3Tags?.artist
      ?? (nameParts.count >= 2 ? nameParts.first! : "Unknown Artist")
    let directoryName = entry.directoryPath.isEmpty
      ? rootAlbumName
      : (entry.directoryPath as NSString).lastPathComponent
    let albumTag = flacTags?.album ?? mp3Tags?.album
    let albumName = albumTag ?? directoryName
    let albumKey: String
    if let albumTag, !albumTag.isEmpty {
      let albumArtist = flacTags?.albumArtist ?? mp3Tags?.albumArtist ?? artistName
      albumKey = "tag:\(albumArtist.lowercased())\u{1F}\(albumTag.lowercased())"
    } else {
      albumKey = "path:\(entry.directoryPath)"
    }
    let mimeType = MimeFileConverter.convertToValidMimeTypeWhenNeccessary(
      mimeType: entry.contentType
        ?? MimeFileConverter.getMIMEType(filenameExtension: extensionName)
        ?? "application/octet-stream"
    )
    let bitrate = duration > 0 ? (entry.size * 8) / duration : 0

    let lyrics = await fetchLyrics(
      entry: entry,
      filesByPath: filesByPath,
      client: client
    ) ?? flacTags?.lyrics ?? mp3Tags?.lyrics
    let artwork = flacTags?.picture ?? mp3Tags?.picture ?? coverData

    return WebDAVFileItem(
      remotePath: entry.relativePath,
      songID: FileSourceLibraryWriter.stableID(prefix: "webdav_song_", value: entry.relativePath),
      albumID: FileSourceLibraryWriter.stableID(prefix: "webdav_album_", value: albumKey),
      title: title,
      artistName: artistName,
      albumName: albumName,
      genreName: flacTags?.genre ?? mp3Tags?.genre,
      year: flacTags?.year ?? mp3Tags?.year ?? 0,
      track: flacTags?.track ?? mp3Tags?.track ?? trackFromName,
      duration: duration,
      size: entry.size,
      bitrate: bitrate,
      contentType: mimeType,
      artwork: artwork,
      lyrics: lyrics,
      addedDate: entry.lastModified ?? Date()
    )
  }

  private nonisolated static func fetchLyrics(
    entry: WebDAVEntry,
    filesByPath: [String: WebDAVEntry],
    client: WebDAVClient
  ) async
    -> String? {
    let base = entry.directoryPath.isEmpty
      ? entry.fileNameWithoutExtension
      : "\(entry.directoryPath)/\(entry.fileNameWithoutExtension)"
    for candidate in [
      "\(base).yrc", "\(base).YRC", "\(base).lrc", "\(base).LRC",
    ] {
      guard filesByPath[candidate] != nil else { continue }
      if let data = try? await client.fetchData(relativePath: candidate),
         let content = String(data: data, encoding: .utf8),
         !content.isEmpty {
        return content
      }
    }
    return nil
  }

  private nonisolated static func trackNumber(from fileName: String) -> (Int, String) {
    let trimmed = fileName.trimmingCharacters(in: .whitespaces)
    let digits = trimmed.prefix { $0.isNumber }
    guard !digits.isEmpty, let number = Int(digits) else { return (0, trimmed) }
    var rest = trimmed.dropFirst(digits.count)
    while let first = rest.first, first == "." || first == "-" || first == "_" || first == " " {
      rest = rest.dropFirst()
    }
    return (number, String(rest))
  }

}
