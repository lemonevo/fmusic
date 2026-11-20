//
//  WebDAVServerApi.swift
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

// MARK: - WebDAVServerApi

final class WebDAVServerApi: BackendApi, @unchecked Sendable {
  private let credentials = Atomic<LoginCredentials?>(wrappedValue: nil)
  private let storage = Atomic<PersistentStorage?>(wrappedValue: nil)
  private let fileManager = CacheFileManager.shared
  private let log = OSLog(subsystem: "fmusic", category: "WebDAVServerApi")

  var clientApiVersion: String { "1.1" }
  var serverApiVersion: String { "webdav" }

  var httpHeaders: [String: String] {
    guard let credentials = credentials.wrappedValue else { return [:] }
    return WebDAVClient.requestHeaders(for: credentials)
  }

  func provideCredentials(credentials: LoginCredentials) {
    self.credentials.wrappedValue = credentials
  }

  func isAuthenticationValid(credentials: LoginCredentials) async throws {
    guard let baseURL = Self.baseURL(from: credentials) else {
      throw WebDAVError.invalidBaseURL
    }
    let client = WebDAVClient(baseURL: baseURL, credentials: credentials)
    _ = try await client.propfind(relativePath: "", depth: 0)
  }

  func generateUrl(forDownloadingPlayable playableInfo: AbstractPlayableInfo) async throws -> URL {
    try await remoteURL(for: playableInfo)
  }

  func generateUrl(forStreamingPlayable playableInfo: AbstractPlayableInfo) async throws
    -> URL {
    try await remoteURL(for: playableInfo)
  }

  func generateUrl(forArtwork artwork: Artwork) async throws -> URL {
    guard let relFilePath = artwork.relFilePath,
          let absoluteFilePath = fileManager.getAbsolutefmusicPath(relFilePath: relFilePath)
    else { throw BackendError.notSupported }
    return absoluteFilePath
  }

  func checkForErrorResponse(response: APIDataResponse) -> ResponseError? { nil }

  @MainActor
  func createLibrarySyncer(account: Account, storage: PersistentStorage) -> LibrarySyncer {
    self.storage.wrappedValue = storage
    return WebDAVLibraryIndexer(
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
    guard let url else { return CleansedURL(urlString: "") }
    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    components?.user = nil
    components?.password = nil
    components?.query = nil
    return CleansedURL(urlString: components?.string ?? "")
  }

  private func remoteURL(for playableInfo: AbstractPlayableInfo) async throws -> URL {
    guard let storage = storage.wrappedValue else { throw BackendError.notSupported }
    let relativePath = try await storage.async.performAndGet { asyncCompanion in
      let playable = AbstractPlayable(
        managedObject: asyncCompanion.context
          .object(with: playableInfo.objectID) as! AbstractPlayableMO
      )
      return playable.url ?? ""
    }
    guard !relativePath.isEmpty else { throw BackendError.notSupported }
    if let openedFileURL = OpenedFileSource.fileURL(from: relativePath) {
      return openedFileURL
    }
    guard let credentials = credentials.wrappedValue,
          let baseURL = Self.baseURL(from: credentials)
    else { throw BackendError.notSupported }
    return WebDAVClient.absoluteURL(
      baseURL: WebDAVClient.normalizedBaseURL(baseURL),
      relativePath: relativePath
    )
  }

  private static func baseURL(from credentials: LoginCredentials) -> URL? {
    guard let url = URL(string: credentials.activeBackendServerUrl) else { return nil }
    return url
  }
}
