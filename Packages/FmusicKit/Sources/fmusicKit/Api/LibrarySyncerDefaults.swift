//
//  LibrarySyncerDefaults.swift
//  fmusicKit
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import Foundation

/// File based library sources have no server side catalogue: everything is
/// already stored in Core Data after indexing. These defaults keep the
/// server oriented `LibrarySyncer` surface usable for local and WebDAV sources.
@MainActor
extension LibrarySyncer {
  public func sync(genre: Genre) async throws {}
  public func sync(artist: Artist) async throws {}
  public func sync(album: Album) async throws {}
  public func sync(song: Song) async throws {}
  public func sync(podcast: Podcast) async throws {}
  public func syncNewestAlbums(offset: Int, count: Int) async throws {}
  public func syncRecentAlbums(offset: Int, count: Int) async throws {}
  public func syncNewestPodcastEpisodes() async throws {}
  public func syncFavoriteLibraryElements() async throws {}
  public func syncRadios() async throws {}
  public func syncDownPlaylistsWithoutSongs() async throws {}
  public func syncDown(playlist: Playlist) async throws {}
  public func syncUpload(playlistToUpdateName playlist: Playlist) async throws {}
  public func syncUpload(playlistToAddSongs playlist: Playlist, songs: [Song]) async throws {}
  public func syncUpload(playlistToDeleteSong playlist: Playlist, index: Int) async throws {}
  public func syncUpload(playlistToUpdateOrder playlist: Playlist) async throws {}
  public func syncUpload(playlistIdToDelete id: String) async throws {}
  public func syncDownPodcastsWithoutEpisodes() async throws {}
  public func searchArtists(searchText: String) async throws {}
  public func searchAlbums(searchText: String) async throws {}
  public func searchSongs(searchText: String) async throws {}
  public func syncMusicFolders() async throws {}
  public func syncIndexes(musicFolder: MusicFolder) async throws {}
  public func sync(directory: Directory) async throws {}
  public func requestRandomSongs(playlist: Playlist, count: Int) async throws {}
  public func requestSimilarSongs(song: Song, count: Int) async throws -> [Song] { [] }
  public func requestPodcastEpisodeDelete(podcastEpisode: PodcastEpisode) async throws {}

  public func setFavorite(song: Song, isFavorite: Bool) async throws {
    song.isFavorite = isFavorite
    song.starredDate = isFavorite ? Date() : nil
  }

  public func setFavorite(album: Album, isFavorite: Bool) async throws {
    album.isFavorite = isFavorite
    album.starredDate = isFavorite ? Date() : nil
  }

  public func setFavorite(artist: Artist, isFavorite: Bool) async throws {
    artist.isFavorite = isFavorite
    artist.starredDate = isFavorite ? Date() : nil
  }

  public func parseLyrics(relFilePath: URL) async throws -> LyricsList {
    await Task.detached(priority: .userInitiated) {
      let fileManager = CacheFileManager.shared
      guard let absoluteFilePath = fileManager.getAbsolutefmusicPath(relFilePath: relFilePath),
            let data = try? Data(contentsOf: absoluteFilePath)
      else { return LyricsList() }
      return LyricsTextParser.parse(data: data)
    }.value
  }
}

// MARK: - StructuredLyrics + WordTiming

public extension StructuredLyrics {
  var isWordTimed: Bool {
    line.contains { !$0.words.isEmpty }
  }
}

// MARK: - LyricsTextParser

enum LyricsTextParser {
  static func parse(_ content: String) -> LyricsList {
    if QRCFileParser.isQRC(content) {
      return QRCFileParser.parse(content)
    }
    if KRCFileParser.isKRC(content) {
      return KRCFileParser.parse(content)
    }
    return YRCFileParser.isYRC(content) ? YRCFileParser.parse(content) : LRCFileParser
      .parse(content)
  }

  static func parse(data: Data) -> LyricsList {
    guard let content = LyricsSidecarReader.text(from: data) else { return LyricsList() }
    return parse(content)
  }

  static func isWordTimed(_ content: String) -> Bool {
    QRCFileParser.isQRC(content) || KRCFileParser.isKRC(content) || YRCFileParser.isYRC(content)
  }

  static func isWordTimed(data: Data) -> Bool {
    guard let content = LyricsSidecarReader.text(from: data) else { return false }
    return isWordTimed(content)
  }

