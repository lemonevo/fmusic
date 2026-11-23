//
//  HomeViewController.swift
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

/// `.home` — Apple Music style start page with random, recently played and newest albums.
///
/// All three sections live in a single `NSCollectionView` (flow layout sections with a
/// title header); each tile shows the artwork with the album and artist name underneath,
/// double-click plays the album and the 随机专辑 header has a refresh button that re-rolls
/// the random selection.
@MainActor
final class HomeViewController: NSViewController {
  private struct HomeSnapshot: Sendable {
    var random: [NSManagedObjectID] = []
    var recent: [NSManagedObjectID] = []
    var newest: [NSManagedObjectID] = []
    var albumCount = 0
  }

  private struct Section {
    enum Kind {
      case random
      case recent
      case newest
    }

    var kind: Kind
    var title: String
    var albums: [Album]
  }

  private enum SectionVisibility {
    static func key(for kind: Section.Kind) -> String {
      switch kind {
      case .random: return "fmusic.home.random"
      case .recent: return "fmusic.home.recent"
      case .newest: return "fmusic.home.newest"
      }
    }

    static func isEnabled(_ kind: Section.Kind) -> Bool {
      let key = key(for: kind)
      if UserDefaults.standard.object(forKey: key) == nil { return true }
      return UserDefaults.standard.bool(forKey: key)
    }

    static func set(_ kind: Section.Kind, enabled: Bool) {
      UserDefaults.standard.set(enabled, forKey: key(for: kind))
    }
  }

  func presentSectionEditor() {
    showEditMenu()
  }

  @objc
  private func showEditMenu() {
    let menu = NSMenu()
    let header = NSMenuItem(title: L10n.tr("Edit"), action: nil, keyEquivalent: "")
    header.isEnabled = false
    menu.addItem(header)
    menu.addItem(.separator())
    let entries: [(Section.Kind, String)] = [
      (.random, L10n.tr("Random Albums")),
      (.recent, L10n.tr("Recently Played Albums")),
      (.newest, L10n.tr("Newest Albums")),
    ]
    for (kind, title) in entries {
      let item = NSMenuItem(
        title: title,
        action: #selector(toggleSection(_:)),
        keyEquivalent: ""
      )
      item.target = self
      item.representedObject = title
      item.state = SectionVisibility.isEnabled(kind) ? .on : .off
      item.identifier = NSUserInterfaceItemIdentifier(SectionVisibility.key(for: kind))
      menu.addItem(item)
    }
    menu.popUp(
      positioning: nil,
      at: NSPoint(x: editButton.bounds.midX, y: editButton.bounds.minY - 4),
      in: editButton
    )
  }

  @objc
  private func toggleSection(_ sender: NSMenuItem) {
    guard let identifier = sender.identifier?.rawValue else { return }
    let enabled = sender.state == .off
    UserDefaults.standard.set(enabled, forKey: identifier)
    reloadHome()
  }

  private enum Metrics {
    static let albumsPerSection = 6
    static let largeTitleTopInset: CGFloat = 20
    static let pageInset: CGFloat = 24
    static let targetItemWidth: CGFloat = 100
    static let maxColumns = 4
  }

  private let titleLabel = NSTextField(labelWithString: L10n.tr("Home"))
  private let subtitleLabel = NSTextField(labelWithString: "")
  private let editButton = NSButton()
  private let scrollView = NSScrollView()
  private let collectionView = DoubleClickCollectionView()
  private let emptyLabel = NSTextField(labelWithString: "")

  private var sections: [Section] = []
  private var reloadGeneration = 0
  private var lastLayoutWidth: CGFloat = 0

  // MARK: - Lifecycle

