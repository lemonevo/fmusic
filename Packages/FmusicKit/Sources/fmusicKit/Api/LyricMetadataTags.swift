//
//  LyricMetadataTags.swift
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

import Foundation

// MARK: - LyricMetadataTags

/// Identity tags commonly carried by sidecar LRC files. They are not part of
/// the timed lyric text, so the lyric parsers intentionally drop them.
struct LyricMetadataTags: Sendable {
  let title: String?
  let artist: String?
  let album: String?

  static func parse(_ text: String) -> LyricMetadataTags {
    var title: String?
    var artist: String?
    var album: String?

    for rawLine in text.components(separatedBy: .newlines) {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      guard line.hasPrefix("["), let closing = line.firstIndex(of: "]") else { continue }
      let body = line[line.index(after: line.startIndex) ..< closing]
      guard let separator = body.firstIndex(of: ":") else { continue }
      let key = body[..<separator]
        .trimmingCharacters(in: .whitespaces)
        .lowercased()
      let value = body[body.index(after: separator)...]
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !value.isEmpty else { continue }
      switch key {
      case "ti":
        if title == nil { title = value }
      case "ar":
        if artist == nil { artist = value }
      case "al":
        if album == nil { album = value }
      default:
        break
      }
    }

    return LyricMetadataTags(title: title, artist: artist, album: album)
  }
}

extension LyricMetadataTags {
  static func firstNonEmpty(_ values: String?...) -> String? {
    values.compactMap { $0 }.first {
      !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }
}
