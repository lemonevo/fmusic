//
//  SideBarVC.swift
//  fmusic
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

import fmusicKit
import UIKit

class SideBarVC: KeyCommandCollectionViewController {
  private static let accountFooterHeight: CGFloat = 48

  private let account: Account!
  private var accountMenuButton: UIButton?
  private var accountNameLabel: UILabel?
  private var avatarLabel: UILabel?
  private var accountSwitcherOverlay: AccountSwitcherOverlay?
  private var accountSwitcherView: AccountSwitcherView?
  private var accountSwitcherBottomConstraint: NSLayoutConstraint?

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

    if let overlay = accountSwitcherOverlay,
       let button = accountMenuButton,
       let superview = overlay.superview {
      let anchor = button.convert(button.bounds, to: superview)
      accountSwitcherBottomConstraint?.constant = anchor.minY - 6
    }
  }

  private func configureAccountFooter() {
    let footer = UIView()
    footer.translatesAutoresizingMaskIntoConstraints = false

    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.addTarget(self, action: #selector(showAccountSwitcher), for: .touchUpInside)
    button.accessibilityLabel = L10n.tr("Account")

    let avatar = UILabel()
    avatar.translatesAutoresizingMaskIntoConstraints = false
    avatar.font = .systemFont(ofSize: 13, weight: .semibold)
    avatar.textAlignment = .center
    avatar.textColor = .white
    avatar.backgroundColor = UIColor(red: 0.56, green: 0.65, blue: 0.91, alpha: 1.0)
    avatar.layer.cornerRadius = 9
    avatar.layer.cornerCurve = .continuous
    avatar.clipsToBounds = true

    let name = UILabel()
    name.translatesAutoresizingMaskIntoConstraints = false
    name.font = .systemFont(ofSize: 15, weight: .semibold)
    name.textColor = .label

    let stack = UIStackView(arrangedSubviews: [avatar, name])
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .horizontal
    stack.alignment = .center
    stack.spacing = 14
    stack.isUserInteractionEnabled = false

    let settingsButton = UIControl()
    settingsButton.translatesAutoresizingMaskIntoConstraints = false
    settingsButton.isAccessibilityElement = true
    settingsButton.accessibilityLabel = L10n.tr("Settings")
    settingsButton.accessibilityTraits = .button
    settingsButton.addTarget(self, action: #selector(showSettings), for: .touchUpInside)

    let gearView = UIImageView(
      image: UIImage(
        systemName: "gearshape",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
      )
    )
    gearView.translatesAutoresizingMaskIntoConstraints = false
    gearView.contentMode = .scaleAspectFit
    gearView.tintColor = .secondaryLabel

    guard let containerView = navigationController?.view ?? view else { return }
    containerView.addSubview(footer)
    footer.addSubview(button)
    footer.addSubview(settingsButton)
    settingsButton.addSubview(gearView)
    button.addSubview(stack)

    NSLayoutConstraint.activate([
      footer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
      footer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
      footer.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
      footer.heightAnchor.constraint(equalToConstant: Self.accountFooterHeight),

      button.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 16),
      button.trailingAnchor.constraint(
        lessThanOrEqualTo: settingsButton.leadingAnchor,
        constant: -8
      ),
      button.bottomAnchor.constraint(equalTo: footer.bottomAnchor, constant: -10),
      button.heightAnchor.constraint(equalToConstant: 28),

      settingsButton.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -16),
      settingsButton.centerYAnchor.constraint(equalTo: button.centerYAnchor),
      settingsButton.widthAnchor.constraint(equalToConstant: 28),
      settingsButton.heightAnchor.constraint(equalToConstant: 28),

      gearView.widthAnchor.constraint(equalToConstant: 18),
      gearView.heightAnchor.constraint(equalToConstant: 18),
      gearView.centerXAnchor.constraint(equalTo: settingsButton.centerXAnchor),
      gearView.centerYAnchor.constraint(equalTo: settingsButton.centerYAnchor),

      stack.leadingAnchor.constraint(equalTo: button.leadingAnchor),
      stack.centerYAnchor.constraint(equalTo: button.centerYAnchor),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: button.trailingAnchor),

      avatar.widthAnchor.constraint(equalToConstant: 28),
      avatar.heightAnchor.constraint(equalToConstant: 28),
    ])

    accountMenuButton = button
    accountNameLabel = name
    avatarLabel = avatar
    refreshAccountFooter()
  }

  private func refreshAccountFooter() {
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


// MARK: - Account switcher

extension SideBarVC {
  @objc
  private func showSettings() {
    appDelegate.showSettings(sender: "")
  }

  @objc
  private func showAccountSwitcher() {
    guard accountSwitcherOverlay == nil,
          let window = view.window,
          let button = accountMenuButton
    else { return }

    let switcher = AccountSwitcherView()
    switcher.onSelectAccount = { [weak self] accountInfo in
      guard let self else { return }
      guard accountInfo != self.appDelegate.storage.settings.accounts.active else {
        self.hideAccountSwitcher()
        return
      }
      self.hideAccountSwitcher(animated: false) {
        self.appDelegate.switchAccount(accountInfo: accountInfo)
      }
    }
    switcher.onRemoveAccount = { [weak self] accountInfo in
      self?.hideAccountSwitcher {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
          self?.confirmRemoveAccount(accountInfo: accountInfo)
        }
      }
    }
    switcher.onAddAccount = { [weak self] in
      guard let self else { return }
      self.hideAccountSwitcher(animated: false)
      let loginVC = AppStoryboard.Main.segueToLogin()
      loginVC.modalPresentationStyle = .formSheet
      self.present(loginVC, animated: true)
    }
    switcher.onOpenSettings = { [weak self] in
      guard let self else { return }
      // Fade the switcher out while the settings window comes up instead of cutting it away.
      self.hideAccountSwitcher()
      self.appDelegate.showSettings(sender: "")
    }

    let overlay = AccountSwitcherOverlay(frame: window.bounds)
    overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    overlay.onDismiss = { [weak self] in
      self?.hideAccountSwitcher()
    }
    overlay.addSubview(switcher)
    window.addSubview(overlay)

    let anchor = button.convert(button.bounds, to: window)
    let bottomConstraint = switcher.bottomAnchor.constraint(
      equalTo: overlay.topAnchor,
      constant: anchor.minY - 6
    )
    NSLayoutConstraint.activate([
      switcher.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 8),
      switcher.widthAnchor.constraint(equalToConstant: 194),
      bottomConstraint,
    ])

    accountSwitcherOverlay = overlay
    accountSwitcherView = switcher
    accountSwitcherBottomConstraint = bottomConstraint

    appDelegate.accountSwitcherDismissHandler = { [weak self] in
      self?.hideAccountSwitcher()
    }

    switcher.alpha = 0
    switcher.transform = CGAffineTransform(translationX: 0, y: 6)
    overlay.alpha = 0
    UIView.animate(
      withDuration: 0.16,
      delay: 0,
      options: [.curveEaseOut, .allowUserInteraction]
    ) {
      overlay.alpha = 1
      switcher.alpha = 1
      switcher.transform = .identity
    }
  }

  private func hideAccountSwitcher(
    animated: Bool = true,
    completion: (() -> ())? = nil
  ) {
    guard let overlay = accountSwitcherOverlay else {
      completion?()
      return
    }
    let switcher = accountSwitcherView
    accountSwitcherOverlay = nil
    accountSwitcherView = nil
    accountSwitcherBottomConstraint = nil
    appDelegate.accountSwitcherDismissHandler = nil
    overlay.resignFirstResponder()

    let finish = {
      overlay.removeFromSuperview()
      completion?()
    }
    guard animated else {
      finish()
      return
    }
    UIView.animate(
      withDuration: 0.12,
      delay: 0,
      options: [.curveEaseIn, .allowUserInteraction]
    ) {
      overlay.alpha = 0
      switcher?.alpha = 0
      switcher?.transform = CGAffineTransform(translationX: 0, y: 6)
    } completion: { _ in
      finish()
    }
  }

  private func confirmRemoveAccount(accountInfo: AccountInfo) {
    let username = appDelegate.storage.settings.accounts.getSetting(accountInfo).read
      .loginCredentials?.username ?? ""
    let name = username.isEmpty ? L10n.tr("Account") : username
    let alert = UIAlertController(
      title: L10n.tr("Remove Account"),
      message: L10n.tr(
        "Removing “%@” deletes its login credentials and all downloaded files for this account. Your original music files are not touched.\n\nDo you want to remove this account?",
        name
      ),
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: L10n.tr("Cancel"), style: .cancel))
    alert.addAction(UIAlertAction(title: L10n.tr("Remove"), style: .destructive) { [weak self] _ in
      self?.appDelegate.removeAccount(accountInfo: accountInfo)
    })
    present(alert, animated: true)
  }
}

