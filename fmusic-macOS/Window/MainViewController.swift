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
/// Layout (Catalyst fmusic style):
///   ┌────────────┬──────────────────────┬──────────────┐
///   │ sidebar    │ content toolbar      │ lyrics pane  │
///   │ (210 pt)   ├──────────────────────┤ (optional)   │
///   │            │ page content         │              │
///   └────────────┴──────────────────────┴──────────────┘
///        ╭──────────────────────────────────────────╮
///        │ floating capsule player bar              │
///        ╰──────────────────────────────────────────╯
@MainActor
final class MainViewController: NSViewController {
  static weak var current: MainViewController?

  private(set) var sidebarViewController = SidebarViewController()
  private(set) var contentContainerViewController = NSViewController()
  private(set) var playerBarViewController = PlayerBarViewController()
  private(set) lazy var lyricsPaneViewController = LyricsSidebarViewController()

  private let splitViewController = NSSplitViewController()
  private let toolbar = ContentToolbarView()
  private let pageContainer = NSViewController()
  private var pageStack: [NSViewController] = []
  private var pageTitles: [String] = []
  private var lyricsPaneItem: NSSplitViewItem?
  private var sidebarItem: NSSplitViewItem?
  private(set) var isLyricsPaneVisible = false

  private var didApplyInitialSplitPositions = false
  private var nowPlayingWindow: NSWindow?

