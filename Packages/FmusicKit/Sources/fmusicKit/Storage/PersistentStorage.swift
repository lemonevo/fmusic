//
//  PersistentStorage.swift
//  fmusicKit
//
//  Created by Maximilian Bauer on 09.03.19.
//  Copyright (c) 2019 Maximilian Bauer. All rights reserved.
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

import CoreData
import Foundation

// MARK: - CoreDataCompanion

public class CoreDataCompanion {
  public let context: NSManagedObjectContext
  public let library: LibraryStorage

  init(context: NSManagedObjectContext) {
    self.context = context
    self.library = LibraryStorage(context: context)
  }

  public func saveContext() {
    library.saveContext()
  }

  public func perform(body: @escaping (_ asyncCompanion: CoreDataCompanion) -> ()) {
    context.performAndWait {
      body(self)
      library.saveContext()
    }
  }
}

// MARK: - AsyncCoreDataAccessWrapper

public actor AsyncCoreDataAccessWrapper {
  let persistentContainer: NSPersistentContainer

  init(persistentContainer: NSPersistentContainer) {
    self.persistentContainer = persistentContainer
  }

  public func perform(
    body: @escaping @Sendable (_ asyncCompanion: CoreDataCompanion) throws
      -> ()
  ) async throws {
    let context = persistentContainer.newBackgroundContext()
    NSPersistentContainer.configureContext(context)

    await context.perform {
      let library = LibraryStorage(context: context)
      let asyncCompanion = CoreDataCompanion(context: context)
      do {
        try body(asyncCompanion)
        library.saveContext()
      } catch {
        library.saveContext()
      }
    }
  }

  public func performAndGet<T>(
    body: @escaping @Sendable (_ asyncCompanion: CoreDataCompanion) throws
      -> T
  ) async throws
    -> T where T: Sendable {
    let context = persistentContainer.newBackgroundContext()
    NSPersistentContainer.configureContext(context)

    let syncRequestedValue = try await context.perform {
      let asyncCompanion = CoreDataCompanion(context: context)
      do {
        let asyncRequestedValue = try body(asyncCompanion)
        asyncCompanion.saveContext()
        return asyncRequestedValue
      } catch {
        asyncCompanion.saveContext()
        throw error
      }
    }
    return syncRequestedValue
  }
}

// MARK: - PersistentStorage

public class PersistentStorage {
  public enum UserDefaultsKey: String {
    case SettingsApp = "settings.app"
    case SettingsUser = "settings.user"
    case SettingsAccount = "settings.account"
  }

  /// Flat keys from the Catalyst front-end. They are no longer read or written; the
  /// AppKit app keeps everything in the three `settings.*` blobs above.
  private static let legacyCatalystDefaultsKeys = [
    "serverUrl", "alternativeServerUrls", "username", "password", "backendApi",
    "libraryIsSynced", "initialSyncCompletionStatus", "artworkDownloadSetting",
    "artworkDisplayPreference", "sleepTimerInterval", "screenLockPreventionPreference",
    "cacheLimitInBytes", "playerVolume", "showDetailedInfo", "showSongDuration",
    "showAlbumDuration", "showArtistDuration", "enablePlayerShuffleButton",
    "showMusicPlayerSkipButtons", "alwaysHidePlayerLyricsButton",
    "isLyricsSmoothScrolling", "appearanceMode", "songActionOnTab",
    "libraryDisplaySettings", "swipeLeadingActionSettings",
    "swipeTrailingActionSettings", "playlistsSortSetting", "artistsSortSetting",
    "albumsSortSetting", "songsSortSetting", "favoriteSongSortSetting",
    "artistsFilterSetting", "albumsDisplayStyleSetting", "albumsGridSizeSetting",
    "podcastsShowSetting", "playerDisplayStyle", "isPlayerLyricsDisplayed",
    "isPlayerVisualizerDisplayed", "isOfflineMode", "isAutoDownloadLatestSongsActive",
    "isPlaybackStartOnlyOnPlay", "librarySyncVersion", "isHapticsEnabled",
    "homeSections", "librarySyncInfoReadByUser", "themePreference",
    "isEqualizerEnabled", "equalizerSettings", "activeEqualizerSetting",
    "isReplayGainEnabled",
  ]
  private static let legacyPurgeMarkerKey = "fmusic.legacyCatalystDefaultsPurged"

