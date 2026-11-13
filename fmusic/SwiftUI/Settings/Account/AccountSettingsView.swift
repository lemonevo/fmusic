//
//  AccountSettingsView.swift
//  fmusic
//
//  Created by Maximilian Bauer on 14.09.22.
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
import SwiftUI

// MARK: - AccountSettingsView

struct AccountSettingsView: View {
  enum Destination: Hashable {
    case serverURLs
    case customHTTPHeaders
  }

  let splitPercentage = 0.25

  @State
  var isPwUpdateDialogVisible = false
  @State
  var isShowLogoutAlert = false
  @State
  var isShowResyncLibraryAlert = false
  @EnvironmentObject
  var settings: Settings

  private var activeBackendApi: BackenApiType? {
    guard let activeAccountInfo = settings.activeAccountInfo else { return nil }
    return appDelegate.storage.settings.accounts.getSetting(activeAccountInfo).read
      .loginCredentials?.backendApi
  }

  func setThemePreference(preference: ThemePreference) {
    settings.themePreference = preference
    appDelegate.setAppTheme(color: preference.asColor)
    appDelegate.applyAppThemeToAlreadyLoadedViews()
  }

  private func resyncLibrary(accountInfo: AccountInfo) {
    appDelegate.closeAllButActiveMainTabs()
    if appDelegate.storage.settings.accounts.allAccounts.count <= 1 {
      appDelegate.stopForInit()
    }

    let meta = appDelegate.getMeta(accountInfo)
    meta.stopManager()
    appDelegate.resetMeta(accountInfo)

    // reset quick actions
    appDelegate.quickActionsManager.configureQuickActions()
    appDelegate.configureMainMenu()

    appDelegate.storage.settings.user.isOfflineMode = false
    let account = appDelegate.storage.main.library.getAccount(info: accountInfo)
    appDelegate.player.logout(account: account)
    let syncVC = AppStoryboard.Main.segueToSync(account: account)
    syncVC.modalPresentationStyle = .formSheet
    AppDelegate.mainSceneDelegate?.window?.rootViewController?.dismiss(animated: false)
    AppDelegate.mainSceneDelegate?.window?.rootViewController?.present(syncVC, animated: true)
  }

  private func httpHeaders(accountInfo: AccountInfo) -> [String: String] {
    appDelegate.storage.settings.accounts.getSetting(accountInfo).read
      .loginCredentials?.httpHeaders ?? [:]
  }

  private func saveHTTPHeaders(_ headers: [String: String], accountInfo: AccountInfo) {
    appDelegate.storage.settings.accounts
      .updateSetting(accountInfo) { accountSettings in
        accountSettings.loginCredentials?.httpHeaders = headers
      }
    if let updatedCredentials = appDelegate.storage.settings.accounts
      .getSetting(accountInfo).read.loginCredentials {
      appDelegate.getMeta(accountInfo).backendApi
        .provideCredentials(credentials: updatedCredentials)
    }
  }

  private func logout(accountInfo: AccountInfo) {
    appDelegate.removeAccount(accountInfo: accountInfo)
  }

