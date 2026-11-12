//
//  EntityPreviewVC.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 12.02.24.
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

import AmperfyKit
import Foundation
import MarqueeLabel
import UIKit

typealias GetPlayContextCallback = () -> PlayContext?
typealias GetPlayerIndexCallback = () -> PlayerIndex?

// MARK: - EntityPreviewActionBuilder

@MainActor
class EntityPreviewActionBuilder {
  private var entityContainer: PlayableContainable
  private var rootView: UIViewController
  private var playContextCb: GetPlayContextCallback?
  private var playerIndexCb: GetPlayerIndexCallback?
  private var appDelegate: AppDelegate

  private var entityPlayables: [AbstractPlayable] {
    let playables = entityContainer.playables
      .filterCached(dependigOn: appDelegate.storage.settings.user.isOfflineMode)
    switch entityContainer.playContextType {
    case .music:
      return playables
        .filter { $0.asSong?.isAvailableToUser() ?? false }
    case .podcast:
      return playables
    }
  }

  // configure states
  private var isPlay = false
  private var isShuffle = false
  private var isMusicQueue = false
  private var isShowAlbum = false
  private var isShowArtist = false
  private var isAddToPlaylist = false
  private var isDownloadPossible: Bool {
    !(
      entityContainer.playables.isCachedCompletely ||
        appDelegate.storage.settings.user.isOfflineMode ||
        !entityContainer.isDownloadAvailable
    )
  }

  private var isShowSongDetails = false
  private var isInstantMix = false
  private var isShareable = false

  init(
    container: PlayableContainable,
    on rootView: UIViewController,
    playContextCb: GetPlayContextCallback? = nil,
    playerIndexCb: GetPlayerIndexCallback? = nil
  ) {
    self.appDelegate = (UIApplication.shared.delegate as! AppDelegate)
    self.entityContainer = container
    self.rootView = rootView
    self.playContextCb = playContextCb
    self.playerIndexCb = playerIndexCb
  }

  public func createMenu() -> UIMenu {
    UIMenu(children: createMenuActions())
  }

  public func createMenuActions() -> [UIMenuElement] {
    var menuActions = [UIMenuElement]()

    configureUI()

    var playActions = [UIMenuElement]()
    var gotoActions = [UIMenuElement]()
    var ratingFavActions = [UIMenuElement]()
    var elementHandlingActions = [UIMenuElement]()

    if isPlay {
      playActions.append(createPlayAction())
    }
    if isShuffle {
      playActions.append(createPlayShuffledAction())
    }
    if isInstantMix {
      playActions.append(createInstantMixAction())
    }
    if !playActions.isEmpty {
      menuActions.append(UIMenu(options: .displayInline, children: playActions))
    }
    if isMusicQueue {
      menuActions.append(createMusicQueueAction())
    }
    if isShowAlbum {
      gotoActions.append(createShowAlbumAction())
    }
    if isShowArtist {
      gotoActions.append(createShowArtistAction())
    }
    if isShowSongDetails,
       let song = (entityContainer as? AbstractPlayable)?.asSong,
       let lyricsShowAction = createShowLyricsAction(song: song) {
      gotoActions.append(lyricsShowAction)
    }
    if !gotoActions.isEmpty {
      menuActions.append(UIMenu(options: .displayInline, children: gotoActions))
    }
    if let libraryEntity = entityContainer as? AbstractLibraryEntity, entityContainer.isFavoritable,
       appDelegate.storage.settings.user.isOnlineMode {
      ratingFavActions.append(createFavoriteMenu(libraryEntity: libraryEntity))
    }
    if let libraryEntity = entityContainer as? AbstractLibraryEntity, entityContainer.isRateable,
       appDelegate.storage.settings.user.isOnlineMode {
      ratingFavActions.append(createRatingMenu(libraryEntity: libraryEntity))
    }
    if !ratingFavActions.isEmpty {
      menuActions.append(UIMenu(options: .displayInline, children: ratingFavActions))
    }
    if isAddToPlaylist {
      elementHandlingActions.append(createAddToPlaylistAction())
    }
    if isDownloadPossible {
      elementHandlingActions.append(createDownloadAction())
    }
    if entityContainer.playables.hasCachedItems {
      elementHandlingActions.append(createDeleteCacheAction())
    }
    if isShareable, let playable = entityContainer as? AbstractPlayable {
      elementHandlingActions.append(createShareAction(playable: playable))
    }
    if !elementHandlingActions.isEmpty {
      menuActions.append(UIMenu(options: .displayInline, children: elementHandlingActions))
    }
    if appDelegate.storage.settings.user.isShowDetailedInfo {
      menuActions.append(createCopyIdToClipboardAction())
    }

    return menuActions
  }

