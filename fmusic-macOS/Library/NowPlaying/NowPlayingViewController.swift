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

  private var closePill: NSView?
  private let closeButton = GlassPillButton()
  private var volumePill: NSView?
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

  private var morePill: NSView?
  private let moreButton = GlassPillButton()
  private let modeTogglePill = NowPlayingModeTogglePill()

  private let lyricsController: LyricsSidebarViewController = {
    let controller = LyricsSidebarViewController()
    controller.usesTransparentBackground = true
    controller.compactRows = true
    return controller
  }()
  private let inlineQueueView = NowPlayingQueuePaneView()
  private var isShowingQueue = false

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
    lyricsController.setPaneVisible(!isShowingQueue)
    if isShowingQueue {
      inlineQueueView.reload()
    }
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

  private func makeGlassPill(cornerRadius: CGFloat = 17) -> (pill: NSView, content: NSView) {
    let pill = LiquidGlassCapsuleView(cornerRadius: cornerRadius)
    pill.translatesAutoresizingMaskIntoConstraints = false
    return (pill, pill.contentContainer)
  }

  private func buildChrome(in root: NSView) {
    let pillHeight: CGFloat = 34
    let pillRadius: CGFloat = pillHeight / 2

    let (closeGlass, closeContent) = makeGlassPill(cornerRadius: pillRadius)
    closePill = closeGlass
    configurePillButton(closeButton, symbol: "xmark", action: #selector(closePressed), size: 14, weight: .medium)
    closeContent.addSubview(closeButton)

    let (volumeGlass, volumeContent) = makeGlassPill(cornerRadius: pillRadius)
    volumePill = volumeGlass

    volumeIcon.image = NSImage(
      systemSymbolName: "speaker.wave.2.fill",
      accessibilityDescription: nil
    )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .medium))
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

    volumeContent.addSubview(volumeSlider)
    volumeContent.addSubview(volumeIcon)

    root.addSubview(closeGlass)
    root.addSubview(volumeGlass)

    NSLayoutConstraint.activate([
      // Clean gap beside the traffic lights, vertically centered with them and the volume pill.
      closeGlass.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 92),
      closeGlass.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
      closeGlass.widthAnchor.constraint(equalToConstant: 42),
      closeGlass.heightAnchor.constraint(equalToConstant: pillHeight),
      closeButton.topAnchor.constraint(equalTo: closeContent.topAnchor),
      closeButton.bottomAnchor.constraint(equalTo: closeContent.bottomAnchor),
      closeButton.leadingAnchor.constraint(equalTo: closeContent.leadingAnchor),
      closeButton.trailingAnchor.constraint(equalTo: closeContent.trailingAnchor),

      volumeGlass.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
      volumeGlass.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
      volumeGlass.widthAnchor.constraint(equalToConstant: 204),
      volumeGlass.heightAnchor.constraint(equalToConstant: pillHeight),

      volumeSlider.leadingAnchor.constraint(equalTo: volumeContent.leadingAnchor, constant: 14),
      volumeSlider.trailingAnchor.constraint(equalTo: volumeIcon.leadingAnchor, constant: -10),
      volumeSlider.centerYAnchor.constraint(equalTo: volumeContent.centerYAnchor),
      volumeSlider.heightAnchor.constraint(equalToConstant: 22),

      volumeIcon.trailingAnchor.constraint(equalTo: volumeContent.trailingAnchor, constant: -14),
      volumeIcon.centerYAnchor.constraint(equalTo: volumeContent.centerYAnchor),
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

    inlineQueueView.translatesAutoresizingMaskIntoConstraints = false
    inlineQueueView.isHidden = true
    root.addSubview(inlineQueueView)

    NSLayoutConstraint.activate([
      lyricsView.leadingAnchor.constraint(
        equalTo: artworkView.trailingAnchor,
        constant: lyricsGap
      ),
      lyricsView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -64),
      lyricsView.topAnchor.constraint(equalTo: root.topAnchor, constant: 64),
      lyricsView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -56),

      inlineQueueView.leadingAnchor.constraint(
        equalTo: artworkView.trailingAnchor,
        constant: lyricsGap
      ),
      inlineQueueView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -56),
      inlineQueueView.topAnchor.constraint(equalTo: root.topAnchor, constant: 72),
      inlineQueueView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -66),
    ])
  }

  private func buildBottomCluster(in root: NSView) {
    let pillHeight: CGFloat = 36
    let (moreGlass, moreContent) = makeGlassPill(cornerRadius: pillHeight / 2)
    morePill = moreGlass
    configurePillButton(moreButton, symbol: "ellipsis", action: #selector(showPlayerOptionsMenu), size: 15)
    moreContent.addSubview(moreButton)

    modeTogglePill.translatesAutoresizingMaskIntoConstraints = false
    modeTogglePill.onSelectQueue = { [weak self] showQueue in
      self?.setQueueVisible(showQueue, animated: true)
    }
    modeTogglePill.setQueueSelected(isShowingQueue, animated: false)

    root.addSubview(moreGlass)
    root.addSubview(modeTogglePill)

    NSLayoutConstraint.activate([
      modeTogglePill.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
      modeTogglePill.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18),
      modeTogglePill.widthAnchor.constraint(equalToConstant: 74),
      modeTogglePill.heightAnchor.constraint(equalToConstant: pillHeight),

      moreGlass.trailingAnchor.constraint(equalTo: modeTogglePill.leadingAnchor, constant: -10),
      moreGlass.centerYAnchor.constraint(equalTo: modeTogglePill.centerYAnchor),
      moreGlass.widthAnchor.constraint(equalToConstant: pillHeight),
      moreGlass.heightAnchor.constraint(equalToConstant: pillHeight),

      moreButton.topAnchor.constraint(equalTo: moreContent.topAnchor),
      moreButton.bottomAnchor.constraint(equalTo: moreContent.bottomAnchor),
      moreButton.leadingAnchor.constraint(equalTo: moreContent.leadingAnchor),
      moreButton.trailingAnchor.constraint(equalTo: moreContent.trailingAnchor),
    ])
  }

  private func configurePillButton(
    _ button: GlassPillButton,
    symbol: String,
    action: Selector,
    size: CGFloat,
    weight: NSFont.Weight = .medium
  ) {
    button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
      .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: weight))
    button.isBordered = false
    button.bezelStyle = .regularSquare
    button.imagePosition = .imageOnly
    button.contentTintColor = .white
    button.target = self
    button.action = action
    button.translatesAutoresizingMaskIntoConstraints = false
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

  private func setQueueVisible(_ visible: Bool, animated: Bool) {
    guard isShowingQueue != visible else { return }
    isShowingQueue = visible
    modeTogglePill.setQueueSelected(visible, animated: animated)
    lyricsController.setPaneVisible(!visible)
    if visible {
      inlineQueueView.reload()
    }
    let lyricsView = lyricsController.view
    if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      if visible {
        inlineQueueView.alphaValue = 0
        inlineQueueView.isHidden = false
      } else {
        lyricsView.alphaValue = 0
        lyricsView.isHidden = false
      }
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.2
        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        inlineQueueView.animator().alphaValue = visible ? 1 : 0
        lyricsView.animator().alphaValue = visible ? 0 : 1
      } completionHandler: { [weak self] in
        Task { @MainActor in
          guard let self else { return }
          self.inlineQueueView.isHidden = !self.isShowingQueue
          self.lyricsController.view.isHidden = self.isShowingQueue
          self.inlineQueueView.alphaValue = 1
          self.lyricsController.view.alphaValue = 1
        }
      }
    } else {
      inlineQueueView.isHidden = !visible
      lyricsView.isHidden = visible
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

// MARK: - LiquidGlassCapsuleView

/// Apple Music style Liquid Glass capsule over rich dark media backgrounds:
/// uses macOS 26 `NSGlassEffectView` (`.clear` style for bright translucent refraction
/// rather than dark muted `.regular`) topped with an anisotropic white specular rim
/// (brightest on the top & bottom curves, softer on the sides) and a subtle ambient
/// shadow so the capsule stays luminous whether the window is focused or unfocused.
@MainActor
private final class LiquidGlassCapsuleView: NSView {
  let contentContainer = NSView()
  private let cornerRadius: CGFloat
  private let backdropView: NSView
  private let sheenLayer = CAGradientLayer()
  private let rimGradientLayer = CAGradientLayer()
  private let rimMaskLayer = CAShapeLayer()

  init(cornerRadius: CGFloat) {
    self.cornerRadius = cornerRadius
    if #available(macOS 26.0, *) {
      let glass = NSGlassEffectView()
      glass.style = .clear
      glass.tintColor = NSColor.white.withAlphaComponent(0.10)
      glass.cornerRadius = cornerRadius
      backdropView = glass
    } else {
      let effect = NSVisualEffectView()
      effect.material = .popover
      effect.blendingMode = .withinWindow
      effect.state = .active
      effect.wantsLayer = true
      effect.layer?.cornerRadius = cornerRadius
      effect.layer?.masksToBounds = true
      backdropView = effect
    }
    super.init(frame: .zero)

    wantsLayer = true
    layer?.masksToBounds = false
    layer?.shadowColor = NSColor.black.cgColor
    layer?.shadowOpacity = 0.26
    layer?.shadowRadius = 10
    layer?.shadowOffset = CGSize(width: 0, height: -2)

    backdropView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(backdropView)

    // Subtle inner top-to-bottom glass sheen so the capsule reads as luminous curved glass.
    sheenLayer.colors = [
      NSColor.white.withAlphaComponent(0.16).cgColor,
      NSColor.white.withAlphaComponent(0.05).cgColor,
      NSColor.white.withAlphaComponent(0.02).cgColor,
      NSColor.white.withAlphaComponent(0.10).cgColor,
    ]
    sheenLayer.locations = [0.0, 0.35, 0.72, 1.0]
    sheenLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
    sheenLayer.endPoint = CGPoint(x: 0.5, y: 0.0)
    sheenLayer.cornerRadius = cornerRadius
    sheenLayer.masksToBounds = true
    layer?.addSublayer(sheenLayer)

    // Anisotropic Liquid Glass specular rim: bright silver-white on top & bottom edges,
    // softer along the horizontal mid-section, matching Apple Music's Tahoe pills.
    rimGradientLayer.colors = [
      NSColor.white.withAlphaComponent(0.75).cgColor,
      NSColor.white.withAlphaComponent(0.22).cgColor,
      NSColor.white.withAlphaComponent(0.20).cgColor,
      NSColor.white.withAlphaComponent(0.62).cgColor,
    ]
    rimGradientLayer.locations = [0.0, 0.36, 0.66, 1.0]
    rimGradientLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
    rimGradientLayer.endPoint = CGPoint(x: 0.5, y: 0.0)
    rimMaskLayer.fillColor = NSColor.clear.cgColor
    rimMaskLayer.strokeColor = NSColor.white.cgColor
    rimMaskLayer.lineWidth = 1.0
    rimGradientLayer.mask = rimMaskLayer
    layer?.addSublayer(rimGradientLayer)

    contentContainer.translatesAutoresizingMaskIntoConstraints = false
    addSubview(contentContainer)

    NSLayoutConstraint.activate([
      backdropView.topAnchor.constraint(equalTo: topAnchor),
      backdropView.leadingAnchor.constraint(equalTo: leadingAnchor),
      backdropView.trailingAnchor.constraint(equalTo: trailingAnchor),
      backdropView.bottomAnchor.constraint(equalTo: bottomAnchor),

      contentContainer.topAnchor.constraint(equalTo: topAnchor),
      contentContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
      contentContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
      contentContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func layout() {
    super.layout()
    let b = bounds
    guard b.width > 0, b.height > 0 else { return }
    let radius = min(cornerRadius, b.height / 2)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    sheenLayer.frame = b
    sheenLayer.cornerRadius = radius
    rimGradientLayer.frame = b
    let strokeRect = b.insetBy(dx: 0.5, dy: 0.5)
    rimMaskLayer.frame = b
    rimMaskLayer.path = CGPath(
      roundedRect: strokeRect,
      cornerWidth: max(0, radius - 0.5),
      cornerHeight: max(0, radius - 0.5),
      transform: nil
    )
    layer?.shadowPath = CGPath(
      roundedRect: b,
      cornerWidth: radius,
      cornerHeight: radius,
      transform: nil
    )
    CATransaction.commit()
  }
}

// MARK: - GlassPillButton

/// Borderless icon button hosted inside a Liquid Glass pill, with a soft circular
/// hover/press highlight and an Apple Music style bright white active disc state.
@MainActor
private final class GlassPillButton: NSButton {
  private var isHovered = false

  var isActivePill = false {
    didSet { updateFill() }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.masksToBounds = true
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func layout() {
    super.layout()
    layer?.cornerRadius = min(bounds.width, bounds.height) / 2
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(NSTrackingArea(
      rect: .zero,
      options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
      owner: self,
      userInfo: nil
    ))
  }

  override func mouseEntered(with event: NSEvent) {
    isHovered = true
    updateFill()
  }

  override func mouseExited(with event: NSEvent) {
    isHovered = false
    updateFill()
  }

  override func mouseDown(with event: NSEvent) {
    layer?.backgroundColor = isActivePill
      ? NSColor.white.withAlphaComponent(0.82).cgColor
      : NSColor.white.withAlphaComponent(0.28).cgColor
    super.mouseDown(with: event)
    updateFill()
  }

  private func updateFill() {
    if isActivePill {
      layer?.backgroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
      contentTintColor = NSColor(srgbRed: 0.14, green: 0.14, blue: 0.15, alpha: 1)
    } else {
      layer?.backgroundColor = isHovered
        ? NSColor.white.withAlphaComponent(0.16).cgColor
        : NSColor.clear.cgColor
      contentTintColor = .white
    }
  }
}

// MARK: - NowPlayingModeTogglePill

/// Apple Music macOS 26 Tahoe style bottom-right Liquid Glass sliding switcher
/// between Lyrics (`quote.bubble`) and Queue (`list.bullet`), with a bright
/// circular sliding thumb that springs and stretches smoothly across segments.
@MainActor
private final class NowPlayingModeTogglePill: NSView {
  var onSelectQueue: ((Bool) -> Void)?

  private let capsule = LiquidGlassCapsuleView(cornerRadius: 18)
  private let thumbHostView = NSView()
  private let thumbLayer = CALayer()
  private let lyricsButton = SegmentToggleButton()
  private let queueButton = SegmentToggleButton()

  private(set) var isQueueSelected = false

  private let thumbInset: CGFloat = 3
  private let thumbDiameter: CGFloat = 30
  private let activeIconTint = NSColor(srgbRed: 0.24, green: 0.24, blue: 0.26, alpha: 1)

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    buildUI()
  }

  required init?(coder: NSCoder) {
    nil
  }

  private func buildUI() {
    capsule.translatesAutoresizingMaskIntoConstraints = false
    addSubview(capsule)

    let content = capsule.contentContainer
    content.wantsLayer = true

    thumbHostView.wantsLayer = true
    thumbHostView.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(thumbHostView)

    thumbLayer.backgroundColor = NSColor(white: 0.94, alpha: 0.92).cgColor
    thumbLayer.cornerRadius = thumbDiameter / 2
    thumbLayer.borderWidth = 0.5
    thumbLayer.borderColor = NSColor.white.withAlphaComponent(0.60).cgColor
    thumbLayer.shadowColor = NSColor.black.cgColor
    thumbLayer.shadowOpacity = 0.16
    thumbLayer.shadowRadius = 4
    thumbLayer.shadowOffset = CGSize(width: 0, height: -1)
    thumbHostView.layer?.addSublayer(thumbLayer)

    configureButton(lyricsButton, action: #selector(lyricsPressed))
    configureButton(queueButton, action: #selector(queuePressed))

    content.addSubview(lyricsButton)
    content.addSubview(queueButton)

    NSLayoutConstraint.activate([
      capsule.topAnchor.constraint(equalTo: topAnchor),
      capsule.leadingAnchor.constraint(equalTo: leadingAnchor),
      capsule.trailingAnchor.constraint(equalTo: trailingAnchor),
      capsule.bottomAnchor.constraint(equalTo: bottomAnchor),

      thumbHostView.topAnchor.constraint(equalTo: content.topAnchor),
      thumbHostView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      thumbHostView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      thumbHostView.bottomAnchor.constraint(equalTo: content.bottomAnchor),

      lyricsButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: thumbInset),
      lyricsButton.centerYAnchor.constraint(equalTo: content.centerYAnchor),
      lyricsButton.widthAnchor.constraint(equalToConstant: thumbDiameter),
      lyricsButton.heightAnchor.constraint(equalToConstant: thumbDiameter),

      queueButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -thumbInset),
      queueButton.centerYAnchor.constraint(equalTo: content.centerYAnchor),
      queueButton.widthAnchor.constraint(equalToConstant: thumbDiameter),
      queueButton.heightAnchor.constraint(equalToConstant: thumbDiameter),
    ])

    applyIconStates()
  }

  private func configureButton(_ button: SegmentToggleButton, action: Selector) {
    button.isBordered = false
    button.bezelStyle = .regularSquare
    button.imagePosition = .imageOnly
    button.target = self
    button.action = action
    button.translatesAutoresizingMaskIntoConstraints = false
  }

  override func layout() {
    super.layout()
    let b = thumbHostView.bounds
    guard b.width > 0, b.height > 0 else { return }
    let diameter = min(thumbDiameter, b.height - thumbInset * 2)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    thumbLayer.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
    thumbLayer.cornerRadius = diameter / 2
    if thumbLayer.animation(forKey: "thumbSlide") == nil {
      thumbLayer.position = CGPoint(x: thumbCenterX(for: isQueueSelected, in: b), y: b.midY)
    }
    CATransaction.commit()
  }

  func setQueueSelected(_ selected: Bool, animated: Bool) {
    let changed = isQueueSelected != selected
    isQueueSelected = selected
    applyIconStates()

    let b = thumbHostView.bounds
    guard b.width > 0, b.height > 0 else { return }
    let targetX = thumbCenterX(for: selected, in: b)
    let targetPos = CGPoint(x: targetX, y: b.midY)
    let startX = thumbLayer.presentation()?.position.x ?? thumbLayer.position.x

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    thumbLayer.position = targetPos
    CATransaction.commit()

    guard changed, animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
      return
    }

    let slide = CASpringAnimation(keyPath: "position.x")
    slide.fromValue = startX
    slide.toValue = targetX
    slide.stiffness = 380
    slide.damping = 28
    slide.mass = 1.0
    slide.initialVelocity = 0
    slide.duration = slide.settlingDuration
    thumbLayer.add(slide, forKey: "thumbSlide")

    let stretchX = CAKeyframeAnimation(keyPath: "transform.scale.x")
    stretchX.values = [1.0, 1.18, 1.0]
    stretchX.keyTimes = [0.0, 0.42, 1.0]
    stretchX.timingFunctions = [
      CAMediaTimingFunction(name: .easeOut),
      CAMediaTimingFunction(name: .easeInEaseOut),
    ]
    stretchX.duration = 0.28
    thumbLayer.add(stretchX, forKey: "thumbStretchX")

    let squashY = CAKeyframeAnimation(keyPath: "transform.scale.y")
    squashY.values = [1.0, 0.94, 1.0]
    squashY.keyTimes = [0.0, 0.42, 1.0]
    squashY.timingFunctions = [
      CAMediaTimingFunction(name: .easeOut),
      CAMediaTimingFunction(name: .easeInEaseOut),
    ]
    squashY.duration = 0.28
    thumbLayer.add(squashY, forKey: "thumbSquashY")
  }

  private func thumbCenterX(for queueSelected: Bool, in bounds: CGRect) -> CGFloat {
    let radius = min(thumbDiameter, bounds.height - thumbInset * 2) / 2
    return queueSelected ? (bounds.width - thumbInset - radius) : (thumbInset + radius)
  }

  private func applyIconStates() {
    let lyricsSymbol = isQueueSelected ? "quote.bubble" : "quote.bubble.fill"
    let lyricsWeight: NSFont.Weight = isQueueSelected ? .medium : .semibold
    lyricsButton.image = NSImage(systemSymbolName: lyricsSymbol, accessibilityDescription: nil)?
      .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: lyricsWeight))
    lyricsButton.contentTintColor = isQueueSelected ? .white : activeIconTint
    lyricsButton.isSegmentSelected = !isQueueSelected

    queueButton.image = NSImage(systemSymbolName: "list.bullet", accessibilityDescription: nil)?
      .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold))
    queueButton.contentTintColor = isQueueSelected ? activeIconTint : .white
    queueButton.isSegmentSelected = isQueueSelected
  }

  @objc
  private func lyricsPressed() {
    guard isQueueSelected else { return }
    onSelectQueue?(false)
  }

  @objc
  private func queuePressed() {
    guard !isQueueSelected else { return }
    onSelectQueue?(true)
  }
}

