//
//  LyricsLineTracker.swift
//  fmusic-macOS
//
//  Shared current-line tracking for the desktop lyrics window and the menu bar item.
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

import CoreGraphics
import fmusicKit
import Foundation

// MARK: - LyricsSnapshot

struct LyricsSnapshot {
  let currentText: String
  let currentTranslation: String?
  let nextText: String?
  let syllables: [LyricsSyllableTiming]
  let syllableProgress: [CGFloat]
}

// MARK: - LyricsLineTracker

@MainActor
final class LyricsLineTracker {
  // Mirrors the player's lyrics view so the overlay changes lines at the same moment.
  private static let leadTime: TimeInterval = 0.25

  private var lyrics: StructuredLyrics?
  private var syllableCache = [[LyricsSyllableTiming]]()

  var hasLyrics: Bool {
    !(lyrics?.line.isEmpty ?? true)
  }

  func setLyrics(_ lyrics: StructuredLyrics?) {
    self.lyrics = lyrics
    guard let lyrics else {
      syllableCache = []
      return
    }
    let durations = LyricsTimingMap.estimatedDurations(for: lyrics.line)
    syllableCache = lyrics.line.indices.map { index in
      LyricsTimingMap.syllables(
        for: lyrics.line[index],
        estimatedDuration: durations.object(at: index) ?? 0
      )
    }
  }

  func snapshot(at seconds: TimeInterval, userOffsetMs: Int) -> LyricsSnapshot? {
    guard let lyrics, !lyrics.line.isEmpty else { return nil }

    guard lyrics.synced else {
      return LyricsSnapshot(
        currentText: lyrics.line.first?.value ?? "",
        currentTranslation: lyrics.line.first?.translation,
        nextText: nil,
        syllables: [],
        syllableProgress: []
      )
    }

    let offsetSeconds = (Double(lyrics.offset) + Double(userOffsetMs)) / 1_000
    let searchTime = max(0, seconds + offsetSeconds + Self.leadTime)
    var lineIndex = 0
    for (index, line) in lyrics.line.enumerated() {
      guard let start = line.start else { continue }
      if Double(start) / 1_000 <= searchTime {
        lineIndex = index
      } else {
        break
      }
    }

    let rawTime = seconds + offsetSeconds
    let syllables = syllableCache.object(at: lineIndex) ?? []
    let progress: [CGFloat]
    if let start = lyrics.line[lineIndex].start, rawTime >= Double(start) / 1_000 {
      progress = syllables.map { $0.progress(at: rawTime) }
    } else {
      progress = Array(repeating: 0, count: syllables.count)
    }

    let nextText = lyrics.line[(lineIndex + 1)...]
      .first { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }?
      .value

    return LyricsSnapshot(
      currentText: lyrics.line[lineIndex].value,
      currentTranslation: lyrics.line[lineIndex].translation,
      nextText: nextText,
      syllables: syllables,
      syllableProgress: progress
    )
  }
}
