//
//  PlayerControlView.swift
//  fmusic
//
//  Created by Maximilian Bauer on 07.02.24.
//  Copyright (c) 2024 Maximilian Bauer. All rights reserved.
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
import MarqueeLabel
import MediaPlayer
import UIKit

// MARK: - PlayerControlView

class PlayerControlView: UIView {
  static let frameHeight: CGFloat = 175
  static private let margin = UIEdgeInsets(
    top: 0,
    left: UIView.defaultMarginX,
    bottom: 20,
    right: UIView.defaultMarginX
  )

  private var player: PlayerFacade!
  private var rootView: PopupPlayerVC?
  private var playerHandler: PlayerUIHandler?

  @IBOutlet
  weak var playButton: UIButton!
  @IBOutlet
  weak var previousButton: UIButton!
  @IBOutlet
  weak var nextButton: UIButton!
  @IBOutlet
  weak var skipBackwardButton: UIButton!
  @IBOutlet
  weak var skipForwardButton: UIButton!

  @IBOutlet
  weak var timeSlider: UISlider!
  @IBOutlet
  weak var elapsedTimeLabel: UILabel!
  @IBOutlet
  weak var remainingTimeLabel: UILabel!
  @IBOutlet
  weak var liveLabel: UILabel!
  @IBOutlet
  weak var audioInfoLabel: UILabel!
  @IBOutlet
  weak var playTypeIcon: UIImageView!

  @IBOutlet
  weak var optionsStackView: UIStackView!
  @IBOutlet
  weak var playerModeButton: UIButton!
  @IBOutlet
  weak var airplayButton: UIButton!
  @IBOutlet
  weak var displayPlaylistButton: UIButton!
  @IBOutlet
  weak var volumeButton: UIButton!
  @IBOutlet
  weak var optionsButton: UIButton!

  private var shuffleButton: UIButton?
  private var repeatButton: UIButton?
  private var utilityCluster: UIStackView?
  private var utilityClusterInternalConstraints: [NSLayoutConstraint] = []

  required init?(coder aDecoder: NSCoder) {
    super.init(coder: aDecoder)
    self.layoutMargins = Self.margin
    self.player = appDelegate.player
    player.addNotifier(notifier: self)
  }

  /// The utility icons in the XIB use different symbol scales, so their optical sizes drift
  /// apart. Give all of them the same symbol configuration instead.
  private func applyUtilityIcon(_ button: UIButton, systemName: String) {
    let configuration = PlayerUIHandler.utilitySymbolConfiguration
    button.setImage(
      UIImage(systemName: systemName, withConfiguration: configuration),
      for: .normal
    )
    button.setPreferredSymbolConfiguration(configuration, forImageIn: .normal)
  }

