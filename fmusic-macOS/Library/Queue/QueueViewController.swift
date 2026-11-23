//
//  QueueViewController.swift
//  fmusic-macOS
//
//  Now-playing + queue page: large artwork, title/artist, transport controls and
//  the up-next queue. Includes a small lyrics pane that follows the current song.
//  Not a sidebar item: the Lead opens it from a menu action (or inline).
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

/// Queue page with the current song and the player's up-next queue.
@MainActor
final class QueueViewController: NSViewController, MusicPlayable {
  private let titleLabel = NSTextField(labelWithString: L10n.tr("Queue"))
  private let contextLabel = NSTextField(labelWithString: "")

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

  private let lyricsHeader = NSTextField(labelWithString: L10n.tr("Lyrics"))
  private let lyricsPane = LyricsPaneView()
  private let queueSection = QueueSectionView()

  private var clockToken: UUID?
  private var isUpdatingProgress = false

  private var player: PlayerFacade { FmusicKit.shared.player }
  private var storage: PersistentStorage { FmusicKit.shared.storage }

  // MARK: - Lifecycle

  override func loadView() {
    let root = NSView()
    root.wantsLayer = true

    titleLabel.font = MacTheme.largeTitleFont
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    contextLabel.font = MacTheme.secondaryFont
    contextLabel.textColor = MacTheme.secondaryTextColor
    contextLabel.lineBreakMode = .byTruncatingTail
    contextLabel.translatesAutoresizingMaskIntoConstraints = false

    configureLeftPanel()

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
    leftPanel.addSubview(lyricsHeader)
    leftPanel.addSubview(lyricsPane)

    NSLayoutConstraint.activate([
      artworkView.topAnchor.constraint(equalTo: leftPanel.topAnchor, constant: 8),
      artworkView.centerXAnchor.constraint(equalTo: leftPanel.centerXAnchor),
      artworkView.widthAnchor.constraint(equalToConstant: 200),
      artworkView.heightAnchor.constraint(equalToConstant: 200),

      songTitleLabel.topAnchor.constraint(equalTo: artworkView.bottomAnchor, constant: 14),
      songTitleLabel.leadingAnchor.constraint(equalTo: leftPanel.leadingAnchor),
      songTitleLabel.trailingAnchor.constraint(equalTo: leftPanel.trailingAnchor),

      artistLabel.topAnchor.constraint(equalTo: songTitleLabel.bottomAnchor, constant: 3),
      artistLabel.leadingAnchor.constraint(equalTo: leftPanel.leadingAnchor),
      artistLabel.trailingAnchor.constraint(equalTo: leftPanel.trailingAnchor),

      albumLabel.topAnchor.constraint(equalTo: artistLabel.bottomAnchor, constant: 2),
      albumLabel.leadingAnchor.constraint(equalTo: leftPanel.leadingAnchor),
      albumLabel.trailingAnchor.constraint(equalTo: leftPanel.trailingAnchor),

      previousButton.topAnchor.constraint(equalTo: albumLabel.bottomAnchor, constant: 14),
      previousButton.centerXAnchor.constraint(equalTo: leftPanel.centerXAnchor, constant: -48),

      playPauseButton.centerYAnchor.constraint(equalTo: previousButton.centerYAnchor),
      playPauseButton.centerXAnchor.constraint(equalTo: leftPanel.centerXAnchor),

      nextButton.centerYAnchor.constraint(equalTo: previousButton.centerYAnchor),
      nextButton.centerXAnchor.constraint(equalTo: leftPanel.centerXAnchor, constant: 48),

      progressSlider.topAnchor.constraint(equalTo: playPauseButton.bottomAnchor, constant: 12),
      progressSlider.leadingAnchor.constraint(equalTo: leftPanel.leadingAnchor),
      progressSlider.trailingAnchor.constraint(equalTo: leftPanel.trailingAnchor),

      elapsedLabel.topAnchor.constraint(equalTo: progressSlider.bottomAnchor, constant: 2),
      elapsedLabel.leadingAnchor.constraint(equalTo: leftPanel.leadingAnchor),

      remainingLabel.topAnchor.constraint(equalTo: progressSlider.bottomAnchor, constant: 2),
      remainingLabel.trailingAnchor.constraint(equalTo: leftPanel.trailingAnchor),

      lyricsHeader.topAnchor.constraint(equalTo: elapsedLabel.bottomAnchor, constant: 14),
      lyricsHeader.leadingAnchor.constraint(equalTo: leftPanel.leadingAnchor),

      lyricsPane.topAnchor.constraint(equalTo: lyricsHeader.bottomAnchor, constant: 4),
      lyricsPane.leadingAnchor.constraint(equalTo: leftPanel.leadingAnchor),
      lyricsPane.trailingAnchor.constraint(equalTo: leftPanel.trailingAnchor),
      lyricsPane.bottomAnchor.constraint(equalTo: leftPanel.bottomAnchor),
      lyricsPane.heightAnchor.constraint(greaterThanOrEqualToConstant: 80),
    ])

    queueSection.translatesAutoresizingMaskIntoConstraints = false

    let divider = NSBox()
    divider.boxType = .separator
    divider.translatesAutoresizingMaskIntoConstraints = false

    root.addSubview(titleLabel)
    root.addSubview(contextLabel)
    root.addSubview(leftPanel)
    root.addSubview(divider)
    root.addSubview(queueSection)

    NSLayoutConstraint.activate([
      titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
      titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),

      contextLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      contextLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
      contextLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),

      leftPanel.topAnchor.constraint(equalTo: contextLabel.bottomAnchor, constant: 12),
      leftPanel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
      leftPanel.widthAnchor.constraint(equalToConstant: 300),
      leftPanel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),

