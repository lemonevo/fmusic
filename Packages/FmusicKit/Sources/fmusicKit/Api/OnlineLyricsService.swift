//
//  OnlineLyricsService.swift
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
//  Online lookup and candidate ranking are independently implemented after studying
//  LyricsX-Next (MPL-2.0); no source code is copied from that project.
//

import CommonCrypto
import CryptoKit
import Foundation
import os.log

private let onlineLyricsLog = OSLog(subsystem: "fmusic", category: "OnlineLyrics")

// MARK: - OnlineLyricsError

public enum OnlineLyricsError: LocalizedError {
  case noMatch

  public var errorDescription: String? {
    switch self {
    case .noMatch: L10n.tr("No matching lyrics found online.")
    }
  }
}

// MARK: - OnlineLyricsSource

public enum OnlineLyricsSource: String, CaseIterable, Sendable {
  case lrclib
  case netease
  case qqmusic
  case kugou

  var priorityBonus: Int {
    switch self {
    case .lrclib: 3
    case .netease: 2
    case .qqmusic: 1
    case .kugou: 0
    }
  }

  public var displayName: String {
    switch self {
    case .lrclib: "LRCLIB"
    case .netease: L10n.tr("NetEase Music")
    case .qqmusic: L10n.tr("QQ Music")
    case .kugou: L10n.tr("Kugou Music")
    }
  }
}

// MARK: - OnlineLyricsQuery

struct OnlineLyricsQuery: Sendable {
  let title: String
  let artist: String
  let album: String
  /// Milliseconds, 0 when unknown.
  let duration: Int
}

// MARK: - OnlineLyricsPayload

struct OnlineLyricsPayload: Sendable {
  let text: String
  let translation: String?
  let isWordTimed: Bool
}

// MARK: - OnlineLyricsCandidate

struct OnlineLyricsCandidate: Sendable {
  let source: OnlineLyricsSource
  let identifier: String
  let title: String
  let artist: String
  let album: String
  /// Milliseconds, 0 when unknown.
  let duration: Int
  /// Present when the search response already carried the lyrics.
  let inlineLyrics: OnlineLyricsPayload?
  /// Direct cover URL from the search response, when the provider supplies one.
  let artworkURL: URL?
  /// Provider-specific album id used to resolve the cover on demand.
  let albumIdentifier: String?
}

// MARK: - ScoredCandidate

private struct ScoredCandidate: Sendable {
  let candidate: OnlineLyricsCandidate
  let score: Int
}

// MARK: - OnlineLyricsSearchResult

/// One row of the manual lyrics search. The provider candidate stays private: the
/// lyrics text is fetched on demand through `OnlineLyricsService.preview(_:)`.
public struct OnlineLyricsSearchResult: Sendable, Identifiable {
  public let id: String
  public let title: String
  public let artist: String
  public let album: String
  /// Milliseconds, 0 when unknown.
  public let duration: Int
  public let source: OnlineLyricsSource
  public var sourceName: String { source.displayName }
  fileprivate let candidate: OnlineLyricsCandidate
}

// MARK: - OnlineLyricsFormat

/// Native suffix of the fetched lyric file. Word timed formats drive the
/// karaoke-style effects; LRC is line timed only.
public enum OnlineLyricsFormat: String, Sendable, CaseIterable {
  case yrc = "YRC"
  case qrc = "QRC"
  case krc = "KRC"
  case lrc = "LRC"
  case txt = "TXT"

  public var isWordTimed: Bool {
    switch self {
    case .krc, .qrc, .yrc: true
    case .lrc, .txt: false
    }
  }
}

// MARK: - OnlineLyricsMatch

/// A ready-to-apply lyrics file plus the lines shown in the preview.
public struct OnlineLyricsMatch: Sendable {
  public struct Line: Sendable {
    public let text: String
    public let isTranslation: Bool
  }

  /// Tab separated cache format, including translations and YRC word tokens.
  public let text: String
  public let lines: [Line]
  public let isWordTimed: Bool
  public let hasTranslation: Bool
  public let lineCount: Int
  public let format: OnlineLyricsFormat
}

// MARK: - OnlineMetadataMatch

/// Album metadata from a provider that already passed the lyrics identity
/// checks. Used only to fill an unknown album, never to replace file tags.
public struct OnlineMetadataMatch: Sendable {
  public let album: String
  public let source: OnlineLyricsSource
  public let score: Int
  public let artworkURL: URL?
}

// MARK: - ChosenLyrics

private struct ChosenLyrics {
  let text: String
  let score: Int
}

// MARK: - OnlineLyricsProvider

private protocol OnlineLyricsProvider: Sendable {
  var source: OnlineLyricsSource { get }
  func search(_ query: OnlineLyricsQuery) async throws -> [OnlineLyricsCandidate]
  func lyrics(for candidate: OnlineLyricsCandidate) async throws -> OnlineLyricsPayload?
  func album(for candidate: OnlineLyricsCandidate) async throws -> String?
  func artworkURL(for candidate: OnlineLyricsCandidate) async -> URL?
}

extension OnlineLyricsProvider {
  func album(for candidate: OnlineLyricsCandidate) async throws -> String? { nil }
  func artworkURL(for candidate: OnlineLyricsCandidate) async -> URL? {
    candidate.artworkURL
  }
}

// MARK: - OnlineLyricsHTTP

private enum OnlineLyricsHTTP {
  private static let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 10
    configuration.timeoutIntervalForResource = 15
    configuration.httpMaximumConnectionsPerHost = 4
    return URLSession(configuration: configuration)
  }()

  private static let userAgent: String = {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    guard let version, !version.isEmpty else { return "fmusic" }
    return "fmusic/\(version)"
  }()

  static func data(from url: URL, referer: String? = nil) async throws -> Data {
    guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
      throw URLError(.unsupportedURL)
    }
    var secureURL = url
    if scheme == "http", var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
      components.scheme = "https"
      secureURL = components.url ?? url
    }

    var request = URLRequest(url: secureURL)
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let referer {
      request.setValue(referer, forHTTPHeaderField: "Referer")
    }
    return try await data(for: request)
  }

  static func data(for request: URLRequest) async throws -> Data {
    guard let url = request.url,
          let scheme = url.scheme?.lowercased(),
          scheme == "https" || scheme == "http"
    else { throw URLError(.unsupportedURL) }

    var request = request
    if scheme == "http",
       var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
      components.scheme = "https"
      request.url = components.url ?? url
    }
    if request.value(forHTTPHeaderField: "User-Agent") == nil {
      request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    }
    if request.value(forHTTPHeaderField: "Accept") == nil {
      request.setValue("application/json", forHTTPHeaderField: "Accept")
    }

    let (data, response) = try await session.data(for: request)
    if let httpResponse = response as? HTTPURLResponse,
       !(200 ..< 300).contains(httpResponse.statusCode) {
      throw URLError(.badServerResponse)
    }
    guard data.count <= 8 * 1024 * 1024 else {
      throw URLError(.dataLengthExceedsMaximum)
    }
    return data
  }

  static func url(base: String, items: [URLQueryItem]) -> URL? {
    guard var components = URLComponents(string: base) else { return nil }
    components.queryItems = items
    return components.url
  }
}

// MARK: - LRCLIBLyricsProvider

private struct LRCLIBLyricsProvider: OnlineLyricsProvider {
  let source = OnlineLyricsSource.lrclib

  private struct Record: Decodable {
    let id: Int
    let trackName: String?
    let artistName: String?
    let albumName: String?
    let duration: Double?
    let instrumental: Bool?
    let plainLyrics: String?
    let syncedLyrics: String?
  }

  func search(_ query: OnlineLyricsQuery) async throws -> [OnlineLyricsCandidate] {
    var items = [URLQueryItem(name: "track_name", value: query.title)]
    if !query.artist.isEmpty {
      items.append(URLQueryItem(name: "artist_name", value: query.artist))
    }
    var records = try await request(items: items)

    if records.isEmpty {
      let keyword = [query.title, query.artist]
        .filter { !$0.isEmpty }
        .joined(separator: " ")
      records = try await request(items: [URLQueryItem(name: "q", value: keyword)])
    }
    if records.isEmpty {
      records = try await request(items: [URLQueryItem(name: "q", value: query.title)])
    }

    return records.prefix(30).compactMap { record in
      guard record.instrumental != true,
            let title = record.trackName, !title.isEmpty
      else { return nil }
      let lyrics = [record.syncedLyrics, record.plainLyrics]
        .compactMap { $0 }
        .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      guard let lyrics else { return nil }
      return OnlineLyricsCandidate(
        source: source,
        identifier: String(record.id),
        title: title,
        artist: record.artistName ?? "",
        album: record.albumName ?? "",
        duration: record.duration.map { Int(($0 * 1000).rounded()) } ?? 0,
        inlineLyrics: OnlineLyricsPayload(
          text: lyrics,
          translation: nil,
          isWordTimed: YRCFileParser.isYRC(lyrics)
        ),
        artworkURL: nil,
        albumIdentifier: nil
      )
    }
  }

