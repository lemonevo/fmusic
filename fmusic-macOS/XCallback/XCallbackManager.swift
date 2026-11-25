//
//  XCallbackManager.swift
//  fmusic-macOS
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

import AppKit
import CallbackURLKit
import fmusicKit
import Foundation

// MARK: - XCallbackLibraryElementType

/// Library element categories accepted by `searchAndPlay` and `playID`.
///
/// This mirrors `PlayableContainerTypeAppEnum` of the Catalyst app, but without the
/// `AppEnum` conformance: SiriKit / AppIntents / Shortcuts are intentionally not wired up
/// on macOS yet (their platform support is limited and the AppKit app has no intent
/// extensions), so a plain string based enum keeps the X-Callback parameters stable.
enum XCallbackLibraryElementType: String, CaseIterable {
  case artist
  case song
  case playlist
  case album
  case genre

  static var allCasesDescription: String {
    allCases.map(\.rawValue).joined(separator: ", ")
  }

  static func from(string: String) -> XCallbackLibraryElementType? {
    Self(rawValue: string.lowercased())
  }
}

// MARK: - XCallbackManager

/// Registers and dispatches the `fmusic://x-callback-url/...` actions of the macOS app.
///
/// This is the AppKit counterpart of `fmusic/Intents/IntentManager.swift` from the Catalyst
/// app: the same [CallbackURLKit](https://github.com/phimage/CallbackURLKit) based actions are
/// adapted to the shared FmusicKit core. Only actions that make sense without an OpenURL
/// scene / UIKit are registered here.
///
/// Supported URL shape:
/// `fmusic://x-callback-url/[action]?[x-callback parameters]&[action parameters]`
///
/// The standard x-callback-url reply parameters (`x-success`, `x-error`, `x-cancel`) are
/// handled by CallbackURLKit's `Manager`: on success the `x-success` URL is opened with the
/// optional return parameters, on failure `x-error` is opened with `errorCode`/`errorMessage`.
@MainActor
final class XCallbackManager {
  // MARK: Documentation

  struct ParameterDoc {
    let name: String
    let type: String
    let isMandatory: Bool
    let description: String
    let defaultIfNotGiven: String?
  }

  struct ActionDoc {
    let name: String
    let action: String
    let description: String
    let exampleURLs: [String]
    let parameters: [ParameterDoc]
  }

  // MARK: Dependencies

  private let fmusic: FmusicKit

  private var storage: PersistentStorage { fmusic.storage }
  private var library: LibraryStorage { storage.main.library }
  private var player: PlayerFacade { fmusic.player }
  private var eventLogger: EventLogger { fmusic.eventLogger }

  // MARK: State

  private(set) var documentation = [ActionDoc]()
  private(set) var isRegistered = false

  init() {
    fmusic = .shared
  }

  // MARK: - URL handling

  /// Entry point used by `AppDelegate.application(_:open:)`.
  ///
  /// Returns `false` when the URL is not a `fmusic://x-callback-url/...` URL (for instance a
  /// plain `fmusic://something` URL or a URL for another app), so the delegate can ignore it.
  @discardableResult
  func handleIncoming(url: URL) -> Bool {
    Manager.shared.handleOpen(url: url)
  }

  // MARK: - Registration

  /// Registers all X-Callback-URL actions. Must run once on the main thread at launch.
  func registerXCallbackURLs() {
    guard !isRegistered else { return }
    isRegistered = true

    // The URL scheme is read from Info.plist (`CFBundleURLTypes`) where `fmusic` is declared.
    Manager.shared.callbackURLScheme = Manager.urlSchemes?.first

    documentation.removeAll()

    // TODO: SiriKit / AppIntents / Shortcuts are skipped on macOS for now: they need intent
    // extensions and the Catalyst `AppIntents` folder is UIKit/Catalyst only. The
    // X-Callback-URL actions below cover the same functionality for script automation.
    registerSearchAndPlay()
    registerPlayID()
    registerPlayRandomSongs()
    registerPlaybackActions()
    registerPlaybackOptions()
    registerOfflineMode()
    registerFavorite()
  }

