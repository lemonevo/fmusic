//
//  LocalServerApi.swift
//  fmusicKit
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import CoreData
import Foundation
import os.log

// MARK: - LocalServerApi

final class LocalServerApi: BackendApi, @unchecked Sendable {
  private let credentials = Atomic<LoginCredentials?>(wrappedValue: nil)
  private let storage = Atomic<PersistentStorage?>(wrappedValue: nil)
  private let log = OSLog(subsystem: "fmusic", category: "LocalServerApi")
  private let fileManager = CacheFileManager.shared

  var clientApiVersion: String { "local" }
  var serverApiVersion: String { "local" }
  var httpHeaders: [String: String] { [:] }

  func provideCredentials(credentials: LoginCredentials) {
    self.credentials.wrappedValue = credentials
    if credentials.backendApi == .local {
      do {
        _ = try LocalFolderAccess.shared.activate(credentials: credentials)
      } catch {
        os_log(
          "Local folder could not be activated: %s",
          log: log,
          type: .error,
          error.localizedDescription
        )
      }
    }
  }

  func isAuthenticationValid(credentials: LoginCredentials) async throws {
    _ = try LocalFolderAccess.shared.activate(credentials: credentials)
  }

  func generateUrl(forDownloadingPlayable playableInfo: AbstractPlayableInfo) async throws -> URL {
    try await absoluteURL(for: playableInfo)
  }

  func generateUrl(forStreamingPlayable playableInfo: AbstractPlayableInfo) async throws
    -> URL {
    try await absoluteURL(for: playableInfo)
  }

  func generateUrl(forArtwork artwork: Artwork) async throws -> URL {
    throw BackendError.notSupported
  }

  func checkForErrorResponse(response: APIDataResponse) -> ResponseError? { nil }

  @MainActor
  func createLibrarySyncer(account: Account, storage: PersistentStorage) -> LibrarySyncer {
    self.storage.wrappedValue = storage
    return LocalLibraryIndexer(
      account: account,
      storage: storage,
      credentials: credentials.wrappedValue
    )
  }

  func createArtworkDownloadDelegate() -> DownloadManagerDelegate {
    LocalArtworkDownloadDelegate()
  }

  func extractArtworkInfoFromURL(urlString: String) -> ArtworkRemoteInfo? { nil }

  func cleanse(url: URL?) -> CleansedURL {
    CleansedURL(urlString: url?.path ?? "")
  }

  private func absoluteURL(for playableInfo: AbstractPlayableInfo) async throws -> URL {
    guard let storage = storage.wrappedValue else {
      throw BackendError.notSupported
    }
    let relativePath = try await storage.async.performAndGet { asyncCompanion in
      let playable = AbstractPlayable(
        managedObject: asyncCompanion.context
          .object(with: playableInfo.objectID) as! AbstractPlayableMO
      )
      return playable.url ?? ""
    }
    guard !relativePath.isEmpty else { throw BackendError.notSupported }
    return try folderURL().appendingPathComponent(relativePath)
  }

  private func folderURL() throws -> URL {
    guard let credentials = credentials.wrappedValue else {
      throw LocalFolderError.noFolderSelected
    }
    return try LocalFolderAccess.shared.activate(credentials: credentials)
  }
}

// MARK: - LocalArtworkDownloadDelegate

/// Local artwork is written to the cache directly while indexing the folder.
final class LocalArtworkDownloadDelegate: DownloadManagerDelegate {
  var requestPredicate: NSPredicate { NSPredicate(value: false) }
  var parallelDownloadsCount: Int { 1 }
  var httpHeaders: [String: String] { [:] }

  func prepareDownload(
    downloadInfo: DownloadElementInfo,
    storage: AsyncCoreDataAccessWrapper
  ) async throws
    -> URL {
    throw DownloadError.fetchFailed
  }

  func validateDownloadedData(fileURL: URL?, downloadURL: URL?) -> ResponseError? { nil }

  func completedDownload(
    downloadInfo: DownloadElementInfo,
    fileURL: URL,
    fileMimeType: String?,
    storage: AsyncCoreDataAccessWrapper
  ) async {}

  func failedDownload(
    downloadInfo: DownloadElementInfo,
    storage: AsyncCoreDataAccessWrapper
  ) async {}
}
