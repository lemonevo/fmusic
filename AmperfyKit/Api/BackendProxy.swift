//
//  BackendProxy.swift
//  AmperfyKit
//
//  Created by Maximilian Bauer on 05.04.19.
//  Copyright (c) 2019 Maximilian Bauer. All rights reserved.
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

// MARK: - ServerApiType

public enum ServerApiType: Int, Sendable {
  case ampache = 1
  case subsonic = 2
}

// MARK: - BackenApiType

public enum BackenApiType: Int, Sendable, Codable {
  case notDetected = 0
  case local = 4
  case webdav = 5

  public var description: String {
    switch self {
    case .notDetected: return "NotDetected"
    case .local: return "Local Folder"
    case .webdav: return "WebDAV"
    }
  }

  public var selectorDescription: String {
    switch self {
    case .notDetected: return L10n.tr("Select Source")
    case .local: return L10n.tr("Local Folder")
    case .webdav: return L10n.tr("WebDAV")
    }
  }

  public var asServerApiType: ServerApiType? {
    nil
  }
}

// MARK: - AuthenticationError

public enum AuthenticationError: LocalizedError {
  case notAbleToLogin
  case invalidUrl
  case requestStatusError(message: String)
  case downloadError(message: String)

  public var errorDescription: String? {
    var ret = ""
    switch self {
    case .notAbleToLogin:
      ret = "Not able to login, please check credentials!"
    case .invalidUrl:
      ret = "Server URL is invalid!"
    case let .requestStatusError(message: message):
      ret = "Requesting server URL finished with status response error code '\(message)'!"
    case let .downloadError(message: message):
      ret = message
    }
    return ret
  }
}

// MARK: - BackendError

public enum BackendError: LocalizedError {
  case invalidUrl
  case noCredentials
  case persistentSaveFailed
  case notSupported
  case incorrectServerBehavior(message: String)

  public var errorDescription: String? {
    var ret = ""
    switch self {
    case .invalidUrl:
      ret = "Provided URL is invalid."
    case .noCredentials:
      ret = "Internal error: no credentials provided."
    case .persistentSaveFailed:
      ret = "Change could not be saved."
    case .notSupported:
      ret = "Requested functionality is not supported."
    case let .incorrectServerBehavior(message: message):
      ret = "Server didn't behave as expected: \(message)"
    }
    return ret
  }
}

// MARK: - ResponseErrorType

public enum ResponseErrorType: Sendable {
  case api
  case xml
  case resource
}

// MARK: - ResponseError

final public class ResponseError: LocalizedError, Sendable {
  public let type: ResponseErrorType
  public let statusCode: Int
  public let message: String
  public let cleansedURL: CleansedURL?
  public let data: Data?

  init(
    type: ResponseErrorType,
    statusCode: Int = 0,
    message: String = "",
    cleansedURL: CleansedURL? = nil,
    data: Data? = nil
  ) {
    self.type = type
    self.statusCode = statusCode
    self.cleansedURL = cleansedURL
    self.data = data

    switch type {
    case .api:
      self.message = message
    case .xml:
      self.message = "XML response could not be parsed."
    case .resource:
      self.message = message
    }
  }

  public var errorDescription: String? {
    switch type {
    case .api:
      return "API error \(statusCode): \(message)"
    case .xml:
      return "\(message)"
    case .resource:
      return "API error \(statusCode): \(message)"
    }
  }

  public func asInfo(topic: String) -> ResponseErrorInfo {
    var dataString: String?
    if let data = data {
      dataString = String(decoding: data, as: UTF8.self)
    }
    return ResponseErrorInfo(
      topic: topic,
      statusCode: statusCode,
      message: message,
      cleansedURL: cleansedURL?.description ?? "",
      data: dataString
    )
  }
}

// MARK: - ResponseErrorInfo

public struct ResponseErrorInfo: Encodable {
  public var topic: String
  public var statusCode: Int
  public var message: String
  public var cleansedURL: String
  public var data: String?
}

// MARK: - BackendProxy

public final class BackendProxy: Sendable {
  private let log = OSLog(subsystem: "Amperfy", category: "BackendProxy")
  private let networkMonitor: NetworkMonitorFacade
  private let performanceMonitor: ThreadPerformanceMonitor
  private let eventLogger: EventLogger
  private let settings: AmperfySettings

  public var selectedApi: BackenApiType {
    get {
      activeApiType.wrappedValue
    }
    set {
      os_log("%s is active backend api", log: self.log, type: .info, newValue.description)
      activeApiType.wrappedValue = newValue
      downloadManagerDelegate.wrappedValue = activeApi.createArtworkDownloadDelegate()
    }
  }

