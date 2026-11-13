//
//  HomeVC.swift
//  fmusic
//
//  Created by Maximilian Bauer on 24.11.25.
//  Copyright (c) 2025 Maximilian Bauer. All rights reserved.
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

import fmusicKit
import CoreData
import OSLog
import UIKit

// MARK: - HomeVC

final class HomeVC: UICollectionViewController {
  // MARK: - Properties

  private var dataSource: UICollectionViewDiffableDataSource<HomeSection, HomeItem>!
  private let log = OSLog(subsystem: "fmusic", category: "HomeVC")

  /// Apple Music style grid: four albums per row that grow and shrink with the window.
  private static let maximumColumns = 4
  private static let minimumItemWidth: CGFloat = 132.0
  private static let itemSpacing: CGFloat = 16.0
  private static let sectionHorizontalInset: CGFloat = 20.0

  private let account: Account
  private let sharedHome: HomeManager

  // MARK: - Init

  init(account: Account) {
    self.account = account
    let appDelegate = (UIApplication.shared.delegate as! AppDelegate)
    self.sharedHome = HomeManager(
      account: account,
      storage: appDelegate.storage,
      getMeta: appDelegate.getMeta,
      eventLogger: appDelegate.eventLogger
    )
    let layout = HomeVC.createLayout()
    super.init(collectionViewLayout: layout)
    sharedHome.applySnapshotCB = { [weak self] in
      guard let self else { return }
      applySnapshot(animated: true)
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Lifecycle

  override func viewDidLoad() {
    super.viewDidLoad()
    // ensures that the collection view stops placing items under the sidebar
    collectionView.contentInsetAdjustmentBehavior = .scrollableAxes
    title = L10n.tr("Home")

    registerForTraitChanges(
      [UITraitPreferredContentSizeCategory.self],
      handler: { (self: Self, previousTraitCollection: UITraitCollection) in
        self.collectionView.collectionViewLayout.invalidateLayout()
      }
    )

    navigationController?.navigationBar.prefersLargeTitles = true
    navigationItem.largeTitleDisplayMode = .always
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      title: L10n.tr("Edit"),
      style: .plain,
      target: self,
      action: #selector(editSectionsTapped)
    )
    configureCollectionView()
    configureDataSource()
    sharedHome.createFetchController()
    applySnapshot(animated: false)

    appDelegate.notificationHandler.register(
      self,
      selector: #selector(refreshOfflineMode),
      name: .offlineModeChanged,
      object: nil
    )
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.navigationBar.prefersLargeTitles = true
    navigationItem.largeTitleDisplayMode = .always
  }

  override func viewIsAppearing(_ animated: Bool) {
    super.viewIsAppearing(animated)
    extendSafeAreaToAccountForMiniPlayer()
    sharedHome.updateFromRemote()
  }

  // MARK: - Layout

  private static func columnCount(for containerWidth: CGFloat) -> Int {
    guard containerWidth > 0 else { return maximumColumns }
    let available = containerWidth - (2 * sectionHorizontalInset)
    let fitting = Int((available + itemSpacing) / (minimumItemWidth + itemSpacing))
    return max(1, min(maximumColumns, fitting))
  }

  private static func itemWidth(for containerWidth: CGFloat) -> CGFloat {
    let columns = CGFloat(columnCount(for: containerWidth))
    let available = containerWidth - (2 * sectionHorizontalInset)
    return max(0, (available - (itemSpacing * (columns - 1))) / columns)
  }

  private static func createLayout() -> UICollectionViewCompositionalLayout {
    let layout = UICollectionViewCompositionalLayout { sectionIndex, environment in
      guard let _ = HomeSection(rawValue: sectionIndex) else { return nil }

      let containerWidth = environment.container.effectiveContentSize.width
      let columns = Self.columnCount(for: containerWidth)
      let cardWidth = Self.itemWidth(for: containerWidth)

      // Item: square image with title below
      let itemSize = NSCollectionLayoutSize(
        widthDimension: .absolute(cardWidth),
        heightDimension: .fractionalHeight(1.0)
      )
      let item = NSCollectionLayoutItem(layoutSize: itemSize)

      // Group: one row of cards that fills the available width
      let labelAreaHeight = AlbumCollectionCell
        .labelAreaHeight(for: environment.traitCollection, defaultHeight: 50.0)
      let groupSize = NSCollectionLayoutSize(
        widthDimension: .fractionalWidth(1.0),
        heightDimension: .absolute(cardWidth + labelAreaHeight)
      )
      let group = NSCollectionLayoutGroup.horizontal(
        layoutSize: groupSize,
        subitems: Array(repeating: item, count: columns)
      )
      group.interItemSpacing = .fixed(itemSpacing)

      let sectionLayout = NSCollectionLayoutSection(group: group)
      sectionLayout.interGroupSpacing = 20
      sectionLayout.contentInsets = NSDirectionalEdgeInsets(
        top: 12,
        leading: sectionHorizontalInset,
        bottom: 28,
        trailing: sectionHorizontalInset
      )

      // Header
      let headerSize = NSCollectionLayoutSize(
        widthDimension: .fractionalWidth(1.0),
        heightDimension: sectionIndex == 0 ? .absolute(112) : .estimated(44)
      )
      let header = NSCollectionLayoutBoundarySupplementaryItem(
        layoutSize: headerSize,
        elementKind: UICollectionView.elementKindSectionHeader,
        alignment: .top
      )
      header.pinToVisibleBounds = false
      header.zIndex = 1
      sectionLayout.boundarySupplementaryItems = [header]

      return sectionLayout
    }
    return layout
  }

  // MARK: - CollectionView Setup

  private func configureCollectionView() {
    collectionView.backgroundColor = .systemBackground
    collectionView.register(
      UINib(nibName: AlbumCollectionCell.typeName, bundle: .main),
      forCellWithReuseIdentifier: AlbumCollectionCell.typeName
    )
    collectionView.register(
      SectionHeaderView.self,
      forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
      withReuseIdentifier: SectionHeaderView.reuseID
    )
  }

  // MARK: - Data Source

  private func configureDataSource() {
    dataSource = UICollectionViewDiffableDataSource<
      HomeSection,
      HomeItem
    >(collectionView: collectionView) { collectionView, indexPath, item in
      let cell = collectionView.dequeueReusableCell(
        withReuseIdentifier: AlbumCollectionCell.typeName,
        for: indexPath
      ) as! AlbumCollectionCell
      let contentWidth = collectionView.bounds.width > 0 ? collectionView.bounds.width : 800
      cell.display(
        container: item.playableContainable,
        rootView: self,
        itemWidth: Self.itemWidth(for: contentWidth),
        initialIndexPath: indexPath
      )
      return cell
    }

    dataSource.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
      guard kind == UICollectionView.elementKindSectionHeader,
            let header = collectionView.dequeueReusableSupplementaryView(
              ofKind: kind,
              withReuseIdentifier: SectionHeaderView.reuseID,
              for: indexPath
            ) as? SectionHeaderView,
            let section = self?.sharedHome.orderedVisibleSections.element(at: indexPath.section)
      else {
        return nil
      }
      header.title = section.title
      header.largeTitle = indexPath.section == 0 ? L10n.tr("Home") : nil
      if section == .randomAlbums {
        header.showsRefreshButton = true
        header.setRefreshHandler { [weak self] in self?.refreshRandomAlbumsSection() }
      } else if section == .randomArtists {
        header.showsRefreshButton = true
        header.setRefreshHandler { [weak self] in self?.refreshRandomArtistsSection() }
      } else if section == .randomGenres {
        header.showsRefreshButton = true
        header.setRefreshHandler { [weak self] in self?.refreshRandomGenresSection() }
      } else if section == .randomSongs {
        header.showsRefreshButton = true
        header.setRefreshHandler { [weak self] in self?.refreshRandomSongsSection() }
      } else {
        header.showsRefreshButton = false
        header.setRefreshHandler(nil)
      }
      return header
    }
  }