// MARK: - AccountSwitcherOverlay

private final class AccountSwitcherOverlay: UIControl {
  var onDismiss: (() -> ())?

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    addTarget(self, action: #selector(handleTap), for: .touchUpInside)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @objc
  private func handleTap() {
    onDismiss?()
  }

}

// MARK: - AccountSwitcherView

private final class AccountSwitcherView: UIView {
  var onSelectAccount: ((AccountInfo) -> ())?
  var onRemoveAccount: ((AccountInfo) -> ())?
  var onAddAccount: (() -> ())?
  var onOpenSettings: (() -> ())?

  private let accountRowHeight: CGFloat = 52
  private let actionRowHeight: CGFloat = 40
  private let separatorHeight: CGFloat = 9
  private let verticalPadding: CGFloat = 6

  init() {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    backgroundColor = .secondarySystemBackground
    layer.cornerRadius = 12
    layer.cornerCurve = .continuous
    layer.borderWidth = 1.0 / UIScreen.main.scale
    layer.borderColor = UIColor.separator.cgColor
    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOpacity = 0.12
    layer.shadowRadius = 12
    layer.shadowOffset = CGSize(width: 0, height: 4)
    buildContent()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    layer.borderColor = UIColor.separator.cgColor
  }

  private func buildContent() {
    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = 0
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)

