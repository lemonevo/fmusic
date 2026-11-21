//
//  MiniPlayerViewController.swift
//  fmusic-macOS
//
//  Content of the borderless mini player window: artwork, title/artist, transport,
//  progress and volume. It is a `MusicPlayable` notifier of the shared player, so it
//  always reflects the same state as the library window's player bar.
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

// MARK: - MiniPlayerViewController

@MainActor
final class MiniPlayerViewController: NSViewController, MusicPlayable {
  /// The expand button: switch back to the library window (handled by the app delegate).
  var onExpand: (() -> Void)?
  /// The close button: close the mini player without touching playback.
  var onClose: (() -> Void)?

  private let backgroundView = NSVisualEffectView()
  private let artworkView = NSImageView()
  private let titleLabel = NSTextField(labelWithString: L10n.tr("No music playing"))
  private let artistLabel = NSTextField(labelWithString: "")

  private let previousButton = NSButton()
  private let playPauseButton = NSButton()
  private let nextButton = NSButton()
  private let expandButton = NSButton()
  private let closeButton = NSButton()

  private let elapsedLabel = NSTextField(labelWithString: "0:00")
  private let remainingLabel = NSTextField(labelWithString: "-0:00")
  private let progressSlider = NSSlider()
  private let volumeIconView = NSImageView()
  private let volumeSlider = NSSlider()

  nonisolated(unsafe) private var progressTimer: Timer?
  private var isUpdatingProgress = false

  private var player: PlayerFacade { FmusicKit.shared.player }
  private var storage: PersistentStorage { FmusicKit.shared.storage }

  // MARK: - Lifecycle

  override func loadView() {
    let root = NSView(frame: NSRect(origin: .zero, size: MiniPlayerWindowController.contentSize))
    root.wantsLayer = true
    root.layer?.cornerRadius = 12
    root.layer?.masksToBounds = true

    backgroundView.material = .hudWindow
    backgroundView.blendingMode = .behindWindow
    backgroundView.state = .active
    backgroundView.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(backgroundView)

    configureArtwork()
    configureLabels()
    configureTransportButtons()
    configureWindowButtons()
    configureProgress()
    configureVolume()

    let transportRow = NSStackView(views: [previousButton, playPauseButton, nextButton])
    transportRow.orientation = .horizontal
    transportRow.alignment = .centerY
    transportRow.spacing = 18
    transportRow.translatesAutoresizingMaskIntoConstraints = false

    let progressRow = NSStackView(views: [elapsedLabel, progressSlider, remainingLabel])
    progressRow.orientation = .horizontal
    progressRow.alignment = .centerY
    progressRow.spacing = 6
    progressRow.translatesAutoresizingMaskIntoConstraints = false

    let volumeRow = NSStackView(views: [volumeIconView, volumeSlider])
    volumeRow.orientation = .horizontal
    volumeRow.alignment = .centerY
    volumeRow.spacing = 6
    volumeRow.translatesAutoresizingMaskIntoConstraints = false

    for view in [artworkView, titleLabel, artistLabel, transportRow, progressRow, volumeRow] {
      root.addSubview(view)
    }
    // The window buttons sit above the artwork/title row in the top trailing corner.
    root.addSubview(expandButton)
    root.addSubview(closeButton)

    NSLayoutConstraint.activate([
      backgroundView.topAnchor.constraint(equalTo: root.topAnchor),
      backgroundView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      backgroundView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      backgroundView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

      artworkView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
      artworkView.centerYAnchor.constraint(equalTo: root.centerYAnchor),
      artworkView.widthAnchor.constraint(equalToConstant: 96),
      artworkView.heightAnchor.constraint(equalToConstant: 96),

      closeButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
      closeButton.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),

      expandButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -6),
      expandButton.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),

