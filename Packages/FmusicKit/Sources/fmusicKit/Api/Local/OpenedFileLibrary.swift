//
//  OpenedFileLibrary.swift
//  fmusicKit
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import Foundation
import os.log

// MARK: - OpenedFileSource

enum OpenedFileSource {
  private static let schemePrefix = "fmusic-file://"

  static func urlString(for fileURL: URL) -> String {
    schemePrefix + fileURL.standardizedFileURL.path
  }

  static func isOpenedFileURL(_ urlString: String?) -> Bool {
    urlString?.hasPrefix(schemePrefix) == true
  }

  static func fileURL(from urlString: String?) -> URL? {
    guard let urlString, isOpenedFileURL(urlString) else { return nil }
    return URL(fileURLWithPath: String(urlString.dropFirst(schemePrefix.count)))
  }
}

// MARK: - OpenedFileError

public enum OpenedFileError: LocalizedError {
  case noActiveAccount
  case unsupportedFile(String)
  case unreadableFile(String)

  public var errorDescription: String? {
    switch self {
    case .noActiveAccount:
      return L10n.tr("Add a local folder or WebDAV source before opening a file.")
    case let .unsupportedFile(name):
      return L10n.tr("Unsupported audio file: %@", name)
    case let .unreadableFile(name):
      return L10n.tr("The audio file could not be read: %@", name)
    }
  }
}

// MARK: - SingleFileItem

private struct SingleFileItem: FileSourceMediaItem {
  let fileURL: URL
  let playablePathValue: String
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
  let artwork: Data?
  let lyrics: String?
  let addedDate: Date
  let idScopeValue: String

  var playablePath: String { playablePathValue }
  var localFileURL: URL? { fileURL }
  var idScope: String { idScopeValue }
}

// MARK: - OpenedFileBookmarkStore

final class OpenedFileBookmarkStore: @unchecked Sendable {
  static let shared = OpenedFileBookmarkStore()

  private struct Record: Codable {
    let path: String
    let bookmark: Data
  }

  private let lock = NSLock()
  private var bookmarks = [String: Data]()
  private var activeURLs = [String: URL]()
  private let storeURL: URL?
  private let log = OSLog(subsystem: "fmusic", category: "OpenedFileBookmarkStore")

  private init() {
    if let directory = CacheFileManager.shared.getfmusicPath() {
      self.storeURL = URL(fileURLWithPath: directory)
        .appendingPathComponent("opened-file-bookmarks.json")
    } else {
      self.storeURL = nil
    }
    load()
  }

  func remember(fileURL: URL) {
    let path = fileURL.standardizedFileURL.path
    guard let bookmark = try? fileURL.bookmarkData(
      options: LocalFolderAccess.creationOptions,
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    ) else {
      os_log(
        "Bookmark for opened file could not be created: %s",
        log: log,
        type: .info,
        path
      )
      return
    }
    lock.withLock {
      bookmarks[path] = bookmark
      activeURLs[path] = fileURL
    }
    save()
  }

  func forget(fileURL: URL) {
    let path = fileURL.standardizedFileURL.path
    let removed = lock.withLock { () -> Bool in
      let hadBookmark = bookmarks.removeValue(forKey: path) != nil
      if let activeURL = activeURLs.removeValue(forKey: path) {
        activeURL.stopAccessingSecurityScopedResource()
      }
      return hadBookmark
    }
    if removed {
      save()
    }
  }

  func activateAll() {
    let storedBookmarks = lock.withLock { bookmarks }
    for (path, bookmark) in storedBookmarks {
      activate(path: path, bookmark: bookmark)
    }
  }

  private func activate(path: String, bookmark: Data) {
    if lock.withLock({ activeURLs[path] != nil }) { return }
    var isStale = false
    guard let url = try? URL(
      resolvingBookmarkData: bookmark,
      options: LocalFolderAccess.resolutionOptions,
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    ) else {
      os_log(
        "Bookmark for opened file could not be resolved: %s",
        log: log,
        type: .info,
        path
      )
      return
    }
    _ = url.startAccessingSecurityScopedResource()
    if isStale {
      os_log("Bookmark for opened file is stale: %s", log: log, type: .info, path)
    }
    lock.withLock { activeURLs[path] = url }
  }

  private func load() {
    guard let storeURL,
          let data = try? Data(contentsOf: storeURL),
          let records = try? JSONDecoder().decode([Record].self, from: data)
    else { return }
    bookmarks = Dictionary(uniqueKeysWithValues: records.map { ($0.path, $0.bookmark) })
  }

  private func save() {
    guard let storeURL else { return }
    let records = lock.withLock {
      bookmarks.map { Record(path: $0.key, bookmark: $0.value) }
    }
    guard let data = try? JSONEncoder().encode(records) else { return }
    try? FileManager.default.createDirectory(
      at: storeURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try? data.write(to: storeURL, options: .atomic)
  }
}

// MARK: - OpenedFileLibrary

@MainActor
public final class OpenedFileLibrary {
  public static let shared = OpenedFileLibrary()

  private let bookmarkStore = OpenedFileBookmarkStore.shared
  private let log = OSLog(subsystem: "fmusic", category: "OpenedFileLibrary")

  public func activateBookmarks() {
    bookmarkStore.activateAll()
  }

