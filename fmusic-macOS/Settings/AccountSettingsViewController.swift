//
//  AccountSettingsViewController.swift
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

/// 账户: information about the active account plus the two destructive account actions.
///
/// Both actions are shared with the Catalyst app through `LibraryResyncService`, so the
/// AppKit app does not reimplement any of the sync/logout logic:
/// - Resync runs the backend's full indexer behind a modal progress sheet. It keeps the
///   library, the downloaded songs and the playback data; only library metadata is refreshed.
/// - Logout removes the account's login credentials and its downloaded files and returns the
///   app to the "not logged in" state.
@MainActor
final class AccountSettingsViewController: SettingsPageViewController {
  private let service = LibraryResyncService()
  private var resyncTask: Task<Void, Never>?
  private var resyncProgressViewController: LibraryResyncProgressViewController?

  init() {
    super.init(title: L10n.tr("Account"))
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func buildForm() {
    let storage = SettingsStore.storage
    let accountInfo = storage.settings.accounts.active
    let credentials = storage.settings.accounts.getSetting(accountInfo).read.loginCredentials

    guard let credentials else {
      addSection(rows: [makeTextRow(L10n.tr("You aren't logged in yet."))])
      return
    }

    let usernameRow = makeValueRow(title: L10n.tr("Username"), value: credentials.username)
    let serverRow = makeValueRow(title: L10n.tr("URL"), value: credentials.displayServerUrl)
    let apiRow = makeValueRow(
      title: L10n.tr("Backend API"),
      value: L10n.tr(credentials.backendApi.description)
    )
    addSection(header: L10n.tr("Account"), rows: [usernameRow, serverRow, apiRow])

    // Deliberately placed after the information rows: resyncing keeps the account and the
    // downloaded files, logging out removes them, so Logout is the last (destructive) action.
    addButton(title: L10n.tr("Resync Library")) { [weak self] in
      self?.confirmResync()
    }
    addButton(title: L10n.tr("Logout")) { [weak self] in
      self?.confirmLogout()
    }
  }

  // MARK: - Alerts

  private func present(
    _ alert: NSAlert,
    completion: @escaping (NSApplication.ModalResponse) -> Void
  ) {
    guard let window = view.window else {
      completion(alert.runModal())
      return
    }
    alert.beginSheetModal(for: window, completionHandler: completion)
  }

  // MARK: - Resync

  private func confirmResync() {
    guard let accountInfo = SettingsStore.activeAccount else { return }

    let alert = NSAlert()
    alert.messageText = L10n.tr("Resync Library")
    alert.informativeText = L10n.tr(
      "This will rescan your music source and pick up added, changed, or removed files. Unchanged files are skipped, and your downloads and playback data stay on this device.\n\nDo you want to resync your library?"
    )
    alert.alertStyle = .warning
    alert.addButton(withTitle: L10n.tr("Resync"))
    alert.addButton(withTitle: L10n.tr("Cancel"))

    present(alert) { [weak self] response in
      guard response == .alertFirstButtonReturn else { return }
      // Start after the confirmation sheet finished its dismissal animation so the
      // progress sheet can be attached without a sheet transition conflict.
      DispatchQueue.main.async {
        self?.startResync(accountInfo: accountInfo)
      }
    }
  }

  private func startResync(accountInfo: AccountInfo) {
    guard resyncTask == nil else { return }

    let progressViewController = LibraryResyncProgressViewController()
    progressViewController.onCancel = { [weak self] in
      // Cancelling is safe: `LibraryResyncService` restarts the background managers before
      // it returns and lets the indexer finish in the background (like the Catalyst app's
      // "Skip Sync"), so no library, download or playback data is affected.
      self?.resyncTask?.cancel()
    }
    resyncProgressViewController = progressViewController
    presentAsSheet(progressViewController)

    let service = service
    resyncTask = Task { @MainActor [weak self] in
      let result: Result<Void, Error>
      do {
        try await service.resyncLibrary(accountInfo: accountInfo) { [weak self] progress in
          self?.resyncProgressViewController?.update(progress)
        }
        result = .success(())
      } catch {
        result = .failure(error)
      }
      self?.resyncDidFinish(result)
    }
  }

  private func resyncDidFinish(_ result: Result<Void, Error>) {
    resyncTask = nil

    if let progressViewController = resyncProgressViewController {
      resyncProgressViewController = nil
      if progressViewController.presentingViewController != nil {
        dismiss(progressViewController)
      }
    }

    // The library lists in the main window reload from the
    // `.librarySongsSynced` notification the service posts.
    reloadForm()

    switch result {
    case .success:
      break
    case .failure(let error):
      // A cancelled resync is not an error: the service restored the app state already.
      guard !(error is CancellationError) else { return }
      // Wait for the sheet dismissal before presenting the error as another sheet.
      DispatchQueue.main.async { [weak self] in
        self?.presentResyncError(error)
      }
    }
  }

  private func presentResyncError(_ error: Error) {
    let alert = NSAlert()
    alert.messageText = L10n.tr("Resync Library")
    alert.informativeText = error.localizedDescription
    alert.alertStyle = .warning
    alert.addButton(withTitle: L10n.tr("OK"))
    present(alert) { _ in }
  }

  // MARK: - Logout

  private func confirmLogout() {
    guard let accountInfo = SettingsStore.activeAccount else { return }

    let alert = NSAlert()
    alert.messageText = L10n.tr("Logout")
    alert.informativeText = L10n.tr(
      "Logging out will sign you out of the current account. Your login credentials will be removed, and all downloaded files for this account will be deleted.\n\nDo you want to log out?"
    )
    alert.alertStyle = .critical
    alert.addButton(withTitle: L10n.tr("Logout"))
    alert.addButton(withTitle: L10n.tr("Cancel"))

    present(alert) { [weak self] response in
      guard response == .alertFirstButtonReturn else { return }
      self?.performLogout(accountInfo: accountInfo)
    }
  }

  private func performLogout(accountInfo: AccountInfo) {
    // Removes the credentials and the account's downloaded/cached files, stops the
    // background managers, detaches the player and posts `.accountActiveChanged` /
    // `.accountDeleted`, so the main window (song list, sidebar footer) updates itself.
    service.logout(accountInfo: accountInfo)
    // The page now has to show the "not logged in" state.
    reloadForm()
  }
}