  public func performPreviewTransition() {
    if let playable = entityContainer as? AbstractPlayable {
      if let _ = playable.asSong, !(rootView is AlbumDetailVC) {
        showAlbum()
      }
    } else if let album = entityContainer as? Album, let account = album.account {
      rootView.navigationController?.pushViewController(
        AppStoryboard.Main.segueToAlbumDetail(account: account, album: album),
        animated: true
      )
    } else if let artist = entityContainer as? Artist, let account = artist.account {
      rootView.navigationController?.pushViewController(
        AppStoryboard.Main.segueToArtistDetail(account: account, artist: artist),
        animated: true
      )
    } else if let genre = entityContainer as? Genre, let account = genre.account {
      rootView.navigationController?.pushViewController(
        AppStoryboard.Main.segueToGenreDetail(account: account, genre: genre),
        animated: true
      )
    } else if let playlist = entityContainer as? Playlist, let account = playlist.account {
      rootView.navigationController?.pushViewController(
        AppStoryboard.Main.segueToPlaylistDetail(account: account, playlist: playlist),
        animated: true
      )
    } else if let directory = entityContainer as? Directory, let account = directory.account {
      rootView.navigationController?.pushViewController(
        AppStoryboard.Main.segueToDirectories(account: account, directory: directory),
        animated: true
      )
    }
  }

  private func configureUI() {
    if let playable = entityContainer as? AbstractPlayable {
      if let song = playable.asSong {
        configureFor(song: song)
      }
    } else if let album = entityContainer as? Album {
      configureFor(album: album)
    } else if let artist = entityContainer as? Artist {
      configureFor(artist: artist)
    } else if let genre = entityContainer as? Genre {
      configureFor(genre: genre)
    } else if let playlist = entityContainer as? Playlist {
      configureFor(playlist: playlist)
    } else if let directory = entityContainer as? Directory {
      configureFor(directory: directory)
    }
  }

  private func configureFor(song: Song) {
    isPlay = !(
      (playContextCb == nil) ||
        (!song.isCached && appDelegate.storage.settings.user.isOfflineMode)
    )
    isShuffle = !(
      (playContextCb == nil) ||
        playerIndexCb != nil ||
        (!song.isCached && appDelegate.storage.settings.user.isOfflineMode)
    ) &&
      appDelegate.storage.settings.user.isPlayerShuffleButtonEnabled
    isMusicQueue = !(
      (playContextCb == nil) ||
        playerIndexCb != nil ||
        (!song.isCached && appDelegate.storage.settings.user.isOfflineMode)
    )
    isShowAlbum = !(rootView is AlbumDetailVC)
    isShowArtist = !(rootView is ArtistDetailVC)
    isAddToPlaylist = appDelegate.storage.settings.user.isOnlineMode
    isShowSongDetails = true
    isInstantMix = appDelegate.storage.settings.user.isOnlineMode
    isShareable = song.isCached || appDelegate.storage.settings.user.isOnlineMode
  }

  private func configureFor(playlist: Playlist) {
    isPlay = appDelegate.storage.settings.user.isOnlineMode || entityContainer.playables
      .hasCachedItems
    isShuffle = (
      appDelegate.storage.settings.user.isOnlineMode || entityContainer.playables
        .hasCachedItems
    ) &&
      appDelegate.storage.settings.user.isPlayerShuffleButtonEnabled
    isMusicQueue = true
    isShowAlbum = false
    isShowArtist = false
    isAddToPlaylist = appDelegate.storage.settings.user.isOnlineMode
    isShowSongDetails = false
  }

