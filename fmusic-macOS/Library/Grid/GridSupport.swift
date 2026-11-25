//
//  GridSupport.swift
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
import CoreData
import fmusicKit

/// Metrics shared by the Apple Music style artwork grids (home/albums/newest/recent).
@MainActor
enum GridMetrics {
  static let pageInset: CGFloat = 24
  static let itemSpacing: CGFloat = 16
  static let lineSpacing: CGFloat = 22
  /// Height reserved under a square artwork tile for title + artist labels.
  static let labelHeight: CGFloat = 44
  static let artworkCornerRadius: CGFloat = 10
  static let sectionHeaderHeight: CGFloat = 38
  static let sectionTitleFontSize: CGFloat = 17
  static let artistRowHeight: CGFloat = 56
  static let artistArtworkSize: CGFloat = 40
}

// MARK: - LibraryCountText

/// `N Albums` / `N Songs` secondary labels with singular/plural localisation.
@MainActor
enum LibraryCountText {
  static func albums(_ count: Int) -> String {
    count == 1 ? L10n.tr("%d Album", count) : L10n.tr("%d Albums", count)
  }

  static func artists(_ count: Int) -> String {
    count == 1 ? L10n.tr("%d Artist", count) : L10n.tr("%d Artists", count)
  }

  static func songs(_ count: Int) -> String {
    count == 1 ? L10n.tr("%d Song", count) : L10n.tr("%d Songs", count)
  }
}

// MARK: - LibraryAppearance

/// Read-only access to the active account's theme/artwork preferences.
@MainActor
enum LibraryAppearance {
  static var themePreference: ThemePreference {
    FmusicKit.shared.storage.settings.accounts.activeSetting.read.themePreference
  }

  static var artworkDisplayPreference: ArtworkDisplayPreference {
    FmusicKit.shared.storage.settings.accounts.activeSetting.read.artworkDisplayPreference
  }

  static func artworkImage(
    for entity: AbstractLibraryEntity,
    maxPixelSize: Int = 384
  )
    -> PlatformImage {
    ArtworkImageLoader.image(
      for: entity,
      themePreference: themePreference,
      artworkDisplayPreference: artworkDisplayPreference,
      maxPixelSize: maxPixelSize
    )
  }
}

// MARK: - LibraryPlayback

/// Playback entry points shared by the library pages (double-click on a tile/row).
@MainActor
enum LibraryPlayback {
  static func play(album: Album) {
    guard !album.playables.isEmpty else { return }
    FmusicKit.shared.player.play(context: PlayContext(containable: album))
  }

  static func play(artist: Artist) {
    guard !artist.playables.isEmpty else { return }
    FmusicKit.shared.player.play(context: PlayContext(containable: artist))
  }

  static func play(playlist: Playlist) {
    guard !playlist.playables.isEmpty else { return }
    FmusicKit.shared.player.play(context: PlayContext(containable: playlist))
  }
}

// MARK: - ThemedBackgroundView

/// Page root view that keeps its themed layer background in sync with the light/dark
/// appearance (`NSViewController` has no appearance callback, so the view provides it).
@MainActor
final class ThemedBackgroundView: NSView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = MacTheme.cgColor(MacTheme.contentBackgroundColor, for: effectiveAppearance)
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    layer?.backgroundColor = MacTheme.cgColor(MacTheme.contentBackgroundColor, for: effectiveAppearance)
  }
}

// MARK: - DoubleClickCollectionView

/// `NSCollectionView` with a double-click callback (the AppKit collection view has no
/// `doubleAction` like `NSTableView`). Single clicks keep their normal selection handling.
@MainActor
final class DoubleClickCollectionView: NSCollectionView {
  var onItemDoubleClick: ((IndexPath) -> Void)?
  var onItemContextMenu: ((IndexPath) -> NSMenu?)?

  override func mouseDown(with event: NSEvent) {
    super.mouseDown(with: event)
    guard event.clickCount >= 2, let onItemDoubleClick else { return }
    let point = convert(event.locationInWindow, from: nil)
    if let indexPath = indexPathForItem(at: point) {
      onItemDoubleClick(indexPath)
    }
  }

  override func menu(for event: NSEvent) -> NSMenu? {
    guard let onItemContextMenu else { return super.menu(for: event) }
    let point = convert(event.locationInWindow, from: nil)
    guard let indexPath = indexPathForItem(at: point) else { return super.menu(for: event) }
    return onItemContextMenu(indexPath) ?? super.menu(for: event)
  }
}