      titleLabel.leadingAnchor.constraint(equalTo: artworkView.trailingAnchor, constant: 14),
      titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
      titleLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: expandButton.leadingAnchor,
        constant: -10
      ),

      artistLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      artistLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
      artistLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: expandButton.leadingAnchor,
        constant: -10
      ),

      transportRow.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      transportRow.topAnchor.constraint(equalTo: artistLabel.bottomAnchor, constant: 8),

      progressRow.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      progressRow.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
      progressRow.topAnchor.constraint(equalTo: transportRow.bottomAnchor, constant: 5),

      volumeRow.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      volumeRow.topAnchor.constraint(equalTo: progressRow.bottomAnchor, constant: 4),
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

    progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) {
      [weak self] _ in
      Task { @MainActor in self?.timerTick() }
    }
    if let progressTimer {
      RunLoop.main.add(progressTimer, forMode: .common)
    }
  }

  override func viewDidDisappear() {
    super.viewDidDisappear()
    progressTimer?.invalidate()
    progressTimer = nil
  }

  deinit {
    progressTimer?.invalidate()
    NotificationCenter.default.removeObserver(self)
  }

  @objc
  private func themeColorChanged() {
    updateSliderColors()
    refreshArtwork()
  }

  @objc
  private func playbackSettingsChanged() {
    volumeSlider.doubleValue = Double(storage.settings.user.playerVolume)
  }

  // MARK: - Configuration

  private func configureArtwork() {
    artworkView.imageScaling = .scaleProportionallyUpOrDown
    artworkView.wantsLayer = true
    artworkView.layer?.cornerRadius = 8
    artworkView.layer?.masksToBounds = true
    artworkView.translatesAutoresizingMaskIntoConstraints = false
  }

  private func configureLabels() {
    titleLabel.font = .systemFont(ofSize: MacTheme.bodyFontSize, weight: .semibold)
    titleLabel.lineBreakMode = .byTruncatingTail
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    artistLabel.font = MacTheme.secondaryFont
    artistLabel.textColor = .secondaryLabelColor
    artistLabel.lineBreakMode = .byTruncatingTail
    artistLabel.translatesAutoresizingMaskIntoConstraints = false

    let clockFont = NSFont.monospacedDigitSystemFont(
      ofSize: MacTheme.secondaryFontSize,
      weight: .regular
    )
    elapsedLabel.font = clockFont
    elapsedLabel.textColor = .secondaryLabelColor
    elapsedLabel.alignment = .right
    elapsedLabel.translatesAutoresizingMaskIntoConstraints = false
    elapsedLabel.widthAnchor.constraint(equalToConstant: 34).isActive = true

    remainingLabel.font = clockFont
    remainingLabel.textColor = .secondaryLabelColor
    remainingLabel.translatesAutoresizingMaskIntoConstraints = false
    remainingLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true
  }

  private func configureTransportButtons() {
    configure(
      button: previousButton,
      symbol: "backward.fill",
      size: 14,
      buttonSize: 26,
      action: #selector(playPrevious)
    )
    configure(
      button: playPauseButton,
      symbol: "play.fill",
      size: 18,
      buttonSize: 26,
      action: #selector(togglePlayPause)
    )
    configure(
      button: nextButton,
      symbol: "forward.fill",
      size: 14,
      buttonSize: 26,
      action: #selector(playNext)
    )
  }

  private func configureWindowButtons() {
    configure(
      button: expandButton,
      symbol: "arrow.up.left.and.arrow.down.right",
      size: 11,
      buttonSize: 20,
      action: #selector(expandToMainWindow)
    )
    configure(
      button: closeButton,
      symbol: "xmark",
      size: 11,
      buttonSize: 20,
      action: #selector(closeMiniPlayer)
    )
    expandButton.toolTip = L10n.tr("Switch Library/Mini Player")
    closeButton.toolTip = L10n.tr("Close")
  }

  private func configureProgress() {
    progressSlider.minValue = 0
    progressSlider.maxValue = 1
    progressSlider.doubleValue = 0
    progressSlider.isContinuous = false
    progressSlider.controlSize = .small
    progressSlider.target = self
    progressSlider.action = #selector(seek)
    progressSlider.translatesAutoresizingMaskIntoConstraints = false
    progressSlider.setContentHuggingPriority(.init(1), for: .horizontal)
    progressSlider.setContentCompressionResistancePriority(.init(1), for: .horizontal)
  }

  private func configureVolume() {
    volumeIconView.image = symbolImage("speaker.wave.2.fill", size: 11)
    volumeIconView.contentTintColor = .secondaryLabelColor
    volumeIconView.translatesAutoresizingMaskIntoConstraints = false
    volumeIconView.widthAnchor.constraint(equalToConstant: 14).isActive = true
    volumeIconView.heightAnchor.constraint(equalToConstant: 14).isActive = true

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

  private func configure(
    button: NSButton,
    symbol: String,
    size: CGFloat,
    buttonSize: CGFloat,
    action: Selector
  ) {
    button.image = symbolImage(symbol, size: size)
    button.isBordered = false
    button.bezelStyle = .regularSquare
    button.imagePosition = .imageOnly
    button.focusRingType = .none
    button.target = self
    button.action = action
    button.contentTintColor = .labelColor
    button.translatesAutoresizingMaskIntoConstraints = false
    button.widthAnchor.constraint(equalToConstant: buttonSize).isActive = true
    button.heightAnchor.constraint(equalToConstant: buttonSize).isActive = true
  }

  private func symbolImage(_ name: String, size: CGFloat) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: nil)?
      .withSymbolConfiguration(
        NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
      )
  }

  private func updateSliderColors() {
    progressSlider.trackFillColor = MacTheme.accentColor
    volumeSlider.trackFillColor = MacTheme.accentColor
  }

  // MARK: - Refresh

  private func refreshAll() {
    refreshInfo()
    refreshArtwork()
    refreshPlaybackState()
    updateProgress()
    updateSliderColors()
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
    let setting = storage.settings.accounts.activeSetting.read
    guard let playable = player.currentlyPlaying else {
      artworkView.image = ArtworkImageLoader.generatedImage(
        theme: setting.themePreference,
        artworkType: .song
      )
      return
    }
    artworkView.image = ArtworkImageLoader.image(
      for: playable,
      themePreference: setting.themePreference,
      artworkDisplayPreference: setting.artworkDisplayPreference
    )
  }

  private func refreshPlaybackState() {
    let symbol = player.isPlaying ? "pause.fill" : "play.fill"
    playPauseButton.image = symbolImage(symbol, size: 18)
    let duration = player.duration
    progressSlider.isEnabled = duration.isFinite && duration > 0
    if duration.isFinite, duration > 0 {
      progressSlider.maxValue = duration
    }
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
    volumeSlider.doubleValue = Double(player.volume)
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
    player.volume = Float(volumeSlider.doubleValue)
  }

  @objc
  private func expandToMainWindow() {
    onExpand?()
  }

  @objc
  private func closeMiniPlayer() {
    onClose?()
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

  func didShuffleChange() {}

  func didRepeatChange() {}

  func didPlaybackRateChange() {}
}