@MainActor
private final class SegmentToggleButton: NSButton {
  private var isHovered = false

  var isSegmentSelected = false {
    didSet { updateHighlight() }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.masksToBounds = true
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func layout() {
    super.layout()
    layer?.cornerRadius = min(bounds.width, bounds.height) / 2
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(NSTrackingArea(
      rect: .zero,
      options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
      owner: self,
      userInfo: nil
    ))
  }

  override func mouseEntered(with event: NSEvent) {
    isHovered = true
    updateHighlight()
  }

  override func mouseExited(with event: NSEvent) {
    isHovered = false
    updateHighlight()
  }

  override func mouseDown(with event: NSEvent) {
    if !isSegmentSelected {
      layer?.backgroundColor = NSColor.white.withAlphaComponent(0.24).cgColor
    }
    super.mouseDown(with: event)
    updateHighlight()
  }

  private func updateHighlight() {
    if isSegmentSelected {
      layer?.backgroundColor = NSColor.clear.cgColor
    } else {
      layer?.backgroundColor = isHovered
        ? NSColor.white.withAlphaComponent(0.14).cgColor
        : NSColor.clear.cgColor
    }
  }
}

// MARK: - NowPlayingQueuePaneView

/// Inline right-hand Queue pane inside the fullscreen Now Playing view, styled
/// after Apple Music's fullscreen Up Next / History column.
@MainActor
private final class NowPlayingQueuePaneView: NSView, NSTableViewDataSource,
  NSTableViewDelegate, MusicPlayable {
  private enum Row {
    case sectionHeader(String)
    case track(AbstractPlayable, PlayerIndex)
  }

  private let headerTitleLabel = NSTextField(labelWithString: L10n.tr("Next in Queue"))
  private let clearButton = NSButton()
  private let headerDivider = NSView()
  private let scrollView = NSScrollView()
  private let tableView = NSTableView()
  private let emptyLabel = NSTextField(labelWithString: L10n.tr("No items in queue"))

  private var rows: [Row] = []
  private var hasRegisteredNotifier = false

  private let trackCellID = NSUserInterfaceItemIdentifier("npQueueTrackCell")
  private let headerCellID = NSUserInterfaceItemIdentifier("npQueueHeaderCell")
  private let columnID = NSUserInterfaceItemIdentifier("npQueueColumn")

  private var player: PlayerFacade { FmusicKit.shared.player }
  private var storage: PersistentStorage { FmusicKit.shared.storage }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    buildUI()
  }

