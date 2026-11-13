//
//  WebDAVClient.swift
//  fmusicKit
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import Foundation
import os.log

// MARK: - WebDAVEntry

struct WebDAVEntry: Sendable {
  let relativePath: String
  let isDirectory: Bool
  let size: Int
  let lastModified: Date?
  let contentType: String?

  var fileName: String {
    (relativePath as NSString).lastPathComponent
  }

  var fileExtension: String {
    (fileName as NSString).pathExtension.lowercased()
  }

  var directoryPath: String {
    (relativePath as NSString).deletingLastPathComponent
  }

  var fileNameWithoutExtension: String {
    (fileName as NSString).deletingPathExtension
  }
}

// MARK: - WebDAVError

enum WebDAVError: LocalizedError, Sendable {
  case invalidBaseURL
  case unauthorized
  case digestNotSupported
  case requestFailed(statusCode: Int)
  case invalidResponse
  case unreadableRange

  var errorDescription: String? {
    switch self {
    case .invalidBaseURL:
      return L10n.tr("The WebDAV URL is invalid.")
    case .unauthorized:
      return L10n.tr("WebDAV login failed. Please check username and password.")
    case .digestNotSupported:
      return L10n.tr("This WebDAV server requires Digest authentication, which is not supported yet.")
    case let .requestFailed(statusCode):
      return L10n.tr("WebDAV request failed with status code %d.", statusCode)
    case .invalidResponse:
      return L10n.tr("The WebDAV server returned an unexpected response.")
    case .unreadableRange:
      return L10n.tr("The WebDAV server did not return the requested byte range.")
    }
  }
}

// MARK: - WebDAVClient

final class WebDAVClient: @unchecked Sendable {
  let baseURL: URL
  private let credentials: LoginCredentials
  private let log = OSLog(subsystem: "fmusic", category: "WebDAVClient")

  /// One session for all WebDAV accounts and requests. Creating a URLSession per
  /// request is expensive and leaks connection pools.
  private static let sharedSession: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.waitsForConnectivity = true
    configuration.timeoutIntervalForRequest = 60
    configuration.timeoutIntervalForResource = 3600
    configuration.httpMaximumConnectionsPerHost = 8
    return URLSession(configuration: configuration)
  }()

  private let session = WebDAVClient.sharedSession

  init(baseURL: URL, credentials: LoginCredentials) {
    self.baseURL = Self.normalizedBaseURL(baseURL)
    self.credentials = credentials
  }

  static func normalizedBaseURL(_ baseURL: URL) -> URL {
    guard !baseURL.absoluteString.hasSuffix("/") else { return baseURL }
    var normalizedURL = baseURL
    normalizedURL.appendPathComponent("")
    return normalizedURL
  }

  static func requestHeaders(for credentials: LoginCredentials) -> [String: String] {
    var headers = credentials.httpHeaders
    guard !credentials.username.isEmpty else { return headers }
    let token = Data("\(credentials.username):\(credentials.password)".utf8)
      .base64EncodedString()
    headers["Authorization"] = "Basic \(token)"
    return headers
  }

  var requestHeaders: [String: String] {
    Self.requestHeaders(for: credentials)
  }

  static func absoluteURL(baseURL: URL, relativePath: String) -> URL {
    var url = baseURL
    for component in relativePath.split(separator: "/") {
      url.appendPathComponent(String(component))
    }
    return url
  }

  func absoluteURL(for relativePath: String) -> URL {
    Self.absoluteURL(baseURL: baseURL, relativePath: relativePath)
  }

  func propfind(relativePath: String, depth: Int = 1) async throws -> [WebDAVEntry] {
    var request = URLRequest(url: absoluteURL(for: relativePath))
    request.httpMethod = "PROPFIND"
    request.setValue("\(depth)", forHTTPHeaderField: "Depth")
    request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data(Self.propfindBody.utf8)
    applyHeaders(to: &request)

    let (data, response) = try await session.data(for: request)
    try validate(response: response)
    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 200 || httpResponse.statusCode == 207
    else { throw WebDAVError.invalidResponse }

    let parser = WebDAVMultiStatusParser(baseURL: baseURL)
    return parser.parse(data: data)
  }

  func fetchData(relativePath: String, range: ClosedRange<Int>? = nil) async throws -> Data {
    var request = URLRequest(url: absoluteURL(for: relativePath))
    if let range {
      request.setValue(
        "bytes=\(range.lowerBound)-\(range.upperBound)",
        forHTTPHeaderField: "Range"
      )
    }
    applyHeaders(to: &request)
    let (data, response) = try await session.data(for: request)
    try validate(response: response)
    return data
  }

  func download(relativePath: String, to destination: URL) async throws {
    var request = URLRequest(url: absoluteURL(for: relativePath))
    applyHeaders(to: &request)
    let (temporaryURL, response) = try await session.download(for: request)
    try validate(response: response)
    try? FileManager.default.removeItem(at: destination)
    try FileManager.default.moveItem(at: temporaryURL, to: destination)
  }

  private func applyHeaders(to request: inout URLRequest) {
    for (field, value) in requestHeaders {
      request.setValue(value, forHTTPHeaderField: field)
    }
  }

  private func validate(response: URLResponse) throws {
    guard let httpResponse = response as? HTTPURLResponse else {
      throw WebDAVError.invalidResponse
    }
    if httpResponse.statusCode == 401 {
      let authenticate = httpResponse.value(forHTTPHeaderField: "WWW-Authenticate") ?? ""
      if authenticate.lowercased().hasPrefix("digest") {
        throw WebDAVError.digestNotSupported
      }
      throw WebDAVError.unauthorized
    }
    guard (200 ..< 300).contains(httpResponse.statusCode) else {
      throw WebDAVError.requestFailed(statusCode: httpResponse.statusCode)
    }
  }

  private static let propfindBody = """
  <?xml version="1.0" encoding="utf-8"?>
  <d:propfind xmlns:d="DAV:">
    <d:prop>
      <d:displayname/>
      <d:resourcetype/>
      <d:getcontentlength/>
      <d:getcontenttype/>
      <d:getlastmodified/>
    </d:prop>
  </d:propfind>
  """
}

