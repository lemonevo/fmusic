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

/// Floating capsule player bar (Apple Music style): artwork + title/artist on the left,
/// transport controls, a wide progress slider and the output/lyrics/queue/volume cluster on
/// the right. The capsule floats above the window content with rounded ends.
@MainActor
final class PlayerBarViewController: NSViewController, MusicPlayable {
  private let capsule = NSVisualEffectView()

  private let artworkView = NSImageView()
  private let titleLabel = NSTextField(labelWithString: L10n.tr("No music playing"))
  private let artistLabel = NSTextField(labelWithString: "")

  private let shuffleButton = NSButton()
  private let previousButton = NSButton()
  private let playPauseButton = NSButton()
  private let nextButton = NSButton()
  private let repeatButton = NSButton()

  private let elapsedLabel = NSTextField(labelWithString: "0:00")
  private let remainingLabel = NSTextField(labelWithString: "-0:00")
  private let progressSlider = NSSlider()

  private let lyricsButton = NSButton()
  private let queueButton = NSButton()
  private let moreButton = NSButton()
  private let outputButton = NSButton()
  private let volumeIcon = NSImageView()
  private let volumeSlider = NSSlider()

  /// Called when the user toggles the lyrics side pane.
  var onToggleLyricsPane: (() -> Void)?

  /// Whether the lyrics pane is currently visible (drives the toggle highlight).
  var isLyricsPaneVisible = false {
    didSet { updateLyricsButton() }
  }

  nonisolated(unsafe) private var progressTimer: Timer?
  private var isUpdatingProgress = false

  private var player: PlayerFacade { FmusicKit.shared.player }
  private var storage: PersistentStorage { FmusicKit.shared.storage }

  /// Height of the floating capsule (also used by the window layout).
  static let capsuleHeight: CGFloat = 56

  // MARK: - Lifecycle

  override func loadView() {
    let root = NSView()
    root.translatesAutoresizingMaskIntoConstraints = false
    root.wantsLayer = true

    capsule.material = .hudWindow
    capsule.blendingMode = .withinWindow
    capsule.state = .active
    capsule.wantsLayer = true
    capsule.layer?.cornerRadius = Self.capsuleHeight / 2
    capsule.layer?.masksToBounds = true
    capsule.layer?.borderWidth = 1
    capsule.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
    capsule.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(capsule)

    configureArtwork()
    configureLabels()
    configureTransportButtons()
    configureProgress()
    configureRightCluster()

    let leftGroup = NSStackView(views: [artworkView, infoStack()])
    leftGroup.orientation = .horizontal
    leftGroup.alignment = .centerY
    leftGroup.spacing = 10
    leftGroup.translatesAutoresizingMaskIntoConstraints = false

    let controlsGroup = NSStackView(views: [
      shuffleButton,
      previousButton,
      playPauseButton,
      nextButton,
      repeatButton,
    ])
    controlsGroup.orientation = .horizontal
    controlsGroup.alignment = .centerY
    controlsGroup.spacing = 4
    controlsGroup.translatesAutoresizingMaskIntoConstraints = false

    let progressGroup = NSStackView(views: [elapsedLabel, progressSlider, remainingLabel])
    progressGroup.orientation = .horizontal
    progressGroup.alignment = .centerY
    progressGroup.spacing = 10
    progressGroup.translatesAutoresizingMaskIntoConstraints = false
    progressSlider.setContentHuggingPriority(.defaultLow, for: .horizontal)
    progressSlider.setContentCompressionResistancePriority(
      .defaultLow,
      for: .horizontal
    )

    let rightGroup = NSStackView(views: [
      moreButton,
      lyricsButton,
      queueButton,
      outputButton,
      volumeIcon,
      volumeSlider,
    ])
    rightGroup.orientation = .horizontal
    rightGroup.alignment = .centerY
    rightGroup.spacing = 8
    rightGroup.translatesAutoresizingMaskIntoConstraints = false

    capsule.addSubview(leftGroup)
    capsule.addSubview(controlsGroup)
    capsule.addSubview(progressGroup)
    capsule.addSubview(rightGroup)

    NSLayoutConstraint.activate([
      capsule.topAnchor.constraint(equalTo: root.topAnchor),
      capsule.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      capsule.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      capsule.bottomAnchor.constraint(equalTo: root.bottomAnchor),
      capsule.heightAnchor.constraint(equalToConstant: Self.capsuleHeight),

      leftGroup.leadingAnchor.constraint(equalTo: capsule.leadingAnchor, constant: 14),
      leftGroup.centerYAnchor.constraint(equalTo: capsule.centerYAnchor),
      leftGroup.widthAnchor.constraint(lessThanOrEqualToConstant: 230),

      controlsGroup.leadingAnchor.constraint(
        greaterThanOrEqualTo: leftGroup.trailingAnchor,
        constant: 18
      ),
      controlsGroup.centerYAnchor.constraint(equalTo: capsule.centerYAnchor),

      progressGroup.leadingAnchor.constraint(
        greaterThanOrEqualTo: controlsGroup.trailingAnchor,
        constant: 18
      ),
      progressGroup.centerYAnchor.constraint(equalTo: capsule.centerYAnchor),
      progressGroup.trailingAnchor.constraint(
        lessThanOrEqualTo: rightGroup.leadingAnchor,
        constant: -18
      ),
      progressGroup.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),

      rightGroup.trailingAnchor.constraint(equalTo: capsule.trailingAnchor, constant: -18),
      rightGroup.centerYAnchor.constraint(equalTo: capsule.centerYAnchor),
      rightGroup.leadingAnchor.constraint(
        greaterThanOrEqualTo: progressGroup.trailingAnchor,
        constant: 4
      ),
    ])

