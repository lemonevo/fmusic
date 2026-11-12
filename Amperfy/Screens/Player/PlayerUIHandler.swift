//
//  PlayerUIHandler.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 01.08.25.
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

import AmperfyKit
import MediaPlayer
import UIKit

// MARK: - PlayerUIStyle

enum PlayerUIStyle {
  case miniPlayerMac
  case popupPlayer
  case miniPlayeriOS
}

// MARK: - PlayerUIHandler

@MainActor
class PlayerUIHandler: NSObject {
  public static let playButtonImagePointSize: CGFloat = 25
  public static let bigButtonImagePointSize: CGFloat = 17
  public static let playAndNextiOSButtonImagePointSize: CGFloat = 15
  /// One shared size for the small utility icons (AirPlay, queue, volume, ellipsis).
  public static let utilitySymbolConfiguration = UIImage.SymbolConfiguration(
    pointSize: 17,
    weight: .regular
  )

  private var player: PlayerFacade
  private var style: PlayerUIStyle

  init(player: PlayerFacade, style: PlayerUIStyle) {
    self.player = player
    self.style = style
  }

  func playButtonPushed() {
    player.togglePlayPause()
  }

  func skipBackwardButtonPushed() {
    player.skipBackward(interval: player.skipBackwardMusicInterval)
  }

  func skipForwardButtonPushed() {
    player.skipForward(interval: player.skipForwardMusicInterval)
  }

  func previousButtonPushed() {
    switch player.playerMode {
    case .music:
      player.playPreviousOrReplay()
    case .podcast:
      player.skipBackward(interval: player.skipBackwardPodcastInterval)
    }
  }

  func nextButtonPushed() {
    switch player.playerMode {
    case .music:
      player.playNext()
    case .podcast:
      player.skipForward(interval: player.skipForwardPodcastInterval)
    }
  }

  func shuffleButtonPushed() {
    player.toggleShuffle()
  }

  func repeatButtonPushed() {
    player.setRepeatMode(player.repeatMode.nextMode)
  }

  func autoplayButtonPushed() {
    appDelegate.storage.settings.user.isAutoplayEnabled.toggle()
  }

  func refreshPlayButton(_ button: UIButton) {
    var buttonImg = UIImage()
    if player.isPlaying {
      if player.isStopInsteadOfPause {
        buttonImg = UIImage.stop
      } else {
        buttonImg = UIImage.pause
      }
    } else {
      buttonImg = UIImage.play
    }

    switch style {
    case .miniPlayerMac:
      buttonImg = buttonImg
        .withConfiguration(UIImage.SymbolConfiguration(pointSize: Self.playButtonImagePointSize))
    case .miniPlayeriOS:
      buttonImg = buttonImg
        .withConfiguration(
          UIImage
            .SymbolConfiguration(pointSize: Self.playAndNextiOSButtonImagePointSize)
        )
    case .popupPlayer:
      break
    }

    button.setImage(buttonImg, for: UIControl.State.normal)
    button.configuration?.image = buttonImg
  }

  func refreshSkipButtons(skipBackwardButton: UIButton, skipForwardButton: UIButton) {
    switch player.playerMode {
    case .music:
      skipBackwardButton.isHidden = !appDelegate.storage.settings.user.isShowMusicPlayerSkipButtons
      skipBackwardButton.isEnabled = player.isSkipAvailable
      skipBackwardButton.alpha = !appDelegate.storage.settings.user
        .isShowMusicPlayerSkipButtons ? 0.0 : 1.0
      skipForwardButton.isHidden = !appDelegate.storage.settings.user.isShowMusicPlayerSkipButtons
      skipForwardButton.isEnabled = player.isSkipAvailable
      skipForwardButton.alpha = !appDelegate.storage.settings.user
        .isShowMusicPlayerSkipButtons ? 0.0 : 1.0
    case .podcast:
      skipBackwardButton.isHidden = true
      skipBackwardButton.isEnabled = true
      skipForwardButton.isHidden = true
      skipForwardButton.isEnabled = true
    }
  }

  func refreshPrevNextButtons(previousButton: UIButton, nextButton: UIButton) {
    previousButton.imageView?.contentMode = .scaleAspectFit
    nextButton.imageView?.contentMode = .scaleAspectFit

    var previouseImg = UIImage()
    var nextImg = UIImage()
    switch player.playerMode {
    case .music:
      previouseImg = UIImage.backwardFill
      nextImg = UIImage.forwardFill
    case .podcast:
      previouseImg = UIImage.goBackward15
      nextImg = UIImage.goForward30
    }

    switch style {
    case .miniPlayerMac:
      previouseImg = previouseImg.withConfiguration(UIImage.SymbolConfiguration(scale: .medium))
      nextImg = nextImg.withConfiguration(UIImage.SymbolConfiguration(scale: .medium))
    case .popupPlayer:
      break
    case .miniPlayeriOS:
      previouseImg = previouseImg
        .withConfiguration(
          UIImage
            .SymbolConfiguration(pointSize: Self.playAndNextiOSButtonImagePointSize)
        )
      nextImg = nextImg
        .withConfiguration(
          UIImage
            .SymbolConfiguration(pointSize: Self.playAndNextiOSButtonImagePointSize)
        )
    }

    previousButton.setImage(previouseImg, for: UIControl.State.normal)
    previousButton.configuration?.image = previouseImg
    nextButton.setImage(nextImg, for: UIControl.State.normal)
    nextButton.configuration?.image = nextImg
  }

