//
//  WelcomePopupPresenter.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 31.07.25.
//  Copyright (c) 2025 Maximilian Bauer. All rights reserved.
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
import Foundation

@MainActor
class WelcomePopupPresenter: NSObject {
  func displayInfoPopupsIfNeeded() {
    if !appDelegate.storage.settings.app.isLibrarySyncInfoReadByUser {
      displaySyncInfo()
    }
  }

  private func displaySyncInfo() {
    let popupVC = AppStoryboard.Main.segueToLibrarySyncPopup()
    popupVC.setContent(
      topic: L10n.tr("Synchronization"),
      detailMessage: L10n.tr("Your music library is read directly from the selected folder or WebDAV server. Use \"Resync Library\" in the account settings to pick up added or removed files."),
      customIcon: .refresh,
      customAnimation: .rotate,
      onClosePressed: { _ in
        self.appDelegate.storage.settings.app.isLibrarySyncInfoReadByUser = true
      }
    )
    appDelegate.display(popup: popupVC)
  }
}