  // MARK: - Actions

  private func registerSearchAndPlay() {
    documentation.append(ActionDoc(
      name: "SearchAndPlay",
      action: "searchAndPlay",
      description: L10n.tr(
        "Plays the first search result for searchTerm in searchCategory from the currently active account."
      ),
      exampleURLs: [
        "fmusic://x-callback-url/searchAndPlay?searchTerm=Awesome&searchCategory=playlist",
        "fmusic://x-callback-url/searchAndPlay?searchTerm=Example&searchCategory=artist&shuffleOption=1&repeatOption=2",
      ],
      parameters: [
        ParameterDoc(
          name: "searchTerm",
          type: "String",
          isMandatory: true,
          description: L10n.tr("Query term to search for"),
          defaultIfNotGiven: nil
        ),
        ParameterDoc(
          name: "searchCategory",
          type: "String",
          isMandatory: true,
          description: XCallbackLibraryElementType.allCasesDescription,
          defaultIfNotGiven: nil
        ),
        ParameterDoc(
          name: "shuffleOption",
          type: "Int",
          isMandatory: false,
          description: L10n.tr("0 (false) or 1 (true)"),
          defaultIfNotGiven: "false"
        ),
        ParameterDoc(
          name: "repeatOption",
          type: "Int",
          isMandatory: false,
          description: L10n.tr("0 (off), 1 (all), 2 (single)"),
          defaultIfNotGiven: "off"
        ),
      ]
    ))
    CallbackURLKit.register(action: "searchAndPlay") { [self] parameters, success, failure, _ in
      guard let account = activeAccount else {
        fail(failure, reason: "You are not yet logged in.")
        return
      }
      guard let searchTerm = parameters["searchTerm"], !searchTerm.isEmpty else {
        fail(failure, reason: "Parameter searchTerm not provided.")
        return
      }
      guard let categoryRaw = parameters["searchCategory"] else {
        fail(failure, reason: "Parameter searchCategory not provided.")
        return
      }
      guard let category = XCallbackLibraryElementType.from(string: categoryRaw) else {
        fail(failure, reason: "Parameter searchCategory is not valid. Use: \(XCallbackLibraryElementType.allCasesDescription).")
        return
      }
      let shuffleOption = boolParameter(parameters, "shuffleOption")
      let repeatOption = repeatModeParameter(parameters)
      let container = findPlayableContainer(
        searchTerm: searchTerm,
        category: category,
        account: account
      )
      Task { @MainActor in
        let didPlay = await play(
          container: container,
          shuffleOption: shuffleOption,
          repeatOption: repeatOption
        )
        if didPlay {
          success(nil)
        } else {
          self.fail(failure, reason: "Requested element could not be played.")
        }
      }
    }
  }

