//
//  MainViewController.swift
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

/// Root content controller of the main window.
///
/// Layout (Apple Music style):
///   ┌────────────┬──────────────────────┬──────────────┐
///   │ sidebar    │ library content      │ lyrics pane  │
///   │ (210 pt)   │                      │ (optional)   │
///   └────────────┴──────────────────────┴──────────────┘
///        ╭──────────────────────────────────────────╮
///        │ floating capsule player bar              │
///        ╰──────────────────────────────────────────╯
@MainActor
final class MainViewController: NSViewController {
  private(set) var sidebarViewController = SidebarViewController()
  private(set) var contentContainerViewController = NSViewController()
  private(set) var playerBarViewController = PlayerBarViewController()
  private(set) lazy var lyricsPaneViewController = LyricsPageViewController()

  private let splitViewController = NSSplitViewController()
  private var lyricsPaneItem: NSSplitViewItem?
  private(set) var isLyricsPaneVisible = false

  override func loadView() {
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 1024, height: 768))
    root.wantsLayer = true

    // Sidebar | content | optional lyrics pane.
    let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarViewController)
    sidebarItem.minimumThickness = 190
    sidebarItem.maximumThickness = 240
    sidebarItem.canCollapse = false
    sidebarItem.holdingPriority = NSLayoutConstraint.Priority(280)

    let contentItem = NSSplitViewItem(viewController: contentContainerViewController)
    contentItem.minimumThickness = 380
    // The content column absorbs the space freed when the lyrics pane collapses.
    contentItem.holdingPriority = NSLayoutConstraint.Priority(240)

    let lyricsItem = NSSplitViewItem(viewController: lyricsPaneViewController)
    lyricsItem.minimumThickness = 280
    lyricsItem.maximumThickness = 340
    lyricsItem.canCollapse = true
    lyricsItem.isCollapsed = true
    lyricsItem.holdingPriority = NSLayoutConstraint.Priority(270)
    lyricsPaneItem = lyricsItem

    splitViewController.addSplitViewItem(sidebarItem)
    splitViewController.addSplitViewItem(contentItem)
    splitViewController.addSplitViewItem(lyricsItem)
    splitViewController.splitView.dividerStyle = .thin

    addChild(splitViewController)
    splitViewController.view.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(splitViewController.view)

    // The player capsule floats over the library content column (Apple Music style):
    // the content scrolls underneath it, the sidebar and lyrics pane stay full height.
    contentContainerViewController.view.wantsLayer = true
    addChild(playerBarViewController)
    let capsuleView = playerBarViewController.view
    capsuleView.translatesAutoresizingMaskIntoConstraints = false
    contentContainerViewController.view.addSubview(capsuleView)

    let capsuleWidth = capsuleView.widthAnchor.constraint(
      equalTo: contentContainerViewController.view.widthAnchor,
      constant: -40
    )
    capsuleWidth.priority = .defaultHigh
    capsuleWidth.isActive = true

    NSLayoutConstraint.activate([
      splitViewController.view.topAnchor.constraint(equalTo: root.topAnchor),
      splitViewController.view.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      splitViewController.view.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      splitViewController.view.bottomAnchor.constraint(equalTo: root.bottomAnchor),

      capsuleView.centerXAnchor.constraint(equalTo: contentContainerViewController.view.centerXAnchor),
      capsuleView.bottomAnchor.constraint(
        equalTo: contentContainerViewController.view.bottomAnchor,
        constant: -12
      ),
      capsuleView.heightAnchor.constraint(
        equalToConstant: PlayerBarViewController.capsuleHeight
      ),
      capsuleView.widthAnchor.constraint(lessThanOrEqualToConstant: 720),
      capsuleView.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
    ])

    self.view = root
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    sidebarViewController.onSelectionChanged = { [weak self] item in
      self?.show(item: item)
    }
    playerBarViewController.onToggleLyricsPane = { [weak self] in
      self?.toggleLyricsPane()
    }

    // Dev hooks: `--songs` or `--page <sidebar-item-raw-value>` open a page directly.
    let arguments = ProcessInfo.processInfo.arguments
    var initialItem: SidebarItem = .home
    if let pageIndex = arguments.firstIndex(of: "--page"),
       pageIndex + 1 < arguments.count,
       let item = SidebarItem(rawValue: arguments[pageIndex + 1]) {
      initialItem = item
    } else if arguments.contains("--songs") {
      initialItem = .songs
    }
    sidebarViewController.select(item: initialItem)
    show(item: initialItem)

    // Restore the lyrics side pane from the shared setting.
    setLyricsPaneVisible(
      FmusicKit.shared.storage.settings.user.isPlayerLyricsDisplayed,
      persist: false
    )
  }

  private var didApplyInitialSplitPositions = false

  override func viewDidAppear() {
    super.viewDidAppear()
    guard !didApplyInitialSplitPositions else { return }
    didApplyInitialSplitPositions = true
    let splitView = splitViewController.splitView
    splitView.setPosition(210, ofDividerAt: 0)
    if isLyricsPaneVisible, splitView.subviews.count > 2 {
      splitView.setPosition(splitView.bounds.width - 310, ofDividerAt: 1)
    }
  }

  /// Selects a sidebar entry programmatically (used by menu shortcuts) and shows its page.
  func select(item: SidebarItem) {
    sidebarViewController.select(item: item)
    show(item: item)
  }

  // MARK: - Lyrics pane

  func toggleLyricsPane() {
    setLyricsPaneVisible(!isLyricsPaneVisible, persist: true)
  }

  private func setLyricsPaneVisible(_ visible: Bool, persist: Bool) {
    isLyricsPaneVisible = visible
    lyricsPaneItem?.isCollapsed = !visible
    playerBarViewController.isLyricsPaneVisible = visible
    if persist {
      SettingsStore.updateUser { $0.isPlayerLyricsDisplayed = visible }
    }
    guard visible else { return }
    let splitView = splitViewController.splitView
    DispatchQueue.main.async { [weak self, weak splitView] in
      guard let self, let splitView, splitView.subviews.count > 2 else { return }
      splitView.setPosition(
        max(self.sidebarViewController.view.frame.width, splitView.bounds.width - 340),
        ofDividerAt: 1
      )
    }
  }

  // MARK: - Content

  private func show(item: SidebarItem) {
    let controller: NSViewController
    switch item {
    case .home: controller = HomeViewController()
    case .songs: controller = SongsViewController()
    case .artists: controller = ArtistsViewController()
    case .albums: controller = AlbumsViewController()
    case .newestAlbums: controller = NewestAlbumsViewController()
    case .recentlyPlayed: controller = RecentlyPlayedViewController()
    case .search: controller = SearchViewController()
    case .favoriteSongs: controller = FavoriteSongsViewController()
    case .playlists: controller = PlaylistsViewController()
    case .podcasts: controller = PodcastsViewController()
    case .directories: controller = DirectoriesViewController()
    case .radios: controller = RadiosViewController()
    case .downloads: controller = DownloadsViewController()
    case .lyricsSearch: controller = LyricsSearchViewController()
    }
    for child in contentContainerViewController.children {
      child.view.removeFromSuperview()
      child.removeFromParent()
    }
    controller.view.translatesAutoresizingMaskIntoConstraints = false
    contentContainerViewController.view.addSubview(controller.view)
    NSLayoutConstraint.activate([
      controller.view.topAnchor.constraint(equalTo: contentContainerViewController.view.topAnchor),
      controller.view.leadingAnchor.constraint(equalTo: contentContainerViewController.view.leadingAnchor),
      controller.view.trailingAnchor.constraint(equalTo: contentContainerViewController.view.trailingAnchor),
      controller.view.bottomAnchor.constraint(equalTo: contentContainerViewController.view.bottomAnchor),
    ])
    contentContainerViewController.addChild(controller)
    applyCapsuleContentInset(to: controller.view)
    contentContainerViewController.view.addSubview(
      playerBarViewController.view,
      positioned: .above,
      relativeTo: nil
    )
  }

  /// Reserves space under the floating capsule so the last rows can scroll above it.
  private func applyCapsuleContentInset(to view: NSView) {
    let extra = PlayerBarViewController.capsuleHeight + 26
    for scrollView in allScrollViews(in: view) {
      var insets = scrollView.contentInsets
      insets.bottom = max(insets.bottom, extra)
      scrollView.contentInsets = insets
    }
  }

  private func allScrollViews(in view: NSView) -> [NSScrollView] {
    var result: [NSScrollView] = []
    if let scrollView = view as? NSScrollView {
      result.append(scrollView)
    }
    for subview in view.subviews {
      result.append(contentsOf: allScrollViews(in: subview))
    }
    return result
  }
}
