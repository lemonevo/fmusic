//
//  PopupPlayerVC.swift
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
import CoreMedia
import UIKit

// MARK: - PopupPlayerVC

class PopupPlayerVC: UIViewController, UIScrollViewDelegate {
  @IBOutlet
  weak var tableView: UITableView!
  @IBOutlet
  weak var largePlayerPlaceholderView: UIView!
  @IBOutlet
  weak var controlPlaceholderView: UIView!
  @IBOutlet
  weak var backgroundImage: UIImageView!
  @IBOutlet
  weak var closeButtonPlaceholderView: UIView!

  @IBOutlet
  weak var controlPlaceholderHeightConstraint: NSLayoutConstraint!
  private let safetyMarginOnBottom = 20.0
  internal var artworkGradientColors = [UIColor]()

  lazy var tableViewKeyCommandsController = TableViewKeyCommandsController(
    tableView: tableView,
    overrideFirstLastIndexPath: IndexPath(
      row: 0,
      section: PlayerSectionCategory.currentlyPlaying.rawValue
    )
  )

  var player: PlayerFacade!
  var playerHandler: PlayerUIHandler?
  var controlView: PlayerControlView?
  var largeCurrentlyPlayingView: LargeCurrentlyPlayingPlayerView?
  var accountNotificationHandler: AccountNotificationHandler?

  private var volumeSliderControl: UIView?
  #if targetEnvironment(macCatalyst)
    var windowVolumeControl: PlayerWindowVolumeControl?
    private var isPlayerVisible = false
  #endif
  private var closeButtonControl: UIButton?
  private var largeLyricsColumnView: UIView?
  private var controlFullWidthConstraint: NSLayoutConstraint?
  private var controlSplitConstraint: NSLayoutConstraint?

  var currentlyPlayingTableCell: CurrentlyPlayingTableCell?
  var contextPrevQueueSectionHeader: ContextQueuePrevSectionHeader?
  var userQueueSectionHeader: UserQueueSectionHeader?
  var contextNextQueueSectionHeader: ContextQueueNextSectionHeader?
  var activeDisplayedSectionHeader = Set<PlayerSectionCategory>()
  lazy var clearEmptySectionFooter = {
    let view = UIView()
    view.backgroundColor = .clear
    view.isHidden = true
    return view
  }()

