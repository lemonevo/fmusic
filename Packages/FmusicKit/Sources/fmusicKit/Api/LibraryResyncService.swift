//
//  LibraryResyncService.swift
//  fmusicKit
//
//  Created by Maximilian Bauer on 21.11.26.
//  Copyright (c) 2026 Maximilian Bauer. All rights reserved.
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
import os.log

// MARK: - LibrarySyncProgress

/// A platform-neutral snapshot of a running library sync.
///
/// Front-ends translate `phase` into their own localized status text and use
/// `fractionCompleted` to drive a progress bar. `fractionCompleted` is `nil` while the
/// total number of objects is unknown (the sync is still enumerating the source); the
/// progress bar should then be shown as indeterminate.
public struct LibrarySyncProgress: Sendable, Equatable {
  public enum Phase: Sendable, Equatable {
    /// Managers are stopped and the account/player state is being reset.
    case preparing
    case artist
    case album
    case song
    case playlist
    case genre
    case podcast
    case cache
    /// The library managers have been restarted; the UI can be reloaded.
    case finished

    init(_ parsedObjectType: ParsedObjectType) {
      switch parsedObjectType {
      case .artist: self = .artist
      case .album: self = .album
      case .song: self = .song
      case .playlist: self = .playlist
      case .genre: self = .genre
      case .podcast: self = .podcast
      case .cache: self = .cache
      }
    }
  }

  public let phase: Phase
  public let parsedObjectCount: Int
  public let totalCount: Int

  public init(
    phase: Phase,
    parsedObjectCount: Int = 0,
    totalCount: Int = 0
  ) {
    self.phase = phase
    self.parsedObjectCount = parsedObjectCount
    self.totalCount = totalCount
  }

  /// 0.0 ... 1.0, or `nil` when the total object count is not known yet.
  public var fractionCompleted: Double? {
    guard totalCount > 0 else { return nil }
    return min(1, max(0, Double(parsedObjectCount) / Double(totalCount)))
  }
}

// MARK: - LibrarySyncProgressBridge

/// Bridges the `SyncCallbacks` notifications of a library syncer (which may be called from
/// any thread) to a `@MainActor` progress handler.
private final class LibrarySyncProgressBridge: SyncCallbacks, @unchecked Sendable {
  private let handler: @MainActor (LibrarySyncProgress) -> Void
  private var phase: LibrarySyncProgress.Phase = .preparing
  private var parsedObjectCount = 0
  private var totalCount = 0
  private var lastPublishedFraction = -1.0

  init(handler: @escaping @MainActor (LibrarySyncProgress) -> Void) {
    self.handler = handler
  }

  nonisolated func notifySyncStarted(
    ofType parsedObjectType: ParsedObjectType,
    totalCount: Int
  ) {
    Task { @MainActor in
      phase = LibrarySyncProgress.Phase(parsedObjectType)
      parsedObjectCount = 0
      self.totalCount = max(0, totalCount)
      lastPublishedFraction = -1.0
      publish()
    }
  }

  nonisolated func notifyParsedObject(ofType parsedObjectType: ParsedObjectType) {
    Task { @MainActor in
      // Ignore stale notifications of an object type that was already finished.
      guard LibrarySyncProgress.Phase(parsedObjectType) == phase else { return }
      parsedObjectCount += 1
      // Thousands of objects are parsed per sync; only publish when the visible progress
      // actually changed so the main thread is not flooded.
      let fraction = totalCount > 0
        ? Double(parsedObjectCount) / Double(totalCount)
        : 0
      guard lastPublishedFraction < 0 ||
        fraction - lastPublishedFraction >= 0.002 ||
        parsedObjectCount == totalCount
      else { return }
      lastPublishedFraction = fraction
      publish()
    }
  }

  @MainActor
  private func publish() {
    handler(LibrarySyncProgress(
      phase: phase,
      parsedObjectCount: parsedObjectCount,
      totalCount: totalCount
    ))
  }
}

// MARK: - SyncContinuationBox

/// One-shot continuation box that couples the (non-cancellable) library indexer to the
/// caller's task without ever resuming the continuation twice.
private final class SyncContinuationBox: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, Error>?
  private var pendingResult: Result<Void, Error>?

  func install(_ continuation: CheckedContinuation<Void, Error>) {
    lock.lock()
    let result = pendingResult
    pendingResult = nil
    if result == nil {
      self.continuation = continuation
    }
    lock.unlock()
    if let result {
      continuation.resume(with: result)
    }
  }

  func resume(with result: Result<Void, Error>) {
    lock.lock()
    if let continuation {
      self.continuation = nil
      lock.unlock()
      continuation.resume(with: result)
    } else {
      if pendingResult == nil {
        pendingResult = result
      }
      lock.unlock()
    }
  }
}

// MARK: - LibraryResyncService

