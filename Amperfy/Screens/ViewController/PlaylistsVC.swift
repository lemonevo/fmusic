//
//  PlaylistsVC.swift
//  Amperfy
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

import AmperfyKit
import CoreData
import UIKit
import UniformTypeIdentifiers

// MARK: - PlaylistsDiffableDataSource

class PlaylistsDiffableDataSource: BasicUITableViewDiffableDataSource {
  override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
    // Return false if you do not want the item to be re-orderable.
    false
  }

  func playlistAt(indexPath: IndexPath) -> Playlist? {
    let objectID = itemIdentifier(for: indexPath)
    guard let objectID,
          let object = try? appDelegate.storage.main.context
          .existingObject(with: objectID),
          let playlistMO = object as? PlaylistMO
    else {
      return nil
    }

    let playlist = Playlist(
      library: appDelegate.storage.main.library,
      managedObject: playlistMO
    )
    return playlist
  }

  // Override to support editing the table view.
  override func tableView(
    _ tableView: UITableView,
    commit editingStyle: UITableViewCell.EditingStyle,
    forRowAt indexPath: IndexPath
  ) {
    guard editingStyle == .delete else { return }

    guard let playlist = playlistAt(indexPath: indexPath)
    else {
      return
    }

    let playlistId = playlist.id
    guard let account = playlist.account else { return }
    appDelegate.storage.main.library.deletePlaylist(playlist)
    appDelegate.storage.main.saveContext()

    guard !playlistId.isEmpty else { return }
    Task { @MainActor in do {
      try await self.appDelegate.getMeta(account.info).librarySyncer
        .syncUpload(playlistIdToDelete: playlistId)
    } catch {
      self.appDelegate.eventLogger.report(topic: "Playlist Upload Deletion", error: error)
    }}
  }
}

// MARK: - PlaylistsVC

class PlaylistsVC: SingleSnapshotFetchedResultsTableViewController<PlaylistMO> {
  override var sceneTitle: String? { L10n.tr("Playlists") }

  private var fetchedResultsController: PlaylistFetchedResultsController!
  private var optionsButton: UIBarButtonItem!
  private var sortType: PlaylistSortType = .name

  init(account: Account) {
    super.init(style: .plain, account: account)
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  override func createDiffableDataSource() -> BasicUITableViewDiffableDataSource {
    let source =
      PlaylistsDiffableDataSource(tableView: tableView) { tableView, indexPath, objectID -> UITableViewCell? in
        guard let object = try? self.appDelegate.storage.main.context
          .existingObject(with: objectID),
          let playlistMO = object as? PlaylistMO
        else {
          return UITableViewCell()
        }
        let playlist = Playlist(
          library: self.appDelegate.storage.main.library,
          managedObject: playlistMO
        )
        return self.createCell(tableView, forRowAt: indexPath, playlist: playlist)
      }
    return source
  }

  func playlistAt(indexPath: IndexPath) -> Playlist? {
    (diffableDataSource as? PlaylistsDiffableDataSource)?.playlistAt(indexPath: indexPath)
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    appDelegate.userStatistics.visited(.playlists)

    optionsButton = UIBarButtonItem.createSortBarButton()

    change(sortType: appDelegate.storage.settings.user.playlistsSortSetting)

    configureSearchController(
      placeholder: L10n.tr("Search in \"%@\"", L10n.tr("Playlists")),
      scopeButtonTitles: nil
    )
    setNavBarTitle(title: L10n.tr("Playlists"))
    tableView.register(nibName: PlaylistTableCell.typeName)
    tableView.reloadOnTextSizeChange { PlaylistTableCell.rowHeight }
    tableView.sectionFooterHeight = 0.0
    tableView.estimatedSectionFooterHeight = 0.0
    tableView.sectionHeaderHeight = 0.0
    tableView.estimatedSectionHeaderHeight = 0.0

    if #available(macCatalyst 27.0, *) {
      refreshControl = UIRefreshControl()
    }
    refreshControl?.addTarget(
      self,
      action: #selector(Self.handleRefresh),
      for: UIControl.Event.valueChanged
    )

    containableAtIndexPathCallback = { indexPath in
      self.playlistAt(indexPath: indexPath)
    }
    playContextAtIndexPathCallback = { indexPath in
      guard let entity = self.playlistAt(indexPath: indexPath) else { return nil }
      return PlayContext(containable: entity)
    }
    swipeCallback = { indexPath, completionHandler in
      guard let playlist = self.playlistAt(indexPath: indexPath) else { return }
      Task { @MainActor in
        do {
          try await playlist.fetch(
            storage: self.appDelegate.storage,
            librarySyncer: self.appDelegate.getMeta(self.account.info).librarySyncer,
            playableDownloadManager: self.appDelegate.getMeta(self.account.info)
              .playableDownloadManager
          )
        } catch {
          self.appDelegate.eventLogger.report(topic: "Playlist Sync", error: error)
        }
        completionHandler(SwipeActionContext(containable: playlist))
      }
    }
    snapshotDidChange = {
      self.updateContentUnavailable()
    }
  }

