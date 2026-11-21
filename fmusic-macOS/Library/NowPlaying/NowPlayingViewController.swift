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

  private let lyricsPane = LyricsPaneView()

  nonisolated(unsafe) private var progressTimer: Timer?
  private var isUpdatingProgress = false
  private var sleepTimer: Timer?

  private var player: PlayerFacade { FmusicKit.shared.player }
  private var storage: PersistentStorage { FmusicKit.shared.storage }

  // MARK: - Layout constants (scaled from the Catalyst large player)

  private let sideMargin: CGFloat = 92
  private let artworkSide: CGFloat = 350
  private let lyricsGap: CGFloat = 170

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
      closeButton.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),

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

    NSLayoutConstraint.activate([
      artworkView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: sideMargin),
      artworkView.topAnchor.constraint(equalTo: root.topAnchor, constant: 122),
      artworkView.widthAnchor.constraint(equalToConstant: artworkSide),
      artworkView.heightAnchor.constraint(equalToConstant: artworkSide),

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

      remainingLabel.trailingAnchor.constraint(equalTo: progressSlider.trailingAnchor),
      remainingLabel.topAnchor.constraint(equalTo: elapsedLabel.topAnchor),

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
    ])
  }

  private func buildLyricsColumn(in root: NSView) {
    lyricsPane.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(lyricsPane)
    NSLayoutConstraint.activate([
      lyricsPane.leadingAnchor.constraint(
        equalTo: artworkView.trailingAnchor,
        constant: lyricsGap
      ),
      lyricsPane.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -64),
      lyricsPane.topAnchor.constraint(equalTo: root.topAnchor, constant: 108),
      lyricsPane.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -80),
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

  @objc
  private func closePressed() {
    onClose?()
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
    guard let song = player.currentlyPlaying?.asSong else { return }
    song.isFavorite.toggle()
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

    let rating = NSMenuItem(title: L10n.tr("Rating"), action: nil, keyEquivalent: "")
    let ratingMenu = NSMenu()
    for stars in 0...5 {
      let item = NSMenuItem(
        title: stars == 0 ? L10n.tr("None") : String(repeating: "★", count: stars),
        action: #selector(setRating(_:)),
        keyEquivalent: ""
      )
      item.target = self
      item.tag = stars
      item.state = song.rating == stars ? .on : .off
      ratingMenu.addItem(item)
    }
    rating.submenu = ratingMenu
    menu.addItem(rating)
    menu.addItem(.separator())

    menu.addItem(disabledItem(L10n.tr("Add to Playlist")))
    menu.addItem(disabledItem(L10n.tr("Delete Cache")))
    menu.addItem(disabledItem(L10n.tr("Share")))

    menu.popUp(
      positioning: nil,
      at: NSPoint(x: optionsButton.bounds.midX, y: optionsButton.bounds.minY - 4),
      in: optionsButton
    )
  }

  @objc
  private func instantMix() {
    if let url = URL(string: "fmusic://x-callback-url/playRandomSongs") {
      NSWorkspace.shared.open(url)
    }
  }

  @objc
  private func showAlbumPage() {
    guard let album = player.currentlyPlaying?.asSong?.album else { return }
    (NSApp.delegate as? AppDelegate)?
      .mainWindowController?
      .mainViewController?
      .openAlbum(album)
  }

  @objc
  private func showArtistPage() {
    guard let artist = player.currentlyPlaying?.asSong?.artist else { return }
    (NSApp.delegate as? AppDelegate)?
      .mainWindowController?
      .mainViewController?
      .openArtist(artist)
  }

  @objc
  private func toggleDesktopLyrics() {
    AppDelegate.sharedAppDelegate?.toggleDesktopLyrics(nil)
  }

  @objc
  private func matchOnlineLyrics() {
    guard let song = player.currentlyPlaying?.asSong else { return }
    Task { @MainActor in
      _ = await OnlineLyricsService.shared.matchLyrics(for: song)
    }
  }

  @objc
  private func setRating(_ sender: NSMenuItem) {
    guard let song = player.currentlyPlaying?.asSong else { return }
    song.rating = sender.tag
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
    sleepTimer?.invalidate()
    sleepTimer = nil
    guard sender.tag > 0 else { return }
    sleepTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(sender.tag), repeats: false) { [weak self] _ in
      Task { @MainActor in
        FmusicKit.shared.player.pause()
        _ = self
      }
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

/// The Catalyst popup paints the artwork (blurred) behind a vertical gradient of
/// its dominant colours. This view reproduces that with a blurred artwork image
/// plus a dark gradient so the foreground stays legible.
@MainActor
private final class PlayerBlurredArtworkBackground: NSView {
  private let imageView = NSImageView()
  private let gradientView = NSView()
  private let gradientLayer = CAGradientLayer()
  private let context = CIContext(options: nil)
  private var currentArtwork: NSImage?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = NSColor.black.cgColor

    imageView.imageScaling = .scaleAxesIndependently
    imageView.wantsLayer = true
    imageView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(imageView)

    gradientView.wantsLayer = true
    gradientView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(gradientView)
    gradientLayer.startPoint = CGPoint(x: 0.5, y: 1)
    gradientLayer.endPoint = CGPoint(x: 0.5, y: 0)
    gradientLayer.colors = [
      NSColor.black.withAlphaComponent(0.55).cgColor,
      NSColor.black.withAlphaComponent(0.85).cgColor,
    ]
    gradientView.layer?.addSublayer(gradientLayer)

    NSLayoutConstraint.activate([
      imageView.topAnchor.constraint(equalTo: topAnchor),
      imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
      imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
      imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
      gradientView.topAnchor.constraint(equalTo: topAnchor),
      gradientView.leadingAnchor.constraint(equalTo: leadingAnchor),
      gradientView.trailingAnchor.constraint(equalTo: trailingAnchor),
      gradientView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    gradientLayer.frame = gradientView.bounds
    CATransaction.commit()
  }

  func apply(artwork: NSImage?, accent: NSColor) {
    guard artwork !== currentArtwork else { return }
    currentArtwork = artwork
    imageView.image = Self.blurred(artwork, context: context)
    // Catalyst uses the artwork's dominant colours for the gradient; take the
    // average colour and darken it towards the bottom.
    let base = Self.averageColor(of: artwork) ?? accent
    let dark = base.blended(withFraction: 0.55, of: .black) ?? base
    let deeper = base.blended(withFraction: 0.82, of: .black) ?? base
    gradientLayer.colors = [
      deeper.withAlphaComponent(0.92).cgColor,
      dark.withAlphaComponent(0.55).cgColor,
    ]
  }

  private static func averageColor(of image: NSImage?) -> NSColor? {
    guard let image,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let cgImage = bitmap.cgImage
    else { return nil }
    let input = CIImage(cgImage: cgImage)
    guard let filter = CIFilter(name: "CIAreaAverage") else { return nil }
    filter.setValue(input, forKey: kCIInputImageKey)
    filter.setValue(CIVector(cgRect: input.extent), forKey: kCIInputExtentKey)
    guard let output = filter.outputImage else { return nil }
    let context = CIContext(options: nil)
    var pixel = [UInt8](repeating: 0, count: 4)
    context.render(
      output,
      toBitmap: &pixel,
      rowBytes: 4,
      bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
      format: .RGBA8,
      colorSpace: nil
    )
    return NSColor(
      srgbRed: CGFloat(pixel[0]) / 255,
      green: CGFloat(pixel[1]) / 255,
      blue: CGFloat(pixel[2]) / 255,
      alpha: 1
    )
  }

  private static func blurred(_ image: NSImage?, context: CIContext) -> NSImage? {
    guard let image,
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else { return image }
    let ciImage = CIImage(cgImage: cgImage)
    guard let filter = CIFilter(name: "CIGaussianBlur") else { return image }
    filter.setValue(ciImage, forKey: kCIInputImageKey)
    filter.setValue(60, forKey: kCIInputRadiusKey)
    guard let output = filter.outputImage else { return image }
    let cropped = output.cropped(to: ciImage.extent)
    guard let rendered = context.createCGImage(cropped, from: ciImage.extent) else {
      return image
    }
    return NSImage(cgImage: rendered, size: image.size)
  }
}
