//
//  LoginWindowController.swift
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

/// Standalone window for the login / add-account flow of the pure AppKit app.
///
/// The window hosts `LoginViewController`, which owns the complete flow (form,
/// authentication through the shared core, initial library sync through
/// `LibraryResyncService`, notifications and errors). This controller only creates the
/// window, reuses it while it is open and releases it when it closes.
///
/// Wiring for the Lead (no other file has to be touched to build this):
///
/// ```swift
/// // AppDelegate — launch: no account signed in yet (fresh install / last account logged out)
/// if storage.settings.accounts.active == nil {
///   LoginWindowController.presentLogin()
/// }
///
/// // AppDelegate — menu action "Add Account"
/// @objc func addAccount(_ sender: Any?) {
///   LoginWindowController.presentLogin()
/// }
/// ```
///
/// Populates the library without extra wiring: the controller posts
/// `.accountAdded` / `.accountActiveChanged` and `LibraryResyncService` posts
/// `.librarySongsSynced`, so the sidebar footer, the song list and the home page reload by
/// themselves.
@MainActor
final class LoginWindowController: NSWindowController, NSWindowDelegate {
  private static var shared: LoginWindowController?

  private let loginViewController: LoginViewController

  // MARK: - Presentation

  /// Shows the login window (or brings the already open one to the front).
  static func presentLogin() {
    let controller = shared ?? LoginWindowController()
    shared = controller
    controller.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
    controller.window?.makeKeyAndOrderFront(nil)
  }

  /// Alias used by the "Add Account" menu action; same window as `presentLogin()`.
  static func presentAddAccount() {
    presentLogin()
  }

  /// Shows the login window only when no account is signed in. Returns whether it was
  /// presented. Intended for app launch and after the last account was logged out.
  @discardableResult
  static func presentLoginIfNeeded() -> Bool {
    guard FmusicKit.shared.storage.settings.accounts.active == nil else { return false }
    presentLogin()
    return true
  }

  // MARK: - Init

  init() {
    let accounts = FmusicKit.shared.storage.settings.accounts
    let viewController = LoginViewController()

    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: LoginViewController.windowSize),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = accounts.allAccounts.isEmpty
      ? L10n.tr("Login")
      : L10n.tr("Add Account")
    window.isReleasedWhenClosed = false
    window.tabbingMode = .disallowed
    window.contentViewController = viewController
    window.center()

    loginViewController = viewController
    super.init(window: window)
    window.delegate = self

    viewController.onCancel = { [weak self] in
      self?.closeLoginWindow()
    }
    viewController.onLoginFinished = { [weak self] in
      self?.closeLoginWindow()
    }
  }

  required init?(coder: NSCoder) {
    nil
  }

  // MARK: - Closing

  private func closeLoginWindow() {
    guard let window else { return }
    window.performClose(nil)
  }

  func windowWillClose(_ notification: Notification) {
    // Abort a running authentication or initial sync. Cancelling the sync is safe: it
    // mirrors the Catalyst "Skip Sync" (the account stays signed in, the indexer finishes
    // in the background and the library populates through `.librarySongsSynced`).
    loginViewController.cancelPendingWork()
    loginViewController.onCancel = nil
    loginViewController.onLoginFinished = nil
    if Self.shared === self {
      Self.shared = nil
    }
  }
}
