//
//  NowPlayingViewController.swift
//  fmusic-macOS
//
//  Large "Now Playing" page: artwork with a theme/artwork colour gradient, song
//  metadata, transport controls, progress slider and inline lyrics/queue panes.
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

/// Big "正在播放" page. Two toggle buttons show the lyrics pane or the queue inline.
@MainActor
final class NowPlayingViewController: NSViewController, MusicPlayable {
  /// Called when the user taps the chevron (full-window overlay mode).
  var onClose: (() -> Void)?
  private let backgroundView = ArtworkGradientBackgroundView()
  private let titleLabel = NSTextField(labelWithString: L10n.tr("Now Playing"))
  private let closeButton = NSButton()
  private let volumeSlider = NSSlider()

  private let artworkView = NSImageView()
  private let songTitleLabel = NSTextField(labelWithString: L10n.tr("No music playing"))
  private let artistLabel = NSTextField(labelWithString: "")
  private let albumLabel = NSTextField(labelWithString: "")

  private let previousButton = NSButton()
  private let playPauseButton = NSButton()
  private let nextButton = NSButton()

  private let elapsedLabel = NSTextField(labelWithString: "0:00")
  private let remainingLabel = NSTextField(labelWithString: "-0:00")
  private let progressSlider = NSSlider()

  private let modeControl = NSSegmentedControl(
    labels: [L10n.tr("Lyrics"), L10n.tr("Queue")],
    trackingMode: .selectOne,
    target: nil,
    action: nil
  )
  private let panesContainer = NSView()
  private let lyricsPane = LyricsPaneView()
  private let queueSection = QueueSectionView()

  nonisolated(unsafe) private var progressTimer: Timer?
  private var isUpdatingProgress = false

  private var player: PlayerFacade { FmusicKit.shared.player }
  private var storage: PersistentStorage { FmusicKit.shared.storage }

  // MARK: - Lifecycle