  var body: some View {
    ZStack {
      SettingsList {
        if let activeAccountInfo = settings.activeAccountInfo {
          SettingsSection {
            SettingsRow(title: "URL", orientation: .vertical, splitPercentage: splitPercentage) {
              SecondaryText(
                appDelegate.storage.settings.accounts.getSetting(settings.activeAccountInfo).read
                  .loginCredentials?.displayServerUrl ?? ""
              )
            }
            SettingsRow(
              title: L10n.tr("Username"),
              orientation: .vertical,
              splitPercentage: splitPercentage
            ) {
              SecondaryText(
                appDelegate.storage.settings.accounts.getSetting(settings.activeAccountInfo).read
                  .loginCredentials?.username ?? ""
              )
            }
          }

          SettingsSection {
            SettingsRow(title: L10n.tr("Theme Color")) {
              Menu(L10n.tr(settings.themePreference.description)) {
                Button(L10n.tr(ThemePreference.blue.description)) {
                  setThemePreference(preference: .blue)
                }
                Button(L10n.tr(ThemePreference.green.description)) {
                  setThemePreference(preference: .green)
                }
                Button(L10n.tr(ThemePreference.red.description)) {
                  setThemePreference(preference: .red)
                }
                Button(L10n.tr(ThemePreference.yellow.description)) {
                  setThemePreference(preference: .yellow)
                }
                Button(L10n.tr(ThemePreference.orange.description)) {
                  setThemePreference(preference: .orange)
                }
                Button(L10n.tr(ThemePreference.purple.description)) {
                  setThemePreference(preference: .purple)
                }
              }
            }
          }

          SettingsSection(content: {
            SettingsCheckBoxRow(
              title: L10n.tr("Newest Songs"),
              isOn: $settings.isAutoCacheLatestSongs
            )
          }, header: L10n.tr("Auto Cache"))

          SettingsSection {
            SettingsRow(title: L10n.tr("Backend API"), splitPercentage: splitPercentage) {
              Text(
                L10n.tr(
                  appDelegate.storage.settings.accounts
                    .getSetting(settings.activeAccountInfo).read
                    .loginCredentials?.backendApi.description ?? ""
                )
              )
              .foregroundColor(.secondary)
              .help(
                L10n.tr(
                  appDelegate.storage.settings.accounts
                    .getSetting(settings.activeAccountInfo).read
                    .loginCredentials?.backendApi.description ?? ""
                )
              )
            }

            SettingsRow(title: L10n.tr("Server API Version"), splitPercentage: splitPercentage) {
              Text(appDelegate.getMeta(activeAccountInfo).backendApi.serverApiVersion)
                .foregroundColor(.secondary)
                .help(appDelegate.getMeta(activeAccountInfo).backendApi.serverApiVersion)
            }
            SettingsRow(title: L10n.tr("Client API Version"), splitPercentage: splitPercentage) {
              Text(appDelegate.getMeta(activeAccountInfo).backendApi.clientApiVersion)
                .foregroundColor(.secondary)
                .help(appDelegate.getMeta(activeAccountInfo).backendApi.clientApiVersion)
            }
          }

          SettingsSection {
            NavigationLink(value: Destination.serverURLs) {
              Text(L10n.tr("Manage Server URLs"))
            }
            NavigationLink(value: Destination.customHTTPHeaders) {
              Text(L10n.tr("Custom HTTP Headers"))
            }
          }

          SettingsSection {
            if activeBackendApi != .local {
              SettingsButtonRow(title: L10n.tr("Update Password")) {
                withPopupAnimation { isPwUpdateDialogVisible = true }
              }
            }
            SettingsButtonRow(title: L10n.tr("Resync Library")) {
              isShowResyncLibraryAlert = true
            }.alert(isPresented: $isShowResyncLibraryAlert) {
              Alert(
                title: Text(L10n.tr("Resync Library")),
                message: Text(
                  L10n.tr(
                    "This will rescan your music source and pick up added, changed, or removed files. Unchanged files are skipped, and your downloads and playback data stay on this device.\n\nDo you want to resync your library?"
                  )
                ),
                primaryButton: .destructive(Text(L10n.tr("Resync"))) {
                  resyncLibrary(accountInfo: activeAccountInfo)
                },
                secondaryButton: .cancel()
              )
            }
          }

          SettingsSection {
            SettingsButtonRow(title: L10n.tr("Logout"), actionType: .destructive) {
              isShowLogoutAlert = true
            }
            .alert(isPresented: $isShowLogoutAlert) {
              Alert(
                title: Text(L10n.tr("Logout")),
                message: Text(
                  L10n.tr(
                    "Logging out will sign you out of the current account. Your login credentials will be removed, and all downloaded files for this account will be deleted.\n\nDo you want to log out?"
                  )
                ),
                primaryButton: .destructive(Text(L10n.tr("Logout"))) {
                  logout(accountInfo: activeAccountInfo)
                },
                secondaryButton: .cancel()
              )
            }
          }
        } else {
          // User is not logged in yet
          SettingsSection {
            SecondaryText(L10n.tr("You aren't logged in yet."))
          }
        }
      }
    }
    .navigationTitle(L10n.tr("Account"))
    .navigationBarTitleDisplayMode(.inline)
    .navigationDestination(for: Destination.self) { destination in
      switch destination {
      case .serverURLs:
        ServerURLsSettingsView()
      case .customHTTPHeaders:
        if let activeAccountInfo = settings.activeAccountInfo {
          CustomHTTPHeadersView(
            headers: httpHeaders(accountInfo: activeAccountInfo)
          ) { updated in
            saveHTTPHeaders(updated, accountInfo: activeAccountInfo)
          }
        }
      }
    }
    .sheet(isPresented: $isPwUpdateDialogVisible) {
      UpdatePasswordView(isVisible: $isPwUpdateDialogVisible)
    }
    // MacOS workaround: reading the state here makes the body depend on it. Without this, setting
    // isPwUpdateDialogVisible to false from the sheet (Cancel) does not dismiss it.
    .onChange(of: isPwUpdateDialogVisible) { _, _ in }
  }
}

// MARK: - AccountSettingsView_Previews

struct AccountSettingsView_Previews: PreviewProvider {
  static var previews: some View {
    AccountSettingsView()
  }
}
