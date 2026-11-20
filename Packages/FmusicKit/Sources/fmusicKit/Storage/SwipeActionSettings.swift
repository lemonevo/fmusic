//
//  SwipeActionSettings.swift
//  fmusicKit
//
//  Created by Maximilian Bauer on 06.02.22.
//  Copyright (c) 2022 Maximilian Bauer. All rights reserved.
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

// MARK: - SwipeActionType

public enum SwipeActionType: Int, CaseIterable, Sendable, Codable {
  case insertUserQueue = 0
  case appendUserQueue = 1
  case insertContextQueue = 2
  case appendContextQueue = 3
  case download = 4
  case removeFromCache = 5
  case addToPlaylist = 6
  case play = 7
  case playShuffled = 8
  case insertPodcastQueue = 9
  case appendPodcastQueue = 10
  case favorite = 11

  /// Podcast queue actions stay in the enum so existing settings still decode,
  /// but they are not offered anywhere in this music-only fork.
  public var isSupported: Bool {
    switch self {
    case .appendPodcastQueue, .insertPodcastQueue:
      return false
    default:
      return true
    }
  }

  public var displayName: String {
    switch self {
    case .insertUserQueue:
      return L10n.tr("Insert User Queue")
    case .appendUserQueue:
      return L10n.tr("Append User Queue")
    case .insertContextQueue:
      return L10n.tr("Insert Context Queue")
    case .appendContextQueue:
      return L10n.tr("Append Context Queue")
    case .download:
      return L10n.tr("Download")
    case .removeFromCache:
      return L10n.tr("Remove from Cache")
    case .addToPlaylist:
      return L10n.tr("Add to Playlist")
    case .play:
      return L10n.tr("Play")
    case .playShuffled:
      return L10n.tr("Play shuffled")
    case .insertPodcastQueue:
      return L10n.tr("Insert Podcast Queue")
    case .appendPodcastQueue:
      return L10n.tr("Append Podcast Queue")
    case .favorite:
      return L10n.tr("Favorite")
    }
  }

  public var settingsName: String {
    switch self {
    case .insertUserQueue:
      return L10n.tr("Insert in User Queue")
    case .appendUserQueue:
      return L10n.tr("Append to User Queue")
    case .insertContextQueue:
      return L10n.tr("Insert in Context Queue")
    case .appendContextQueue:
      return L10n.tr("Append to Context Queue")
    case .download:
      return L10n.tr("Download")
    case .removeFromCache:
      return L10n.tr("Remove from Cache")
    case .addToPlaylist:
      return L10n.tr("Add to Playlist")
    case .play:
      return L10n.tr("Play")
    case .playShuffled:
      return L10n.tr("Play shuffled")
    case .insertPodcastQueue:
      return L10n.tr("Insert in Podcast Queue")
    case .appendPodcastQueue:
      return L10n.tr("Append to Podcast Queue")
    case .favorite:
      return L10n.tr("Mark as Favorite")
    }
  }

  @MainActor
  public var image: PlatformImage {
    switch self {
    case .insertUserQueue:
      return PlatformImage.userQueueInsert.platformTinted(with: .white)
    case .appendUserQueue:
      return PlatformImage.userQueueAppend.platformTinted(with: .white)
    case .insertContextQueue:
      return PlatformImage.contextQueueInsert.platformTinted(with: .white)
    case .appendContextQueue:
      return PlatformImage.contextQueueAppend.platformTinted(with: .white)
    case .download:
      return PlatformImage.download.platformTinted(with: .white)
    case .removeFromCache:
      return PlatformImage.trash.platformTinted(with: .white)
    case .addToPlaylist:
      return PlatformImage.playlist.platformTinted(with: .white)
    case .play:
      return PlatformImage.play.platformTinted(with: .white)
    case .playShuffled:
      return PlatformImage.shuffle.platformTinted(with: .white)
    case .insertPodcastQueue:
      return PlatformImage.podcastQueueInsert.platformTinted(with: .white)
    case .appendPodcastQueue:
      return PlatformImage.podcastQueueAppend.platformTinted(with: .white)
    case .favorite:
      return PlatformImage.heartFill.platformTinted(with: .white)
    }
  }
}

// MARK: - SwipeActionSettings

public struct SwipeActionSettings: Sendable, Codable {
  public var combined: [[SwipeActionType]]

  public var leading: [SwipeActionType] {
    combined[0].filter(\.isSupported)
  }

  public var trailing: [SwipeActionType] {
    combined[1].filter(\.isSupported)
  }

  public var notUsed: [SwipeActionType] {
    combined[2].filter(\.isSupported)
  }

  public init(leading: [SwipeActionType], trailing: [SwipeActionType]) {
    let notUsedSet = Set(SwipeActionType.allCases)
      .filter(\.isSupported)
      .subtracting(Set(leading))
      .subtracting(Set(trailing))
    self.combined = [leading, trailing, Array(notUsedSet)]
  }

  // Explicit Codable conformance to ensure stable schema
  private enum CodingKeys: String, CodingKey {
    case combined
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    // Decode combined as an array of arrays of SwipeActionType
    let decodedCombined = try container.decode([[SwipeActionType]].self, forKey: .combined)
    // Ensure we always have exactly three buckets: leading, trailing, notUsed
    if decodedCombined.count >= 3 {
      self.combined = decodedCombined
    } else if decodedCombined.count == 2 {
      // If older data without notUsed, compute it
      let leading = decodedCombined[0]
      let trailing = decodedCombined[1]
      let notUsedSet = Set(SwipeActionType.allCases).subtracting(Set(leading))
        .subtracting(Set(trailing))
      self.combined = [leading, trailing, Array(notUsedSet)]
    } else {
      // Fallback to defaults if data is malformed
      self = SwipeActionSettings.defaultSettings
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(combined, forKey: .combined)
  }

  public static var defaultSettings: SwipeActionSettings {
    SwipeActionSettings(
      leading: [
        .appendContextQueue,
        .insertContextQueue,

      ], trailing: [
        .appendUserQueue,
        .insertUserQueue,
        .download,
      ]
    )
  }
}

// MARK: - SwipeActionContext

public struct SwipeActionContext {
  public let containable: PlayableContainable
  private let customPlayContext: PlayContext?

  public var playables: [AbstractPlayable] { containable.playables }
  public var playContext: PlayContext {
    customPlayContext ?? PlayContext(containable: containable)
  }

  public init(containable: PlayableContainable, playContext: PlayContext? = nil) {
    self.containable = containable
    self.customPlayContext = playContext
  }
}