  static func isWordTimed(fileURL: URL) -> Bool {
    guard let data = try? Data(contentsOf: fileURL) else { return false }
    return isWordTimed(data: data)
  }

  /// Picks the richer local lyric source: word-timed (YRC/QRC/KRC) always
  /// beats line-timed LRC, with sidecar winning ties over embedded tags.
  static func preferredLocalLyrics(sidecar: String?, embedded: String?) -> String? {
    let cleanSidecar = sidecar?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
      ? sidecar
      : nil
    let cleanEmbedded = embedded?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
      ? embedded
      : nil
    if let cleanSidecar, isWordTimed(cleanSidecar) { return cleanSidecar }
    if let cleanEmbedded, isWordTimed(cleanEmbedded) { return cleanEmbedded }
    return cleanSidecar ?? cleanEmbedded
  }
}

// MARK: - LyricsSidecarReader

/// Reads sidecar lyric files in any supported format. KRC ships as a binary
/// `krc1` + XOR + zlib container, QRC as UTF-8/hex text, LRC/YRC as text.
enum LyricsSidecarReader {
  static func text(from data: Data) -> String? {
    if data.starts(with: Data("krc1".utf8)) {
      return KRCFileParser.decrypt(data)
    }
    return String(data: data, encoding: .utf8)
  }
}

// MARK: - LyricsCreditFilter

enum LyricsCreditFilter {
  private static let pattern = try? NSRegularExpression(
    pattern: "^(作词人?|作曲人?|编曲|制作人|制作|出品人|出品监制|出品|发行|混音师?|母带师?|录音师|录音棚|人声录音师|人声录音棚|录音作品及MV版权|录音作品|录音|制作统筹|统筹|企划|监制|和声|吉他|贝斯|鼓|弦乐|键盘|词版权管理方|词版权|曲版权管理方|曲版权|联合出品|词|曲|OP|SP|演唱|原唱|翻唱)\\s*[:：]",
    options: []
  )

  static func isCreditLine(_ text: String) -> Bool {
    guard let pattern else { return false }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return pattern.firstMatch(
      in: trimmed,
      range: NSRange(trimmed.startIndex..., in: trimmed)
    ) != nil
  }
}

// MARK: - YRCFileParser

/// NetEase word-synced lyrics: `[lineStart,lineDuration](wordStart,wordDuration,0)word`
enum YRCFileParser {
  private static let linePattern = try? NSRegularExpression(
    pattern: "^\\[(\\d{1,9}),(\\d{1,9})\\]",
    options: []
  )
  private static let wordTagPattern = try? NSRegularExpression(
    pattern: "\\((\\d{1,9}),(\\d{1,9}),(\\d{1,3})\\)",
    options: []
  )

  static func isYRC(_ content: String) -> Bool {
    content.components(separatedBy: .newlines).contains { rawLine in
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      guard !line.isEmpty, !line.hasPrefix("{") else { return false }
      return linePattern?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line))
        != nil
    }
  }

  static func parse(_ content: String) -> LyricsList {
    var lines = [LyricsLine]()
    for rawLine in content.components(separatedBy: .newlines) {
      guard let line = parseLine(rawLine) else { continue }
      lines.append(line)
    }

    var lyrics = StructuredLyrics()
    lyrics.lang = "und"
    lyrics.synced = !lines.isEmpty
    lyrics.line = lines.sorted { ($0.start ?? 0) < ($1.start ?? 0) }
    var list = LyricsList()
    list.lyrics = [lyrics]
    return list
  }

  private static func parseLine(_ rawLine: String) -> LyricsLine? {
    // Credit rows are JSON objects, not timed text.
    let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty, !trimmed.hasPrefix("{"), let linePattern else { return nil }

    var timedPart = trimmed
    var translation: String?
    if let tabIndex = trimmed.firstIndex(of: "\t") {
      timedPart = String(trimmed[..<tabIndex]).trimmingCharacters(in: .whitespaces)
      let translated = String(trimmed[trimmed.index(after: tabIndex)...])
        .trimmingCharacters(in: .whitespacesAndNewlines)
      translation = translated.isEmpty ? nil : translated
    }

    let text = timedPart as NSString
    let fullRange = NSRange(location: 0, length: text.length)
    guard let header = linePattern.firstMatch(in: timedPart, range: fullRange),
          let start = Int(text.substring(with: header.range(at: 1)))
    else { return nil }

    let bodyStart = header.range.location + header.range.length
    let bodyRange = NSRange(location: bodyStart, length: text.length - bodyStart)
    let tags = wordTagPattern?.matches(in: timedPart, range: bodyRange) ?? []
    guard !tags.isEmpty else { return nil }

    var words = [LyricWord]()
    for (index, tag) in tags.enumerated() {
      let wordStart = Int(text.substring(with: tag.range(at: 1))) ?? 0
      let duration = Int(text.substring(with: tag.range(at: 2))) ?? 0
      let wordTextStart = tag.range.location + tag.range.length
      let wordTextEnd = index + 1 < tags.count ? tags[index + 1].range.location : text.length
      guard wordTextEnd >= wordTextStart else { continue }
      let wordText = text.substring(
        with: NSRange(location: wordTextStart, length: wordTextEnd - wordTextStart)
      )
      words.append(LyricWord(start: wordStart, duration: duration, value: wordText))
    }

    let spacedWords = LyricsWordSpacing.insertPauseSpaces(into: words)
    let value = spacedWords.map(\.value).joined()
    guard !value.trimmingCharacters(in: .whitespaces).isEmpty,
          !LyricsCreditFilter.isCreditLine(value)
    else { return nil }

    var line = LyricsLine()
    line.start = start
    line.value = value
    line.translation = translation
    line.words = spacedWords
    return line
  }
}

