//
//  PlaybackClock.swift
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
import CoreMedia
import fmusicKit

/// One shared 0.5 s playback tick for every visible player surface. The timer only
/// runs while at least one surface is subscribed and the player is playing.
@MainActor
final class PlaybackClock: MusicPlayable {
  static let shared = PlaybackClock()

  private var timer: Timer?
  private var handlers: [UUID: () -> Void] = [:]
  private var isNotifierRegistered = false

  private var player: PlayerFacade { FmusicKit.shared.player }

  @discardableResult
  func subscribe(_ handler: @escaping @MainActor () -> Void) -> UUID {
    ensureNotifier()
    let token = UUID()
    handlers[token] = handler
    startIfNeeded()
    return token
  }

  func unsubscribe(_ token: UUID?) {
    guard let token else { return }
    handlers.removeValue(forKey: token)
    if handlers.isEmpty { stop() }
  }

  private func ensureNotifier() {
    guard !isNotifierRegistered else { return }
    isNotifierRegistered = true
    player.addNotifier(notifier: self)
  }

  private func startIfNeeded() {
    guard timer == nil, !handlers.isEmpty, player.isPlaying else { return }
    let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) {
      [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        for handler in self.handlers.values { handler() }
      }
    }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  private func stop() {
    timer?.invalidate()
    timer = nil
  }

  // MARK: - MusicPlayable

  func didStartPlayingFromBeginning() {}
  func didStartPlaying() { startIfNeeded() }
  func didPause() { stop() }
  func didStopPlaying() { stop() }
  func didElapsedTimeChange() {}
  func didLyricsTimeChange(time: CMTime) {}
  func didPlaylistChange() {}
  func didArtworkChange() {}
  func didNowPlayingInfoChange() {}
  func didShuffleChange() {}
  func didRepeatChange() {}
  func didPlaybackRateChange() {}
}