  required init?(coder: NSCoder) {
    nil
  }

  private func buildUI() {
    wantsLayer = true

    headerTitleLabel.font = .systemFont(ofSize: 16, weight: .bold)
    headerTitleLabel.textColor = .white
    headerTitleLabel.translatesAutoresizingMaskIntoConstraints = false

    clearButton.title = L10n.tr("Clear")
    clearButton.isBordered = false
    clearButton.font = .systemFont(ofSize: 13, weight: .medium)
    clearButton.contentTintColor = MacTheme.accentColor
    clearButton.target = self
    clearButton.action = #selector(clearQueuePressed)
    clearButton.translatesAutoresizingMaskIntoConstraints = false

    headerDivider.wantsLayer = true
    headerDivider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
    headerDivider.translatesAutoresizingMaskIntoConstraints = false

    let column = NSTableColumn(identifier: columnID)
    column.resizingMask = .autoresizingMask
    tableView.addTableColumn(column)
    tableView.headerView = nil
    tableView.backgroundColor = .clear
    tableView.style = .plain
    tableView.selectionHighlightStyle = .none
    tableView.intercellSpacing = .zero
    tableView.focusRingType = .none
    tableView.dataSource = self
    tableView.delegate = self
    tableView.target = self
    tableView.action = #selector(rowClicked)
    tableView.doubleAction = #selector(rowClicked)

    scrollView.documentView = tableView
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.scrollerStyle = .overlay
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    emptyLabel.font = .systemFont(ofSize: 14, weight: .medium)
    emptyLabel.textColor = NSColor.white.withAlphaComponent(0.55)
    emptyLabel.alignment = .center
    emptyLabel.translatesAutoresizingMaskIntoConstraints = false

    addSubview(headerTitleLabel)
    addSubview(clearButton)
    addSubview(headerDivider)
    addSubview(scrollView)
    addSubview(emptyLabel)

    NSLayoutConstraint.activate([
      headerTitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
      headerTitleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),

      clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
      clearButton.centerYAnchor.constraint(equalTo: headerTitleLabel.centerYAnchor),

      headerDivider.leadingAnchor.constraint(equalTo: leadingAnchor),
      headerDivider.trailingAnchor.constraint(equalTo: trailingAnchor),
      headerDivider.topAnchor.constraint(equalTo: headerTitleLabel.bottomAnchor, constant: 10),
      headerDivider.heightAnchor.constraint(equalToConstant: 1),

      scrollView.topAnchor.constraint(equalTo: headerDivider.bottomAnchor, constant: 4),
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

      emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
      emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
    ])
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window != nil {
      if !hasRegisteredNotifier {
        hasRegisteredNotifier = true
        player.addNotifier(notifier: self)
      }
      reload()
    }
  }

  func reload() {
    clearButton.contentTintColor = MacTheme.accentColor
    var newRows: [Row] = []

    let userQueue = player.getAllUserQueueItems()
    let nextQueue = player.getAllNextQueueItems()
    let prevQueue = player.getAllPrevQueueItems()

    if !userQueue.isEmpty {
      for (index, playable) in userQueue.enumerated() {
        newRows.append(.track(playable, PlayerIndex(queueType: .user, index: index)))
      }
    }
    if !nextQueue.isEmpty {
      if !userQueue.isEmpty {
        newRows.append(.sectionHeader(L10n.tr("Next from: %@", player.contextName)))
      }
      for (index, playable) in nextQueue.enumerated() {
        newRows.append(.track(playable, PlayerIndex(queueType: .next, index: index)))
      }
    }
    if !prevQueue.isEmpty {
      if !newRows.isEmpty {
        newRows.append(.sectionHeader(L10n.tr("Previous")))
      }
      for (index, playable) in prevQueue.enumerated().reversed() {
        newRows.append(.track(playable, PlayerIndex(queueType: .prev, index: index)))
      }
    }

    let hasUpNext = !userQueue.isEmpty || !nextQueue.isEmpty
    headerTitleLabel.stringValue = hasUpNext
      ? L10n.tr("Next in Queue")
      : (prevQueue.isEmpty ? L10n.tr("Next in Queue") : L10n.tr("Previous"))
    clearButton.isHidden = !hasUpNext

    rows = newRows
    tableView.reloadData()
    emptyLabel.isHidden = !rows.isEmpty
    scrollView.isHidden = rows.isEmpty
  }

  @objc
  private func clearQueuePressed() {
    player.clearUserQueue()
    player.clearContextQueue()
    reload()
  }

  @objc
  private func rowClicked() {
    let row = tableView.clickedRow
    guard row >= 0, row < rows.count, case .track(_, let playerIndex) = rows[row] else {
      return
    }
    player.play(playerIndex: playerIndex)
  }

  private func showRowMenu(for row: Int, relativeTo anchor: NSView) {
    guard row >= 0, row < rows.count, case .track(_, let playerIndex) = rows[row] else {
      return
    }
    let menu = NSMenu()
    let playItem = NSMenuItem(title: L10n.tr("Play"), action: #selector(menuPlayRow(_:)), keyEquivalent: "")
    playItem.target = self
    playItem.tag = row
    menu.addItem(playItem)
    if playerIndex.queueType != .prev {
      let removeItem = NSMenuItem(title: L10n.tr("Remove"), action: #selector(menuRemoveRow(_:)), keyEquivalent: "")
      removeItem.target = self
      removeItem.tag = row
      menu.addItem(removeItem)
    }
    menu.popUp(positioning: nil, at: NSPoint(x: anchor.bounds.midX, y: anchor.bounds.minY - 4), in: anchor)
  }

  @objc
  private func menuPlayRow(_ sender: NSMenuItem) {
    let row = sender.tag
    guard row >= 0, row < rows.count, case .track(_, let playerIndex) = rows[row] else { return }
    player.play(playerIndex: playerIndex)
  }

  @objc
  private func menuRemoveRow(_ sender: NSMenuItem) {
    let row = sender.tag
    guard row >= 0, row < rows.count, case .track(_, let playerIndex) = rows[row] else { return }
    player.removePlayable(at: playerIndex)
    reload()
  }

  // MARK: - NSTableViewDataSource & Delegate

  func numberOfRows(in tableView: NSTableView) -> Int {
    rows.count
  }

  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    guard row < rows.count else { return 56 }
    if case .sectionHeader = rows[row] { return 34 }
    return 56
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard row < rows.count else { return nil }
    switch rows[row] {
    case .sectionHeader(let title):
      let cell = tableView.makeView(withIdentifier: headerCellID, owner: self) as? NSTableCellView
        ?? {
          let view = NSTableCellView()
          let label = NSTextField(labelWithString: "")
          label.font = .systemFont(ofSize: 13, weight: .semibold)
          label.textColor = NSColor.white.withAlphaComponent(0.70)
          label.translatesAutoresizingMaskIntoConstraints = false
          view.addSubview(label)
          view.textField = label
          NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4),
          ])
          return view
        }()
      cell.identifier = headerCellID
      cell.textField?.stringValue = title
      return cell

    case .track(let playable, _):
      let cell = tableView.makeView(withIdentifier: trackCellID, owner: self) as? NowPlayingQueueRowView
        ?? NowPlayingQueueRowView()
      cell.identifier = trackCellID
      let setting = storage.settings.accounts.activeSetting.read
      let artwork = ArtworkImageLoader.image(
        for: playable,
        themePreference: setting.themePreference,
        artworkDisplayPreference: setting.artworkDisplayPreference,
        maxPixelSize: 120
      )
      let albumName = playable.asSong?.album?.name ?? ""
      let subtitle = albumName.isEmpty
        ? playable.creatorName
        : "\(playable.creatorName) — \(albumName)"
      cell.configure(artwork: artwork, title: playable.title, subtitle: subtitle)
      cell.onMore = { [weak self] anchor in
        self?.showRowMenu(for: row, relativeTo: anchor)
      }
      return cell
    }
  }

  // MARK: - MusicPlayable

  func didStartPlayingFromBeginning() { reload() }
  func didStartPlaying() { reload() }
  func didPause() {}
  func didStopPlaying() { reload() }
  func didElapsedTimeChange() {}
  func didLyricsTimeChange(time: CMTime) {}
  func didPlaylistChange() { reload() }
  func didArtworkChange() { reload() }
  func didNowPlayingInfoChange() { reload() }
  func didShuffleChange() { reload() }
  func didRepeatChange() {}
  func didPlaybackRateChange() {}
}