  private var coreDataManager: CoreDataManagable

  init(coreDataManager: CoreDataManagable) {
    self.coreDataManager = coreDataManager
  }

  public var settings = fmusicSettings()

  /// One-time removal of the old Catalyst login/settings keys. The new AppKit
  /// settings live in `settings.app`, `settings.user` and `settings.account` and
  /// are deliberately not touched.
  public func purgeLegacyCatalystDefaultsIfNeeded() {
    let defaults = UserDefaults.standard
    guard !defaults.bool(forKey: Self.legacyPurgeMarkerKey) else { return }
    for key in Self.legacyCatalystDefaultsKeys {
      defaults.removeObject(forKey: key)
    }
    defaults.set(true, forKey: Self.legacyPurgeMarkerKey)
  }

  @MainActor
  public lazy var main: CoreDataCompanion = {
    CoreDataCompanion(context: coreDataManager.context)
  }()

  public var async: AsyncCoreDataAccessWrapper {
    AsyncCoreDataAccessWrapper(persistentContainer: coreDataManager.persistentContainer)
  }
}

// MARK: - CoreDataManagable

protocol CoreDataManagable {
  var persistentContainer: NSPersistentContainer { get }
  @MainActor
  var context: NSManagedObjectContext { get }
}

// MARK: - CoreDataPersistentManager

public class CoreDataPersistentManager: CoreDataManagable {
  nonisolated(unsafe) public static let managedObjectModel: NSManagedObjectModel =
    .mergedModel(from: [FmusicKitResources.bundle])!

  /// Directory that holds the library database. Kept identical for the iOS/iPad and
  /// macOS apps so both native front-ends read the same user library.
  public static var storeDirectoryURL: URL {
    let fileManager = FileManager.default
    let baseDirectory = fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first ?? fileManager.temporaryDirectory
    return baseDirectory.appendingPathComponent("fmusic", isDirectory: true)
  }

  /// The SQLite store shared by every fmusic front-end.
  public static var storeURL: URL {
    storeDirectoryURL.appendingPathComponent("fmusic.sqlite")
  }

  lazy var persistentContainer: NSPersistentContainer = {
    /*
     The persistent container for the application. This implementation
     creates and returns a container, having loaded the store for the
     application to it. This property is optional since there are legitimate
     error conditions that could cause the creation of the store to fail.
     */
    let container = NSPersistentContainer(
      name: "fmusic",
      managedObjectModel: Self.managedObjectModel
    )
    let description = container.persistentStoreDescriptions.first
    description?.shouldInferMappingModelAutomatically = false
    description?.shouldMigrateStoreAutomatically = false
    description?.type = NSSQLiteStoreType
    // The default URL depends on the host bundle; pin it so the macOS and iOS apps
    // always open the same user library.
    try? FileManager.default.createDirectory(
      at: Self.storeDirectoryURL,
      withIntermediateDirectories: true
    )
    description?.url = Self.storeURL

    guard let storeURL = container.persistentStoreDescriptions.first?.url else {
      fatalError("persistentContainer was not set up properly")
    }

    let migrator = CoreDataMigrator()
    if migrator.requiresMigration(at: storeURL, toVersion: CoreDataMigrationVersion.current) {
      migrator.migrateStore(at: storeURL, toVersion: CoreDataMigrationVersion.current)
    }

    container.loadPersistentStores(completionHandler: { storeDescription, error in
      if let error = error as NSError? {
        // Replace this implementation with code to handle the error appropriately.
        // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.

        /*
         Typical reasons for an error here include:
         * The parent directory does not exist, cannot be created, or disallows writing.
         * The persistent store is not accessible, due to permissions or data protection when the device is locked.
         * The device is out of space.
         * The store could not be migrated to the current model version.
         Check the error message to determine what the actual problem was.
         */
        fatalError("Unresolved error \(error), \(error.userInfo)")
      }
    })

    return container
  }()

  @MainActor
  lazy var context: NSManagedObjectContext = {
    NSPersistentContainer.configureContext(persistentContainer.viewContext)
    return persistentContainer.viewContext
  }()
}

extension NSPersistentContainer {
  static fileprivate func configureContext(_ contextToConfigure: NSManagedObjectContext) {
    contextToConfigure.automaticallyMergesChangesFromParent = true
    contextToConfigure
      .mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
  }
}