  private func applySnapshot(animated: Bool = true) {
    var snapshot = NSDiffableDataSourceSnapshot<HomeSection, HomeItem>()
    snapshot.appendSections(sharedHome.orderedVisibleSections)
    for section in sharedHome.orderedVisibleSections {
      // Ids are stable per entity, so a repeated entity would be a duplicate identifier (assert).
      var seenIds = Set<String>()
      let items = (sharedHome.data[section] ?? []).filter { seenIds.insert($0.id).inserted }
      snapshot.appendItems(items, toSection: section)
    }
    let oldItems = dataSource.snapshot().itemIdentifiers
    let oldFingerprints = Dictionary(oldItems.map { ($0.id, $0.artworkFingerprint) }) { first, _ in
      first
    }
    let changedItems = snapshot.itemIdentifiers.filter {
      guard let old = oldFingerprints[$0.id] else { return false }
      return old != $0.artworkFingerprint
    }
    snapshot.reconfigureItems(changedItems)
    dataSource.apply(snapshot, animatingDifferences: animated)
  }

  @objc
  private func refreshOfflineMode() {
    os_log("HomeVC: OfflineModeChanged", log: self.log, type: .info)
    sharedHome.createFetchController()
  }

  @objc
  private func editSectionsTapped() {
    presentSectionEditor()
  }