/// Platform-neutral library management used by every front-end.
///
/// Both the UIKit/Catalyst app and the pure AppKit macOS app resync the library with the
/// same steps the initial-login sync uses:
///
///  1. stop the account's background managers and drop its cached `MetaManager`,
///  2. leave offline mode and detach the player from the account,
///  3. run the backend's initial/full library sync with progress callbacks,
///  4. restart the background managers and mark the library as synced.
///
/// Logout removes the account's login credentials and its downloaded/cached files. The
/// library database entries are kept, so logging in to the same account again reuses them.
///
/// The service only talks to public `fmusicKit` APIs and contains no UIKit/AppKit code.
@MainActor
public final class LibraryResyncService {
  private let fmusicKit: FmusicKit
  private let log = OSLog(subsystem: "fmusic", category: "LibraryResyncService")

  public init(fmusicKit: FmusicKit) {
    self.fmusicKit = fmusicKit
  }

  public convenience init() {
    self.init(fmusicKit: .shared)
  }

  // MARK: - Resync

  /// Re-indexes the account's music source from scratch (incremental where the backend can
  /// skip unchanged files). The library, downloaded songs and playback data are kept.
  ///
  /// - Parameters:
  ///   - accountInfo: account whose library should be resynced.
  ///   - progress: called on the main actor with status and fraction updates. The final
  ///     callback has `phase == .finished`.
  /// - Throws: the underlying sync error (for example a network error). The app state is
  ///   restored (managers restarted, player usable) even when the sync fails, so callers can
  ///   simply show an error alert. Cancelling the surrounding task is safe as well and
  ///   mirrors the Catalyst app's "Skip Sync": the call returns `CancellationError`
  ///   immediately, the managers are restarted at once and the indexer finishes in the
  ///   background (no downloaded song or playback data is ever deleted).
  public func resyncLibrary(
    accountInfo: AccountInfo,
    progress: @escaping @MainActor (LibrarySyncProgress) -> Void
  ) async throws {
    let storage = fmusicKit.storage
    let player = fmusicKit.player
    let notificationHandler = fmusicKit.notificationHandler

    guard storage.settings.accounts.getSetting(accountInfo).read.loginCredentials != nil
    else { throw BackendError.noCredentials }

    os_log("Resync library started", log: log, type: .info)
    progress(LibrarySyncProgress(phase: .preparing))

    // 1. Stop all background work of this account and drop the cached managers, exactly
    //    like the initial-login sync does before it starts from a clean state.
    if let meta = fmusicKit.allActiveMetas[accountInfo] {
      meta.stopManager()
    }
    fmusicKit.resetMeta(accountInfo)

    // 2. A sync needs the network.
    if storage.settings.user.isOfflineMode {
      storage.settings.user.isOfflineMode = false
      notificationHandler.post(name: .offlineModeChanged, object: nil, userInfo: nil)
    }

    // The Catalyst app behaves like a fresh install for a single-account setup: the library
    // is marked unsynced until the resync finished. Keep this in sync with `SyncVC`.
    if storage.settings.accounts.allAccounts.count <= 1 {
      storage.settings.app.isLibrarySynced = false
      player.stop()
    }

    // 3. Detach the player from the account before the library is re-indexed. Downloaded
    //    files and playback data on disk are intentionally not touched.
    let account = storage.main.library.getAccount(info: accountInfo)
    player.logout(account: account)

    let eventLogger = fmusicKit.eventLogger
    let previousSuppressAlerts = eventLogger.supressAlerts
    eventLogger.supressAlerts = true
    defer { eventLogger.supressAlerts = previousSuppressAlerts }

    // Create a fresh MetaManager *after* the reset. It resolves the backend API from the
    // persisted account/credentials (`AccountInfo.apiType` is not persisted in the settings,
    // see `AccountInfo.CodingKeys`), so a WebDAV account keeps using the WebDAV indexer.
    let meta = fmusicKit.getMeta(accountInfo)
    if let credentials = storage.settings.accounts.getSetting(accountInfo).read
      .loginCredentials,
      credentials.backendApi != .notDetected,
      meta.backendApi.selectedApi != credentials.backendApi {
      // Defensive: never let a WebDAV account be indexed by the local folder indexer. This
      // should already be guaranteed by `MetaManager`'s resolved-API-type fallback.
      os_log(
        "Resync library corrected backend API from %s to %s",
        log: log,
        type: .info,
        meta.backendApi.selectedApi.description,
        credentials.backendApi.description
      )
      meta.backendApi.selectedApi = credentials.backendApi
      // `BackendProxy` only forwards credentials to the currently selected API, so hand
      // them to the new one before syncing.
      meta.backendApi.provideCredentials(credentials: credentials)
    }

    let bridge = LibrarySyncProgressBridge(handler: progress)
    var syncError: Error?
    do {
      try await waitForInitialSync(
        meta: meta,
        accountInfo: accountInfo,
        bridge: bridge,
        storage: storage,
        notificationHandler: notificationHandler
      )
    } catch {
      syncError = error
      let isCancelled = error is CancellationError || Task.isCancelled
      storage.settings.accounts.updateSetting(accountInfo) { accountSettings in
        accountSettings.initialSyncCompletionStatus = isCancelled ? .skipped : .aborted
      }
      if !isCancelled {
        os_log(
          "Resync library failed: %s",
          log: log,
          type: .error,
          error.localizedDescription
        )
        eventLogger.report(
          topic: L10n.tr("Initial Sync"),
          error: error,
          displayPopup: false
        )
      }
    }

    // 4. Put the app back into its normal working state. This also runs after a failed or
    //    cancelled sync so the user is never left with stopped background managers
    //    (mirrors Catalyst `SyncVC.finishSync()`).
    storage.settings.app.librarySyncVersion = .newestVersion
    storage.settings.app.isLibrarySynced = true
    meta.startManagerAfterSync(player: player)
    notificationHandler.post(name: .librarySongsSynced, object: nil, userInfo: nil)
    progress(LibrarySyncProgress(phase: .finished))

    os_log("Resync library finished", log: log, type: .info)
    if let syncError {
      throw syncError
    }
  }