  private func registerPlayID() {
    documentation.append(ActionDoc(
      name: "PlayID",
      action: "playID",
      description: L10n.tr(
        "Plays the library element with the given ID from the currently active account."
      ),
      exampleURLs: [
        "fmusic://x-callback-url/playID?id=123456&libraryElementType=playlist",
        "fmusic://x-callback-url/playID?id=aa2349&libraryElementType=artist&shuffleOption=1&repeatOption=2",
      ],
      parameters: [
        ParameterDoc(
          name: "id",
          type: "String",
          isMandatory: true,
          description: L10n.tr("ID of the library element"),
          defaultIfNotGiven: nil
        ),
        ParameterDoc(
          name: "libraryElementType",
          type: "String",
          isMandatory: true,
          description: XCallbackLibraryElementType.allCasesDescription,
          defaultIfNotGiven: nil
        ),
        ParameterDoc(
          name: "shuffleOption",
          type: "Int",
          isMandatory: false,
          description: L10n.tr("0 (false) or 1 (true)"),
          defaultIfNotGiven: "false"
        ),
        ParameterDoc(
          name: "repeatOption",
          type: "Int",
          isMandatory: false,
          description: L10n.tr("0 (off), 1 (all), 2 (single)"),
          defaultIfNotGiven: "off"
        ),
      ]
    ))
    CallbackURLKit.register(action: "playID") { [self] parameters, success, failure, _ in
      guard let account = activeAccount else {
        fail(failure, reason: "You are not yet logged in.")
        return
      }
      guard let id = parameters["id"], !id.isEmpty else {
        fail(failure, reason: "Parameter id not provided.")
        return
      }
      guard let elementTypeRaw = parameters["libraryElementType"] else {
        fail(failure, reason: "Parameter libraryElementType not provided.")
        return
      }
      guard let elementType = XCallbackLibraryElementType.from(string: elementTypeRaw) else {
        fail(failure, reason: "Parameter libraryElementType is not valid. Use: \(XCallbackLibraryElementType.allCasesDescription).")
        return
      }
      let shuffleOption = boolParameter(parameters, "shuffleOption")
      let repeatOption = repeatModeParameter(parameters)
      let container = findPlayableContainer(account: account, id: id, category: elementType)
      Task { @MainActor in
        let didPlay = await play(
          container: container,
          shuffleOption: shuffleOption,
          repeatOption: repeatOption
        )
        if didPlay {
          success(nil)
        } else {
          self.fail(failure, reason: "Requested element could not be played.")
        }
      }
    }
  }

  private func registerPlayRandomSongs() {
    documentation.append(ActionDoc(
      name: "PlayRandomSongs",
      action: "playRandomSongs",
      description: L10n.tr(
        "Plays random songs from the currently active account."
      ),
      exampleURLs: [
        "fmusic://x-callback-url/playRandomSongs",
        "fmusic://x-callback-url/playRandomSongs?onlyCached=1",
      ],
      parameters: [
        ParameterDoc(
          name: "onlyCached",
          type: "Int",
          isMandatory: false,
          description: L10n.tr("0 (false) or 1 (true), use only cached songs from library"),
          defaultIfNotGiven: "false"
        ),
      ]
    ))
    CallbackURLKit.register(action: "playRandomSongs") { [self] parameters, success, failure, _ in
      guard let account = activeAccount else {
        fail(failure, reason: "You are not yet logged in.")
        return
      }
      let onlyCached = boolParameter(parameters, "onlyCached")
      let songs = library.getRandomSongs(
        for: account,
        count: player.maxSongsToAddOnce,
        onlyCached: onlyCached
      )
      player.play(context: PlayContext(name: L10n.tr("Random Songs"), playables: songs))
      success(nil)
    }
  }

