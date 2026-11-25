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

// MARK: - PersistentStorageError

public enum PersistentStorageError: LocalizedError {
  case missingManagedObjectModel
  case missingStoreURL
  case loadFailed(Error)

  public var errorDescription: String? {
    switch self {
    case .missingManagedObjectModel:
      return "Core Data managed object model could not be loaded from resources."
    case .missingStoreURL:
      return "Core Data persistent store URL could not be configured."
    case .loadFailed(let error):
      return error.localizedDescription
    }
  }
}

// MARK: - CoreDataPersistentManager

public class CoreDataPersistentManager: CoreDataManagable {
  nonisolated(unsafe) public static let managedObjectModel: NSManagedObjectModel =
    .mergedModel(from: [FmusicKitResources.bundle]) ?? NSManagedObjectModel()

  private static let hasMergedModel: Bool =
    NSManagedObjectModel.mergedModel(from: [FmusicKitResources.bundle]) != nil

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

  public private(set) var storeLoadError: Error?
  private var _persistentContainer: NSPersistentContainer?

  /// Prepares and loads the persistent store, throwing on model, migration, or SQLite
  /// errors instead of crashing so the UI can present recovery options.
  public func prepareStore() throws {
    if _persistentContainer != nil, storeLoadError == nil {
      return
    }
    guard Self.hasMergedModel else {
      let error = PersistentStorageError.missingManagedObjectModel
      storeLoadError = error
      throw error
    }

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
    try FileManager.default.createDirectory(
      at: Self.storeDirectoryURL,
      withIntermediateDirectories: true
    )
    description?.url = Self.storeURL

    guard let storeURL = container.persistentStoreDescriptions.first?.url else {
      let error = PersistentStorageError.missingStoreURL
      storeLoadError = error
      throw error
    }

    do {
      let migrator = CoreDataMigrator()
      if migrator.requiresMigration(at: storeURL, toVersion: CoreDataMigrationVersion.current) {
        try migrator.migrateStore(at: storeURL, toVersion: CoreDataMigrationVersion.current)
      }

      var loadError: Error?
      container.loadPersistentStores { _, error in
        if let error {
          loadError = error
        }
      }
      if let loadError {
        throw PersistentStorageError.loadFailed(loadError)
      }

      _persistentContainer = container
      storeLoadError = nil
    } catch {
      storeLoadError = error
      throw error
    }
  }

  /// Moves the current SQLite store files into a timestamped backup folder under
  /// `storeDirectoryURL/CorruptedBackups` so a fresh library can be created without
  /// permanently destroying the user's database files.
  public func backupAndResetStore() throws {
    let fileManager = FileManager.default
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
    let backupDir = Self.storeDirectoryURL
      .appendingPathComponent("CorruptedBackups", isDirectory: true)
      .appendingPathComponent(stamp, isDirectory: true)

    let storeFiles = [
      Self.storeURL,
      URL(fileURLWithPath: Self.storeURL.path + "-wal"),
      URL(fileURLWithPath: Self.storeURL.path + "-shm"),
    ]

    var didCreateBackupDir = false
    for fileURL in storeFiles where fileManager.fileExists(atPath: fileURL.path) {
      if !didCreateBackupDir {
        try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)
        didCreateBackupDir = true
      }
      let destination = backupDir.appendingPathComponent(fileURL.lastPathComponent)
      try fileManager.moveItem(at: fileURL, to: destination)
    }

    _persistentContainer = nil
    storeLoadError = nil
  }

  var persistentContainer: NSPersistentContainer {
    if let existing = _persistentContainer {
      return existing
    }
    do {
      try prepareStore()
      if let prepared = _persistentContainer {
        return prepared
      }
    } catch {
      storeLoadError = error
    }
    // Non-fatal fallback in-memory container when disk store could not be opened.
    let fallback = NSPersistentContainer(
      name: "fmusic",
      managedObjectModel: Self.managedObjectModel
    )
    let memoryDesc = NSPersistentStoreDescription()
    memoryDesc.type = NSInMemoryStoreType
    fallback.persistentStoreDescriptions = [memoryDesc]
    fallback.loadPersistentStores { _, _ in }
    _persistentContainer = fallback
    return fallback
  }

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