  /// Runs the indexer in an unstructured task and waits for it, unless the caller's task is
  /// cancelled first.
  ///
  /// The library indexers are not cancellation-aware (they only write their result at the
  /// very end and must not be interrupted half way), so cancelling must not stop them. This
  /// mirrors the Catalyst app's "Skip Sync": the caller returns immediately and restores the
  /// app state, while the indexer finishes in the background and updates the library. The
  /// indexer's completion also marks the account as synced and notifies open windows, so a
  /// skipped resync still converges to a complete library.
  private func waitForInitialSync(
    meta: MetaManager,
    accountInfo: AccountInfo,
    bridge: SyncCallbacks,
    storage: PersistentStorage,
    notificationHandler: EventNotificationHandler
  ) async throws {
    let box = SyncContinuationBox()
    Task { @MainActor in
      do {
        try await meta.librarySyncer.syncInitial(statusNotifyier: bridge)
        // The caller may have cancelled (and even logged the account out) while the
        // indexer was finishing in the background; only update settings that still exist.
        if storage.settings.accounts.allAccounts.contains(accountInfo) {
          storage.settings.accounts.updateSetting(accountInfo) { accountSettings in
            accountSettings.initialSyncCompletionStatus = .completed
          }
          notificationHandler.post(name: .librarySongsSynced, object: nil, userInfo: nil)
        }
        box.resume(with: .success(()))
      } catch {
        box.resume(with: .failure(error))
      }
    }
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        box.install(continuation)
      }
    } onCancel: {
      box.resume(with: .failure(CancellationError()))
    }
  }

  // MARK: - Logout

  /// Removes the account's login credentials and deletes its downloaded/cached files.
  ///
  /// The library database entries are kept (like the Catalyst app does): logging in with the
  /// same account again reuses them. Background managers are stopped, the player is detached
  /// from the account and `.accountDeleted` / `.accountActiveChanged` are posted so every
  /// front-end can update its window.
  ///
  /// - Note: When this was the last account `app.isLibrarySynced` is reset, so the next launch
  ///   behaves like a fresh install and asks for login again.
  public func logout(accountInfo: AccountInfo) {
    let storage = fmusicKit.storage
    let player = fmusicKit.player
    let notificationHandler = fmusicKit.notificationHandler

    os_log("Logout account started", log: log, type: .info)

    if let meta = fmusicKit.allActiveMetas[accountInfo] {
      meta.stopManager()
    }
    fmusicKit.resetMeta(accountInfo)

    if storage.settings.accounts.allAccounts.count <= 1 {
      player.stop()
    }

    // Delete the account's downloaded songs, podcast episodes, artwork and lyrics. The
    // original music files on the source are not touched.
    CacheFileManager.shared.deleteAccountCache(accountInfo: accountInfo)

    // Reset the login credentials. The library objects stay in the database, so a later
    // login of the same account reuses them.
    storage.settings.accounts.logout(accountInfo)

    let account = storage.main.library.getAccount(info: accountInfo)
    player.logout(account: account)

    if storage.settings.user.isOfflineMode {
      storage.settings.user.isOfflineMode = false
      notificationHandler.post(name: .offlineModeChanged, object: nil, userInfo: nil)
    }

    if storage.settings.accounts.active == nil {
      // No account left: behave like an initial app start (a fresh install asks for login
      // and runs the initial sync).
      storage.settings.app.isLibrarySynced = false
    }

    notificationHandler.post(name: .accountDeleted, object: nil, userInfo: nil)
    notificationHandler.post(name: .accountActiveChanged, object: nil, userInfo: nil)

    os_log("Logout account finished", log: log, type: .info)
  }
}
