//
//  LoginVC.swift
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
import SwiftUI
import UIKit
import UniformTypeIdentifiers

extension String {
  var isHyperTextProtocolProvided: Bool {
    hasPrefix("https://") || hasPrefix("http://")
  }
}

extension UITextField {
  func configuteForLogin(image: UIImage) {
    clipsToBounds = true
    borderStyle = .none
    backgroundColor = .clear
    font = .systemFont(ofSize: LoginVC.fontSize)
    textColor = .label
    tintColor = .label

    let leftContainerView = UIView(frame: CGRect(x: 0, y: 0, width: 38, height: 44))
    let imageView = UIImageView(frame: CGRect(x: 11, y: 14, width: 16, height: 16))
    imageView.contentMode = .scaleAspectFit
    imageView.image = image.withRenderingMode(.alwaysTemplate)
    imageView.tintColor = .tertiaryLabel
    leftContainerView.addSubview(imageView)

    leftView = leftContainerView
    leftViewMode = .always
  }
}

// MARK: - LoginRowView

/// One row of the grouped login card: fixed height plus an optional hairline separator.
fileprivate final class LoginRowView: UIView {
  static let height: CGFloat = 44

  let content: UIView
  private let separatorView = UIView()
  var showsSeparator: Bool {
    get { !separatorView.isHidden }
    set { separatorView.isHidden = !newValue }
  }

  init(content: UIView, showsSeparator: Bool = true) {
    self.content = content
    super.init(frame: .zero)
    content.translatesAutoresizingMaskIntoConstraints = false
    separatorView.translatesAutoresizingMaskIntoConstraints = false
    separatorView.backgroundColor = .separator
    separatorView.isHidden = !showsSeparator
    addSubview(content)
    addSubview(separatorView)
    NSLayoutConstraint.activate([
      heightAnchor.constraint(equalToConstant: Self.height),
      content.topAnchor.constraint(equalTo: topAnchor),
      content.leadingAnchor.constraint(equalTo: leadingAnchor),
      content.trailingAnchor.constraint(equalTo: trailingAnchor),
      content.bottomAnchor.constraint(equalTo: bottomAnchor),
      separatorView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
      separatorView.trailingAnchor.constraint(equalTo: trailingAnchor),
      separatorView.bottomAnchor.constraint(equalTo: bottomAnchor),
      separatorView.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

// MARK: - LoginVC

class LoginVC: UIViewController {
  var selectedApiType: BackenApiType = .webdav
  var httpHeaders: [String: String] = [:]
  var localFolderURL: URL?
  var localFolderBookmark: Data?

  #if targetEnvironment(macCatalyst)
    static let fontSize: CGFloat = 13
  #else
    static let fontSize: CGFloat = 16
  #endif

  private var themeColor: UIColor {
    appDelegate.storage.settings.accounts.getSetting(nil).read.themePreference.asColor
  }

  fileprivate lazy var iconView: UIImageView = {
    let imageView = UIImageView()
    imageView.contentMode = .scaleAspectFit
    imageView.image = .appIconTemplate
    imageView.tintColor = themeColor
    return imageView
  }()

  fileprivate lazy var titleLabel: UILabel = {
    let label = UILabel()
    label.text = "Amperfy"
    label.font = .systemFont(ofSize: 28, weight: .semibold)
    label.textColor = themeColor
    label.textAlignment = .center
    return label
  }()

  fileprivate lazy var subtitleLabel: UILabel = {
    let label = UILabel()
    label.text = L10n.tr("Sign in to your music library")
    label.font = .systemFont(ofSize: 13)
    label.textColor = .secondaryLabel
    label.textAlignment = .center
    label.numberOfLines = 0
    return label
  }()

  fileprivate lazy var apiRowLabel: UILabel = {
    let label = UILabel()
    label.text = L10n.tr("API")
    label.font = .systemFont(ofSize: Self.fontSize)
    label.textColor = .label
    return label
  }()

  fileprivate lazy var serverUrlTF: UITextField = {
    let textField = UITextField()
    textField.configuteForLogin(image: .serverUrl)
    textField.placeholder = "https://localhost/ampache"
    textField.textContentType = .URL
    textField.keyboardType = .URL
    textField.autocorrectionType = .no
    textField.autocapitalizationType = .none
    textField.addTarget(
      self,
      action: #selector(Self.serverUrlActionPressed),
      for: .primaryActionTriggered
    )
    return textField
  }()

  @IBAction
  func serverUrlActionPressed() {
    serverUrlTF.resignFirstResponder()
    login()
  }

  fileprivate lazy var usernameTF: UITextField = {
    let textField = UITextField()
    textField.configuteForLogin(image: .userPerson)
    textField.placeholder = L10n.tr("Username")
    textField.textContentType = .username
    textField.keyboardType = .default
    textField.autocorrectionType = .no
    textField.autocapitalizationType = .none
    textField.addTarget(
      self,
      action: #selector(Self.usernameActionPressed),
      for: .primaryActionTriggered
    )
    return textField
  }()

  @IBAction
  func usernameActionPressed() {
    usernameTF.resignFirstResponder()
    login()
  }

  fileprivate lazy var passwordTF: UITextField = {
    let textField = UITextField()
    textField.configuteForLogin(image: .password)
    textField.placeholder = L10n.tr("Password")
    textField.textContentType = .password
    textField.keyboardType = .default
    textField.isSecureTextEntry = true
    textField.autocorrectionType = .no
    textField.autocapitalizationType = .none
    textField.addTarget(
      self,
      action: #selector(Self.passwordActionPressed),
      for: .primaryActionTriggered
    )
    return textField
  }()

  @IBAction
  func passwordActionPressed() {
    passwordTF.resignFirstResponder()
    login()
  }

  fileprivate lazy var apiSelectorButton: UIButton = {
    var config = UIButton.Configuration.plain()
    config.image = UIImage(systemName: "chevron.up.chevron.down")
    config.imagePlacement = .trailing
    config.imagePadding = 6
    config.baseForegroundColor = .secondaryLabel
    config.contentInsets = .zero
    config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
      var outgoing = incoming
      outgoing.font = .systemFont(ofSize: Self.fontSize)
      return outgoing
    }
    let button = UIButton(configuration: config)
    button.setTitle(L10n.tr("API"), for: .normal)
    button.showsMenuAsPrimaryAction = true
    button.preferredBehavioralStyle = .pad
    return button
  }()

  fileprivate lazy var loginButton: UIButton = {
    var config = UIButton.Configuration.filled()
    config.baseBackgroundColor = themeColor
    config.baseForegroundColor = .white
    config.background.cornerRadius = 8
    config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
    config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
      var outgoing = incoming
      outgoing.font = .systemFont(ofSize: Self.fontSize, weight: .semibold)
      return outgoing
    }
    let button = UIButton(configuration: config)
    button.setTitle(L10n.tr("Login"), for: .normal)
    button.accessibilityLabel = L10n.tr("Login")
    button.addTarget(self, action: #selector(Self.loginPressed), for: .touchUpInside)
    button.preferredBehavioralStyle = .pad
    return button
  }()

  fileprivate lazy var httpHeadersButton: UIButton = {
    var config = UIButton.Configuration.plain()
    config.image = UIImage(systemName: "slider.horizontal.3")
    config.imagePlacement = .leading
    config.imagePadding = 10
    config.baseForegroundColor = .secondaryLabel
    config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
      pointSize: 15,
      weight: .regular
    )
    config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
    config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
      var outgoing = incoming
      outgoing.font = .systemFont(ofSize: Self.fontSize)
      outgoing.foregroundColor = .label
      return outgoing
    }
    let button = UIButton(configuration: config)
    button.setTitle(L10n.tr("Custom HTTP Headers"), for: .normal)
    button.accessibilityLabel = L10n.tr("Custom HTTP Headers")
    button.contentHorizontalAlignment = .leading
    button.addTarget(self, action: #selector(Self.httpHeadersPressed), for: .touchUpInside)
    button.preferredBehavioralStyle = .pad
    return button
  }()

  @IBAction
  func httpHeadersPressed() {
    let editor = CustomHTTPHeadersView(headers: httpHeaders) { [weak self] updated in
      self?.httpHeaders = updated
    }
    let hostingController = UIHostingController(rootView: AnyView(EmptyView()))
    hostingController.rootView = AnyView(NavigationStack {
      editor
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button(L10n.tr("Done")) { [weak hostingController] in
              hostingController?.dismiss(animated: true)
            }
          }
        }
    })
    hostingController.modalPresentationStyle = .formSheet
    present(hostingController, animated: true)
  }

  // Close button shown when presented as a sheet/modal
  fileprivate lazy var closeButton: UIButton = {
    var config = UIButton.Configuration.plain()
    config.image = .xmark
    config.baseForegroundColor = .secondaryLabel
    config.background.backgroundColor = .quaternarySystemFill
    config.background.cornerRadius = 14
    config.contentInsets = .zero
    let button = UIButton(configuration: config)
    button.accessibilityLabel = L10n.tr("Close")
    button.addTarget(self, action: #selector(Self.closePressed), for: .touchUpInside)
    button.preferredBehavioralStyle = .pad
    button.isHidden = true
    return button
  }()

  @IBAction
  func closePressed() {
    // Dismiss when presented modally (e.g., as a sheet)
    if presentingViewController != nil || navigationController?.presentingViewController != nil {
      dismiss(animated: true)
    }
  }

  @IBAction
  func loginPressed() {
    serverUrlTF.resignFirstResponder()
    usernameTF.resignFirstResponder()
    passwordTF.resignFirstResponder()
    login()
  }

  // MARK: - Card layout

  private var apiRow: LoginRowView!
  private var serverUrlRow: LoginRowView!
  private var usernameRow: LoginRowView!
  private var passwordRow: LoginRowView!
  private var httpHeadersRow: LoginRowView!

  private lazy var cardView: UIView = {
    let view = UIView()
    view.backgroundColor = .secondarySystemBackground
    view.layer.cornerRadius = 14
    view.layer.cornerCurve = .continuous
    view.layer.borderWidth = 1 / UIScreen.main.scale
    view.layer.borderColor = UIColor.separator.cgColor
    view.layer.shadowColor = UIColor.black.cgColor
    view.layer.shadowOpacity = 0.06
    view.layer.shadowRadius = 16
    view.layer.shadowOffset = CGSize(width: 0, height: 6)
    return view
  }()

  private lazy var cardStack: UIStackView = {
    apiRowLabel.translatesAutoresizingMaskIntoConstraints = false
    apiSelectorButton.translatesAutoresizingMaskIntoConstraints = false
    let apiContent = UIView()
    apiContent.addSubview(apiRowLabel)
    apiContent.addSubview(apiSelectorButton)
    NSLayoutConstraint.activate([
      apiRowLabel.leadingAnchor.constraint(equalTo: apiContent.leadingAnchor, constant: 14),
      apiRowLabel.centerYAnchor.constraint(equalTo: apiContent.centerYAnchor),
      apiSelectorButton.leadingAnchor.constraint(
        greaterThanOrEqualTo: apiRowLabel.trailingAnchor,
        constant: 12
      ),
      apiSelectorButton.trailingAnchor.constraint(
        equalTo: apiContent.trailingAnchor,
        constant: -14
      ),
      apiSelectorButton.centerYAnchor.constraint(equalTo: apiContent.centerYAnchor),
    ])

    func makeFieldRow(_ textField: UITextField) -> LoginRowView {
      textField.translatesAutoresizingMaskIntoConstraints = false
      let content = UIView()
      content.addSubview(textField)
      NSLayoutConstraint.activate([
        textField.leadingAnchor.constraint(equalTo: content.leadingAnchor),
        textField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
        textField.topAnchor.constraint(equalTo: content.topAnchor),
        textField.bottomAnchor.constraint(equalTo: content.bottomAnchor),
      ])
      return LoginRowView(content: content)
    }

    httpHeadersButton.translatesAutoresizingMaskIntoConstraints = false
    let httpContent = UIView()
    httpContent.addSubview(httpHeadersButton)
    NSLayoutConstraint.activate([
      httpHeadersButton.leadingAnchor.constraint(equalTo: httpContent.leadingAnchor),
      httpHeadersButton.trailingAnchor.constraint(equalTo: httpContent.trailingAnchor),
      httpHeadersButton.topAnchor.constraint(equalTo: httpContent.topAnchor),
      httpHeadersButton.bottomAnchor.constraint(equalTo: httpContent.bottomAnchor),
    ])

    apiRow = LoginRowView(content: apiContent)
    serverUrlRow = makeFieldRow(serverUrlTF)
    usernameRow = makeFieldRow(usernameTF)
    passwordRow = makeFieldRow(passwordTF)
    httpHeadersRow = LoginRowView(content: httpContent, showsSeparator: false)

    let stack = UIStackView(arrangedSubviews: [
      apiRow, serverUrlRow, usernameRow, passwordRow, httpHeadersRow,
    ])
    stack.axis = .vertical
    stack.spacing = 0
    return stack
  }()

  private lazy var contentStack: UIStackView = {
    iconView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      iconView.widthAnchor.constraint(equalToConstant: 44),
      iconView.heightAnchor.constraint(equalToConstant: 44),
    ])

    let headerStack = UIStackView(arrangedSubviews: [iconView, titleLabel, subtitleLabel])
    headerStack.axis = .vertical
    headerStack.alignment = .center
    headerStack.spacing = 8
    headerStack.setCustomSpacing(14, after: iconView)

    cardStack.translatesAutoresizingMaskIntoConstraints = false
    cardView.addSubview(cardStack)
    NSLayoutConstraint.activate([
      cardStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 2),
      cardStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
      cardStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
      cardStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -2),
    ])

    loginButton.translatesAutoresizingMaskIntoConstraints = false
    loginButton.heightAnchor.constraint(equalToConstant: 40).isActive = true

    let stack = UIStackView(arrangedSubviews: [headerStack, cardView, loginButton])
    stack.axis = .vertical
    stack.spacing = 18
    stack.setCustomSpacing(26, after: headerStack)
    return stack
  }()

  func login() {
    if selectedApiType == .local {
      guard let localFolderURL, let localFolderBookmark else {
        presentLocalFolderPicker()
        return
      }
      var credentials = LoginCredentials(
        serverUrl: localFolderURL.path,
        username: "Local",
        password: ""
      )
      credentials.backendApi = .local
      credentials.localFolderBookmark = localFolderBookmark
      credentials.localFolderPath = localFolderURL.path
      performLogin(credentials: credentials)
      return
    }

    guard let serverUrl = serverUrlTF.text?.trimmingCharacters(in: .whitespacesAndNewlines),
          !serverUrl.isEmpty else {
      showErrorMsg(message: L10n.tr("No server URL given!"))
      return
    }
    guard serverUrl.isHyperTextProtocolProvided else {
      showErrorMsg(message: L10n.tr("Please provide either 'https://' or 'http://' in your server URL."))
      return
    }
    guard let username = usernameTF.text, !username.isEmpty else {
      showErrorMsg(message: L10n.tr("No username given!"))
      return
    }
    guard let password = passwordTF.text, !password.isEmpty else {
      showErrorMsg(message: L10n.tr("No password given!"))
      return
    }

    var credentials = LoginCredentials(serverUrl: serverUrl, username: username, password: password)
    credentials.httpHeaders = httpHeaders
    performLogin(credentials: credentials)
  }

  func performLogin(credentials: LoginCredentials) {
    var credentials = credentials
    var accountInfo = Account.createInfo(credentials: credentials)

    guard !appDelegate.storage.settings.accounts.allAccounts.contains(where: { $0 == accountInfo })
    else {
      showErrorMsg(message: L10n.tr("Account already added!"))
      return
    }

    Task { @MainActor in
      do {
        let meta = self.appDelegate.getMeta(accountInfo)
        let authenticatedApiType = try await meta.backendApi.login(
          apiType: selectedApiType,
          credentials: credentials
        )
        credentials.backendApi = authenticatedApiType
        accountInfo = Account.createInfo(credentials: credentials)
        meta.backendApi.selectedApi = authenticatedApiType
        meta.account.assignInfo(info: accountInfo)
        self.appDelegate.storage.main.saveContext()
        self.appDelegate.storage.settings.accounts.login(credentials)
        meta.backendApi.provideCredentials(credentials: credentials)

        self.appDelegate.notificationHandler.post(name: .accountAdded, object: nil, userInfo: nil)
        self.appDelegate.notificationHandler.post(
          name: .accountActiveChanged,
          object: nil,
          userInfo: nil
        )
        AmperfyAppShortcuts.updateAppShortcutParameters()

        let syncVC = AppStoryboard.Main.segueToSync(account: meta.account)
        if let rootVC = presentingViewController {
          syncVC.modalPresentationStyle = self.modalPresentationStyle
          rootVC.dismiss(animated: false) {
            rootVC.present(syncVC, animated: false)
          }
        } else {
          guard let mainScene = AppDelegate.mainSceneDelegate else { return }
          mainScene
            .replaceMainRootViewController(vc: syncVC)
        }
      } catch {
        if error is AuthenticationError {
          self.showErrorMsg(message: error.localizedDescription)
        } else {
          self.showErrorMsg(message: L10n.tr("Not able to login!"))
        }
        self.appDelegate.resetMeta(accountInfo)
      }
    }
  }

  func showErrorMsg(message: String) {
    let alert = UIAlertController(
      title: L10n.tr("Login failed"),
      message: message,
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: L10n.tr("OK"), style: .default))
    present(alert, animated: true, completion: nil)
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    apiSelectorButton.menu = UIMenu(title: L10n.tr("Select Source"), children: [
      UIAction(title: BackenApiType.local.selectorDescription, handler: { _ in
        self.selectedApiType = .local
        self.updateApiSelectorText()
      }),
      UIAction(title: BackenApiType.webdav.selectorDescription, handler: { _ in
        self.selectedApiType = .webdav
        self.updateApiSelectorText()
      }),
    ])

    view.backgroundColor = .systemBackground

    contentStack.translatesAutoresizingMaskIntoConstraints = false
    closeButton.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(contentStack)
    view.addSubview(closeButton)

    let centerY = contentStack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
    centerY.priority = .defaultHigh
    let width = contentStack.widthAnchor.constraint(equalToConstant: 360)
    width.priority = UILayoutPriority(999)

    NSLayoutConstraint.activate([
      contentStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      centerY,
      width,
      contentStack.widthAnchor.constraint(
        lessThanOrEqualTo: view.safeAreaLayoutGuide.widthAnchor,
        constant: -48
      ),
      contentStack.topAnchor.constraint(
        greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor,
        constant: 24
      ),
      contentStack.bottomAnchor.constraint(
        lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor,
        constant: -24
      ),

      closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
      closeButton.trailingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.trailingAnchor,
        constant: -16
      ),
      closeButton.widthAnchor.constraint(equalToConstant: 28),
      closeButton.heightAnchor.constraint(equalToConstant: 28),
    ])

    updateApiSelectorText()

    let isModal = presentingViewController != nil || navigationController?
      .presentingViewController != nil
    closeButton.isHidden = !isModal
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection)
    else { return }
    cardView.layer.borderColor = UIColor.separator.resolvedColor(with: traitCollection).cgColor
  }

  override func viewIsAppearing(_ animated: Bool) {
    super.viewIsAppearing(animated)
    guard let credentials = appDelegate.storage.settings.accounts.getSetting(nil).read
      .loginCredentials else { return }
    // Only prefill when logging in the first account or adding another account
    // of the same source type. A local folder path must not leak into the
    // WebDAV form (and vice versa).
    guard appDelegate.storage.settings.accounts.allAccounts.isEmpty
      || credentials.backendApi == selectedApiType
    else { return }
    serverUrlTF.text = credentials.serverUrl
    usernameTF.text = credentials.username
    httpHeaders = credentials.httpHeaders
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    let isModal = presentingViewController != nil || navigationController?
      .presentingViewController != nil
    closeButton.isHidden = !isModal
  }

  func updateApiSelectorText() {
    apiSelectorButton.setTitle(selectedApiType.selectorDescription, for: .normal)
    updateLoginForm()
  }

  func updateLoginForm() {
    let isLocal = selectedApiType == .local
    usernameRow?.isHidden = isLocal
    passwordRow?.isHidden = isLocal
    httpHeadersRow?.isHidden = isLocal
    serverUrlRow?.showsSeparator = !isLocal
    serverUrlTF.isUserInteractionEnabled = !isLocal
    serverUrlTF.placeholder = isLocal
      ? L10n.tr("Tap Login to choose a music folder")
      : "https://dav.example.com/music"
    apiRowLabel.text = isLocal ? L10n.tr("Source") : L10n.tr("API")
    if isLocal {
      serverUrlTF.text = localFolderURL?.path
    } else if serverUrlTF.text == localFolderURL?.path {
      serverUrlTF.text = nil
    }
  }

  func presentLocalFolderPicker() {
    let picker = UIDocumentPickerViewController(
      forOpeningContentTypes: [.folder],
      asCopy: false
    )
    picker.delegate = self
    picker.allowsMultipleSelection = false
    present(picker, animated: true)
  }
}

// MARK: UIDocumentPickerDelegate

extension LoginVC: UIDocumentPickerDelegate {
  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    guard let folderURL = urls.first else { return }
    do {
      let bookmark = try LocalFolderAccess.createBookmark(for: folderURL)
      localFolderURL = folderURL
      localFolderBookmark = bookmark
      serverUrlTF.text = folderURL.path
      login()
    } catch {
      showErrorMsg(message: error.localizedDescription)
    }
  }
}