  override func viewDidLoad() {
    super.viewDidLoad()

    // The player follows Apple Music's dark, artwork-driven surface: white lyrics and white
    // controls stay readable on the blurred artwork.
    overrideUserInterfaceStyle = .dark

    tableView.delegate = self
    tableView.dataSource = self
    tableView.dragDelegate = self
    tableView.dropDelegate = self
    tableView.dragInteractionEnabled = true

    player = appDelegate.player
    player.addNotifier(notifier: self)
    playerHandler = PlayerUIHandler(player: player, style: .popupPlayer)

    backgroundImage.setBackgroundBlur(style: .prominent)

    // Dim the blurred artwork so white lyrics and controls keep enough contrast. This is the
    // dark scrim Apple Music puts over the full player background.
    let scrim = UIView()
    scrim.translatesAutoresizingMaskIntoConstraints = false
    scrim.backgroundColor = UIColor.black.withAlphaComponent(0.15)
    scrim.isUserInteractionEnabled = false
    view.insertSubview(scrim, aboveSubview: backgroundImage)
    NSLayoutConstraint.activate([
      scrim.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scrim.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scrim.topAnchor.constraint(equalTo: view.topAnchor),
      scrim.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])

    controlPlaceholderHeightConstraint.constant = PlayerControlView
      .frameHeight + safetyMarginOnBottom
    if let createdPlayerControlView = ViewCreator<PlayerControlView>
      .createFromNib(withinFixedFrame: CGRect(
        x: 0,
        y: 0,
        width: controlPlaceholderView.bounds.size.width,
        height: controlPlaceholderView.bounds.size.height
      )) {
      controlView = createdPlayerControlView
      createdPlayerControlView.prepare(toWorkOnRootView: self)
      controlPlaceholderView.addSubview(createdPlayerControlView)
    }
    setupLargeLyricsColumn()
    if let createdLargeCurrentlyPlayingView = ViewCreator<LargeCurrentlyPlayingPlayerView>
      .createFromNib(withinFixedFrame: CGRect(
        x: 0,
        y: 0,
        width: largePlayerPlaceholderView.bounds.size.width,
        height: largePlayerPlaceholderView.bounds.size.height
      )) {
      largeCurrentlyPlayingView = createdLargeCurrentlyPlayingView
      createdLargeCurrentlyPlayingView.prepare(
        toWorkOnRootView: self,
        lyricsContainer: largeLyricsColumnView
      )
      largePlayerPlaceholderView.addSubview(createdLargeCurrentlyPlayingView)
    }

    setupVolumeControl()
    updateVolumeControlVisibility(for: appDelegate.storage.settings.user.playerDisplayStyle)

    closeButtonPlaceholderView.isHidden = true

    setupTableView()
    fetchSongInfoAndUpdateViews()

    if let sectionView = ViewCreator<ContextQueuePrevSectionHeader>
      .createFromNib(withinFixedFrame: CGRect(
        x: 0,
        y: 0,
        width: view.bounds.size.width,
        height: ContextQueuePrevSectionHeader.frameHeight
      )) {
      contextPrevQueueSectionHeader = sectionView
      contextPrevQueueSectionHeader?.display(name: L10n.tr("Previous"))
    }
    if let sectionView = ViewCreator<UserQueueSectionHeader>.createFromNib(withinFixedFrame: CGRect(
      x: 0,
      y: 0,
      width: view.bounds.size.width,
      height: UserQueueSectionHeader.frameHeight
    )) {
      userQueueSectionHeader = sectionView
      userQueueSectionHeader?.display(
        name: L10n.tr("Next from Queue"),
        buttonPressAction: clearUserQueue
      )
    }
    if let sectionView = ViewCreator<ContextQueueNextSectionHeader>
      .createFromNib(withinFixedFrame: CGRect(
        x: 0,
        y: 0,
        width: view.bounds.size.width,
        height: ContextQueueNextSectionHeader.frameHeight
      )) {
      contextNextQueueSectionHeader = sectionView
      contextNextQueueSectionHeader?.prepare(toWorkOnRootView: self)
    }

    accountNotificationHandler = AccountNotificationHandler(
      storage: appDelegate.storage,
      notificationHandler: appDelegate.notificationHandler
    )
    accountNotificationHandler?.registerCallbackForAllAccounts { [weak self] accountInfo in
      guard let self else { return }
      appDelegate.notificationHandler.register(
        self,
        selector: #selector(downloadFinishedSuccessful(notification:)),
        name: .downloadFinishedSuccess,
        object: appDelegate.getMeta(accountInfo).artworkDownloadManager
      )
      appDelegate.notificationHandler.register(
        self,
        selector: #selector(downloadFinishedSuccessful(notification:)),
        name: .downloadFinishedSuccess,
        object: appDelegate.getMeta(accountInfo).playableDownloadManager
      )
    }

    registerForTraitChanges(
      [UITraitUserInterfaceStyle.self, UITraitHorizontalSizeClass.self],
      handler: { (self: Self, previousTraitCollection: UITraitCollection) in
        self.refresh()
      }
    )
  }

  /// Apple Music keeps a compact volume slider in the top-right corner of the player instead
  /// of a volume button next to the transport controls.
  private func setupVolumeControl() {
    guard volumeSliderControl == nil else { return }

    let icon = UIImageView(
      image: UIImage(
        systemName: "speaker.wave.2.fill",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .regular)
      )
    )
    icon.tintColor = .white
    icon.setContentHuggingPriority(.required, for: .horizontal)

