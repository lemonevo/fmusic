//
//  LocalLibraryIndexer.swift
//  fmusicKit
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
import UniformTypeIdentifiers

// MARK: - LocalFileItem

private struct LocalFileItem: Sendable {
  let url: URL
  let relativePath: String
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

// MARK: FileSourceMediaItem

extension LocalFileItem: FileSourceMediaItem {
  var playablePath: String { relativePath }
  var localFileURL: URL? { url }
  var idScope: String { "local" }
}

// MARK: - FileSourceMetadata

struct FileSourceMetadata: Sendable {
  let title: String
  let artistName: String
  let albumName: String
  let albumKey: String
  let genreName: String?
  let year: Int
  let track: Int
  let duration: Int
  let size: Int
  let bitrate: Int
  let contentType: String
  let artwork: Data?
  let lyrics: String?
  let addedDate: Date
}

// MARK: - FileSourceMetadataReader

/// Reads tags and file attributes for folder indexers and single-file import.
enum FileSourceMetadataReader {
  nonisolated static func read(
    fileURL: URL,
    rootURL: URL,
    folderArtwork: Data?
  ) async
    -> FileSourceMetadata? {
    let extensionName = fileURL.pathExtension.lowercased()
    let flacTags = extensionName == "flac" ? FlacTagReader.read(url: fileURL) : nil
    let mp3Tags = extensionName == "mp3" ? MP3TagReader.read(url: fileURL) : nil

    var metadataTitle: String?
    var metadataArtist: String?
    var metadataAlbum: String?
    var artworkData: Data?
    var avDurationSeconds = 0

    if flacTags != nil || mp3Tags != nil {
      // FLAC carries its duration in STREAMINFO; MP3 still needs AVFoundation.
      if flacTags?.duration == nil {
        avDurationSeconds = await mediaDurationSeconds(of: fileURL) ?? 0
      }
    } else {
      let asset = AVURLAsset(url: fileURL)
      let commonMetadata = (try? await asset.load(.commonMetadata)) ?? []
      metadataTitle = stringValue(in: commonMetadata, identifier: .commonIdentifierTitle)
      metadataArtist = stringValue(in: commonMetadata, identifier: .commonIdentifierArtist)
      metadataAlbum = stringValue(in: commonMetadata, identifier: .commonIdentifierAlbumName)
      artworkData = AVMetadataItem.metadataItems(
        from: commonMetadata,
        filteredByIdentifier: .commonIdentifierArtwork
      ).first?.dataValue
      avDurationSeconds = await mediaDurationSeconds(asset: asset) ?? 0
    }
    let durationSeconds = flacTags?.duration ?? avDurationSeconds

    let values = try? fileURL.resourceValues(
      forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey]
    )
    let size = values?.fileSize ?? 0
    let bitrate = durationSeconds > 0 ? (size * 8) / durationSeconds : 0
    let addedDate = values?.creationDate ?? values?.contentModificationDate ?? Date()

    let lyrics = sidecarLyrics(for: fileURL) ?? flacTags?.lyrics ?? mp3Tags?.lyrics
    let lyricTags = lyrics.map(LyricMetadataTags.parse)

    let fileName = fileURL.deletingPathExtension().lastPathComponent
    let (trackFromName, nameWithoutTrack) = trackNumber(from: fileName)
    let nameParts = nameWithoutTrack.components(separatedBy: " - ")
    let tagTitle = LyricMetadataTags
      .firstNonEmpty(flacTags?.title, mp3Tags?.title, metadataTitle)
    // User libraries name files "Title - Artist"; this fork previously assumed
    // the reverse and swapped every untagged song.
    let title = tagTitle ?? lyricTags?.title
      ?? (nameParts.count >= 2 ? nameParts.first! : nameWithoutTrack)
    let tagArtist = LyricMetadataTags
      .firstNonEmpty(flacTags?.artist, mp3Tags?.artist, metadataArtist)
    let artistName = tagArtist ?? lyricTags?.artist
      ?? (nameParts.count >= 2 ? nameParts.dropFirst().joined(separator: " - ") : "Unknown Artist")
    let albumFolderURL = fileURL.deletingLastPathComponent()
    let albumTag = LyricMetadataTags
      .firstNonEmpty(flacTags?.album, mp3Tags?.album, metadataAlbum)
    let albumName = albumTag ?? lyricTags?.album
      ?? (
        albumFolderURL.standardizedFileURL.path == rootURL.standardizedFileURL.path
          ? "Unknown Album"
          : albumFolderURL.lastPathComponent
      )
    let albumFolderKey = relativePath(of: albumFolderURL, rootURL: rootURL)
    let albumKey = FileSourceLibraryWriter.albumKey(
      albumName: albumTag ?? lyricTags?.album,
      fallbackDirectoryPath: albumFolderKey
    )
    let mimeType = MimeFileConverter.convertToValidMimeTypeWhenNeccessary(
      mimeType: MimeFileConverter.getMIMEType(filenameExtension: extensionName)
        ?? "application/octet-stream"
    )