  /// Imports each file that is not already part of the active library and returns the songs in
  /// the same order. Files inside the active local folder use the regular local IDs, so a later
  /// folder scan reuses them instead of creating duplicates.
  public func importFiles(
    fileURLs: [URL],
    storage: PersistentStorage
  ) async
    -> [Song] {
    guard let accountInfo = storage.settings.accounts.active else { return [] }
    let account = storage.main.library.getAccount(info: accountInfo)
    let credentials = storage.settings.accounts.getSetting(accountInfo).read.loginCredentials
    let localRoot = activeLocalRoot(account: account, credentials: credentials)
    let accountObjectId = account.managedObject.objectID

    var orderedSongIDs = [String]()
    var existingSongs = [String: Song]()
    var newItems = [SingleFileItem]()
    var seenPaths = Set<String>()

    for fileURL in fileURLs {
      let url = fileURL.standardizedFileURL
      guard seenPaths.insert(url.path).inserted else { continue }
      guard LocalLibraryIndexer.audioExtensions.contains(url.pathExtension.lowercased()) else {
        os_log(
          "Opened file is not a supported audio file: %s",
          log: log,
          type: .info,
          url.path
        )
        continue
      }

      _ = url.startAccessingSecurityScopedResource()
      bookmarkStore.remember(fileURL: url)

      if let localRoot,
         let item = await localItem(fileURL: url, rootURL: localRoot) {
        orderedSongIDs.append(item.songID)
        if let existing = storage.main.library.getSong(for: account, id: item.songID) {
          existingSongs[item.songID] = existing
        } else {
          newItems.append(item)
        }
        continue
      }

      if let item = await openedItem(fileURL: url) {
        orderedSongIDs.append(item.songID)
        newItems.append(item)
      } else if let existing = storage.main.library
        .getSong(for: account, id: openedSongID(for: url)) {
        orderedSongIDs.append(existing.id)
        existingSongs[existing.id] = existing
      } else {
        os_log("Opened file could not be read: %s", log: log, type: .error, url.path)
      }
    }

    guard !newItems.isEmpty else {
      return orderedSongIDs.compactMap { existingSongs[$0] }
    }
    let itemsToWrite = newItems

    do {
      try await storage.async.perform { asyncCompanion in
        let account = asyncCompanion.library.getAccount(managedObjectId: accountObjectId)
        FileSourceLibraryWriter.write(
          items: itemsToWrite,
          account: account,
          accountInfo: accountInfo,
          library: asyncCompanion.library,
          cacheFileManager: CacheFileManager.shared
        )
        FileSourceLibraryWriter.updateDenormalizedValues(
          account: account,
          library: asyncCompanion.library
        )
        asyncCompanion.saveContext()
      }
    } catch {
      os_log(
        "Opened files could not be added to the library: %s",
        log: log,
        type: .error,
        error.localizedDescription
      )
      return orderedSongIDs.compactMap { existingSongs[$0] }
    }

    var songs = [Song]()
    for songID in orderedSongIDs {
      if let existing = existingSongs[songID] {
        songs.append(existing)
      } else if let song = storage.main.library.getSong(for: account, id: songID) {
        songs.append(song)
      }
    }
    os_log("Opened files imported: %d", log: log, type: .info, itemsToWrite.count)
    return songs
  }

  private func activeLocalRoot(account: Account, credentials: LoginCredentials?) -> URL? {
    guard account.apiType == .local, let credentials else { return nil }
    return try? LocalFolderAccess.shared.activate(credentials: credentials)
  }

  private func localItem(fileURL: URL, rootURL: URL) async -> SingleFileItem? {
    let relativePath = FileSourceMetadataReader.relativePath(of: fileURL, rootURL: rootURL)
    guard !relativePath.isEmpty else { return nil }
    guard let metadata = await FileSourceMetadataReader.read(
      fileURL: fileURL,
      rootURL: rootURL,
      folderArtwork: LocalLibraryIndexer.folderArtwork(in: fileURL.deletingLastPathComponent())
    ) else { return nil }

    return SingleFileItem(
      fileURL: fileURL,
      playablePathValue: relativePath,
      songID: FileSourceLibraryWriter.stableID(prefix: "local_song_", value: relativePath),
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
      addedDate: metadata.addedDate,
      idScopeValue: "local"
    )
  }

  private func openedItem(fileURL: URL) async -> SingleFileItem? {
    let folderURL = fileURL.deletingLastPathComponent()
    guard let metadata = await FileSourceMetadataReader.read(
      fileURL: fileURL,
      rootURL: folderURL,
      folderArtwork: LocalLibraryIndexer.folderArtwork(in: folderURL)
    ) else { return nil }

    let albumIdentity = metadata.albumKey == "path:"
      ? "path:\(folderURL.standardizedFileURL.path)"
      : metadata.albumKey

    return SingleFileItem(
      fileURL: fileURL,
      playablePathValue: OpenedFileSource.urlString(for: fileURL),
      songID: openedSongID(for: fileURL),
      albumID: FileSourceLibraryWriter.stableID(
        prefix: "opened_album_",
        value: albumIdentity
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
      addedDate: metadata.addedDate,
      idScopeValue: "opened"
    )
  }

  private func openedSongID(for fileURL: URL) -> String {
    FileSourceLibraryWriter.stableID(
      prefix: "opened_song_",
      value: fileURL.standardizedFileURL.path
    )
  }
}