    let slider = VolumeSlider()
    slider.contentColor = .white
    slider.value = player.volume
    slider.accessibilityLabel = L10n.tr("Volume")
    slider.addTarget(self, action: #selector(volumeSliderChanged(_:)), for: .valueChanged)

    // Apple Music puts the slider first and the speaker icon at the trailing edge.
    let stack = UIStackView(arrangedSubviews: [slider, icon])
    stack.axis = .horizontal
    stack.spacing = 10
    stack.alignment = .center
    stack.translatesAutoresizingMaskIntoConstraints = false

    // Faint glass capsule, like Apple Music: the artwork stays visible through it.
    let container = UIView()
    container.translatesAutoresizingMaskIntoConstraints = false
    container.layer.cornerRadius = 18
    container.layer.cornerCurve = .continuous
    container.backgroundColor = UIColor.white.withAlphaComponent(0.12)
    container.layer.borderWidth = 1.0 / UIScreen.main.scale
    container.layer.borderColor = UIColor.white.withAlphaComponent(0.22).cgColor
    container.addSubview(stack)
    view.addSubview(container)
    NSLayoutConstraint.activate([
      container.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
      container.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      container.widthAnchor.constraint(equalToConstant: 180),
      container.heightAnchor.constraint(equalToConstant: 36),
      stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
      stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
      stack.topAnchor.constraint(equalTo: container.topAnchor),
      stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
    volumeSliderControl = container
    #if targetEnvironment(macCatalyst)
      windowVolumeControl = PlayerWindowVolumeControl(player: player)
    #endif
  }

  @objc
  private func volumeSliderChanged(_ sender: VolumeSlider) {
    player.volume = sender.value
  }

  /// The sheet has no title bar on Mac Catalyst, so it needs an explicit way back
  /// besides dragging the grabber. Only sheets get the button; the standalone
  /// mini player window is closed with its window controls.
  private func setupCloseButton() {
    guard closeButtonControl == nil, presentingViewController != nil else { return }

    let button = UIButton(type: .system)
    button.setImage(
      UIImage(
        systemName: "chevron.down",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
      ),
      for: .normal
    )
    button.tintColor = .secondaryLabel
    button.backgroundColor = UIColor.black.withAlphaComponent(0.28)
    button.layer.cornerRadius = 15
    button.translatesAutoresizingMaskIntoConstraints = false
    button.accessibilityLabel = L10n.tr("Close")
    button.addTarget(self, action: #selector(closePlayerPressed), for: .touchUpInside)
    view.addSubview(button)
    NSLayoutConstraint.activate([
      button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 15),
      button.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      button.widthAnchor.constraint(equalToConstant: 30),
      button.heightAnchor.constraint(equalToConstant: 30),
    ])
    closeButtonControl = button
  }

  @objc
  func closePlayerPressed() {
    guard let presentingViewController else { return }
    presentingViewController.dismiss(animated: true)
  }

  /// Apple Music splits the window: artwork and metadata on the left, lyrics on the right.
  /// The compact style still uses the single-column queue table.
  private func setupLargeLyricsColumn() {
    #if targetEnvironment(macCatalyst)
      guard largeLyricsColumnView == nil else { return }

      let column = UIView()
      column.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(column)

      // The XIB pins the large player and the control bar to the trailing margin; replace
      // that with the split. The control bar returns to full width in compact style.
      view.constraints.first {
        ($0.firstItem as? UIView) === view &&
          $0.firstAttribute == .rightMargin &&
          ($0.secondItem as? UIView) === largePlayerPlaceholderView &&
          $0.secondAttribute == .trailing
      }?.isActive = false
      controlFullWidthConstraint = view.constraints.first {
        ($0.firstItem as? UIView) === view &&
          $0.firstAttribute == .trailingMargin &&
          ($0.secondItem as? UIView) === controlPlaceholderView &&
          $0.secondAttribute == .trailing
      }
      let splitControlConstraint = controlPlaceholderView.trailingAnchor.constraint(
        equalTo: largePlayerPlaceholderView.trailingAnchor
      )
      controlSplitConstraint = splitControlConstraint

      NSLayoutConstraint.activate([
        column.topAnchor.constraint(equalTo: largePlayerPlaceholderView.topAnchor),
        column.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
        column.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        column.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.44),
        largePlayerPlaceholderView.trailingAnchor.constraint(
          equalTo: column.leadingAnchor,
          constant: -24
        ),
      ])
      largeLyricsColumnView = column

      // The floating close button sits in the top-left corner; keep the compact queue
      // (and its first artwork) clear of it, matching the large player's top inset.
      view.constraints.first {
        ($0.firstItem as? UIView) === tableView &&
          $0.firstAttribute == .top &&
          ($0.secondItem as? UIView) === view &&
          $0.secondAttribute == .topMargin
      }?.constant = 54
    #endif
  }

  func updateLargeLyricsColumnVisibility(for displayStyle: PlayerDisplayStyle) {
    guard let largeLyricsColumnView else { return }
    let isLarge = displayStyle == .large
    largeLyricsColumnView.isHidden = !isLarge
    controlSplitConstraint?.isActive = isLarge
    controlFullWidthConstraint?.isActive = !isLarge
    if isLarge {
      controlView?.attachUtilityCluster(to: largeLyricsColumnView)
    } else {
      controlView?.restoreUtilityCluster()
    }
  }

  func updateVolumeControlVisibility(for displayStyle: PlayerDisplayStyle) {
    #if targetEnvironment(macCatalyst)
      // Apple Music keeps the slider in the title bar row; the in-content capsule is only
      // the fallback when the scene exposes no title bar.
      if displayStyle == .large {
        windowVolumeControl?.attach(to: view.window?.windowScene)
      } else {
        windowVolumeControl?.detach()
      }
      volumeSliderControl?.isHidden = displayStyle != .large
        || (windowVolumeControl?.isAttached ?? false)
    #else
      volumeSliderControl?.isHidden = displayStyle != .large
    #endif
    controlView?.updateVolumeControlVisibility(for: displayStyle)
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    refreshCellMasks()
    controlView?.refreshView()
    applyGradientBackground()
    #if targetEnvironment(macCatalyst)
      // The window scene exists once the player is actually in a window.
      if isPlayerVisible,
         appDelegate.storage.settings.user.playerDisplayStyle == .large {
        if !(windowVolumeControl?.isAttached ?? false) {
          windowVolumeControl?.attach(to: view.window?.windowScene)
        }
        volumeSliderControl?.isHidden = windowVolumeControl?.isAttached ?? false
      }
    #endif
  }

  override func viewIsAppearing(_ animated: Bool) {
    super.viewIsAppearing(animated)
    #if targetEnvironment(macCatalyst)
      isPlayerVisible = true
    #endif
    setupCloseButton()
    appDelegate.userStatistics.visited(.popupPlayer)
    becomeFirstResponder()
    changeDisplayStyleVisually(
      to: appDelegate.storage.settings.user.playerDisplayStyle,
      animated: false
    )
    reloadData()
    scrollToCurrentlyPlayingRow()
    controlView?.refreshView()
    refresh()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    resignFirstResponder()
    AudioOutputPicker.dismiss()
    #if targetEnvironment(macCatalyst)
      isPlayerVisible = false
      windowVolumeControl?.detach()
    #endif
  }

  override func viewWillLayoutSubviews() {
    adjustLayoutMargins()
  }

  func fetchSongInfoAndUpdateViews() {
    guard appDelegate.storage.settings.user.isOnlineMode,
          let song = player.currentlyPlaying?.asSong,
          let account = song.account
    else { return }

    Task { @MainActor in do {
      try await self.appDelegate.getMeta(account.info).librarySyncer.sync(song: song)
      self.refreshCurrentlyPlayingInfoView()
    } catch {
      self.appDelegate.eventLogger.report(topic: "Song Info", error: error)
    }}
  }

  func reloadData() {
    tableView.reloadData()
    scrollToCurrentlyPlayingRow()
  }

  func scrollToCurrentlyPlayingRow() {
    tableView.scrollToRow(
      at: IndexPath(row: 0, section: PlayerSectionCategory.currentlyPlaying.rawValue),
      at: .top,
      animated: false
    )
  }

  func favoritePressed() {
    switch player.playerMode {
    case .music:
      guard let playableInfo = player.currentlyPlaying,
            playableInfo.isSong,
            let account = playableInfo.account
      else { return }
      Task { @MainActor in
        do {
          try await playableInfo
            .remoteToggleFavorite(
              syncer: self.appDelegate.getMeta(account.info)
                .librarySyncer
            )
        } catch {
          self.appDelegate.eventLogger.report(topic: "Toggle Favorite", error: error)
        }
        self.refresh()
      }
    case .podcast: break
    }
  }

  func displayArtistDetail() {
    if let song = player.currentlyPlaying?.asSong, let artist = song.artist,
       let account = artist.account {
      let artistDetailVC = AppStoryboard.Main.segueToArtistDetail(account: account, artist: artist)
      closePopupPlayerAndDisplayInLibraryTab(vc: artistDetailVC)
    }
  }

  func displayAlbumDetail() {
    if let song = player.currentlyPlaying?.asSong, let album = song.album,
       let account = album.account {
      let albumDetailVC = AppStoryboard.Main.segueToAlbumDetail(
        account: account,
        album: album,
        songToScrollTo: song
      )
      closePopupPlayerAndDisplayInLibraryTab(vc: albumDetailVC)
    }
  }

  func closePopupPlayer() {
    guard let hostingSplitVC = AppDelegate.mainWindowHostVC else { return }
    hostingSplitVC.visualizePopupPlayer(direction: .close, animated: true)
  }

  func closePopupPlayerAndDisplayInLibraryTab(vc: UIViewController) {
    #if targetEnvironment(macCatalyst)
      if view.window?.windowScene?.delegate is MiniPlayerSceneDelegate {
        displayInMainWindowAndCloseMiniPlayer(vc: vc)
        return
      }
    #endif
    guard let hostingSplitVC = AppDelegate.mainWindowHostVC else { return }
    hostingSplitVC.visualizePopupPlayer(direction: .close, animated: true, completion: { () in
      hostingSplitVC.pushNavLibrary(vc: vc)
    })
  }

  #if targetEnvironment(macCatalyst)
    /// The mini player lives in its own window scene: show the content in the main window (opening it if necessary)
    /// and close the mini player afterwards, so it stays open if the main window can't be reached.
    private func displayInMainWindowAndCloseMiniPlayer(vc: UIViewController) {
      if appDelegate.isMainWindowOpen {
        if let mainSession = AppDelegate.mainSceneDelegate?.window?.windowScene?.session {
          UIApplication.shared.requestSceneSessionActivation(
            mainSession,
            userActivity: nil,
            options: nil,
            errorHandler: nil
          )
        }
      } else {
        appDelegate.openMainWindow()
      }
      Task { @MainActor [weak self] in
        // a newly requested main window needs a moment until its content is loaded
        for _ in 0 ..< 50 {
          if let hostVC = AppDelegate.mainWindowHostVC, Self.isLibraryReady(hostVC: hostVC) {
            // the main window's popup player might be expanded, it would cover the pushed screen
            hostVC.visualizePopupPlayer(direction: .close, animated: true, completion: {
              hostVC.pushNavLibrary(vc: vc)
              // the main window exists by now, so closing the mini player won't open another one
              self?.appDelegate.closeMiniPlayer()
              self?.appDelegate.rebuildMainMenu()
            })
            return
          }
          try? await Task.sleep(nanoseconds: 100_000_000)
        }
      }
    }

    private static func isLibraryReady(hostVC: MainSceneHostingViewController) -> Bool {
      guard let splitVC = hostVC as? SplitVC else { return true }
      return splitVC.viewController(for: .secondary) is UINavigationController
    }
  #endif

  func refreshUserQueueSectionHeader() {
    guard let userQueueSectionView = userQueueSectionHeader else { return }
    if player.userQueueCount == 0 {
      userQueueSectionView.hide()
    } else {
      userQueueSectionView.display(
        name: L10n.tr(PlayerQueueType.user.description),
        buttonPressAction: clearUserQueue
      )
    }
  }

  func refreshContextQueueSectionHeader() {
    guard let contextNextQueueSectionHeader = contextNextQueueSectionHeader else { return }
    contextNextQueueSectionHeader.refresh()
  }

  // MARK: - UIScrollViewDelegate

  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    refreshCellMasks()
  }