  func lyrics(for candidate: OnlineLyricsCandidate) async throws -> OnlineLyricsPayload? {
    candidate.inlineLyrics
  }

  private func request(items: [URLQueryItem]) async throws -> [Record] {
    guard let url = OnlineLyricsHTTP.url(base: "https://lrclib.net/api/search", items: items)
    else { return [] }
    let data = try await OnlineLyricsHTTP.data(from: url)
    return try JSONDecoder().decode([Record].self, from: data)
  }
}

// MARK: - NetEaseLyricsProvider

private struct NetEaseLyricsProvider: OnlineLyricsProvider {
  let source = OnlineLyricsSource.netease

  private static let referer = "https://music.163.com/"
  private static let browserUserAgent =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

  private struct SearchResponse: Decodable {
    struct Result: Decodable {
      let songs: [Song]?
    }

    struct Song: Decodable {
      struct Artist: Decodable {
        let name: String?
      }

      struct Album: Decodable {
        let id: Int64?
        let name: String?
      }

      let id: Int64
      let name: String?
      let duration: Int64?
      let artists: [Artist]?
      let album: Album?
    }

    let result: Result?
  }

  private struct LegacyLyricsResponse: Decodable {
    struct Payload: Decodable {
      let lyric: String?
    }

    let lrc: Payload?
    let tlyric: Payload?
    let nolyric: Bool?
  }

  private struct EapiLyricsResponse: Decodable {
    struct Payload: Decodable {
      let lyric: String?
    }

    let lrc: Payload?
    let tlyric: Payload?
    let yrc: Payload?
    let ytlrc: Payload?
  }

  private struct AlbumDetailResponse: Decodable {
    struct Album: Decodable {
      let picUrl: String?
    }

    let album: Album?
  }

  func artworkURL(for candidate: OnlineLyricsCandidate) async -> URL? {
    guard let albumID = candidate.albumIdentifier, !albumID.isEmpty,
          let url = URL(string: "https://music.163.com/api/album/\(albumID)")
    else { return nil }
    guard let data = try? await OnlineLyricsHTTP.data(from: url, referer: Self.referer),
          let response = try? JSONDecoder().decode(AlbumDetailResponse.self, from: data),
          let raw = response.album?.picUrl,
          let artworkURL = URL(string: raw)
    else { return nil }
    return artworkURL
  }

  func search(_ query: OnlineLyricsQuery) async throws -> [OnlineLyricsCandidate] {
    let keyword = [query.title, query.artist]
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    var songs = try await request(keyword: keyword)
    if songs.isEmpty, !query.artist.isEmpty {
      songs = try await request(keyword: query.title)
    }
    os_log(
      "NetEase search %{public}@ -> %d",
      log: onlineLyricsLog,
      type: .info,
      keyword,
      songs.count
    )
    for song in songs.prefix(3) {
      os_log(
        "  candidate %lld %{public}@/%{public}@ %lld",
        log: onlineLyricsLog,
        type: .info,
        song.id,
        song.name ?? "",
        (song.artists ?? []).compactMap(\.name).joined(separator: ","),
        song.duration ?? 0
      )
    }

    return songs.compactMap { song in
      guard let title = song.name, !title.isEmpty else { return nil }
      let artists = (song.artists ?? [])
        .compactMap(\.name)
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
      return OnlineLyricsCandidate(
        source: source,
        identifier: String(song.id),
        title: title,
        artist: artists,
        album: song.album?.name ?? "",
        duration: Int(song.duration ?? 0),
        inlineLyrics: nil,
        artworkURL: nil,
        albumIdentifier: song.album?.id.map(String.init)
      )
    }
  }

  private func request(keyword: String) async throws -> [SearchResponse.Song] {
    let items = [
      URLQueryItem(name: "csrf_token", value: ""),
      URLQueryItem(name: "s", value: keyword),
      URLQueryItem(name: "type", value: "1"),
      URLQueryItem(name: "offset", value: "0"),
      URLQueryItem(name: "limit", value: "20"),
      URLQueryItem(name: "total", value: "true"),
    ]
    guard let url = OnlineLyricsHTTP.url(
      base: "https://music.163.com/api/search/get/web",
      items: items
    ) else { return [] }

    let data = try await OnlineLyricsHTTP.data(from: url, referer: Self.referer)
    let response = try JSONDecoder().decode(SearchResponse.self, from: data)
    return response.result?.songs ?? []
  }

  func lyrics(for candidate: OnlineLyricsCandidate) async throws -> OnlineLyricsPayload? {
    guard let songID = Int64(candidate.identifier) else { return nil }
    do {
      if let payload = try await eapiLyrics(songID: songID) {
        os_log(
          "NetEase eapi %lld -> word=%d text=%d translation=%d",
          log: onlineLyricsLog,
          type: .info,
          songID,
          payload.isWordTimed ? 1 : 0,
          payload.text.count,
          payload.translation?.count ?? 0
        )
        return payload
      }
      os_log("NetEase eapi %lld -> empty", log: onlineLyricsLog, type: .info, songID)
    } catch {
      os_log(
        "NetEase eapi %lld failed: %{public}@",
        log: onlineLyricsLog,
        type: .error,
        songID,
        error.localizedDescription
      )
    }
    return try await legacyLyrics(songID: songID)
  }

  private func eapiLyrics(songID: Int64) async throws -> OnlineLyricsPayload? {
    guard let params = NetEaseEAPI.params(songID: songID),
          let url = URL(string: "https://interface3.music.163.com/eapi/song/lyric/v1")
    else { return nil }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.setValue(Self.referer, forHTTPHeaderField: "Referer")
    request.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")
    // The eapi endpoint rejects requests without an Android client marker.
    request.setValue("os=android; appver=8.0.0", forHTTPHeaderField: "Cookie")
    request.httpBody = Data("params=\(params)".utf8)

    let data = try await OnlineLyricsHTTP.data(for: request)
    let response = try JSONDecoder().decode(EapiLyricsResponse.self, from: data)
    os_log(
      "NetEase eapi payload %lld yrc=%d lrc=%d tlyric=%d",
      log: onlineLyricsLog,
      type: .info,
      songID,
      response.yrc?.lyric?.count ?? 0,
      response.lrc?.lyric?.count ?? 0,
      response.tlyric?.lyric?.count ?? 0
    )
    guard let original = Self.bestOriginalText(from: response) else { return nil }

    let translation = [response.ytlrc?.lyric, response.tlyric?.lyric]
      .compactMap { $0 }
      .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    return OnlineLyricsPayload(
      text: original,
      translation: translation,
      isWordTimed: YRCFileParser.isYRC(original)
    )
  }

  private static func bestOriginalText(from response: EapiLyricsResponse) -> String? {
    if let yrc = response.yrc?.lyric, YRCFileParser.isYRC(yrc) {
      return yrc
    }
    if let lrc = response.lrc?.lyric {
      let cleaned = sanitizedEapiLRC(lrc)
      if !cleaned.isEmpty { return cleaned }
    }
    return nil
  }

  /// The eapi `lrc` field mixes JSON credit rows with the timed lines.
  private static func sanitizedEapiLRC(_ text: String) -> String {
    text.components(separatedBy: .newlines)
      .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("{") }
      .joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func legacyLyrics(songID: Int64) async throws -> OnlineLyricsPayload? {
    let items = [
      URLQueryItem(name: "id", value: String(songID)),
      URLQueryItem(name: "lv", value: "1"),
      URLQueryItem(name: "kv", value: "1"),
      URLQueryItem(name: "tv", value: "-1"),
    ]
    guard let url = OnlineLyricsHTTP.url(
      base: "https://music.163.com/api/song/lyric",
      items: items
    ) else { return nil }

    let data = try await OnlineLyricsHTTP.data(from: url, referer: Self.referer)
    let response = try JSONDecoder().decode(LegacyLyricsResponse.self, from: data)
    guard response.nolyric != true,
          let lrc = response.lrc?.lyric,
          !lrc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return nil }
    let translation = [response.tlyric?.lyric]
      .compactMap { $0 }
      .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    return OnlineLyricsPayload(
      text: lrc,
      translation: translation,
      isWordTimed: false
    )
  }
}

