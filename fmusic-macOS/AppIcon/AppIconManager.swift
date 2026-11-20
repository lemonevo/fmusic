//
//  AppIconManager.swift
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

/// Applies and persists the app icon chosen in the display settings.
///
/// macOS has no `UIApplication.setAlternateIconName` equivalent, so switching the icon
/// means assigning `NSApp.applicationIconImage`; the Dock and the app switcher pick the new
/// image up immediately. The choice is stored in `UserDefaults` and restored on the next
/// launch by calling `applySavedIcon()` from the app delegate once `NSApp` exists.
///
/// The image is loaded from the `AppIconPreviews.xcassets` catalog that the macOS target
/// bundles, using the preview names listed in `MacAppIconOption`. Missing catalog entries
/// degrade gracefully: the picker falls back to the current icon and applying a broken icon
/// leaves the Dock icon untouched.
@MainActor
enum AppIconManager {
  /// `UserDefaults` key holding the identifier of the selected icon.
  static let userDefaultsKey = "fmusic.mac.appIconID"

  // MARK: - Catalogue

  static var options: [MacAppIconOption] { MacAppIconOption.all }

  static func options(in category: MacAppIconCategory) -> [MacAppIconOption] {
    options.filter { $0.category == category }
  }

  static func option(withID id: String) -> MacAppIconOption? {
    options.first { $0.id == id }
  }

  /// The persisted selection. Unknown or missing identifiers fall back to the default icon.
  static var selectedIconID: String {
    guard let stored = UserDefaults.standard.string(forKey: userDefaultsKey),
          option(withID: stored) != nil
    else { return MacAppIconOption.defaultID }
    return stored
  }

  static var selectedOption: MacAppIconOption {
    option(withID: selectedIconID) ?? options[0]
  }

  // MARK: - Images

  /// Preview image for the picker grid.
  ///
  /// Falls back to the icon the app currently shows when the asset catalog does not contain
  /// the preview (e.g. a build that did not bundle `AppIconPreviews.xcassets`), so the picker
  /// still renders instead of showing empty cells.
  static func previewImage(for option: MacAppIconOption) -> NSImage? {
    if let image = assetImage(named: option.previewName) { return image }
    return NSApp?.applicationIconImage
  }

  // MARK: - Applying

  /// Restores the persisted icon. Call this once during app launch after `NSApp` exists.
  static func applySavedIcon() {
    apply(iconID: selectedIconID)
  }

  /// Applies `iconID` to the Dock icon and persists the choice.
  static func apply(iconID: String) {
    guard let option = option(withID: iconID) else { return }
    rememberBundleIconIfNeeded()

    if option.iconName == nil {
      // Default: restore the icon the app was launched with. It is captured before the
      // first override so switching back does not lose the bundle icon.
      NSApp?.applicationIconImage = bundleIconImage ?? previewImage(for: option)
    } else if let image = assetImage(named: option.previewName) {
      NSApp?.applicationIconImage = image
    } else {
      // The alternate icon asset is missing from this build: keep the current Dock icon
      // instead of ending up without one, but still remember the user's selection.
    }

    UserDefaults.standard.set(option.id, forKey: userDefaultsKey)
  }

  // MARK: - Private

  /// The icon the app bundle launched with, captured before the first override.
  private static var bundleIconImage: NSImage?

  private static func rememberBundleIconIfNeeded() {
    guard bundleIconImage == nil, let app = NSApp else { return }
    bundleIconImage = app.applicationIconImage
  }

  private static func assetImage(named name: String) -> NSImage? {
    NSImage(named: NSImage.Name(name))
  }
}