  private func registerPlaybackActions() {
    // play
    documentation.append(ActionDoc(
      name: "Play",
      action: "play",
      description: L10n.tr("Starts or resumes playback."),
      exampleURLs: ["fmusic://x-callback-url/play"],
      parameters: []
    ))
    CallbackURLKit.register(action: "play") { [self] _, success, _, _ in
      player.play()
      success(nil)
    }

    // pause
    documentation.append(ActionDoc(
      name: "Pause",
      action: "pause",
      description: L10n.tr("Pauses playback."),
      exampleURLs: ["fmusic://x-callback-url/pause"],
      parameters: []
    ))
    CallbackURLKit.register(action: "pause") { [self] _, success, _, _ in
      player.pause()
      success(nil)
    }

    // togglePlayPause
    documentation.append(ActionDoc(
      name: "TogglePlayPause",
      action: "togglePlayPause",
      description: L10n.tr("Toggles between play and pause."),
      exampleURLs: ["fmusic://x-callback-url/togglePlayPause"],
      parameters: []
    ))
    CallbackURLKit.register(action: "togglePlayPause") { [self] _, success, _, _ in
      player.togglePlayPause()
      success(nil)
    }

    // next track (`nextTrack` is the documented spelling, `playNext` the Catalyst one)
    documentation.append(ActionDoc(
      name: "NextTrack",
      action: "nextTrack",
      description: L10n.tr("Skips to the next track."),
      exampleURLs: [
        "fmusic://x-callback-url/nextTrack",
        "fmusic://x-callback-url/playNext",
      ],
      parameters: []
    ))
    CallbackURLKit.register(action: "nextTrack") { [self] _, success, _, _ in
      player.playNext()
      success(nil)
    }
    CallbackURLKit.register(action: "playNext") { [self] _, success, _, _ in
      player.playNext()
      success(nil)
    }

    // previous track (`previousTrack` is the documented spelling, `playPreviousOrReplay` the
    // Catalyst one: the current track restarts when it plays longer than a few seconds)
    documentation.append(ActionDoc(
      name: "PreviousTrack",
      action: "previousTrack",
      description: L10n.tr("Skips to the previous track or restarts the current one."),
      exampleURLs: [
        "fmusic://x-callback-url/previousTrack",
        "fmusic://x-callback-url/playPreviousOrReplay",
      ],
      parameters: []
    ))
    CallbackURLKit.register(action: "previousTrack") { [self] _, success, _, _ in
      player.playPreviousOrReplay()
      success(nil)
    }
    CallbackURLKit.register(action: "playPreviousOrReplay") { [self] _, success, _, _ in
      player.playPreviousOrReplay()
      success(nil)
    }
  }

  private func registerPlaybackOptions() {
    // setShuffle
    documentation.append(ActionDoc(
      name: "SetShuffle",
      action: "setShuffle",
      description: L10n.tr("Sets the shuffle state of the player."),
      exampleURLs: ["fmusic://x-callback-url/setShuffle?shuffleOption=1"],
      parameters: [
        ParameterDoc(
          name: "shuffleOption",
          type: "Int",
          isMandatory: true,
          description: L10n.tr("0 (false) or 1 (true)"),
          defaultIfNotGiven: nil
        ),
      ]
    ))
    CallbackURLKit.register(action: "setShuffle") { [self] parameters, success, failure, _ in
      guard let raw = parameters["shuffleOption"], let value = Int(raw), value >= 0, value <= 1
      else {
        fail(failure, reason: "Parameter shuffleOption not provided or not valid.")
        return
      }
      let wantedShuffle = value == 1
      if player.isShuffle != wantedShuffle {
        player.toggleShuffle()
      }
      success(nil)
    }

    // setRepeat
    documentation.append(ActionDoc(
      name: "SetRepeat",
      action: "setRepeat",
      description: L10n.tr("Sets the repeat state of the player."),
      exampleURLs: ["fmusic://x-callback-url/setRepeat?repeatOption=2"],
      parameters: [
        ParameterDoc(
          name: "repeatOption",
          type: "Int",
          isMandatory: true,
          description: L10n.tr("0 (off), 1 (all), 2 (single)"),
          defaultIfNotGiven: nil
        ),
      ]
    ))
    CallbackURLKit.register(action: "setRepeat") { [self] parameters, success, failure, _ in
      guard let raw = parameters["repeatOption"], let value = Int16(raw),
            let repeatMode = RepeatMode(rawValue: value) else {
        fail(failure, reason: "Parameter repeatOption not provided or not valid.")
        return
      }
      player.setRepeatMode(repeatMode)
      success(nil)
    }
  }

