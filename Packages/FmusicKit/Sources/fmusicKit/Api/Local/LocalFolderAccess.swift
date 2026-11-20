//
//  LocalFolderAccess.swift
//  fmusicKit
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import Foundation
import os.log

// MARK: - LocalFolderError

public enum LocalFolderError: LocalizedError, Sendable {
  case noFolderSelected
  case bookmarkResolutionFailed
  case accessDenied
  case folderNotReadable(String)

  public var errorDescription: String? {
    switch self {
    case .noFolderSelected:
      return L10n.tr("No music folder selected.")
    case .bookmarkResolutionFailed:
      return L10n.tr("The selected music folder can not be restored.")
    case .accessDenied:
      return L10n.tr("Access to the selected music folder was denied.")
    case let .folderNotReadable(path):
      return L10n.tr("The music folder is not readable: %@", path)
    }
  }
}

// MARK: - LocalFolderAccess

/// Owns the security scoped access to folders selected by the user.
/// Access is intentionally kept until the app terminates: the audio player
/// opens files through symlinks in the app container and Core Data stores
/// relative paths only.
public final class LocalFolderAccess: @unchecked Sendable {
  static let shared = LocalFolderAccess()

  private let lock = NSLock()
  private var activeURLs = [String: URL]()
  private let log = OSLog(subsystem: "fmusic", category: "LocalFolderAccess")

  private init() {}

  static var creationOptions: URL.BookmarkCreationOptions {
    #if targetEnvironment(macCatalyst) || os(macOS)
      return .withSecurityScope
    #else
      return .minimalBookmark
    #endif
  }

  static var resolutionOptions: URL.BookmarkResolutionOptions {
    #if targetEnvironment(macCatalyst) || os(macOS)
      return .withSecurityScope
    #else
      return []
    #endif
  }

  public static func createBookmark(for url: URL) throws -> Data {
    try url.bookmarkData(
      options: creationOptions,
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
  }

  func activate(credentials: LoginCredentials) throws -> URL {
    try activate(bookmark: credentials.localFolderBookmark, key: credentials.serverUrl)
  }

  func activate(bookmark: Data?, key: String) throws -> URL {
    guard let bookmark else { throw LocalFolderError.noFolderSelected }

    if let existingURL = lock.withLock({ activeURLs[key] }) {
      return existingURL
    }

    var isStale = false
    let url: URL
    do {
      url = try URL(
        resolvingBookmarkData: bookmark,
        options: Self.resolutionOptions,
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )
    } catch {
      os_log(
        "Folder bookmark could not be resolved: %s",
        log: log,
        type: .error,
        error.localizedDescription
      )
      throw LocalFolderError.bookmarkResolutionFailed
    }

    let accessStarted = url.startAccessingSecurityScopedResource()
    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
    guard exists, isDirectory.boolValue, FileManager.default.isReadableFile(atPath: url.path)
    else {
      if accessStarted { url.stopAccessingSecurityScopedResource() }
      throw LocalFolderError.folderNotReadable(url.path)
    }
    // Non-sandboxed builds report false although the folder is readable.
    // Keep the access active for the lifetime of the process in sandboxed builds.

    if isStale {
      os_log("Folder bookmark is stale: %s", log: log, type: .info, url.path)
    }
    os_log("Folder access activated: %s", log: log, type: .info, url.path)
    lock.withLock { activeURLs[key] = url }
    return url
  }

  func deactivate(key: String) {
    guard let url = lock.withLock({ activeURLs.removeValue(forKey: key) }) else { return }
    url.stopAccessingSecurityScopedResource()
  }
}
