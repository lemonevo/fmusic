//
//  LoginViewController.swift
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
import fmusicKit

/// Login / add-account form of the pure AppKit app.
///
/// The flow mirrors the Catalyst `LoginVC` + `SyncVC` pair:
///  1. validate the entered credentials (or ask for a local music folder),
///  2. authenticate through the shared `BackendProxy`
///     (`meta.backendApi.login(apiType:credentials:)`),
///  3. persist the account exactly like the Catalyst login does
///     (`meta.account.assignInfo`, `storage.main.saveContext()`,
///     `storage.settings.accounts.login(credentials)`),
///  4. run the initial library sync through the shared `LibraryResyncService` and show its
///     progress callbacks,
///  5. close the window and let the shared notifications refresh the app
///     (`.accountAdded`, `.accountActiveChanged`, `.librarySongsSynced`).
///
/// Never logs or prints credentials. The password only lives in the text field and in the
/// `LoginCredentials` handed to the core, which persists it exactly like the Catalyst app.
@MainActor
final class LoginViewController: NSViewController {
  static let windowSize = NSSize(width: 480, height: 420)

  /// Called when the user closes the window without logging in.
  var onCancel: (() -> Void)?
  /// Called once the account was added and the initial sync finished or was skipped.
  var onLoginFinished: (() -> Void)?

  private var fmusic: FmusicKit { FmusicKit.shared }
  private var storage: PersistentStorage { FmusicKit.shared.storage }

  private let resyncService = LibraryResyncService()

  private let sourceTypes: [BackenApiType] = [.webdav, .local]

  private var selectedApiType: BackenApiType = .webdav
  private var localFolderURL: URL?
  private var localFolderBookmark: Data?
  /// Custom HTTP headers of the previously used account of the same source type. There is
  /// no header editor in the AppKit UI yet, but prefilling keeps them when an account is
  /// added again (e.g. a Cloudflare Access service token on the WebDAV server).
  private var prefilledHTTPHeaders: [String: String] = [:]

  private var loginTask: Task<Void, Never>?
  private var isBusy = false
  /// Set as soon as the credentials and the account were persisted. From that moment on a
  /// cancelled initial sync means "skip", never "login failed".
  private var hasPersistedAccount = false
  private var didFinish = false

  // MARK: - Views

  private var headerStack: NSStackView!

  private let cardView = LoginCardView()
  private let busyView = LoginCardView()

  private let iconView = NSImageView()
  private let titleLabel = NSTextField(labelWithString: "fmusic")
  private let subtitleLabel = NSTextField(labelWithString: L10n.tr("Sign in to your music library"))

  private let sourcePopup = NSPopUpButton(frame: .zero, pullsDown: false)
  private let serverUrlField = NSTextField(frame: .zero)
  private let usernameField = NSTextField(frame: .zero)
  private let passwordField = NSSecureTextField(frame: .zero)
  private let folderPathLabel = NSTextField(labelWithString: "")
  private let chooseFolderButton = NSButton()
  private var sourceRow: NSStackView!
  private var serverUrlRow: NSStackView!
  private var usernameRow: NSStackView!
  private var passwordRow: NSStackView!
  private var folderRow: NSStackView!

  private let busyTitleLabel = NSTextField(labelWithString: "")
  private let busyStatusLabel = NSTextField(labelWithString: "")
  private let busyDetailLabel = NSTextField(labelWithString: "")
  private let progressIndicator = NSProgressIndicator()

  private let loginButton = NSButton()
  private let cancelButton = NSButton()

  // MARK: - Lifecycle

  override func loadView() {
    let root = NSView(frame: NSRect(origin: .zero, size: Self.windowSize))
    root.wantsLayer = true
    self.view = root

    buildHeader()
    buildFormCard()
    buildBusyCard()
    buildButtons()

    updateFormVisibility()
    prefillCredentialsIfNeeded()
  }

  override func viewDidAppear() {
    super.viewDidAppear()
    if selectedApiType == .local {
      view.window?.makeFirstResponder(chooseFolderButton)
    } else {
      view.window?.makeFirstResponder(serverUrlField)
    }
  }

  // MARK: - Layout