  private func configureFor(genre: Genre) {
    isPlay = appDelegate.storage.settings.user.isOnlineMode || entityContainer.playables
      .hasCachedItems
    isShuffle = (
      appDelegate.storage.settings.user.isOnlineMode || entityContainer.playables
        .hasCachedItems
    ) &&
      appDelegate.storage.settings.user.isPlayerShuffleButtonEnabled
    isMusicQueue = true
    isShowAlbum = false
    isShowArtist = false
    isAddToPlaylist = appDelegate.storage.settings.user.isOnlineMode
    isShowSongDetails = false
  }

  private func configureFor(artist: Artist) {
    isPlay = appDelegate.storage.settings.user.isOnlineMode || entityContainer.playables
      .hasCachedItems
    isShuffle = (
      appDelegate.storage.settings.user.isOnlineMode || entityContainer.playables
        .hasCachedItems
    ) &&
      appDelegate.storage.settings.user.isPlayerShuffleButtonEnabled
    isMusicQueue = true
    isShowAlbum = false
    isShowArtist = false
    isAddToPlaylist = appDelegate.storage.settings.user.isOnlineMode
    isShowSongDetails = false
  }

  private func configureFor(album: Album) {
    isPlay = appDelegate.storage.settings.user.isOnlineMode || entityContainer.playables
      .hasCachedItems
    isShuffle = (
      appDelegate.storage.settings.user.isOnlineMode || entityContainer.playables
        .hasCachedItems
    ) &&
      appDelegate.storage.settings.user.isPlayerShuffleButtonEnabled
    isMusicQueue = true
    isShowAlbum = false
    isShowArtist = !(rootView is ArtistDetailVC)
    isAddToPlaylist = appDelegate.storage.settings.user.isOnlineMode
    isShowSongDetails = false
  }

  private func configureFor(directory: Directory) {
    isPlay = appDelegate.storage.settings.user.isOnlineMode || entityContainer.playables
      .hasCachedItems
    isShuffle = (
      appDelegate.storage.settings.user.isOnlineMode || entityContainer.playables
        .hasCachedItems
    ) &&
      appDelegate.storage.settings.user.isPlayerShuffleButtonEnabled
    isMusicQueue = true
    isShowAlbum = false
    isShowArtist = false
    isAddToPlaylist = appDelegate.storage.settings.user.isOnlineMode && !entityContainer.playables
      .isEmpty
    isShowSongDetails = false
  }

  private func createPlayAction() -> UIAction {
    UIAction(title: L10n.tr("Play"), image: .play) { action in
      guard !self.entityPlayables.isEmpty else { return }
      if let playerIndex = self.playerIndexCb?() {
        self.appDelegate.player.play(playerIndex: playerIndex)
      } else if let context = self.playContextCb?() {
        self.appDelegate.player.play(context: context)
      } else {
        self.appDelegate.player.play(context: PlayContext(
          containable: self.entityContainer,
          playables: self.entityPlayables
        ))
      }
    }
  }

  private func createPlayShuffledAction() -> UIAction {
    UIAction(title: L10n.tr("Shuffle"), image: .shuffle) { action in
      guard !self.entityPlayables.isEmpty else { return }
      if let context = self.playContextCb?() {
        self.appDelegate.player.playShuffled(context: context)
      } else {
        self.appDelegate.player.playShuffled(context: PlayContext(
          containable: self.entityContainer,
          playables: self.entityPlayables
        ))
      }
    }
  }

  private func createInstantMixAction() -> UIAction {
    UIAction(title: L10n.tr("Instant Mix"), image: .instantMix) { [weak self] action in
      guard let self = self,
            let song = (entityContainer as? AbstractPlayable)?.asSong
      else { return }

      Task { @MainActor in
        await self.createAndPlayInstantMix(for: song)
      }
    }
  }

