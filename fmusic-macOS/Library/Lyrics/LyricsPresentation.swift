//
//  LyricsPresentation.swift
//  fmusic-macOS
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

import AppKit
import fmusicKit

/// Shared lyric timing, current-line resolution and text layout rules. The side
/// pane and the Now Playing column keep their own fonts/metrics, but agree on how
/// offsets, current lines and line wrapping are computed.
@MainActor
enum LyricsPresentation {
  /// Matches the original desktop/current-line lead so line switches feel the same.
  static let leadTime: TimeInterval = 0.25

  static func playbackTime(
    elapsed: TimeInterval,
    lyricsOffsetMs: Int,
    userOffsetMs: Int
  )
    -> TimeInterval {
    elapsed + (Double(lyricsOffsetMs) + Double(userOffsetMs)) / 1_000
  }

  /// Index of the active lyric line. Returns -1 for empty/unsynced content.
  static func currentLineIndex(
    lyrics: StructuredLyrics,
    elapsed: TimeInterval,
    userOffsetMs: Int,
    leadTime: TimeInterval = 0
  )
    -> Int {
    guard lyrics.synced, !lyrics.line.isEmpty else { return -1 }
    let position = max(
      0,
      playbackTime(
        elapsed: elapsed,
        lyricsOffsetMs: lyrics.offset,
        userOffsetMs: userOffsetMs
      ) + leadTime
    )
    var index = 0
    for (lineIndex, line) in lyrics.line.enumerated() {
      guard let start = line.start else { continue }
      if Double(start) / 1_000 <= position {
        index = lineIndex
      } else {
        break
      }
    }
    return index
  }

  static func paragraphStyle(
    lineSpacing: CGFloat,
    alignment: NSTextAlignment = .left
  )
    -> NSParagraphStyle {
    let style = NSMutableParagraphStyle()
    style.lineSpacing = lineSpacing
    style.lineBreakMode = .byWordWrapping
    // Prevents a single CJK glyph (e.g. “末”) from being stranded on its own line.
    style.lineBreakStrategy = .pushOut
    style.alignment = alignment
    return style
  }

  static func contentWidth(containerWidth: CGFloat, horizontalInset: CGFloat) -> CGFloat {
    max(80, containerWidth - horizontalInset * 2)
  }
}