// MARK: - LyricsWordSpacing

/// Inserts a natural space between timed words separated by a vocal pause
/// (e.g. phrase breaks in CJK lyrics) when the source omits spaces.
private enum LyricsWordSpacing {
  private static let pauseGapThresholdMs = 260
  private static let noSpaceBefore: Set<Character> = [
    ",", "，", ".", "。", "!", "！", "?", "？", "、", ":", "：", ";", "；",
    ")", "）", "]", "】", "》", "」", "』", "\"", "”", "'", "’", "~", "～",
  ]
  private static let noSpaceAfter: Set<Character> = [
    "(", "（", "[", "【", "《", "「", "『", "“", "‘",
  ]

  static func insertPauseSpaces(into words: [LyricWord]) -> [LyricWord] {
    guard words.count > 1 else { return words }
    var result = words
    for index in 0 ..< (result.count - 1) {
      let current = result[index]
      let next = result[index + 1]
      guard !current.value.isEmpty, !next.value.isEmpty else { continue }
      guard let lastChar = current.value.last, let firstChar = next.value.first else { continue }
      if lastChar.isWhitespace || firstChar.isWhitespace { continue }
      if noSpaceAfter.contains(lastChar) || noSpaceBefore.contains(firstChar) { continue }
      let gapMs = next.start - (current.start + current.duration)
      if gapMs >= pauseGapThresholdMs {
        result[index] = LyricWord(
          start: current.start,
          duration: current.duration,
          value: current.value + " "
        )
      }
    }
    return result
  }
}

// MARK: - LRCFileParser

enum LRCFileParser {
  private static let timestampPattern = try? NSRegularExpression(
    pattern: "^\\[(\\d{1,3}):(\\d{1,2})(?:[.:](\\d{1,3}))?\\]",
    options: []
  )
  private static let offsetPattern = try? NSRegularExpression(
    pattern: "\\[offset:\\s*([+-]?\\d+)\\s*\\]",
    options: [.caseInsensitive]
  )

