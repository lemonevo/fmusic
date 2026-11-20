//
//  MediaSession+UIKit.swift
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

#if canImport(UIKit)
  import AVFoundation
  import Foundation
  import os.log

  /// iOS/iPadOS/Catalyst implementation of `MediaSessionHandling`, backed by `AVAudioSession`.
  @MainActor
  final class UIKitMediaSession: NSObject, MediaSessionHandling {
    private var isObserving = false
    private var onInterruption: (@MainActor (MediaSessionInterruption) -> ())?
    private var onHeadphonesConnected: (@MainActor () -> ())?
    private var onHeadphonesDisconnected: (@MainActor () -> ())?

    func startObserving(
      onInterruption: @escaping @MainActor (MediaSessionInterruption) -> (),
      onHeadphonesConnected: @escaping @MainActor () -> (),
      onHeadphonesDisconnected: @escaping @MainActor () -> ()
    ) {
      self.onInterruption = onInterruption
      self.onHeadphonesConnected = onHeadphonesConnected
      self.onHeadphonesDisconnected = onHeadphonesDisconnected
      guard !isObserving else { return }
      isObserving = true
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleInterruption(_:)),
        name: AVAudioSession.interruptionNotification,
        object: nil
      )
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleRouteChange(_:)),
        name: AVAudioSession.routeChangeNotification,
        object: nil
      )
    }

    func stopObserving() {
      guard isObserving else { return }
      isObserving = false
      NotificationCenter.default.removeObserver(self)
      onInterruption = nil
      onHeadphonesConnected = nil
      onHeadphonesDisconnected = nil
    }

    func configureBackgroundPlayback(onError: @escaping @MainActor (Error) -> ()) {
      do {
        try AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playback)
        try AVAudioSession.sharedInstance().setActive(true)
      } catch {
        onError(error)
      }
    }

    // MARK: - Notifications

    @objc
    private func handleInterruption(_ notification: Notification) {
      guard let interruptionTypeRaw = notification
        .userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber,
        let interruptionType = AVAudioSession
        .InterruptionType(rawValue: interruptionTypeRaw.uintValue) else {
        os_log(.error, "Audio Session: Audio interruption type invalid")
        return
      }

      switch interruptionType {
      case .began:
        os_log(.info, "Audio Session: Audio interruption began")
        onInterruption?(.began)
      case .ended:
        var shouldResume = false
        if let interruptionOptionRaw = notification
          .userInfo?[AVAudioSessionInterruptionOptionKey] as? NSNumber {
          let interruptionOption = AVAudioSession
            .InterruptionOptions(rawValue: interruptionOptionRaw.uintValue)
          shouldResume = interruptionOption.contains(.shouldResume)
        }
        os_log(.info, "Audio Session: Audio interruption ended")
        onInterruption?(.ended(shouldResume: shouldResume))
      @unknown default:
        break
      }
    }

    @objc
    private func handleRouteChange(_ notification: Notification) {
      os_log(.info, "Audio Session: route changed")
      guard let userInfo = notification.userInfo,
            let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
        return
      }

      switch reason {
      case .newDeviceAvailable:
        let session = AVAudioSession.sharedInstance()
        for output in session.currentRoute.outputs where
          output.portType == AVAudioSession.Port.headphones ||
          output.portType == AVAudioSession.Port.bluetoothA2DP {
          os_log(.info, "Audio Session: headphones connected")
          onHeadphonesConnected?()
          break
        }
      case .oldDeviceUnavailable:
        if let previousRoute =
          userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription {
          for output in previousRoute.outputs where
            output.portType == AVAudioSession.Port.headphones ||
            output.portType == AVAudioSession.Port.bluetoothA2DP {
            os_log(.info, "Audio Session: headphones disconnected")
            onHeadphonesDisconnected?()
            break
          }
        }
      default:
        break
      }
    }
  }
#endif
