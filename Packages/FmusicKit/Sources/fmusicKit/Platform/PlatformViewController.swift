//
//  PlatformViewController.swift
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
  /// The platform view controller type: `UIViewController` on iOS/iPadOS/Mac Catalyst,
  /// `NSViewController` on macOS. Used where the shared core only needs to *hand over*
  /// a view controller to the app (for example the event log popups).
  public typealias PlatformViewController = UIViewController
#elseif canImport(AppKit)
  import AppKit
  /// The platform view controller type: `UIViewController` on iOS/iPadOS/Mac Catalyst,
  /// `NSViewController` on macOS. Used where the shared core only needs to *hand over*
  /// a view controller to the app (for example the event log popups).
  public typealias PlatformViewController = NSViewController
#endif