// MARK: - AlbumTileItem

/// Reusable artwork + title + artist tile used by all album grids.
@MainActor
final class AlbumTileItem: NSCollectionViewItem {
  static let reuseIdentifier = NSUserInterfaceItemIdentifier("AlbumTileItem")

  private let artworkShadowContainer = NSView()
  private let artworkView = NSImageView()
  private let titleLabel = NSTextField(labelWithString: "")
  private let artistLabel = NSTextField(labelWithString: "")
  private var trackingArea: NSTrackingArea?
  private var isHovered = false

  private(set) var album: Album?

  override var isSelected: Bool {
    didSet { updateSelectionAppearance() }
  }

  override func loadView() {
    let root = NSView()
    root.wantsLayer = true
    self.view = root

    artworkShadowContainer.wantsLayer = true
    artworkShadowContainer.layer?.masksToBounds = false
    artworkShadowContainer.layer?.shadowColor = NSColor.black.cgColor
    artworkShadowContainer.layer?.shadowOpacity = 0.08
    artworkShadowContainer.layer?.shadowRadius = 4
    artworkShadowContainer.layer?.shadowOffset = CGSize(width: 0, height: -2)
    artworkShadowContainer.translatesAutoresizingMaskIntoConstraints = false

    artworkView.translatesAutoresizingMaskIntoConstraints = false
    artworkView.imageScaling = .scaleProportionallyUpOrDown
    artworkView.wantsLayer = true
    artworkView.layer?.cornerRadius = GridMetrics.artworkCornerRadius
    artworkView.layer?.masksToBounds = true
    artworkView.layer?.borderWidth = 0

    titleLabel.font = MacTheme.titleFont
    titleLabel.lineBreakMode = .byTruncatingTail
    titleLabel.maximumNumberOfLines = 1
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    artistLabel.font = MacTheme.secondaryFont
    artistLabel.textColor = MacTheme.secondaryTextColor
    artistLabel.lineBreakMode = .byTruncatingTail
    artistLabel.maximumNumberOfLines = 1
    artistLabel.translatesAutoresizingMaskIntoConstraints = false

    artworkShadowContainer.addSubview(artworkView)
    root.addSubview(artworkShadowContainer)
    root.addSubview(titleLabel)
    root.addSubview(artistLabel)

    NSLayoutConstraint.activate([
      artworkShadowContainer.topAnchor.constraint(equalTo: root.topAnchor),
      artworkShadowContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      artworkShadowContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      artworkShadowContainer.heightAnchor.constraint(equalTo: artworkShadowContainer.widthAnchor),

      artworkView.topAnchor.constraint(equalTo: artworkShadowContainer.topAnchor),
      artworkView.leadingAnchor.constraint(equalTo: artworkShadowContainer.leadingAnchor),
      artworkView.trailingAnchor.constraint(equalTo: artworkShadowContainer.trailingAnchor),
      artworkView.bottomAnchor.constraint(equalTo: artworkShadowContainer.bottomAnchor),

      titleLabel.topAnchor.constraint(equalTo: artworkShadowContainer.bottomAnchor, constant: 7),
      titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 1),
      titleLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -1),

      artistLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
      artistLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      artistLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
    ])
  }

  override func viewDidLayout() {
    super.viewDidLayout()
    if let trackingArea {
      view.removeTrackingArea(trackingArea)
    }
    let area = NSTrackingArea(
      rect: .zero,
      options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
      owner: self,
      userInfo: nil
    )
    view.addTrackingArea(area)
    trackingArea = area
  }

  override func mouseEntered(with event: NSEvent) {
    setHovered(true)
  }

  override func mouseExited(with event: NSEvent) {
    setHovered(false)
  }

  private func setHovered(_ hovered: Bool) {
    guard isHovered != hovered else { return }
    isHovered = hovered
    guard let layer = artworkShadowContainer.layer else { return }
    let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    let duration: CFTimeInterval = reduceMotion ? 0 : 0.16
    let bounds = artworkShadowContainer.bounds
    var transform = CATransform3DIdentity
    if hovered, !reduceMotion {
      transform = CATransform3DTranslate(transform, bounds.midX, bounds.midY, 0)
      transform = CATransform3DScale(transform, 1.022, 1.022, 1)
      transform = CATransform3DTranslate(transform, -bounds.midX, -bounds.midY, 0)
    }
    CATransaction.begin()
    CATransaction.setAnimationDuration(duration)
    CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
    layer.transform = transform
    layer.shadowOpacity = hovered ? 0.22 : 0.08
    layer.shadowRadius = hovered ? 10 : 4
    layer.shadowOffset = CGSize(width: 0, height: hovered ? -4 : -2)
    CATransaction.commit()
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    album = nil
    isHovered = false
    if let layer = artworkShadowContainer.layer {
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      layer.transform = CATransform3DIdentity
      layer.shadowOpacity = 0.08
      layer.shadowRadius = 4
      layer.shadowOffset = CGSize(width: 0, height: -2)
      CATransaction.commit()
    }
    artworkView.image = nil
    titleLabel.stringValue = ""
    artistLabel.stringValue = ""
  }

  func configure(album: Album) {
    self.album = album
    titleLabel.stringValue = album.name
    let artistName = album.artist?.name ?? ""
    artistLabel.stringValue = artistName
    artistLabel.isHidden = artistName.isEmpty
    artworkView.image = LibraryAppearance.artworkImage(for: album)
    updateSelectionAppearance()
  }

  private func updateSelectionAppearance() {
    let accent = MacTheme.accentColor
    artworkView.layer?.borderWidth = isSelected ? 2 : 0
    artworkView.layer?.borderColor = accent.cgColor
    titleLabel.textColor = isSelected ? accent : .labelColor
  }
}