  override func loadView() {
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 1024, height: 768))
    root.wantsLayer = true

    // Sidebar | content | optional lyrics pane.
    let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarViewController)
    sidebarItem.minimumThickness = 210
    sidebarItem.maximumThickness = 210
    sidebarItem.canCollapse = true
    sidebarItem.holdingPriority = NSLayoutConstraint.Priority(280)
    self.sidebarItem = sidebarItem

    let contentItem = NSSplitViewItem(viewController: contentContainerViewController)
    contentItem.minimumThickness = 380
    contentItem.holdingPriority = NSLayoutConstraint.Priority(240)

    let lyricsItem = NSSplitViewItem(viewController: lyricsPaneViewController)
    lyricsItem.minimumThickness = 210
    lyricsItem.maximumThickness = 210
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

    // Content column: toolbar on top, pushed pages below, floating capsule on top.
    addChild(pageContainer)
    contentContainerViewController.view.wantsLayer = true
    toolbar.translatesAutoresizingMaskIntoConstraints = false
    pageContainer.view.translatesAutoresizingMaskIntoConstraints = false
    contentContainerViewController.view.addSubview(toolbar)
    contentContainerViewController.view.addSubview(pageContainer.view)

    addChild(playerBarViewController)
    let capsuleView = playerBarViewController.view
    // Manual frame layout: the floating capsule must never contribute to the content
    // column's minimum size (otherwise opening the lyrics pane grows the window).
    capsuleView.translatesAutoresizingMaskIntoConstraints = true
    root.addSubview(capsuleView)

    NSLayoutConstraint.activate([
      splitViewController.view.topAnchor.constraint(equalTo: root.topAnchor),
      splitViewController.view.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      splitViewController.view.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      splitViewController.view.bottomAnchor.constraint(equalTo: root.bottomAnchor),

      toolbar.topAnchor.constraint(equalTo: contentContainerViewController.view.topAnchor),
      toolbar.leadingAnchor.constraint(equalTo: contentContainerViewController.view.leadingAnchor),
      toolbar.trailingAnchor.constraint(equalTo: contentContainerViewController.view.trailingAnchor),
      toolbar.heightAnchor.constraint(equalToConstant: ContentToolbarView.height),

      pageContainer.view.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
      pageContainer.view.leadingAnchor.constraint(equalTo: contentContainerViewController.view.leadingAnchor),
      pageContainer.view.trailingAnchor.constraint(equalTo: contentContainerViewController.view.trailingAnchor),
      pageContainer.view.bottomAnchor.constraint(equalTo: contentContainerViewController.view.bottomAnchor),
    ])

    self.view = root
    Self.current = self
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    sidebarViewController.onSelectionChanged = { [weak self] item in
      self?.showRoot(item: item)
    }
    playerBarViewController.onToggleLyricsPane = { [weak self] in
      self?.toggleLyricsPane()
    }
    sidebarViewController.onToggleSidebar = { [weak self] in
      self?.toggleSidebar()
    }
    sidebarViewController.onEditHome = { [weak self] in
      guard let self else { return }
      self.select(item: .home)
      (self.pageStack.first as? HomeViewController)?.presentSectionEditor()
    }
    sidebarViewController.onOpenSettings = {
      AppDelegate.sharedAppDelegate?.showSettings(nil)
    }
    toolbar.onBack = { [weak self] in
      self?.pop()
    }
    toolbar.onSearchChange = { [weak self] text in
      self?.currentPageDidChangeSearch(text: text)
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
    showRoot(item: initialItem)

    // Dev hook: `--album <name>` pushes an album detail page directly.
    if let index = arguments.firstIndex(of: "--album"), index + 1 < arguments.count {
      let name = arguments[index + 1]
      DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
        guard let self,
              let accountInfo = FmusicKit.shared.storage.settings.accounts.active
        else { return }
        let library = FmusicKit.shared.storage.main.library
        let account = library.getAccount(info: accountInfo)
        if let album = library.getAlbums(for: account)
          .first(where: { $0.name.contains(name) }) {
          self.openAlbum(album)
        }
      }
    }

    // Dev hook: `--artist <name>` pushes an artist detail page directly.
    if let index = arguments.firstIndex(of: "--artist"), index + 1 < arguments.count {
      let name = arguments[index + 1]
      DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
        guard let self,
              let accountInfo = FmusicKit.shared.storage.settings.accounts.active
        else { return }
        let library = FmusicKit.shared.storage.main.library
        let account = library.getAccount(info: accountInfo)
        if let artist = library.getArtists(for: account)
          .first(where: { $0.name.contains(name) }) {
          self.openArtist(artist)
        }
      }
    }

    if let index = arguments.firstIndex(of: "--playlist"), index + 1 < arguments.count {
      let name = arguments[index + 1]
      DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
        guard let self,
              let accountInfo = FmusicKit.shared.storage.settings.accounts.active
        else { return }
        let library = FmusicKit.shared.storage.main.library
        let account = library.getAccount(info: accountInfo)
        if let playlist = library.getPlaylists(for: account)
          .first(where: { $0.name.contains(name) }) {
          let detail = PlaylistDetailViewController(playlist: playlist)
          self.push(detail, title: playlist.name)
        }
      }
    }

    if ProcessInfo.processInfo.arguments.contains("--toggle-lyrics-demo") {
      DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
        self?.toggleLyricsPane()
      }
    }

    // Restore the lyrics side pane from the shared setting.
    setLyricsPaneVisible(
      FmusicKit.shared.storage.settings.user.isPlayerLyricsDisplayed,
      persist: false
    )
  }

  override func viewDidLayout() {
    super.viewDidLayout()
    layoutPlayerCapsule()
  }

  override func viewDidAppear() {
    super.viewDidAppear()
    guard !didApplyInitialSplitPositions else { return }
    didApplyInitialSplitPositions = true
    let splitView = splitViewController.splitView
    splitView.setPosition(210, ofDividerAt: 0)
    if isLyricsPaneVisible, splitView.subviews.count > 2 {
      splitView.setPosition(splitView.bounds.width - 210, ofDividerAt: 1)
    }
  }

  private func layoutPlayerCapsule() {
    // The capsule lives inside the content column and scales with it: opening the
    // lyrics pane shrinks the middle column, so the capsule shrinks too.
    let sidebarWidth: CGFloat = (sidebarItem?.isCollapsed ?? false) ? 0 : 210
    let lyricsWidth: CGFloat = isLyricsPaneVisible ? 210 : 0
    let available = view.bounds.width - sidebarWidth - lyricsWidth
    guard available > 0 else { return }
    let width = min(780, max(300, available - 16))
    let height = PlayerBarViewController.capsuleHeight
    playerBarViewController.view.frame = NSRect(
      x: sidebarWidth + (available - width) / 2,
      y: 12,
      width: width,
      height: height
    )
  }

  // MARK: - Now Playing overlay

  /// Full-window Now Playing page, presented over the whole main window like the
  /// Catalyst `PopupPlayerVC`.
  func presentNowPlayingOverlay() {
    NSLog("fmusic: overlay requested")
    dismissNowPlayingOverlay(animated: false)
    guard let parent = view.window ?? NSApp.windows.first(where: { $0.isVisible }) else { return }
    let controller = NowPlayingViewController()
    controller.onClose = { [weak self] in
      self?.dismissNowPlayingOverlay(animated: true)
    }
    let overlayWindow = NowPlayingOverlayWindow(contentViewController: controller)
    overlayWindow.styleMask = [.borderless]
    overlayWindow.isOpaque = false
    overlayWindow.backgroundColor = .clear
    overlayWindow.hasShadow = false
    overlayWindow.setFrame(parent.frame, display: true)
    // Match the main window's rounded corners instead of a square borderless window.
    if let content = overlayWindow.contentView {
      content.wantsLayer = true
      content.layer?.cornerRadius = 12
      content.layer?.cornerCurve = .continuous
      content.layer?.masksToBounds = true
    }
    parent.addChildWindow(overlayWindow, ordered: .above)
    NSLog("fmusic: overlay added \(overlayWindow.frame)")
    overlayWindow.orderFront(nil)
    nowPlayingWindow = overlayWindow
  }

  func dismissNowPlayingOverlay(animated: Bool) {
    guard let window = nowPlayingWindow else { return }
    nowPlayingWindow = nil
    window.parent?.removeChildWindow(window)
    window.orderOut(nil)
  }

  /// Selects a sidebar entry programmatically (used by menu shortcuts) and shows its page.
  func select(item: SidebarItem) {
    sidebarViewController.select(item: item)
    showRoot(item: item)
  }

  // MARK: - Navigation

  private func showRoot(item: SidebarItem) {
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
    pageStack.forEach(removePage)
    pageStack = [controller]
    pageTitles = [item.title]
    attach(controller)
    updateToolbar(title: item.title, showsBack: false)
  }

  /// Pushes a detail page over the current one (back button appears in the toolbar).
  func push(_ controller: NSViewController, title: String) {
    pageStack.append(controller)
    pageTitles.append(title)
    attach(controller)
    updateToolbar(title: title, showsBack: true)
  }

  func pop() {
    guard pageStack.count > 1 else { return }
    let controller = pageStack.removeLast()
    pageTitles.removeLast()
    removePage(controller)
    updateToolbar(
      title: pageTitles.last ?? "",
      showsBack: pageStack.count > 1
    )
  }

  /// Opens the home screen and its section editor (toolbar 编辑 button).
  func presentHomeEditor() {
    select(item: .home)
    (pageStack.first as? HomeViewController)?.presentSectionEditor()
  }

  func openAlbum(_ album: Album) {
    push(AlbumDetailViewController(album: album), title: album.name)
  }

  /// Collapses/expands the library sidebar (View > Show Sidebar).
  func toggleSidebar() {
    guard let sidebarItem else { return }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.2
      sidebarItem.animator().isCollapsed.toggle()
    }
    DispatchQueue.main.async { [weak self] in
      self?.layoutPlayerCapsule()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
      self?.layoutPlayerCapsule()
    }
  }

  func openArtist(_ artist: Artist) {
    push(ArtistDetailViewController(artist: artist), title: artist.name)
  }

  private func attach(_ controller: NSViewController) {
    controller.view.translatesAutoresizingMaskIntoConstraints = false
    pageContainer.view.addSubview(controller.view)
    NSLayoutConstraint.activate([
      controller.view.topAnchor.constraint(equalTo: pageContainer.view.topAnchor),
      controller.view.leadingAnchor.constraint(equalTo: pageContainer.view.leadingAnchor),
      controller.view.trailingAnchor.constraint(equalTo: pageContainer.view.trailingAnchor),
      controller.view.bottomAnchor.constraint(equalTo: pageContainer.view.bottomAnchor),
    ])
    pageContainer.addChild(controller)
    applyCapsuleContentInset(to: controller.view)
    view.addSubview(playerBarViewController.view, positioned: .above, relativeTo: nil)
  }

  private func removePage(_ controller: NSViewController) {
    controller.view.removeFromSuperview()
    controller.removeFromParent()
  }

  private func updateToolbar(title: String, showsBack: Bool) {
    let searchable = pageStack.last as? ContentSearchable
    toolbar.configure(
      title: title,
      showsBack: showsBack,
      searchPlaceholder: searchable?.contentSearchPlaceholder
    )
  }

  private func currentPageDidChangeSearch(text: String) {
    (pageStack.last as? ContentSearchable)?.contentSearchDidChange(text: text)
  }

  // MARK: - Lyrics pane

  func toggleLyricsPane() {
    setLyricsPaneVisible(!isLyricsPaneVisible, persist: true)
  }

  private func setLyricsPaneVisible(_ visible: Bool, persist: Bool) {
    let window = view.window
    let sizeBeforeToggle = window?.contentLayoutRect.size
    isLyricsPaneVisible = visible
    lyricsPaneItem?.isCollapsed = !visible
    playerBarViewController.isLyricsPaneVisible = visible

    // Opening/closing the pane changes the middle column width: re-centre the capsule.
    DispatchQueue.main.async { [weak self] in self?.layoutPlayerCapsule() }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
      self?.layoutPlayerCapsule()
    }
    // Opening/closing the pane only shrinks/grows the middle column, the window keeps
    // its size (restore it explicitly in case AppKit grew it to satisfy constraints).
    if let window, let sizeBeforeToggle {
      DispatchQueue.main.async {
        var frame = window.frame
        let currentContent = window.contentLayoutRect.size
        let deltaHeight = currentContent.height - sizeBeforeToggle.height
        let deltaWidth = currentContent.width - sizeBeforeToggle.width
        if abs(deltaHeight) > 0.5 || abs(deltaWidth) > 0.5 {
          frame.size.width -= deltaWidth
          frame.size.height -= deltaHeight
          window.setFrame(frame, display: true)
        }
      }
    }
    if persist {
      SettingsStore.updateUser { $0.isPlayerLyricsDisplayed = visible }
    }
    guard visible else { return }
    let splitView = splitViewController.splitView
    DispatchQueue.main.async { [weak self, weak splitView] in
      guard let self, let splitView, splitView.subviews.count > 2 else { return }
      splitView.setPosition(
        max(210, splitView.bounds.width - 210),
        ofDividerAt: 1
      )
    }
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

private final class NowPlayingOverlayWindow: NSWindow {
  /// AppKit grows borderless windows to the content view's fitting size; pin the
  /// overlay to the parent window rectangle so it covers it exactly.
  override func setFrame(_ frameRect: NSRect, display flag: Bool) {
    var rect = frameRect
    if let parent {
      rect.size = parent.frame.size
      rect.origin = parent.frame.origin
    }
    super.setFrame(rect, display: flag)
  }

  override func mouseDown(with event: NSEvent) {
    if let parent {
      parent.performDrag(with: event)
    } else {
      super.mouseDown(with: event)
    }
  }
}