  private func presentSectionEditor() {
    // Build a simple editor using a temporary UIViewController with a table view
    let editor = HomeEditorVC(
      order: appDelegate.storage.settings.accounts.getSetting(account.info).read.homeSectionOrder,
      visible: sharedHome.orderedVisibleSections
    ) { [weak self] order, visible in
      guard let self else { return }
      sharedHome.orderedVisibleSections = visible
      // same account the order was read from
      appDelegate.storage.settings.accounts.updateSetting(account.info) { accountSettings in
        accountSettings.homeSections = visible
        accountSettings.homeSectionOrder = order
      }
      applySnapshot(animated: true)

      sharedHome.createFetchController()
      sharedHome.updateFromRemote()
    }
    #if targetEnvironment(macCatalyst)
      // reordering via drag & drop did not drop inside a form sheet on macOS
      // revert to the form sheet once fixed: https://developer.apple.com/forums/thread/850756
      navigationController?.pushViewController(editor, animated: true)
    #else
      let nav = UINavigationController(rootViewController: editor)
      nav.modalPresentationStyle = .formSheet
      present(nav, animated: true)
    #endif
  }

  @objc
  func refreshRandomAlbumsSection() {
    Task { @MainActor in
      await sharedHome.updateRandomAlbums(isOfflineMode: sharedHome.isOfflineMode)
    }
  }

  @objc
  func refreshRandomArtistsSection() {
    Task { @MainActor in
      await sharedHome.updateRandomArtists(isOfflineMode: sharedHome.isOfflineMode)
    }
  }

  @objc
  func refreshRandomGenresSection() {
    Task { @MainActor in
      await sharedHome.updateRandomGenres()
    }
  }

  @objc
  func refreshRandomSongsSection() {
    Task { @MainActor in
      await sharedHome.updateRandomSongs(isOfflineMode: sharedHome.isOfflineMode)
    }
  }

  // MARK: - Selection Handling

  override func collectionView(
    _ collectionView: UICollectionView,
    didSelectItemAt indexPath: IndexPath
  ) {
    guard let playableContainer = dataSource.itemIdentifier(for: indexPath)?.playableContainable
    else { return }

    if let album = playableContainer as? Album {
      navigationController?.pushViewController(
        AppStoryboard.Main.segueToAlbumDetail(account: account, album: album),
        animated: true
      )
      navigationController?.navigationBar.prefersLargeTitles = false
    } else if let artist = playableContainer as? Artist {
      navigationController?.pushViewController(
        AppStoryboard.Main.segueToArtistDetail(account: account, artist: artist),
        animated: true
      )
      navigationController?.navigationBar.prefersLargeTitles = false
    } else if let playlist = playableContainer as? Playlist {
      navigationController?.pushViewController(
        AppStoryboard.Main.segueToPlaylistDetail(account: account, playlist: playlist),
        animated: true
      )
      navigationController?.navigationBar.prefersLargeTitles = false
    } else if let song = playableContainer as? Song {
      appDelegate.player.play(context: PlayContext(containable: song))
    } else if let genre = playableContainer as? Genre {
      navigationController?.pushViewController(
        AppStoryboard.Main.segueToGenreDetail(account: account, genre: genre),
        animated: true
      )
      navigationController?.navigationBar.prefersLargeTitles = false
    }
  }
}