  private func buildHeader() {
    iconView.image = NSApp.applicationIconImage
    iconView.imageScaling = .scaleProportionallyUpOrDown
    iconView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      iconView.widthAnchor.constraint(equalToConstant: 44),
      iconView.heightAnchor.constraint(equalToConstant: 44),
    ])

    titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
    titleLabel.textColor = .labelColor
    titleLabel.alignment = .center

    subtitleLabel.font = MacTheme.bodyFont
    subtitleLabel.textColor = .secondaryLabelColor
    subtitleLabel.alignment = .center
    subtitleLabel.lineBreakMode = .byWordWrapping
    subtitleLabel.maximumNumberOfLines = 2
    subtitleLabel.preferredMaxLayoutWidth = 340

    let header = NSStackView(views: [iconView, titleLabel, subtitleLabel])
    header.orientation = .vertical
    header.alignment = .centerX
    header.spacing = 4
    header.setCustomSpacing(10, after: iconView)
    header.translatesAutoresizingMaskIntoConstraints = false
    headerStack = header
    view.addSubview(header)

    NSLayoutConstraint.activate([
      header.topAnchor.constraint(equalTo: view.topAnchor, constant: 26),
      header.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      header.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
      header.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
    ])
  }

  private func buildFormCard() {
    cardView.translatesAutoresizingMaskIntoConstraints = false

    sourcePopup.removeAllItems()
    sourcePopup.addItems(withTitles: sourceTypes.map(\.selectorDescription))
    sourcePopup.font = MacTheme.bodyFont
    sourcePopup.selectItem(at: 0)
    sourcePopup.target = self
    sourcePopup.action = #selector(sourceTypeChanged)

    configureInputField(
      serverUrlField,
      placeholder: "https://dav.example.com/music",
      contentType: .URL
    )
    configureInputField(
      usernameField,
      placeholder: L10n.tr("Username"),
      contentType: .username
    )
    configureInputField(
      passwordField,
      placeholder: L10n.tr("Password"),
      contentType: .password
    )

    folderPathLabel.font = MacTheme.bodyFont
    folderPathLabel.textColor = .secondaryLabelColor
    folderPathLabel.lineBreakMode = .byTruncatingMiddle
    folderPathLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
    folderPathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    chooseFolderButton.title = L10n.tr("Choose Folder…")
    chooseFolderButton.bezelStyle = .rounded
    chooseFolderButton.target = self
    chooseFolderButton.action = #selector(chooseFolderPressed)
    chooseFolderButton.setContentHuggingPriority(.required, for: .horizontal)
    chooseFolderButton.setContentCompressionResistancePriority(.required, for: .horizontal)

    let folderStack = NSStackView(views: [folderPathLabel, chooseFolderButton])
    folderStack.orientation = .horizontal
    folderStack.alignment = .centerY
    folderStack.spacing = 8

    sourceRow = makeRow(title: L10n.tr("Source"), control: sourcePopup)
    serverUrlRow = makeRow(title: L10n.tr("URL"), control: serverUrlField)
    usernameRow = makeRow(title: L10n.tr("Username"), control: usernameField)
    passwordRow = makeRow(title: L10n.tr("Password"), control: passwordField)
    folderRow = makeRow(title: L10n.tr("Local Folder"), control: folderStack)

    let rows: [NSStackView] = [sourceRow, serverUrlRow, usernameRow, passwordRow, folderRow]
    let cardStack = NSStackView(views: rows)
    cardStack.orientation = .vertical
    cardStack.alignment = .leading
    cardStack.spacing = 12
    // The local-folder form hides the URL/credentials rows; detaching hidden views lets the
    // card shrink to the remaining rows.
    cardStack.detachesHiddenViews = true
    cardStack.translatesAutoresizingMaskIntoConstraints = false
    for row in rows {
      row.widthAnchor.constraint(equalTo: cardStack.widthAnchor).isActive = true
    }

    cardView.addSubview(cardStack)
    view.addSubview(cardView)

    NSLayoutConstraint.activate([
      cardStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
      cardStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
      cardStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
      cardStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16),

      cardView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 20),
      cardView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
      cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
    ])
  }

  private func buildBusyCard() {
    busyView.translatesAutoresizingMaskIntoConstraints = false
    busyView.isHidden = true

    busyTitleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
    busyTitleLabel.textColor = .labelColor
    busyTitleLabel.lineBreakMode = .byTruncatingTail

    busyStatusLabel.font = MacTheme.bodyFont
    busyStatusLabel.textColor = .labelColor
    busyStatusLabel.lineBreakMode = .byTruncatingTail

    busyDetailLabel.font = MacTheme.secondaryFont
    busyDetailLabel.textColor = .secondaryLabelColor
    busyDetailLabel.lineBreakMode = .byTruncatingTail

    progressIndicator.style = .bar
    progressIndicator.isIndeterminate = true
    progressIndicator.minValue = 0
    progressIndicator.maxValue = 1
    progressIndicator.doubleValue = 0

    for subview in [busyTitleLabel, busyStatusLabel, progressIndicator, busyDetailLabel] {
      subview.translatesAutoresizingMaskIntoConstraints = false
      busyView.addSubview(subview)
    }
    view.addSubview(busyView)

    NSLayoutConstraint.activate([
      busyTitleLabel.topAnchor.constraint(equalTo: busyView.topAnchor, constant: 18),
      busyTitleLabel.leadingAnchor.constraint(equalTo: busyView.leadingAnchor, constant: 18),
      busyTitleLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: busyView.trailingAnchor,
        constant: -18
      ),

      busyStatusLabel.topAnchor.constraint(equalTo: busyTitleLabel.bottomAnchor, constant: 10),
      busyStatusLabel.leadingAnchor.constraint(equalTo: busyTitleLabel.leadingAnchor),
      busyStatusLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: busyView.trailingAnchor,
        constant: -18
      ),

      progressIndicator.topAnchor.constraint(equalTo: busyStatusLabel.bottomAnchor, constant: 10),
      progressIndicator.leadingAnchor.constraint(equalTo: busyView.leadingAnchor, constant: 18),
      progressIndicator.trailingAnchor.constraint(equalTo: busyView.trailingAnchor, constant: -18),
      progressIndicator.heightAnchor.constraint(equalToConstant: 20),

      busyDetailLabel.topAnchor.constraint(
        equalTo: progressIndicator.bottomAnchor,
        constant: 6
      ),
      busyDetailLabel.leadingAnchor.constraint(equalTo: busyTitleLabel.leadingAnchor),
      busyDetailLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: busyView.trailingAnchor,
        constant: -18
      ),
      busyDetailLabel.bottomAnchor.constraint(equalTo: busyView.bottomAnchor, constant: -18),

      busyView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 20),
      busyView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
      busyView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
    ])
  }

  private func buildButtons() {
    cancelButton.title = L10n.tr("Cancel")
    cancelButton.bezelStyle = .rounded
    cancelButton.keyEquivalent = "\u{1b}"
    cancelButton.target = self
    cancelButton.action = #selector(cancelPressed)

    loginButton.title = L10n.tr("Login")
    loginButton.bezelStyle = .rounded
    loginButton.keyEquivalent = "\r"
    loginButton.target = self
    loginButton.action = #selector(submitPressed)

    let buttonRow = NSStackView(views: [cancelButton, loginButton])
    buttonRow.orientation = .horizontal
    buttonRow.alignment = .centerY
    buttonRow.spacing = 10
    buttonRow.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(buttonRow)

    NSLayoutConstraint.activate([
      buttonRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
      buttonRow.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
      buttonRow.topAnchor.constraint(greaterThanOrEqualTo: cardView.bottomAnchor, constant: 16),
      buttonRow.topAnchor.constraint(greaterThanOrEqualTo: busyView.bottomAnchor, constant: 16),
    ])
  }

  private func makeRow(title: String, control: NSView) -> NSStackView {
    let label = NSTextField(labelWithString: title)
    label.font = MacTheme.bodyFont
    label.textColor = .labelColor
    label.alignment = .right
    label.lineBreakMode = .byTruncatingTail
    label.setContentHuggingPriority(.required, for: .horizontal)
    label.setContentCompressionResistancePriority(.required, for: .horizontal)
    label.widthAnchor.constraint(equalToConstant: 92).isActive = true

    control.setContentHuggingPriority(.defaultLow, for: .horizontal)
    control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    let row = NSStackView(views: [label, control])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 10
    row.translatesAutoresizingMaskIntoConstraints = false
    return row
  }

  private func configureInputField(
    _ field: NSTextField,
    placeholder: String,
    contentType: NSTextContentType
  ) {
    field.font = MacTheme.bodyFont
    field.placeholderString = placeholder
    field.usesSingleLineMode = true
    field.lineBreakMode = .byTruncatingTail
    field.contentType = contentType
    field.delegate = self
    // Return submits the form. The action is sent after the field editor committed its
    // text, so `stringValue` is guaranteed to contain the last typed character.
    field.target = self
    field.action = #selector(submitPressed)
  }

  // MARK: - Form state

  @objc
  private func sourceTypeChanged() {
    guard sourceTypes.indices.contains(sourcePopup.indexOfSelectedItem) else { return }
    selectedApiType = sourceTypes[sourcePopup.indexOfSelectedItem]
    updateFormVisibility()
    if selectedApiType == .local {
      view.window?.makeFirstResponder(chooseFolderButton)
    } else {
      view.window?.makeFirstResponder(serverUrlField)
    }
  }

  private func updateFormVisibility() {
    let isLocal = selectedApiType == .local
    serverUrlRow?.isHidden = isLocal
    usernameRow?.isHidden = isLocal
    passwordRow?.isHidden = isLocal
    folderRow?.isHidden = !isLocal

    if isLocal {
      let path = localFolderURL?.path
      folderPathLabel.stringValue = path ?? L10n.tr("No music folder selected.")
      folderPathLabel.toolTip = path
    }
  }

  private func prefillCredentialsIfNeeded() {
    let accounts = storage.settings.accounts
    guard let credentials = accounts.getSetting(nil).read.loginCredentials else { return }
    // Like the Catalyst login: prefill only for the first account or for a second account
    // of the same source type, so a local folder path never leaks into the WebDAV form.
    guard accounts.allAccounts.isEmpty || credentials.backendApi == selectedApiType else {
      return
    }

    if accounts.allAccounts.isEmpty,
       credentials.backendApi == .webdav || credentials.backendApi == .local {
      selectedApiType = credentials.backendApi
      if let index = sourceTypes.firstIndex(of: selectedApiType) {
        sourcePopup.selectItem(at: index)
      }
      updateFormVisibility()
    }

    guard credentials.backendApi != .local else { return }
    serverUrlField.stringValue = credentials.serverUrl
    usernameField.stringValue = credentials.username
    prefilledHTTPHeaders = credentials.httpHeaders
  }

  // MARK: - Login

  @objc
  private func chooseFolderPressed() {
    chooseLocalFolder(autoLogin: false)
  }

  @objc
  private func submitPressed() {
    guard !isBusy else { return }
    startLogin()
  }

  @objc
  private func cancelPressed() {
    if isBusy {
      loginTask?.cancel()
      // While the initial sync is running the cancellation means "Skip Sync": the account
      // stays signed in and the window closes when the service restored the app state.
      if hasPersistedAccount {
        return
      }
    }
    onCancel?()
  }

  private func startLogin() {
    let apiType = selectedApiType
    guard let credentials = makeCredentials(for: apiType) else { return }

    let accountInfo = Account.createInfo(credentials: credentials)
    guard !storage.settings.accounts.allAccounts.contains(accountInfo) else {
      showError(message: L10n.tr("Account already added!"))
      return
    }

    beginBusy()
    loginTask?.cancel()
    loginTask = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.performLogin(credentials: credentials, apiType: apiType)
    }
  }

  private func makeCredentials(for apiType: BackenApiType) -> LoginCredentials? {
    if apiType == .local {
      guard let url = localFolderURL, let bookmark = localFolderBookmark else {
        // Catalyst parity: pressing Login without a folder opens the folder picker and
        // starts the login right after the user selected one.
        chooseLocalFolder(autoLogin: true)
        return nil
      }
      var credentials = LoginCredentials(
        serverUrl: url.path,
        username: "Local",
        password: ""
      )
      credentials.backendApi = .local
      credentials.localFolderBookmark = bookmark
      credentials.localFolderPath = url.path
      return credentials
    }

    let serverUrl = serverUrlField.stringValue
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !serverUrl.isEmpty else {
      showError(message: L10n.tr("No server URL given!"))
      return nil
    }
    guard serverUrl.hasHTTPProtocolPrefix else {
      showError(
        message: L10n
          .tr("Please provide either 'https://' or 'http://' in your server URL.")
      )
      return nil
    }
    let username = usernameField.stringValue
    guard !username.isEmpty else {
      showError(message: L10n.tr("No username given!"))
      return nil
    }
    let password = passwordField.stringValue
    guard !password.isEmpty else {
      showError(message: L10n.tr("No password given!"))
      return nil
    }

    var credentials = LoginCredentials(
      serverUrl: serverUrl,
      username: username,
      password: password
    )
    credentials.httpHeaders = prefilledHTTPHeaders
    return credentials
  }

  private func performLogin(credentials: LoginCredentials, apiType: BackenApiType) async {
    var credentials = credentials
    let initialAccountInfo = Account.createInfo(credentials: credentials)
    var accountInfo = initialAccountInfo
    let meta = fmusic.getMeta(initialAccountInfo)

    do {
      // Step 1: authenticate with the selected backend (WebDAV or local folder). This is
      // exactly the call the Catalyst login uses; it also activates the folder bookmark.
      let authenticatedApiType = try await meta.backendApi.login(
        apiType: apiType,
        credentials: credentials
      )
      try Task.checkCancellation()

      // Step 2: persist the account the same way the Catalyst login does.
      credentials.backendApi = authenticatedApiType
      accountInfo = Account.createInfo(credentials: credentials)
      meta.backendApi.selectedApi = authenticatedApiType
      meta.account.assignInfo(info: accountInfo)
      storage.main.saveContext()
      storage.settings.accounts.login(credentials)
      meta.backendApi.provideCredentials(credentials: credentials)
      hasPersistedAccount = true

      // The account switcher / sidebar footer and the account settings listen to these.
      fmusic.notificationHandler.post(name: .accountAdded, object: nil, userInfo: nil)
      fmusic.notificationHandler.post(name: .accountActiveChanged, object: nil, userInfo: nil)
    } catch {
      fmusic.resetMeta(initialAccountInfo)
      handleLoginFailure(error)
      return
    }

    // Step 3: initial full library sync with progress (reused from the shared core).
    await runInitialSync(accountInfo: accountInfo)
  }

  private func runInitialSync(accountInfo: AccountInfo) async {
    beginSyncProgress()
    do {
      try await resyncService.resyncLibrary(accountInfo: accountInfo) { [weak self] progress in
        self?.updateSyncProgress(progress)
      }
      finishLogin()
    } catch is CancellationError {
      // "Skip Sync" or the window was closed: the account stays signed in and the indexer
      // finishes in the background, so the library still populates from
      // `.librarySongsSynced`.
      finishLogin()
    } catch {
      // Authentication succeeded and the account is signed in; only the indexer failed.
      // `LibraryResyncService` already logged the error with `EventLogger`; the library can
      // be resynced later from the account settings.
      endBusy()
      presentSyncFailedAlert(error)
    }
  }

  private func finishLogin() {
    guard !didFinish else { return }
    didFinish = true
    loginTask = nil
    // The library lists reload from `.librarySongsSynced`; this also updates the sidebar
    // footer and the title independent of whether the indexer already finished.
    fmusic.notificationHandler.post(name: .accountActiveChanged, object: nil, userInfo: nil)
    DispatchQueue.main.async { [weak self] in
      self?.onLoginFinished?()
    }
  }

  // MARK: - Failure handling

  private func handleLoginFailure(_ error: Error) {
    endBusy()
    guard !(error is CancellationError), !Task.isCancelled else { return }
    showError(message: Self.localizedLoginErrorMessage(for: error))
  }

  private static func localizedLoginErrorMessage(for error: Error) -> String {
    if let localizedError = error as? LocalizedError,
       let description = localizedError.errorDescription,
       !description.isEmpty {
      return description
    }
    return L10n.tr("Not able to login!")
  }

  private func presentSyncFailedAlert(_ error: Error) {
    guard let window = view.window else {
      finishLogin()
      return
    }
    let alert = NSAlert()
    alert.messageText = L10n.tr("Initial Sync")
    alert.informativeText = error.localizedDescription
    alert.alertStyle = .warning
    alert.addButton(withTitle: L10n.tr("OK"))
    alert.beginSheetModal(for: window) { [weak self] _ in
      self?.finishLogin()
    }
  }

  private func showError(message: String) {
    guard let window = view.window else { return }
    let alert = NSAlert()
    alert.messageText = L10n.tr("Login failed")
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.addButton(withTitle: L10n.tr("OK"))
    alert.beginSheetModal(for: window) { [weak self] _ in
      guard let self else { return }
      DispatchQueue.main.async {
        self.view.window?.makeFirstResponder(self.passwordField)
      }
    }
  }

  // MARK: - Local folder

  private func chooseLocalFolder(autoLogin: Bool) {
    guard let window = view.window else { return }
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false
    panel.directoryURL = localFolderURL
    panel.beginSheetModal(for: window) { [weak self] response in
      guard let self, response == .OK, let url = panel.url else { return }
      self.setLocalFolder(url)
      if autoLogin {
        self.startLogin()
      }
    }
  }

  private func setLocalFolder(_ url: URL) {
    do {
      let bookmark = try LocalFolderAccess.createBookmark(for: url)
      localFolderURL = url
      localFolderBookmark = bookmark
      updateFormVisibility()
    } catch {
      showError(message: error.localizedDescription)
    }
  }

  // MARK: - Busy state / progress

  private func beginBusy() {
    isBusy = true
    cardView.isHidden = true
    busyView.isHidden = false
    loginButton.isHidden = true
    cancelButton.title = L10n.tr("Cancel")
    cancelButton.isEnabled = true
    busyTitleLabel.stringValue = L10n.tr("Login")
    busyStatusLabel.stringValue = ""
    busyDetailLabel.stringValue = ""
    progressIndicator.isIndeterminate = true
    progressIndicator.doubleValue = 0
    progressIndicator.startAnimation(nil)
    view.window?.makeFirstResponder(nil)
  }

  private func beginSyncProgress() {
    busyTitleLabel.stringValue = L10n.tr("Initial Sync")
    busyStatusLabel.stringValue = L10n.tr("Initial Sync")
    busyDetailLabel.stringValue = ""
    progressIndicator.isIndeterminate = true
    progressIndicator.startAnimation(nil)
    cancelButton.title = L10n.tr("Skip Sync")
    cancelButton.isEnabled = true
  }

  private func endBusy() {
    isBusy = false
    cardView.isHidden = false
    busyView.isHidden = true
    loginButton.isHidden = false
    cancelButton.title = L10n.tr("Cancel")
    cancelButton.isEnabled = true
    progressIndicator.stopAnimation(nil)
    progressIndicator.isIndeterminate = true
    progressIndicator.doubleValue = 0
  }

  private func updateSyncProgress(_ progress: LibrarySyncProgress) {
    switch progress.phase {
    case .preparing:
      busyStatusLabel.stringValue = L10n.tr("Initial Sync")
    case .artist:
      busyStatusLabel.stringValue = L10n.tr("Syncing artists ...")
    case .album:
      busyStatusLabel.stringValue = L10n.tr("Syncing albums ...")
    case .song:
      busyStatusLabel.stringValue = L10n.tr("Syncing songs ...")
    case .playlist:
      busyStatusLabel.stringValue = L10n.tr("Syncing playlists ...")
    case .genre:
      busyStatusLabel.stringValue = L10n.tr("Syncing genres ...")
    case .podcast:
      busyStatusLabel.stringValue = L10n.tr("Syncing podcasts ...")
    case .cache:
      busyStatusLabel.stringValue = L10n.tr("Applying cache ...")
    case .finished:
      busyStatusLabel.stringValue = L10n.tr("Done")
      cancelButton.isEnabled = false
    }

    if let fraction = progress.fractionCompleted {
      progressIndicator.stopAnimation(nil)
      progressIndicator.isIndeterminate = false
      progressIndicator.doubleValue = fraction
      busyDetailLabel.stringValue = String(
        format: "%d / %d",
        progress.parsedObjectCount,
        progress.totalCount
      )
    } else {
      progressIndicator.isIndeterminate = true
      progressIndicator.startAnimation(nil)
      busyDetailLabel.stringValue = ""
    }
  }

  /// Cancels a running authentication or initial sync. Called by the window controller when
  /// the window closes; safe to call multiple times.
  func cancelPendingWork() {
    loginTask?.cancel()
    loginTask = nil
  }
}

// MARK: - NSTextFieldDelegate

extension LoginViewController: NSTextFieldDelegate {
  func control(
    _ control: NSControl,
    textView: NSTextView,
    doCommandBy commandSelector: Selector
  ) -> Bool {
    // Esc cancels the window (or skips a running sync) even while a text field is edited;
    // the field editor would otherwise swallow the first Esc to end editing.
    if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
      cancelPressed()
      return true
    }
    return false
  }
}

// MARK: - String

private extension String {
  var hasHTTPProtocolPrefix: Bool {
    hasPrefix("https://") || hasPrefix("http://")
  }
}

// MARK: - LoginCardView

/// Rounded card that hosts the form / progress content. Paints a dynamic background and a
/// hairline border like the settings cards, re-resolving the colours on appearance changes.
@MainActor
private final class LoginCardView: NSView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
  }

  required init?(coder: NSCoder) {
    nil
  }

  override var wantsUpdateLayer: Bool { true }

  override func updateLayer() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
      layer?.borderColor = NSColor.separatorColor.cgColor
    }
    layer?.cornerRadius = 10
    layer?.borderWidth = 1
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }
}