// MARK: - QQMusicLyricsProvider

private struct QQMusicLyricsProvider: OnlineLyricsProvider {
  let source = OnlineLyricsSource.qqmusic

  private static let referer = "https://y.qq.com/"
  private static let browserUserAgent =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

  private struct SmartboxResponse: Decodable {
    struct Payload: Decodable {
      let song: Songs?
    }

    struct Songs: Decodable {
      let itemlist: [Item]?
    }

    struct Item: Decodable {
      let id: String?
      let mid: String?
      let name: String?
      let singer: String?
    }

    let code: Int?
    let data: Payload?
  }

  func search(_ query: OnlineLyricsQuery) async throws -> [OnlineLyricsCandidate] {
    let keyword = [query.title, query.artist]
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    var items = try await request(keyword: keyword)
    if items.isEmpty, !query.artist.isEmpty {
      items = try await request(keyword: query.title)
    }

    return items.compactMap { item in
      guard let identifier = item.id, !identifier.isEmpty,
            let name = item.name, !name.isEmpty
      else { return nil }
      // Carry the public song mid so album metadata can be fetched on demand.
      let lookup = [identifier, item.mid ?? ""].joined(separator: "|")
      return OnlineLyricsCandidate(
        source: source,
        identifier: lookup,
        title: name,
        artist: item.singer ?? "",
        album: "",
        duration: 0,
        inlineLyrics: nil,
        artworkURL: nil,
        albumIdentifier: nil
      )
    }
  }

  private struct SingleSongResponse: Decodable {
    struct Item: Decodable {
      struct Album: Decodable {
        let name: String?
        let mid: String?
      }

      let album: Album?
    }

    let data: [Item]?
  }

  func album(for candidate: OnlineLyricsCandidate) async throws -> String? {
    let parts = candidate.identifier.split(
      separator: "|",
      maxSplits: 1,
      omittingEmptySubsequences: false
    )
    guard parts.count == 2 else { return nil }
    let mid = String(parts[1])
    guard !mid.isEmpty,
          let url = OnlineLyricsHTTP.url(
            base: "https://c.y.qq.com/v8/fcg-bin/fcg_play_single_song.fcg",
            items: [
              URLQueryItem(name: "songmid", value: mid),
              URLQueryItem(name: "format", value: "json"),
              URLQueryItem(name: "platform", value: "yqq"),
              URLQueryItem(name: "needNewCode", value: "0"),
            ]
          )
    else { return nil }
    let data = try await OnlineLyricsHTTP.data(from: url, referer: Self.referer)
    let response = try JSONDecoder().decode(SingleSongResponse.self, from: data)
    return response.data?
      .lazy
      .compactMap { $0.album?.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty }
  }

  func artworkURL(for candidate: OnlineLyricsCandidate) async -> URL? {
    let parts = candidate.identifier.split(
      separator: "|",
      maxSplits: 1,
      omittingEmptySubsequences: false
    )
    guard parts.count == 2 else { return nil }
    let mid = String(parts[1])
    guard !mid.isEmpty,
          let url = OnlineLyricsHTTP.url(
            base: "https://c.y.qq.com/v8/fcg-bin/fcg_play_single_song.fcg",
            items: [
              URLQueryItem(name: "songmid", value: mid),
              URLQueryItem(name: "format", value: "json"),
              URLQueryItem(name: "platform", value: "yqq"),
              URLQueryItem(name: "needNewCode", value: "0"),
            ]
          )
    else { return nil }
    guard let data = try? await OnlineLyricsHTTP.data(from: url, referer: Self.referer),
          let response = try? JSONDecoder().decode(SingleSongResponse.self, from: data),
          let albumMid = response.data?
          .lazy
          .compactMap({ $0.album?.mid })
          .first(where: { !$0.isEmpty })
    else { return nil }
    return URL(
      string: "https://y.gtimg.cn/music/photo_new/T002R500x500M000\(albumMid).jpg"
    )
  }

  func lyrics(for candidate: OnlineLyricsCandidate) async throws -> OnlineLyricsPayload? {
    guard let rawID = candidate.identifier.split(separator: "|").first,
          let songID = Int64(rawID),
          let url = URL(string: "https://c.y.qq.com/qqmusic/fcgi-bin/lyric_download.fcg")
    else { return nil }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.setValue(Self.referer, forHTTPHeaderField: "Referer")
    request.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")
    request.httpBody = Data("musicid=\(songID)&version=15&miniversion=82&lrctype=4".utf8)

    let data = try await OnlineLyricsHTTP.data(for: request)
    guard var xml = String(data: data, encoding: .utf8) else { return nil }
    xml = xml
      .replacingOccurrences(of: "<!--", with: "")
      .replacingOccurrences(of: "-->", with: "")

    guard let raw = Self.cdata("content", in: xml) else { return nil }
    let compact = raw.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    let decoded: String
    if Self.isHex(compact) {
      guard let decrypted = decryptQQMusicQrc(compact) else { return nil }
      decoded = decrypted
    } else {
      decoded = raw
    }
    guard let text = Self.qrcText(from: decoded) else { return nil }

    let translation = Self.cdata("contentts", in: xml).flatMap { value in
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : Self.unescaped(value)
    }
    return OnlineLyricsPayload(
      text: text,
      translation: translation,
      isWordTimed: QRCFileParser.isQRC(text)
    )
  }

  private func request(keyword: String) async throws -> [SmartboxResponse.Item] {
    guard let url = OnlineLyricsHTTP.url(
      base: "https://c.y.qq.com/splcloud/fcgi-bin/smartbox_new.fcg",
      items: [URLQueryItem(name: "key", value: keyword)]
    ) else { return [] }

    let data = try await OnlineLyricsHTTP.data(from: url, referer: Self.referer)
    let response = try JSONDecoder().decode(SmartboxResponse.self, from: data)
    if let code = response.code, code != 0 { return [] }
    return response.data?.song?.itemlist ?? []
  }

  private static func cdata(_ tag: String, in xml: String) -> String? {
    let pattern = "<\(tag)(?:\\s[^>]*)?><!\\[CDATA\\[(.*?)\\]\\]></\(tag)>"
    guard let regex = try? NSRegularExpression(
      pattern: pattern,
      options: [.dotMatchesLineSeparators]
    ) else { return nil }
    let range = NSRange(xml.startIndex..., in: xml)
    guard let match = regex.firstMatch(in: xml, range: range),
          let contentRange = Range(match.range(at: 1), in: xml)
    else { return nil }
    return String(xml[contentRange])
  }

  private static func isHex(_ text: String) -> Bool {
    guard !text.isEmpty, text.count % 2 == 0 else { return false }
    return text.allSatisfy { $0.isASCII && $0.isHexDigit }
  }

  /// The decrypted payload is a nested QrcInfos XML whose LyricContent attribute
  /// carries the actual lyric text; native QRC parsing happens in
  /// `LyricsTextParser`.
  private static func qrcText(from decoded: String) -> String? {
    var text = decoded
    if let marker = text.range(of: "LyricContent=\""),
       let end = text[marker.upperBound...].lastIndex(of: "\"") {
      text = String(text[marker.upperBound ..< end])
    }
    text = unescaped(text)
    return text.isEmpty ? nil : text
  }

  private static func unescaped(_ text: String) -> String {
    text
      .replacingOccurrences(of: "&#10;", with: "\n")
      .replacingOccurrences(of: "&#13;", with: "\r")
      .replacingOccurrences(of: "&#32;", with: " ")
      .replacingOccurrences(of: "&#39;", with: "'")
      .replacingOccurrences(of: "&#40;", with: "(")
      .replacingOccurrences(of: "&#41;", with: ")")
      .replacingOccurrences(of: "&#45;", with: "-")
      .replacingOccurrences(of: "&#46;", with: ".")
      .replacingOccurrences(of: "&#58;", with: ":")
      .replacingOccurrences(of: "&#64;", with: "@")
      .replacingOccurrences(of: "&#95;", with: "_")
      .replacingOccurrences(of: "&#124;", with: "|")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&apos;", with: "'")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
  }
}

// MARK: - KugouLyricsProvider

private struct KugouLyricsProvider: OnlineLyricsProvider {
  let source = OnlineLyricsSource.kugou

  private struct SearchResponse: Decodable {
    struct Payload: Decodable {
      let info: [Song]?
    }

    struct TransParam: Decodable {
      let unionCover: String?

      enum CodingKeys: String, CodingKey {
        case unionCover = "union_cover"
      }
    }

