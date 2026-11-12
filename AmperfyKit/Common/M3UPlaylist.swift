//
//  M3UPlaylist.swift
//  AmperfyKit
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import Foundation

// MARK: - M3UEntry

public struct M3UEntry: Sendable {
  public let path: String
  public let duration: Int
  public let artistTitle: String?

  public init(path: String, duration: Int, artistTitle: String?) {
    self.path = path
    self.duration = duration
    self.artistTitle = artistTitle
  }
}

// MARK: - M3UCodec

public enum M3UCodec {
  public static func parse(_ content: String) -> [M3UEntry] {
    var entries = [M3UEntry]()
    var pendingDuration = 0
    var pendingArtistTitle: String?

    for rawLine in content.components(separatedBy: .newlines) {
      var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !line.isEmpty else { continue }
      if line.hasPrefix("\u{FEFF}") {
        line.removeFirst()
      }
      let upper = line.uppercased()
      if upper.hasPrefix("#EXTM3U") {
        continue
      }
      if upper.hasPrefix("#EXTINF:") {
        let body = String(line.dropFirst("#EXTINF:".count))
        let parts = body.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        pendingDuration = Int(parts.first?.trimmingCharacters(in: .whitespaces) ?? "") ?? 0
        pendingArtistTitle = parts.count > 1
          ? String(parts[1]).trimmingCharacters(in: .whitespaces)
          : nil
        continue
      }
      if line.hasPrefix("#") {
        continue
      }
      entries.append(M3UEntry(
        path: line,
        duration: pendingDuration,
        artistTitle: pendingArtistTitle
      ))
      pendingDuration = 0
      pendingArtistTitle = nil
    }
    return entries
  }

  public static func export(playables: [AbstractPlayable]) -> String {
    var lines = ["#EXTM3U"]
    for playable in playables {
      guard let url = playable.url, !url.isEmpty else { continue }
      let artist = playable.asSong?.artist?.name ?? ""
      let title = playable.title
      let display = artist.isEmpty ? title : "\(artist) - \(title)"
      lines.append("#EXTINF:\(playable.duration),\(display)")
      lines.append(url)
    }
    return lines.joined(separator: "\n") + "\n"
  }
}

// MARK: - M3UImportMatcher

public enum M3UImportMatcher {
  public static func match(
    entries: [M3UEntry],
    songs: [Song]
  )
    -> (matches: [Song], unmatchedCount: Int) {
    let songPaths = songs.map { song in
      (song: song, path: normalize(song.url ?? ""), file: fileName(song.url ?? ""))
    }

    var byPath = [String: Song]()
    var byFile = [String: [Song]]()
    var byArtistTitle = [String: [Song]]()
    var byTitle = [String: [Song]]()
    for entry in songPaths {
      guard !entry.path.isEmpty else { continue }
      if byPath[entry.path] == nil {
        byPath[entry.path] = entry.song
      }
      byFile[entry.file, default: []].append(entry.song)
      let artistTitle = "\(entry.song.artist?.name ?? "") - \(entry.song.title)"
      byArtistTitle[normalizeLabel(artistTitle), default: []].append(entry.song)
      byTitle[normalizeLabel(entry.song.title), default: []].append(entry.song)
    }

    var matches = [Song]()
    var unmatchedCount = 0
    for entry in entries {
      let path = normalize(entry.path)
      if let song = byPath[path] {
        matches.append(song)
        continue
      }

      let suffixMatches = songPaths
        .filter { !$0.path.isEmpty && ($0.path.hasSuffix("/\(path)") || path.hasSuffix("/\($0.path)")) }
        .map(\.song)
      if let song = pick(suffixMatches, duration: entry.duration) {
        matches.append(song)
        continue
      }

      if let song = pick(byFile[fileName(path)] ?? [], duration: entry.duration) {
        matches.append(song)
        continue
      }

      if let artistTitle = entry.artistTitle {
        if let song = pick(byArtistTitle[normalizeLabel(artistTitle)] ?? [], duration: entry
          .duration) {
          matches.append(song)
          continue
        }
        let titlePart = artistTitle
          .components(separatedBy: " - ")
          .dropFirst()
          .joined(separator: " - ")
        let candidateTitle = titlePart.isEmpty ? artistTitle : titlePart
        if let song = pick(byTitle[normalizeLabel(candidateTitle)] ?? [], duration: entry.duration) {
          matches.append(song)
          continue
        }
      }

      unmatchedCount += 1
    }
    return (matches, unmatchedCount)
  }

  private static func pick(_ candidates: [Song], duration: Int) -> Song? {
    if candidates.count == 1 {
      return candidates.first
    }
    guard duration > 0 else { return nil }
    return candidates.first { abs($0.duration - duration) <= 2 }
  }

  private static func normalize(_ raw: String) -> String {
    var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    value = value.replacingOccurrences(of: "\\", with: "/")
    value = value.removingPercentEncoding ?? value
    if value.lowercased().hasPrefix("file://") {
      value.removeFirst("file://".count)
    }
    while value.hasPrefix("./") {
      value.removeFirst(2)
    }
    while value.hasPrefix("/") {
      value.removeFirst(1)
    }
    return value
  }

  private static func fileName(_ path: String) -> String {
    (normalize(path) as NSString).lastPathComponent.lowercased()
  }

  private static func normalizeLabel(_ value: String) -> String {
    value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
  }
}