  private func createAndPlayInstantMix(for song: Song) async {
    do {
      // Get the library syncer for the song's account
      guard let account = song.account else {
        appDelegate.eventLogger.error(
          topic: "Instant Mix",
          statusCode: .commonError,
          message: L10n.tr("Song has no account"),
          displayPopup: true
        )
        return
      }

      let librarySyncer = appDelegate.getMeta(account.info).librarySyncer

      // Fetch similar songs from backend
      let similarSongs = try await librarySyncer.requestSimilarSongs(song: song, count: 99)

      if similarSongs.isEmpty {
        appDelegate.eventLogger.info(
          topic: "Instant Mix",
          message: L10n.tr("No similar songs found"),
          displayPopup: true
        )
        return
      }

      // Create playlist: seed song + similar songs
      let allSongs = [song] + similarSongs

      // Create play context and start playing
      let context = PlayContext(name: L10n.tr("Instant Mix: %@", song.title), playables: allSongs)
      appDelegate.player.play(context: context)

      appDelegate.eventLogger.info(
        topic: "Instant Mix",
        message: L10n.tr("Playing instant mix with %d songs", allSongs.count),
        displayPopup: true
      )

    } catch {
      appDelegate.eventLogger.report(topic: "Instant Mix", error: error)
    }
  }

  private func createMusicQueueAction() -> UIMenuElement {
    UIMenu(title: L10n.tr("Music Queue"), image: .listBullet, children: [
      UIAction(title: L10n.tr("Insert Context Queue"), image: .contextQueueInsert) { action in
        guard !self.entityPlayables.isEmpty else { return }
        self.appDelegate.player.insertContextQueue(playables: self.entityPlayables)
      },
      UIAction(title: L10n.tr("Append Context Queue"), image: .contextQueueAppend) { action in
        guard !self.entityPlayables.isEmpty else { return }
        self.appDelegate.player.appendContextQueue(playables: self.entityPlayables)
      },
      UIAction(title: L10n.tr("Insert User Queue"), image: .userQueueInsert) { action in
        guard !self.entityPlayables.isEmpty else { return }
        self.appDelegate.player.insertUserQueue(playables: self.entityPlayables)
      },
      UIAction(title: L10n.tr("Append User Queue"), image: .userQueueAppend) { action in
        guard !self.entityPlayables.isEmpty else { return }
        self.appDelegate.player.appendUserQueue(playables: self.entityPlayables)
      },
    ])
  }

  private func createFavoriteMenu(libraryEntity: AbstractLibraryEntity) -> UIAction {
    libraryEntity.isFavorite ?
      UIAction(title: L10n.tr("Unmark favorite"), image: .heartSlash) { action in self.toggleFavorite() } :
      UIAction(title: L10n.tr("Favorite"), image: .heartEmpty) { action in self.toggleFavorite() }
  }

  private func toggleFavorite() {
    guard appDelegate.storage.settings.user.isOnlineMode,
          let account = entityContainer.account else { return }
    Task { @MainActor in
      do {
        try await entityContainer
          .remoteToggleFavorite(
            syncer: self.appDelegate.getMeta(account.info)
              .librarySyncer
          )
      } catch {
        self.appDelegate.eventLogger.report(topic: "Toggle Favorite", error: error)
      }
      self.reloadRootView()
    }
  }