  override func loadView() {
    let root = ThemedBackgroundView()

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
    editButton.title = L10n.tr("Edit")
    editButton.font = .systemFont(ofSize: 12, weight: .medium)
    editButton.isBordered = false
    editButton.bezelStyle = .regularSquare
    editButton.contentTintColor = MacTheme.accentColor
    editButton.target = self
    editButton.action = #selector(showEditMenu)
    editButton.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(editButton)

    root.addSubview(subtitleLabel)
    root.addSubview(scrollView)
    root.addSubview(emptyLabel)

    NSLayoutConstraint.activate([
      titleLabel.leadingAnchor.constraint(
        equalTo: root.leadingAnchor,
        constant: Metrics.pageInset
      ),
      titleLabel.topAnchor.constraint(
        equalTo: root.topAnchor,
        constant: Metrics.largeTitleTopInset
      ),
      titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -24),

      subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
      subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -110),

      editButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
      editButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

      scrollView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 8),
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
      selector: #selector(reloadHome),
      name: .librarySongsSynced,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(reloadHome),
      name: .accountActiveChanged,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(themeDidChange),
      name: .macThemeColorChanged,
      object: nil
    )
    reloadHome()
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
    layout.headerReferenceSize = NSSize(width: 0, height: GridMetrics.sectionHeaderHeight)
    layout.sectionInset = NSEdgeInsets(
      top: 0,
      left: Metrics.pageInset,
      bottom: Metrics.pageInset,
      right: Metrics.pageInset
    )
    collectionView.collectionViewLayout = layout
    collectionView.register(
      AlbumTileItem.self,
      forItemWithIdentifier: AlbumTileItem.reuseIdentifier
    )
    collectionView.register(
      AlbumSectionHeaderView.self,
      forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
      withIdentifier: AlbumSectionHeaderView.reuseIdentifier
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
  private func reloadHome() {
    let storage = FmusicKit.shared.storage
    reloadGeneration += 1
    let generation = reloadGeneration
    guard let accountInfo = storage.settings.accounts.active else {
      sections = []
      collectionView.reloadData()
      subtitleLabel.stringValue = ""
      emptyLabel.stringValue = L10n.tr("No %@", L10n.tr("Albums"))
      emptyLabel.isHidden = false
      return
    }
    let accountID = storage.main.library.getAccount(info: accountInfo).managedObject.objectID
    let showRandom = SectionVisibility.isEnabled(.random)
    let showRecent = SectionVisibility.isEnabled(.recent)
    let showNewest = SectionVisibility.isEnabled(.newest)
    let perSection = Metrics.albumsPerSection

    Task { [weak self] in
      guard let self else { return }
      let fetched = try? await storage.async.performAndGet { companion
        -> HomeSnapshot in
        let account = companion.library.getAccount(managedObjectId: accountID)
        var result = HomeSnapshot()
        let random = companion.library.getRandomAlbums(
          for: account,
          count: perSection,
          onlyCached: false
        )
        let fallbackRandom = random.isEmpty
          ? Array(companion.library.getAlbums(for: account).prefix(perSection))
          : random
        result.random = fallbackRandom.map(\.managedObject.objectID)
        result.recent = companion.library.getRecentAlbums(
          for: account,
          offset: 0,
          count: perSection
        ).map(\.managedObject.objectID)
        result.newest = companion.library.getNewestAlbums(
          for: account,
          offset: 0,
          count: perSection
        ).map(\.managedObject.objectID)
        result.albumCount = companion.library.getAlbumCount(for: account)
        return result
      }
      guard generation == self.reloadGeneration,
            storage.settings.accounts.active == accountInfo else { return }

      let context = storage.main.context
      func albums(_ ids: [NSManagedObjectID]) -> [Album] {
        ids.compactMap { context.object(with: $0) as? AlbumMO }
          .compactMap { Album(managedObject: $0) }
      }
      let snapshot = fetched ?? HomeSnapshot()
      var newSections = [Section]()
      let random = albums(snapshot.random)
      if !random.isEmpty, showRandom {
        newSections.append(Section(
          kind: .random,
          title: L10n.tr("Random Albums"),
          albums: random
        ))
      }
      let recent = albums(snapshot.recent)
      if !recent.isEmpty, showRecent {
        newSections.append(Section(
          kind: .recent,
          title: L10n.tr("Recently Played Albums"),
          albums: recent
        ))
      }
      let newest = albums(snapshot.newest)
      if !newest.isEmpty, showNewest {
        newSections.append(Section(
          kind: .newest,
          title: L10n.tr("Newest Albums"),
          albums: newest
        ))
      }
      self.sections = newSections
      self.collectionView.reloadData()
      self.subtitleLabel.stringValue = snapshot.albumCount > 0
        ? LibraryCountText.albums(snapshot.albumCount)
        : ""
      self.emptyLabel.stringValue = L10n.tr("No %@", L10n.tr("Albums"))
      self.emptyLabel.isHidden = !newSections.isEmpty
    }
  }

  /// Re-rolls only the 随机专辑 section without touching the other sections.
  private func shuffleRandomAlbums() {
    guard let index = sections.firstIndex(where: { $0.kind == .random }) else { return }
    let storage = FmusicKit.shared.storage
    guard let accountInfo = storage.settings.accounts.active else { return }
    let library = storage.main.library
    let account = library.getAccount(info: accountInfo)
    var random = library.getRandomAlbums(
      for: account,
      count: Metrics.albumsPerSection,
      onlyCached: false
    )
    if random.isEmpty {
      random = Array(library.getAlbums(for: account).prefix(Metrics.albumsPerSection))
    }
    sections[index].albums = random
    collectionView.reloadData()
  }

  @objc
  private func themeDidChange() {
    collectionView.reloadData()
  }

  // MARK: - Actions

  private func playItem(at indexPath: IndexPath) {
    guard indexPath.section >= 0, indexPath.section < sections.count else { return }
    let albums = sections[indexPath.section].albums
    guard indexPath.item >= 0, indexPath.item < albums.count else { return }
    LibraryPlayback.play(album: albums[indexPath.item])
  }

  // MARK: - Layout

  private func itemWidth(for collectionWidth: CGFloat) -> CGFloat {
    let available = max(160, collectionWidth - Metrics.pageInset * 2)
    let spacing = GridMetrics.itemSpacing
    let columns = max(
      2,
      min(Metrics.maxColumns, Int((available + spacing) / (Metrics.targetItemWidth + spacing)))
    )
    return floor((available - CGFloat(columns - 1) * spacing) / CGFloat(columns))
  }
}