extension HomeVC {
  override func collectionView(
    _ collectionView: UICollectionView,
    contextMenuConfigurationForItemAt indexPath: IndexPath,
    point: CGPoint
  )
    -> UIContextMenuConfiguration? {
    guard let containable = dataSource.itemIdentifier(for: indexPath)?.playableContainable
    else { return nil }

    let identifier = NSString(string: TableViewPreviewInfo(
      playableContainerIdentifier: containable.containerIdentifier,
      indexPath: indexPath
    ).asJSONString())
    return UIContextMenuConfiguration(identifier: identifier, previewProvider: {
      let vc = EntityPreviewVC()
      vc.display(container: containable, on: self)
      Task { @MainActor in
        do {
          try await containable.fetch(
            storage: self.appDelegate.storage,
            librarySyncer: self.appDelegate.getMeta(self.account.info).librarySyncer,
            playableDownloadManager: self.appDelegate.getMeta(self.account.info)
              .playableDownloadManager
          )
        } catch {
          self.appDelegate.eventLogger.report(topic: "Preview Sync", error: error)
        }
        vc.refresh()
      }
      return vc
    }) { suggestedActions in
      var playIndexCB: (() -> PlayContext?)?
      playIndexCB = { PlayContext(containable: containable) }
      return EntityPreviewActionBuilder(
        container: containable,
        on: self,
        playContextCb: playIndexCB
      ).createMenu()
    }
  }

  override func collectionView(
    _ collectionView: UICollectionView,
    willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
    animator: UIContextMenuInteractionCommitAnimating
  ) {
    animator.addCompletion {
      if let identifier = configuration.identifier as? String,
         let tvPreviewInfo = TableViewPreviewInfo.create(fromIdentifier: identifier),
         let containerIdentifier = tvPreviewInfo.playableContainerIdentifier,
         let container = self.appDelegate.storage.main.library
         .getContainer(identifier: containerIdentifier) {
        EntityPreviewActionBuilder(container: container, on: self).performPreviewTransition()
      }
    }
  }
}

// MARK: - SectionHeaderView

final class SectionHeaderView: UICollectionReusableView {
  static let reuseID = "SectionHeaderView"

  private let refreshButton: UIButton = {
    let btn = UIButton(type: .system)
    btn.translatesAutoresizingMaskIntoConstraints = false
    btn.setImage(UIImage.refresh, for: .normal)
    btn.isHidden = true
    btn.accessibilityLabel = L10n.tr("Refresh Randoms")
    return btn
  }()

  private let largeTitleLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 34, weight: .bold)
    label.textColor = .label
    label.isHidden = true
    return label
  }()

  private var largeTitleHeightConstraint: NSLayoutConstraint!

  private let titleLabel: UILabel = {
    let lbl = ScaledLabel()
    lbl.translatesAutoresizingMaskIntoConstraints = false
    // title 3 at the default text size, scaled with the user's text size
    let defaultTraits = UITraitCollection(preferredContentSizeCategory: .large)
    let font = UIFont.preferredFont(forTextStyle: .title3, compatibleWith: defaultTraits)
      .withWeight(.semibold)
    lbl.font = UIFontMetrics(forTextStyle: .title3).scaledFont(for: font)
    lbl.adjustsFontForContentSizeCategory = true
    lbl.textColor = .label
    return lbl
  }()

  var showsRefreshButton: Bool {
    get { !refreshButton.isHidden }
    set { refreshButton.isHidden = !newValue }
  }

  func setRefreshHandler(_ handler: (() -> ())?) {
    refreshButton.removeTarget(nil, action: nil, for: .allEvents)
    guard let handler else { return }
    refreshButton.addAction(UIAction { _ in handler() }, for: .touchUpInside)
  }

  var title: String? {
    didSet { titleLabel.text = title }
  }

  var largeTitle: String? {
    didSet {
      largeTitleLabel.text = largeTitle
      largeTitleLabel.isHidden = largeTitle == nil
      largeTitleHeightConstraint.constant = largeTitle == nil ? 0 : 52
    }
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    configure()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configure()
  }

  private func configure() {
    largeTitleHeightConstraint = largeTitleLabel.heightAnchor.constraint(equalToConstant: 0)
    addSubview(largeTitleLabel)
    addSubview(titleLabel)
    addSubview(refreshButton)
    NSLayoutConstraint.activate([
      largeTitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
      largeTitleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
      largeTitleHeightConstraint,
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
      titleLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: refreshButton.leadingAnchor,
        constant: -8
      ),
      titleLabel.topAnchor.constraint(equalTo: largeTitleLabel.bottomAnchor),
      titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
      refreshButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
      refreshButton.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }
}

extension UIFont {
  fileprivate func withWeight(_ weight: UIFont.Weight) -> UIFont {
    let descriptor = fontDescriptor.addingAttributes([
      UIFontDescriptor.AttributeName.traits: [UIFontDescriptor.TraitKey.weight: weight],
    ])
    return UIFont(descriptor: descriptor, size: pointSize)
  }
}