  private func registerOfflineMode() {
    documentation.append(ActionDoc(
      name: "SetOfflineMode",
      action: "setOfflineMode",
      description: L10n.tr("Sets the fmusic offline mode to active/inactive."),
      exampleURLs: [
        "fmusic://x-callback-url/setOfflineMode?offlineMode=1",
        "fmusic://x-callback-url/setOfflineMode?offlineMode=0",
      ],
      parameters: [
        ParameterDoc(
          name: "offlineMode",
          type: "Int",
          isMandatory: true,
          description: L10n.tr("0 (inactive) or 1 (active)"),
          defaultIfNotGiven: nil
        ),
      ]
    ))
    CallbackURLKit.register(action: "setOfflineMode") { [self] parameters, success, failure, _ in
      guard let raw = parameters["offlineMode"], let value = Int(raw), value >= 0, value <= 1
      else {
        fail(failure, reason: "Parameter offlineMode not provided or not valid.")
        return
      }
      storage.settings.user.isOfflineMode = value == 1
      // Same notification the offline toggle of the settings window posts, so downloaders and
      // the UI react immediately (the player flag itself is restored at next launch).
      fmusic.notificationHandler.post(name: .offlineModeChanged, object: nil, userInfo: nil)
      NotificationCenter.default.post(name: .macPlaybackSettingsChanged, object: nil)
      success(nil)
    }
  }

  private func registerFavorite() {
    documentation.append(ActionDoc(
      name: "FavoriteCurrentlyPlayingSong",
      action: "favoriteCurrentlyPlayingSong",
      description: L10n.tr("Marks the currently playing song as favorite (or removes it)."),
      exampleURLs: [
        "fmusic://x-callback-url/favoriteCurrentlyPlayingSong?favorite=1",
        "fmusic://x-callback-url/setFavorite?favorite=0",
      ],
      parameters: [
        ParameterDoc(
          name: "favorite",
          type: "Int",
          isMandatory: true,
          description: L10n.tr("0 (no favorite) or 1 (favorite)"),
          defaultIfNotGiven: nil
        ),
      ]
    ))
    let handler: ActionHandler = { [self] parameters, success, failure, _ in
      guard let favoriteRaw = parameters["favorite"], let favorite = Int(favoriteRaw),
            favorite >= 0, favorite <= 1 else {
        fail(failure, reason: "Parameter favorite not provided or not valid.")
        return
      }
      guard storage.settings.user.isOnlineMode else {
        fail(failure, reason: "Favorite can only be changed in Online Mode.")
        return
      }
      guard let currentlyPlaying = player.currentlyPlaying else {
        fail(failure, reason: "There is no song currently playing.")
        return
      }
      guard currentlyPlaying.isSong else {
        fail(failure, reason: "Only songs can be marked as favorite.")
        return
      }
      guard currentlyPlaying.isFavorite != (favorite == 1) else {
        success(nil)
        return
      }
      Task { @MainActor in
        if let accountInfo = currentlyPlaying.account?.info {
          do {
            try await currentlyPlaying.remoteToggleFavorite(
              syncer: self.fmusic.getMeta(accountInfo).librarySyncer
            )
          } catch {
            self.eventLogger.error(
              topic: "X-Callback-URL",
              statusCode: .connectionError,
              message: "favoriteCurrentlyPlayingSong: \(error.localizedDescription)",
              displayPopup: false
            )
          }
        }
        success(nil)
      }
    }
    CallbackURLKit.register(action: "favoriteCurrentlyPlayingSong", actionHandler: handler)
    CallbackURLKit.register(action: "setFavorite", actionHandler: handler)
  }

  // MARK: - Core helpers

  private var activeAccount: Account? {
    guard let accountInfo = storage.settings.accounts.active else { return nil }
    return library.getAccount(info: accountInfo)
  }

  private func findPlayableContainer(
    searchTerm: String,
    category: XCallbackLibraryElementType,
    account: Account
  )
    -> PlayableContainable? {
    switch category {
    case .song:
      return FuzzySearcher.findBestMatch(
        in: library.getSongs(for: account),
        search: searchTerm
      ).first
    case .artist:
      return FuzzySearcher.findBestMatch(
        in: library.getArtists(for: account),
        search: searchTerm
      ).first
    case .playlist:
      return FuzzySearcher.findBestMatch(
        in: library.getPlaylists(for: account),
        search: searchTerm
      ).first
    case .album:
      return FuzzySearcher.findBestMatch(
        in: library.getAlbums(for: account),
        search: searchTerm
      ).first
    case .genre:
      return FuzzySearcher.findBestMatch(
        in: library.getGenres(for: account),
        search: searchTerm
      ).first
    }
  }

