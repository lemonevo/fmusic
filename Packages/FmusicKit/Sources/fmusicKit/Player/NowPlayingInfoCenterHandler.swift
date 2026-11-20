//
//  NowPlayingInfoCenterHandler.swift
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
import MediaPlayer

// MARK: - NowPlayingInfoCenterHandler

@MainActor
public class NowPlayingInfoCenterHandler {
  private let musicPlayer: AudioPlayer
  private let backendAudioPlayer: BackendAudioPlayer
  private let storage: PersistentStorage
  private var nowPlayingCenter: NowPlayingCenter
  private let getArtworkDownloaderCB: GetArtworkDownloadManagerCallback
  private var accountNotificationHandler: AccountNotificationHandler?
  /// Last position pushed to the system; the full metadata/artwork push is expensive.
  private var lastPushedElapsedTime: Double = .nan

  init(
    musicPlayer: AudioPlayer,
    backendAudioPlayer: BackendAudioPlayer,
    nowPlayingCenter: NowPlayingCenter,
    storage: PersistentStorage,
    notificationHandler: EventNotificationHandler,
    getArtworkDownloaderCB: @escaping GetArtworkDownloadManagerCallback,
    getPlayableDownloaderCB: @escaping GetPlayableDownloadManagerCallback
  ) {
    self.musicPlayer = musicPlayer
    self.backendAudioPlayer = backendAudioPlayer
    self.nowPlayingCenter = nowPlayingCenter
    self.storage = storage
    self.getArtworkDownloaderCB = getArtworkDownloaderCB

    nowPlayingCenter.playbackState = .stopped

    self.accountNotificationHandler = AccountNotificationHandler(
      storage: storage,
      notificationHandler: notificationHandler
    )
    accountNotificationHandler?.registerCallbackForAllAccounts { [weak self] accountInfo in
      guard let self else { return }
      notificationHandler.register(
        self,
        selector: #selector(downloadFinishedSuccessful(notification:)),
        name: .downloadFinishedSuccess,
        object: getArtworkDownloaderCB(accountInfo)
      )
      notificationHandler.register(
        self,
        selector: #selector(downloadFinishedSuccessful(notification:)),
        name: .downloadFinishedSuccess,
        object: getPlayableDownloaderCB(accountInfo)
      )
    }
  }

  private func updateNowPlayingInfo(playable: AbstractPlayable) {
    let albumTitle = playable.asSong?.album?.name ?? ""
    let nowPlaying = displayNowPlayingInfo(for: playable)

    var artworkImage = PlatformImages.empty
    if let accountInfo = playable.account?.info {
      #if canImport(UIKit)
      artworkImage = LibraryEntityImage.getImageToDisplayImmediately(
        libraryEntity: playable,
        themePreference: storage.settings.accounts.getSetting(accountInfo).read.themePreference,
        artworkDisplayPreference: storage.settings.accounts.getSetting(accountInfo).read
          .artworkDisplayPreference,
        useCache: true
      )
      #endif
      if let artwork = playable.artwork {
        getArtworkDownloaderCB(accountInfo).download(object: artwork)
      }
    }

    let concurrentSafeArtworkImage = artworkImage
    let elapsedTime = backendAudioPlayer.elapsedTime
    nowPlayingCenter.nowPlayingInfo = [
      MPNowPlayingInfoPropertyMediaType: NSNumber(value: MPNowPlayingInfoMediaType.audio.rawValue),
      MPNowPlayingInfoPropertyServiceIdentifier: FmusicKit.name,

      MPMediaItemPropertyIsCloudItem: !playable.isCached,
      MPMediaItemPropertyTitle: nowPlaying.title,
      MPMediaItemPropertyAlbumTitle: albumTitle,
      MPMediaItemPropertyArtist: nowPlaying.artist,

      MPMediaItemPropertyPlaybackDuration: backendAudioPlayer.duration,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsedTime,
      MPNowPlayingInfoPropertyIsLiveStream: playable.isRadio,

      MPNowPlayingInfoPropertyDefaultPlaybackRate: NSNumber(value: 1.0),
      MPNowPlayingInfoPropertyPlaybackRate: NSNumber(
        value: backendAudioPlayer.playbackRate
          .asDouble
      ),

      MPMediaItemPropertyArtwork: MPMediaItemArtwork(
        boundsSize: concurrentSafeArtworkImage.size,
        requestHandler: { @Sendable size -> PlatformImage in
          // this completion handler is not called in main thread!
          return concurrentSafeArtworkImage
        }
      ),
    ]
    lastPushedElapsedTime = elapsedTime
  }

  private func displayNowPlayingInfo(for playable: AbstractPlayable) -> RadioNowPlayingInfo {
    if playable.isRadio,
       let radioInfo = musicPlayer.currentRadioNowPlaying,
       !radioInfo.isEmpty {
      return radioInfo
    }
    return RadioNowPlayingInfo(title: playable.title, artist: playable.creatorName)
  }

  @objc
  private func downloadFinishedSuccessful(notification: Notification) {
    guard let downloadNotification = DownloadNotification.fromNotification(notification),
          let curPlayable = musicPlayer.currentlyPlaying
    else { return }
    if curPlayable.uniqueID == downloadNotification.id {
      Task { @MainActor in
        updateNowPlayingInfo(playable: curPlayable)
      }
    }
    if let artwork = curPlayable.artwork,
       artwork.uniqueID == downloadNotification.id {
      Task { @MainActor in
        updateNowPlayingInfo(playable: curPlayable)
      }
    }
  }
}

// MARK: MusicPlayable

extension NowPlayingInfoCenterHandler: MusicPlayable {
  public func didStartPlayingFromBeginning() {}

  public func didStartPlaying() {
    if let curPlayable = musicPlayer.currentlyPlaying {
      updateNowPlayingInfo(playable: curPlayable)
    }
    nowPlayingCenter.playbackState = .playing
  }

  public func didPause() {
    if let curPlayable = musicPlayer.currentlyPlaying {
      updateNowPlayingInfo(playable: curPlayable)
    }
    nowPlayingCenter.playbackState = .paused
  }

  public func didStopPlaying() {
    nowPlayingCenter.nowPlayingInfo = nil
    nowPlayingCenter.playbackState = .stopped
  }

  public func didElapsedTimeChange() {
    pushElapsedTime(force: false)
  }

  /// Updates only the position/rate keys; the system interpolates the position itself.
  private func pushElapsedTime(force: Bool) {
    guard let curPlayable = musicPlayer.currentlyPlaying else { return }
    guard var info = nowPlayingCenter.nowPlayingInfo else {
      updateNowPlayingInfo(playable: curPlayable)
      return
    }
    // Refreshing the whole metadata and artwork every tick only burns CPU
    // (MediaRemote even re-encodes the artwork image).
    let elapsed = backendAudioPlayer.elapsedTime
    guard elapsed.isFinite, force || abs(elapsed - lastPushedElapsedTime) >= 1.0 else { return }
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
    info[MPNowPlayingInfoPropertyPlaybackRate] = NSNumber(
      value: backendAudioPlayer.playbackRate.asDouble
    )
    nowPlayingCenter.nowPlayingInfo = info
    lastPushedElapsedTime = elapsed
  }

  public func didPlaylistChange() {}

  public func didArtworkChange() {}

  public func didNowPlayingInfoChange() {
    if let curPlayable = musicPlayer.currentlyPlaying {
      updateNowPlayingInfo(playable: curPlayable)
    }
  }

  public func didShuffleChange() {}

  public func didRepeatChange() {}

  public func didPlaybackRateChange() {
    pushElapsedTime(force: true)
  }
}