// MARK: - WebDAVMultiStatusParser

private final class WebDAVMultiStatusParser: NSObject, XMLParserDelegate {
  private let baseURL: URL
  private let basePath: String
  private var entries = [WebDAVEntry]()
  private var currentHref: String?
  private var currentIsDirectory = false
  private var currentSize = 0
  private var currentContentType: String?
  private var currentLastModified: Date?
  private var currentElement = ""
  private var currentText = ""
  private var isInsideResourceType = false

  init(baseURL: URL) {
    self.baseURL = baseURL
    self.basePath = baseURL.path.hasSuffix("/")
      ? String(baseURL.path.dropLast())
      : baseURL.path
  }

  func parse(data: Data) -> [WebDAVEntry] {
    entries.removeAll()
    let parser = XMLParser(data: data)
    parser.delegate = self
    parser.shouldProcessNamespaces = false
    parser.parse()
    return entries
  }

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    let name = localName(of: elementName)
    currentElement = name
    currentText = ""
    switch name {
    case "response":
      currentHref = nil
      currentIsDirectory = false
      currentSize = 0
      currentContentType = nil
      currentLastModified = nil
    case "resourcetype":
      isInsideResourceType = true
    case "collection":
      if isInsideResourceType { currentIsDirectory = true }
    default:
      break
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    currentText += string
  }

  func parser(
    _ parser: XMLParser,
    didEndElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    let name = localName(of: elementName)
    let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
    switch name {
    case "href":
      if currentHref == nil { currentHref = value }
    case "getcontentlength":
      currentSize = Int(value) ?? 0
    case "getcontenttype":
      currentContentType = value.isEmpty ? nil : value
    case "getlastmodified":
      currentLastModified = Self.parseHTTPDate(value)
    case "resourcetype":
      isInsideResourceType = false
    case "response":
      appendCurrentEntry()
    default:
      break
    }
    currentElement = ""
    currentText = ""
  }

  private func appendCurrentEntry() {
    guard let href = currentHref, !href.isEmpty else { return }
    let relativePath = relativePath(for: href)
    guard !relativePath.isEmpty else { return }
    entries.append(WebDAVEntry(
      relativePath: relativePath,
      isDirectory: currentIsDirectory,
      size: currentSize,
      lastModified: currentLastModified,
      contentType: currentContentType
    ))
  }

  private func relativePath(for href: String) -> String {
    let resolvedURL: URL?
    if href.hasPrefix("http://") || href.hasPrefix("https://") {
      resolvedURL = URL(string: href)
    } else {
      resolvedURL = URL(string: href, relativeTo: baseURL)?.absoluteURL
    }
    guard let resolvedURL else { return "" }
    let path = resolvedURL.path
    if path == basePath || path == basePath + "/" { return "" }
    guard path.hasPrefix(basePath + "/") else { return "" }
    return String(path.dropFirst(basePath.count + 1))
  }

  private func localName(of elementName: String) -> String {
    guard let separator = elementName.firstIndex(of: ":") else { return elementName }
    return String(elementName[elementName.index(after: separator)...])
  }

  private static func parseHTTPDate(_ value: String) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    return formatter.date(from: value)
  }
}