    struct Song: Decodable {
      let hash: String?
      let albumAudioID: Int64?
      let albumID: String?
      let songname: String?
      let singername: String?
      let albumName: String?
      let duration: Int?
      let transParam: TransParam?

      enum CodingKeys: String, CodingKey {
        case hash
        case albumAudioID = "album_audio_id"
        case albumID = "album_id"
        case songname
        case singername
        case albumName = "album_name"
        case duration
        case transParam = "trans_param"
      }
    }

    let data: Payload?
  }

  private struct CredentialResponse: Decodable {
    struct Candidate: Decodable {
      let id: String?
      let accesskey: String?
      let song: String?
      let singer: String?
      /// Milliseconds.
      let duration: Int?
    }

    let candidates: [Candidate]?
  }

  private struct DownloadResponse: Decodable {
    let content: String?
    let fmt: String?
  }

  func search(_ query: OnlineLyricsQuery) async throws -> [OnlineLyricsCandidate] {
    let keyword = [query.title, query.artist]
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    var songs = try await request(keyword: keyword)
    if songs.isEmpty, !query.artist.isEmpty {
      songs = try await request(keyword: query.title)
    }
    songs = Self.relevant(
      songs,
      tokens: keyword.split(whereSeparator: \.isWhitespace).map(String.init)
    )

    return songs.compactMap { song in
      guard let hash = song.hash, !hash.isEmpty,
            let name = song.songname, !name.isEmpty
      else { return nil }
      return OnlineLyricsCandidate(
        source: source,
        identifier: "\(hash)|\(song.albumAudioID ?? 0)",
        title: name,
        artist: song.singername ?? "",
        album: song.albumName ?? "",
        duration: max(0, song.duration ?? 0) * 1_000,
        inlineLyrics: nil,
        artworkURL: Self.artworkURL(from: song.transParam?.unionCover),
        albumIdentifier: song.albumID
      )
    }
  }

  func lyrics(for candidate: OnlineLyricsCandidate) async throws -> OnlineLyricsPayload? {
    let parts = candidate.identifier.split(separator: "|", maxSplits: 1)
    guard let hash = parts.first.map(String.init) else { return nil }
    let albumAudioID = parts.count > 1 ? String(parts[1]) : ""

    var credentialItems = [
      URLQueryItem(name: "ver", value: "1"),
      URLQueryItem(name: "man", value: "yes"),
      URLQueryItem(name: "client", value: "mobi"),
      URLQueryItem(name: "hash", value: hash),
    ]
    if !albumAudioID.isEmpty, albumAudioID != "0" {
      credentialItems.append(URLQueryItem(name: "album_audio_id", value: albumAudioID))
    }
    guard let credentialURL = OnlineLyricsHTTP.url(
      base: "https://krcs.kugou.com/search",
      items: credentialItems
    ) else { return nil }

    let credentialData = try await OnlineLyricsHTTP.data(from: credentialURL)
    let credentials = try JSONDecoder().decode(CredentialResponse.self, from: credentialData)
    guard let best = Self.bestCandidate(credentials.candidates ?? [], for: candidate),
          let identifier = best.id, let accesskey = best.accesskey
    else { return nil }

    let downloadURL = OnlineLyricsHTTP.url(
      base: "https://lyrics.kugou.com/download",
      items: [
        URLQueryItem(name: "ver", value: "1"),
        URLQueryItem(name: "client", value: "pc"),
        URLQueryItem(name: "id", value: identifier),
        URLQueryItem(name: "accesskey", value: accesskey),
        URLQueryItem(name: "fmt", value: "krc"),
        URLQueryItem(name: "charset", value: "utf8"),
      ]
    )
    guard let downloadURL else { return nil }
    let downloadData = try await OnlineLyricsHTTP.data(from: downloadURL)
    let download = try JSONDecoder().decode(DownloadResponse.self, from: downloadData)
    guard let content = download.content,
          let decrypted = Self.decrypt(content, format: download.fmt)
    else { return nil }

    return OnlineLyricsPayload(
      text: decrypted,
      translation: nil,
      isWordTimed: KRCFileParser.isKRC(decrypted)
    )
  }

  private func request(keyword: String) async throws -> [SearchResponse.Song] {
    guard let url = OnlineLyricsHTTP.url(
      base: "https://mobiles.kugou.com/api/v3/search/song",
      items: [
        URLQueryItem(name: "format", value: "json"),
        URLQueryItem(name: "keyword", value: keyword),
        URLQueryItem(name: "page", value: "1"),
        URLQueryItem(name: "pagesize", value: "20"),
        URLQueryItem(name: "showtype", value: "1"),
      ]
    ) else { return [] }

    let data = try await OnlineLyricsHTTP.data(from: url)
    let response = try JSONDecoder().decode(SearchResponse.self, from: data)
    return response.data?.info ?? []
  }

  /// Kugou answers an artist hit with that singer's whole catalogue, so keep
  /// only entries whose name covers the title tokens (and singer the rest).
  private static func relevant(
    _ songs: [SearchResponse.Song],
    tokens: [String]
  )
    -> [SearchResponse.Song] {
    let usable = tokens.filter { $0.count >= 2 }
    guard !usable.isEmpty else { return songs }
    let titleTokens = usable.filter { token in
      songs.contains { ($0.songname ?? "").localizedCaseInsensitiveContains(token) }
    }
    let artistTokens = usable.filter { token in
      !titleTokens.contains(token) && songs.contains {
        ($0.singername ?? "").localizedCaseInsensitiveContains(token)
      }
    }
    guard !titleTokens.isEmpty || !artistTokens.isEmpty else { return songs }
    let kept = songs.filter { song in
      let name = song.songname ?? ""
      let singer = song.singername ?? ""
      if !titleTokens.isEmpty {
        return titleTokens.allSatisfy { name.localizedCaseInsensitiveContains($0) }
      }
      return artistTokens.allSatisfy {
        singer.localizedCaseInsensitiveContains($0) || name.localizedCaseInsensitiveContains($0)
      }
    }
    return kept.isEmpty ? songs : kept
  }

  /// The search stage returns one song entry, the lyric stage may offer several
  /// candidates (studio / live / cover). Pick the one closest to the song entry.
  private static func bestCandidate(
    _ candidates: [CredentialResponse.Candidate],
    for target: OnlineLyricsCandidate
  )
    -> CredentialResponse.Candidate? {
    let targetTitle = normalized(target.title)
    let targetArtist = normalized(target.artist)
    var best: (candidate: CredentialResponse.Candidate, score: Int)?

    for candidate in candidates {
      let title = normalized(candidate.song ?? "")
      let artist = normalized(candidate.singer ?? "")
      var score = 0
      if !title.isEmpty, title == targetTitle {
        score += 60
      } else if !title.isEmpty, !targetTitle.isEmpty,
                title.contains(targetTitle) || targetTitle.contains(title) {
        score += 25
      }
      if !targetArtist.isEmpty, !artist.isEmpty {
        if artist == targetArtist {
          score += 25
        } else if artist.contains(targetArtist) || targetArtist.contains(artist) {
          score += 12
        }
      }
      if target.duration > 0, let duration = candidate.duration, duration > 0 {
        let delta = abs(duration - target.duration)
        if delta <= 5_000 {
          score += 10
        } else if delta <= 30_000 {
          score += 4
        }
      }
      if best == nil || score > best!.score {
        best = (candidate, score)
      }
    }
    return best?.candidate
  }

  /// Search results carry the cover template with a `{size}` placeholder.
  private static func artworkURL(from template: String?) -> URL? {
    guard let template, !template.isEmpty else { return nil }
    let sized = template.replacingOccurrences(of: "{size}", with: "400")
    let secure = sized.hasPrefix("http://") ? "https://" + sized.dropFirst(7) : sized
    return URL(string: secure)
  }

  private static func normalized(_ text: String) -> String {
    text.folding(
      options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
      locale: .current
    )
    .filter { !$0.isWhitespace }
  }

  private static func decrypt(_ content: String, format: String?) -> String? {
    guard let data = Data(base64Encoded: content) else { return nil }
    if data.starts(with: Data("krc1".utf8)) {
      return KRCFileParser.decrypt(data)
    }
    guard format != "krc", let plain = String(data: data, encoding: .utf8) else { return nil }
    return plain
  }
}

// MARK: - NetEaseEAPI

private enum NetEaseEAPI {
  private static let urlPath = "/api/song/lyric/v1"
  private static let key = Data("e82ckenh8dichen8".utf8)

