//
//  NowPlayingViewController.swift
//  fmusic-macOS
//
//  Full-window Now Playing page, ported from the Catalyst `PopupPlayerVC` /
//  `LargeCurrentlyPlayingPlayerView` (always dark, artwork coloured gradient,
//  chevron + volume chrome, artwork/details/progress/transport column, lyrics
//  column, favourite/options and the bottom-right utility cluster).
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
import CoreImage
import CoreMedia
import fmusicKit

@MainActor
final class NowPlayingViewController: NSViewController, MusicPlayable {
  /// Called when the user taps the chevron (full-window overlay mode).
  var onClose: (() -> Void)?

  private let backgroundView = PlayerBlurredArtworkBackground()

  private let closeButton = NSButton()
  private let volumePill = NSView()
  private let volumeIcon = NSImageView()
  private let volumeSlider = NSSlider()

  private let artworkView = NSImageView()
  private let songTitleLabel = NSTextField(labelWithString: L10n.tr("No music playing"))
  private let albumLabel = NSTextField(labelWithString: "")
  private let artistLabel = NSTextField(labelWithString: "")
  private let favoriteButton = NSButton()
  private let optionsButton = NSButton()

  private let progressSlider = NSSlider()
  private let elapsedLabel = NSTextField(labelWithString: "0:00")
  private let remainingLabel = NSTextField(labelWithString: "-0:00")

  private let shuffleButton = NSButton()
  private let previousButton = NSButton()
  private let playPauseButton = NSButton()
  private let nextButton = NSButton()
  private let repeatButton = NSButton()

  private let airplayButton = NSButton()
  private let queueButton = NSButton()
  private let moreButton = NSButton()

  private let lyricsController: LyricsSidebarViewController = {
    let controller = LyricsSidebarViewController()
    controller.usesTransparentBackground = true
    controller.compactRows = true
    return controller
  }()

  private var artworkWidthConstraint: NSLayoutConstraint?
  private var artworkHeightConstraint: NSLayoutConstraint?

  private var clockToken: UUID?
  private var isUpdatingProgress = false

  private var player: PlayerFacade { FmusicKit.shared.player }
  private let entityActions = PlayerEntityActions()
  private var entityPlaylistHandlers: [() -> Void] = []
  private var storage: PersistentStorage { FmusicKit.shared.storage }

  // MARK: - Layout constants (scaled from the Catalyst large player)

  private let sideMargin: CGFloat = 92
  private let artworkSide: CGFloat = 350
  private let lyricsGap: CGFloat = 170
  /// Space the artwork column occupies below the cover (metadata, progress, transport)
  /// plus the bottom utility cluster. The cover is capped by the window height so the
  /// page fits a resized window instead of overflowing (the design height is 768).
  private let artworkBottomChrome: CGFloat = 296
  private let artworkMinimumSide: CGFloat = 110

  // MARK: - Lifecycle

  override func loadView() {
    let root = NSView()
    root.wantsLayer = true
    root.layer?.backgroundColor = NSColor.black.cgColor
    root.appearance = NSAppearance(named: .darkAqua)
    self.view = root

    backgroundView.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(backgroundView)

    buildChrome(in: root)
    buildArtworkColumn(in: root)
    buildLyricsColumn(in: root)
    buildBottomCluster(in: root)

    NSLayoutConstraint.activate([
      backgroundView.topAnchor.constraint(equalTo: root.topAnchor),
      backgroundView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      backgroundView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      backgroundView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
    ])
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

  override func viewDidAppear() {
    super.viewDidAppear()
    lyricsController.setPaneVisible(true)
  }

  override func viewDidDisappear() {
    super.viewDidDisappear()
    lyricsController.setPaneVisible(false)
    PlaybackClock.shared.unsubscribe(clockToken)
    clockToken = nil
  }

  override func viewDidLayout() {
    super.viewDidLayout()
    // The page was designed for the fixed 1024×768 overlay; now that it fills the
    // resizable main window the cover shrinks first so the transport row stays visible.
    let available = view.bounds.height - 122 - artworkBottomChrome
    let side = min(artworkSide, max(artworkMinimumSide, available))
    if artworkWidthConstraint?.constant != side {
      artworkWidthConstraint?.constant = side
      artworkHeightConstraint?.constant = side
    }
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  // MARK: - Build

  private func buildChrome(in root: NSView) {
    configureRound(closeButton, symbol: "chevron.down", action: #selector(closePressed), size: 15)
    closeButton.layer?.cornerRadius = 21
    closeButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
    closeButton.widthAnchor.constraint(equalToConstant: 42).isActive = true
    closeButton.heightAnchor.constraint(equalToConstant: 42).isActive = true

    volumePill.wantsLayer = true
    volumePill.layer?.cornerRadius = 16
    volumePill.layer?.masksToBounds = true
    volumePill.translatesAutoresizingMaskIntoConstraints = false
    let volumeGlass: NSView
    if #available(macOS 26.0, *) {
      let glass = NSGlassEffectView()
      glass.style = .regular
      glass.cornerRadius = 16
      volumeGlass = glass
    } else {
      let effect = NSVisualEffectView()
      effect.material = .popover
      effect.blendingMode = .withinWindow
      effect.state = .active
      volumeGlass = effect
    }
    volumeGlass.translatesAutoresizingMaskIntoConstraints = false
    volumePill.addSubview(volumeGlass)

    volumeIcon.image = NSImage(
      systemSymbolName: "speaker.wave.2.fill",
      accessibilityDescription: nil
    )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .medium))
    volumeIcon.contentTintColor = .white
    volumeIcon.translatesAutoresizingMaskIntoConstraints = false

    volumeSlider.minValue = 0
    volumeSlider.maxValue = 1
    volumeSlider.doubleValue = Double(player.volume)
    volumeSlider.controlSize = .large
    volumeSlider.isContinuous = true
    volumeSlider.target = self
    volumeSlider.action = #selector(volumeChanged)
    volumeSlider.translatesAutoresizingMaskIntoConstraints = false

    for item in [closeButton, volumePill] {
      root.addSubview(item)
    }
    volumePill.addSubview(volumeSlider)
    volumePill.addSubview(volumeIcon)

    NSLayoutConstraint.activate([
      closeButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
      // Clear the traffic lights instead of sitting in the same titlebar band.
      closeButton.topAnchor.constraint(equalTo: root.topAnchor, constant: 44),

      volumePill.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
      volumePill.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
      volumePill.widthAnchor.constraint(equalToConstant: 200),
      volumePill.heightAnchor.constraint(equalToConstant: 32),

      volumeGlass.topAnchor.constraint(equalTo: volumePill.topAnchor),
      volumeGlass.leadingAnchor.constraint(equalTo: volumePill.leadingAnchor),
      volumeGlass.trailingAnchor.constraint(equalTo: volumePill.trailingAnchor),
      volumeGlass.bottomAnchor.constraint(equalTo: volumePill.bottomAnchor),
      volumeSlider.leadingAnchor.constraint(equalTo: volumePill.leadingAnchor, constant: 12),
      volumeSlider.trailingAnchor.constraint(equalTo: volumeIcon.leadingAnchor, constant: -10),
      volumeSlider.centerYAnchor.constraint(equalTo: volumePill.centerYAnchor),
      volumeSlider.heightAnchor.constraint(equalToConstant: 22),

      volumeIcon.trailingAnchor.constraint(equalTo: volumePill.trailingAnchor, constant: -12),
      volumeIcon.centerYAnchor.constraint(equalTo: volumePill.centerYAnchor),
    ])
  }