  func updateContentUnavailable() {
    if fetchedResultsController.fetchedObjects?.count ?? 0 == 0 {
      if fetchedResultsController.isSearchActive {
        contentUnavailableConfiguration = UIContentUnavailableConfiguration.localizedSearch()
      } else {
        contentUnavailableConfiguration = emptyContentConfig
      }
    } else {
      contentUnavailableConfiguration = nil
    }
  }

  lazy var emptyContentConfig: UIContentUnavailableConfiguration = {
    var config = UIContentUnavailableConfiguration.empty()
    config.image = .playlist
    config.text = L10n.tr("No Playlists")
    config.secondaryText = L10n.tr("Your playlists will appear here.")
    return config
  }()

  func change(sortType: PlaylistSortType) {
    self.sortType = sortType
    appDelegate.storage.settings.user.playlistsSortSetting = sortType
    singleFetchedResultsController?.clearResults()
    fetchedResultsController = PlaylistFetchedResultsController(
      coreDataCompanion: appDelegate.storage.main, account: account,
      sortType: sortType,
      isGroupedInAlphabeticSections: sortType.asSectionIndexType != .none
    )
    fetchedResultsController.fetchResultsController.sectionIndexType = sortType.asSectionIndexType
    singleFetchedResultsController = fetchedResultsController
    singleFetchedResultsController?.delegate = self
    singleFetchedResultsController?.fetch()
    tableView.reloadData()
    updateRightBarButtonItems()
    updateContentUnavailable()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.navigationBar.prefersLargeTitles = true
  }

  override func viewIsAppearing(_ animated: Bool) {
    super.viewIsAppearing(animated)
    extendSafeAreaToAccountForMiniPlayer()
    if appDelegate.storage.settings.user.isOfflineMode {
      isEditing = false
    }
    updateRightBarButtonItems()
    updateContentUnavailable()
    guard appDelegate.storage.settings.user.isOnlineMode else { return }
    Task { @MainActor in do {
      try await self.appDelegate.getMeta(self.account.info).librarySyncer
        .syncDownPlaylistsWithoutSongs()
    } catch {
      self.appDelegate.eventLogger.report(topic: "Playlists Sync", error: error)
    }}
  }

  func updateRightBarButtonItems() {
    var actions = [UIMenu]()
    actions.append(createSortButtonMenu())
    actions.append(createOptionsButtonMenu())
    optionsButton = UIBarButtonItem.createOptionsBarButton()
    optionsButton.menu = UIMenu(children: actions)
    var barButtons = [UIBarButtonItem]()
    barButtons.append(optionsButton)
    if appDelegate.storage.settings.user.isOnlineMode {
      barButtons.append(editButtonItem)
    }
    navigationItem.rightBarButtonItems = barButtons
  }

