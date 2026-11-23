//
//  SearchViewController.swift
//  fmusic-macOS
//
//  Library search page, modelled on the Catalyst `SearchVC`: the search field lives
//  in the content toolbar, the body shows search history / a content-unavailable
//  empty state, and results are grouped into artist / album / song / playlist
//  sections with artwork rows.
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
import fmusicKit

@MainActor
final class SearchViewController: NSViewController, NSTableViewDataSource,
  NSTableViewDelegate {
  private enum Row {
    case header(String)
    case history(String)
    case artist(Artist)
    case album(Album)
    case song(Song)
    case playlist(Playlist)
  }

  private let tableView = NSTableView()
  private let scrollView = NSScrollView()
  private let emptyIconView = NSImageView()
  private let emptyLabel = NSTextField(labelWithString: "")
  private let emptyDetailLabel = NSTextField(wrappingLabelWithString: "")

  private var query = ""
  private var rows: [Row] = []
  private var pendingSearch: DispatchWorkItem?

  private var player: PlayerFacade { FmusicKit.shared.player }
  private var storage: PersistentStorage { FmusicKit.shared.storage }

  // MARK: - Lifecycle

  override func loadView() {
    // Same warm grey page surface as the other library pages (Catalyst paints the
    // whole window body with the base background; only the toolbar is white).
    let root = ThemedBackgroundView()

    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("search"))
    column.resizingMask = .autoresizingMask
    tableView.addTableColumn(column)
    tableView.headerView = nil
    tableView.rowHeight = 56
    tableView.backgroundColor = .clear
    tableView.selectionHighlightStyle = .none
    tableView.dataSource = self
    tableView.delegate = self
    tableView.target = self
    tableView.doubleAction = #selector(rowDoubleClicked)

    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.drawsBackground = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.isHidden = true

    // UIContentUnavailableConfiguration.empty() uses title2 (22 pt semibold) for the
    // text and the body style for the secondary text.
    emptyLabel.font = .systemFont(ofSize: 22, weight: .semibold)
    emptyLabel.textColor = MacTheme.secondaryTextColor
    emptyLabel.alignment = .center
    emptyLabel.translatesAutoresizingMaskIntoConstraints = false

    emptyDetailLabel.font = .systemFont(ofSize: 13)
    emptyDetailLabel.textColor = MacTheme.secondaryTextColor
    emptyDetailLabel.alignment = .center
    emptyDetailLabel.translatesAutoresizingMaskIntoConstraints = false

    emptyIconView.image = NSImage(
      systemSymbolName: "clock",
      accessibilityDescription: nil
    )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 36, weight: .regular))
    emptyIconView.contentTintColor = MacTheme.secondaryTextColor
    emptyIconView.translatesAutoresizingMaskIntoConstraints = false

    root.addSubview(scrollView)
    root.addSubview(emptyIconView)
    root.addSubview(emptyLabel)
    root.addSubview(emptyDetailLabel)

    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
      scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

      // Catalyst centres the whole block (icon + title + detail) slightly above the
      // content centre: title centre −13.5 pt, icon ink 30 pt above the title and the
      // detail ink 17.5 pt below it (measured from the original window).
      emptyIconView.centerXAnchor.constraint(equalTo: root.centerXAnchor),
      emptyIconView.bottomAnchor.constraint(equalTo: emptyLabel.topAnchor, constant: -28),

      emptyLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
      emptyLabel.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: -14),
      emptyLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 460),

      emptyDetailLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
      emptyDetailLabel.topAnchor.constraint(equalTo: emptyLabel.bottomAnchor, constant: 14),
      emptyDetailLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 460),
    ])

    self.view = root
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(libraryChanged),
      name: .librarySongsSynced,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(libraryChanged),
      name: .accountActiveChanged,
      object: nil
    )
    reloadResults()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  // MARK: - Searching

  @objc
  private func libraryChanged() {
    reloadResults()
  }

  private func reloadResults() {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let accountInfo = storage.settings.accounts.active else {
      showEmptyState(
        L10n.tr("No Search History"),
        detail: L10n.tr("Your search history will appear here.")
      )
      return
    }
    let account = storage.main.library.getAccount(info: accountInfo)
    let library = storage.main.library

    guard !trimmed.isEmpty else {
      let history = library.getSearchHistory(for: account)
      if history.isEmpty {
        showEmptyState(
          L10n.tr("No Search History"),
          detail: L10n.tr("Your search history will appear here.")
        )
      } else {
        var rows: [Row] = [.header(L10n.tr("Recent Searches"))]
        rows += history.compactMap { item -> Row? in
          guard let containable = item.searchedPlayableContainable else { return nil }
          let text = (containable as? AbstractPlayable)?.title ?? containable.name
          return text.isEmpty ? nil : .history(text)
        }
        show(rows: rows)
      }
      return
    }

    let artists = library.searchArtists(
      for: account,
      searchText: trimmed,
      onlyCached: false,
      displayFilter: .all
    )
    let albums = library.searchAlbums(
      for: account,
      searchText: trimmed,
      onlyCached: false,
      displayFilter: .all
    )
    let songs = library.searchSongs(
      for: account,
      searchText: trimmed,
      onlyCached: false,
      displayFilter: .all
    )
    let playlists = library.searchPlaylists(
      for: account,
      searchText: trimmed,
      playlistSearchCategory: .all
    )

    var rows: [Row] = []
    if !artists.isEmpty {
      rows.append(.header(L10n.tr("Artists")))
      rows += artists.map(Row.artist)
    }
    if !albums.isEmpty {
      rows.append(.header(L10n.tr("Albums")))
      rows += albums.map(Row.album)
    }
    if !playlists.isEmpty {
      rows.append(.header(L10n.tr("Playlists")))
      rows += playlists.map(Row.playlist)
    }
    if !songs.isEmpty {
      rows.append(.header(L10n.tr("Songs")))
      rows += songs.map(Row.song)
    }
    if rows.isEmpty {
      showEmptyState(L10n.tr("No Results"))
    } else {
      show(rows: rows)
    }

    // Lyrics are stored as sidecar files, so they cannot be part of the Core Data
    // predicate. Scan them off the main thread and append a "Lyrics" section.
    let knownSongIDs = Set(songs.map(\.identifier))
    Task { [weak self] in
      await self?.searchLyrics(
        query: trimmed,
        accountInfo: accountInfo,
        excluding: knownSongIDs,
        baseRows: rows
      )
    }
  }

  /// Scans every song's lyric sidecar for `query`, then appends matching songs
  /// under a "Lyrics" header (ignoring stale results once the query changed).
  private func searchLyrics(
    query: String,
    accountInfo: AccountInfo,
    excluding knownSongIDs: Set<String>,
    baseRows: [Row]
  ) async {
    let library = storage.main.library
    let account = library.getAccount(info: accountInfo)
    let allSongs = library.getSongs(for: account)
    var songsByID: [String: Song] = [:]
    var candidates: [(id: String, path: URL)] = []
    for song in allSongs {
      let id = song.identifier
      guard !id.isEmpty,
            !knownSongIDs.contains(id),
            let rel = song.lyricsRelFilePath,
            let abs = CacheFileManager.shared.getAbsolutefmusicPath(relFilePath: rel)
      else { continue }
      songsByID[id] = song
      candidates.append((id, abs))
    }
    guard !candidates.isEmpty else { return }

    let needle = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    let capturedQuery = query
    let matched: [String] = await Task.detached(priority: .userInitiated) {
      var result: [String] = []
      for candidate in candidates {
        guard let data = try? Data(contentsOf: candidate.path),
              let text = String(data: data, encoding: .utf8)
              ?? String(data: data, encoding: .utf16)
        else { continue }
        let folded = text.folding(
          options: [.caseInsensitive, .diacriticInsensitive],
          locale: .current
        )
        if folded.contains(needle) {
          result.append(candidate.id)
          if result.count >= 50 { break }
        }
      }
      return result
    }.value

    guard !matched.isEmpty,
          query.trimmingCharacters(in: .whitespacesAndNewlines) == capturedQuery
    else { return }
    let matchedSongs = matched.compactMap { songsByID[$0] }
    guard !matchedSongs.isEmpty else { return }
    var updated = baseRows
    updated.append(.header(L10n.tr("Lyrics")))
    updated += matchedSongs.map(Row.song)
    show(rows: updated)
  }

  private func show(rows: [Row]) {
    self.rows = rows
    scrollView.isHidden = false
    hideEmptyState()
    tableView.reloadData()
  }

  private func showEmptyState(_ text: String, detail: String? = nil) {
    rows = []
    tableView.reloadData()
    scrollView.isHidden = true
    emptyIconView.isHidden = false
    emptyIconView.image = NSImage(
      systemSymbolName: text == L10n.tr("No Results") ? "magnifyingglass" : "clock",
      accessibilityDescription: nil
    )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 36, weight: .regular))
    emptyLabel.stringValue = text
    emptyDetailLabel.stringValue = detail ?? ""
    emptyDetailLabel.isHidden = (detail ?? "").isEmpty
  }

  private func hideEmptyState() {
    emptyIconView.isHidden = true
    emptyLabel.isHidden = true
    emptyDetailLabel.isHidden = true
  }

  // MARK: - Actions

  @objc
  private func rowDoubleClicked() {
    openRow(at: tableView.clickedRow)
  }

  private func openRow(at index: Int) {
    guard rows.indices.contains(index) else { return }
    switch rows[index] {
    case .header:
      return
    case let .history(text):
      query = text
      reloadResults()
    case let .song(song):
      player.play(context: PlayContext(name: L10n.tr("Songs"), playables: [song]))
    case let .album(album):
      MainViewController.current?.openAlbum(album)
    case let .artist(artist):
      MainViewController.current?.openArtist(artist)
    case .playlist:
      return
    }
  }

  // MARK: - Table

  func numberOfRows(in tableView: NSTableView) -> Int {
    rows.count
  }

  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    if case .header = rows[row] { return 40 }
    // Catalyst PlayableTableCell/GenericTableCell: 48 pt content + 9 pt top/bottom
    // margins; PlaylistTableCell is taller (70 pt content) for its two-line layout.
    if case .playlist = rows[row] { return 88 }
    return 66
  }

  func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
    if case .header = rows[row] { return true }
    return false
  }

  func tableView(
    _ tableView: NSTableView,
    viewFor tableColumn: NSTableColumn?,
    row: Int
  )
    -> NSView? {
    switch rows[row] {
    case let .header(title):
      let label = NSTextField(labelWithString: title)
      label.font = .systemFont(ofSize: 13, weight: .semibold)
      label.textColor = MacTheme.secondaryTextColor
      let container = NSView()
      label.translatesAutoresizingMaskIntoConstraints = false
      container.addSubview(label)
      NSLayoutConstraint.activate([
        label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
        label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
      ])
      return container
    case let .history(text):
      return makeRowView(
        artwork: nil,
        title: text,
        subtitle: L10n.tr("Search History"),
        symbol: "clock.arrow.circlepath"
      )
    case let .artist(artist):
      return makeRowView(
        artwork: artworkImage(for: artist as AbstractLibraryEntity),
        title: artist.name,
        subtitle: L10n.tr("Artist")
      )
    case let .album(album):
      return makeRowView(
        artwork: artworkImage(for: album as AbstractLibraryEntity),
        title: album.name,
        subtitle: album.artist?.name ?? L10n.tr("Album")
      )
    case let .playlist(playlist):
      return makeRowView(
        artwork: nil,
        title: playlist.name,
        subtitle: L10n.tr("Playlist"),
        symbol: "music.note.list"
      )
    case let .song(song):
      let subtitle = [song.artist?.name, song.album?.name]
        .compactMap { $0 }
        .joined(separator: " · ")
      return makeRowView(
        artwork: artworkImage(for: song),
        title: song.title,
        subtitle: subtitle,
        duration: song.duration
      )
    }
  }

  private func artworkImage(for playable: AbstractPlayable) -> NSImage? {
    let setting = storage.settings.accounts.activeSetting.read
    return ArtworkImageLoader.image(
      for: playable,
      themePreference: setting.themePreference,
      artworkDisplayPreference: setting.artworkDisplayPreference
    )
  }

  private func artworkImage(for entity: AbstractLibraryEntity) -> NSImage {
    LMLibraryArtwork.image(
      for: entity,
      setting: storage.settings.accounts.activeSetting.read
    )
  }

  private func makeRowView(
    artwork: NSImage?,
    title: String,
    subtitle: String,
    symbol: String? = nil,
    duration: Int? = nil
  )
    -> NSView {
    let container = NSView()

    let artworkView = NSImageView()
    artworkView.imageScaling = .scaleProportionallyUpOrDown
    artworkView.wantsLayer = true
    artworkView.layer?.cornerRadius = 5
    artworkView.layer?.masksToBounds = true
    artworkView.translatesAutoresizingMaskIntoConstraints = false
    if let artwork {
      artworkView.image = artwork
    } else if let symbol {
      artworkView.image = NSImage(
        systemSymbolName: symbol,
        accessibilityDescription: nil
      )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .regular))
      artworkView.contentTintColor = MacTheme.secondaryTextColor
    }

    let titleLabel = NSTextField(labelWithString: title)
    titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
    titleLabel.lineBreakMode = .byTruncatingTail
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    let subtitleLabel = NSTextField(labelWithString: subtitle)
    subtitleLabel.font = .systemFont(ofSize: 11)
    subtitleLabel.textColor = MacTheme.secondaryTextColor
    subtitleLabel.lineBreakMode = .byTruncatingTail
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

    container.addSubview(artworkView)
    container.addSubview(titleLabel)
    container.addSubview(subtitleLabel)

    NSLayoutConstraint.activate([
      // Catalyst cells use a 20 pt horizontal margin (CommonScreenOperations.defaultMarginCellX).
      artworkView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
      artworkView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
      artworkView.widthAnchor.constraint(equalToConstant: 48),
      artworkView.heightAnchor.constraint(equalToConstant: 48),

      titleLabel.leadingAnchor.constraint(equalTo: artworkView.trailingAnchor, constant: 12),
      titleLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: container.trailingAnchor,
        constant: -20
      ),
      titleLabel.topAnchor.constraint(equalTo: artworkView.topAnchor, constant: 2),

      subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
      subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
    ])

    if let duration {
      let durationLabel = NSTextField(
        labelWithString: ClockTime(timeInSeconds: duration).asShortString()
      )
      durationLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
      durationLabel.textColor = MacTheme.secondaryTextColor
      durationLabel.translatesAutoresizingMaskIntoConstraints = false
      container.addSubview(durationLabel)
      NSLayoutConstraint.activate([
        durationLabel.trailingAnchor.constraint(
          equalTo: container.trailingAnchor,
          constant: -20
        ),
        durationLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        titleLabel.trailingAnchor.constraint(
          lessThanOrEqualTo: durationLabel.leadingAnchor,
          constant: -12
        ),
      ])
    }

    return container
  }
}

// MARK: - ContentSearchable

extension SearchViewController: ContentSearchable {
  var contentSearchPlaceholder: String? {
    L10n.tr("Search Library")
  }

  func contentSearchDidChange(text: String) {
    query = text
    // Debounce the four library queries so typing stays responsive.
    pendingSearch?.cancel()
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      reloadResults()
      return
    }
    let work = DispatchWorkItem { [weak self] in
      self?.reloadResults()
    }
    pendingSearch = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
  }
}
