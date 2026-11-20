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

  static func artworkImage(for entity: AbstractLibraryEntity) -> PlatformImage {
    ArtworkImageLoader.image(
      for: entity,
      themePreference: themePreference,
      artworkDisplayPreference: artworkDisplayPreference
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
}

// MARK: - ThemedBackgroundView

/// Page root view that keeps its themed layer background in sync with the light/dark
/// appearance (`NSViewController` has no appearance callback, so the view provides it).
@MainActor
final class ThemedBackgroundView: NSView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = MacTheme.contentBackgroundColor.cgColor
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    layer?.backgroundColor = MacTheme.contentBackgroundColor.cgColor
  }
}

// MARK: - DoubleClickCollectionView

/// `NSCollectionView` with a double-click callback (the AppKit collection view has no
/// `doubleAction` like `NSTableView`). Single clicks keep their normal selection handling.
@MainActor
final class DoubleClickCollectionView: NSCollectionView {
  var onItemDoubleClick: ((IndexPath) -> Void)?

  override func mouseDown(with event: NSEvent) {
    super.mouseDown(with: event)
    guard event.clickCount >= 2, let onItemDoubleClick else { return }
    let point = convert(event.locationInWindow, from: nil)
    if let indexPath = indexPathForItem(at: point) {
      onItemDoubleClick(indexPath)
    }
  }
}

// MARK: - AlbumTileItem

/// Reusable artwork + title + artist tile used by all album grids.
@MainActor
final class AlbumTileItem: NSCollectionViewItem {
  static let reuseIdentifier = NSUserInterfaceItemIdentifier("AlbumTileItem")

  private let artworkView = NSImageView()
  private let titleLabel = NSTextField(labelWithString: "")
  private let artistLabel = NSTextField(labelWithString: "")

  private(set) var album: Album?

  override var isSelected: Bool {
    didSet { updateSelectionAppearance() }
  }

  override func loadView() {
    let root = NSView()
    root.wantsLayer = true
    self.view = root

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

    root.addSubview(artworkView)
    root.addSubview(titleLabel)
    root.addSubview(artistLabel)

    NSLayoutConstraint.activate([
      artworkView.topAnchor.constraint(equalTo: root.topAnchor),
      artworkView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      artworkView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      artworkView.heightAnchor.constraint(equalTo: artworkView.widthAnchor),

      titleLabel.topAnchor.constraint(equalTo: artworkView.bottomAnchor, constant: 7),
      titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 1),
      titleLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -1),

      artistLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
      artistLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      artistLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
    ])
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    album = nil
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
class AlbumGridPageViewController: NSViewController {
  // MARK: - Subclass hooks

  /// Large title shown above the grid.
  var pageTitle: String { "" }
  /// Message shown when no albums are available.
  var emptyMessage: String { L10n.tr("No %@", L10n.tr("Albums")) }
  /// Preferred tile width; the actual column count adapts to the available width.
  var targetItemWidth: CGFloat { 140 }
  /// Upper bound for the adaptive column count.
  var maxColumnCount: Int { 7 }
  /// The albums rendered by this page.
  func loadAlbums() -> [Album] { [] }

  // MARK: - Views

  let collectionView = DoubleClickCollectionView()
  private let scrollView = NSScrollView()
  private let titleLabel = NSTextField(labelWithString: "")
  private let subtitleLabel = NSTextField(labelWithString: "")
  private let emptyLabel = NSTextField(labelWithString: "")

  private(set) var albums: [Album] = []
  private var lastLayoutWidth: CGFloat = 0

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
    albums = loadAlbums()
    collectionView.reloadData()
    subtitleLabel.stringValue = albums.isEmpty ? "" : LibraryCountText.albums(albums.count)
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
    layout collectionViewLayout: NSCollectionViewLayout,
    sizeForItemAt indexPath: IndexPath
  )
    -> NSSize {
    let width = itemWidth(for: collectionView.bounds.width)
    return NSSize(width: width, height: width + GridMetrics.labelHeight)
  }
}
