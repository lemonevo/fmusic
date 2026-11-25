//
//  LyricsSearchViewController.swift
//  fmusic-macOS
//
//  Pure-AppKit "歌词搜索" page: search the online lyrics providers through the
//  shared `OnlineLyricsService`, filter the results by provider, preview a result
//  and apply it to the current song (or another recent one from the player queue).
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

/// Sidebar `.lyricsSearch` page.
///
/// Strictly self-contained: the Lead only has to map the sidebar entry to
/// `LyricsSearchViewController()`; there is no toolbar or menu dependency.
@MainActor
final class LyricsSearchViewController: NSViewController, NSTableViewDataSource,
  NSTableViewDelegate, NSSearchFieldDelegate {
  // MARK: - Source filter

  /// `nil` is the "All Sources" entry, mirroring the Catalyst lyrics search filter.
  private static let sourceFilters: [OnlineLyricsSource?] = [nil, .netease, .qqmusic, .kugou]

  private static let durationColumnWidth: CGFloat = 60
  private static let sourceColumnWidth: CGFloat = 110

  // MARK: - Views

  private let titleLabel = NSTextField(labelWithString: L10n.tr("Lyrics Search"))
  private let searchField = NSSearchField()
  private let sourceControl = NSSegmentedControl()
  private let targetCaptionLabel = NSTextField(labelWithString: "")
  private let targetPopup = NSPopUpButton()
  private let searchThisSongButton = NSButton()
  private let statusLabel = NSTextField(labelWithString: "")
  private let spinner = NSProgressIndicator()
  private let resultsContainer = NSView()
  private let tableView = NSTableView()
  private let scrollView = NSScrollView()
  private let separator = NSBox()
  private let previewPane = LyricsSearchPreviewPane()

  private enum Column {
    static let title = NSUserInterfaceItemIdentifier("lyricsResultTitle")
    static let artist = NSUserInterfaceItemIdentifier("lyricsResultArtist")
    static let source = NSUserInterfaceItemIdentifier("lyricsResultSource")
    static let duration = NSUserInterfaceItemIdentifier("lyricsResultDuration")
  }

  // MARK: - State

  private var selectedSource: OnlineLyricsSource?
  private var results: [OnlineLyricsSearchResult] = []
  private var selectedResult: OnlineLyricsSearchResult?
  private var previewMatch: OnlineLyricsMatch?
  private var targetSongs: [Song] = []

  private var isSearching = false
  private var hasSearched = false
  private var lastAutoPrefill: String?
  private var didRunInitialSearch = false

  private var searchGeneration = 0
  private var searchTask: Task<Void, Never>?
  private var searchDebounceTask: Task<Void, Never>?
  private var previewTask: Task<Void, Never>?

  private var player: PlayerFacade { FmusicKit.shared.player }
  private var storage: PersistentStorage { FmusicKit.shared.storage }

  private var visibleResults: [OnlineLyricsSearchResult] {
    guard let selectedSource else { return results }
    return results.filter { $0.source == selectedSource }
  }

  private var currentSong: Song? { player.currentlyPlaying?.asSong }

  /// Song that "Apply Lyrics" writes to: the picker selection, falling back to the
  /// song that is currently playing.
  private var selectedTargetSong: Song? {
    guard targetPopup.isEnabled,
          targetSongs.indices.contains(targetPopup.indexOfSelectedItem)
    else { return nil }
    return targetSongs[targetPopup.indexOfSelectedItem]
  }

  // MARK: - Lifecycle

  override func loadView() {
    let root = NSView()
    root.wantsLayer = true

    titleLabel.font = MacTheme.largeTitleFont
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    configureSearchControls()
    configureTargetControls()
    configureStatusRow()
    configureResultsTable()
    configureContentLayout(in: root)
    configurePreviewPane()

    self.view = root
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    registerObservers()
    previewPane.onApply = { [weak self] in
      self?.applyPressed()
    }
    rebuildTargetSongs()
    updateStatus()
  }

  override func viewDidAppear() {
    super.viewDidAppear()
    rebuildTargetSongs()
    runInitialSearchIfNeeded()
  }

  deinit {
    searchTask?.cancel()
    searchDebounceTask?.cancel()
    previewTask?.cancel()
    NotificationCenter.default.removeObserver(self)
  }

  // MARK: - View configuration

  private func configureSearchControls() {
    searchField.placeholderString = L10n.tr("Search lyrics by song or artist")
    // Only search on Return from the field itself; typing is debounced through
    // `controlTextDidChange` so a keystroke cannot trigger two network searches.
    searchField.sendsSearchStringImmediately = false
    searchField.sendsWholeSearchString = true
    searchField.delegate = self
    searchField.target = self
    searchField.action = #selector(searchFieldAction)
    searchField.translatesAutoresizingMaskIntoConstraints = false
    searchField.widthAnchor.constraint(equalToConstant: 280).isActive = true

    let labels = Self.sourceFilters.map { source -> String in
      source?.displayName ?? L10n.tr("All Sources")
    }
    sourceControl.segmentCount = labels.count
    sourceControl.trackingMode = .selectOne
    sourceControl.segmentDistribution = .fillEqually
    for (index, label) in labels.enumerated() {
      sourceControl.setLabel(label, forSegment: index)
      sourceControl.setWidth(86, forSegment: index)
    }
    sourceControl.selectedSegment = 0
    sourceControl.target = self
    sourceControl.action = #selector(sourceFilterChanged)
    sourceControl.translatesAutoresizingMaskIntoConstraints = false
  }

  private func configureTargetControls() {
    // `Apply to: %@` is the only localized "apply to" string the shared table has;
    // formatting it without a song yields a clean caption in both languages.
    targetCaptionLabel.stringValue = L10n
      .tr("Apply to: %@", "")
      .trimmingCharacters(in: .whitespaces)
    targetCaptionLabel.font = MacTheme.secondaryFont
    targetCaptionLabel.textColor = MacTheme.secondaryTextColor
    targetCaptionLabel.translatesAutoresizingMaskIntoConstraints = false

    targetPopup.target = self
    targetPopup.action = #selector(targetSongChanged)
    targetPopup.translatesAutoresizingMaskIntoConstraints = false
    targetPopup.widthAnchor.constraint(equalToConstant: 280).isActive = true
    targetPopup.toolTip = L10n.tr("Apply Lyrics")

    searchThisSongButton.title = L10n.tr("Search this song")
    searchThisSongButton.bezelStyle = .rounded
    searchThisSongButton.target = self
    searchThisSongButton.action = #selector(searchSelectedSong)
    searchThisSongButton.translatesAutoresizingMaskIntoConstraints = false
  }

  private func configureStatusRow() {
    statusLabel.font = MacTheme.secondaryFont
    statusLabel.textColor = MacTheme.secondaryTextColor
    statusLabel.translatesAutoresizingMaskIntoConstraints = false

    spinner.style = .spinning
    spinner.controlSize = .small
    spinner.isDisplayedWhenStopped = false
    spinner.translatesAutoresizingMaskIntoConstraints = false
  }

  private func configureResultsTable() {
    let titleColumn = NSTableColumn(identifier: Column.title)
    titleColumn.title = L10n.tr("Title")
    titleColumn.width = 240
    titleColumn.minWidth = 140

    let artistColumn = NSTableColumn(identifier: Column.artist)
    artistColumn.title = L10n.tr("Artist")
    artistColumn.width = 160
    artistColumn.minWidth = 100

    let sourceColumn = NSTableColumn(identifier: Column.source)
    sourceColumn.title = L10n.tr("Source")
    sourceColumn.width = Self.sourceColumnWidth
    sourceColumn.minWidth = Self.sourceColumnWidth
    sourceColumn.maxWidth = Self.sourceColumnWidth

    let durationColumn = NSTableColumn(identifier: Column.duration)
    durationColumn.title = L10n.tr("Duration")
    durationColumn.width = Self.durationColumnWidth
    durationColumn.minWidth = Self.durationColumnWidth
    durationColumn.maxWidth = 80

    [titleColumn, artistColumn, sourceColumn, durationColumn]
      .forEach(tableView.addTableColumn)

    tableView.rowHeight = 36
    tableView.style = .fullWidth
    tableView.selectionHighlightStyle = .regular
    tableView.allowsMultipleSelection = false
    tableView.allowsEmptySelection = true
    tableView.usesAlternatingRowBackgroundColors = false
    tableView.backgroundColor = .clear
    tableView.gridStyleMask = []
    tableView.dataSource = self
    tableView.delegate = self
    tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    tableView.translatesAutoresizingMaskIntoConstraints = false

    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.drawsBackground = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false
  }

  private func configureContentLayout(in root: NSView) {
    resultsContainer.translatesAutoresizingMaskIntoConstraints = false
    resultsContainer.addSubview(scrollView)

    separator.boxType = .separator
    separator.translatesAutoresizingMaskIntoConstraints = false

    root.addSubview(titleLabel)
    root.addSubview(searchField)
    root.addSubview(sourceControl)
    root.addSubview(targetCaptionLabel)
    root.addSubview(targetPopup)
    root.addSubview(searchThisSongButton)
    root.addSubview(spinner)
    root.addSubview(statusLabel)
    root.addSubview(resultsContainer)
    root.addSubview(separator)
    root.addSubview(previewPane)
    previewPane.translatesAutoresizingMaskIntoConstraints = false

    let resultsWidth = resultsContainer.widthAnchor.constraint(
      equalTo: root.widthAnchor,
      multiplier: 0.46
    )
    resultsWidth.priority = .defaultHigh

    NSLayoutConstraint.activate([
      titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
      titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),

      searchField.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      searchField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),

      sourceControl.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 12),
      sourceControl.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
      sourceControl.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -24),

      targetCaptionLabel.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
      targetCaptionLabel.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 14),

      targetPopup.leadingAnchor.constraint(equalTo: targetCaptionLabel.trailingAnchor, constant: 8),
      targetPopup.centerYAnchor.constraint(equalTo: targetCaptionLabel.centerYAnchor),

      searchThisSongButton.leadingAnchor.constraint(
        equalTo: targetPopup.trailingAnchor,
        constant: 10
      ),
      searchThisSongButton.centerYAnchor.constraint(equalTo: targetCaptionLabel.centerYAnchor),
      searchThisSongButton.trailingAnchor.constraint(
        lessThanOrEqualTo: root.trailingAnchor,
        constant: -24
      ),

      spinner.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
      spinner.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
      spinner.widthAnchor.constraint(equalToConstant: 16),
      spinner.heightAnchor.constraint(equalToConstant: 16),

      statusLabel.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 8),
      statusLabel.topAnchor.constraint(equalTo: targetCaptionLabel.bottomAnchor, constant: 14),
      statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -24),

      resultsContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
      resultsContainer.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 10),
      resultsContainer.bottomAnchor.constraint(
        equalTo: root.bottomAnchor,
        constant: -(MacTheme.playerBarHeight + 24)
      ),
      resultsWidth,
      resultsContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 320),

      scrollView.topAnchor.constraint(equalTo: resultsContainer.topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: resultsContainer.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: resultsContainer.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: resultsContainer.bottomAnchor),

      separator.leadingAnchor.constraint(equalTo: resultsContainer.trailingAnchor, constant: 14),
      separator.topAnchor.constraint(equalTo: resultsContainer.topAnchor),
      separator.bottomAnchor.constraint(equalTo: resultsContainer.bottomAnchor),
      separator.widthAnchor.constraint(equalToConstant: 1),

      previewPane.leadingAnchor.constraint(equalTo: separator.trailingAnchor, constant: 16),
      previewPane.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
      previewPane.topAnchor.constraint(equalTo: resultsContainer.topAnchor),
      previewPane.bottomAnchor.constraint(equalTo: resultsContainer.bottomAnchor),
    ])
  }

  private func configurePreviewPane() {
    previewPane.showPlaceholder()
  }

  // MARK: - Observers

  private func registerObservers() {
    let center = NotificationCenter.default
    center.addObserver(
      self,
      selector: #selector(playerDidChange),
      name: .playerPlay,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(playerDidChange),
      name: .playerStop,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(offlineModeChanged),
      name: .offlineModeChanged,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(targetSongsMayHaveChanged),
      name: .librarySongsSynced,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(targetSongsMayHaveChanged),
      name: .accountActiveChanged,
      object: nil
    )
  }

  @objc
  private func playerDidChange() {
    rebuildTargetSongs()
    // Keep the search field in sync while it still holds the auto-filled song.
    let previousPrefill = lastAutoPrefill
    let newPrefill = currentSongQuery()
    lastAutoPrefill = newPrefill
    if let previousPrefill, previousPrefill == searchField.stringValue,
       let newPrefill, !newPrefill.isEmpty {
      searchField.stringValue = newPrefill
    }
  }

  @objc
  private func offlineModeChanged() {
    updateStatus()
  }

  @objc
  private func targetSongsMayHaveChanged() {
    rebuildTargetSongs()
  }

  // MARK: - Initial search

  private func runInitialSearchIfNeeded() {
    guard !didRunInitialSearch else { return }
    didRunInitialSearch = true

    let query = currentSongQuery() ?? ""
    guard !query.isEmpty else {
      updateStatus()
      return
    }
    searchField.stringValue = query
    lastAutoPrefill = query
    performSearch(keyword: query)
  }

  private func currentSongQuery() -> String? {
    guard let song = currentSong else { return nil }
    let parts = [song.title, song.creatorName]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard !parts.isEmpty else { return nil }
    return parts.joined(separator: " ")
  }

  // MARK: - Search

  @objc
  private func searchFieldAction() {
    searchDebounceTask?.cancel()
    performSearch(keyword: searchField.stringValue)
  }

  func controlTextDidChange(_ notification: Notification) {
    let keyword = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    searchDebounceTask?.cancel()

    guard keyword.count >= 2 else {
      searchTask?.cancel()
      searchGeneration &+= 1
      isSearching = false
      hasSearched = false
      results = []
      tableView.reloadData()
      select(result: nil)
      updateStatus()
      return
    }

    searchDebounceTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(400))
      guard let self, !Task.isCancelled else { return }
      self.performSearch(keyword: keyword)
    }
  }

  private func performSearch(keyword: String) {
    let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count >= 2 else {
      updateStatus()
      return
    }
    guard storage.settings.user.isOnlineMode else {
      searchTask?.cancel()
      searchGeneration &+= 1
      isSearching = false
      hasSearched = true
      results = []
      tableView.reloadData()
      select(result: nil)
      updateStatus()
      return
    }

    searchDebounceTask?.cancel()
    searchTask?.cancel()
    searchGeneration &+= 1
    let generation = searchGeneration

    isSearching = true
    hasSearched = true
    results = []
    tableView.reloadData()
    select(result: nil)
    updateStatus()

    searchTask = Task { @MainActor [weak self] in
      let found = await OnlineLyricsService.shared.searchLyrics(keyword: trimmed)
      guard let self,
            !Task.isCancelled,
            self.searchGeneration == generation
      else { return }
      self.results = found
      self.isSearching = false
      self.tableView.reloadData()
      self.updateStatus()
      if let first = self.visibleResults.first {
        self.tableView.selectRowIndexes(
          IndexSet(integer: 0),
          byExtendingSelection: false
        )
        self.select(result: first)
      } else {
        self.select(result: nil)
      }
    }
  }

  @objc
  private func sourceFilterChanged() {
    let index = sourceControl.selectedSegment
    selectedSource = Self.sourceFilters.indices.contains(index)
      ? Self.sourceFilters[index]
      : nil
    tableView.reloadData()

    if let selectedResult,
       let row = visibleResults.firstIndex(where: { $0.id == selectedResult.id }) {
      tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    } else if let first = visibleResults.first {
      tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
      select(result: first)
    } else {
      select(result: nil)
    }
    updateStatus()
  }

  @objc
  private func searchSelectedSong() {
    guard let song = selectedTargetSong ?? currentSong else { return }
    let query = [song.title, song.creatorName]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    guard !query.isEmpty else { return }
    searchField.stringValue = query
    lastAutoPrefill = nil
    performSearch(keyword: query)
  }

  private func updateStatus() {
    let isOnline = storage.settings.user.isOnlineMode
    spinner.isHidden = !isSearching
    if isSearching {
      spinner.startAnimation(nil)
    } else {
      spinner.stopAnimation(nil)
    }

    if isSearching {
      statusLabel.stringValue = L10n.tr("Searching lyrics…")
      return
    }
    guard isOnline else {
      statusLabel.stringValue = L10n.tr(
        "Online lyrics search is unavailable in offline mode."
      )
      return
    }
    guard hasSearched else {
      statusLabel.stringValue = L10n.tr("Enter a song or artist to search.")
      return
    }
    guard !results.isEmpty else {
      statusLabel.stringValue = L10n.tr("No lyrics found.")
      return
    }
    guard !visibleResults.isEmpty else {
      statusLabel.stringValue = L10n.tr("No results from this source.")
      return
    }
    let sourceName = selectedSource?.displayName ?? L10n.tr("All Sources")
    statusLabel.stringValue = "\(visibleResults.count) · \(sourceName)"
  }

  // MARK: - Target song picker

  private func rebuildTargetSongs() {
    var songs = [Song]()
    var seen = Set<String>()

    func append(_ playable: AbstractPlayable?) {
      guard let song = playable?.asSong, seen.insert(song.id).inserted else { return }
      songs.append(song)
    }

    append(player.currentlyPlaying)
    for playable in player.getAllPrevQueueItems().reversed() where songs.count < 13 {
      append(playable)
    }
    for playable in player.getAllNextQueueItems() where songs.count < 25 {
      append(playable)
    }

    let previousSelectionID = selectedTargetSong?.id
    targetSongs = songs
    targetPopup.removeAllItems()

    guard !songs.isEmpty else {
      targetPopup.addItem(withTitle: L10n.tr("Play a song to apply lyrics."))
      targetPopup.isEnabled = false
      searchThisSongButton.isEnabled = false
      return
    }

    targetPopup.isEnabled = true
    searchThisSongButton.isEnabled = true
    for song in songs {
      targetPopup.addItem(withTitle: Self.targetTitle(for: song))
    }
    if let previousSelectionID,
       let index = songs.firstIndex(where: { $0.id == previousSelectionID }) {
      targetPopup.selectItem(at: index)
    }
    if let selected = selectedTargetSong {
      targetPopup.item(at: targetPopup.indexOfSelectedItem)?.toolTip = Self.targetTitle(for: selected)
    }
  }

  @objc
  private func targetSongChanged() {
    guard let song = selectedTargetSong else { return }
    targetPopup.item(at: targetPopup.indexOfSelectedItem)?.toolTip = Self.targetTitle(for: song)
  }

  private static func targetTitle(for song: Song) -> String {
    let artist = song.creatorName.trimmingCharacters(in: .whitespacesAndNewlines)
    return artist.isEmpty ? song.title : "\(song.title) — \(artist)"
  }

  // MARK: - Preview selection

  private func select(result: OnlineLyricsSearchResult?) {
    guard selectedResult?.id != result?.id else { return }
    selectedResult = result
    previewMatch = nil

    guard let result else {
      previewTask?.cancel()
      previewPane.showPlaceholder()
      return
    }
    loadPreview(for: result)
  }

  private func loadPreview(for result: OnlineLyricsSearchResult) {
    previewTask?.cancel()
    previewMatch = nil
    previewPane.showLoading(for: result)

    previewTask = Task { @MainActor [weak self] in
      let match = await OnlineLyricsService.shared.preview(result)
      guard let self,
            !Task.isCancelled,
            self.selectedResult?.id == result.id
      else { return }
      guard let match else {
        self.previewPane.showFailure(for: result)
        return
      }
      self.previewMatch = match
      self.previewPane.show(match: match, result: result)
    }
  }

  // MARK: - Apply

  private func applyPressed() {
    guard let match = previewMatch, let result = selectedResult else { return }
    guard let song = selectedTargetSong else {
      presentSimpleAlert(L10n.tr("No song is playing. Play a song first, then apply lyrics to it."))
      return
    }

    let mismatch = mismatchDetail(result: result, song: song)

    if song.lyricsRelFilePath != nil {
      let alert = NSAlert()
      alert.messageText = L10n.tr("This song already has lyrics. Replace them?")
      alert.informativeText = mismatch ?? L10n.tr("Timings may not line up.")
      alert.alertStyle = .warning
      alert.addButton(withTitle: L10n.tr("Replace"))
      alert.addButton(withTitle: L10n.tr("Cancel"))
      present(alert) { [weak self] response in
        guard response == .alertFirstButtonReturn else { return }
        self?.apply(match, to: song)
      }
      return
    }

    guard let mismatch else {
      apply(match, to: song)
      return
    }

    let alert = NSAlert()
    alert.messageText = L10n.tr("Lyrics may not match")
    alert.informativeText = mismatch + "\n" + L10n.tr("Timings may not line up. Apply anyway?")
    alert.alertStyle = .warning
    alert.addButton(withTitle: L10n.tr("Apply Anyway"))
    alert.addButton(withTitle: L10n.tr("Cancel"))
    present(alert) { [weak self] response in
      guard response == .alertFirstButtonReturn else { return }
      self?.apply(match, to: song)
    }
  }

  private func apply(_ match: OnlineLyricsMatch, to song: Song) {
    guard OnlineLyricsService.shared.apply(match, to: song) else {
      presentSimpleAlert(L10n.tr("Could not load lyrics for this result."))
      return
    }
    let alert = NSAlert()
    alert.messageText = L10n.tr("Lyrics applied")
    alert.informativeText = Self.targetTitle(for: song)
    alert.addButton(withTitle: L10n.tr("OK"))
    present(alert) { _ in }
  }

  /// Mirrors the Catalyst preview page: warns when the selected lyric belongs to a
  /// different recording so the timestamps can drift against the current song.
  private func mismatchDetail(result: OnlineLyricsSearchResult, song: Song) -> String? {
    let resultArtist = comparable(result.artist)
    let songArtist = comparable(song.creatorName)
    let artistMismatch = !resultArtist.isEmpty && !songArtist.isEmpty &&
      !resultArtist.contains(songArtist) && !songArtist.contains(resultArtist)

    let resultTitle = comparable(result.title)
    let songTitle = comparable(song.title)
    let titleMismatch = !resultTitle.isEmpty && !songTitle.isEmpty &&
      !resultTitle.contains(songTitle) && !songTitle.contains(resultTitle)

    // Online results report milliseconds; playable durations are stored in seconds.
    let songDurationMs = song.duration * 1_000
    let durationMismatch = result.duration > 0 && song.duration > 0 &&
      abs(result.duration - songDurationMs) > 5_000

    guard artistMismatch || titleMismatch || durationMismatch else { return nil }

    let resultParts = [
      result.title,
      result.artist,
      result.duration > 0 ? Self.durationText(result.duration) ?? "" : "",
    ]
    .filter { !$0.isEmpty }
    .joined(separator: " · ")

    let songParts = [
      song.title,
      song.creatorName,
      song.duration > 0 ? Self.durationText(songDurationMs) ?? "" : "",
    ]
    .filter { !$0.isEmpty }
    .joined(separator: " · ")

    return L10n.tr(
      "This lyric is for %@, but the current song is %@.",
      resultParts,
      songParts
    )
  }

  private func comparable(_ text: String) -> String {
    text.folding(
      options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
      locale: .current
    )
    .filter { !$0.isWhitespace && !$0.isPunctuation }
  }

  // MARK: - Alerts

  private func present(
    _ alert: NSAlert,
    completion: @escaping (NSApplication.ModalResponse) -> Void
  ) {
    guard let window = view.window else {
      completion(alert.runModal())
      return
    }
    alert.beginSheetModal(for: window, completionHandler: completion)
  }

  private func presentSimpleAlert(_ message: String) {
    let alert = NSAlert()
    alert.messageText = message
    alert.addButton(withTitle: L10n.tr("OK"))
    present(alert) { _ in }
  }

  // MARK: - NSTableViewDataSource

  func numberOfRows(in tableView: NSTableView) -> Int {
    visibleResults.count
  }

  // MARK: - NSTableViewDelegate

  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    let rowView = ThemedRowView()
    rowView.cornerRadius = 5
    rowView.horizontalInset = 8
    return rowView
  }

  func tableView(
    _ tableView: NSTableView,
    viewFor tableColumn: NSTableColumn?,
    row: Int
  )
    -> NSView? {
    guard let tableColumn, visibleResults.indices.contains(row) else { return nil }
    let result = visibleResults[row]

    switch tableColumn.identifier {
    case Column.title:
      return textCell(
        identifier: Column.title,
        text: result.title,
        font: MacTheme.titleFont,
        color: .labelColor,
        alignment: .left
      )
    case Column.artist:
      return textCell(
        identifier: Column.artist,
        text: result.artist,
        font: MacTheme.bodyFont,
        color: MacTheme.secondaryTextColor,
        alignment: .left
      )
    case Column.source:
      return textCell(
        identifier: Column.source,
        text: result.sourceName,
        font: MacTheme.secondaryFont,
        color: MacTheme.accentColor,
        alignment: .left
      )
    case Column.duration:
      return textCell(
        identifier: Column.duration,
        text: Self.durationText(result.duration) ?? "",
        font: MacTheme.tabularBodyFont,
        color: MacTheme.secondaryTextColor,
        alignment: .right
      )
    default:
      return nil
    }
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    let row = tableView.selectedRow
    guard visibleResults.indices.contains(row) else { return }
    select(result: visibleResults[row])
  }

  private func textCell(
    identifier: NSUserInterfaceItemIdentifier,
    text: String,
    font: NSFont,
    color: NSColor,
    alignment: NSTextAlignment
  )
    -> NSView {
    let cell = tableView.makeView(withIdentifier: identifier, owner: self) as?
      LyricsSearchTextCellView ?? LyricsSearchTextCellView()
    cell.identifier = identifier
    cell.configure(text: text, font: font, color: color, alignment: alignment)
    return cell
  }

  // MARK: - Formatting

  private static func durationText(_ milliseconds: Int) -> String? {
    guard milliseconds > 0 else { return nil }
    let seconds = milliseconds / 1_000
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
  }
}

// MARK: - LyricsSearchTextCellView

/// Plain single-line text cell used for every results column.
@MainActor
private final class LyricsSearchTextCellView: NSTableCellView {
  private let label = NSTextField(labelWithString: "")

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.lineBreakMode = .byTruncatingTail
    label.maximumNumberOfLines = 1
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
      label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
    textField = label
  }

  required init?(coder: NSCoder) {
    nil
  }

  func configure(text: String, font: NSFont, color: NSColor, alignment: NSTextAlignment) {
    label.stringValue = text
    label.font = font
    label.textColor = color
    label.alignment = alignment
  }
}
