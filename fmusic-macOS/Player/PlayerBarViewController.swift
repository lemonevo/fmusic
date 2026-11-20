//
//  PlayerBarViewController.swift
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
import CoreMedia
import fmusicKit

/// Bottom player bar: artwork, title/artist, transport controls, progress and volume.
@MainActor
final class PlayerBarViewController: NSViewController, MusicPlayable {
  private let artworkView = NSImageView()
  private let titleLabel = NSTextField(labelWithString: L10n.tr("No music playing"))
  private let artistLabel = NSTextField(labelWithString: "")

  private let previousButton = NSButton()
  private let playPauseButton = NSButton()
  private let nextButton = NSButton()

  private let elapsedLabel = NSTextField(labelWithString: "0:00")
  private let remainingLabel = NSTextField(labelWithString: "-0:00")
  private let progressSlider = NSSlider()
  private let volumeSlider = NSSlider()

  private let shuffleButton = NSButton()
  private let repeatButton = NSButton()

  nonisolated(unsafe) private var progressTimer: Timer?
  private var isUpdatingProgress = false

  private var player: PlayerFacade { FmusicKit.shared.player }
  private var storage: PersistentStorage { FmusicKit.shared.storage }

  // MARK: - Lifecycle

  override func loadView() {
    let root = NSView()
    root.wantsLayer = true
    root.translatesAutoresizingMaskIntoConstraints = false

    let background = NSVisualEffectView()
    background.material = .headerView
    background.blendingMode = .withinWindow
    background.state = .active
    background.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(background)
    NSLayoutConstraint.activate([
      background.topAnchor.constraint(equalTo: root.topAnchor),
      background.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      background.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      background.bottomAnchor.constraint(equalTo: root.bottomAnchor),
    ])

    configureArtwork()
    configureLabels()
    configureTransportButtons()
    configureProgress()
    configureVolume()
    configureModeButtons()

    let infoStack = NSStackView(views: [titleLabel, artistLabel])
    infoStack.orientation = .vertical
    infoStack.alignment = .leading
    infoStack.spacing = 1
    infoStack.translatesAutoresizingMaskIntoConstraints = false

    let centerStack = NSStackView(views: [
      previousButton,
      playPauseButton,
      nextButton,
      spacer(width: 12),
      elapsedLabel,
      progressSlider,
      remainingLabel,
    ])
    centerStack.orientation = .horizontal
    centerStack.alignment = .centerY
    centerStack.spacing = 10
    centerStack.translatesAutoresizingMaskIntoConstraints = false

    let rightStack = NSStackView(views: [
      shuffleButton,
      repeatButton,
      spacer(width: 8),
      volumeSlider,
    ])
    rightStack.orientation = .horizontal
    rightStack.alignment = .centerY
    rightStack.spacing = 10
    rightStack.translatesAutoresizingMaskIntoConstraints = false

    root.addSubview(artworkView)
    root.addSubview(infoStack)
    root.addSubview(centerStack)
    root.addSubview(rightStack)

    NSLayoutConstraint.activate([
      artworkView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
      artworkView.centerYAnchor.constraint(equalTo: root.centerYAnchor),
      artworkView.widthAnchor.constraint(equalToConstant: 44),
      artworkView.heightAnchor.constraint(equalToConstant: 44),

      infoStack.leadingAnchor.constraint(equalTo: artworkView.trailingAnchor, constant: 12),
      infoStack.centerYAnchor.constraint(equalTo: root.centerYAnchor),
      infoStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
      infoStack.widthAnchor.constraint(lessThanOrEqualToConstant: 230),

      centerStack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
      centerStack.centerYAnchor.constraint(equalTo: root.centerYAnchor),
      centerStack.leadingAnchor.constraint(
        greaterThanOrEqualTo: infoStack.trailingAnchor,
        constant: 16
      ),

      rightStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
      rightStack.centerYAnchor.constraint(equalTo: root.centerYAnchor),
      rightStack.leadingAnchor.constraint(
        greaterThanOrEqualTo: centerStack.trailingAnchor,
        constant: 16
      ),
    ])

    self.view = root
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    player.addNotifier(notifier: self)
    refreshAll()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(themeColorChanged),
      name: .macThemeColorChanged,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(playbackSettingsChanged),
      name: .macPlaybackSettingsChanged,
      object: nil
    )