    let accounts = appDelegate.storage.settings.accounts.allAccounts
    for accountInfo in accounts {
      let isActive = accountInfo == appDelegate.storage.settings.accounts.active
      stack.addArrangedSubview(makeAccountRow(accountInfo: accountInfo, isActive: isActive))
    }
    stack.addArrangedSubview(makeSeparator())
    stack.addArrangedSubview(makeActionRow(title: L10n.tr("Add Account")) { [weak self] in
      self?.onAddAccount?()
    })
    stack.addArrangedSubview(makeActionRow(title: L10n.tr("Settings")) { [weak self] in
      self?.onOpenSettings?()
    })

    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: topAnchor, constant: verticalPadding),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -verticalPadding),
    ])
  }

  private func makeAccountRow(accountInfo: AccountInfo, isActive: Bool) -> UIView {
    let row = AccountSwitcherRow()
    row.translatesAutoresizingMaskIntoConstraints = false
    row.heightAnchor.constraint(equalToConstant: accountRowHeight).isActive = true
    row.onTap = { [weak self] in
      self?.onSelectAccount?(accountInfo)
    }

    let credentials = appDelegate.storage.settings.accounts.getSetting(accountInfo).read
      .loginCredentials
    let username = credentials?.username ?? ""
    let name = username.isEmpty ? L10n.tr("Account") : username
    let serverUrl = credentials?.displayServerUrl ?? ""

    let checkmark = UIImageView(image: UIImage(systemName: "checkmark"))
    checkmark.translatesAutoresizingMaskIntoConstraints = false
    checkmark.tintColor = .label
    checkmark.contentMode = .scaleAspectFit
    checkmark.isHidden = !isActive

    let nameLabel = UILabel()
    nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
    nameLabel.textColor = .label
    nameLabel.text = name

    let urlLabel = UILabel()
    urlLabel.font = .systemFont(ofSize: 11)
    urlLabel.textColor = .secondaryLabel
    urlLabel.text = serverUrl
    urlLabel.lineBreakMode = .byTruncatingMiddle

    let labels = UIStackView(arrangedSubviews: [nameLabel, urlLabel])
    labels.translatesAutoresizingMaskIntoConstraints = false
    labels.axis = .vertical
    labels.spacing = 1

    let minusButton = UIButton(type: .system)
    minusButton.translatesAutoresizingMaskIntoConstraints = false
    minusButton.setImage(
      UIImage(
        systemName: "minus.circle",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
      ),
      for: .normal
    )
    minusButton.tintColor = .secondaryLabel
    minusButton.accessibilityLabel = L10n.tr("Remove Account")
    minusButton.addAction(UIAction { [weak self] _ in
      self?.onRemoveAccount?(accountInfo)
    }, for: .touchUpInside)

    row.addSubview(checkmark)
    row.addSubview(labels)
    row.addSubview(minusButton)
    NSLayoutConstraint.activate([
      checkmark.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
      checkmark.centerYAnchor.constraint(equalTo: row.centerYAnchor),
      checkmark.widthAnchor.constraint(equalToConstant: 14),
      checkmark.heightAnchor.constraint(equalToConstant: 14),

      labels.leadingAnchor.constraint(equalTo: checkmark.trailingAnchor, constant: 10),
      labels.centerYAnchor.constraint(equalTo: row.centerYAnchor),
      labels.trailingAnchor.constraint(equalTo: minusButton.leadingAnchor, constant: -8),

      minusButton.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8),
      minusButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
      minusButton.widthAnchor.constraint(equalToConstant: 28),
      minusButton.heightAnchor.constraint(equalToConstant: 28),
    ])
    return row
  }

  private func makeSeparator() -> UIView {
    let container = UIView()
    container.translatesAutoresizingMaskIntoConstraints = false
    container.heightAnchor.constraint(equalToConstant: separatorHeight).isActive = true
    let line = UIView()
    line.translatesAutoresizingMaskIntoConstraints = false
    line.backgroundColor = .separator
    container.addSubview(line)
    NSLayoutConstraint.activate([
      line.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
      line.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
      line.centerYAnchor.constraint(equalTo: container.centerYAnchor),
      line.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),
    ])
    return container
  }

  private func makeActionRow(title: String, action: @escaping () -> ()) -> UIView {
    let row = AccountSwitcherRow()
    row.translatesAutoresizingMaskIntoConstraints = false
    row.heightAnchor.constraint(equalToConstant: actionRowHeight).isActive = true
    row.onTap = action

    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 13)
    label.textColor = .label
    label.text = title
    row.addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
      label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
      label.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -10),
    ])
    return row
  }
}

// MARK: - AccountSwitcherRow

private final class AccountSwitcherRow: UIControl {
  var onTap: (() -> ())?

  private var isHovered = false

  override init(frame: CGRect) {
    super.init(frame: frame)
    layer.cornerRadius = 6
    addTarget(self, action: #selector(handleTap), for: .touchUpInside)
    addGestureRecognizer(
      UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
    )
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @objc
  private func handleTap() {
    onTap?()
  }

  @objc
  private func handleHover(_ recognizer: UIHoverGestureRecognizer) {
    isHovered = recognizer.state == .began || recognizer.state == .changed
    updateBackground()
  }

  override var isHighlighted: Bool {
    didSet { updateBackground() }
  }

  private func updateBackground() {
    backgroundColor = (isHovered || isHighlighted) ?
      UIColor.label.withAlphaComponent(0.06) : .clear
  }
}
