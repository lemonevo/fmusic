//
//  SplitVC.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 25.02.24.
//  Copyright (c) 2024 Maximilian Bauer. All rights reserved.
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
import UIKit

import SwiftUI

// MARK: - SplitVC

class SplitVC: UISplitViewController {
  public static let sidebarWidth: CGFloat = 210
  public static let inspectorWidth: CGFloat = 300
  public static let miniPlayerWidth: CGFloat = 700
  public static let miniPlayerHeight: CGFloat = 54

  var miniPlayer: MiniPlayerView?
  var miniPlayerWidthConstraint: NSLayoutConstraint?
  var miniPlayerCenterXConstraint: NSLayoutConstraint?
  var miniPlayerLeadingConstraint: NSLayoutConstraint?
  var miniPlayerTrailingConstraint: NSLayoutConstraint?
  var miniPlayerBottomConstraint: NSLayoutConstraint?
  var miniPlayerHeightConstraint: NSLayoutConstraint?
  var welcomePopupPresenter = WelcomePopupPresenter()
  private let account: Account!

  init(style: UISplitViewController.Style, account: Account) {
    self.account = account
    super.init(style: style)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    setViewController(
      embeddInNavigation(vc: AppStoryboard.Main.segueToSideBar(account: account)),
      for: .primary
    )
    setViewController(defaultSecondaryVC, for: .secondary)
    primaryEdge = .leading
    primaryBackgroundStyle = .sidebar

    if appDelegate.storage.settings.user.isOfflineMode {
      appDelegate.eventLogger.info(
        topic: "Reminder",
        message: L10n.tr("Offline Mode is active.")
      )
    }

    miniPlayer = MiniPlayerView(player: appDelegate.player)
    miniPlayer!.configureForMac()
    guard let miniPlayer else { return }

    displayOrHideInspector()

    view.addSubview(miniPlayer.glassContainer)
    // Apple Music style: fixed 700 x 54 floating capsule, centered at the bottom
    miniPlayer.glassContainer.translatesAutoresizingMaskIntoConstraints = false

    miniPlayer.glassContainer.layer.cornerRadius = Self.miniPlayerHeight / 2
    miniPlayer.glassContainer.clipsToBounds = true

    miniPlayerWidthConstraint = miniPlayer.glassContainer.widthAnchor.constraint(
      equalToConstant: Self.miniPlayerWidth
    )
    miniPlayerWidthConstraint?.priority = UILayoutPriority(999)
    miniPlayerCenterXConstraint = miniPlayer.glassContainer.centerXAnchor.constraint(
      equalTo: view.safeAreaLayoutGuide.centerXAnchor,
      constant: 0
    )
    miniPlayerLeadingConstraint = miniPlayer.glassContainer.leadingAnchor.constraint(
      greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor,
      constant: 24
    )
    miniPlayerTrailingConstraint = miniPlayer.glassContainer.trailingAnchor.constraint(
      lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor,
      constant: -24
    )
    miniPlayerBottomConstraint = view.bottomAnchor.constraint(
      equalTo: miniPlayer.glassContainer.bottomAnchor,
      constant: 10
    )
    miniPlayerHeightConstraint = miniPlayer.glassContainer.heightAnchor
      .constraint(equalToConstant: Self.miniPlayerHeight)

    NSLayoutConstraint.activate([
      miniPlayerWidthConstraint!,
      miniPlayerCenterXConstraint!,
      miniPlayerLeadingConstraint!,
      miniPlayerTrailingConstraint!,
      miniPlayerBottomConstraint!,
      miniPlayerHeightConstraint!,
    ])
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()

    // Apple Music centers the player bar in the content column, not in the whole window.
    let sidebarInset = isSidebarVisible ? primaryColumnWidth : 0
    let inspectorWidth = viewController(for: .inspector)?.view.bounds.width ?? 0
    miniPlayerCenterXConstraint?.constant = (sidebarInset - inspectorWidth) / 2
    miniPlayerLeadingConstraint?.constant = sidebarInset + 24
    miniPlayerTrailingConstraint?.constant = -(inspectorWidth + 24)
  }

  override func viewIsAppearing(_ animated: Bool) {
    super.viewIsAppearing(animated)

    // set min and max sidebar width
    minimumPrimaryColumnWidth = Self.sidebarWidth
    maximumPrimaryColumnWidth = Self.sidebarWidth
    minimumInspectorColumnWidth = Self.sidebarWidth
    maximumInspectorColumnWidth = Self.sidebarWidth
    welcomePopupPresenter.displayInfoPopupsIfNeeded()
    miniPlayer?.refreshPlayer()
  }