  static func params(songID: Int64) -> String? {
    let json =
      "{\"id\":\(songID),\"cp\":false,\"lv\":-1,\"kv\":-1,\"tv\":-1,\"rv\":-1,\"yv\":1,\"ytv\":1,\"yrv\":1}"
    let digest = Insecure.MD5.hash(
      data: Data(("nobody" + urlPath + "use" + json + "md5forencrypt").utf8)
    )
    .map { String(format: "%02x", $0) }
    .joined()
    let text = urlPath + "-36cd479b6b5-" + json + "-36cd479b6b5-" + digest
    guard let encrypted = aesECBEncrypt(Data(text.utf8)) else { return nil }
    return encrypted.map { String(format: "%02x", $0) }.joined()
  }

  private static func aesECBEncrypt(_ data: Data) -> Data? {
    let bufferSize = data.count + kCCBlockSizeAES128
    var buffer = Data(count: bufferSize)
    var encryptedCount = 0
    let status = buffer.withUnsafeMutableBytes { bufferBytes in
      data.withUnsafeBytes { dataBytes in
        key.withUnsafeBytes { keyBytes in
          CCCrypt(
            CCOperation(kCCEncrypt),
            CCAlgorithm(kCCAlgorithmAES),
            CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding),
            keyBytes.baseAddress,
            key.count,
            nil,
            dataBytes.baseAddress,
            data.count,
            bufferBytes.baseAddress,
            bufferSize,
            &encryptedCount
          )
        }
      }
    }
    guard status == kCCSuccess, encryptedCount > 0 else { return nil }
    return Data(buffer.prefix(encryptedCount))
  }
}

// MARK: - OnlineLyricsRanker

enum OnlineLyricsRanker {
  /// Returns nil when the candidate is not a plausible match.
  static func score(candidate: OnlineLyricsCandidate, query: OnlineLyricsQuery) -> Int? {
    let queryTitles = titleVariants(query.title)
    let candidateTitles = titleVariants(candidate.title)
    guard !queryTitles.isEmpty, !candidateTitles.isEmpty else { return nil }

    let isExactTitle = !queryTitles.isDisjoint(with: candidateTitles)
    guard isExactTitle || hasLatinEquivalent(queryTitles, candidateTitles) else { return nil }

    var score = isExactTitle ? 60 : 48

    let expectedArtists = artistNames(query.artist)
    if !expectedArtists.isEmpty {
      let candidateArtists = artistNames(candidate.artist)
      guard !candidateArtists.isEmpty else { return nil }
      if !candidateArtists.isDisjoint(with: expectedArtists) {
        score += 25
      } else if isCompatible(candidateArtists, expectedArtists) {
        score += 15
      } else {
        return nil
      }
    }

    if query.duration > 0, candidate.duration > 0 {
      let deltaMs = abs(query.duration - candidate.duration)
      let toleranceMs = max(20_000, Int(Double(query.duration) * 0.08))
      guard deltaMs <= toleranceMs else { return nil }
      score += max(0, 10 - deltaMs / 1000)
    }

    return score + candidate.source.priorityBonus
  }

  // MARK: Text normalization

  private static let simplifiedTransform = StringTransform("Traditional-Simplified")

  private static func normalized(_ text: String) -> String {
    let simplified = text.applyingTransform(simplifiedTransform, reverse: false) ?? text
    let folded = simplified.folding(
      options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
      locale: .current
    )
    let scalars = folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
    return String(String.UnicodeScalarView(scalars))
  }

  private static func latinNormalized(_ text: String) -> String {
    let latin = text.applyingTransform(.toLatin, reverse: false) ?? text
    return normalized(latin)
  }

  private static func containsNonASCII(_ text: String) -> Bool {
    text.unicodeScalars.contains { !$0.isASCII }
  }

  private static func hasLatinEquivalent(_ lhs: Set<String>, _ rhs: Set<String>) -> Bool {
    let needsTransliteration = lhs.contains(where: containsNonASCII) ||
      rhs.contains(where: containsNonASCII)
    guard needsTransliteration else { return false }
    let latinLHS = Set(lhs.map(latinNormalized).filter { $0.count >= 3 })
    let latinRHS = Set(rhs.map(latinNormalized).filter { $0.count >= 3 })
    return !latinLHS.isDisjoint(with: latinRHS)
  }

  private static func titleVariants(_ raw: String) -> Set<String> {
    var variants = [String]()
    func add(_ value: String) {
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return }
      variants.append(trimmed)
    }

    add(raw)

    var stripped = raw
    for pattern in ["\\([^)]*\\)", "（[^）]*）", "\\[[^\\]]*\\]", "【[^】]*】"] {
      stripped = stripped.replacingOccurrences(
        of: pattern,
        with: " ",
        options: .regularExpression
      )
    }
    add(stripped)

    let withoutFeatures = stripped.replacingOccurrences(
      of: "(?i)\\b(?:feat|ft|prod)\\.?\\s+.*$",
      with: "",
      options: .regularExpression
    )
    add(withoutFeatures)

    for separator in [" - ", " – ", " — ", "~", "～", "〜"] {
      for part in stripped.components(separatedBy: separator) {
        add(part)
      }
      for part in withoutFeatures.components(separatedBy: separator) {
        add(part)
      }
    }

    return Set(variants.map(normalized).filter { !$0.isEmpty })
  }

  private static func artistNames(_ raw: String) -> Set<String> {
    let separators = CharacterSet(charactersIn: ",，/&;；、+")
    var names = [raw]
    names.append(contentsOf: raw.components(separatedBy: separators))
    for marker in [" feat. ", " feat ", " ft. ", " ft ", " with ", " vs. ", " vs "] {
      names = names.flatMap { $0.components(separatedBy: marker) }
    }
    return Set(names.map(normalized).filter { !$0.isEmpty })
  }

  private static func isCompatible(_ lhs: Set<String>, _ rhs: Set<String>) -> Bool {
    for left in lhs {
      for right in rhs {
        guard min(left.count, right.count) >= 3 else { continue }
        if left.contains(right) || right.contains(left) {
          return true
        }
      }
    }
    return false
  }
}

// MARK: - OnlineLyricsLanguage

private enum OnlineLyricsLanguage {
  private static let simplifiedTransform = StringTransform("Traditional-Simplified")

  /// Every Han character the ICU table rewrites. Their presence means the text
  /// needs conversion; the transform alone would also rewrite valid Simplified
  /// words such as 俱乐部 into 具乐部.
  private static let traditionalMarkers: Set<Character> = {
    var markers = Set<Character>()
    for value in 0x3400 ... 0x9FFF {
      guard let scalar = Unicode.Scalar(value) else { continue }
      let text = String(Character(scalar))
      guard let simplified = text.applyingTransform(simplifiedTransform, reverse: false),
            simplified != text
      else { continue }
      markers.insert(Character(scalar))
    }
    // Variants missing from the ICU table, handled as suffix replacements below.
    markers.formUnion("淩祕")
    return markers
  }()

  /// Characters that are valid in Simplified Chinese but mapped differently by
  /// the ICU table (俱→具, 藉→借, 瞭→了).
  private static let protectedCharacters: Set<Character> = ["俱", "藉", "瞭"]

  /// Chinese when the text contains Han characters and no kana or Hangul. A
  /// Chinese song with English words still counts as Chinese.
  static func isChinese(_ text: String) -> Bool {
    var hasHan = false
    for scalar in text.unicodeScalars {
      switch scalar.value {
      case 0x1100 ... 0x11FF, 0x3040 ... 0x30FF,
           0x3130 ... 0x318F, 0x31F0 ... 0x31FF, 0xAC00 ... 0xD7AF:
        return false
      case 0x3400 ... 0x4DBF, 0x4E00 ... 0x9FFF, 0xF900 ... 0xFAFF:
        hasHan = true
      default:
        break
      }
    }
    return hasHan
  }