// MARK: - AlbumSectionHeaderView

/// Section title (and optional refresh button) used by the home page flow layout.
@MainActor
final class AlbumSectionHeaderView: NSView, NSCollectionViewElement {
  static let reuseIdentifier = NSUserInterfaceItemIdentifier("AlbumSectionHeader")

  private let titleLabel = NSTextField(labelWithString: "")
  private let refreshButton = NSButton()
  var onRefresh: (() -> Void)?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    titleLabel.font = .systemFont(ofSize: GridMetrics.sectionTitleFontSize, weight: .bold)
    titleLabel.textColor = .labelColor
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    refreshButton.title = L10n.tr("Refresh")
    refreshButton.bezelStyle = .inline
    refreshButton.isBordered = false
    refreshButton.font = MacTheme.bodyFont
    refreshButton.contentTintColor = MacTheme.accentColor
    refreshButton.target = self
    refreshButton.action = #selector(refreshTapped)
    refreshButton.translatesAutoresizingMaskIntoConstraints = false

    addSubview(titleLabel)
    addSubview(refreshButton)
    // Flow layout headers span the full collection width (they ignore section insets on
    // macOS), so pad them here to line up with the page title.
    NSLayoutConstraint.activate([
      titleLabel.leadingAnchor.constraint(
        equalTo: leadingAnchor,
        constant: GridMetrics.pageInset
      ),
      titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
      titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: refreshButton.leadingAnchor, constant: -12),

      refreshButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -GridMetrics.pageInset),
      refreshButton.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  required init?(coder: NSCoder) {
    nil
  }

  func configure(title: String, showsRefresh: Bool) {
    titleLabel.stringValue = title
    refreshButton.isHidden = !showsRefresh
    refreshButton.contentTintColor = MacTheme.accentColor
  }

  @objc
  private func refreshTapped() {
    onRefresh?()
  }
}

// MARK: - AlbumGridPageViewController

/// Shared implementation for the flat album grid pages (albums/newest/recently played).
///
/// Subclasses only describe the page: title, empty message and how the albums are loaded.
@MainActor
class AlbumGridPageViewController: NSViewController, ContentSearchable {
  // MARK: - Subclass hooks

  /// Large title shown above the grid.
  var pageTitle: String { "" }
  /// Message shown when no albums are available.
  var emptyMessage: String { L10n.tr("No %@", L10n.tr("Albums")) }
  /// Preferred tile width; the actual column count adapts to the available width.
  var targetItemWidth: CGFloat { 140 }
  /// Upper bound for the adaptive column count.
  var maxColumnCount: Int { 7 }
  /// Pure data loader for the background Core Data context.
  nonisolated func loadAlbumIDs(
    in library: LibraryStorage,
    account: Account
  )
    -> [NSManagedObjectID] { [] }

  // MARK: - Views

  let collectionView = DoubleClickCollectionView()
  private let scrollView = NSScrollView()
  private let titleLabel = NSTextField(labelWithString: "")
  private let subtitleLabel = NSTextField(labelWithString: "")
  private let emptyLabel = NSTextField(labelWithString: "")