// MARK: - NowPlayingQueueRowView

@MainActor
private final class NowPlayingQueueRowView: NSTableCellView {
  var onMore: ((NSView) -> Void)?

  private let artworkView = NSImageView()
  private let titleLabel = NSTextField(labelWithString: "")
  private let subtitleLabel = NSTextField(labelWithString: "")
  private let moreButton = NSButton()
  private let divider = NSView()
  private var isHovered = false

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = 8

    artworkView.imageScaling = .scaleProportionallyUpOrDown
    artworkView.wantsLayer = true
    artworkView.layer?.cornerRadius = 6
    artworkView.layer?.masksToBounds = true
    artworkView.translatesAutoresizingMaskIntoConstraints = false

    titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
    titleLabel.textColor = .white
    titleLabel.lineBreakMode = .byTruncatingTail
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
    subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.62)
    subtitleLabel.lineBreakMode = .byTruncatingTail
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

    moreButton.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)?
      .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .medium))
    moreButton.isBordered = false
    moreButton.bezelStyle = .regularSquare
    moreButton.imagePosition = .imageOnly
    moreButton.contentTintColor = NSColor.white.withAlphaComponent(0.65)
    moreButton.target = self
    moreButton.action = #selector(morePressed)
    moreButton.translatesAutoresizingMaskIntoConstraints = false

    divider.wantsLayer = true
    divider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
    divider.translatesAutoresizingMaskIntoConstraints = false

    addSubview(artworkView)
    addSubview(titleLabel)
    addSubview(subtitleLabel)
    addSubview(moreButton)
    addSubview(divider)

    NSLayoutConstraint.activate([
      artworkView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
      artworkView.centerYAnchor.constraint(equalTo: centerYAnchor),
      artworkView.widthAnchor.constraint(equalToConstant: 40),
      artworkView.heightAnchor.constraint(equalToConstant: 40),

      titleLabel.leadingAnchor.constraint(equalTo: artworkView.trailingAnchor, constant: 12),
      titleLabel.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor, constant: -8),
      titleLabel.bottomAnchor.constraint(equalTo: centerYAnchor, constant: -1),

      subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
      subtitleLabel.topAnchor.constraint(equalTo: centerYAnchor, constant: 2),

      moreButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
      moreButton.centerYAnchor.constraint(equalTo: centerYAnchor),
      moreButton.widthAnchor.constraint(equalToConstant: 26),
      moreButton.heightAnchor.constraint(equalToConstant: 26),

      divider.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      divider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
      divider.bottomAnchor.constraint(equalTo: bottomAnchor),
      divider.heightAnchor.constraint(equalToConstant: 0.5),
    ])
  }

  required init?(coder: NSCoder) {
    nil
  }

  func configure(artwork: NSImage?, title: String, subtitle: String) {
    artworkView.image = artwork
    titleLabel.stringValue = title
    subtitleLabel.stringValue = subtitle
  }

  @objc
  private func morePressed() {
    onMore?(moreButton)
  }

  private static weak var activeHoveredRow: NowPlayingQueueRowView?

  private func setHovered(_ hovered: Bool) {
    if hovered {
      if let previous = Self.activeHoveredRow, previous !== self {
        previous.setHovered(false)
      }
      Self.activeHoveredRow = self
    } else if Self.activeHoveredRow === self {
      Self.activeHoveredRow = nil
    }
    guard isHovered != hovered else { return }
    isHovered = hovered
    layer?.backgroundColor = hovered
      ? NSColor.white.withAlphaComponent(0.08).cgColor
      : NSColor.clear.cgColor
    moreButton.contentTintColor = hovered ? .white : NSColor.white.withAlphaComponent(0.65)
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    setHovered(false)
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window == nil {
      setHovered(false)
    }
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(NSTrackingArea(
      rect: .zero,
      options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited],
      owner: self,
      userInfo: nil
    ))
    if isHovered {
      guard let window, window.isKeyWindow else {
        setHovered(false)
        return
      }
      let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
      if !visibleRect.contains(point) {
        setHovered(false)
      }
    }
  }

  override func mouseEntered(with event: NSEvent) {
    setHovered(true)
  }

  override func mouseExited(with event: NSEvent) {
    setHovered(false)
  }
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
