//
//  CommonScreenOperations.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 09.03.19.
//  Copyright (c) 2019 Maximilian Bauer. All rights reserved.
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

import AmperfyKit
import Foundation
import UIKit

extension UIView {
  static let defaultMarginX: CGFloat = 25
  static let defaultMarginY: CGFloat = 11
  static let defaultMarginTopElement = UIEdgeInsets(
    top: 0.0,
    left: UIView.defaultMarginX,
    bottom: 0.0,
    right: UIView.defaultMarginX
  )
  static let defaultMarginMiddleElement = UIEdgeInsets(
    top: UIView.defaultMarginY,
    left: UIView.defaultMarginX,
    bottom: UIView.defaultMarginY,
    right: UIView.defaultMarginX
  )
  static let defaultMarginCellX: CGFloat = 20
  static let defaultMarginCellY: CGFloat = 9
  static let defaultMarginCell = UIEdgeInsets(
    top: UIView.defaultMarginCellY,
    left: UIView.defaultMarginCellX,
    bottom: UIView.defaultMarginCellY,
    right: UIView.defaultMarginCellX
  )
}

// MARK: - CommonScreenOperations

class CommonScreenOperations {
  /// Scales with the user's text size (40pt at the default text size)
  @MainActor
  static var tableSectionHeightLarge: CGFloat { TextScaling.scaledValue(40) }
  static let tableSectionHeightFooter: CGFloat = 8
}

// MARK: - UIViewController


// MARK: - Localized empty states

extension UIContentUnavailableConfiguration {
  /// The system `search()` state is localized from the app bundle, which only ships
  /// Base.lproj and therefore always renders English. Build the same state from L10n.
  static func localizedSearch() -> UIContentUnavailableConfiguration {
    var config = UIContentUnavailableConfiguration.empty()
    config.image = UIImage(systemName: "magnifyingglass")
    config.text = L10n.tr("No Results")
    config.secondaryText = L10n.tr("Check the spelling or try a new search.")
    return config
  }
}