  func displayOrHideInspector() {
    if appDelegate.storage.settings.user.isPlayerLyricsDisplayed {
      let lyricsVC = LyricsVC()
      setViewController(lyricsVC, for: .inspector)
      show(.inspector)
    } else if appDelegate.storage.settings.user.isPlayerQueueDisplayed {
      let queueVC = QueueVC()
      setViewController(queueVC, for: .inspector)
      show(.inspector)
    } else {
      hide(.inspector)
      setViewController(nil, for: .inspector)
    }
    miniPlayer?.refreshInspectorButtons()
  }

  var isSidebarVisible: Bool {
    switch displayMode {
    case .allVisible, .automatic, .oneBesideSecondary, .primaryOverlay, .twoBesideSecondary,
         .twoDisplaceSecondary:
      // Sidebar is visible in some capacity
      return true
    case .oneOverSecondary, .secondaryOnly, .twoOverSecondary:
      // Sidebar is occupying main space
      return false
    @unknown default:
      return true
    }
  }

  func embeddInNavigation(vc: UIViewController) -> UINavigationController {
    UINavigationController(rootViewController: vc)
  }

  var defaultSecondaryVC: UINavigationController {
    embeddInNavigation(vc: TabNavigatorItem.home.getController(account: account))
  }

  public func push(vc: UIViewController) {
    let secondaryVC = viewController(for: .secondary) as? UINavigationController
    // Only animate when the navigation stack is already on screen; pushing into a stack that
    // is still being attached (e.g. a just opened main window) has to be immediate.
    let animated = secondaryVC?.viewIfLoaded?.window != nil
    secondaryVC?.pushViewController(vc, animated: animated)
  }

  /// Swaps the secondary column with a fade-through: the old page fades out, then the new page
  /// fades in. Replacing the navigation controller without an animation made switching sidebar
  /// sections snap to the new content; a direct cross-fade looked like a double exposure.
  public func replaceSecondary(vc: UIViewController, animated: Bool = true) {
    let newSecondary = embeddInNavigation(vc: vc)
    guard animated,
          viewIfLoaded?.window != nil,
          !isCollapsed,
          let oldView = viewController(for: .secondary)?.view,
          oldView.superview != nil,
          oldView.bounds.width > 1
    else {
      setViewController(newSecondary, for: .secondary)
      return
    }

    let snapshot = oldView.snapshotView(afterScreenUpdates: false)
    let snapshotFrame = view.convert(oldView.bounds, from: oldView)
    setViewController(newSecondary, for: .secondary)
    newSecondary.view.alpha = 0

    if let snapshot {
      snapshot.frame = snapshotFrame
      snapshot.isUserInteractionEnabled = false
      // Keep the floating mini player above the fading content.
      if let glassContainer = miniPlayer?.glassContainer,
         glassContainer.superview === view {
        view.insertSubview(snapshot, belowSubview: glassContainer)
      } else {
        view.addSubview(snapshot)
      }
    }

    UIView.animate(
      withDuration: 0.1,
      delay: 0,
      options: [.curveEaseIn, .allowUserInteraction, .beginFromCurrentState]
    ) {
      snapshot?.alpha = 0
    } completion: { _ in
      // Fade the new page in from the plain background. Blending two dense grids at the same
      // time looked like a double exposure, so the pages fade through instead of cross-fading.
      UIView.animate(
        withDuration: 0.14,
        delay: 0,
        options: [.curveEaseOut, .allowUserInteraction]
      ) {
        newSecondary.view.alpha = 1
      } completion: { _ in
        snapshot?.removeFromSuperview()
      }
    }
  }
}

// MARK: MainSceneHostingViewController

extension SplitVC: MainSceneHostingViewController {
  public func pushNavLibrary(vc: UIViewController) {
    push(vc: vc)
  }

  public func pushLibraryCategory(vc: UIViewController) {
    replaceSecondary(vc: vc)
  }

  func pushTabCategory(tabCategory: TabNavigatorItem) {
    replaceSecondary(vc: tabCategory.getController(account: account))
  }

  func displaySearch() {
    visualizePopupPlayer(direction: .close, animated: true) {
      let searchVC = AppStoryboard.Main.segueToSearch(account: self.account)
      self.replaceSecondary(vc: searchVC)
      Task {
        try await Task.sleep(nanoseconds: 500_000_000)
        searchVC.activateSearchBar()
      }
    }
  }

  func getSafeAreaExtension() -> CGFloat {
    guard let miniPlayerBottomConstraint,
          let miniPlayerHeightConstraint else { return 0.0 }

    return miniPlayerBottomConstraint.constant + miniPlayerHeightConstraint.constant
  }
}
