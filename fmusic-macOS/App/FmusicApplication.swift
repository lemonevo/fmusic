//
//  FmusicApplication.swift
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

/// Application subclass that implements the app-wide shortcuts which cannot be expressed as
/// menu key equivalents (space would break text editing).
final class FmusicApplication: NSApplication {
  override func sendEvent(_ event: NSEvent) {
    if shouldHandleAsPlayPause(event) {
      (delegate as? AppDelegate)?.togglePlayPause(nil)
      return
    }
    super.sendEvent(event)
  }

  private func shouldHandleAsPlayPause(_ event: NSEvent) -> Bool {
    guard event.type == .keyDown else { return false }
    guard event.charactersIgnoringModifiers == " " else { return false }
    guard event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
    else { return false }
    // Never steal Space from modal alerts, sheets, text inputs, or focused controls.
    guard modalWindow == nil else { return false }
    guard let keyWindow, keyWindow.attachedSheet == nil, !keyWindow.isSheet else { return false }
    if let responder = keyWindow.firstResponder {
      if responder is NSText || responder is NSControl {
        return false
      }
    }
    return true
  }
}
