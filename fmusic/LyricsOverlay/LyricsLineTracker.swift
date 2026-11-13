//
//  LyricsLineTracker.swift
//  fmusic
//
//  Shared current-line tracking for the desktop lyrics window and the menu bar item.
//

import fmusicKit
import CoreGraphics
import Foundation

// MARK: - LyricsSnapshot

struct LyricsSnapshot {
  let lineIndex: Int
  let currentText: String
  let nextText: String?
  let syllables: [LyricsSyllableTiming]
  let syllableProgress: [CGFloat]
  let isSynced: Bool

  var isBlankLine: Bool {
    currentText.trimmingCharacters(in: .whitespaces).isEmpty
  }
}

// MARK: - LyricsLineTracker

@MainActor
final class LyricsLineTracker {
  // Mirrors the player's lyrics view so the overlay changes lines at the same moment.
  private static let leadTime: TimeInterval = 0.25

  private(set) var lyrics: StructuredLyrics?
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
        lineIndex: 0,
        currentText: lyrics.line.first?.value ?? "",
        nextText: nil,
        syllables: [],
        syllableProgress: [],
        isSynced: false
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
      lineIndex: lineIndex,
      currentText: lyrics.line[lineIndex].value,
      nextText: nextText,
      syllables: syllables,
      syllableProgress: progress,
      isSynced: true
    )
  }
}