      divider.topAnchor.constraint(equalTo: leftPanel.topAnchor),
      divider.bottomAnchor.constraint(equalTo: leftPanel.bottomAnchor),
      divider.leadingAnchor.constraint(equalTo: leftPanel.trailingAnchor, constant: 20),

      queueSection.topAnchor.constraint(equalTo: leftPanel.topAnchor),
      queueSection.leadingAnchor.constraint(equalTo: divider.trailingAnchor, constant: 20),
      queueSection.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
      queueSection.bottomAnchor.constraint(equalTo: leftPanel.bottomAnchor),
    ])

    self.view = root
  }

  private func configureLeftPanel() {
    artworkView.imageScaling = .scaleProportionallyUpOrDown
    artworkView.wantsLayer = true
    artworkView.layer?.cornerRadius = 10
    artworkView.layer?.masksToBounds = true
    artworkView.translatesAutoresizingMaskIntoConstraints = false

    songTitleLabel.font = .systemFont(ofSize: 18, weight: .bold)
    songTitleLabel.lineBreakMode = .byTruncatingTail
    songTitleLabel.translatesAutoresizingMaskIntoConstraints = false

    artistLabel.font = .systemFont(ofSize: 13)
    artistLabel.textColor = .secondaryLabelColor
    artistLabel.lineBreakMode = .byTruncatingTail
    artistLabel.translatesAutoresizingMaskIntoConstraints = false

    albumLabel.font = .systemFont(ofSize: 11)
    albumLabel.textColor = .tertiaryLabelColor
    albumLabel.lineBreakMode = .byTruncatingTail
    albumLabel.translatesAutoresizingMaskIntoConstraints = false

    configure(button: previousButton, symbol: "backward.fill", size: 15, pointSize: 24)
    previousButton.action = #selector(playPrevious)
    configure(button: playPauseButton, symbol: "play.fill", size: 22, pointSize: 36)
    playPauseButton.action = #selector(togglePlayPause)
    configure(button: nextButton, symbol: "forward.fill", size: 15, pointSize: 24)
    nextButton.action = #selector(playNext)

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

    lyricsHeader.font = .systemFont(ofSize: MacTheme.secondaryFontSize, weight: .semibold)
    lyricsHeader.textColor = .secondaryLabelColor
    lyricsHeader.translatesAutoresizingMaskIntoConstraints = false

    lyricsPane.translatesAutoresizingMaskIntoConstraints = false
  }

  private func configure(
    button: NSButton,
    symbol: String,
    size: CGFloat,
    pointSize: CGFloat
  ) {
    button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
      .withSymbolConfiguration(
        NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
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

    if clockToken == nil {
      clockToken = PlaybackClock.shared.subscribe { [weak self] in
        self?.timerTick()
      }
    }
  }

  override func viewDidDisappear() {
    super.viewDidDisappear()
    PlaybackClock.shared.unsubscribe(clockToken)
    clockToken = nil
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  @objc
  private func themeColorChanged() {
    queueSection.reload()
  }

  @objc
  private func libraryChanged() {
    queueSection.reload()
    refreshInfo()
    refreshArtwork()
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
    contextLabel.stringValue = player.contextName
  }

  private func refreshArtwork() {
    let setting = storage.settings.accounts.activeSetting.read
    if let playable = player.currentlyPlaying {
      artworkView.image = LMLibraryArtwork.image(for: playable, setting: setting)
    } else {
      artworkView.image = ArtworkImageLoader.generatedImage(
        theme: setting.themePreference,
        artworkType: .song
      )
    }
  }

  private func refreshPlaybackState() {
    let symbol = player.isPlaying ? "pause.fill" : "play.fill"
    playPauseButton.image = NSImage(
      systemSymbolName: symbol,
      accessibilityDescription: nil
    )?.withSymbolConfiguration(
      NSImage.SymbolConfiguration(pointSize: 22, weight: .medium)
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