  func refreshRepeatButton(repeatButton: UIButton) {
    let isSelected = player.repeatMode != .off
    var image: UIImage?
    switch player.repeatMode {
    case .off:
      image = .repeatMenu
    case .all:
      image = .repeatAll
    case .single:
      image = .repeatOne
    }

    switch style {
    case .miniPlayeriOS, .miniPlayerMac:
      repeatButton.configuration?.image = image?
        .withConfiguration(UIImage.SymbolConfiguration(scale: .medium))
      repeatButton.tintColor = isSelected ? .tintColor : .secondaryLabel
      repeatButton.backgroundColor = isSelected ? .tintColor.withAlphaComponent(0.2) : .clear
    case .popupPlayer:
      var config = UIButton.Configuration.player(isSelected: isSelected)
      config.image = image?
        .withConfiguration(UIImage.SymbolConfiguration(scale: .medium))
      repeatButton.configuration = config
      #if targetEnvironment(macCatalyst)
        repeatButton.isHidden = !appDelegate.isShowingMiniPlayer
      #else
        repeatButton.isHidden = false
      #endif
    }
    repeatButton.isSelected = isSelected
  }

  func refreshShuffleButton(shuffleButton: UIButton) {
    switch style {
    case .miniPlayeriOS, .miniPlayerMac:
      shuffleButton.configuration?.image = .shuffle
        .withConfiguration(UIImage.SymbolConfiguration(scale: .medium))
      shuffleButton.tintColor = player.isShuffle ? .tintColor : .secondaryLabel
      shuffleButton.backgroundColor = player.isShuffle ? .tintColor.withAlphaComponent(0.2) : .clear
    case .popupPlayer:
      var config = UIButton.Configuration.player(isSelected: player.isShuffle)
      config.image = .shuffle
        .withConfiguration(UIImage.SymbolConfiguration(scale: .medium))
      shuffleButton.configuration = config
      #if targetEnvironment(macCatalyst)
        shuffleButton.isHidden = !appDelegate.isShowingMiniPlayer
      #else
        shuffleButton.isHidden = false
      #endif
    }
    shuffleButton.isEnabled = appDelegate.storage.settings.user.isPlayerShuffleButtonEnabled
    shuffleButton.isSelected = player.isShuffle
  }

  func refreshAutoplayButton(autoplayButton: UIButton) {
    let isActive = appDelegate.storage.settings.user.isAutoplayEnabled

    switch style {
    case .miniPlayeriOS, .miniPlayerMac:
      autoplayButton.configuration?.image = .infinity
        .withConfiguration(UIImage.SymbolConfiguration(scale: .medium))
      autoplayButton.tintColor = isActive ? .tintColor : .secondaryLabel
      autoplayButton.backgroundColor = isActive ? .tintColor.withAlphaComponent(0.2) : .clear
    case .popupPlayer:
      var config = UIButton.Configuration.player(isSelected: isActive)
      config.image = .infinity
        .withConfiguration(UIImage.SymbolConfiguration(scale: .medium))
      autoplayButton.configuration = config
    }
    autoplayButton.isEnabled = player.playerMode == .music
    autoplayButton.isSelected = isActive
  }

  func refreshDisplayPlaylistButton(displayPlaylistButton: UIButton) {
    let isQueueDisplayed = appDelegate.storage.settings.user.isPlayerQueueDisplayed

    switch style {
    case .miniPlayeriOS, .miniPlayerMac:
      displayPlaylistButton.tintColor = isQueueDisplayed ? .tintColor : .label
    case .popupPlayer:
      var config = UIButton.Configuration.plain()
      config.image = .playlistDisplayStyle
      config.preferredSymbolConfigurationForImage = Self.utilitySymbolConfiguration
      config.baseForegroundColor = .label
      displayPlaylistButton.isSelected = false
      displayPlaylistButton.configuration = config
    }
  }

  func refreshDisplayLyrisButton(displayLyricsButton: UIButton) {
    let isSelected = appDelegate.storage.settings.user.isPlayerLyricsDisplayed

    switch style {
    case .miniPlayeriOS, .miniPlayerMac:
      displayLyricsButton.tintColor = isSelected ? .tintColor : .label
    case .popupPlayer:
      break
    }
  }

  func refreshPlayerOptions(
    optionsButton: UIButton?,
    menuCreateCB: @escaping () -> [UIMenuElement]
  ) {
    optionsButton?.showsMenuAsPrimaryAction = true
    optionsButton?.menu = UIMenu.lazyMenu(title: L10n.tr("Player Options")) {
      menuCreateCB()
    }
  }