  /// Apple Music puts five transport controls in one row. The popup player additionally keeps
  /// the queue toggles in the bottom-right corner instead of a second centered row.
  private func configureTransportControls() {
    guard let transportStack = playButton.superview as? UIStackView else { return }

    skipBackwardButton.isHidden = true
    skipForwardButton.isHidden = true
    skipBackwardButton.removeFromSuperview()
    skipForwardButton.removeFromSuperview()

    let shuffle = makeToggleButton(imageName: "shuffle")
    shuffle.accessibilityLabel = L10n.tr("Shuffle")
    shuffle.addTarget(self, action: #selector(shuffleButtonPushed), for: .touchUpInside)
    let repeatToggle = makeToggleButton(imageName: "repeat")
    repeatToggle.accessibilityLabel = L10n.tr("Repeat")
    repeatToggle.addTarget(self, action: #selector(repeatButtonPushed), for: .touchUpInside)
    transportStack.insertArrangedSubview(shuffle, at: 0)
    transportStack.addArrangedSubview(repeatToggle)
    shuffleButton = shuffle
    repeatButton = repeatToggle

    // Keep the play control clearly dominant, like Apple Music, but not oversized.
    playButton.setPreferredSymbolConfiguration(
      UIImage.SymbolConfiguration(pointSize: 27),
      forImageIn: .normal
    )
    previousButton.setPreferredSymbolConfiguration(
      UIImage.SymbolConfiguration(pointSize: 21),
      forImageIn: .normal
    )
    nextButton.setPreferredSymbolConfiguration(
      UIImage.SymbolConfiguration(pointSize: 21),
      forImageIn: .normal
    )
  }

  private func makeToggleButton(imageName: String) -> UIButton {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(Self.toggleIcon(imageName, tint: Self.iconTintColor), for: .normal)
    return button
  }

  // The outline toggles are small enough that a tinted template image renders weaker than the
  // filled transport glyphs, so bake the color in and give them a heavier stroke.
  private static func toggleIcon(_ systemName: String, tint: UIColor) -> UIImage? {
    UIImage(
      systemName: systemName,
      withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .bold)
    )?.withTintColor(tint, renderingMode: .alwaysOriginal)
  }

  private func configureUtilityCluster() {
    guard let transportStack = playButton.superview as? UIStackView else { return }
    optionsStackView.isHidden = true

    let cluster = UIStackView(arrangedSubviews: [
      airplayButton,
      displayPlaylistButton,
      volumeButton,
      optionsButton,
    ])
    cluster.axis = .horizontal
    cluster.spacing = 18
    cluster.alignment = .center
    cluster.translatesAutoresizingMaskIntoConstraints = false
    addSubview(cluster)
    utilityCluster = cluster
    utilityClusterInternalConstraints = [
      cluster.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
      cluster.topAnchor.constraint(equalTo: transportStack.bottomAnchor, constant: 14),
    ]
    NSLayoutConstraint.activate(utilityClusterInternalConstraints)
  }

  /// The large player moves the utility icons to the bottom-right of the lyrics column.
  func attachUtilityCluster(to container: UIView) {
    guard let utilityCluster else { return }
    NSLayoutConstraint.deactivate(utilityClusterInternalConstraints)
    utilityCluster.removeFromSuperview()
    container.addSubview(utilityCluster)
    NSLayoutConstraint.activate([
      utilityCluster.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      utilityCluster.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
  }

  /// Compact mode keeps the icons inside the control bar, under the transport row.
  func restoreUtilityCluster() {
    guard let utilityCluster else { return }
    utilityCluster.removeFromSuperview()
    addSubview(utilityCluster)
    NSLayoutConstraint.activate(utilityClusterInternalConstraints)
  }

  @objc
  private func shuffleButtonPushed() {
    playerHandler?.shuffleButtonPushed()
    refreshTransportToggles()
  }

  @objc
  private func repeatButtonPushed() {
    playerHandler?.repeatButtonPushed()
    refreshTransportToggles()
  }

  private static let iconTintColor = UIColor.label.withAlphaComponent(0.85)

  private func refreshTransportToggles() {
    let shuffleEnabled = appDelegate.storage.settings.user.isPlayerShuffleButtonEnabled
    shuffleButton?.isEnabled = shuffleEnabled
    shuffleButton?.alpha = shuffleEnabled ? 1 : 0.35
    let accent = appDelegate.storage.settings.accounts.getSetting(nil).read.themePreference
      .asColor
    let shuffleTint = player.isShuffle ? accent : Self.iconTintColor
    shuffleButton?.setImage(Self.toggleIcon("shuffle", tint: shuffleTint), for: .normal)

    let repeatSymbolName: String = switch player.repeatMode {
    case .off, .all: "repeat"
    case .single: "repeat.1"
    }
    let repeatTint = player.repeatMode == .off ? Self.iconTintColor : accent
    repeatButton?.setImage(
      Self.toggleIcon(repeatSymbolName, tint: repeatTint),
      for: .normal
    )
  }

  /// The utility cluster mirrors the full player in every display style: on Mac the volume
  /// always lives in the top-right title bar control, so the cluster keeps the same three icons.
  func updateVolumeControlVisibility(for displayStyle: PlayerDisplayStyle) {
    #if targetEnvironment(macCatalyst)
      volumeButton.isHidden = true
    #else
      volumeButton.isHidden = displayStyle == .large
    #endif
  }

  func prepare(toWorkOnRootView: PopupPlayerVC?) {
    rootView = toWorkOnRootView

    playerHandler = PlayerUIHandler(player: player, style: .popupPlayer)

    playButton.imageView?.tintColor = Self.iconTintColor
    previousButton.tintColor = Self.iconTintColor
    nextButton.tintColor = Self.iconTintColor
    skipBackwardButton.tintColor = Self.iconTintColor
    skipForwardButton.tintColor = Self.iconTintColor
    applyUtilityIcon(airplayButton, systemName: "airplayaudio")
    applyUtilityIcon(volumeButton, systemName: "speaker.wave.3.fill")
    applyUtilityIcon(optionsButton, systemName: "ellipsis.circle")
    airplayButton.tintColor = Self.iconTintColor
    playerModeButton.tintColor = Self.iconTintColor
    volumeButton.tintColor = Self.iconTintColor
    optionsButton.imageView?.tintColor = Self.iconTintColor
    displayPlaylistButton.tintColor = Self.iconTintColor
    configureTransportControls()
    configureUtilityCluster()
    updateVolumeControlVisibility(for: appDelegate.storage.settings.user.playerDisplayStyle)
    refreshPlayer()
    playerHandler?.refreshPlayerOptions(
      optionsButton: optionsButton,
      menuCreateCB: createPlayerOptionsMenu
    )

    registerForTraitChanges(
      [UITraitUserInterfaceStyle.self, UITraitHorizontalSizeClass.self],
      handler: { (self: Self, previousTraitCollection: UITraitCollection) in
        self.playerHandler?.refreshTimeInfo(
          timeSlider: self.timeSlider,
          elapsedTimeLabel: self.elapsedTimeLabel,
          remainingTimeLabel: self.remainingTimeLabel,
          audioInfoLabel: self.audioInfoLabel,
          playTypeIcon: self.playTypeIcon,
          liveLabel: self.liveLabel
        )
      }
    )
  }

  @IBAction
  func swipeHandler(_ gestureRecognizer: UISwipeGestureRecognizer) {
    if gestureRecognizer.state == .ended {
      rootView?.closePopupPlayer()
    }
  }

  @IBAction
  func playButtonPushed(_ sender: Any) {
    playerHandler?.playButtonPushed()
    playerHandler?.refreshPlayButton(playButton)
  }

  @IBAction
  func previousButtonPushed(_ sender: Any) {
    playerHandler?.previousButtonPushed()
  }

  @IBAction
  func nextButtonPushed(_ sender: Any) {
    playerHandler?.nextButtonPushed()
  }

  @IBAction
  func skipBackwardButtonPushed(_ sender: Any) {
    playerHandler?.skipBackwardButtonPushed()
  }

  @IBAction
  func skipForwardButtonPushed(_ sender: Any) {
    playerHandler?.skipForwardButtonPushed()
  }

  @IBAction
  func timeSliderChanged(_ sender: Any) {
    playerHandler?.timeSliderChanged(timeSlider: timeSlider)
  }

  @IBAction
  func timeSliderIsChanging(_ sender: Any) {
    playerHandler?.timeSliderIsChanging(
      timeSlider: timeSlider,
      elapsedTimeLabel: elapsedTimeLabel,
      remainingTimeLabel: remainingTimeLabel
    )
  }

  @IBAction
  func airplayButtonPushed(_ sender: UIButton) {
    playerHandler?.airplayButtonPushed(button: sender)
  }

  @IBAction
  func volumeButtonPressed(_ sender: Any) {
    showVolumeSliderMenu()
  }

  func showVolumeSliderMenu() {
    let popoverContentController = SliderMenuPopover()
    let sliderMenuView = popoverContentController.sliderMenuView
    sliderMenuView.frame = CGRect(x: 0, y: 0, width: 250, height: 50)

    sliderMenuView.slider.minimumValue = 0
    sliderMenuView.slider.maximumValue = 100
    sliderMenuView.slider.value = appDelegate.player.volume * 100

    sliderMenuView.sliderValueChangedCB = {
      self.appDelegate.player.volume = Float(sliderMenuView.slider.value) / 100.0
    }

    popoverContentController.modalPresentationStyle = .popover
    popoverContentController.preferredContentSize = sliderMenuView.frame.size

    if let popoverPresentationController = popoverContentController.popoverPresentationController {
      popoverPresentationController.permittedArrowDirections = .down
      popoverPresentationController.delegate = popoverContentController
      popoverPresentationController.sourceView = volumeButton
      rootView?.present(
        popoverContentController,
        animated: true,
        completion: nil
      )
    }
  }

  @IBAction
  func displayPlaylistPressed() {
    rootView?.switchDisplayStyleOptionPersistent()
    playerHandler?.refreshDisplayPlaylistButton(displayPlaylistButton: displayPlaylistButton)
    playerHandler?.refreshPlayerOptions(
      optionsButton: optionsButton,
      menuCreateCB: createPlayerOptionsMenu
    )
  }

  @IBAction
  func playerModeChangePressed(_ sender: Any) {
    switch player.playerMode {
    case .music:
      appDelegate.player.setPlayerMode(.podcast)
    case .podcast:
      appDelegate.player.setPlayerMode(.music)
    }
    refreshPlayerModeChangeButton()
  }

  func refreshView() {
    refreshPlayer()
  }

  func refreshPlayer() {
    // Weak outlets can already be gone while the player UI is torn down (account removal).
    guard playButton != nil,
          previousButton != nil,
          nextButton != nil,
          timeSlider != nil,
          elapsedTimeLabel != nil,
          remainingTimeLabel != nil,
          audioInfoLabel != nil,
          playTypeIcon != nil,
          liveLabel != nil,
          displayPlaylistButton != nil,
          playerModeButton != nil,
          optionsStackView != nil
    else { return }

    playerHandler?.refreshPlayButton(playButton)
    playerHandler?.refreshTimeInfo(
      timeSlider: timeSlider,
      elapsedTimeLabel: elapsedTimeLabel,
      remainingTimeLabel: remainingTimeLabel,
      audioInfoLabel: audioInfoLabel,
      playTypeIcon: playTypeIcon,
      liveLabel: liveLabel
    )
    playerHandler?.refreshPrevNextButtons(previousButton: previousButton, nextButton: nextButton)
    playerHandler?.refreshDisplayPlaylistButton(displayPlaylistButton: displayPlaylistButton)
    refreshTransportToggles()
    refreshPlayerModeChangeButton()
  }

  func createPlaybackRateMenu() -> UIMenuElement {
    let playerPlaybackRate = player.playbackRate
    let availablePlaybackRates: [UIAction] = PlaybackRate.allCases.compactMap { playbackRate in
      UIAction(
        title: playbackRate.description,
        image: playbackRate == playerPlaybackRate ? .check : nil,
        handler: { _ in
          self.player.setPlaybackRate(playbackRate)
        }
      )
    }
    return UIMenu(
      title: L10n.tr("Playback Rate"),
      subtitle: playerPlaybackRate.description,
      image: .playbackRate,
      children: availablePlaybackRates
    )
  }

  func createLyricsOffsetMenu() -> UIMenuElement {
    let currentOffset = appDelegate.storage.settings.user.lyricsOffsetMs
    let presets = [-1_000, -500, -200, 0, 200, 500, 1_000]
    let actions = presets.map { offset in
      UIAction(
        title: Self.lyricsOffsetDescription(offset),
        state: offset == currentOffset ? .on : .off,
        handler: { [weak self] _ in
          self?.appDelegate.storage.settings.user.lyricsOffsetMs = offset
          NotificationCenter.default.post(name: .lyricsOffsetChanged, object: nil)
        }
      )
    }
    return UIMenu(
      title: L10n.tr("Lyrics Offset"),
      subtitle: Self.lyricsOffsetDescription(currentOffset),
      image: .lyrics,
      children: actions
    )
  }

  private static func lyricsOffsetDescription(_ milliseconds: Int) -> String {
    guard milliseconds != 0 else { return L10n.tr("Synced") }
    let seconds = String(format: "%.1fs", abs(Double(milliseconds)) / 1_000)
    let direction = milliseconds > 0
      ? L10n.tr("Lyrics ahead by")
      : L10n.tr("Lyrics behind by")
    return "\(direction) \(seconds)"
  }

  func createVisualizerTypeMenu() -> UIMenuElement {
    let currentType = appDelegate.storage.settings.user.selectedVisualizerType
    let availableTypes: [UIAction] = VisualizerType.allCases.reversed()
      .compactMap { visualizerType in
        UIAction(
          title: visualizerType.displayName,
          image: UIImage(systemName: visualizerType.iconName),
          state: visualizerType == currentType ? .on : .off,
          handler: { _ in
            self.appDelegate.storage.settings.user.selectedVisualizerType = visualizerType
            self.rootView?.largeCurrentlyPlayingView?.showVisualizer()
          }
        )
      }
    return UIMenu(
      title: L10n.tr("Visualizer Style"),
      subtitle: currentType.displayName,
      image: .sparkles,
      children: availableTypes
    )
  }

  func createPlayerOptionsMenu() -> [UIMenuElement] {
    var menuActions = [UIMenuElement]()
    if player.currentlyPlaying != nil || player.prevQueueCount > 0 || player
      .userQueueCount > 0 || player.nextQueueCount > 0 {
      let clearPlayer = UIAction(title: L10n.tr("Clear Player"), image: .clear, handler: { _ in
        self.player.clearQueues()
      })
      menuActions.append(clearPlayer)
    }
    if player.userQueueCount > 0 {
      let clearUserQueue = UIAction(
        title: L10n.tr("Clear User Queue"),
        image: .playlistX,
        handler: { _ in
          self.rootView?.clearUserQueue()
        }
      )
      menuActions.append(clearUserQueue)
    }

    menuActions.append(appDelegate.createSleepTimerMenu(refreshCB: nil))
    menuActions.append(createPlaybackRateMenu())
    menuActions.append(createLyricsOffsetMenu())

    if rootView?.largeCurrentlyPlayingView?.isLyricsButtonAllowedToDisplay ?? false {
      if !appDelegate.storage.settings.user.isPlayerLyricsDisplayed ||
        appDelegate.storage.settings.user.playerDisplayStyle != .large {
        let showLyricsAction = UIAction(
          title: L10n.tr("Show Lyrics"),
          image: .lyrics,
          handler: { _ in
            if !self.appDelegate.storage.settings.user.isPlayerLyricsDisplayed {
              self.appDelegate.storage.settings.user.isPlayerLyricsDisplayed.toggle()
              self.appDelegate.storage.settings.user.isPlayerVisualizerDisplayed = false
              self.rootView?.largeCurrentlyPlayingView?.display(element: .lyrics)
            }
            if self.appDelegate.storage.settings.user.playerDisplayStyle != .large {
              self.displayPlaylistPressed()
            }
          }
        )
        menuActions.append(showLyricsAction)
      } else {
        let hideLyricsAction = UIAction(
          title: L10n.tr("Hide Lyrics"),
          image: .lyrics,
          handler: { _ in
            self.appDelegate.storage.settings.user.isPlayerLyricsDisplayed.toggle()
            self.rootView?.largeCurrentlyPlayingView?.display(element: .artwork)
          }
        )
        menuActions.append(hideLyricsAction)
      }
    }

    if !appDelegate.storage.settings.user.isPlayerVisualizerDisplayed ||
      appDelegate.storage.settings.user.playerDisplayStyle != .large {
      let showVisualizerAction = UIAction(
        title: L10n.tr("Show Audio Visualizer"),
        image: .audioVisualizer,
        handler: { _ in
          if !self.appDelegate.storage.settings.user.isPlayerVisualizerDisplayed {
            self.appDelegate.storage.settings.user.isPlayerVisualizerDisplayed = true
            self.appDelegate.storage.settings.user.isPlayerLyricsDisplayed = false
            self.rootView?.largeCurrentlyPlayingView?.display(element: .visualizer)
          }
          if self.appDelegate.storage.settings.user.playerDisplayStyle != .large {
            self.displayPlaylistPressed()
          }
        }
      )
      menuActions.append(showVisualizerAction)
    } else {
      let hideVisualizerAction = UIAction(
        title: L10n.tr("Hide Audio Visualizer"),
        image: .audioVisualizer,
        handler: { _ in
          self.appDelegate.storage.settings.user.isPlayerVisualizerDisplayed = false
          self.rootView?.largeCurrentlyPlayingView?.display(element: .artwork)
        }
      )
      menuActions.append(hideVisualizerAction)

      // Add visualizer type selector submenu
      menuActions.append(createVisualizerTypeMenu())
    }

    switch player.playerMode {
    case .music:
      if player.currentlyPlaying != nil || player.prevQueueCount > 0 || player.nextQueueCount > 0,
         appDelegate.storage.settings.user.isOnlineMode {
        let addContextToPlaylist = UIAction(
          title: L10n.tr("Add Context Queue to Playlist"),
          image: .playlistPlus,
          handler: { _ in
            var itemsToAdd = self.player.getAllPrevQueueItems().filterSongs()
            if let currentlyPlaying = self.player.currentlyPlaying,
               let currentSong = currentlyPlaying.asSong {
              itemsToAdd.append(currentSong)
            }
            itemsToAdd.append(contentsOf: self.player.getAllNextQueueItems().filterSongs())
            // allow add to playlist only if all songs belong to the same account
            guard let firstItemAccount = itemsToAdd.first?.account,
                  itemsToAdd.count == itemsToAdd.filter({ $0.account == firstItemAccount }).count
            else { return }
            let selectPlaylistVC = AppStoryboard.Main
              .segueToPlaylistSelector(account: firstItemAccount, itemsToAdd: itemsToAdd)
            let selectPlaylistNav = UINavigationController(rootViewController: selectPlaylistVC)
            self.rootView?.present(selectPlaylistNav, animated: true, completion: nil)
          }
        )
        menuActions.append(addContextToPlaylist)
      }
    case .podcast: break
    }

    switch appDelegate.storage.settings.user.playerDisplayStyle {
    case .compact:
      let scrollToCurrentlyPlaying = UIAction(
        title: L10n.tr("Scroll to currently playing"),
        image: .squareArrow,
        handler: { _ in
          self.rootView?.scrollToCurrentlyPlayingRow()
        }
      )
      menuActions.append(scrollToCurrentlyPlaying)
    case .large: break
    }

    let playerInfo = UIAction(title: L10n.tr("Player Info"), image: .info, handler: { _ in
      guard let rootView = self.rootView else { return }
      let detailVC = PlainDetailsVC()
      detailVC.display(player: self.player, on: rootView)
      rootView.present(detailVC, animated: true)
    })
    menuActions.append(playerInfo)
    return menuActions
  }

  func refreshPlayerModeChangeButton() {
    playerModeButton.isHidden = appDelegate.player.podcastItemCount == 0 && appDelegate.player
      .playerMode != .podcast
    switch player.playerMode {
    case .music:
      playerModeButton.setImage(UIImage.musicalNotes, for: .normal)
    case .podcast:
      playerModeButton.setImage(UIImage.podcast, for: .normal)
    }
    optionsStackView.layoutIfNeeded()
  }
}

// MARK: MusicPlayable

extension PlayerControlView: MusicPlayable {
  func didStartPlayingFromBeginning() {}

  func didStartPlaying() {
    refreshPlayer()
  }

  func didPause() {
    refreshPlayer()
  }

  func didStopPlaying() {
    guard skipBackwardButton != nil, skipForwardButton != nil else { return }
    refreshPlayer()
    playerHandler?.refreshSkipButtons(
      skipBackwardButton: skipBackwardButton,
      skipForwardButton: skipForwardButton
    )
  }

  func didElapsedTimeChange() {
    guard timeSlider != nil,
          elapsedTimeLabel != nil,
          remainingTimeLabel != nil,
          audioInfoLabel != nil,
          playTypeIcon != nil,
          liveLabel != nil
    else { return }
    playerHandler?.refreshTimeInfo(
      timeSlider: timeSlider,
      elapsedTimeLabel: elapsedTimeLabel,
      remainingTimeLabel: remainingTimeLabel,
      audioInfoLabel: audioInfoLabel,
      playTypeIcon: playTypeIcon,
      liveLabel: liveLabel
    )
  }

  func didPlaylistChange() {
    refreshPlayer()
  }

  func didArtworkChange() {}

  func didShuffleChange() {}

  func didRepeatChange() {}

  func didPlaybackRateChange() {}
}
