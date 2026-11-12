//
//  SideBarVC.swift
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

class SideBarVC: KeyCommandCollectionViewController {
  private static let accountFooterHeight: CGFloat = 72

  private let account: Account!
  private var accountMenuButton: UIButton?
  private var accountNameLabel: UILabel?
  private var avatarLabel: UILabel?

  init(collectionViewLayout: UICollectionViewLayout, account: Account) {
    self.account = account
    super.init(collectionViewLayout: collectionViewLayout)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private var offsetData: [LibraryNavigatorItem] = {
    [
      LibraryNavigatorItem(title: L10n.tr("Search"), tab: .search),
      LibraryNavigatorItem(title: L10n.tr("Home"), tab: .home),
      LibraryNavigatorItem(title: L10n.tr("Library"), isInteractable: false),
    ]
  }()

  lazy var layoutConfig = UICollectionLayoutListConfiguration(appearance: .sidebar)
  lazy var libraryItemConfigurator = LibraryNavigatorConfigurator(
    account: account, offsetData: offsetData,
    librarySettings: appDelegate.storage.settings.accounts.getSetting(self.account.info)
      .read
      .libraryDisplaySettings,
    layoutConfig: self.layoutConfig, pressedOnLibraryItemCB: self.pushedOn
  )

  override func viewDidLoad() {
    super.viewDidLoad()

    clearsSelectionOnViewWillAppear = false
    collectionView.tintColor = .secondaryLabel
    libraryItemConfigurator.viewDidLoad(
      navigationItem: navigationItem,
      collectionView: collectionView
    )
    configureAccountFooter()
    if #available(macCatalyst 27.0, *) {
      // soft top border -> works fine on macOS 27, no sidebar item is covered
      collectionView.topEdgeEffect.style = .soft
    } else {
      // hard top border -> other glass effect is to big and covers top sidebar elements
      collectionView.topEdgeEffect.style = .hard
    }
  }

  override func viewIsAppearing(_ animated: Bool) {
    super.viewIsAppearing(animated)
    becomeFirstResponder()
    libraryItemConfigurator.viewIsAppearing(
      navigationItem: navigationItem,
      collectionView: collectionView
    )
    refreshAccountFooter()
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    resignFirstResponder()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let topInsetCorrection = 55.0 - collectionView.safeAreaInsets.top
    collectionView.contentInset = .init(
      top: topInsetCorrection,
      left: 0,
      bottom: Self.accountFooterHeight,
      right: 0
    )
    collectionView.verticalScrollIndicatorInsets = .init(
      top: 0,
      left: 0,
      bottom: Self.accountFooterHeight - 8,
      right: 0
    )
  }

  private func configureAccountFooter() {
    let footer = UIView()
    footer.translatesAutoresizingMaskIntoConstraints = false

    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.showsMenuAsPrimaryAction = true
    button.accessibilityLabel = L10n.tr("Account")

    let avatar = UILabel()
    avatar.translatesAutoresizingMaskIntoConstraints = false
    avatar.font = .systemFont(ofSize: 15, weight: .semibold)
    avatar.textAlignment = .center
    avatar.textColor = .white
    avatar.backgroundColor = UIColor(red: 0.56, green: 0.65, blue: 0.91, alpha: 1.0)
    avatar.layer.cornerRadius = 20
    avatar.clipsToBounds = true

    let name = UILabel()
    name.translatesAutoresizingMaskIntoConstraints = false
    name.font = .systemFont(ofSize: 13, weight: .semibold)
    name.textColor = .label

    let stack = UIStackView(arrangedSubviews: [avatar, name])
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .horizontal
    stack.alignment = .center
    stack.spacing = 12
    stack.isUserInteractionEnabled = false

    guard let containerView = navigationController?.view ?? view else { return }
    containerView.addSubview(footer)
    footer.addSubview(button)
    button.addSubview(stack)

    NSLayoutConstraint.activate([
      footer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
      footer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
      footer.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
      footer.heightAnchor.constraint(equalToConstant: Self.accountFooterHeight),

      button.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 16),
      button.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -16),
      button.topAnchor.constraint(equalTo: footer.topAnchor),
      button.bottomAnchor.constraint(equalTo: footer.bottomAnchor, constant: -10),

      stack.leadingAnchor.constraint(equalTo: button.leadingAnchor),
      stack.centerYAnchor.constraint(equalTo: button.centerYAnchor),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: button.trailingAnchor),

      avatar.widthAnchor.constraint(equalToConstant: 40),
      avatar.heightAnchor.constraint(equalToConstant: 40),
    ])

    accountMenuButton = button
    accountNameLabel = name
    avatarLabel = avatar
    refreshAccountFooter()
  }

  private func refreshAccountFooter() {
    accountMenuButton?.menu = createUserButtonMenu()
    guard let accountInfo = appDelegate.storage.settings.accounts.active else { return }
    let credentials = appDelegate.storage.settings.accounts.getSetting(accountInfo).read
      .loginCredentials
    let username = credentials?.username ?? ""
    let displayName = username.isEmpty ? L10n.tr("Account") : username
    accountNameLabel?.text = displayName
    let initials = displayName.split(separator: " ").prefix(2)
      .compactMap { $0.first }
      .map(String.init)
      .joined()
      .uppercased()
    avatarLabel?.text = initials.isEmpty ? String(displayName.prefix(1)).uppercased() : initials
  }

  public func pushedOn(selectedItem: LibraryNavigatorItem) {
    // selection changed -> the keyboard focus is no longer relevant
    collectionViewKeyCommandsController.removeFocus()
    guard let splitVC = splitViewController as? SplitVC,
          !splitVC.isCollapsed
    else { return }

    if splitVC.displayMode == .oneOverSecondary {
      splitVC.hide(.primary)
    }

    if let libraryItem = selectedItem.library {
      AppDelegate.mainWindowHostVC?
        .pushLibraryCategory(vc: libraryItem.controller(
          account: account,
          settings: appDelegate.storage.settings
        ))
    } else if let libraryItem = selectedItem.tab {
      AppDelegate.mainWindowHostVC?.pushTabCategory(tabCategory: libraryItem)
    }
  }
}
