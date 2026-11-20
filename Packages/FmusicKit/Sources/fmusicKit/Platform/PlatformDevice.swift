//
//  PlatformDevice.swift
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

#if canImport(UIKit)
import UIKit
#endif

// MARK: - PlatformIdiom

/// Platform-independent replacement for `UIDevice.current.userInterfaceIdiom`.
public enum PlatformIdiom: Sendable {
  case phone
  case pad
  case mac
  case other

  public static var current: PlatformIdiom {
    #if canImport(UIKit)
    #if targetEnvironment(macCatalyst)
    return .mac
    #else
    switch UIDevice.current.userInterfaceIdiom {
    case .pad: return .pad
    case .phone: return .phone
    case .mac: return .mac
    default: return .other
    }
    #endif
    #elseif canImport(AppKit)
    return .mac
    #else
    return .other
    #endif
  }

  /// The default number of columns for the album grid on this device class.
  public static var defaultAlbumGridSize: Int {
    current == .pad ? 4 : 3
  }
}

// MARK: - PlatformDeviceInfo

/// Platform-independent device description used by the exported log.
public struct PlatformDeviceInfo: Sendable {
  public var model: String
  public var systemVersion: String

  public init(model: String, systemVersion: String) {
    self.model = model
    self.systemVersion = systemVersion
  }

  public static var current: PlatformDeviceInfo {
    #if canImport(UIKit)
    let device = UIDevice.current
    return PlatformDeviceInfo(model: device.model, systemVersion: device.systemVersion)
    #elseif canImport(AppKit)
    let version = ProcessInfo.processInfo.operatingSystemVersion
    return PlatformDeviceInfo(
      model: "Mac",
      systemVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    )
    #else
    return PlatformDeviceInfo(model: "Unknown", systemVersion: "Unknown")
    #endif
  }
}

// MARK: - PlatformDiskCapacity

/// Disk capacity of the volume the app lives on, used by the storage settings footer.
public enum PlatformDiskCapacity {
  public static var totalInBytes: Int64? {
    let fileURL = URL(fileURLWithPath: "/")
    guard let values = try? fileURL.resourceValues(forKeys: [.volumeTotalCapacityKey]),
          let capacity = values.volumeTotalCapacity else { return nil }
    return Int64(capacity)
  }

  public static var availableInBytes: Int64? {
    let fileURL = URL(fileURLWithPath: "/")
    guard let values = try? fileURL.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
          let capacity = values.volumeAvailableCapacity else { return nil }
    return Int64(capacity)
  }
}

// MARK: - BackgroundFetchResult

/// Platform-independent replacement for `UIBackgroundFetchResult`.
public enum BackgroundFetchResult: Int, Sendable {
  case newData = 0
  case noData = 1
  case failed = 2
}