  static func simplifiedIfChinese(_ text: String) -> String {
    guard isChinese(text), text.contains(where: traditionalMarkers.contains)
    else { return text }

    var converted = ""
    var segment = ""
    for character in text {
      if protectedCharacters.contains(character) {
        converted += segment.applyingTransform(simplifiedTransform, reverse: false)
          ?? segment
        segment = ""
        converted.append(character)
      } else {
        segment.append(character)
      }
    }
    converted += segment.applyingTransform(simplifiedTransform, reverse: false) ?? segment

    return converted
      .replacingOccurrences(of: "瞭解", with: "了解")
      .replacingOccurrences(of: "明瞭", with: "明了")
      .replacingOccurrences(of: "藉口", with: "借口")
      .replacingOccurrences(of: "憑藉", with: "凭借")
      .replacingOccurrences(of: "藉此", with: "借此")
      // Variants the ICU table leaves untouched.
      .replacingOccurrences(of: "淩", with: "凌")
      .replacingOccurrences(of: "祕", with: "秘")
      // 乾 has a gān (乾燥) and a qián (乾隆) reading; the table always maps it to 干.
      .replacingOccurrences(of: "干隆", with: "乾隆")
      .replacingOccurrences(of: "干坤", with: "乾坤")
      // 著 is used for both zhe (走著) and zhù (著名); only restore the zhù words.
      .replacingOccurrences(of: "着名", with: "著名")
      .replacingOccurrences(of: "着作", with: "著作")
      .replacingOccurrences(of: "显着", with: "显著")
      .replacingOccurrences(of: "土着", with: "土著")
      .replacingOccurrences(of: "昭着", with: "昭著")
      .replacingOccurrences(of: "卓着", with: "卓著")
      .replacingOccurrences(of: "着述", with: "著述")
      .replacingOccurrences(of: "着录", with: "著录")
      .replacingOccurrences(of: "编着", with: "编著")
      .replacingOccurrences(of: "论着", with: "论著")
      .replacingOccurrences(of: "原着", with: "原著")
      .replacingOccurrences(of: "名着", with: "名著")
      .replacingOccurrences(of: "巨着", with: "巨著")
      .replacingOccurrences(of: "遗着", with: "遗著")
      .replacingOccurrences(of: "着者", with: "著者")
      .replacingOccurrences(of: "着称", with: "著称")
      .replacingOccurrences(of: "着书", with: "著书")
      .replacingOccurrences(of: "撰着", with: "撰著")
      .replacingOccurrences(of: "专着", with: "专著")
      .replacingOccurrences(of: "合着", with: "合著")
      .replacingOccurrences(of: "译着", with: "译著")
      .replacingOccurrences(of: "着文", with: "著文")
  }
}

// MARK: - OnlineLyricsCacheBuilder

private enum OnlineLyricsCacheBuilder {
  static func build(from payload: OnlineLyricsPayload) -> String? {
    let parsed = LyricsTextParser.parse(payload.text)
    guard let lyrics = parsed.getFirstSyncedLyricsOrUnsyncedAsDefault() else { return nil }

    let lines = lyrics.line.filter { line in
      let value = line.value.trimmingCharacters(in: .whitespacesAndNewlines)
      return !value.isEmpty && !LyricsCreditFilter.isCreditLine(value)
    }
    guard lines.count >= 2 else { return nil }

    let isChinese = OnlineLyricsLanguage.isChinese(
      lines.map(\.value).joined(separator: " ")
    )
    let translations = isChinese ? [] : translationMap(from: payload.translation)
    let isWordTimed = payload.isWordTimed || lines.contains { !$0.words.isEmpty }
    var output = [String]()

    if isWordTimed {
      for (index, line) in lines.enumerated() {
        guard let start = line.start, !line.words.isEmpty else { continue }
        let translated = isChinese ? nil : translatedText(
          at: start,
          translations: translations,
          fallback: line.translation
        )
        let words = line.words.map { word in
          // Word tokens carry meaningful spaces in English lines; only strip
          // characters that would break the one-line YRC format.
          let text = word.value
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
          let cleaned = isChinese
            ? OnlineLyricsLanguage.simplifiedIfChinese(text)
            : text
          return "(\(word.start),\(word.duration),0)\(cleaned)"
        }.joined()
        let nextStart = lines[(index + 1)...].first { $0.start != nil }?.start
        let wordEnd = line.words.map(\.end).max() ?? start + 1
        let duration = max(wordEnd - start, (nextStart ?? start + 1) - start, 1)
        var row = "[\(start),\(duration)]\(words)"
        if let translated {
          row += "\t" + sanitized(
            translated,
            chinese: OnlineLyricsLanguage.isChinese(translated)
          )
        }
        output.append(row)
      }
    } else {
      if lyrics.offset != 0 {
        output.append("[offset:\(lyrics.offset)]")
      }
      for line in lines {
        let value = sanitized(line.value, chinese: isChinese)
        if let start = line.start {
          let translated = isChinese ? nil : translatedText(
            at: start,
            translations: translations,
            fallback: line.translation
          )
          var row = "[\(timestamp(start))]\(value)"
          if let translated {
            row += "\t" + sanitized(
              translated,
              chinese: OnlineLyricsLanguage.isChinese(translated)
            )
          }
          output.append(row)
        } else {
          var row = value
          if let translation = line.translation, !isChinese {
            row += "\t" + sanitized(
              translation,
              chinese: OnlineLyricsLanguage.isChinese(translation)
            )
          }
          output.append(row)
        }
      }
    }

    guard output.count >= 2 else { return nil }
    return output.joined(separator: "\n")
  }

  private static func translationMap(from text: String?) -> [(start: Int, text: String)] {
    guard let text else { return [] }
    let parsed = LyricsTextParser.parse(text)
    guard let lyrics = parsed.getFirstSyncedLyricsOrUnsyncedAsDefault() else { return [] }
    return lyrics.line.compactMap { line in
      guard let start = line.start else { return nil }
      let value = line.value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !value.isEmpty else { return nil }
      return (start, value)
    }.sorted { $0.start < $1.start }
  }