  private func createRatingMenu(libraryEntity: AbstractLibraryEntity) -> UIMenu {
    let rating = libraryEntity.rating == 0
      ? L10n.tr("Not rated")
      : L10n.tr(libraryEntity.rating > 1 ? "%d Stars" : "%d Star", libraryEntity.rating)
    let menuIcon = libraryEntity
      .rating == 0 ? UIImage.starEmpty : UIImage.starFill
    let children = [
      UIAction(title: L10n.tr("No Rating"), image: .ban) { action in self.setRating(rating: 0) },
      UIAction(
        title: L10n.tr("%d Star", 1),
        image: libraryEntity.rating >= 1 ? .starFill : .starEmpty
      ) { action in
        self.setRating(rating: 1)
      },
      UIAction(
        title: L10n.tr("%d Stars", 2),
        image: libraryEntity.rating >= 2 ? .starFill : .starEmpty
      ) { action in self
        .setRating(rating: 2)
      },
      UIAction(
        title: L10n.tr("%d Stars", 3),
        image: libraryEntity.rating >= 3 ? .starFill : .starEmpty
      ) { action in self
        .setRating(rating: 3)
      },
      UIAction(
        title: L10n.tr("%d Stars", 4),
        image: libraryEntity.rating >= 4 ? .starFill : .starEmpty
      ) { action in self
        .setRating(rating: 4)
      },
      UIAction(
        title: L10n.tr("%d Stars", 5),
        image: libraryEntity.rating >= 5 ? .starFill : .starEmpty
      ) { action in self
        .setRating(rating: 5)
      },
    ]

    return UIMenu(
      title: L10n.tr("Rating: %@", rating),
      image: menuIcon,
      options: .displayAsPalette,
      children: children
    )
  }

  private func setRating(rating: Int) {
    guard appDelegate.storage.settings.user.isOnlineMode,
          let account = entityContainer.account else { return }
    if let song = (entityContainer as? AbstractPlayable)?.asSong {
      song.rating = rating
      appDelegate.storage.main.saveContext()
      Task { @MainActor in do {
        try await self.appDelegate.getMeta(account.info).librarySyncer.setRating(
          song: song,
          rating: rating
        )
      } catch {
        self.appDelegate.eventLogger.report(topic: "Song Rating Sync", error: error)
      }}
    } else if let album = entityContainer as? Album {
      album.rating = rating
      appDelegate.storage.main.saveContext()
      Task { @MainActor in do {
        try await self.appDelegate.getMeta(account.info).librarySyncer.setRating(
          album: album,
          rating: rating
        )
      } catch {
        self.appDelegate.eventLogger.report(topic: "Album Rating Sync", error: error)
      }}
    } else if let artist = entityContainer as? Artist {
      artist.rating = rating
      appDelegate.storage.main.saveContext()
      Task { @MainActor in do {
        try await self.appDelegate.getMeta(account.info).librarySyncer.setRating(
          artist: artist,
          rating: rating
        )
      } catch {
        self.appDelegate.eventLogger.report(topic: "Artist Rating Sync", error: error)
      }}
    }
  }

  private func createAddToPlaylistAction() -> UIAction {
    UIAction(title: L10n.tr("Add to Playlist"), image: .playlistPlus) { action in
      guard !self.entityPlayables.isEmpty,
            let account = self.entityContainer.account else { return }
      let selectPlaylistVC = AppStoryboard.Main
        .segueToPlaylistSelector(account: account, itemsToAdd: self.entityPlayables.filterSongs())
      let selectPlaylistNav = UINavigationController(rootViewController: selectPlaylistVC)
      self.rootView.present(selectPlaylistNav, animated: true)
    }
  }

  private func createShowAlbumAction() -> UIAction {
    UIAction(title: L10n.tr("Show Album"), image: .album) { action in
      self.showAlbum()
    }
  }

  private func showAlbum() {
    let playable = entityContainer as? AbstractPlayable
    let album = playable?.asSong?.album
    guard let album = album, let account = album.account else { return }
    appDelegate.userStatistics.usedAction(.alertGoToAlbum)
    let albumDetailVC = AppStoryboard.Main.segueToAlbumDetail(
      account: account,
      album: album,
      songToScrollTo: playable?.asSong
    )
    if let popupPlayer = rootView as? PopupPlayerVC {
      popupPlayer.closePopupPlayerAndDisplayInLibraryTab(vc: albumDetailVC)
    } else if let navController = rootView.navigationController {
      navController.pushViewController(albumDetailVC, animated: true)
    } else {
      guard let hostingSplitVC = AppDelegate.mainWindowHostVC else { return }
      hostingSplitVC.pushNavLibrary(vc: albumDetailVC)
    }
  }

