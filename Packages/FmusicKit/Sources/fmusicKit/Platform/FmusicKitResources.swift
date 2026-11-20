//
//  FmusicKitResources.swift
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

/// Single place that knows where the resources shipped by the FmusicKit package live.
///
/// The asset catalog and the Core Data model are SwiftPM resources now, so they are
/// looked up in `Bundle.module` instead of `Bundle.main`. Host apps can still override
/// nibs (and only nibs) by putting an identically named compiled nib in their bundle.
public enum FmusicKitResources {
  /// Bundle that contains the package resources (asset catalog + Core Data model).
  public static var bundle: Bundle { Bundle.module }

  /// Bundle that contains the compiled nib with the given name.
  ///
  /// Prefers the main app bundle so an app target may override a package nib, then
  /// falls back to the package resource bundle.
  public static func nibBundle(named name: String) -> Bundle {
    for candidate in [Bundle.main, bundle]
      where candidate.url(forResource: name, withExtension: "nib") != nil {
      return candidate
    }
    return bundle
  }
}
