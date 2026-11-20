//
//  LibrarySettingsView.swift
//  fmusic
//
//  Created by Maximilian Bauer on 15.09.22.
//  Copyright (c) 2022 Maximilian Bauer. All rights reserved.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import Combine
import fmusicKit
import SwiftUI

// MARK: - LibrarySettingsView

struct LibrarySettingsView: View {
  @EnvironmentObject
  private var settings: Settings

  @State
  var playlistCount = 0
  @State
  var artistCount = 0
  @State
  var albumCount = 0
  @State
  var songCount = 0
  @State
  var albumWithSyncedSongsCount = 0
  @State
  var autoSyncProgressText = ""

  private func updateValues() async {
    do {
      guard let activeAccountInfo = settings.activeAccountInfo else { return }
      let accountObjectId = appDelegate.storage.main.library
        .getAccount(info: activeAccountInfo).managedObject.objectID
      let counts = try await appDelegate.storage.async.performAndGet { asyncCompanion in
        let accountAsync = asyncCompanion.library.getAccount(managedObjectId: accountObjectId)
        return (
          playlists: asyncCompanion.library.getPlaylistCount(for: accountAsync),
          artists: asyncCompanion.library.getArtistCount(for: accountAsync),
          albums: asyncCompanion.library.getAlbumCount(for: accountAsync),
          songs: asyncCompanion.library.getSongCount(for: accountAsync),
          syncedAlbums: asyncCompanion.library.getAlbumWithSyncedSongsCount(for: accountAsync)
        )
      }
      playlistCount = counts.playlists
      artistCount = counts.artists
      albumCount = counts.albums
      songCount = counts.songs
      albumWithSyncedSongsCount = counts.syncedAlbums

      if albumCount < 1 {
        autoSyncProgressText = String(format: "%.1f", 0.0) + "%"
      } else {
        let progress = Float(albumWithSyncedSongsCount) * 100.0 / Float(albumCount)
        autoSyncProgressText = String(format: "%.1f", progress) + "%"
      }
    } catch {
      // do nothing
    }
  }

  var body: some View {
    ZStack {
      SettingsList {
        SettingsSection(content: {
          SettingsRow(title: L10n.tr("Playlists")) {
            SecondaryText(playlistCount.description)
          }
          SettingsRow(title: L10n.tr("Artists")) {
            SecondaryText(artistCount.description)
          }
          SettingsRow(title: L10n.tr("Albums")) {
            SecondaryText(albumCount.description)
          }
          SettingsRow(title: L10n.tr("Songs")) {
            SecondaryText(songCount.description)
          }
          SettingsRow(title: L10n.tr("Initial Sync")) {
            SecondaryText(
              appDelegate.storage.settings.accounts.getSetting(settings.activeAccountInfo).read
                .initialSyncCompletionStatus.description
            )
          }
        }, header: L10n.tr("Library"))

        SettingsSection(content: {
          SettingsRow(title: L10n.tr("Progress")) {
            SecondaryText(autoSyncProgressText)
          }
        }, header: L10n.tr("Background song sync"))
      }
    }
    .navigationTitle(L10n.tr("Library"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      appDelegate.userStatistics.visited(.settingsLibrary)
    }
    .task {
      // Update while the page is visible; the task is cancelled automatically
      // when the view disappears, so no timer keeps running in the background.
      while !Task.isCancelled {
        await updateValues()
        try? await Task.sleep(for: .seconds(1))
      }
    }
  }
}

// MARK: - LibrarySettingsView_Previews

struct LibrarySettingsView_Previews: PreviewProvider {
  @State
  static var settings = Settings()

  static var previews: some View {
    LibrarySettingsView().environmentObject(settings)
  }
}