    // Let the progress group grow between the control cluster and the right cluster.
    let centerX = progressGroup.centerXAnchor.constraint(equalTo: capsule.centerXAnchor)
    centerX.priority = .defaultLow
    centerX.isActive = true

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

  // MARK: - Configuration

  private func configureArtwork() {
    artworkView.imageScaling = .scaleProportionallyUpOrDown
    artworkView.wantsLayer = true
    artworkView.layer?.cornerRadius = 6
    artworkView.layer?.masksToBounds = true
    artworkView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      artworkView.widthAnchor.constraint(equalToConstant: 38),
      artworkView.heightAnchor.constraint(equalToConstant: 38),
    ])
  }

  private func infoStack() -> NSStackView {
    titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
    titleLabel.lineBreakMode = .byTruncatingTail
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    artistLabel.font = .systemFont(ofSize: 10)
    artistLabel.textColor = .secondaryLabelColor
    artistLabel.lineBreakMode = .byTruncatingTail
    artistLabel.translatesAutoresizingMaskIntoConstraints = false
    let stack = NSStackView(views: [titleLabel, artistLabel])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 0
    return stack
  }

  private func configureLabels() {
    elapsedLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    elapsedLabel.textColor = .secondaryLabelColor
    elapsedLabel.alignment = .right
    remainingLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    remainingLabel.textColor = .secondaryLabelColor
    remainingLabel.alignment = .left
    elapsedLabel.translatesAutoresizingMaskIntoConstraints = false
    remainingLabel.translatesAutoresizingMaskIntoConstraints = false
    elapsedLabel.widthAnchor.constraint(equalToConstant: 34).isActive = true
    remainingLabel.widthAnchor.constraint(equalToConstant: 38).isActive = true
  }

  private func configureTransportButtons() {
    configure(button: shuffleButton, symbol: "shuffle", size: 12, action: #selector(toggleShuffle))
    configure(button: previousButton, symbol: "backward.fill", size: 14, action: #selector(playPrevious))
    configure(
      button: playPauseButton,
      symbol: "play.fill",
      size: 19,
      action: #selector(togglePlayPause)
    )
    configure(button: nextButton, symbol: "forward.fill", size: 14, action: #selector(playNext))
    configure(
      button: repeatButton,
      symbol: "repeat",
      size: 12,
      action: #selector(cycleRepeatMode)
    )
    playPauseButton.widthAnchor.constraint(equalToConstant: 30).isActive = true
  }

  private func configureProgress() {
    progressSlider.minValue = 0
    progressSlider.maxValue = 1
    progressSlider.doubleValue = 0
    progressSlider.isContinuous = false
    progressSlider.translatesAutoresizingMaskIntoConstraints = false
    progressSlider.controlSize = .small
    progressSlider.target = self
    progressSlider.action = #selector(seek)
    progressSlider.setContentHuggingPriority(.defaultLow, for: .horizontal)
    progressSlider.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
  }

  private func configureRightCluster() {
    configure(
      button: lyricsButton,
      symbol: "quote.bubble",
      size: 13,
      action: #selector(toggleLyricsPane)
    )
    configure(button: queueButton, symbol: "list.bullet", size: 13, action: #selector(showQueue))
    configure(button: moreButton, symbol: "ellipsis.circle", size: 13, action: #selector(showMoreMenu))
    configure(button: outputButton, symbol: "airplayaudio", size: 13, action: #selector(showOutputMenu))

    volumeIcon.image = symbolImage("speaker.fill", size: 10)
    volumeIcon.contentTintColor = .secondaryLabelColor
    volumeIcon.translatesAutoresizingMaskIntoConstraints = false

    volumeSlider.minValue = 0
    volumeSlider.maxValue = 1
    volumeSlider.doubleValue = Double(storage.settings.user.playerVolume)
    volumeSlider.isContinuous = true
    volumeSlider.controlSize = .small
    volumeSlider.target = self
    volumeSlider.action = #selector(changeVolume)
    volumeSlider.translatesAutoresizingMaskIntoConstraints = false
    volumeSlider.widthAnchor.constraint(equalToConstant: 70).isActive = true
  }

  private func configure(button: NSButton, symbol: String, size: CGFloat, action: Selector) {
    button.image = symbolImage(symbol, size: size)
    button.isBordered = false
    button.bezelStyle = .regularSquare
    button.imagePosition = .imageOnly
    button.target = self
    button.action = action
    button.contentTintColor = .labelColor
    button.translatesAutoresizingMaskIntoConstraints = false
    button.widthAnchor.constraint(equalToConstant: 24).isActive = true
    button.heightAnchor.constraint(equalToConstant: 24).isActive = true
  }

  private func symbolImage(_ name: String, size: CGFloat) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: nil)?
      .withSymbolConfiguration(
        NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
      )
  }

  // MARK: - Refresh

  private func refreshAll() {
    refreshInfo()
    refreshArtwork()
    refreshPlaybackState()
    updateProgress()
    updateModeButtons()
    updateLyricsButton()
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
    playPauseButton.image = symbolImage(symbol, size: 19)
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

  private func updateLyricsButton() {
    lyricsButton.contentTintColor = isLyricsPaneVisible
      ? MacTheme.accentColor
      : .secondaryLabelColor
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

  @objc
  private func themeColorChanged() {
    updateModeButtons()
    updateLyricsButton()
  }

  @objc
  private func playbackSettingsChanged() {
    volumeSlider.doubleValue = Double(FmusicKit.shared.storage.settings.user.playerVolume)
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

  @objc
  private func toggleLyricsPane() {
    isLyricsPaneVisible.toggle()
    onToggleLyricsPane?()
  }

  @objc
  private func showQueue() {
    PlayerPageWindowController.presentQueue()
  }

  @objc
  private func showMoreMenu() {
    let menu = NSMenu()
    let nowPlaying = NSMenuItem(
      title: L10n.tr("Now Playing"),
      action: #selector(showNowPlayingFromMenu),
      keyEquivalent: ""
    )
    nowPlaying.target = self
    menu.addItem(nowPlaying)
    let queue = NSMenuItem(
      title: L10n.tr("Queue"),
      action: #selector(showQueueFromMenu),
      keyEquivalent: ""
    )
    queue.target = self
    menu.addItem(queue)
    let lyrics = NSMenuItem(
      title: L10n.tr("Show Lyrics"),
      action: #selector(showLyricsPageFromMenu),
      keyEquivalent: ""
    )
    lyrics.target = self
    menu.addItem(lyrics)
    menu.addItem(.separator())
    let mini = NSMenuItem(
      title: L10n.tr("Mini Player"),
      action: #selector(showMiniPlayerFromMenu),
      keyEquivalent: ""
    )
    mini.target = self
    menu.addItem(mini)
    menu.popUp(
      positioning: nil,
      at: NSPoint(x: moreButton.bounds.midX, y: moreButton.bounds.minY - 6),
      in: moreButton
    )
  }

  @objc
  private func showNowPlayingFromMenu() {
    PlayerPageWindowController.presentNowPlaying()
  }

  @objc
  private func showQueueFromMenu() {
    PlayerPageWindowController.presentQueue()
  }

  @objc
  private func showLyricsPageFromMenu() {
    LyricsPageWindowController.present()
  }

  @objc
  private func showMiniPlayerFromMenu() {
    AppDelegate.sharedAppDelegate?.showMiniPlayer(nil)
  }

  @objc
  private func showOutputMenu() {
    let menu = NSMenu()
    let title = NSMenuItem(title: L10n.tr("Audio Output"), action: nil, keyEquivalent: "")
    title.isEnabled = false
    menu.addItem(title)
    menu.addItem(.separator())
    let settings = NSMenuItem(
      title: L10n.tr("Open System Sound Settings"),
      action: #selector(openSoundSettings),
      keyEquivalent: ""
    )
    settings.target = self
    menu.addItem(settings)
    menu.popUp(
      positioning: nil,
      at: NSPoint(x: outputButton.bounds.midX, y: outputButton.bounds.minY - 6),
      in: outputButton
    )
  }

  @objc
  private func openSoundSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
      NSWorkspace.shared.open(url)
    }
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
