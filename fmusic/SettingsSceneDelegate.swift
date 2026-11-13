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

/// Settings is presented inside the main window (`AppDelegate.showSettings`). Scene sessions from
/// older builds, where settings had its own window, can still be restored on launch - discard them
/// so no empty settings window appears.
class SettingsSceneDelegate: UIResponder, UIWindowSceneDelegate {
  public lazy var log = {
    FmusicKit.shared.log
  }()

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    os_log("Settings scene discarded", log: self.log, type: .info)
    UIApplication.shared.requestSceneSessionDestruction(
      session,
      options: nil,
      errorHandler: nil
    )
  }
}