    // Compress while reading: the items array lives until the whole folder has
    // been read, so multi-megabyte embedded covers would otherwise pile up in memory.
    // Folder covers arrive already compressed from folderArtwork(in:).
    let tagArtwork = flacTags?.picture ?? mp3Tags?.picture ?? artworkData
    let artwork = tagArtwork.map(ArtworkImageEncoder.compressedData(from:)) ?? folderArtwork

    return FileSourceMetadata(
      title: title,
      artistName: artistName,
      albumName: albumName,
      albumKey: albumKey,
      genreName: flacTags?.genre ?? mp3Tags?.genre,
      year: flacTags?.year ?? mp3Tags?.year ?? 0,
      track: flacTags?.track ?? mp3Tags?.track ?? trackFromName,
      duration: durationSeconds,
      size: size,
      bitrate: bitrate,
      contentType: mimeType,
      artwork: artwork,
      lyrics: lyrics,
      addedDate: addedDate
    )
  }

  nonisolated static func relativePath(of url: URL, rootURL: URL) -> String {
    let rootPath = rootURL.standardizedFileURL.path
    let path = url.standardizedFileURL.path
    if path == rootPath { return "" }
    guard path.hasPrefix(rootPath + "/") else { return "" }
    return String(path.dropFirst(rootPath.count + 1))
  }

  nonisolated private static func mediaDurationSeconds(of fileURL: URL) async -> Int? {
    await mediaDurationSeconds(asset: AVURLAsset(url: fileURL))
  }

  nonisolated private static func mediaDurationSeconds(asset: AVURLAsset) async -> Int? {
    guard let duration = try? await asset.load(.duration) else { return nil }
    let seconds = CMTimeGetSeconds(duration)
    guard seconds.isFinite, seconds > 0 else { return nil }
    return Int(seconds.rounded())
  }

  nonisolated private static func stringValue(
    in metadata: [AVMetadataItem],
    identifier: AVMetadataIdentifier
  )
    -> String? {
    guard let item = AVMetadataItem.metadataItems(
      from: metadata,
      filteredByIdentifier: identifier
    ).first else { return nil }
    if let string = item.stringValue, !string.isEmpty { return string }
    if let value = item.value as? String, !value.isEmpty { return value }
    return nil
  }

  nonisolated private static func trackNumber(from fileName: String) -> (Int, String) {
    let trimmed = fileName.trimmingCharacters(in: .whitespaces)
    let digits = trimmed.prefix { $0.isNumber }
    guard !digits.isEmpty, let number = Int(digits) else { return (0, trimmed) }
    var rest = trimmed.dropFirst(digits.count)
    while let first = rest.first, first == "." || first == "-" || first == "_" || first == " " {
      rest = rest.dropFirst()
    }
    return (number, String(rest))
  }

  nonisolated private static func sidecarLyrics(for fileURL: URL) -> String? {
    for pathExtension in ["yrc", "qrc", "krc", "lrc"] {
      let lyricsURL = fileURL.deletingPathExtension().appendingPathExtension(pathExtension)
      if let data = try? Data(contentsOf: lyricsURL),
         let content = LyricsSidecarReader.text(from: data),
         !content.isEmpty {
        return content
      }
    }
    return nil
  }
}

// MARK: - LocalLibraryIndexer

@MainActor
final class LocalLibraryIndexer: LibrarySyncer {
  nonisolated static let audioExtensions: Set<String> = [
    "flac", "mp3", "m4a", "mp4", "aac", "wav", "aiff", "aif", "ogg", "oga", "opus",
  ]
  nonisolated private static let coverFileNames = [
    "cover.jpg", "cover.jpeg", "cover.png",
    "folder.jpg", "folder.jpeg", "folder.png",
    "front.jpg", "front.jpeg", "front.png",
  ]

  private let accountObjectId: NSManagedObjectID
  private let accountInfo: AccountInfo
  private let storage: PersistentStorage
  private let credentials: LoginCredentials?
  private let log = OSLog(subsystem: "fmusic", category: "LocalLibraryIndexer")

  init(account: Account, storage: PersistentStorage, credentials: LoginCredentials?) {
    self.accountObjectId = account.managedObject.objectID
    self.accountInfo = account.info
    self.storage = storage
    self.credentials = credentials
  }

  // MARK: LibrarySyncer

  func requestSimilarSongs(song: Song, count: Int) async throws -> [Song] {
    let account = storage.main.library.getAccount(info: accountInfo)
    return storage.main.library.getSimilarSongs(for: account, to: song, count: count)
  }

  private static var activeIndexTasks = [AccountInfo: Task<(), Error>]()

  func syncInitial(statusNotifyier: SyncCallbacks?) async throws {
    if let existingTask = Self.activeIndexTasks[accountInfo] {
      try await existingTask.value
      return
    }
    let accountInfo = accountInfo
    let indexTask = Task { [weak self] in
      guard let self else { return }
      try await performIndexing(statusNotifyier: statusNotifyier)
    }
    Self.activeIndexTasks[accountInfo] = indexTask
    defer { Self.activeIndexTasks.removeValue(forKey: accountInfo) }
    try await indexTask.value
  }

