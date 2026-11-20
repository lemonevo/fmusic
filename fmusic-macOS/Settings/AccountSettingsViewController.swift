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

/// 账户: read-only information about the active account.
///
/// Destructive actions (logout, resync) are intentionally not implemented yet; they are
/// shown disabled so the window matches the Catalyst app's structure without touching
/// the user's account data.
@MainActor
final class AccountSettingsViewController: SettingsPageViewController {
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

    addButton(title: L10n.tr("Logout"), isEnabled: false) {}
    addButton(title: L10n.tr("Resync Library"), isEnabled: false) {}
    addFootnote(L10n.tr("Requested functionality is not supported."))
  }
}
