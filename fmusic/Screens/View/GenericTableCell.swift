//
//  GenericTableCell.swift
//  fmusic
//
//  Created by Maximilian Bauer on 20.02.22.
//  Copyright (c) 2022 Maximilian Bauer. All rights reserved.
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

import fmusicKit
import UIKit

class GenericTableCell: BasicTableCell {
  @IBOutlet
  weak var titleLabel: UILabel!
  @IBOutlet
  weak var subtitleLabel: UILabel!
  @IBOutlet
  weak var entityImage: EntityImageView!
  @IBOutlet
  weak var infoLabel: UILabel!
  @IBOutlet
  weak var favoriteIconImage: UIImageView!

  @IBOutlet
  weak var infoLabelWidthConstraint: NSLayoutConstraint!

  static var rowHeight: CGFloat { scaledRowHeight(contentHeight: 48.0) }
  static var rowHeightWithoutImage: CGFloat { scaledRowHeight(contentHeight: 28.0) }

  private var container: PlayableContainable?
  private var rootView: UITableViewController?

  /// Subtle pointer highlight, matching the sidebar rows and the playable song cells.
  private lazy var hoverBackgroundView: UIView = {
    let view = UIView()
    view.backgroundColor = UIColor { traits in
      traits.userInterfaceStyle == .dark
        ? UIColor.white.withAlphaComponent(0.07)
        : UIColor.black.withAlphaComponent(0.045)
    }
    view.layer.cornerRadius = 6
    view.layer.cornerCurve = .continuous
    view.alpha = 0
    view.isUserInteractionEnabled = false
    return view
  }()

  override func awakeFromNib() {
    super.awakeFromNib()
    #if targetEnvironment(macCatalyst)
      // Compact macOS list typography, matching the sidebar and settings (13/11 pt).
      titleLabel?.font = .systemFont(ofSize: 13)
      subtitleLabel?.font = .systemFont(ofSize: 11)
      infoLabel?.font = .systemFont(ofSize: 11)
      contentView.insertSubview(hoverBackgroundView, at: 0)
      addGestureRecognizer(
        UIHoverGestureRecognizer(target: self, action: #selector(handlePointerHover(_:)))
      )
    #endif
  }

  @objc
  private func handlePointerHover(_ recognizer: UIHoverGestureRecognizer) {
    let isHovering: Bool
    switch recognizer.state {
    case .began, .changed: isHovering = true
    default: isHovering = false
    }
    UIView.animate(
      withDuration: 0.12,
      delay: 0,
      options: [.beginFromCurrentState, .allowUserInteraction]
    ) {
      self.hoverBackgroundView.alpha = isHovering ? 1 : 0
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    hoverBackgroundView.frame = contentView.bounds.insetBy(dx: 6, dy: 2)
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    hoverBackgroundView.alpha = 0
  }

  func display(container: PlayableContainable, rootView: UITableViewController) {
    self.container = container
    self.rootView = rootView
    selectionStyle = .none
    titleLabel.text = container.name
    subtitleLabel.isHidden = container.subtitle == nil
    subtitleLabel.text = container.subtitle
    entityImage.display(
      theme: appDelegate.storage.settings.accounts.getSetting(container.account?.info).read
        .themePreference,
      container: container
    )
    let infoText = container.info(
      for: container.account?.apiType.asServerApiType,
      details: DetailInfoType(type: .short, settings: appDelegate.storage.settings)
    )
    infoLabel.isHidden = infoText.isEmpty
    infoLabel.text = infoText
    infoLabel.textAlignment = (traitCollection.horizontalSizeClass == .regular) ? .right : .left
    favoriteIconImage.isHidden = !container.isFavorite
    favoriteIconImage.tintColor = .red

    if container is Album {
      infoLabelWidthConstraint.constant = 75
    } else if container is Artist {
      infoLabelWidthConstraint.constant = 230
    } else if container is Genre {
      infoLabelWidthConstraint.constant = 260
    }
    accessoryType = .disclosureIndicator
    backgroundColor = .systemBackground
  }
}