  private func createShowArtistAction() -> UIAction {
    UIAction(title: L10n.tr("Show Artist"), image: .artist) { action in
      self.showArtist()
    }
  }

  private func showArtist() {
    let playable = entityContainer as? AbstractPlayable
    let album = entityContainer as? Album
    if let artist = playable?.asSong?.artist ?? album?.artist, let account = artist.account {
      appDelegate.userStatistics.usedAction(.alertGoToArtist)
      let artistDetailVC = AppStoryboard.Main.segueToArtistDetail(
        account: account,
        artist: artist,
        albumToScrollTo: album
      )
      if let popupPlayer = rootView as? PopupPlayerVC {
        popupPlayer.closePopupPlayerAndDisplayInLibraryTab(vc: artistDetailVC)
      } else if let navController = rootView.navigationController {
        navController.pushViewController(artistDetailVC, animated: true)
      } else {
        guard let hostingSplitVC = AppDelegate.mainWindowHostVC else { return }
        hostingSplitVC.pushNavLibrary(vc: artistDetailVC)
      }
    }
  }

  private func createDownloadAction() -> UIAction {
    UIAction(title: L10n.tr("Download"), image: .download) { action in
      if !self.entityPlayables.isEmpty,
         let accountInfo = self.entityPlayables.first?.account?.info {
        self.appDelegate.getMeta(accountInfo).playableDownloadManager
          .download(objects: self.entityPlayables)
      }
    }
  }

  private func createDeleteCacheAction() -> UIAction {
    UIAction(title: L10n.tr("Delete Cache"), image: .trash) { action in
      guard self.entityPlayables.hasCachedItems,
            let account = self.entityContainer.account else { return }

      let alert = UIAlertController(
        title: nil,
        message: self.entityPlayables.count > 1
          ? L10n.tr("Are you sure to delete the cached files?")
          : L10n.tr("Are you sure to delete the cached file?"),
        preferredStyle: .alert
      )
      alert.addAction(UIAlertAction(title: L10n.tr("Delete"), style: .destructive, handler: { _ in
        self.appDelegate.getMeta(account.info).playableDownloadManager
          .removeFinishedDownload(for: self.entityPlayables)
        self.appDelegate.storage.main.library.deleteCache(of: self.entityPlayables)
        self.appDelegate.storage.main.saveContext()
        self.reloadRootView()
      }))
      alert.addAction(UIAlertAction(title: L10n.tr("Cancel"), style: .cancel, handler: { _ in
        // do nothing
      }))
      self.rootView.present(alert, animated: true, completion: nil)
    }
  }

  private func createShareAction(playable: AbstractPlayable) -> UIAction {
    UIAction(
      title: L10n.tr("Share"),
      image: UIImage(systemName: "square.and.arrow.up")
    ) { [weak self] _ in
      // Used if the song is not cached, otherwise never called
      let downloadManagerProvider: () -> DownloadManageable? = { [weak self] in
        guard let self, let accountInfo = playable.account?.info
        else { return nil }
        return appDelegate
          .getMeta(accountInfo)
          .playableDownloadManager
      }

      guard let self else { return }
      // Note: This is strongly coupled, I could protocolize and inject. But this is simplest and the project doesn't seem to do DI/tests for this target.
      ShareSongAction.share(
        playable: playable,
        from: rootView.view,
        presenter: rootView,
        downloadManagerProvider: downloadManagerProvider
      )
    }
  }

  private func createShowLyricsAction(song: Song) -> UIAction? {
    guard let playable = entityContainer as? AbstractPlayable,
          let song = playable.asSong,
          let lyricsRelFilePath = song.lyricsRelFilePath,
          let lyricsAccount = song.account
    else { return nil }

    return UIAction(title: L10n.tr("Show Lyrics"), image: .lyrics) { action in
      self.showLyrics(lyricsRelFilePath: lyricsRelFilePath, lyricsAccount: lyricsAccount)
    }
  }

