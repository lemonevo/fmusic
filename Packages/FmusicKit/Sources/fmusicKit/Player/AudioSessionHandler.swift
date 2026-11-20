//
//  AudioSessionHandler.swift
//  fmusicKit
//
//  Created by Maximilian Bauer on 23.11.21.
//  Copyright (c) 2021 Maximilian Bauer. All rights reserved.
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

@MainActor
public class AudioSessionHandler {
  var musicPlayer: AudioPlayer?
  var eventLogger: EventLogger?

  private let mediaSession: MediaSessionHandling
  private var isObserving = false

  init(mediaSession: MediaSessionHandling = PlatformMediaSession.make()) {
    self.mediaSession = mediaSession
  }

  /// Routes system audio interruptions (calls, Siri, …) and output-route changes
  /// (headphone connect/disconnect) to the player.
  ///
  /// The actual platform work lives in `MediaSessionHandling`; the shared core never
  /// imports `AVAudioSession`.
  func configureObserverForAudioSessionInterruption() {
    guard !isObserving else { return }
    isObserving = true
    mediaSession.startObserving(
      onInterruption: { [weak self] interruption in
        guard let self else { return }
        switch interruption {
        case .began:
          musicPlayer?.pause()
        case let .ended(shouldResume):
          if shouldResume {
            musicPlayer?.play()
          }
        }
      },
      onHeadphonesConnected: { [weak self] in
        self?.musicPlayer?.play()
      },
      onHeadphonesDisconnected: { [weak self] in
        self?.musicPlayer?.pause()
      }
    )
  }

  /// Prepares the platform audio session so playback continues in the background.
  func configureBackgroundPlayback() {
    mediaSession.configureBackgroundPlayback { [weak self] error in
      self?.eventLogger?.report(topic: "Audio Session", error: error)
    }
  }
}