  func refreshCellMasks() {
    guard let topSection = Array(activeDisplayedSectionHeader)
      .sorted(by: { $0.rawValue < $1.rawValue }).first
    else { return }

    let topSectionHeight = tableView(tableView, heightForHeaderInSection: topSection.rawValue)
    let scrollOffset = tableView.contentOffset.y

    for cell in tableView.visibleCells {
      let hiddenFrameHeight = scrollOffset + topSectionHeight - cell.frame.origin.y
      if hiddenFrameHeight >= 0 || hiddenFrameHeight <= cell.frame.size.height {
        if let customCell = cell as? PlayableTableCell {
          customCell.maskCell(fromTop: hiddenFrameHeight)
        }
      }
    }
  }

  func refreshCellsContent() {
    for cell in tableView.visibleCells {
      guard let playableCell = cell as? PlayableTableCell else { continue }
      playableCell.refresh()
    }
  }
}

// MARK: MusicPlayable

extension PopupPlayerVC: MusicPlayable {
  func didStartPlayingFromBeginning() {
    fetchSongInfoAndUpdateViews()
    largeCurrentlyPlayingView?.initializeLyrics()
  }

  func didStartPlaying() {
    reloadData()
    refresh()
  }

  func didStopPlaying() {
    reloadData()
    refresh()
  }

  func didPlaylistChange() {
    reloadData()
    refresh()
  }

  func didPause() {
    // Elapsed and lyrics updates come from timers that stop with playback. Push the final
    // position once so the seek bar and the lyrics don't stay behind when the user pauses.
    let time = CMTime(seconds: player.elapsedTime, preferredTimescale: 1_000)
    controlView?.didElapsedTimeChange()
    largeCurrentlyPlayingView?.refreshLyricsTime(time: time)
  }

  func didElapsedTimeChange() {}

  func didLyricsTimeChange(time: CMTime) {
    largeCurrentlyPlayingView?.refreshLyricsTime(time: time)
  }

  func didArtworkChange() {
    refreshCurrentlyPlayingArtworks()
  }

  func didNowPlayingInfoChange() {
    refreshCurrentlyPlayingInfoView()
  }

  func didShuffleChange() {}
  func didRepeatChange() {}
  func didPlaybackRateChange() {}
}