  private func buildArtworkColumn(in root: NSView) {
    artworkView.imageScaling = .scaleProportionallyUpOrDown
    artworkView.wantsLayer = true
    artworkView.layer?.cornerRadius = 10
    artworkView.layer?.masksToBounds = true
    artworkView.layer?.shadowColor = NSColor.black.cgColor
    artworkView.layer?.shadowOpacity = 0.35
    artworkView.layer?.shadowRadius = 30
    artworkView.layer?.shadowOffset = CGSize(width: 0, height: -12)
    artworkView.translatesAutoresizingMaskIntoConstraints = false

    songTitleLabel.font = .systemFont(ofSize: 22, weight: .bold)
    songTitleLabel.textColor = .white
    songTitleLabel.lineBreakMode = .byTruncatingTail
    albumLabel.font = .systemFont(ofSize: 15)
    albumLabel.textColor = NSColor.white.withAlphaComponent(0.85)
    albumLabel.lineBreakMode = .byTruncatingTail
    artistLabel.font = .systemFont(ofSize: 13)
    artistLabel.textColor = NSColor.white.withAlphaComponent(0.55)
    artistLabel.lineBreakMode = .byTruncatingTail
    for label in [songTitleLabel, albumLabel, artistLabel] {
      label.translatesAutoresizingMaskIntoConstraints = false
    }

    configureGlyphButton(favoriteButton, symbol: "heart", action: #selector(toggleFavorite))
    configureGlyphButton(optionsButton, symbol: "ellipsis", action: #selector(showEntityMenu))


    progressSlider.minValue = 0
    progressSlider.maxValue = 1
    progressSlider.isContinuous = false
    progressSlider.controlSize = .large
    progressSlider.target = self
    progressSlider.action = #selector(seek)
    progressSlider.translatesAutoresizingMaskIntoConstraints = false
    for label in [elapsedLabel, remainingLabel] {
      label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
      label.textColor = NSColor.white.withAlphaComponent(0.65)
      label.lineBreakMode = .byClipping
      label.maximumNumberOfLines = 1
      label.setContentCompressionResistancePriority(.required, for: .horizontal)
      label.translatesAutoresizingMaskIntoConstraints = false
    }
    remainingLabel.alignment = .right

    configureRound(shuffleButton, symbol: "shuffle", action: #selector(toggleShuffle), size: 16)
    configureRound(previousButton, symbol: "backward.fill", action: #selector(playPrevious), size: 22)
    configureRound(playPauseButton, symbol: "play.fill", action: #selector(togglePlayPause), size: 26)
    configureRound(nextButton, symbol: "forward.fill", action: #selector(playNext), size: 22)
    configureRound(repeatButton, symbol: "repeat", action: #selector(cycleRepeat), size: 16)

    for item in [
      artworkView, songTitleLabel, albumLabel, artistLabel,
      favoriteButton, optionsButton, progressSlider, elapsedLabel, remainingLabel,
      shuffleButton, previousButton, playPauseButton, nextButton, repeatButton,
    ] {
      root.addSubview(item)
    }

    let artworkWidth = artworkView.widthAnchor.constraint(equalToConstant: artworkSide)
    let artworkHeight = artworkView.heightAnchor.constraint(equalToConstant: artworkSide)
    artworkWidthConstraint = artworkWidth
    artworkHeightConstraint = artworkHeight

    NSLayoutConstraint.activate([
      artworkView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: sideMargin),
      artworkView.topAnchor.constraint(equalTo: root.topAnchor, constant: 122),
      artworkWidth,
      artworkHeight,

      songTitleLabel.leadingAnchor.constraint(equalTo: artworkView.leadingAnchor),
      songTitleLabel.topAnchor.constraint(equalTo: artworkView.bottomAnchor, constant: 26),

      albumLabel.leadingAnchor.constraint(equalTo: artworkView.leadingAnchor),
      albumLabel.topAnchor.constraint(equalTo: songTitleLabel.bottomAnchor, constant: 6),

      artistLabel.leadingAnchor.constraint(equalTo: artworkView.leadingAnchor),
      artistLabel.topAnchor.constraint(equalTo: albumLabel.bottomAnchor, constant: 3),

      // Both buttons on one horizontal line, right-aligned with the info block.
      optionsButton.trailingAnchor.constraint(equalTo: artworkView.trailingAnchor, constant: 40),
      optionsButton.centerYAnchor.constraint(equalTo: songTitleLabel.centerYAnchor),
      optionsButton.widthAnchor.constraint(equalToConstant: 36),
      optionsButton.heightAnchor.constraint(equalToConstant: 36),
      favoriteButton.trailingAnchor.constraint(equalTo: optionsButton.leadingAnchor, constant: -10),
      favoriteButton.centerYAnchor.constraint(equalTo: optionsButton.centerYAnchor),
      favoriteButton.widthAnchor.constraint(equalToConstant: 36),
      favoriteButton.heightAnchor.constraint(equalToConstant: 36),


      progressSlider.leadingAnchor.constraint(equalTo: artworkView.leadingAnchor),
      progressSlider.trailingAnchor.constraint(equalTo: artworkView.trailingAnchor, constant: 40),
      progressSlider.topAnchor.constraint(equalTo: artistLabel.bottomAnchor, constant: 40),

      elapsedLabel.leadingAnchor.constraint(equalTo: progressSlider.leadingAnchor),
      elapsedLabel.topAnchor.constraint(equalTo: progressSlider.bottomAnchor, constant: 6),
      elapsedLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),

      remainingLabel.trailingAnchor.constraint(equalTo: progressSlider.trailingAnchor),
      remainingLabel.centerYAnchor.constraint(equalTo: elapsedLabel.centerYAnchor),
      remainingLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
      remainingLabel.leadingAnchor.constraint(
        greaterThanOrEqualTo: elapsedLabel.trailingAnchor,
        constant: 12
      ),

      shuffleButton.leadingAnchor.constraint(equalTo: artworkView.leadingAnchor, constant: 20),
      shuffleButton.topAnchor.constraint(equalTo: elapsedLabel.bottomAnchor, constant: 24),
      repeatButton.leadingAnchor.constraint(equalTo: nextButton.trailingAnchor, constant: 42),
      repeatButton.centerYAnchor.constraint(equalTo: shuffleButton.centerYAnchor),

      previousButton.leadingAnchor.constraint(equalTo: shuffleButton.trailingAnchor, constant: 42),
      previousButton.centerYAnchor.constraint(equalTo: shuffleButton.centerYAnchor),
      playPauseButton.leadingAnchor.constraint(equalTo: previousButton.trailingAnchor, constant: 30),
      playPauseButton.centerYAnchor.constraint(equalTo: shuffleButton.centerYAnchor),
      nextButton.leadingAnchor.constraint(equalTo: playPauseButton.trailingAnchor, constant: 30),
      nextButton.centerYAnchor.constraint(equalTo: shuffleButton.centerYAnchor),
      repeatButton.trailingAnchor.constraint(
        lessThanOrEqualTo: progressSlider.trailingAnchor
      ),
    ])
  }

  private func buildLyricsColumn(in root: NSView) {
    addChild(lyricsController)
    let lyricsView = lyricsController.view
    lyricsView.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(lyricsView)
    NSLayoutConstraint.activate([
      lyricsView.leadingAnchor.constraint(
        equalTo: artworkView.trailingAnchor,
        constant: lyricsGap
      ),
      lyricsView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -64),
      lyricsView.topAnchor.constraint(equalTo: root.topAnchor, constant: 64),
      lyricsView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -56),
    ])
  }

  private func buildBottomCluster(in root: NSView) {
    configureRound(airplayButton, symbol: "airplayaudio", action: #selector(showDeviceMenu), size: 16)
    configureRound(queueButton, symbol: "list.bullet", action: #selector(showQueue), size: 16)
    configureRound(moreButton, symbol: "ellipsis.circle", action: #selector(showPlayerOptionsMenu), size: 16)
    for button in [airplayButton, queueButton, moreButton] {
      root.addSubview(button)
      button.widthAnchor.constraint(equalToConstant: 26).isActive = true
      button.heightAnchor.constraint(equalToConstant: 26).isActive = true
      button.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24).isActive = true
    }
    NSLayoutConstraint.activate([
      moreButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),
      queueButton.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor, constant: -22),
      airplayButton.trailingAnchor.constraint(equalTo: queueButton.leadingAnchor, constant: -22),
    ])
  }

  private func configureGlyphButton(_ button: NSButton, symbol: String, action: Selector) {
    button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
      .withSymbolConfiguration(NSImage.SymbolConfiguration(scale: .medium))
    button.imagePosition = .imageOnly
    button.target = self
    button.action = action
    if #available(macOS 26.0, *) {
      // System-provided Liquid Glass bezel (same component family the Catalyst app
      // gets from UIButton.Configuration.gray()).
      button.bezelStyle = .glass
      button.isBordered = true
    } else {
      button.bezelStyle = .regularSquare
      button.isBordered = false
    }
    button.translatesAutoresizingMaskIntoConstraints = false
    button.widthAnchor.constraint(equalToConstant: 36).isActive = true
    button.heightAnchor.constraint(equalToConstant: 36).isActive = true
  }

  private func configureRound(
    _ button: NSButton,
    symbol: String,
    action: Selector,
    size: CGFloat
  ) {
    button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
      .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: .medium))
    button.isBordered = false
    button.bezelStyle = .regularSquare
    button.imagePosition = .imageOnly
    button.contentTintColor = NSColor.white.withAlphaComponent(0.9)
    button.target = self
    button.action = action
    button.wantsLayer = true
    button.translatesAutoresizingMaskIntoConstraints = false
  }

