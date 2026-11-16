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
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import Combine
import fmusicKit
import SwiftUI

// MARK: - LibrarySettingsView

struct LibrarySettingsView: View {
  enum Destination: Hashable {
    case cacheSizeLimit
    case artwork
  }

  @EnvironmentObject
  private var settings: Settings

  let fileManager = CacheFileManager.shared

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
  var cachedSongCount = 0
  @State
  var completeCacheSize = ""
  @State
  var cacheSizeLimit = ""
  @State
  var cacheSelection = ["0", " MB"]
  @State
  var autoSyncProgressText = ""

  @State
  var isShowDeleteCacheAlert = false
  @State
  var isShowDownloadSongsAlert = false

  let byteValues = (
    stride(from: 0, through: 20, by: 1).map { $0.description } +
      stride(from: 25, through: 50, by: 5).map { $0.description } +
      stride(from: 60, through: 100, by: 10).map { $0.description } +
      stride(from: 110, through: 975, by: 25).map { $0.description }
  )

  private func updateValues() async {
    do {
      guard let activeAccountInfo = settings.activeAccountInfo else { return }
      let accountObjectId = appDelegate.storage.main.library
        .getAccount(info: activeAccountInfo).managedObject.objectID
      // One background context for all counts; previously this opened six
      // separate contexts every second while the page was visible.
      let counts = try await appDelegate.storage.async.performAndGet { asyncCompanion in
        let accountAsync = asyncCompanion.library.getAccount(managedObjectId: accountObjectId)
        return (
          playlists: asyncCompanion.library.getPlaylistCount(for: accountAsync),
          artists: asyncCompanion.library.getArtistCount(for: accountAsync),
          albums: asyncCompanion.library.getAlbumCount(for: accountAsync),
          songs: asyncCompanion.library.getSongCount(for: accountAsync),
          syncedAlbums: asyncCompanion.library.getAlbumWithSyncedSongsCount(for: accountAsync),
          cachedSongs: asyncCompanion.library.getCachedSongCount(for: accountAsync),
          cacheSize: fileManager.getPlayableCacheSize(for: accountAsync.info)
        )
      }
      playlistCount = counts.playlists
      artistCount = counts.artists
      albumCount = counts.albums
      songCount = counts.songs
      albumWithSyncedSongsCount = counts.syncedAlbums
      cachedSongCount = counts.cachedSongs

      if albumCount < 1 {
        autoSyncProgressText = String(format: "%.1f", 0.0) + "%"
      } else {
        let progress = Float(albumWithSyncedSongsCount) * 100.0 / Float(albumCount)
        autoSyncProgressText = String(format: "%.1f", progress) + "%"
      }

      completeCacheSize = (counts.cacheSize > 1_000_000) ? counts.cacheSize.asByteString : Int64(0)
        .asByteString

      let curCacheSizeLimit = Int64(settings.cacheSizeLimit)
      cacheSizeLimit = curCacheSizeLimit > 0 ? curCacheSizeLimit.asByteString : L10n.tr("No Limit")
      cacheSelection = curCacheSizeLimit > 0 ? [
        curCacheSizeLimit.asByteString.components(separatedBy: " ")[0],
        " " + curCacheSizeLimit.asByteString.components(separatedBy: " ")[1]
      ] : ["0", " MB"]
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
        })

        let progressTitle = L10n.tr("Progress")

        SettingsSection(content: {
          SettingsRow(title: progressTitle) {
            SecondaryText(autoSyncProgressText)
          }
        }, header: L10n.tr("Background song sync"))