  static func parse(_ content: String) -> LyricsList {
    var lines = [LyricsLine]()
    var isSynced = false
    var offsetMs = 0

    if let offsetPattern,
       let match = offsetPattern.firstMatch(
         in: content,
         range: NSRange(content.startIndex..., in: content)
       ),
       let valueRange = Range(match.range(at: 1), in: content),
       let value = Int(content[valueRange]) {
      offsetMs = value
    }

    for rawLine in content.components(separatedBy: .newlines) {
      var remaining = rawLine.trimmingCharacters(in: .whitespaces)
      guard !remaining.isEmpty else { continue }

      if remaining.hasPrefix("["),
         let closingIndex = remaining.dropFirst().firstIndex(of: "]") {
        let tag = remaining[remaining.index(after: remaining.startIndex) ..< closingIndex]
        if tag.contains(":") {
          let key = tag.split(separator: ":", maxSplits: 1).first?
            .trimmingCharacters(in: .whitespaces) ?? ""
          let isTimestamp = !key.isEmpty && key.allSatisfy(\.isNumber)
          if !isTimestamp { continue }
        }
      }

      var timestamps = [Int]()
      while let match = timestampPattern?.firstMatch(
        in: remaining,
        range: NSRange(remaining.startIndex..., in: remaining)
      ) {
        guard let minutesRange = Range(match.range(at: 1), in: remaining),
              let secondsRange = Range(match.range(at: 2), in: remaining),
              let minutes = Int(remaining[minutesRange]),
              let seconds = Int(remaining[secondsRange])
        else { break }
        var milliseconds = 0
        if let fractionRange = Range(match.range(at: 3), in: remaining),
           let fraction = Int(remaining[fractionRange]) {
          let digits = remaining[fractionRange].count
          milliseconds = digits == 1 ? fraction * 100 : (digits == 2 ? fraction * 10 : fraction)
        }
        timestamps.append(((minutes * 60) + seconds) * 1000 + milliseconds)
        guard let fullRange = Range(match.range, in: remaining) else { break }
        remaining = String(remaining[fullRange.upperBound...])
          .trimmingCharacters(in: .whitespaces)
      }

      guard !remaining.isEmpty else { continue }
      // Malformed tags such as `[00:00.00-1]` survive timestamp parsing; a
      // bracket left at the start is metadata, never sung text.
      if remaining.hasPrefix("[") { continue }

      var value = remaining
      var translation: String?
      if let tabIndex = remaining.firstIndex(of: "\t") {
        value = String(remaining[..<tabIndex]).trimmingCharacters(in: .whitespaces)
        let translated = String(remaining[remaining.index(after: tabIndex)...])
          .trimmingCharacters(in: .whitespacesAndNewlines)
        translation = translated.isEmpty ? nil : translated
      }
      guard !value.isEmpty, !LyricsCreditFilter.isCreditLine(value) else { continue }

      if timestamps.isEmpty {
        var line = LyricsLine()
        line.value = value
        line.translation = translation
        lines.append(line)
      } else {
        isSynced = true
        for timestamp in timestamps {
          var line = LyricsLine()
          line.start = timestamp
          line.value = value
          line.translation = translation
          lines.append(line)
        }
      }
    }

    var lyrics = StructuredLyrics()
    lyrics.lang = "und"
    lyrics.synced = isSynced
    lyrics.offset = offsetMs
    lyrics.line = isSynced ? lines.sorted { ($0.start ?? 0) < ($1.start ?? 0) } : lines
    var list = LyricsList()
    list.lyrics = [lyrics]
    return list
  }
}

// MARK: - QRCFileParser

/// QQ Music word-synced lyrics: `[lineStart,lineDuration]word(wordStart,wordDuration)word(...)`.
/// Files may be plain QRC text, a `QrcInfos` XML wrapper, or the hex ciphertext
/// served by the lyric download API.
enum QRCFileParser {
  private static let headerPattern = try? NSRegularExpression(
    pattern: "^\\[(\\d{1,9}),(\\d{1,9})\\]",
    options: []
  )
  private static let cuePattern = try? NSRegularExpression(
    pattern: "\\((\\d{1,9}),(\\d{1,9})\\)",
    options: []
  )

  static func isQRC(_ content: String) -> Bool {
    if content.contains("LyricContent=\"") || content.contains("<QrcInfos") {
      return true
    }
    if isHexCipher(content) {
      return true
    }
    return content.components(separatedBy: .newlines).contains { rawLine in
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      guard !line.isEmpty, let headerPattern else { return false }
      let fullRange = NSRange(line.startIndex..., in: line)
      guard headerPattern.firstMatch(in: line, range: fullRange) != nil else { return false }
      return cuePattern?.firstMatch(in: line, range: fullRange) != nil
    }
  }

  static func parse(_ content: String) -> LyricsList {
    let text = normalized(content)
    var lines = [LyricsLine]()
    for rawLine in text.components(separatedBy: .newlines) {
      guard let line = parseLine(rawLine) else { continue }
      lines.append(line)
    }

    var lyrics = StructuredLyrics()
    lyrics.lang = "und"
    lyrics.synced = !lines.isEmpty
    lyrics.line = lines.sorted { ($0.start ?? 0) < ($1.start ?? 0) }
    var list = LyricsList()
    list.lyrics = [lyrics]
    return list
  }

