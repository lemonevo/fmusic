//
//  MacAppIconOption.swift
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

import Foundation
import fmusicKit

/// The icon families offered by the app icon picker.
///
/// Mirrors the Catalyst `AppIconCategory` enum in
/// `fmusic/SwiftUI/Settings/Display/AppIcon/AppIconCategory.swift`.
enum MacAppIconCategory: String, CaseIterable, Sendable {
  case fmusic
  case music

  /// Localized family title (English key, translated at display time like the Catalyst app).
  var title: String {
    switch self {
    case .fmusic: L10n.tr("fmusic")
    case .music: L10n.tr("Music")
    }
  }
}

/// One selectable app icon.
///
/// The macOS counterpart of the Catalyst `AppIconOption` catalogue in
/// `fmusic/SwiftUI/Settings/Display/AppIcon/AppIconOption.swift` (that file is not part of
/// the macOS target). Keep this list, the `fmusic/Assets/*.icon` bundles and the imagesets
/// in `fmusic/Assets/AppIconPreviews.xcassets` in sync when icons are added or renamed.
struct MacAppIconOption: Identifiable, Sendable {
  /// English title key, localized when it is displayed.
  let title: String
  /// Name of the bundled alternate icon; `nil` selects the default app icon.
  let iconName: String?
  /// Name of the preview image in `AppIconPreviews.xcassets`.
  let previewName: String
  let category: MacAppIconCategory

  /// Identifier used for the default (bundled) icon.
  static let defaultID = "Default"

  var id: String { iconName ?? Self.defaultID }

  var localizedTitle: String { L10n.tr(title) }

  /// Same order and identifiers as `AppIconOption.all` in the Catalyst app.
  static let all: [MacAppIconOption] = [
    MacAppIconOption(
      title: "Default",
      iconName: nil,
      previewName: "fmusicAppIconPreview",
      category: .fmusic
    ),
    MacAppIconOption(
      title: "Teal",
      iconName: "fmusicTeal",
      previewName: "fmusicTealPreview",
      category: .fmusic
    ),
    MacAppIconOption(
      title: "Green",
      iconName: "fmusicGreen",
      previewName: "fmusicGreenPreview",
      category: .fmusic
    ),
    MacAppIconOption(
      title: "Yellow",
      iconName: "fmusicYellow",
      previewName: "fmusicYellowPreview",
      category: .fmusic
    ),
    MacAppIconOption(
      title: "Orange",
      iconName: "fmusicOrange",
      previewName: "fmusicOrangePreview",
      category: .fmusic
    ),
    MacAppIconOption(
      title: "Red",
      iconName: "fmusicRed",
      previewName: "fmusicRedPreview",
      category: .fmusic
    ),
    MacAppIconOption(
      title: "Pink",
      iconName: "fmusicPink",
      previewName: "fmusicPinkPreview",
      category: .fmusic
    ),
    MacAppIconOption(
      title: "Purple",
      iconName: "fmusicPurple",
      previewName: "fmusicPurplePreview",
      category: .fmusic
    ),
    MacAppIconOption(
      title: "Music Blue",
      iconName: "fmusicMusicBlue",
      previewName: "fmusicMusicBluePreview",
      category: .music
    ),
    MacAppIconOption(
      title: "Music Teal",
      iconName: "fmusicMusicTeal",
      previewName: "fmusicMusicTealPreview",
      category: .music
    ),
    MacAppIconOption(
      title: "Music Green",
      iconName: "fmusicMusicGreen",
      previewName: "fmusicMusicGreenPreview",
      category: .music
    ),
    MacAppIconOption(
      title: "Music Yellow",
      iconName: "fmusicMusicYellow",
      previewName: "fmusicMusicYellowPreview",
      category: .music
    ),
    MacAppIconOption(
      title: "Music Orange",
      iconName: "fmusicMusicOrange",
      previewName: "fmusicMusicOrangePreview",
      category: .music
    ),
    MacAppIconOption(
      title: "Music Red",
      iconName: "fmusicMusicRed",
      previewName: "fmusicMusicRedPreview",
      category: .music
    ),
    MacAppIconOption(
      title: "Music Pink",
      iconName: "fmusicMusicPink",
      previewName: "fmusicMusicPinkPreview",
      category: .music
    ),
    MacAppIconOption(
      title: "Music Purple",
      iconName: "fmusicMusicPurple",
      previewName: "fmusicMusicPurplePreview",
      category: .music
    ),
    MacAppIconOption(
      title: "Music Single",
      iconName: "fmusicMusicSingle",
      previewName: "fmusicMusicSinglePreview",
      category: .music
    ),
    MacAppIconOption(
      title: "Music Single Gradient",
      iconName: "fmusicMusicSingleGradient",
      previewName: "fmusicMusicSingleGradientPreview",
      category: .music
    ),
  ]
}