        SettingsSection(content: {
          let changeHandler: ([String], [String]) -> () = { oldCacheString, newCacheString in
            if newCacheString[1] == "" {
              settings.cacheSizeLimit = 0
              cacheSelection = ["0", " MB"]
            }
            if let cacheInByte = (newCacheString[0] + newCacheString[1]).asByteCount {
              settings.cacheSizeLimit = cacheInByte
            }
          }

          SettingsRow(title: L10n.tr("Cached Songs")) {
            SecondaryText(cachedSongCount.description)
          }
          SettingsRow(title: L10n.tr("Complete Cache Size")) {
            SecondaryText(completeCacheSize.description)
          }

          #if targetEnvironment(macCatalyst) // ok
            // We can not present the picker in wheel style on macOS. It is not supported.
            // Instead, we use a menu style picker without a navigation link.
            MultiPickerView(
              data: [(L10n.tr("Cache Size Limit"), byteValues), ("", [" MB", " GB"])],
              selection: $cacheSelection
            )
            .onChange(of: cacheSelection, changeHandler)
          #else
            NavigationLink(value: Destination.cacheSizeLimit) {
              SettingsRow(title: L10n.tr("Cache Size Limit")) {
                SecondaryText(cacheSizeLimit.description)
              }
            }
            .onChange(of: cacheSelection, changeHandler)
          #endif

          if let activeAccountInfo = settings.activeAccountInfo {
            SettingsButtonRow(title: L10n.tr("Download all songs in library")) {
              isShowDownloadSongsAlert = true
            }
            .alert(isPresented: $isShowDownloadSongsAlert) {
              Alert(
                title: Text(L10n.tr("Download all songs in library")),
                message: Text(
                  L10n.tr(
                    "This will add all uncached songs in your library to the download queue. This may use a lot of data and storage. Continue?"
                  )
                ),
                primaryButton: .default(Text(L10n.tr("OK"))) {
                  let account = appDelegate.storage.main.library
                    .getAccount(info: activeAccountInfo)
                  let allSongsToDownload = appDelegate.storage.main.library
                    .getSongsForCompleteLibraryDownload(for: account)
                  let playableDownloadManager = appDelegate.getMeta(account.info)
                    .playableDownloadManager
                  playableDownloadManager.download(objects: allSongsToDownload)
                  // Also resume pending downloads that are no longer queued
                  // (e.g. the app was suspended while they were waiting).
                  playableDownloadManager.start()
                },
                secondaryButton: .cancel()
              )
            }

            SettingsButtonRow(
              title: L10n.tr("Delete downloaded songs"),
              actionType: .destructive
            ) {
              isShowDeleteCacheAlert = true
            }.alert(isPresented: $isShowDeleteCacheAlert) {
              Alert(
                title: Text(L10n.tr("Delete Cache")),
                message: Text(
                  L10n.tr(
                    "Are you sure you want to delete this account’s downloaded songs?"
                  )
                ),
                primaryButton: .destructive(Text(L10n.tr("Delete"))) {
                  appDelegate.player.stop()
                  let account = appDelegate.storage.main.library
                    .getAccount(info: activeAccountInfo)
                  appDelegate.getMeta(account.info).playableDownloadManager.stop()
                  appDelegate.storage.main.library
                    .deletePlayableCachePaths(for: account)
                  appDelegate.storage.main.library.saveContext()
                  fileManager.deletePlayableCache(accountInfo: account.info)
                  appDelegate.getMeta(account.info).playableDownloadManager.start()
                }, secondaryButton: .cancel()
              )
            }
          }
        }, header: L10n.tr("Cache"))

        SettingsSection {
          NavigationLink(value: Destination.artwork) {
            Text(L10n.tr("Artwork & Cache"))
          }
        }
      }
    }
    .navigationTitle(L10n.tr("Library"))
    .navigationBarTitleDisplayMode(.inline)
    .navigationDestination(for: Destination.self) { destination in
      switch destination {
      case .cacheSizeLimit:
        MultiPickerView(
          data: [("Size", byteValues), (" Bytes", [" MB", " GB"])],
          selection: $cacheSelection
        )
        .navigationTitle(L10n.tr("Cache Size Limit"))
      case .artwork: ArtworkSettingsView()
      }
    }
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
