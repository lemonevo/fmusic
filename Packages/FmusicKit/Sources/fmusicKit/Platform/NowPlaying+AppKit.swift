//
//  NowPlaying+AppKit.swift
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

#if canImport(AppKit)
import AppKit
import Darwin
import MediaPlayer

/// macOS Now Playing center.
///
/// On macOS `MPNowPlayingInfoCenter` is only forwarded to the system while the app is
/// registered as a "now playing application", and third-party Mac players normally do
/// that through the private `MediaRemote` framework (the same framework Apple Music uses).
/// This implementation keeps using the public `MPNowPlayingInfoCenter` for bookkeeping and
/// additionally registers with `MediaRemote` and pushes the same dictionary there.
///
/// Everything is resolved with `dlsym`, so if a future macOS removes the symbols the app
/// silently falls back to the public API instead of crashing.
@MainActor
final class MediaRemoteNowPlayingCenter: NowPlayingCenter {
  private typealias SetBooleanFunction = @convention(c) (UInt8) -> Void
  private typealias SetInfoFunction = @convention(c) (CFDictionary?) -> Void

  private let publicCenter = MediaPlayerNowPlayingCenter()
  private var setNowPlayingInfo: SetInfoFunction?
  private var storedInfo: [String: Any]?
  private var storedState: NowPlayingPlaybackState = .stopped

  init() {
    guard let handle = dlopen(
      "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
      RTLD_LAZY
    ) else { return }

    if let symbol = dlsym(handle, "MRMediaRemoteSetCanBeNowPlayingApplication") {
      let setCanBeNowPlaying = unsafeBitCast(symbol, to: SetBooleanFunction.self)
      // Boolean is UInt8 in the ObjC runtime.
      setCanBeNowPlaying(1)
    }
    if let symbol = dlsym(handle, "MRMediaRemoteSetNowPlayingInfo") {
      setNowPlayingInfo = unsafeBitCast(symbol, to: SetInfoFunction.self)
    }
  }

  // MARK: - NowPlayingCenter

  var nowPlayingInfo: [String: Any]? {
    get { storedInfo }
    set {
      storedInfo = newValue
      publicCenter.nowPlayingInfo = newValue
      pushToMediaRemote()
    }
  }

  var playbackState: NowPlayingPlaybackState {
    get { storedState }
    set {
      storedState = newValue
      publicCenter.playbackState = newValue
      // MediaRemote derives playback state from the playback-rate/elapsed keys.
      pushToMediaRemote()
    }
  }

  private func pushToMediaRemote() {
    guard let setNowPlayingInfo else { return }
    guard let storedInfo else {
      setNowPlayingInfo(nil)
      return
    }
    // MediaRemote protobuf-encodes the dictionary and asserts on unexpected objects
    // (MPMediaItemArtwork for example), so only forward a sanitized, plist-only copy.
    setNowPlayingInfo(Self.mediaRemoteInfo(from: storedInfo) as CFDictionary)
  }

  /// Maps the MediaPlayer keys the shared core produces to the keys MediaRemote expects.
  private static func mediaRemoteInfo(from info: [String: Any]) -> [String: Any] {
    var result: [String: Any] = [:]
    if let title = info[MPMediaItemPropertyTitle] as? String {
      result["kMRMediaRemoteNowPlayingInfoTitle"] = title
    }
    if let artist = info[MPMediaItemPropertyArtist] as? String {
      result["kMRMediaRemoteNowPlayingInfoArtist"] = artist
    }
    if let album = info[MPMediaItemPropertyAlbumTitle] as? String {
      result["kMRMediaRemoteNowPlayingInfoAlbum"] = album
    }
    if let duration = info[MPMediaItemPropertyPlaybackDuration] as? NSNumber {
      result["kMRMediaRemoteNowPlayingInfoDuration"] = duration
    }
    if let elapsed = info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? NSNumber {
      result["kMRMediaRemoteNowPlayingInfoElapsedTime"] = elapsed
    }
    if let rate = info[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber {
      result["kMRMediaRemoteNowPlayingInfoPlaybackRate"] = rate
    }
    if let isStreaming = info[MPNowPlayingInfoPropertyIsLiveStream] as? NSNumber {
      result["kMRMediaRemoteNowPlayingInfoIsStreaming"] = isStreaming
    }
    if let mediaType = info[MPNowPlayingInfoPropertyMediaType] as? NSNumber {
      result["kMRMediaRemoteNowPlayingInfoMediaType"] = mediaType
    }
    if let artworkData = info[NowPlayingInfoKey.artworkData] as? Data {
      result["kMRMediaRemoteNowPlayingInfoArtworkData"] = artworkData as NSData
      result["kMRMediaRemoteNowPlayingInfoArtworkMIMEType"] = "image/png"
    }
    return result
  }
}
#endif