  private static func translatedText(
    at start: Int,
    translations: [(start: Int, text: String)],
    fallback: String?
  )
    -> String? {
    var best: (start: Int, text: String)?
    for item in translations {
      let delta = abs(item.start - start)
      guard delta <= 300 else { continue }
      if best == nil || delta < abs(best!.start - start) {
        best = item
      }
    }
    let value = best?.text ?? fallback
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func sanitized(_ text: String, chinese: Bool) -> String {
    let cleaned = text
      .replacingOccurrences(of: "\t", with: " ")
      .replacingOccurrences(of: "\n", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return chinese ? OnlineLyricsLanguage.simplifiedIfChinese(cleaned) : cleaned
  }

  private static func timestamp(_ milliseconds: Int) -> String {
    let minutes = milliseconds / 60_000
    let seconds = (milliseconds / 1_000) % 60
    let millis = milliseconds % 1_000
    return String(format: "%02d:%02d.%03d", minutes, seconds, millis)
  }
}

// MARK: - OnlineLyricsService

@MainActor
public final class OnlineLyricsService {
  public static let shared = OnlineLyricsService()

  private let providers: [any OnlineLyricsProvider] = [
    LRCLIBLyricsProvider(),
    NetEaseLyricsProvider(),
    QQMusicLyricsProvider(),
    KugouLyricsProvider(),
  ]
  private var inFlight = [String: Task<Bool, Never>]()
  private var attempted = Set<String>()

  private init() {}

  /// True when an automatic lookup would actually start, i.e. the song has no lyrics
  /// file yet and the same metadata has not failed before in this session.
  public func canMatchLyrics(for song: Song) -> Bool {
    guard FmusicKit.shared.settings.user.isOnlineMode,
          song.lyricsRelFilePath == nil,
          let query = makeQuery(for: song)
    else { return false }
    let key = makeKey(for: song, query: query)
    return !attempted.contains(key)
  }

  /// Looks up lyrics for songs without a lyrics file and stores the result in the
  /// fmusic cache, so all existing lyrics views pick it up on the next refresh.
  @discardableResult
  public func matchLyrics(for song: Song, force: Bool = false) async -> Bool {
    guard FmusicKit.shared.settings.user.isOnlineMode else { return false }
    guard let query = makeQuery(for: song) else { return false }
    if !force, song.lyricsRelFilePath != nil { return false }

    let key = makeKey(for: song, query: query)
    if !force, attempted.contains(key) { return false }
    if let task = inFlight[key] {
      return await task.value
    }

    let task = Task<Bool, Never> { [weak self] in
      guard let self else { return false }
      return await performMatch(song: song, query: query)
    }
    inFlight[key] = task
    let result = await task.value
    inFlight[key] = nil
    if !result {
      attempted.insert(key)
    }
    return result
  }

  /// Looks up an album for a song whose file tags do not provide one. The
  /// provider candidate must pass the same title/artist/duration identity
  /// checks used for lyrics, so a loose keyword hit cannot rename an album.
  public func matchMetadata(for song: Song) async -> OnlineMetadataMatch? {
    guard FmusicKit.shared.settings.user.isOnlineMode,
          let query = makeQuery(for: song)
    else { return nil }
    let scored = await searchCandidates(for: query)
    let withAlbum = scored.compactMap { entry -> (entry: ScoredCandidate, album: String)? in
      guard let album = Self.sanitizedAlbum(entry.candidate.album) else { return nil }
      return (entry, album)
    }
    if let best = withAlbum.max(by: { lhs, rhs in
      if lhs.entry.score != rhs.entry.score { return lhs.entry.score < rhs.entry.score }
      return lhs.entry.candidate.source.priorityBonus <
        rhs.entry.candidate.source.priorityBonus
    }), best.entry.score >= 85 {
      return OnlineMetadataMatch(
        album: best.album,
        source: best.entry.candidate.source,
        score: best.entry.score,
        artworkURL: await artworkURL(
          for: best.album,
          preferred: best.entry,
          in: scored
        )
      )
    }

    // QQ search omits albums; ask its single-song endpoint for the best
    // already-verified candidates that LRCLIB could not cover.
    let qqCandidates = scored
      .filter { $0.candidate.source == .qqmusic && $0.score >= 85 }
      .sorted { $0.score > $1.score }
    for entry in qqCandidates.prefix(3) {
      guard let qq = provider(for: .qqmusic),
            let raw = try? await qq.album(for: entry.candidate),
            let album = Self.sanitizedAlbum(raw)
      else { continue }
      return OnlineMetadataMatch(
        album: album,
        source: .qqmusic,
        score: entry.score,
        artworkURL: await artworkURL(for: album, preferred: entry, in: scored)
      )
    }
    return nil
  }

  /// Prefer the provider that supplied the album, then any other high-scoring
  /// candidate carrying the same album. LRCLIB has no cover, so this usually
  /// lands on NetEase, QQ or Kugou without relaxing the identity checks.
  private func artworkURL(
    for album: String,
    preferred: ScoredCandidate,
    in scored: [ScoredCandidate]
  ) async
    -> URL? {
    var entries = [preferred]
    entries.append(
      contentsOf: scored.filter { entry in
        entry.candidate.identifier != preferred.candidate.identifier ||
          entry.candidate.source != preferred.candidate.source
      }
      .filter { entry in
        guard let candidateAlbum = Self.sanitizedAlbum(entry.candidate.album)
        else { return false }
        return candidateAlbum.compare(album, options: .caseInsensitive) == .orderedSame
      }
      .sorted { $0.score > $1.score }
    )
    // Compilation albums often exist only in LRCLIB; a cover from the same
    // song's canonical release is still better than the placeholder.
    entries.append(
      contentsOf: scored
        .filter { $0.score >= 85 && $0.candidate.source != .lrclib }
        .sorted { $0.score > $1.score }
    )
    var seen = Set<String>()
    for entry in entries.prefix(10) {
      let key = "\(entry.candidate.source.rawValue)|\(entry.candidate.identifier)"
      guard seen.insert(key).inserted,
            let provider = provider(for: entry.candidate.source)
      else { continue }
      if let url = await provider.artworkURL(for: entry.candidate) {
        return url
      }
    }
    return nil
  }

  /// LRCLIB carries user-contributed metadata; a few entries embed Swift's
  /// debug description of an optional, e.g. `Optional("不良少年")`.
  private static func sanitizedAlbum(_ raw: String) -> String? {
    var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    for wrapper in ["Optional(\"", "Some(\""] {
      if value.hasPrefix(wrapper), value.hasSuffix("\")") {
        value = String(value.dropFirst(wrapper.count).dropLast(2))
          .trimmingCharacters(in: .whitespacesAndNewlines)
        break
      }
    }
    guard !value.isEmpty else { return nil }
    if value.hasPrefix("Optional(") || value.hasPrefix("Some(") { return nil }
    switch value.lowercased() {
    case "未知专辑", "未知專輯", "n/a", "nil", "none", "null", "unknown album":
      return nil
    default:
      return value
    }
  }

  // MARK: Manual search

  /// Free text search across all providers for the lyrics search page. The results
  /// are not filtered against the current song: the user picks the version to apply.
  public func searchLyrics(keyword: String) async -> [OnlineLyricsSearchResult] {
    let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count >= 2 else { return [] }
    let query = OnlineLyricsQuery(title: trimmed, artist: "", album: "", duration: 0)

    var candidates = [(source: OnlineLyricsSource, index: Int, candidate: OnlineLyricsCandidate)]()
    await withTaskGroup(of: (OnlineLyricsSource, [OnlineLyricsCandidate]).self) { group in
      for provider in providers {
        group.addTask {
          (provider.source, (try? await provider.search(query)) ?? [])
        }
      }
      for await (source, list) in group {
        for (index, candidate) in list.enumerated() {
          candidates.append((source, index, candidate))
        }
      }
    }

    let key = Self.searchKey(trimmed)
    candidates.sort { lhs, rhs in
      let lhsRank = Self.searchRank(lhs.candidate, key: key)
      let rhsRank = Self.searchRank(rhs.candidate, key: key)
      if lhsRank != rhsRank { return lhsRank < rhsRank }
      if lhs.source != rhs.source {
        return Self.manualSourceRank(lhs.source) < Self.manualSourceRank(rhs.source)
      }
      return lhs.index < rhs.index
    }

    // Keep one entry per source: the same title/artist often exists in several
    // providers and the UI filter should still have something to show.
    var seen = Set<String>()
    var results = [OnlineLyricsSearchResult]()
    for entry in candidates {
      let candidate = entry.candidate
      let dedupeKey = [
        entry.source.rawValue,
        Self.searchKey(candidate.title),
        Self.searchKey(candidate.artist),
      ].joined(separator: "|")
      guard seen.insert(dedupeKey).inserted else { continue }
      results.append(OnlineLyricsSearchResult(
        id: "\(entry.source.rawValue):\(candidate.identifier)",
        title: candidate.title,
        artist: candidate.artist,
        album: candidate.album,
        duration: candidate.duration,
        source: entry.source,
        candidate: candidate
      ))
      if results.count >= 40 { break }
    }
    return results
  }

  /// Word timed providers first, plain LRC last.
  private static func manualSourceRank(_ source: OnlineLyricsSource) -> Int {
    switch source {
    case .netease: 0
    case .qqmusic: 1
    case .kugou: 2
    case .lrclib: 3
    }
  }

  /// Fetches and converts the lyrics of a search result for the preview page.
  public func preview(_ result: OnlineLyricsSearchResult) async -> OnlineLyricsMatch? {
    guard let provider = provider(for: result.candidate.source),
          let payload = try? await provider.lyrics(for: result.candidate),
          let text = OnlineLyricsCacheBuilder.build(from: payload)
    else { return nil }
    return Self.makeMatch(text: text, format: Self.detectFormat(payload.text))
  }

  /// Fetches the lyrics of a search result just far enough to know its native
  /// suffix, so the result list can show YRC/QRC/KRC/LRC before applying.
  public func probeFormat(_ result: OnlineLyricsSearchResult) async -> OnlineLyricsFormat? {
    guard let provider = provider(for: result.candidate.source),
          let payload = try? await provider.lyrics(for: result.candidate)
    else { return nil }
    return Self.detectFormat(payload.text)
  }

  private static func detectFormat(_ text: String) -> OnlineLyricsFormat {
    if QRCFileParser.isQRC(text) { return .qrc }
    if KRCFileParser.isKRC(text) { return .krc }
    if YRCFileParser.isYRC(text) { return .yrc }
    if lrcTimestampPattern?.firstMatch(
      in: text,
      range: NSRange(text.startIndex..., in: text)
    ) != nil {
      return .lrc
    }
    return .txt
  }

  private static let lrcTimestampPattern = try? NSRegularExpression(
    pattern: "^\\[\\d{1,3}:\\d{2}([.:]\\d{1,3})?\\]",
    options: [.anchorsMatchLines]
  )

  /// Writes the lyrics into the fmusic cache and points the song at the new file.
  @discardableResult
  public func apply(_ match: OnlineLyricsMatch, to song: Song) -> Bool {
    store(match.text, for: song)
  }

  private static func makeMatch(
    text: String,
    format: OnlineLyricsFormat
  )
    -> OnlineLyricsMatch? {
    let parsed = LyricsTextParser.parse(text)
    guard let lyrics = parsed.getFirstSyncedLyricsOrUnsyncedAsDefault() else { return nil }

    var rows = [OnlineLyricsMatch.Line]()
    var lineCount = 0
    var isWordTimed = false
    var hasTranslation = false
    for line in lyrics.line {
      let value = line.value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !value.isEmpty else { continue }
      lineCount += 1
      if !line.words.isEmpty { isWordTimed = true }
      rows.append(.init(text: value, isTranslation: false))
      if let translation = line.translation?
        .trimmingCharacters(in: .whitespacesAndNewlines), !translation.isEmpty {
        hasTranslation = true
        rows.append(.init(text: translation, isTranslation: true))
      }
    }
    guard lineCount >= 2 else { return nil }

    return OnlineLyricsMatch(
      text: text,
      lines: rows,
      isWordTimed: isWordTimed,
      hasTranslation: hasTranslation,
      lineCount: lineCount,
      format: format
    )
  }

  private static func searchKey(_ text: String) -> String {
    text.folding(
      options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
      locale: .current
    )
    .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func searchRank(_ candidate: OnlineLyricsCandidate, key: String) -> Int {
    let title = searchKey(candidate.title)
    let artist = searchKey(candidate.artist)
    let tokens = key.split(whereSeparator: \.isWhitespace)
      .map(String.init)
      .filter { $0.count >= 2 }
    if title == key { return 0 }
    // A single-token query is a plain title search; with an artist token the
    // title alone must not outrank the recording the user asked for.
    if tokens.count <= 1 {
      if title.contains(key) || key.contains(title) { return 1 }
    } else if title.contains(key) {
      return 1
    }

    let titleMatches = tokens.contains { title.contains($0) }
    let artistMatches = tokens.contains { artist.contains($0) }
    if titleMatches {
      return artistMatches ? 1 : 2
    }
    if artistMatches { return 3 }
    return 4
  }

  // MARK: Query

  private func makeQuery(for song: Song) -> OnlineLyricsQuery? {
    let title = Self.meaningful(
      song.playableManagedObject.title,
      placeholder: "Unknown Title"
    )
    guard !title.isEmpty else { return nil }
    let artist = Self.meaningful(
      song.artist?.managedObject.name,
      placeholder: "Unknown Artist"
    )
    let album = Self.meaningful(
      song.album?.managedObject.name,
      placeholder: "Unknown Album"
    )
    let seconds = song.duration > 0 ? song.duration : song.remoteDuration
    let duration = max(0, seconds) * 1000
    return OnlineLyricsQuery(
      title: title,
      artist: artist,
      album: album,
      duration: duration
    )
  }

  private static func meaningful(_ value: String?, placeholder: String) -> String {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed == placeholder ? "" : trimmed
  }

  private func makeKey(for song: Song, query: OnlineLyricsQuery) -> String {
    [
      song.account?.info.ident ?? "",
      song.id,
      query.title,
      query.artist,
      query.album,
      String(query.duration),
    ].joined(separator: "|")
  }

  // MARK: Matching

  private func performMatch(song: Song, query: OnlineLyricsQuery) async -> Bool {
    let scored = await searchCandidates(for: query)
    guard let best = await chooseLyrics(from: scored) else {
      os_log(
        "Online lyrics: no match for %{public}@",
        log: FmusicKit.shared.log,
        type: .info,
        query.title
      )
      return false
    }
    os_log(
      "Online lyrics: chosen score=%d head=%{public}@",
      log: onlineLyricsLog,
      type: .info,
      best.score,
      String(best.text.prefix(120))
    )
    guard store(best.text, for: song) else { return false }
    os_log(
      "Online lyrics: stored result for %{public}@ with score %d",
      log: FmusicKit.shared.log,
      type: .info,
      query.title,
      best.score
    )
    return true
  }

  private func searchCandidates(for query: OnlineLyricsQuery) async -> [ScoredCandidate] {
    await withTaskGroup(of: [ScoredCandidate].self) { group in
      for provider in providers {
        group.addTask {
          let candidates: [OnlineLyricsCandidate]
          do {
            candidates = try await provider.search(query)
          } catch {
            return []
          }
          return candidates.compactMap { candidate in
            guard let score = OnlineLyricsRanker.score(candidate: candidate, query: query)
            else { return nil }
            return ScoredCandidate(candidate: candidate, score: score)
          }
        }
      }

      var results = [ScoredCandidate]()
      for await partial in group {
        results.append(contentsOf: partial)
      }
      // Keep each source represented: one provider can return dozens of near-identical
      // results and crowd the others out before their lyrics are ever fetched.
      var kept = [ScoredCandidate]()
      for source in OnlineLyricsSource.allCases {
        kept.append(
          contentsOf: results
            .filter { $0.candidate.source == source }
            .sorted {
              if $0.score != $1.score { return $0.score > $1.score }
              return $0.candidate.identifier < $1.candidate.identifier
            }
            .prefix(6)
        )
      }
      return kept.sorted {
        if $0.score != $1.score { return $0.score > $1.score }
        return $0.candidate.source.rawValue < $1.candidate.source.rawValue
      }
    }
  }

  private func chooseLyrics(from scored: [ScoredCandidate]) async -> ChosenLyrics? {
    guard !scored.isEmpty else { return nil }

    var inline = [(ScoredCandidate, OnlineLyricsPayload)]()
    var pending = [ScoredCandidate]()
    for candidate in scored {
      if let payload = candidate.candidate.inlineLyrics {
        inline.append((candidate, payload))
      } else {
        pending.append(candidate)
      }
    }

    var fetchTargets = [ScoredCandidate]()
    for source in OnlineLyricsSource.allCases {
      fetchTargets.append(
        contentsOf: pending.filter { $0.candidate.source == source }.prefix(2)
      )
    }

    var fetched = [(ScoredCandidate, OnlineLyricsPayload)]()
    await withTaskGroup(of: (ScoredCandidate, OnlineLyricsPayload)?.self) { group in
      for candidate in fetchTargets {
        guard let provider = provider(for: candidate.candidate.source) else { continue }
        group.addTask {
          guard let payload = try? await provider.lyrics(for: candidate.candidate)
          else { return nil }
          return (candidate, payload)
        }
      }
      for await result in group {
        guard let result else { continue }
        fetched.append(result)
      }
    }

    var best: ChosenLyrics?
    for (candidate, payload) in inline {
      guard let chosen = evaluate(payload: payload, candidate: candidate) else { continue }
      if best == nil || chosen.score > best!.score {
        best = chosen
      }
    }
    for (candidate, payload) in fetched {
      guard let chosen = evaluate(payload: payload, candidate: candidate) else { continue }
      if best == nil || chosen.score > best!.score {
        best = chosen
      }
    }
    return best
  }

  private func evaluate(payload: OnlineLyricsPayload, candidate: ScoredCandidate) -> ChosenLyrics? {
    guard let text = OnlineLyricsCacheBuilder.build(from: payload) else { return nil }
    let lyricsList = LyricsTextParser.parse(text)
    guard let lyrics = lyricsList.getFirstSyncedLyricsOrUnsyncedAsDefault() else { return nil }
    let lineCount = lyrics.line
      .filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .count
    guard lineCount >= 2 else { return nil }

    var score = candidate.score
    score += lyrics.synced ? 12 : -8
    let wordTimed = lyrics.line.contains(where: { !$0.words.isEmpty })
    if wordTimed {
      score += 18
    }
    let translated = lyrics.line.contains(where: {
      !($0.translation?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    })
    if translated {
      score += 8
    }
    os_log(
      "candidate %{public}@ %{public}@ base=%d final=%d lines=%d word=%d trans=%d",
      log: onlineLyricsLog,
      type: .info,
      candidate.candidate.source.rawValue,
      candidate.candidate.title,
      candidate.score,
      score,
      lyrics.line.count,
      wordTimed ? 1 : 0,
      translated ? 1 : 0
    )
    return ChosenLyrics(text: text, score: score)
  }

  private func provider(for source: OnlineLyricsSource) -> (any OnlineLyricsProvider)? {
    providers.first { $0.source == source }
  }

  // MARK: Storage

  private func store(_ text: String, for song: Song) -> Bool {
    guard !song.managedObject.isDeleted,
          text.utf8.count <= 2 * 1024 * 1024,
          let account = song.account,
          let relFilePath = CacheFileManager.shared.createRelPath(forLyricsOf: song),
          let absoluteFilePath = CacheFileManager.shared
          .getAbsolutefmusicPath(relFilePath: relFilePath)
    else { return false }

    let fileManager = CacheFileManager.shared
    fileManager.createDirectoryIfNeeded(at: absoluteFilePath.deletingLastPathComponent())
    do {
      try fileManager.writeDataExcludedFromBackup(
        data: Data(text.utf8),
        to: absoluteFilePath,
        accountInfo: account.info
      )
    } catch {
      os_log(
        "Online lyrics: write failed: %{public}@",
        log: FmusicKit.shared.log,
        type: .error,
        error.localizedDescription
      )
      return false
    }

    song.lyricsRelFilePath = relFilePath
    FmusicKit.shared.storage.main.saveContext()
    FmusicKit.shared.notificationHandler.post(
      name: .onlineLyricsDidUpdate,
      object: nil,
      userInfo: ["songID": song.id]
    )
    return true
  }
}
