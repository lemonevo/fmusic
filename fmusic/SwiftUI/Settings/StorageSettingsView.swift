//
//  StorageSettingsView.swift
//  fmusic
//
//  Download/cache management plus artwork settings, split out of Library.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import Combine
import fmusicKit
import SwiftUI

// MARK: - StorageSettingsView

struct StorageSettingsView: View {
  enum Destination: Hashable {
    case cacheSizeLimit
    case artwork
  }

  @EnvironmentObject
  private var settings: Settings

  let fileManager = CacheFileManager.shared

  @State
  var cachedSongCount = 0
  @State
  var completeCacheSize = ""
  @State
  var cacheSizeLimit = ""
  @State
  var cacheSelection = ["0", " MB"]

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
      let counts = try await appDelegate.storage.async.performAndGet { asyncCompanion in
        let accountAsync = asyncCompanion.library.getAccount(managedObjectId: accountObjectId)
        return (
          cachedSongs: asyncCompanion.library.getCachedSongCount(for: accountAsync),
          cacheSize: fileManager.getPlayableCacheSize(for: accountAsync.info)
        )
      }
      cachedSongCount = counts.cachedSongs
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
    .navigationTitle(L10n.tr("Storage & Artwork"))
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
    .task {
      while !Task.isCancelled {
        await updateValues()
        try? await Task.sleep(for: .seconds(1))
      }
    }
  }
}
