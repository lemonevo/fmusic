//
//  UIKitUtilities.swift
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
  import Foundation
  import UIKit

  // MARK: - UIView

  extension UIView {
    public var screenshot: UIImage? {
      UIGraphicsBeginImageContextWithOptions(layer.frame.size, false, 0)
      defer {
        UIGraphicsEndImageContext()
      }
      guard let context = UIGraphicsGetCurrentContext() else { return nil }
      layer.render(in: context)
      return UIGraphicsGetImageFromCurrentImageContext()
    }
  }

  // MARK: - UIAlertAction

  extension UIAlertAction {
    public convenience init(
      title: String?,
      image: UIImage,
      style: Style,
      handler: ((UIAlertAction) -> ())? = nil
    ) {
      self.init(title: title, style: style, handler: handler)
      self.image = image
    }

    public var image: UIImage {
      get { value(forKey: "image") as? UIImage ?? UIImage() }
      set(image) { setValue(image, forKey: "image") }
    }
  }

  // MARK: - UIDevice

  extension UIDevice {
    public var totalDiskCapacityInByte: Int64? {
      PlatformDiskCapacity.totalInBytes
    }

    public var availableDiskCapacityInByte: Int64? {
      PlatformDiskCapacity.availableInBytes
    }
  }
#endif