  private func findPlayableContainer(
    account: Account,
    id: String,
    category: XCallbackLibraryElementType
  )
    -> PlayableContainable? {
    switch category {
    case .song:
      return library.getSong(for: account, id: id)
    case .artist:
      // Artists are looked up by name, like the Catalyst implementation.
      return library.getArtistLocal(for: account, name: id)
    case .playlist:
      return library.getPlaylist(for: account, id: id)
    case .album:
      return library.getAlbum(for: account, id: id, isDetailFaultResolution: false)
    case .genre:
      return library.getGenre(for: account, name: id)
    }
  }

  /// Plays a resolved library element with the requested player options.
  ///
  /// Playlists are fetched from the server first (online mode + wifi/ethernet), exactly like the
  /// Catalyst intent manager does, so a stale offline copy is not played.
  private func play(
    container: PlayableContainable?,
    shuffleOption: Bool,
    repeatOption: RepeatMode
  ) async
    -> Bool {
    guard let container else { return false }
    if let playlist = container as? Playlist, let accountInfo = playlist.account?.info {
      if storage.settings.user.isOnlineMode, fmusic.networkMonitor.isWifiOrEthernet {
        let meta = fmusic.getMeta(accountInfo)
        do {
          try await container.fetch(
            storage: storage,
            librarySyncer: meta.librarySyncer,
            playableDownloadManager: meta.playableDownloadManager
          )
        } catch {
          // Play what is available locally instead of failing the whole action.
          eventLogger.error(
            topic: "X-Callback-URL",
            statusCode: .connectionError,
            message: "fetch playlist \(container.name): \(error.localizedDescription)",
            displayPopup: false
          )
        }
      }
    }
    let context = PlayContext(containable: container)
    if shuffleOption {
      player.playShuffled(context: context)
    } else {
      player.play(context: context)
    }
    player.setRepeatMode(repeatOption)
    return true
  }

  // MARK: - Parameter helpers

  private func boolParameter(_ parameters: Parameters, _ key: String) -> Bool {
    guard let raw = parameters[key], let value = Int(raw), value >= 0, value <= 1 else {
      return false
    }
    return value == 1
  }

  private func repeatModeParameter(_ parameters: Parameters) -> RepeatMode {
    guard let raw = parameters["repeatOption"], let value = Int16(raw),
          let repeatMode = RepeatMode(rawValue: value) else { return .off }
    return repeatMode
  }

  // MARK: - Error reporting

  /// Logs an X-Callback failure (no popup: the action is triggered headless, e.g. by a script)
  /// and answers the caller through the standard `x-error` callback.
  private func fail(
    _ failure: FailureCallback,
    reason: String,
    code: ErrorCode = .missingErrorCode
  ) {
    eventLogger.error(
      topic: "X-Callback-URL",
      statusCode: .commonError,
      message: reason,
      displayPopup: false
    )
    failure(NSError.error(code: code, failureReason: reason))
  }

  // MARK: - Documentation

  /// Human readable documentation used by the `X-Callback-URL` helper window/menu action.
  var documentationText: String {
    var lines: [String] = []
    lines.append(L10n.tr("Supported X-Callback-URL actions:"))
    lines.append("")
    for doc in documentation {
      lines.append("\(doc.name) — fmusic://x-callback-url/\(doc.action)")
      lines.append("  \(doc.description)")
      for example in doc.exampleURLs {
        lines.append("  \(example)")
      }
      lines.append("")
    }
    lines.append(L10n.tr(
      "The standard x-success, x-error and x-cancel parameters are supported."
    ))
    return lines.joined(separator: "\n")
  }
}