// MARK: - HomeViewController + NSCollectionViewDataSource

extension HomeViewController: NSCollectionViewDataSource {
  func numberOfSections(in collectionView: NSCollectionView) -> Int {
    sections.count
  }

  func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int)
    -> Int {
    guard section >= 0, section < sections.count else { return 0 }
    return sections[section].albums.count
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
    if let tile = item as? AlbumTileItem,
       indexPath.section >= 0, indexPath.section < sections.count {
      let albums = sections[indexPath.section].albums
      if indexPath.item >= 0, indexPath.item < albums.count {
        tile.configure(album: albums[indexPath.item])
      }
    }
    return item
  }

  func collectionView(
    _ collectionView: NSCollectionView,
    viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind,
    at indexPath: IndexPath
  )
    -> NSView {
    guard kind == NSCollectionView.elementKindSectionHeader,
          indexPath.section >= 0,
          indexPath.section < sections.count else {
      return NSView()
    }
    let header = collectionView.makeSupplementaryView(
      ofKind: kind,
      withIdentifier: AlbumSectionHeaderView.reuseIdentifier,
      for: indexPath
    )
    guard let sectionHeader = header as? AlbumSectionHeaderView else { return header }
    let section = sections[indexPath.section]
    sectionHeader.configure(title: section.title, showsRefresh: section.kind == .random)
    if section.kind == .random {
      sectionHeader.onRefresh = { [weak self] in
        self?.shuffleRandomAlbums()
      }
    } else {
      sectionHeader.onRefresh = nil
    }
    return sectionHeader
  }
}

// MARK: - HomeViewController + NSCollectionViewDelegateFlowLayout

extension HomeViewController: NSCollectionViewDelegateFlowLayout {

  func collectionView(
    _ collectionView: NSCollectionView,
    didSelectItemsAt indexPaths: Set<IndexPath>
  ) {
    guard let indexPath = indexPaths.first,
          indexPath.section >= 0,
          indexPath.section < sections.count else { return }
    let albums = sections[indexPath.section].albums
    guard indexPath.item >= 0, indexPath.item < albums.count else { return }
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