  private static func isHexCipher(_ content: String) -> Bool {
    let compact = content.filter { !$0.isWhitespace }
    guard compact.count >= 32, compact.count % 2 == 0 else { return false }
    return compact.allSatisfy { $0.isASCII && $0.isHexDigit }
  }

  private static func normalized(_ content: String) -> String {
    var text = content
    if isHexCipher(text) {
      let compact = text.filter { !$0.isWhitespace }
      if let decrypted = decryptQQMusicQrc(compact) {
        text = decrypted
      }
    }
    if let marker = text.range(of: "LyricContent=\""),
       let end = text[marker.upperBound...].lastIndex(of: "\"") {
      text = String(text[marker.upperBound ..< end])
    }
    return unescaped(text)
  }

  private static func unescaped(_ text: String) -> String {
    var text = text
    if let pattern = try? NSRegularExpression(pattern: "&#(\\d{1,7});", options: []) {
      let matches = pattern.matches(
        in: text,
        range: NSRange(text.startIndex..., in: text)
      )
      for match in matches.reversed() {
        guard let range = Range(match.range, in: text),
              let valueRange = Range(match.range(at: 1), in: text),
              let raw = UInt32(text[valueRange]),
              let scalar = Unicode.Scalar(raw)
        else { continue }
        text.replaceSubrange(range, with: String(Character(scalar)))
      }
    }
    return text
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&apos;", with: "'")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
  }

  private static func parseLine(_ rawLine: String) -> LyricsLine? {
    let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty, !trimmed.hasPrefix("{"), let headerPattern else { return nil }

    var timedPart = trimmed
    var translation: String?
    if let tabIndex = trimmed.firstIndex(of: "\t") {
      timedPart = String(trimmed[..<tabIndex]).trimmingCharacters(in: .whitespaces)
      let translated = String(trimmed[trimmed.index(after: tabIndex)...])
        .trimmingCharacters(in: .whitespacesAndNewlines)
      translation = translated.isEmpty ? nil : translated
    }

    let text = timedPart as NSString
    let fullRange = NSRange(location: 0, length: text.length)
    guard let header = headerPattern.firstMatch(in: timedPart, range: fullRange),
          let start = Int(text.substring(with: header.range(at: 1)))
    else { return nil }

    // QRC places each word before its cue, so the text runs from the previous
    // cue (or the line header) up to the start of its own cue.
    let bodyStart = header.range.location + header.range.length
    let bodyRange = NSRange(location: bodyStart, length: text.length - bodyStart)
    let cues = cuePattern?.matches(in: timedPart, range: bodyRange) ?? []
    guard !cues.isEmpty else { return nil }

    var words = [LyricWord]()
    var cursor = bodyStart
    for cue in cues {
      guard cue.range.location >= cursor else { continue }
      let wordStart = Int(text.substring(with: cue.range(at: 1))) ?? 0
      let duration = Int(text.substring(with: cue.range(at: 2))) ?? 0
      let value = text.substring(
        with: NSRange(location: cursor, length: cue.range.location - cursor)
      )
      words.append(LyricWord(start: wordStart, duration: duration, value: value))
      cursor = cue.range.location + cue.range.length
    }
    if cursor < text.length, let last = words.last {
      words[words.count - 1] = LyricWord(
        start: last.start,
        duration: last.duration,
        value: last.value + text.substring(from: cursor)
      )
    }

    let spacedWords = LyricsWordSpacing.insertPauseSpaces(into: words)
    let value = spacedWords.map(\.value).joined()
    guard !value.trimmingCharacters(in: .whitespaces).isEmpty,
          !LyricsCreditFilter.isCreditLine(value)
    else { return nil }

    var line = LyricsLine()
    line.start = start
    line.value = value
    line.translation = translation
    line.words = spacedWords
    return line
  }
}

// MARK: - KRCFileParser