  // MARK: - Refresh

  private func refreshAll() {
    refreshInfo()
    refreshArtwork()
    refreshPlaybackState()
    refreshModeState()
    updateProgress()
  }

  private func refreshInfo() {
    guard let playable = player.currentlyPlaying else {
      songTitleLabel.stringValue = L10n.tr("No music playing")
      albumLabel.stringValue = ""
      artistLabel.stringValue = ""
      return
    }
    songTitleLabel.stringValue = playable.title
    albumLabel.stringValue = playable.asSong?.album?.name ?? ""
    artistLabel.stringValue = playable.creatorName
  }

  private func refreshArtwork() {
    let setting = storage.settings.accounts.activeSetting.read
    let image: NSImage?
    if let playable = player.currentlyPlaying {
      image = ArtworkImageLoader.image(
        for: playable,
        themePreference: setting.themePreference,
        artworkDisplayPreference: setting.artworkDisplayPreference
      )
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
    setSymbol(playPauseButton, symbol: player.isPlaying ? "pause.fill" : "play.fill", size: 26)
    volumeSlider.doubleValue = Double(player.volume)
  }

  private func refreshModeState() {
    let accent = MacTheme.accentColor
    let idle = NSColor.white.withAlphaComponent(0.85)
    shuffleButton.contentTintColor = player.isShuffle ? accent : idle
    switch player.repeatMode {
    case .off:
      repeatButton.contentTintColor = idle
      setSymbol(repeatButton, symbol: "repeat", size: 16)
    case .all:
      repeatButton.contentTintColor = accent
      setSymbol(repeatButton, symbol: "repeat", size: 16)
    case .single:
      repeatButton.contentTintColor = accent
      setSymbol(repeatButton, symbol: "repeat.1", size: 16)
    }
    let favorite = player.currentlyPlaying?.asSong?.isFavorite ?? false
    setSymbol(favoriteButton, symbol: favorite ? "heart.fill" : "heart", size: 14)
  }

  private func setSymbol(_ button: NSButton, symbol: String, size: CGFloat) {
    button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
      .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: .medium))
  }

  @objc
  private func timerTick() {
    guard player.isPlaying else { return }
    updateProgress()
  }

  private func updateProgress() {
    guard !isUpdatingProgress else { return }
    isUpdatingProgress = true
    defer { isUpdatingProgress = false }
    let duration = player.duration
    guard duration.isFinite, duration > 0 else {
      progressSlider.doubleValue = 0
      elapsedLabel.stringValue = "0:00"
      remainingLabel.stringValue = "-0:00"
      return
    }
    let elapsed = min(max(player.elapsedTime, 0), duration)
    progressSlider.maxValue = duration
    progressSlider.doubleValue = elapsed
    elapsedLabel.stringValue = ClockTime(timeInSeconds: Int(elapsed)).asShortString()
    remainingLabel.stringValue = "-" +
      ClockTime(timeInSeconds: Int(max(0, duration - elapsed))).asShortString()
  }

  @objc
  private func themeColorChanged() {
    refreshArtwork()
    refreshModeState()
  }

  @objc
  private func libraryChanged() {
    refreshAll()
  }

  // MARK: - Actions

  override func cancelOperation(_ sender: Any?) {
    closePressed()
  }

  @objc
  private func closePressed() {
    if let onClose {
      onClose()
    } else {
      view.window?.performClose(nil)
    }
  }

  @objc
  private func volumeChanged() {
    player.volume = Float(volumeSlider.doubleValue)
  }

  @objc
  private func togglePlayPause() {
    player.togglePlayPause()
    refreshPlaybackState()
  }

  @objc
  private func playPrevious() {
    player.playPreviousOrReplay()
  }

  @objc
  private func playNext() {
    player.playNext()
  }

  @objc
  private func toggleShuffle() {
    player.toggleShuffle()
    refreshModeState()
  }

  @objc
  private func cycleRepeat() {
    player.setRepeatMode(player.repeatMode.nextMode)
    refreshModeState()
  }

  @objc
  private func seek() {
    player.seek(toSecond: progressSlider.doubleValue)
  }

  @objc
  private func toggleFavorite() {
    entityActions.toggleFavorite()
    refreshModeState()
  }

  @objc
  private func showPlayerOptionsMenu() {
    let menu = NSMenu()
    menu.addItem(headerItem(L10n.tr("Player Options")))

    menu.addItem(actionItem(L10n.tr("Clear Player"), #selector(clearPlayer)))

    let sleep = NSMenuItem(title: L10n.tr("Sleep Timer"), action: nil, keyEquivalent: "")
    sleep.submenu = sleepTimerMenu()
    menu.addItem(sleep)

    let speed = NSMenuItem(title: L10n.tr("Playback Speed"), action: nil, keyEquivalent: "")
    speed.submenu = playbackRateMenu()
    menu.addItem(speed)

    let offset = NSMenuItem(title: L10n.tr("Lyrics Offset"), action: nil, keyEquivalent: "")
    offset.submenu = lyricsOffsetMenu()
    menu.addItem(offset)

    menu.addItem(actionItem(L10n.tr("Hide Lyrics"), #selector(hideLyrics)))
    menu.addItem(disabledItem(L10n.tr("Show Audio Visualizer")))
    menu.addItem(disabledItem(L10n.tr("Add Current Queue to Playlist")))
    menu.addItem(actionItem(L10n.tr("Player Information"), #selector(showPlayerInfo)))

    menu.popUp(
      positioning: nil,
      at: NSPoint(x: moreButton.bounds.midX, y: moreButton.bounds.minY - 4),
      in: moreButton
    )
  }

  @objc
  private func showEntityMenu() {
    let menu = NSMenu()
    guard let song = player.currentlyPlaying?.asSong else { return }

    menu.addItem(actionItem(L10n.tr("Instant Mix"), #selector(instantMix)))

    let albumItem = actionItem(L10n.tr("Show Album"), #selector(showAlbumPage))
    albumItem.isEnabled = song.album != nil
    menu.addItem(albumItem)
    let artistItem = actionItem(L10n.tr("Show Artist"), #selector(showArtistPage))
    artistItem.isEnabled = song.artist != nil
    menu.addItem(artistItem)

    menu.addItem(actionItem(L10n.tr("Desktop Lyrics"), #selector(toggleDesktopLyrics)))
    menu.addItem(actionItem(L10n.tr("Match Online Lyrics"), #selector(matchOnlineLyrics)))
    menu.addItem(.separator())

    let playlistOptions = entityActions.addToPlaylistOptions(for: song)
    entityPlaylistHandlers = playlistOptions.map(\.1)
    let playlistItem = NSMenuItem(
      title: L10n.tr("Add to Playlist"),
      action: nil,
      keyEquivalent: ""
    )
    if playlistOptions.isEmpty {
      playlistItem.isEnabled = false
    } else {
      let submenu = NSMenu()
      for (index, option) in playlistOptions.enumerated() {
        let item = NSMenuItem(
          title: option.0,
          action: #selector(addToPlaylistChosen(_:)),
          keyEquivalent: ""
        )
        item.target = self
        item.tag = index
        submenu.addItem(item)
      }
      playlistItem.submenu = submenu
    }
    menu.addItem(playlistItem)

    let downloadItem = actionItem(L10n.tr("Download"), #selector(downloadCurrentSong))
    downloadItem.isEnabled = entityActions.canDownload(song)
    menu.addItem(downloadItem)
    menu.addItem(actionItem(L10n.tr("Share"), #selector(shareCurrentSong)))

    menu.popUp(
      positioning: nil,
      at: NSPoint(x: optionsButton.bounds.midX, y: optionsButton.bounds.minY - 4),
      in: optionsButton
    )
  }

  @objc
  private func instantMix() {
    entityActions.instantMix()
  }

  @objc
  private func showAlbumPage() {
    entityActions.showAlbum()
  }

  @objc
  private func showArtistPage() {
    entityActions.showArtist()
  }

  @objc
  private func toggleDesktopLyrics() {
    entityActions.toggleDesktopLyrics()
  }

  @objc
  private func matchOnlineLyrics() {
    entityActions.matchOnlineLyrics()
  }

  @objc
  private func addToPlaylistChosen(_ sender: NSMenuItem) {
    guard entityPlaylistHandlers.indices.contains(sender.tag) else { return }
    entityPlaylistHandlers[sender.tag]()
  }

  @objc
  private func downloadCurrentSong() {
    guard let song = player.currentlyPlaying?.asSong else { return }
    entityActions.download(song)
  }

  @objc
  private func shareCurrentSong() {
    guard let song = player.currentlyPlaying?.asSong else { return }
    entityActions.share(song, relativeTo: optionsButton)
  }

  private func headerItem(_ title: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.isEnabled = false
    return item
  }

  private func disabledItem(_ title: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.isEnabled = false
    return item
  }

  private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    return item
  }

  private func sleepTimerMenu() -> NSMenu {
    let menu = NSMenu()
    for (title, seconds) in [
      (L10n.tr("Off"), 0),
      (L10n.tr("15 Minutes"), 15 * 60),
      (L10n.tr("30 Minutes"), 30 * 60),
      (L10n.tr("60 Minutes"), 60 * 60),
    ] {
      let item = NSMenuItem(title: title, action: #selector(setSleepTimer(_:)), keyEquivalent: "")
      item.target = self
      item.tag = seconds
      menu.addItem(item)
    }
    return menu
  }

  private func playbackRateMenu() -> NSMenu {
    let menu = NSMenu()
    let rates: [(String, PlaybackRate)] = [
      ("0.5×", .dot5), ("0.75×", .dot75), ("1×", .one),
      ("1.25×", .oneDot25), ("1.5×", .oneDot5), ("1.75×", .oneDot75), ("2×", .two),
    ]
    for (title, rate) in rates {
      let item = NSMenuItem(title: title, action: #selector(setPlaybackRate(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = rate.rawValue
      item.state = player.playbackRate == rate ? .on : .off
      menu.addItem(item)
    }
    return menu
  }

  private func lyricsOffsetMenu() -> NSMenu {
    let menu = NSMenu()
    for (title, delta) in [
      (L10n.tr("−0.5 s"), -500), (L10n.tr("−0.25 s"), -250),
      (L10n.tr("Reset"), 0), (L10n.tr("+0.25 s"), 250), (L10n.tr("+0.5 s"), 500),
    ] {
      let item = NSMenuItem(title: title, action: #selector(adjustLyricsOffset(_:)), keyEquivalent: "")
      item.target = self
      item.tag = delta
      menu.addItem(item)
    }
    return menu
  }

  @objc
  private func clearPlayer() {
    player.stop()
  }

  @objc
  private func setSleepTimer(_ sender: NSMenuItem) {
    if sender.tag == 0 {
      AppDelegate.sharedAppDelegate?.turnOffSleepTimer(nil)
    } else {
      AppDelegate.sharedAppDelegate?.startSleepTimer(minutes: sender.tag / 60)
    }
  }

  @objc
  private func setPlaybackRate(_ sender: NSMenuItem) {
    guard let raw = sender.representedObject as? Int,
          let rate = PlaybackRate(rawValue: raw)
    else { return }
    player.setPlaybackRate(rate)
  }

  @objc
  private func adjustLyricsOffset(_ sender: NSMenuItem) {
    var user = storage.settings.user
    user.lyricsOffsetMs = sender.tag == 0 ? 0 : user.lyricsOffsetMs + sender.tag
    storage.settings.user = user
    NotificationCenter.default.post(name: .lyricsOffsetChanged, object: nil)
  }

  @objc
  private func hideLyrics() {
    (NSApp.delegate as? AppDelegate)?
      .mainWindowController?
      .mainViewController?
      .toggleLyricsPane()
  }

  @objc
  private func showPlayerInfo() {
    let playable = player.currentlyPlaying
    let lines = [
      L10n.tr("Title") + ": " + (playable?.title ?? "-"),
      L10n.tr("Album") + ": " + (playable?.asSong?.album?.name ?? "-"),
      L10n.tr("Artist") + ": " + (playable?.creatorName ?? "-"),
      String(format: "Duration: %.0f s", player.duration),
    ]
    let alert = NSAlert()
    alert.messageText = L10n.tr("Player Information")
    alert.informativeText = lines.joined(separator: "\n")
    alert.addButton(withTitle: L10n.tr("OK"))
    alert.runModal()
  }

  @objc
  private func showQueue() {
    PlayerPageWindowController.presentQueue()
  }

  @objc
  private func showDeviceMenu() {
    let menu = NSMenu()
    let defaultDevice = AudioOutputDevices.defaultOutputDevice()
    for device in AudioOutputDevices.outputDevices() {
      let item = NSMenuItem(
        title: device.name,
        action: #selector(selectDevice(_:)),
        keyEquivalent: ""
      )
      item.target = self
      item.representedObject = device.id
      item.state = device.id == defaultDevice ? .on : .off
      menu.addItem(item)
    }
    menu.addItem(.separator())
    let settings = NSMenuItem(
      title: L10n.tr("Sound Settings…"),
      action: #selector(openSoundSettings),
      keyEquivalent: ""
    )
    settings.target = self
    menu.addItem(settings)
    menu.popUp(
      positioning: nil,
      at: NSPoint(x: airplayButton.bounds.midX, y: airplayButton.bounds.minY - 4),
      in: airplayButton
    )
  }

  @objc
  private func selectDevice(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? AudioDeviceID else { return }
    AudioOutputDevices.setDefaultOutputDevice(id)
  }

  @objc
  private func openSoundSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
      NSWorkspace.shared.open(url)
    }
  }

  // MARK: - MusicPlayable

  func didStartPlayingFromBeginning() { refreshAll() }

  func didStartPlaying() { refreshAll() }

  func didPause() { refreshPlaybackState() }

  func didStopPlaying() { refreshAll() }

  func didElapsedTimeChange() { updateProgress() }

  func didLyricsTimeChange(time: CMTime) {}

  func didPlaylistChange() { refreshAll() }

  func didArtworkChange() { refreshArtwork() }

  func didNowPlayingInfoChange() { refreshInfo() }

  func didShuffleChange() { refreshModeState() }

  func didRepeatChange() { refreshModeState() }

  func didPlaybackRateChange() {}
}

// MARK: - PlayerBlurredArtworkBackground

/// Apple Music style dynamic ambient background derived from the current album cover:
/// extracts a 4-color quadrant palette (chroma-weighted so covers don't average into
/// muddy grey/brown), blends a saturation-boosted blurred artwork wash with four
/// slowly drifting radial color orbs, and crossfades smoothly between tracks.
@MainActor
private final class PlayerBlurredArtworkBackground: NSView {
  private struct Palette {
    let baseTop: NSColor
    let baseBottom: NSColor
    /// Four vibrant quadrant colors driving the drifting ambient orbs.
    let orbs: [NSColor]
  }

  private let baseGradientLayer = CAGradientLayer()
  private let artworkLayer = CALayer()
  private let orbContainerLayer = CALayer()
  private let orbLayers: [CAGradientLayer] = (0 ..< 4).map { _ in
    let orb = CAGradientLayer()
    orb.type = .radial
    orb.startPoint = CGPoint(x: 0.5, y: 0.5)
    orb.endPoint = CGPoint(x: 1.0, y: 1.0)
    orb.locations = [0.0, 0.45, 1.0]
    return orb
  }
  private let scrimLayer = CAGradientLayer()

  private static let ciContext = CIContext(options: [.cacheIntermediates: false])
  private var currentArtwork: NSImage?
  private var hasAppliedInitialPalette = false
  private var isAnimatingOrbs = false

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.masksToBounds = true
    layer?.backgroundColor = NSColor.black.cgColor

    baseGradientLayer.startPoint = CGPoint(x: 0.0, y: 1.0)
    baseGradientLayer.endPoint = CGPoint(x: 1.0, y: 0.0)
    layer?.addSublayer(baseGradientLayer)

    artworkLayer.contentsGravity = .resizeAspectFill
    artworkLayer.opacity = 0.48
    layer?.addSublayer(artworkLayer)

    orbContainerLayer.masksToBounds = true
    for orb in orbLayers {
      orbContainerLayer.addSublayer(orb)
    }
    layer?.addSublayer(orbContainerLayer)

    // Subtle dark vignette/scrim so white lyrics and controls always stay legible
    // even on bright yellow or white album covers.
    scrimLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
    scrimLayer.endPoint = CGPoint(x: 0.5, y: 0.0)
    scrimLayer.colors = [
      NSColor.black.withAlphaComponent(0.22).cgColor,
      NSColor.black.withAlphaComponent(0.14).cgColor,
      NSColor.black.withAlphaComponent(0.36).cgColor,
    ]
    scrimLayer.locations = [0.0, 0.45, 1.0]
    layer?.addSublayer(scrimLayer)
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window != nil {
      startOrbAnimationsIfNeeded()
    } else {
      stopOrbAnimations()
    }
  }

  override func layout() {
    super.layout()
    let b = bounds
    guard b.width > 0, b.height > 0 else { return }

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    baseGradientLayer.frame = b
    // Oversize the blurred artwork slightly so edges never show during scaling.
    artworkLayer.frame = b.insetBy(dx: -b.width * 0.08, dy: -b.height * 0.08)
    orbContainerLayer.frame = b
    scrimLayer.frame = b

    let orbSize = max(b.width, b.height) * 0.92
    let anchors: [CGPoint] = [
      CGPoint(x: b.width * 0.20, y: b.height * 0.78),
      CGPoint(x: b.width * 0.80, y: b.height * 0.72),
      CGPoint(x: b.width * 0.25, y: b.height * 0.24),
      CGPoint(x: b.width * 0.78, y: b.height * 0.22),
    ]
    for (index, orb) in orbLayers.enumerated() {
      orb.bounds = CGRect(x: 0, y: 0, width: orbSize, height: orbSize)
      orb.position = anchors[index]
    }
    CATransaction.commit()

    if window != nil {
      stopOrbAnimations()
      startOrbAnimationsIfNeeded()
    }
  }

  func apply(artwork: NSImage?, accent: NSColor) {
    guard artwork !== currentArtwork || !hasAppliedInitialPalette else { return }
    let shouldAnimate = hasAppliedInitialPalette
      && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    currentArtwork = artwork
    hasAppliedInitialPalette = true

    let palette = Self.extractPalette(from: artwork, fallback: accent)
    let blurredCG = Self.blurredCGImage(artwork, context: Self.ciContext)

    if shouldAnimate, let rootLayer = layer {
      let transition = CATransition()
      transition.type = .fade
      transition.duration = 0.85
      transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      rootLayer.add(transition, forKey: "albumBackgroundCrossfade")
    }

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    artworkLayer.contents = blurredCG
    baseGradientLayer.colors = [
      palette.baseTop.cgColor,
      palette.baseBottom.cgColor,
    ]
    for (index, orb) in orbLayers.enumerated() {
      let color = palette.orbs[index % palette.orbs.count]
      orb.colors = [
        color.withAlphaComponent(0.76).cgColor,
        color.withAlphaComponent(0.30).cgColor,
        color.withAlphaComponent(0.0).cgColor,
      ]
    }
    CATransaction.commit()

    startOrbAnimationsIfNeeded()
  }

  private func startOrbAnimationsIfNeeded() {
    guard !isAnimatingOrbs,
          window != nil,
          bounds.width > 0,
          bounds.height > 0,
          !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    else { return }
    isAnimatingOrbs = true

    let w = bounds.width
    let h = bounds.height
    let paths: [[CGPoint]] = [
      [
        CGPoint(x: w * 0.18, y: h * 0.80),
        CGPoint(x: w * 0.42, y: h * 0.62),
        CGPoint(x: w * 0.24, y: h * 0.48),
        CGPoint(x: w * 0.18, y: h * 0.80),
      ],
      [
        CGPoint(x: w * 0.82, y: h * 0.74),
        CGPoint(x: w * 0.62, y: h * 0.86),
        CGPoint(x: w * 0.74, y: h * 0.50),
        CGPoint(x: w * 0.82, y: h * 0.74),
      ],
      [
        CGPoint(x: w * 0.24, y: h * 0.22),
        CGPoint(x: w * 0.48, y: h * 0.34),
        CGPoint(x: w * 0.16, y: h * 0.42),
        CGPoint(x: w * 0.24, y: h * 0.22),
      ],
      [
        CGPoint(x: w * 0.78, y: h * 0.22),
        CGPoint(x: w * 0.54, y: h * 0.18),
        CGPoint(x: w * 0.84, y: h * 0.46),
        CGPoint(x: w * 0.78, y: h * 0.22),
      ],
    ]
    let durations: [CFTimeInterval] = [20, 24, 22, 26]
    let scales: [(CGFloat, CGFloat)] = [(0.92, 1.14), (1.08, 0.90), (0.94, 1.12), (1.10, 0.92)]

    for (index, orb) in orbLayers.enumerated() {
      let drift = CAKeyframeAnimation(keyPath: "position")
      drift.values = paths[index].map { NSValue(point: $0) }
      drift.duration = durations[index]
      drift.repeatCount = .infinity
      drift.calculationMode = .cubicPaced
      drift.isRemovedOnCompletion = false
      orb.add(drift, forKey: "ambientDrift")

      let breathe = CABasicAnimation(keyPath: "transform.scale")
      breathe.fromValue = scales[index].0
      breathe.toValue = scales[index].1
      breathe.duration = durations[index] * 0.6
      breathe.autoreverses = true
      breathe.repeatCount = .infinity
      breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      breathe.isRemovedOnCompletion = false
      orb.add(breathe, forKey: "ambientBreathe")
    }
  }

  private func stopOrbAnimations() {
    guard isAnimatingOrbs else { return }
    isAnimatingOrbs = false
    for orb in orbLayers {
      orb.removeAnimation(forKey: "ambientDrift")
      orb.removeAnimation(forKey: "ambientBreathe")
    }
  }

  // MARK: - Palette extraction & blur

  private static func extractPalette(from image: NSImage?, fallback: NSColor) -> Palette {
    let fallbackColors = Self.paletteFromSingleColor(fallback)
    guard let image,
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else { return fallbackColors }

    let grid = 16
    var pixels = [UInt8](repeating: 0, count: grid * grid * 4)
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
      data: &pixels,
      width: grid,
      height: grid,
      bitsPerComponent: 8,
      bytesPerRow: grid * 4,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return fallbackColors }

    context.interpolationQuality = .medium
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: grid, height: grid))

    // Extract a chroma-weighted representative color from each of the 4 quadrants
    // so multi-toned covers produce distinct, vibrant hues rather than muddy grey.
    let half = grid / 2
    let quadrants: [(Range<Int>, Range<Int>)] = [
      (0 ..< half, 0 ..< half),
      (half ..< grid, 0 ..< half),
      (0 ..< half, half ..< grid),
      (half ..< grid, half ..< grid),
    ]

    var rawQuadrants = [NSColor]()
    var maxChroma: CGFloat = 0
    for (xRange, yRange) in quadrants {
      var sumR: CGFloat = 0
      var sumG: CGFloat = 0
      var sumB: CGFloat = 0
      var totalWeight: CGFloat = 0
      for y in yRange {
        for x in xRange {
          let offset = (y * grid + x) * 4
          let r = CGFloat(pixels[offset]) / 255
          let g = CGFloat(pixels[offset + 1]) / 255
          let b = CGFloat(pixels[offset + 2]) / 255
          let hi = max(r, g, b)
          let lo = min(r, g, b)
          let chroma = hi - lo
          maxChroma = max(maxChroma, chroma)
          // Favor colorful, mid-tone pixels over pure black/white borders.
          let lumPenalty: CGFloat = (hi < 0.08 || lo > 0.92) ? 0.15 : 1.0
          let weight = (0.18 + chroma * chroma * 4.5) * lumPenalty
          sumR += r * weight
          sumG += g * weight
          sumB += b * weight
          totalWeight += weight
        }
      }
      if totalWeight > 0 {
        rawQuadrants.append(
          NSColor(
            srgbRed: sumR / totalWeight,
            green: sumG / totalWeight,
            blue: sumB / totalWeight,
            alpha: 1
          )
        )
      }
    }

    guard rawQuadrants.count == 4 else { return fallbackColors }
    let isMonochrome = maxChroma < 0.08

    let orbs = rawQuadrants.map { color -> NSColor in
      Self.tunedColor(
        color,
        isMonochrome: isMonochrome,
        saturationBoost: 1.42,
        minSaturation: 0.38,
        minBrightness: 0.34,
        maxBrightness: 0.62
      )
    }
    let baseTop = Self.tunedColor(
      rawQuadrants[0],
      isMonochrome: isMonochrome,
      saturationBoost: 1.25,
      minSaturation: 0.30,
      minBrightness: 0.12,
      maxBrightness: 0.24
    )
    let baseBottom = Self.tunedColor(
      rawQuadrants[3],
      isMonochrome: isMonochrome,
      saturationBoost: 1.25,
      minSaturation: 0.30,
      minBrightness: 0.08,
      maxBrightness: 0.18
    )
    return Palette(baseTop: baseTop, baseBottom: baseBottom, orbs: orbs)
  }

  private static func tunedColor(
    _ color: NSColor,
    isMonochrome: Bool,
    saturationBoost: CGFloat,
    minSaturation: CGFloat,
    minBrightness: CGFloat,
    maxBrightness: CGFloat
  )
    -> NSColor {
    let srgb = color.usingColorSpace(.sRGB) ?? color
    var h: CGFloat = 0
    var s: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 1
    srgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
    let targetS = isMonochrome
      ? min(s, 0.08)
      : min(max(s * saturationBoost, minSaturation), 0.92)
    let targetB = min(max(b * 0.85, minBrightness), maxBrightness)
    return NSColor(hue: h, saturation: targetS, brightness: targetB, alpha: 1)
  }

  private static func paletteFromSingleColor(_ color: NSColor) -> Palette {
    let baseTop = Self.tunedColor(
      color,
      isMonochrome: false,
      saturationBoost: 1.1,
      minSaturation: 0.28,
      minBrightness: 0.12,
      maxBrightness: 0.22
    )
    let baseBottom = Self.tunedColor(
      color,
      isMonochrome: false,
      saturationBoost: 1.1,
      minSaturation: 0.28,
      minBrightness: 0.07,
      maxBrightness: 0.15
    )
    let orb = Self.tunedColor(
      color,
      isMonochrome: false,
      saturationBoost: 1.3,
      minSaturation: 0.36,
      minBrightness: 0.32,
      maxBrightness: 0.56
    )
    return Palette(baseTop: baseTop, baseBottom: baseBottom, orbs: [orb, orb, baseTop, orb])
  }

  private static func blurredCGImage(_ image: NSImage?, context: CIContext) -> CGImage? {
    guard let image,
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else { return nil }
    let ciImage = CIImage(cgImage: cgImage)
    let extent = ciImage.extent
    guard extent.width > 0, extent.height > 0 else { return nil }

    // Downscale before heavy Gaussian blur so large covers stay fast and smooth.
    let targetSide: CGFloat = 240
    let scale = min(1, targetSide / max(extent.width, extent.height))
    let scaled = scale < 1
      ? ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
      : ciImage
    let scaledExtent = scaled.extent

    let saturated: CIImage
    if let colorControls = CIFilter(name: "CIColorControls") {
      colorControls.setValue(scaled, forKey: kCIInputImageKey)
      colorControls.setValue(1.45, forKey: kCIInputSaturationKey)
      colorControls.setValue(1.05, forKey: kCIInputContrastKey)
      saturated = colorControls.outputImage ?? scaled
    } else {
      saturated = scaled
    }

    let blurred = saturated
      .clampedToExtent()
      .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 28])
      .cropped(to: scaledExtent)

    return context.createCGImage(blurred, from: scaledExtent)
  }
}