  func createCell(
    _ tableView: UITableView,
    forRowAt indexPath: IndexPath,
    playlist: Playlist
  )
    -> UITableViewCell {
    let cell: PlaylistTableCell = dequeueCell(for: tableView, at: indexPath)
    cell.display(playlist: playlist, rootView: self)
    return cell
  }

  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    guard let playlist = playlistAt(indexPath: indexPath) else { return }
    navigationController?.pushViewController(
      AppStoryboard.Main.segueToPlaylistDetail(account: account, playlist: playlist),
      animated: true
    )
  }

  private func createSortButtonMenu() -> UIMenu {
    let sortByName = UIAction(
      title: L10n.tr("Name"),
      image: sortType == .name ? .check : nil,
      handler: { _ in
        self.change(sortType: .name)
        self.updateSearchResults(for: self.searchController)
        self.appDelegate.notificationHandler.post(
          name: .fetchControllerSortChanged,
          object: nil,
          userInfo: nil
        )
      }
    )
    let sortByLastTimePlayed = UIAction(
      title: L10n.tr("Last time played"),
      image: sortType == .lastPlayed ? .check : nil,
      handler: { _ in
        self.change(sortType: .lastPlayed)
        self.updateSearchResults(for: self.searchController)
        self.appDelegate.notificationHandler.post(
          name: .fetchControllerSortChanged,
          object: nil,
          userInfo: nil
        )
      }
    )
    let sortByChangeDate = UIAction(
      title: L10n.tr("Change date"),
      image: sortType == .lastChanged ? .check : nil,
      handler: { _ in
        self.change(sortType: .lastChanged)
        self.updateSearchResults(for: self.searchController)
        self.appDelegate.notificationHandler.post(
          name: .fetchControllerSortChanged,
          object: nil,
          userInfo: nil
        )
      }
    )
    let sortByDuration = UIAction(
      title: L10n.tr("Duration"),
      image: sortType == .duration ? .check : nil,
      handler: { _ in
        self.change(sortType: .duration)
        self.updateSearchResults(for: self.searchController)
        self.appDelegate.notificationHandler.post(
          name: .fetchControllerSortChanged,
          object: nil,
          userInfo: nil
        )
      }
    )
    return UIMenu(
      title: L10n.tr("Sort"),
      image: .sort,
      options: [.displayInline],
      children: [sortByName, sortByLastTimePlayed, sortByChangeDate, sortByDuration]
    )
  }

  private func createOptionsButtonMenu() -> UIMenu {
    let fetchAllPlaylists = UIAction(title: L10n.tr("Sync All Playlists"), image: .refresh, handler: { _ in
      Task { @MainActor in do {
        let accountObjectId = self.account.managedObject.objectID
        let playlistsIds = try await self.appDelegate.storage.async
          .performAndGet { asyncCompanion in
            let accoundAsync = asyncCompanion.library.getAccount(managedObjectId: accountObjectId)
            let playlists = asyncCompanion.library.getPlaylists(for: accoundAsync)
            return playlists.compactMap { $0.managedObject.objectID }
          }
        for moId in playlistsIds {
          let playlistMainMO = self.appDelegate.storage.main.context
            .object(with: moId) as! PlaylistMO
          let playlistMain = Playlist(
            library: self.appDelegate.storage.main.library,
            managedObject: playlistMainMO
          )
          try await playlistMain.fetch(
            storage: self.appDelegate.storage,
            librarySyncer: self.appDelegate.getMeta(self.account.info).librarySyncer,
            playableDownloadManager: self.appDelegate.getMeta(self.account.info)
              .playableDownloadManager
          )
        }
        self.appDelegate.eventLogger.info(
          topic: L10n.tr("Sync All Playlists"),
          message: L10n.tr("All playlists have been synced.")
        )
      } catch {
        self.appDelegate.eventLogger.report(topic: "Sync All Playlists", error: error)
      }}
    })
    return UIMenu(
      title: L10n.tr("Options"),
      image: .sort,
      options: [.displayInline],
      children: [
        fetchAllPlaylists,
        UIAction(
          title: L10n.tr("Import M3U Playlist"),
          image: UIImage(systemName: "square.and.arrow.down"),
          handler: { _ in self.presentM3UImporter() }
        ),
      ]
    )
  }

  private func presentM3UImporter() {
    let types = ["m3u", "m3u8"].compactMap { UTType(filenameExtension: $0) }
    let picker = UIDocumentPickerViewController(
      forOpeningContentTypes: types.isEmpty ? [.plainText] : types,
      asCopy: true
    )
    picker.delegate = self
    present(picker, animated: true)
  }

  private func importM3U(from url: URL) {
    let isSecurityScoped = url.startAccessingSecurityScopedResource()
    defer { if isSecurityScoped { url.stopAccessingSecurityScopedResource() } }
    guard let data = try? Data(contentsOf: url),
          let content = String(data: data, encoding: .utf8)
          ?? String(data: data, encoding: .isoLatin1)
    else {
      presentM3UAlert(message: L10n.tr("The M3U file could not be read."))
      return
    }
    let entries = M3UCodec.parse(content)
    guard !entries.isEmpty else {
      presentM3UAlert(message: L10n.tr("No tracks found in this M3U file."))
      return
    }
    let library = appDelegate.storage.main.library
    let songs = library.getSongs(for: account)
    let result = M3UImportMatcher.match(entries: entries, songs: songs)
    guard !result.matches.isEmpty else {
      presentM3UAlert(message: L10n.tr("No matching songs found in the library."))
      return
    }
    let playlist = library.createPlaylist(account: account)
    let fileName = url.deletingPathExtension().lastPathComponent
    playlist.name = fileName.isEmpty ? L10n.tr("Imported Playlist") : fileName
    playlist.append(playables: result.matches)
    library.saveContext()
    presentM3UAlert(message: L10n.tr(
      "Imported %d songs. %d entries were skipped.",
      result.matches.count,
      result.unmatchedCount
    ))
  }

  private func presentM3UAlert(message: String) {
    let alert = UIAlertController(
      title: L10n.tr("M3U Import"),
      message: message,
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: L10n.tr("OK"), style: .default))
    present(alert, animated: true)
  }

  @objc
  func handleRefresh(refreshControl: UIRefreshControl) {
    Task { @MainActor in
      do {
        try await self.appDelegate.getMeta(self.account.info).librarySyncer
          .syncDownPlaylistsWithoutSongs()
      } catch {
        self.appDelegate.eventLogger.report(topic: "Playlists Sync", error: error)
      }
      self.refreshControl?.endRefreshing()
    }
  }

  override func updateSearchResults(for searchController: UISearchController) {
    let searchText = searchController.searchBar.text ?? ""
    let playlistSearchCategory = PlaylistSearchCategory(
      rawValue: searchController.searchBar
        .selectedScopeButtonIndex
    ) ?? PlaylistSearchCategory.defaultValue
    fetchedResultsController.search(
      searchText: searchText,
      playlistSearchCategory: playlistSearchCategory
    )
    tableView.reloadData()
    updateContentUnavailable()
  }
}

extension PlaylistsVC: UIDocumentPickerDelegate {
  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    guard let url = urls.first else { return }
    importM3U(from: url)
  }
}