/// Kugou word-synced lyrics: `[lineStart,lineDuration]<wordStart,wordDuration,0>word...`.
/// Sidecar `.krc` files are `krc1`-prefixed, XOR-obfuscated, zlib-compressed data.
enum KRCFileParser {
  private static let linePattern = try? NSRegularExpression(
    pattern: "^\\[(\\d{1,9}),(\\d{1,9})\\]",
    options: []
  )
  private static let wordTagPattern = try? NSRegularExpression(
    pattern: "<(\\d{1,9}),(\\d{1,9}),(\\d{1,3})>",
    options: []
  )
  private static let key: [UInt8] = [
    0x40, 0x47, 0x61, 0x77, 0x5e, 0x32, 0x74, 0x47,
    0x51, 0x36, 0x31, 0x2d, 0xce, 0xd2, 0x6e, 0x69,
  ]

  static func isKRC(_ content: String) -> Bool {
    content.components(separatedBy: .newlines).contains { rawLine in
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      guard !line.isEmpty, let linePattern else { return false }
      let fullRange = NSRange(line.startIndex..., in: line)
      guard linePattern.firstMatch(in: line, range: fullRange) != nil else { return false }
      return wordTagPattern?.firstMatch(in: line, range: fullRange) != nil
    }
  }

  static func decrypt(_ data: Data) -> String? {
    guard data.starts(with: Data("krc1".utf8)), data.count > 6 else { return nil }
    var bytes = [UInt8](data.dropFirst(4))
    for index in bytes.indices {
      bytes[index] ^= key[index & 15]
    }
    let payload = Data(bytes.dropFirst(2))
    guard let inflated = try? (payload as NSData).decompressed(using: .zlib) else {
      return nil
    }
    return String(data: inflated as Data, encoding: .utf8)
  }

  static func parse(_ content: String) -> LyricsList {
    var lines = [LyricsLine]()
    for rawLine in content.components(separatedBy: .newlines) {
      guard let line = parseLine(rawLine) else { continue }
      lines.append(line)
    }

    var lyrics = StructuredLyrics()
    lyrics.lang = "und"
    lyrics.synced = !lines.isEmpty
    lyrics.line = lines.sorted { ($0.start ?? 0) < ($1.start ?? 0) }
    var list = LyricsList()
    list.lyrics = [lyrics]
    return list
  }

  private static func parseLine(_ rawLine: String) -> LyricsLine? {
    let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty, !trimmed.hasPrefix("{"), let linePattern else { return nil }

    var timedPart = trimmed
    var translation: String?
    if let tabIndex = trimmed.firstIndex(of: "\t") {
      timedPart = String(trimmed[..<tabIndex]).trimmingCharacters(in: .whitespaces)
      let translated = String(trimmed[trimmed.index(after: tabIndex)...])
        .trimmingCharacters(in: .whitespacesAndNewlines)
      translation = translated.isEmpty ? nil : translated
    }

    let text = timedPart as NSString
    let fullRange = NSRange(location: 0, length: text.length)
    guard let header = linePattern.firstMatch(in: timedPart, range: fullRange),
          let start = Int(text.substring(with: header.range(at: 1)))
    else { return nil }

    let bodyStart = header.range.location + header.range.length
    let bodyRange = NSRange(location: bodyStart, length: text.length - bodyStart)
    let tags = wordTagPattern?.matches(in: timedPart, range: bodyRange) ?? []
    guard !tags.isEmpty else { return nil }

    var words = [LyricWord]()
    for (index, tag) in tags.enumerated() {
      let wordStart = Int(text.substring(with: tag.range(at: 1))) ?? 0
      let duration = Int(text.substring(with: tag.range(at: 2))) ?? 0
      let wordTextStart = tag.range.location + tag.range.length
      let wordTextEnd = index + 1 < tags.count ? tags[index + 1].range.location : text.length
      guard wordTextEnd >= wordTextStart else { continue }
      let value = text.substring(
        with: NSRange(location: wordTextStart, length: wordTextEnd - wordTextStart)
      )
      words.append(LyricWord(start: wordStart, duration: duration, value: value))
    }

    let spacedWords = LyricsWordSpacing.insertPauseSpaces(into: words)
    let value = spacedWords.map(\.value).joined()
    guard !value.trimmingCharacters(in: .whitespaces).isEmpty,
          !LyricsCreditFilter.isCreditLine(value)
    else { return nil }

    var line = LyricsLine()
    line.start = start
    line.value = value
    line.translation = translation
    line.words = spacedWords
    return line
  }
}
