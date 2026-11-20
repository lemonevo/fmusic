//
//  MediaSession.swift
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

// MARK: - MediaSessionInterruption

/// A system audio interruption, normalized for the shared core.
public enum MediaSessionInterruption: Sendable {
  /// Another app took the audio session (phone call, notification, …).
  case began
  /// The interruption ended; `shouldResume` is true when the system expects playback
  /// to continue.
  case ended(shouldResume: Bool)
}

// MARK: - MediaSessionHandling

/// Abstraction over the platform audio session.
///
/// iOS/iPadOS/Catalyst implement this with `AVAudioSession`; the native macOS app gets a
/// macOS implementation (CoreAudio/AVAudioEngine based) in the AppKit migration. The
/// shared core only ever talks to this protocol, so it never imports AVAudioSession.
@MainActor
public protocol MediaSessionHandling: AnyObject {
  /// Starts observing system audio interruptions and output-route changes.
  func startObserving(
    onInterruption: @escaping @MainActor (MediaSessionInterruption) -> Void,
    onHeadphonesConnected: @escaping @MainActor () -> Void,
    onHeadphonesDisconnected: @escaping @MainActor () -> Void
  )

  /// Stops observing system notifications.
  func stopObserving()

  /// Prepares the platform audio session for background music playback.
  func configureBackgroundPlayback(onError: @escaping @MainActor (Error) -> Void)
}

// MARK: - PlatformMediaSession

/// Creates the platform specific media session implementation.
public enum PlatformMediaSession {
  @MainActor
  public static func make() -> MediaSessionHandling {
    #if canImport(UIKit)
    return UIKitMediaSession()
    #else
    return NativeMediaSession()
    #endif
  }
}
