//
//  SettingsSceneDelegate.swift
//  fmusic
//
//  Created by David Klopp on 14.08.24.
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
import OSLog
import UIKit

// MARK: - SettingsSceneDelegate

/// Settings live in their own window scene (like Apple Music's Preferences): a
/// separate, smaller window that floats above the main window instead of covering
/// the main window's content. `AppDelegate.showSettings()` opens or raises it.
class SettingsSceneDelegate: UIResponder, UIWindowSceneDelegate {
  public lazy var log = {
    FmusicKit.shared.log
  }()

  var window: UIWindow?
  private var settingsVC: SettingsHostVC?

  #if targetEnvironment(macCatalyst)
    /// A window noticeably smaller than the main window (min 980×540).
    static let preferredWindowSize = CGSize(width: 900, height: 620)
  #endif

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    os_log("Settings scene: willConnectTo", log: self.log, type: .info)
    guard let windowScene = scene as? UIWindowScene else { return }

    window = UIWindow(windowScene: windowScene)
    appDelegate.applyTextSize()
    // Settings follow the in-app appearance choice, not the system one.
    window?.overrideUserInterfaceStyle = appDelegate.storage.settings.user.appearanceMode
      .uiUserInterfaceStyle
    window?.backgroundColor = .clear

    let settingsVC = SettingsHostVC(showsSidebar: true)
    settingsVC.onRequestClose = { [weak self] in self?.closeSettingsScene() }
    self.settingsVC = settingsVC
    window?.rootViewController = settingsVC

    #if targetEnvironment(macCatalyst)
      windowScene.title = windowSettingsTitle
      Self.applyPreferredSize(to: windowScene)
    #endif

    window?.makeKeyAndVisible()
  }

  #if targetEnvironment(macCatalyst)
    private static func applyPreferredSize(to windowScene: UIWindowScene) {
      windowScene.sizeRestrictions?.minimumSize = CGSize(width: 760, height: 520)
      windowScene.sizeRestrictions?.maximumSize = CGSize(width: 1200, height: 900)
      let size = preferredWindowSize

      // Centre the settings window over the main window; fall back to the screen
      // centre when no main window is open (so it never lands in a corner).
      let anchor: CGRect
      if let main = AppDelegate.settingsAnchorFrame {
        anchor = main
      } else {
        let bounds = windowScene.screen.bounds
        anchor = CGRect(x: bounds.midX, y: bounds.midY, width: 0, height: 0)
      }
      let target = CGRect(
        x: anchor.midX - size.width / 2,
        y: anchor.midY - size.height / 2,
        width: size.width,
        height: size.height
      )
      windowScene.requestGeometryUpdate(.Mac(systemFrame: target)) { error in
        os_log(
          "Settings window size request failed: %s",
          type: .info,
          error.localizedDescription
        )
      }
    }
  #endif

  /// Close the settings window by destroying its scene. Hiding it instead does
  /// not survive on Catalyst (the scene disconnects and leaves an empty window),
  /// so we tear it down cleanly; re-opening builds a fresh one.
  private func closeSettingsScene() {
    #if targetEnvironment(macCatalyst)
      if let scene = window?.windowScene {
        UIApplication.shared.requestSceneSessionDestruction(
          scene.session,
          options: nil,
          errorHandler: nil
        )
        return
      }
    #endif
    window?.isHidden = true
  }

  func sceneDidDisconnect(_ scene: UIScene) {
    os_log("Settings scene: didDisconnect", log: self.log, type: .info)
    appDelegate.rebuildMainMenu()
  }

  func sceneDidBecomeActive(_ scene: UIScene) {
    os_log("Settings scene: didBecomeActive", log: self.log, type: .info)
    // Keep the settings window as the key window so Esc / Cmd+W act on it.
    window?.makeKeyAndVisible()
  }

  func sceneWillResignActive(_ scene: UIScene) {}
  func sceneWillEnterForeground(_ scene: UIScene) {}
  func sceneDidEnterBackground(_ scene: UIScene) {}

  // MARK: State restoration

  func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? { nil }

  func scene(
    _ scene: UIScene,
    restoreInteractionStateWith stateRestorationActivity: NSUserActivity
  ) {}
}
