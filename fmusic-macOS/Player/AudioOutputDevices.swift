//
//  AudioOutputDevices.swift
//  fmusic-macOS
//
//  CoreAudio helpers for the player bar's output device menu.
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

import CoreAudio
import Foundation

/// Lists the system's audio output devices and switches the default output.
enum AudioOutputDevices {
  struct Device {
    let id: AudioDeviceID
    let name: String
  }

  static func outputDevices() -> [Device] {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var dataSize: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &dataSize
    ) == noErr, dataSize > 0
    else { return [] }

    let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
    var ids = [AudioDeviceID](repeating: 0, count: count)
    guard AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &dataSize,
      &ids
    ) == noErr
    else { return [] }

    return ids.compactMap { id -> Device? in
      guard hasOutputChannels(id) else { return nil }
      return Device(id: id, name: deviceName(id))
    }
  }

  static func defaultOutputDevice() -> AudioDeviceID {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var deviceID = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &size,
      &deviceID
    )
    return status == noErr ? deviceID : 0
  }

  static func setDefaultOutputDevice(_ id: AudioDeviceID) {
    var mutableID = id
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    AudioObjectSetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      UInt32(MemoryLayout<AudioDeviceID>.size),
      &mutableID
    )
  }

  // MARK: - Private

  private static func hasOutputChannels(_ id: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreamConfiguration,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr,
          size > 0
    else { return false }
    let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
    defer { raw.deallocate() }
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else {
      return false
    }
    let list = raw.assumingMemoryBound(to: AudioBufferList.self)
    let buffers = UnsafeMutableAudioBufferListPointer(list)
    return buffers.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
  }

  private static func deviceName(_ id: AudioDeviceID) -> String {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyDeviceNameCFString,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var name: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    let status = withUnsafeMutablePointer(to: &name) { pointer in
      AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
    }
    if status == noErr {
      return name as String
    }
    // Fall back to the localized name used by the system UI.
    var localizedAddress = AudioObjectPropertyAddress(
      mSelector: kAudioObjectPropertyName,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var localized: CFString = "" as CFString
    let localizedStatus = withUnsafeMutablePointer(to: &localized) { pointer in
      AudioObjectGetPropertyData(id, &localizedAddress, 0, nil, &size, pointer)
    }
    return localizedStatus == noErr ? localized as String : "Audio Device"
  }
}
