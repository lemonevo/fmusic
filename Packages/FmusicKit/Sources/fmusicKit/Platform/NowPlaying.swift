//
//  NowPlaying.swift
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

#if canImport(MediaPlayer)
import MediaPlayer
#endif

// MARK: - NowPlayingPlaybackState

/// Platform-neutral playback state published to the system Now Playing widget.
public enum NowPlayingPlaybackState: Int, Sendable {
  case stopped = 0
  case playing = 1
  case paused = 2
}

// MARK: - NowPlayingCenter

/// Abstraction over the system Now Playing information center.
///
/// iOS/iPadOS/Catalyst are backed by `MPNowPlayingInfoCenter`. The native macOS app can
/// swap in a `MediaRemote` based implementation (same dictionary keys) without touching
/// the shared core; that is why the core only sees this protocol.
@MainActor
public protocol NowPlayingCenter: AnyObject {
  var nowPlayingInfo: [String: Any]? { get set }
  var playbackState: NowPlayingPlaybackState { get set }
}

// MARK: - MediaPlayerNowPlayingCenter

/// `MPNowPlayingInfoCenter` backed Now Playing center (iOS/iPadOS/Catalyst and the
/// interim macOS implementation until MediaRemote lands with the pure-AppKit target).
@MainActor
public final class MediaPlayerNowPlayingCenter: NowPlayingCenter {
  #if canImport(MediaPlayer)
  private let center = MPNowPlayingInfoCenter.default()

  public init() {}

  public var nowPlayingInfo: [String: Any]? {
    get { center.nowPlayingInfo }
    set { center.nowPlayingInfo = newValue }
  }

  public var playbackState: NowPlayingPlaybackState {
    get {
      switch center.playbackState {
      case .playing: return .playing
      case .paused: return .paused
      default: return .stopped
      }
    }
    set {
      switch newValue {
      case .stopped: center.playbackState = .stopped
      case .playing: center.playbackState = .playing
      case .paused: center.playbackState = .paused
      }
    }
  }
  #else
  private var storedInfo: [String: Any]?
  private var storedState: NowPlayingPlaybackState = .stopped

  public init() {}

  public var nowPlayingInfo: [String: Any]? {
    get { storedInfo }
    set { storedInfo = newValue }
  }

  public var playbackState: NowPlayingPlaybackState {
    get { storedState }
    set { storedState = newValue }
  }
  #endif
}

// MARK: - PlatformNowPlaying

/// Creates the platform specific Now Playing center.
public enum PlatformNowPlaying {
  @MainActor
  public static func makeCenter() -> NowPlayingCenter {
    MediaPlayerNowPlayingCenter()
  }
}