  func refreshCurrentlyPlayingInfo(
    artworkImage: LibraryEntityImage,
    titleLabel: UILabel,
    artistLabel: UILabel,
    albumLabel: UILabel? = nil,
    albumButton: UIButton? = nil,
    albumContainerView: UIView? = nil
  ) {
    refreshArtwork(artworkImage: artworkImage)
    if let playableInfo = player.currentlyPlaying {
      titleLabel.text = playableInfo.title
      albumLabel?.text = playableInfo.asSong?.album?.name ?? ""
      albumButton?.isEnabled = playableInfo.isSong
      albumContainerView?.isHidden = !playableInfo.isSong
      artistLabel.text = playableInfo.creatorName
    } else {
      switch player.playerMode {
      case .music:
        titleLabel.text = L10n.tr("No music playing")
      case .podcast:
        titleLabel.text = L10n.tr("No podcast playing")
      }
      albumLabel?.text = ""
      albumButton?.isEnabled = false
      albumContainerView?.isHidden = true
      artistLabel.text = ""
    }
  }

  func refreshArtwork(artworkImage: LibraryEntityImage) {
    if let playableInfo = player.currentlyPlaying {
      artworkImage.display(entity: playableInfo)
    } else {
      switch player.playerMode {
      case .music:
        artworkImage.display(
          artworkType: .song
        )
      case .podcast:
        artworkImage.display(
          artworkType: .podcastEpisode
        )
      }
    }
  }

  func airplayButtonPushed(button: UIButton) {
    appDelegate.userStatistics.usedAction(.airplay)

    #if targetEnvironment(macCatalyst) // ok
      // macOS: show the system audio output devices instead of the iOS route picker.
      AudioOutputPicker.toggle(above: button)
    #else
      let rect = CGRect(x: -100, y: 0, width: 0, height: 0)
      let airplayVolume = MPVolumeView(frame: rect)
      airplayVolume.showsVolumeSlider = false
      let rootView = button.superview ?? button
      rootView.addSubview(airplayVolume)
      for view: UIView in airplayVolume.subviews {
        if let button = view as? UIButton {
          button.sendActions(for: .touchUpInside)
          break
        }
      }
      airplayVolume.removeFromSuperview()
    #endif
  }

  var isLyricsButtonAllowedToDisplay: Bool {
    appDelegate.player.playerMode == .music
  }

  private var remainingTime: Int? {
    let duration = player.duration
    if player.currentlyPlaying != nil, duration.isNormal, !duration.isZero {
      return Int(player.elapsedTime - ceil(player.duration))
    }
    return nil
  }

  func timeSliderChanged(timeSlider: UISlider) {
    player.seek(toSecond: Double(timeSlider.value))
  }

  func timeSliderIsChanging(
    timeSlider: UISlider,
    elapsedTimeLabel: UILabel,
    remainingTimeLabel: UILabel
  ) {
    let elapsedClockTime = ClockTime(timeInSeconds: Int(timeSlider.value))
    elapsedTimeLabel.text = elapsedClockTime.asShortString()
    let remainingTime =
      ClockTime(timeInSeconds: Int(Double(timeSlider.value) - ceil(player.duration)))
    remainingTimeLabel.text = remainingTime.asShortString()
  }

  func refreshTimeInfo(
    timeSlider: UISlider,
    elapsedTimeLabel: UILabel,
    remainingTimeLabel: UILabel,
    audioInfoLabel: UILabel,
    playTypeIcon: UIImageView,
    liveLabel: UILabel
  ) {
    if timeSlider.preferredBehavioralStyle != .pad {
      timeSlider.preferredBehavioralStyle = .pad
    }
    timeSlider.sliderStyle = .thumbless
    if player.currentlyPlaying != nil {
      timeSlider.isEnabled = style != .miniPlayeriOS
      timeSlider.minimumValue = 0.0
      timeSlider.maximumValue = Float(player.duration)
      if !timeSlider.isTracking {
        let elapsedClockTime = ClockTime(timeInSeconds: Int(player.elapsedTime))
        setTextIfChanged(elapsedTimeLabel, elapsedClockTime.asShortString())
        if let remainingTime = remainingTime {
          setTextIfChanged(
            remainingTimeLabel,
            ClockTime(timeInSeconds: remainingTime).asShortString()
          )
        } else {
          setTextIfChanged(remainingTimeLabel, "--:--")
        }
        let elapsed = Float(player.elapsedTime)
        if abs(timeSlider.value - elapsed) > 0.01 {
          timeSlider.value = elapsed
        }
      }

      audioInfoLabel.isHidden = true
      playTypeIcon.isHidden = true
      liveLabel.isHidden = true
      timeSlider.layer.mask = nil
    } else {
      audioInfoLabel.isHidden = true
      playTypeIcon.isHidden = true
      liveLabel.isHidden = true
      timeSlider.layer.mask = nil
      setTextIfChanged(elapsedTimeLabel, "--:--")
      setTextIfChanged(remainingTimeLabel, "--:--")
      timeSlider.isEnabled = false
      timeSlider.minimumValue = 0.0
      timeSlider.maximumValue = 1.0
      timeSlider.value = 0.0
    }
  }

  private func setTextIfChanged(_ label: UILabel, _ text: String) {
    if label.text != text { label.text = text }
  }
}