  private func performIndexing(statusNotifyier: SyncCallbacks?) async throws {
    guard let credentials else { throw LocalFolderError.noFolderSelected }
    let folderURL = try LocalFolderAccess.shared.activate(credentials: credentials)
    // Directory enumeration hits the filesystem for every entry; keep it off the
    // main actor so the UI stays responsive while a large folder is scanned.
    let files = await Task.detached(priority: .utility) {
      Self.audioFiles(in: folderURL)
    }.value

    os_log(
      "Local indexing started: %d files in %s",
      log: log,
      type: .info,
      files.count,
      folderURL.path
    )
    statusNotifyier?.notifySyncStarted(ofType: .song, totalCount: files.count)

    var items = [LocalFileItem]()
    items.reserveCapacity(files.count)
    var artworkAlbumIDs = Set<String>()
    // One cover read per folder instead of once per track in that folder.
    let folderArtwork = await Self.folderArtworkMap(
      for: Set(files.map { $0.deletingLastPathComponent() })
    )
    for fileURL in files {
      guard var item = await Self.read(
        fileURL: fileURL,
        rootURL: folderURL,
        folderArtwork: folderArtwork[fileURL.deletingLastPathComponent().path]
      )
      else {
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

    let itemsToWrite = items
    let activeSongPaths = Set(
      files.map { FileSourceMetadataReader.relativePath(of: $0, rootURL: folderURL) }
    )
    let accountObjectId = accountObjectId
    let accountInfo = accountInfo
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
      if !files.isEmpty {
        FileSourceLibraryWriter.removeStaleEntries(
          library: asyncCompanion.library,
          account: account,
          activeSongPaths: activeSongPaths,
          cacheFileManager: cacheFileManager
        )
      }
      FileSourceLibraryWriter.mergeAlbumsByName(
        account: account,
        library: asyncCompanion.library
      )
      FileSourceLibraryWriter.deduplicateSongs(
        account: account,
        library: asyncCompanion.library
      )
      FileSourceLibraryWriter.updateDenormalizedValues(
        account: account,
        library: asyncCompanion.library
      )
      asyncCompanion.saveContext()
    }
    os_log("Local indexing finished: %d songs", log: log, type: .info, itemsToWrite.count)
    Task { @MainActor [accountInfo] in
      await MetadataBackfillService.shared.backfill(accountInfo: accountInfo)
    }
  }

  // MARK: Helpers

  nonisolated private static func audioFiles(in folderURL: URL) -> [URL] {
    guard let enumerator = FileManager.default.enumerator(
      at: folderURL,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles, .skipsPackageDescendants]
    ) else { return [] }

    var files = [URL]()
    for case let url as URL in enumerator {
      guard audioExtensions.contains(url.pathExtension.lowercased()),
            (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
      else { continue }
      files.append(url)
    }
    return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
  }

  nonisolated private static func read(
    fileURL: URL,
    rootURL: URL,
    folderArtwork: Data?
  ) async
    -> LocalFileItem? {
    let songRelativePath = FileSourceMetadataReader.relativePath(of: fileURL, rootURL: rootURL)
    guard !songRelativePath.isEmpty,
          let metadata = await FileSourceMetadataReader.read(
            fileURL: fileURL,
            rootURL: rootURL,
            folderArtwork: folderArtwork
          )
    else { return nil }

    return LocalFileItem(
      url: fileURL,
      relativePath: songRelativePath,
      songID: FileSourceLibraryWriter.stableID(prefix: "local_song_", value: songRelativePath),
      albumID: FileSourceLibraryWriter.stableID(
        prefix: "local_album_",
        value: metadata.albumKey
      ),
      title: metadata.title,
      artistName: metadata.artistName,
      albumName: metadata.albumName,
      genreName: metadata.genreName,
      year: metadata.year,
      track: metadata.track,
      duration: metadata.duration,
      size: metadata.size,
      bitrate: metadata.bitrate,
      contentType: metadata.contentType,
      artwork: metadata.artwork,
      lyrics: metadata.lyrics,
      addedDate: metadata.addedDate
    )
  }

  nonisolated private static func folderArtworkMap(
    for folders: Set<URL>
  ) async
    -> [String: Data] {
    var result = [String: Data]()
    for folder in folders {
      if let data = folderArtwork(in: folder) {
        result[folder.path] = data
      }
    }
    return result
  }

  nonisolated static func folderArtwork(in folderURL: URL) -> Data? {
    for coverName in coverFileNames {
      let coverURL = folderURL.appendingPathComponent(coverName)
      if let data = try? Data(contentsOf: coverURL), !data.isEmpty {
        // One compressed copy per folder; every song in it shares this data.
        return ArtworkImageEncoder.compressedData(from: data)
      }
    }
    return nil
  }
}