    progressTimer = Timer(
      timeInterval: 0.5,
      target: self,
      selector: #selector(timerTick),
      userInfo: nil,
      repeats: true
    )
    if let progressTimer {
      RunLoop.main.add(progressTimer, forMode: .common)
    }
  }

  deinit {
    progressTimer?.invalidate()
    NotificationCenter.default.removeObserver(self)
  }

  @objc
  private func themeColorChanged() {
    updateModeButtons()
  }

  @objc
  private func playbackSettingsChanged() {
    volumeSlider.doubleValue = Double(FmusicKit.shared.storage.settings.user.playerVolume)
  }

  // MARK: - Configuration

  private func configureArtwork() {
    artworkView.imageScaling = .scaleProportionallyUpOrDown
    artworkView.wantsLayer = true
    artworkView.layer?.cornerRadius = 6
    artworkView.layer?.masksToBounds = true
    artworkView.translatesAutoresizingMaskIntoConstraints = false
  }

  private func configureLabels() {
    titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
    titleLabel.lineBreakMode = .byTruncatingTail
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    artistLabel.font = .systemFont(ofSize: 11)
    artistLabel.textColor = .secondaryLabelColor
    artistLabel.lineBreakMode = .byTruncatingTail
    artistLabel.translatesAutoresizingMaskIntoConstraints = false

    elapsedLabel.font = MacTheme.tabularBodyFont
    elapsedLabel.textColor = .secondaryLabelColor
    elapsedLabel.alignment = .right
    remainingLabel.font = MacTheme.tabularBodyFont
    remainingLabel.textColor = .secondaryLabelColor
    elapsedLabel.translatesAutoresizingMaskIntoConstraints = false
    remainingLabel.translatesAutoresizingMaskIntoConstraints = false
    elapsedLabel.widthAnchor.constraint(equalToConstant: 36).isActive = true
    remainingLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true
  }

  private func configureTransportButtons() {
    configure(button: previousButton, symbol: "backward.fill", action: #selector(playPrevious))
    configure(
      button: playPauseButton,
      symbol: "play.fill",
      action: #selector(togglePlayPause)
    )
    configure(button: nextButton, symbol: "forward.fill", action: #selector(playNext))
    playPauseButton.image = symbolImage("play.fill", size: 20)
    previousButton.image = symbolImage("backward.fill", size: 15)
    nextButton.image = symbolImage("forward.fill", size: 15)
    playPauseButton.contentTintColor = .labelColor
    previousButton.contentTintColor = .labelColor
    nextButton.contentTintColor = .labelColor
  }

  private func configureProgress() {
    progressSlider.minValue = 0
    progressSlider.maxValue = 1
    progressSlider.doubleValue = 0
    progressSlider.isContinuous = false
    progressSlider.target = self
    progressSlider.action = #selector(seek)
    progressSlider.translatesAutoresizingMaskIntoConstraints = false
    progressSlider.widthAnchor.constraint(equalToConstant: 240).isActive = true
  }

  private func configureVolume() {
    volumeSlider.minValue = 0
    volumeSlider.maxValue = 1
    volumeSlider.doubleValue = Double(storage.settings.user.playerVolume)
    volumeSlider.isContinuous = true
    volumeSlider.target = self
    volumeSlider.action = #selector(changeVolume)
    volumeSlider.translatesAutoresizingMaskIntoConstraints = false
    volumeSlider.widthAnchor.constraint(equalToConstant: 90).isActive = true
  }

  private func configureModeButtons() {
    configure(button: shuffleButton, symbol: "shuffle", action: #selector(toggleShuffle))
    configure(button: repeatButton, symbol: "repeat", action: #selector(cycleRepeatMode))
    shuffleButton.image = symbolImage("shuffle", size: 12)
    repeatButton.image = symbolImage("repeat", size: 12)
    shuffleButton.setButtonType(.momentaryChange)
    repeatButton.setButtonType(.momentaryChange)
  }

  private func symbolImage(_ name: String, size: CGFloat) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: nil)?
      .withSymbolConfiguration(
        NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
      )
  }

  private func configure(button: NSButton, symbol: String, action: Selector) {
    button.image = symbolImage(symbol, size: 14)
    button.isBordered = false
    button.bezelStyle = .regularSquare
    button.imagePosition = .imageOnly
    button.target = self
    button.action = action
    button.contentTintColor = .labelColor
    button.translatesAutoresizingMaskIntoConstraints = false
    button.widthAnchor.constraint(equalToConstant: 26).isActive = true
    button.heightAnchor.constraint(equalToConstant: 26).isActive = true
  }

  private func spacer(width: CGFloat) -> NSView {
    let view = NSView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.widthAnchor.constraint(equalToConstant: width).isActive = true
    return view
  }

  // MARK: - Refresh

  private func refreshAll() {
    refreshInfo()
    refreshArtwork()
    refreshPlaybackState()
    updateProgress()
    updateModeButtons()
  }

  private func refreshInfo() {
    if let playable = player.currentlyPlaying {
      titleLabel.stringValue = playable.title
      artistLabel.stringValue = playable.creatorName
    } else {
      titleLabel.stringValue = L10n.tr("No music playing")
      artistLabel.stringValue = ""
    }
  }

  private func refreshArtwork() {
    guard let playable = player.currentlyPlaying else {
      artworkView.image = ArtworkImageLoader.generatedImage(
        theme: storage.settings.accounts.activeSetting.read.themePreference,
        artworkType: .song
      )
      return
    }
    let setting = storage.settings.accounts.activeSetting.read
    artworkView.image = ArtworkImageLoader.image(
      for: playable,
      themePreference: setting.themePreference,
      artworkDisplayPreference: setting.artworkDisplayPreference
    )
  }

  private func refreshPlaybackState() {
    let symbol = player.isPlaying ? "pause.fill" : "play.fill"
    playPauseButton.image = symbolImage(symbol, size: 20)
    let duration = player.duration
    progressSlider.isEnabled = duration.isFinite && duration > 0
    if duration.isFinite, duration > 0 {
      progressSlider.maxValue = duration
    }
  }

  private func updateModeButtons() {
    let accent = MacTheme.accentColor
    shuffleButton.contentTintColor = player.isShuffle ? accent : .secondaryLabelColor
    switch player.repeatMode {
    case .off:
      repeatButton.contentTintColor = .secondaryLabelColor
      repeatButton.image = symbolImage("repeat", size: 12)
    case .all:
      repeatButton.contentTintColor = accent
      repeatButton.image = symbolImage("repeat", size: 12)
    case .single:
      repeatButton.contentTintColor = accent
      repeatButton.image = symbolImage("repeat.1", size: 12)
    }
    volumeSlider.doubleValue = Double(player.volume)
  }

  @objc
  private func updateProgress() {
    guard !isUpdatingProgress else { return }
    isUpdatingProgress = true
    defer { isUpdatingProgress = false }

    let duration = player.duration
    guard duration.isFinite, duration > 0 else {
      elapsedLabel.stringValue = "0:00"
      remainingLabel.stringValue = "-0:00"
      progressSlider.doubleValue = 0
      return
    }
    let elapsed = min(max(player.elapsedTime, 0), duration)
    progressSlider.doubleValue = elapsed
    elapsedLabel.stringValue = ClockTime(timeInSeconds: Int(elapsed)).asShortString()
    remainingLabel.stringValue = "-" + ClockTime(timeInSeconds: Int(duration - elapsed))
      .asShortString()
  }

  @objc
  private func timerTick() {
    guard player.isPlaying else { return }
    updateProgress()
  }

  // MARK: - Actions

  @objc
  private func togglePlayPause() {
    player.togglePlayPause()
    refreshPlaybackState()
  }

  @objc
  private func playNext() {
    player.playNext()
  }

  @objc
  private func playPrevious() {
    player.playPreviousOrReplay()
  }

  @objc
  private func seek() {
    player.seek(toSecond: progressSlider.doubleValue)
  }

  @objc
  private func changeVolume() {
    FmusicKit.shared.player.volume = Float(volumeSlider.doubleValue)
  }

  @objc
  private func toggleShuffle() {
    player.toggleShuffle()
    updateModeButtons()
  }

  @objc
  private func cycleRepeatMode() {
    player.setRepeatMode(player.repeatMode.nextMode)
    updateModeButtons()
  }

  // MARK: - MusicPlayable

  func didStartPlayingFromBeginning() {}

  func didStartPlaying() {
    refreshAll()
  }

  func didPause() {
    refreshPlaybackState()
    updateProgress()
  }

  func didStopPlaying() {
    refreshAll()
  }

  func didElapsedTimeChange() {
    updateProgress()
  }

  func didLyricsTimeChange(time: CMTime) {}

  func didPlaylistChange() {
    refreshInfo()
    refreshArtwork()
  }

  func didArtworkChange() {
    refreshArtwork()
  }

  func didNowPlayingInfoChange() {
    refreshInfo()
  }

  func didShuffleChange() {
    updateModeButtons()
  }

  func didRepeatChange() {
    updateModeButtons()
  }

  func didPlaybackRateChange() {}
}