  override func loadView() {
    let root = NSView()
    root.wantsLayer = true
    root.layer?.backgroundColor = NSColor.clear.cgColor

    backgroundView.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(backgroundView)

    titleLabel.font = MacTheme.largeTitleFont
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    configureCloseButton()
    configureVolumeControl()
    root.addSubview(closeButton)
    root.addSubview(volumeSlider)
    NSLayoutConstraint.activate([
      closeButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
      closeButton.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
      closeButton.widthAnchor.constraint(equalToConstant: 34),
      closeButton.heightAnchor.constraint(equalToConstant: 34),
      volumeSlider.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
      volumeSlider.topAnchor.constraint(equalTo: root.topAnchor, constant: 26),
      volumeSlider.widthAnchor.constraint(equalToConstant: 190),
    ])

    configureArtwork()
    configureLabels()
    configureTransport()
    configureProgress()

    modeControl.isHidden = true
    queueSection.isHidden = true
    modeControl.selectedSegment = 0
    modeControl.target = self
    modeControl.action = #selector(modeChanged)
    modeControl.translatesAutoresizingMaskIntoConstraints = false

    panesContainer.translatesAutoresizingMaskIntoConstraints = false
    lyricsPane.translatesAutoresizingMaskIntoConstraints = false
    queueSection.translatesAutoresizingMaskIntoConstraints = false
    queueSection.isHidden = true
    panesContainer.addSubview(lyricsPane)
    panesContainer.addSubview(queueSection)

    let leftPanel = NSView()
    leftPanel.translatesAutoresizingMaskIntoConstraints = false
    leftPanel.addSubview(artworkView)
    leftPanel.addSubview(songTitleLabel)
    leftPanel.addSubview(artistLabel)
    leftPanel.addSubview(albumLabel)
    leftPanel.addSubview(previousButton)
    leftPanel.addSubview(playPauseButton)
    leftPanel.addSubview(nextButton)
    leftPanel.addSubview(progressSlider)
    leftPanel.addSubview(elapsedLabel)
    leftPanel.addSubview(remainingLabel)

    titleLabel.isHidden = true
    root.addSubview(titleLabel)
    root.addSubview(leftPanel)
    root.addSubview(modeControl)
    root.addSubview(panesContainer)

    NSLayoutConstraint.activate([
      backgroundView.topAnchor.constraint(equalTo: root.topAnchor),
      backgroundView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      backgroundView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      backgroundView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

      leftPanel.topAnchor.constraint(equalTo: root.topAnchor, constant: 96),
      leftPanel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 32),
      leftPanel.widthAnchor.constraint(equalToConstant: 280),
      leftPanel.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -24),

      artworkView.topAnchor.constraint(equalTo: leftPanel.topAnchor),
      artworkView.leadingAnchor.constraint(equalTo: leftPanel.leadingAnchor),
      artworkView.widthAnchor.constraint(equalToConstant: 280),
      artworkView.heightAnchor.constraint(equalToConstant: 280),

      songTitleLabel.topAnchor.constraint(equalTo: artworkView.bottomAnchor, constant: 20),
      songTitleLabel.leadingAnchor.constraint(equalTo: leftPanel.leadingAnchor),
      songTitleLabel.trailingAnchor.constraint(equalTo: leftPanel.trailingAnchor),

      artistLabel.topAnchor.constraint(equalTo: songTitleLabel.bottomAnchor, constant: 4),
      artistLabel.leadingAnchor.constraint(equalTo: leftPanel.leadingAnchor),
      artistLabel.trailingAnchor.constraint(equalTo: leftPanel.trailingAnchor),

      albumLabel.topAnchor.constraint(equalTo: artistLabel.bottomAnchor, constant: 2),
      albumLabel.leadingAnchor.constraint(equalTo: leftPanel.leadingAnchor),
      albumLabel.trailingAnchor.constraint(equalTo: leftPanel.trailingAnchor),

      previousButton.topAnchor.constraint(equalTo: albumLabel.bottomAnchor, constant: 22),
      previousButton.centerXAnchor.constraint(equalTo: leftPanel.centerXAnchor, constant: -56),

      playPauseButton.centerYAnchor.constraint(equalTo: previousButton.centerYAnchor),
      playPauseButton.centerXAnchor.constraint(equalTo: leftPanel.centerXAnchor),

      nextButton.centerYAnchor.constraint(equalTo: previousButton.centerYAnchor),
      nextButton.centerXAnchor.constraint(equalTo: leftPanel.centerXAnchor, constant: 56),

      progressSlider.topAnchor.constraint(equalTo: playPauseButton.bottomAnchor, constant: 16),
      progressSlider.leadingAnchor.constraint(equalTo: leftPanel.leadingAnchor),
      progressSlider.trailingAnchor.constraint(equalTo: leftPanel.trailingAnchor),

      elapsedLabel.topAnchor.constraint(equalTo: progressSlider.bottomAnchor, constant: 2),
      elapsedLabel.leadingAnchor.constraint(equalTo: leftPanel.leadingAnchor),

      remainingLabel.topAnchor.constraint(equalTo: progressSlider.bottomAnchor, constant: 2),
      remainingLabel.trailingAnchor.constraint(equalTo: leftPanel.trailingAnchor),

      panesContainer.leadingAnchor.constraint(equalTo: leftPanel.trailingAnchor, constant: 40),
      panesContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -40),
      panesContainer.topAnchor.constraint(equalTo: root.topAnchor, constant: 96),
      panesContainer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24),

      lyricsPane.topAnchor.constraint(equalTo: panesContainer.topAnchor),
      lyricsPane.leadingAnchor.constraint(equalTo: panesContainer.leadingAnchor),
      lyricsPane.trailingAnchor.constraint(equalTo: panesContainer.trailingAnchor),
      lyricsPane.bottomAnchor.constraint(equalTo: panesContainer.bottomAnchor),

      queueSection.topAnchor.constraint(equalTo: panesContainer.topAnchor),
      queueSection.leadingAnchor.constraint(equalTo: panesContainer.leadingAnchor),
      queueSection.trailingAnchor.constraint(equalTo: panesContainer.trailingAnchor),
      queueSection.bottomAnchor.constraint(equalTo: panesContainer.bottomAnchor),
    ])

    self.view = root
  }

  private func configureCloseButton() {
    closeButton.image = NSImage(
      systemSymbolName: "chevron.down",
      accessibilityDescription: L10n.tr("Close")
    )
    closeButton.isBordered = false
    closeButton.bezelStyle = .regularSquare
    closeButton.imagePosition = .imageOnly
    closeButton.contentTintColor = .labelColor
    closeButton.wantsLayer = true
    closeButton.layer?.cornerRadius = 17
    closeButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
    closeButton.target = self
    closeButton.action = #selector(closePressed)
    closeButton.translatesAutoresizingMaskIntoConstraints = false
  }

  private func configureVolumeControl() {
    volumeSlider.minValue = 0
    volumeSlider.maxValue = 1
    volumeSlider.doubleValue = Double(storage.settings.user.playerVolume)
    volumeSlider.isContinuous = true
    volumeSlider.controlSize = .small
    volumeSlider.target = self
    volumeSlider.action = #selector(volumeChanged)
    volumeSlider.translatesAutoresizingMaskIntoConstraints = false
  }

  @objc
  private func closePressed() {
    onClose?()
  }

  @objc
  private func volumeChanged() {
    FmusicKit.shared.player.volume = Float(volumeSlider.doubleValue)
  }

  private func configureArtwork() {
    artworkView.imageScaling = .scaleProportionallyUpOrDown
    artworkView.wantsLayer = true
    artworkView.layer?.cornerRadius = 14
    artworkView.layer?.masksToBounds = true
    artworkView.layer?.shadowColor = NSColor.black.cgColor
    artworkView.layer?.shadowOpacity = 0.25
    artworkView.layer?.shadowRadius = 18
    artworkView.layer?.shadowOffset = CGSize(width: 0, height: -6)
    artworkView.translatesAutoresizingMaskIntoConstraints = false
  }

  private func configureLabels() {
    songTitleLabel.font = .systemFont(ofSize: 26, weight: .bold)
    songTitleLabel.lineBreakMode = .byTruncatingTail
    songTitleLabel.translatesAutoresizingMaskIntoConstraints = false

    artistLabel.font = .systemFont(ofSize: 16)
    artistLabel.textColor = .secondaryLabelColor
    artistLabel.lineBreakMode = .byTruncatingTail
    artistLabel.translatesAutoresizingMaskIntoConstraints = false

    albumLabel.font = .systemFont(ofSize: 13)
    albumLabel.textColor = .tertiaryLabelColor
    albumLabel.lineBreakMode = .byTruncatingTail
    albumLabel.translatesAutoresizingMaskIntoConstraints = false
  }

  private func configureTransport() {
    configure(
      button: previousButton,
      symbol: "backward.fill",
      symbolSize: 18,
      pointSize: 30
    )
    previousButton.action = #selector(playPrevious)
    configure(
      button: playPauseButton,
      symbol: "play.fill",
      symbolSize: 26,
      pointSize: 44
    )
    playPauseButton.action = #selector(togglePlayPause)
    configure(
      button: nextButton,
      symbol: "forward.fill",
      symbolSize: 18,
      pointSize: 30
    )
    nextButton.action = #selector(playNext)
  }

  private func configureProgress() {
    progressSlider.minValue = 0
    progressSlider.maxValue = 1
    progressSlider.isContinuous = false
    progressSlider.target = self
    progressSlider.action = #selector(seek)
    progressSlider.translatesAutoresizingMaskIntoConstraints = false

    elapsedLabel.font = MacTheme.tabularBodyFont
    elapsedLabel.textColor = .secondaryLabelColor
    elapsedLabel.translatesAutoresizingMaskIntoConstraints = false

    remainingLabel.font = MacTheme.tabularBodyFont
    remainingLabel.textColor = .secondaryLabelColor
    remainingLabel.alignment = .right
    remainingLabel.translatesAutoresizingMaskIntoConstraints = false
  }

  private func configure(
    button: NSButton,
    symbol: String,
    symbolSize: CGFloat,
    pointSize: CGFloat
  ) {
    button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
      .withSymbolConfiguration(
        NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .medium)
      )
    button.isBordered = false
    button.bezelStyle = .regularSquare
    button.imagePosition = .imageOnly
    button.target = self
    button.contentTintColor = .labelColor
    button.translatesAutoresizingMaskIntoConstraints = false
    button.widthAnchor.constraint(equalToConstant: pointSize).isActive = true
    button.heightAnchor.constraint(equalToConstant: pointSize).isActive = true
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
      selector: #selector(libraryChanged),
      name: .librarySongsSynced,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(libraryChanged),
      name: .accountActiveChanged,
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

  // MARK: - Notifications

  @objc
  private func themeColorChanged() {
    refreshArtwork()
    refreshPlaybackState()
  }

  @objc
  private func libraryChanged() {
    refreshInfo()
    refreshArtwork()
    queueSection.reload()
  }

  @objc
  private func modeChanged() {
    let showQueue = modeControl.selectedSegment == 1
    lyricsPane.isHidden = showQueue
    queueSection.isHidden = !showQueue
  }

  // MARK: - Refresh

  private func refreshAll() {
    refreshInfo()
    refreshArtwork()
    refreshPlaybackState()
    updateProgress()
    queueSection.reload()
  }

  private func refreshInfo() {
    songTitleLabel.stringValue = player.currentlyPlaying?.title ?? L10n.tr("No music playing")
    artistLabel.stringValue = player.currentlyPlaying?.creatorName ?? ""
    albumLabel.stringValue = player.currentlyPlaying?.asSong?.album?.name ?? ""
  }

  private func refreshArtwork() {
    let setting = storage.settings.accounts.activeSetting.read
    let image: NSImage
    if let playable = player.currentlyPlaying {
      image = LMLibraryArtwork.image(for: playable, setting: setting)
    } else {
      image = ArtworkImageLoader.generatedImage(
        theme: setting.themePreference,
        artworkType: .song
      )
    }
    artworkView.image = image
    backgroundView.apply(artwork: image, accent: MacTheme.accentColor)
  }

  private func refreshPlaybackState() {
    let symbol = player.isPlaying ? "pause.fill" : "play.fill"
    playPauseButton.image = NSImage(
      systemSymbolName: symbol,
      accessibilityDescription: nil
    )?.withSymbolConfiguration(
      NSImage.SymbolConfiguration(pointSize: 26, weight: .medium)
    )
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
    refreshPlaybackState()
    queueSection.reload()
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
