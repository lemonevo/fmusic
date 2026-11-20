//
//  MediaSession+AppKit.swift
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

#if !canImport(UIKit)
  import Foundation

  /// macOS implementation of `MediaSessionHandling`.
  ///
  /// Native macOS has no `AVAudioSession`; playback does not need a session category to keep
  /// running in the background. The AppKit app wires native device/route handling here when
  /// the pure-AppKit target lands; the shared core only needs the protocol to exist.
  @MainActor
  final class NativeMediaSession: NSObject, MediaSessionHandling {
    func startObserving(
      onInterruption: @escaping @MainActor (MediaSessionInterruption) -> (),
      onHeadphonesConnected: @escaping @MainActor () -> (),
      onHeadphonesDisconnected: @escaping @MainActor () -> ()
    ) {
      // Native macOS playback is not interrupted by the system audio session category.
    }

    func stopObserving() {}

    func configureBackgroundPlayback(onError: @escaping @MainActor (Error) -> ()) {}
  }
#endif