  private let activeApiType = Atomic<BackenApiType>(wrappedValue: .webdav)
  private let downloadManagerDelegate = Atomic<DownloadManagerDelegate?>(wrappedValue: nil)

  private var activeApi: BackendApi {
    switch activeApiType.wrappedValue {
    case .local, .notDetected:
      return localApi.wrappedValue!
    case .webdav:
      return webdavApi.wrappedValue!
    }
  }

  private let localApi = Atomic<BackendApi?>(wrappedValue: nil)
  private let webdavApi = Atomic<BackendApi?>(wrappedValue: nil)

  init(
    networkMonitor: NetworkMonitorFacade,
    performanceMonitor: ThreadPerformanceMonitor,
    eventLogger: EventLogger,
    settings: AmperfySettings
  ) {
    self.networkMonitor = networkMonitor
    self.performanceMonitor = performanceMonitor
    self.eventLogger = eventLogger
    self.settings = settings
  }

  @MainActor
  public func initialize() {
    localApi.wrappedValue = LocalServerApi()
    webdavApi.wrappedValue = WebDAVServerApi()
  }

  @MainActor
  public func login(
    apiType: BackenApiType,
    credentials: LoginCredentials
  ) async throws
    -> BackenApiType {
    switch apiType {
    case .local:
      try await localApi.wrappedValue!.isAuthenticationValid(credentials: credentials)
      return .local
    case .webdav:
      try await webdavApi.wrappedValue!.isAuthenticationValid(credentials: credentials)
      return .webdav
    case .notDetected:
      throw AuthenticationError.notAbleToLogin
    }
  }
}

// MARK: BackendApi

extension BackendProxy: BackendApi {
  public var clientApiVersion: String { activeApi.clientApiVersion }

  public var serverApiVersion: String { activeApi.serverApiVersion }

  public var httpHeaders: [String: String] { activeApi.httpHeaders }

  public func provideCredentials(credentials: LoginCredentials) {
    activeApi.provideCredentials(credentials: credentials)
  }

  public func isAuthenticationValid(credentials: LoginCredentials) async throws {
    try await activeApi.isAuthenticationValid(credentials: credentials)
  }

  public func generateUrl(forDownloadingPlayable playableInfo: AbstractPlayableInfo) async throws
    -> URL {
    try await activeApi.generateUrl(forDownloadingPlayable: playableInfo)
  }

  public func generateUrl(
    forStreamingPlayable playableInfo: AbstractPlayableInfo,
    maxBitrate: StreamingMaxBitratePreference,
    formatPreference: StreamingFormatPreference
  ) async throws
    -> URL {
    try await activeApi.generateUrl(
      forStreamingPlayable: playableInfo,
      maxBitrate: maxBitrate,
      formatPreference: formatPreference
    )
  }

  public func generateUrl(
    forStreamingPlayable playableInfo: AbstractPlayableInfo,
    maxBitrate: StreamingMaxBitratePreference,
    formatPreference: StreamingFormatPreference,
    timeOffset: Int
  ) async throws
    -> URL {
    try await activeApi.generateUrl(
      forStreamingPlayable: playableInfo,
      maxBitrate: maxBitrate,
      formatPreference: formatPreference,
      timeOffset: timeOffset
    )
  }

  public func generateUrl(forArtwork artwork: Artwork) async throws -> URL {
    try await activeApi.generateUrl(forArtwork: artwork)
  }

  public func checkForErrorResponse(response: APIDataResponse) -> ResponseError? {
    activeApi.checkForErrorResponse(response: response)
  }

  public func createLibrarySyncer(account: Account, storage: PersistentStorage) -> LibrarySyncer {
    activeApi.createLibrarySyncer(account: account, storage: storage)
  }

  public func getActiveArtworkDownloadDelegate() -> DownloadManagerDelegate {
    var dlDelegate = downloadManagerDelegate.wrappedValue
    if dlDelegate == nil {
      dlDelegate = activeApi.createArtworkDownloadDelegate()
      downloadManagerDelegate.wrappedValue = dlDelegate
    }
    return dlDelegate!
  }

  public func createArtworkDownloadDelegate() -> DownloadManagerDelegate {
    activeApi.createArtworkDownloadDelegate()
  }

  public func extractArtworkInfoFromURL(urlString: String) -> ArtworkRemoteInfo? {
    activeApi.extractArtworkInfoFromURL(urlString: urlString)
  }

  public func cleanse(url: URL?) -> CleansedURL {
    activeApi.cleanse(url: url)
  }
}