  private var allAlbums: [Album] = []
  private(set) var albums: [Album] = []
  private var filterText = ""
  private var lastLayoutWidth: CGFloat = 0
  private var reloadGeneration = 0
  private var storage: PersistentStorage { FmusicKit.shared.storage }

  var contentSearchPlaceholder: String? {
    L10n.tr("Search in \"%@\"", pageTitle)
  }

  func contentSearchDidChange(text: String) {
    filterText = text
    applyFilter()
  }

  // MARK: - Lifecycle

  override func loadView() {
    let root = ThemedBackgroundView()

    titleLabel.stringValue = pageTitle
    titleLabel.font = MacTheme.largeTitleFont
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    subtitleLabel.font = MacTheme.secondaryFont
    subtitleLabel.textColor = MacTheme.secondaryTextColor
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

    scrollView.documentView = collectionView
    configureCollectionView()
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    emptyLabel.font = MacTheme.bodyFont
    emptyLabel.textColor = MacTheme.secondaryTextColor
    emptyLabel.alignment = .center
    emptyLabel.maximumNumberOfLines = 2
    emptyLabel.isHidden = true
    emptyLabel.translatesAutoresizingMaskIntoConstraints = false

    root.addSubview(titleLabel)
    root.addSubview(subtitleLabel)
    root.addSubview(scrollView)
    root.addSubview(emptyLabel)

    NSLayoutConstraint.activate([
      titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
      titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
      titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -24),

      subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
      subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -24),

      scrollView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 10),
      scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

      emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
      emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
      emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 24),
      emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -24),
    ])

    self.view = root
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    collectionView.dataSource = self
    collectionView.delegate = self

    let center = NotificationCenter.default
    center.addObserver(
      self,
      selector: #selector(reloadAlbums),
      name: .librarySongsSynced,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(reloadAlbums),
      name: .accountActiveChanged,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(themeDidChange),
      name: .macThemeColorChanged,
      object: nil
    )
    reloadAlbums()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  override func viewDidLayout() {
    super.viewDidLayout()
    let width = collectionView.bounds.width
    if abs(width - lastLayoutWidth) > 0.5 {
      lastLayoutWidth = width
      collectionView.collectionViewLayout?.invalidateLayout()
    }
  }

  // MARK: - Configuration

  private func configureCollectionView() {
    let layout = NSCollectionViewFlowLayout()
    layout.minimumInteritemSpacing = GridMetrics.itemSpacing
    layout.minimumLineSpacing = GridMetrics.lineSpacing
    layout.sectionInset = NSEdgeInsets(
      top: 8,
      left: GridMetrics.pageInset,
      bottom: GridMetrics.pageInset + 4,
      right: GridMetrics.pageInset
    )
    collectionView.collectionViewLayout = layout
    collectionView.register(
      AlbumTileItem.self,
      forItemWithIdentifier: AlbumTileItem.reuseIdentifier
    )
    collectionView.isSelectable = true
    collectionView.allowsEmptySelection = true
    collectionView.backgroundColors = [.clear]
    collectionView.onItemDoubleClick = { [weak self] indexPath in
      self?.playItem(at: indexPath)
    }
    collectionView.onItemContextMenu = { [weak self] indexPath in
      self?.makeContextMenu(for: indexPath)
    }
    collectionView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      collectionView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
      collectionView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
      collectionView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
    ])
  }

  // MARK: - Data

  @objc
  func reloadAlbums() {
    let storage = FmusicKit.shared.storage
    reloadGeneration += 1
    let generation = reloadGeneration
    guard let accountInfo = storage.settings.accounts.active else {
      allAlbums = []
      applyFilter()
      return
    }
    let accountID = storage.main.library.getAccount(info: accountInfo).managedObject.objectID

    Task { [weak self] in
      guard let self else { return }
      let objectIDs = try? await self.storage.async.performAndGet { [weak self] companion
        -> [NSManagedObjectID] in
        guard let self else { return [] }
        let account = companion.library.getAccount(managedObjectId: accountID)
        return self.loadAlbumIDs(in: companion.library, account: account)
      }
      guard generation == self.reloadGeneration,
            self.storage.settings.accounts.active == accountInfo else { return }
      let context = self.storage.main.context
      self.allAlbums = (objectIDs ?? [])
        .compactMap { context.object(with: $0) as? AlbumMO }
        .compactMap { Album(managedObject: $0) }
      self.applyFilter()
    }
  }

  private func applyFilter() {
    let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
    if query.isEmpty {
      albums = allAlbums
    } else {
      albums = allAlbums.filter { album in
        album.name.localizedCaseInsensitiveContains(query)
          || (album.artist?.name.localizedCaseInsensitiveContains(query) ?? false)
      }
    }
    collectionView.reloadData()
    subtitleLabel.stringValue = albums.isEmpty
      ? ""
      : LibraryCountText.albums(albums.count)
    emptyLabel.stringValue = emptyMessage
    emptyLabel.isHidden = !albums.isEmpty
  }

  @objc
  private func themeDidChange() {
    collectionView.reloadData()
  }

  // MARK: - Layout

  func itemWidth(for collectionWidth: CGFloat) -> CGFloat {
    let available = max(120, collectionWidth - GridMetrics.pageInset * 2)
    let spacing = GridMetrics.itemSpacing
    let columns = max(
      1,
      min(maxColumnCount, Int((available + spacing) / (targetItemWidth + spacing)))
    )
    return floor((available - CGFloat(columns - 1) * spacing) / CGFloat(columns))
  }

  // MARK: - Actions

  func playItem(at indexPath: IndexPath) {
    guard indexPath.item >= 0, indexPath.item < albums.count else { return }
    LibraryPlayback.play(album: albums[indexPath.item])
  }

  private func makeContextMenu(for indexPath: IndexPath) -> NSMenu? {
    guard indexPath.item >= 0, indexPath.item < albums.count else { return nil }
    let menu = NSMenu()
    let playItem = NSMenuItem(
      title: L10n.tr("Play"),
      action: #selector(contextPlayAlbum(_:)),
      keyEquivalent: ""
    )
    playItem.target = self
    playItem.tag = indexPath.item
    menu.addItem(playItem)

    let rematchItem = NSMenuItem(
      title: L10n.tr("Re-match Cover"),
      action: #selector(contextRematchAlbumCover(_:)),
      keyEquivalent: ""
    )
    rematchItem.target = self
    rematchItem.tag = indexPath.item
    menu.addItem(rematchItem)
    return menu
  }

  @objc
  private func contextPlayAlbum(_ sender: NSMenuItem) {
    guard sender.tag >= 0, sender.tag < albums.count else { return }
    LibraryPlayback.play(album: albums[sender.tag])
  }

  @objc
  private func contextRematchAlbumCover(_ sender: NSMenuItem) {
    guard sender.tag >= 0, sender.tag < albums.count,
          let accountInfo = storage.settings.accounts.active else { return }
    let album = albums[sender.tag]
    Task { @MainActor in
      await MetadataBackfillService.shared.rematchArtwork(for: album, accountInfo: accountInfo)
    }
  }
}