  private func showLyrics(lyricsRelFilePath: URL, lyricsAccount: Account) {
    let lyricsVC = PlainDetailsVC()
    lyricsVC.display(
      lyricsRelFilePath: lyricsRelFilePath,
      lyricsAccount: lyricsAccount,
      on: rootView
    )
    rootView.present(lyricsVC, animated: true)
  }

  private func createCopyIdToClipboardAction() -> UIMenu {
    UIMenu(
      options: .displayInline,
      children: [UIAction(title: L10n.tr("Copy ID to Clipboard"), image: .clipboard) { action in
        if !self.entityContainer.id.isEmpty {
          UIPasteboard.general.string = self.entityContainer.id
        }
      }]
    )
  }

  private func reloadRootView() {
    if let rootTableView = rootView as? UITableViewController {
      rootTableView.tableView.reloadData()
    } else if let popupPlayer = rootView as? PopupPlayerVC {
      popupPlayer.tableView.reloadData()
    }
    if let splitVC = rootView as? SplitVC,
       let queueVC = splitVC.viewController(for: .inspector) as? QueueVC {
      queueVC.tableView?.reloadData()
    }
  }
}

// MARK: - EntityPreviewVC

class EntityPreviewVC: UIViewController {
  override var sceneTitle: String? { entityContainer?.name }

  static let margin = UIEdgeInsets(
    top: UIView.defaultMarginX,
    left: UIView.defaultMarginX,
    bottom: UIView.defaultMarginX,
    right: UIView.defaultMarginX
  )

  @IBOutlet
  weak var titleLabel: MarqueeLabel!
  @IBOutlet
  weak var artistLabel: MarqueeLabel!
  @IBOutlet
  weak var infoLabel: MarqueeLabel!
  @IBOutlet
  weak var entityImageView: EntityImageView!
  @IBOutlet
  weak var gotoDetailsSymbol: UIImageView!

  private var rootView: UIViewController?
  private var entityContainer: PlayableContainable?

  var isNavigationDisallowed: Bool {
    ((entityContainer as? AbstractPlayable)?.isSong ?? false) && (rootView is AlbumDetailVC)
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.setBackgroundBlur(style: .prominent)
    titleLabel.applyAmperfyStyle()
    artistLabel.applyAmperfyStyle()
    infoLabel.applyAmperfyStyle()
    gotoDetailsSymbol.isHidden = isNavigationDisallowed

    // The preview will size to the preferredContentSize, which can be useful
    // for displaying a preview with the dimension of an image, for example.
    // Unlike peek and pop, it doesn't seem to automatically scale down for you.

    if traitCollection.userInterfaceIdiom == .phone {
      preferredContentSize = CGSize(
        width: view.bounds.width,
        height: 150 + Self.margin.top + Self.margin.bottom
      )
    } else if traitCollection.userInterfaceIdiom == .pad {
      preferredContentSize = CGSize(
        width: view.bounds.width,
        height: 190 + Self.margin.top + Self.margin.bottom
      )
    } else {
      preferredContentSize = CGSize(
        width: view.bounds.width,
        height: 190 + Self.margin.top + Self.margin.bottom
      )
    }
  }

  override func viewIsAppearing(_ animated: Bool) {
    refresh()
  }

  func display(container: PlayableContainable, on rootView: UIViewController) {
    self.rootView = rootView
    entityContainer = container
  }

  func refresh() {
    guard let entityContainer = entityContainer else { return }
    entityImageView.display(
      theme: appDelegate.storage.settings.accounts.getSetting(entityContainer.account?.info).read
        .themePreference,
      container: entityContainer
    )
    titleLabel.text = entityContainer.name
    artistLabel.text = entityContainer.subtitle
    artistLabel.isHidden = entityContainer.subtitle == nil
    infoLabel.text = entityContainer.info(
      for: entityContainer.account?.apiType.asServerApiType,
      details: DetailInfoType(type: .long, settings: appDelegate.storage.settings)
    )
  }
}
