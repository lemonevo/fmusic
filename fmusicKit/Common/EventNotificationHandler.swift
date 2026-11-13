//
//  EventNotificationHandler.swift
//  fmusicKit
//
//  Created by Maximilian Bauer on 12.02.22.
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

import Foundation

extension Notification.Name {
  public static let accountActiveChanged = Notification
    .Name(rawValue: "de.fmusic.account.active.changed")
  public static let accountAdded = Notification
    .Name(rawValue: "de.fmusic.account.added")
  public static let accountDeleted = Notification
    .Name(rawValue: "de.fmusic.account.deleted")
  public static let downloadFinishedSuccess = Notification
    .Name(rawValue: "de.fmusic.download.finished.success")
  public static let playerPlay = Notification.Name(rawValue: "de.fmusic.player.play")
  public static let playerPause = Notification.Name(rawValue: "de.fmusic.player.pause")
  public static let playerStop = Notification.Name(rawValue: "de.fmusic.player.stop")
  public static let fetchControllerSortChanged = Notification
    .Name(rawValue: "de.fmusic.fetchController.sort.change")
  public static let offlineModeChanged = Notification
    .Name(rawValue: "de.fmusic.settings.offline-mode")
  public static let autoCollapseToolbarPlayerChanged = Notification
    .Name(rawValue: "de.fmusic.settings.auto-collapse-toolbar-changed")
  public static let networkStatusChanged = Notification
    .Name(rawValue: "de.fmusic.settings.network.status.changed")
  // posted by the background library sync after its newest elements step and at its natural end
  public static let librarySongsSynced = Notification
    .Name(rawValue: "de.fmusic.library.songs.synced")
  // posted when the manual lyrics offset changes so visible lyrics re-render while paused
  public static let lyricsOffsetChanged = Notification
    .Name(rawValue: "de.fmusic.lyrics.offset.changed")
}

// MARK: - DownloadNotification

public struct DownloadNotification {
  public let id: String

  public var asNotificationUserInfo: [String: Any] {
    ["downloadId": id]
  }

  public static func fromNotification(_ notification: Notification) -> DownloadNotification? {
    guard let userInfo = notification.userInfo as? [String: Any],
          let downloadId = userInfo["downloadId"] as? String
    else { return nil }
    return DownloadNotification(id: downloadId)
  }
}

// MARK: - EventNotificationHandler

final public class EventNotificationHandler: Sendable {
  @MainActor
  public func register(
    _ observer: Any,
    selector aSelector: Selector,
    name aName: NSNotification.Name,
    object anObject: Any?
  ) {
    NotificationCenter.default.addObserver(
      observer,
      selector: aSelector,
      name: aName,
      object: anObject
    )
  }

  @MainActor
  public func remove(
    _ observer: Any,
    name aName: NSNotification.Name,
    object anObject: Any?
  ) {
    NotificationCenter.default.removeObserver(observer, name: aName, object: anObject)
  }

  @MainActor
  public func post(
    name aName: NSNotification.Name,
    object anObject: Any?,
    userInfo: [AnyHashable: Any]?
  ) {
    NotificationCenter.default.post(name: aName, object: anObject, userInfo: userInfo)
  }
}