// MARK: - AlbumGridPageViewController + NSCollectionViewDataSource

extension AlbumGridPageViewController: NSCollectionViewDataSource {
  func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int)
    -> Int {
    albums.count
  }

  func collectionView(
    _ collectionView: NSCollectionView,
    itemForRepresentedObjectAt indexPath: IndexPath
  )
    -> NSCollectionViewItem {
    let item = collectionView.makeItem(
      withIdentifier: AlbumTileItem.reuseIdentifier,
      for: indexPath
    )
    if let tile = item as? AlbumTileItem, indexPath.item >= 0, indexPath.item < albums.count {
      tile.configure(album: albums[indexPath.item])
    }
    return item
  }
}

// MARK: - AlbumGridPageViewController + NSCollectionViewDelegateFlowLayout

extension AlbumGridPageViewController: NSCollectionViewDelegateFlowLayout {

  func collectionView(
    _ collectionView: NSCollectionView,
    didSelectItemsAt indexPaths: Set<IndexPath>
  ) {
    guard let indexPath = indexPaths.first,
          indexPath.item >= 0,
          indexPath.item < albums.count else { return }
    MainViewController.current?.openAlbum(albums[indexPath.item])
    collectionView.deselectItems(at: indexPaths)
  }
  func collectionView(
    _ collectionView: NSCollectionView,
    layout collectionViewLayout: NSCollectionViewLayout,
    sizeForItemAt indexPath: IndexPath
  )
    -> NSSize {
    let width = itemWidth(for: collectionView.bounds.width)
    return NSSize(width: width, height: width + GridMetrics.labelHeight)
  }
}
