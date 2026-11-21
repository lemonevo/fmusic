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

/// Floating capsule player bar, styled after the Catalyst fmusic player control:
/// transport controls on the left, artwork + title/artist next to them, the utility
/// cluster (more / lyrics / queue / output / volume) on the right and a thin progress
/// line along the bottom edge of the capsule.
@MainActor
final class PlayerBarViewController: NSViewController, MusicPlayable {
  private let capsule = NSView()

  private let artworkView = NSImageView()
  private let titleLabel = NSTextField(labelWithString: L10n.tr("No music playing"))
  private let artistLabel = NSTextField(labelWithString: "")

  private let shuffleButton = NSButton()
  private let previousButton = NSButton()
  private let playPauseButton = NSButton()
  private let nextButton = NSButton()
  private let repeatButton = NSButton()

  private let lyricsButton = NSButton()
  private let queueButton = NSButton()
  private let moreButton = NSButton()
  private let outputButton = NSButton()
  private let volumeIcon = NSButton()
  private let volumeSlider = NSSlider()

  private let progressTrack = NSView()
  private let progressFill = NSView()
  private var progressFillWidth: NSLayoutConstraint?
  private var progressFraction: CGFloat = 0
  private var isSeekingProgress = false

  private var infoGroup: NSStackView?
  private var compactMode: Bool?

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
  static let capsuleHeight: CGFloat = 54

  // MARK: - Lifecycle

  override func loadView() {
    let root = NSView()
    root.translatesAutoresizingMaskIntoConstraints = false
    root.wantsLayer = true

    // The Catalyst bar uses `UIGlassEffect` (Liquid Glass). AppKit's equivalent is
    // `NSGlassEffectView` on macOS 26; older systems fall back to vibrancy.
    capsule.wantsLayer = true
    capsule.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(capsule)

    let glassBackdrop: NSView
    if #available(macOS 26.0, *) {
      let glass = NSGlassEffectView()
      glass.style = .regular
      // Slightly more see-through than the stock regular glass.
      glass.alphaValue = 0.85
      glass.cornerRadius = Self.capsuleHeight / 2
      glassBackdrop = glass
    } else {
      let effect = NSVisualEffectView()
      effect.material = .popover
      effect.blendingMode = .withinWindow
      effect.state = .active
      effect.wantsLayer = true
      effect.layer?.cornerRadius = Self.capsuleHeight / 2
      effect.layer?.masksToBounds = true
      glassBackdrop = effect
    }
    glassBackdrop.translatesAutoresizingMaskIntoConstraints = false
    capsule.addSubview(glassBackdrop)
    NSLayoutConstraint.activate([
      glassBackdrop.topAnchor.constraint(equalTo: capsule.topAnchor),
      glassBackdrop.leadingAnchor.constraint(equalTo: capsule.leadingAnchor),
      glassBackdrop.trailingAnchor.constraint(equalTo: capsule.trailingAnchor),
      glassBackdrop.bottomAnchor.constraint(equalTo: capsule.bottomAnchor),
    ])

    configureArtwork()
    configureTransportButtons()
    configureRightCluster()
    configureProgressLine()

    let controlsGroup = NSStackView(views: [
      shuffleButton,
      previousButton,
      playPauseButton,
      nextButton,
      repeatButton,
    ])
    controlsGroup.orientation = .horizontal
    controlsGroup.alignment = .centerY
    controlsGroup.spacing = 8
    controlsGroup.translatesAutoresizingMaskIntoConstraints = false

    let infoGroup = NSStackView(views: [artworkView, infoStack()])
    self.infoGroup = infoGroup
    // Tapping the cover/title opens the large Now Playing page, like the Catalyst
    // mini player opening PopupPlayerVC.
    let openNowPlaying = NSClickGestureRecognizer(
      target: self,
      action: #selector(openNowPlayingPage)
    )
    infoGroup.addGestureRecognizer(openNowPlaying)
    infoGroup.toolTip = L10n.tr("Now Playing")

    infoGroup.orientation = .horizontal
    infoGroup.alignment = .centerY
    infoGroup.spacing = 9
    infoGroup.translatesAutoresizingMaskIntoConstraints = false

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
    rightGroup.spacing = 12
    rightGroup.translatesAutoresizingMaskIntoConstraints = false

    capsule.addSubview(controlsGroup)
    capsule.addSubview(infoGroup)
    capsule.addSubview(rightGroup)

    NSLayoutConstraint.activate([
      capsule.topAnchor.constraint(equalTo: root.topAnchor),
      capsule.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      capsule.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      capsule.bottomAnchor.constraint(equalTo: root.bottomAnchor),
      capsule.heightAnchor.constraint(equalToConstant: Self.capsuleHeight),

      controlsGroup.leadingAnchor.constraint(equalTo: capsule.leadingAnchor, constant: 18),
      controlsGroup.centerYAnchor.constraint(
        equalTo: capsule.centerYAnchor,
        constant: -2
      ),

      infoGroup.leadingAnchor.constraint(equalTo: controlsGroup.trailingAnchor, constant: 12),
      infoGroup.centerYAnchor.constraint(equalTo: capsule.centerYAnchor, constant: -7),
      infoGroup.widthAnchor.constraint(lessThanOrEqualToConstant: 200),

      rightGroup.trailingAnchor.constraint(equalTo: capsule.trailingAnchor, constant: -18),
      rightGroup.centerYAnchor.constraint(equalTo: capsule.centerYAnchor, constant: -2),
      rightGroup.leadingAnchor.constraint(greaterThanOrEqualTo: infoGroup.trailingAnchor, constant: 12),
    ])

    // The progress line runs directly under the artwork + title block.
    NSLayoutConstraint.activate([
      progressTrack.leadingAnchor.constraint(equalTo: infoGroup.leadingAnchor),
      progressTrack.trailingAnchor.constraint(equalTo: infoGroup.trailingAnchor),
    ])

    capsule.addSubview(progressTrack, positioned: .above, relativeTo: nil)

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
    titleLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
    titleLabel.textColor = .labelColor
    titleLabel.lineBreakMode = .byTruncatingTail
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    artistLabel.font = .systemFont(ofSize: 10.5)
    artistLabel.textColor = .secondaryLabelColor
    artistLabel.lineBreakMode = .byTruncatingTail
    artistLabel.translatesAutoresizingMaskIntoConstraints = false
    let stack = NSStackView(views: [titleLabel, artistLabel])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 0
    return stack
  }

  private func configureTransportButtons() {
    configure(button: shuffleButton, symbol: "shuffle", size: 13, action: #selector(toggleShuffle))
    configure(button: previousButton, symbol: "backward.fill", size: 16, action: #selector(playPrevious))
    configure(
      button: playPauseButton,
      symbol: "play.fill",
      size: 20,
      action: #selector(togglePlayPause)
    )
    configure(button: nextButton, symbol: "forward.fill", size: 16, action: #selector(playNext))
    configure(
      button: repeatButton,
      symbol: "repeat",
      size: 13,
      action: #selector(cycleRepeatMode)
    )
    playPauseButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
  }

  private func configureRightCluster() {
    configure(
      button: moreButton,
      symbol: "ellipsis.circle",
      size: 15,
      action: #selector(showMoreMenu)
    )
    configure(
      button: lyricsButton,
      symbol: "quote.bubble",
      size: 15,
      action: #selector(toggleLyricsPane)
    )
    configure(button: queueButton, symbol: "list.bullet", size: 15, action: #selector(showQueue))
    configure(
      button: outputButton,
      symbol: "airplayaudio",
      size: 15,
      action: #selector(showOutputMenu)
    )

    volumeIcon.image = symbolImage("speaker.wave.2.fill", size: 14)
    volumeIcon.isBordered = false
    volumeIcon.bezelStyle = .regularSquare
    volumeIcon.imagePosition = .imageOnly
    volumeIcon.contentTintColor = .secondaryLabelColor
    volumeIcon.target = self
    volumeIcon.action = #selector(showVolumePopover)
    volumeIcon.toolTip = L10n.tr("Volume")
    volumeIcon.translatesAutoresizingMaskIntoConstraints = false
    volumeIcon.widthAnchor.constraint(equalToConstant: 26).isActive = true
    volumeIcon.heightAnchor.constraint(equalToConstant: 26).isActive = true

    volumeSlider.minValue = 0
    volumeSlider.maxValue = 1
    volumeSlider.doubleValue = Double(storage.settings.user.playerVolume)
    volumeSlider.isContinuous = true
    volumeSlider.controlSize = .small
    volumeSlider.target = self
    volumeSlider.action = #selector(changeVolume)
    volumeSlider.translatesAutoresizingMaskIntoConstraints = false
    volumeSlider.widthAnchor.constraint(equalToConstant: 56).isActive = true
  }

  private func configureProgressLine() {
    progressTrack.wantsLayer = true
    progressTrack.layer?.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.15).cgColor
    progressTrack.layer?.cornerRadius = 4
    progressTrack.translatesAutoresizingMaskIntoConstraints = false
    progressTrack.toolTip = L10n.tr("Seek")
    progressTrack.addGestureRecognizer(
      NSClickGestureRecognizer(target: self, action: #selector(progressLineClicked(_:)))
    )

    progressFill.wantsLayer = true
    progressFill.layer?.backgroundColor = MacTheme.accentColor.cgColor
    progressFill.layer?.cornerRadius = 4
    progressFill.translatesAutoresizingMaskIntoConstraints = false
    progressTrack.addSubview(progressFill)

    capsule.addSubview(progressTrack)
    NSLayoutConstraint.activate([
      progressTrack.bottomAnchor.constraint(equalTo: capsule.bottomAnchor, constant: -6),
      progressTrack.heightAnchor.constraint(equalToConstant: 8),

      progressFill.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
      progressFill.centerYAnchor.constraint(equalTo: progressTrack.centerYAnchor),
      progressFill.heightAnchor.constraint(equalToConstant: 8),
    ])
    let width = progressFill.widthAnchor.constraint(equalToConstant: 0)
    progressFillWidth = width
    width.isActive = true
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
    button.heightAnchor.constraint(equalToConstant: 26).isActive = true
  }

  private func symbolImage(_ name: String, size: CGFloat) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: nil)?
      .withSymbolConfiguration(
        NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
      )
  }

  override func viewDidLayout() {
    super.viewDidLayout()
    let width = view.bounds.width
    infoGroup?.isHidden = width < 470
    volumeSlider.isHidden = width < 640
    volumeIcon.isHidden = width < 380
    outputButton.isHidden = width < 430
    updateProgressFill()
    compactMode = width < 470
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
    playPauseButton.image = symbolImage(symbol, size: 21)
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

  private func updateProgress() {
    guard !isUpdatingProgress else { return }
    isUpdatingProgress = true
    defer { isUpdatingProgress = false }

    let duration = player.duration
    guard duration.isFinite, duration > 0 else {
      progressFraction = 0
      updateProgressFill()
      return
    }
    let elapsed = min(max(player.elapsedTime, 0), duration)
    progressFraction = CGFloat(elapsed / duration)
    updateProgressFill()
  }

  private func updateProgressFill() {
    guard let progressFillWidth else { return }
    let available = max(progressTrack.bounds.width, 0)
    progressFillWidth.constant = max(0, min(available, available * progressFraction))
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
    progressFill.layer?.backgroundColor = MacTheme.accentColor.cgColor
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
  private func progressLineClicked(_ recognizer: NSClickGestureRecognizer) {
    let location = recognizer.location(in: progressTrack)
    guard progressTrack.bounds.width > 0 else { return }
    let fraction = min(max(location.x / progressTrack.bounds.width, 0), 1)
    let duration = player.duration
    guard duration.isFinite, duration > 0 else { return }
    player.seek(toSecond: Double(fraction) * duration)
    progressFraction = fraction
    updateProgressFill()
  }

  @objc
  private func openNowPlayingPage() {
    PlayerPageWindowController.presentNowPlaying()
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

  private var volumePopover: NSPopover?

  @objc
  private func showVolumePopover() {
    if let popover = volumePopover, popover.isShown {
      popover.performClose(nil)
      return
    }
    let popover = NSPopover()
    popover.behavior = .transient
    let controller = NSViewController()
    let slider = NSSlider(value: Double(player.volume), minValue: 0, maxValue: 1, target: self, action: #selector(volumePopoverChanged(_:)))
    slider.controlSize = .small
    slider.isContinuous = true
    slider.translatesAutoresizingMaskIntoConstraints = false
    let container = NSView()
    container.addSubview(slider)
    NSLayoutConstraint.activate([
      container.widthAnchor.constraint(equalToConstant: 170),
      container.heightAnchor.constraint(equalToConstant: 44),
      slider.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
      slider.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
      slider.centerYAnchor.constraint(equalTo: container.centerYAnchor),
    ])
    controller.view = container
    popover.contentViewController = controller
    popover.show(relativeTo: volumeIcon.bounds, of: volumeIcon, preferredEdge: .maxY)
    volumePopover = popover
  }

  @objc
  private func volumePopoverChanged(_ sender: NSSlider) {
    FmusicKit.shared.player.volume = Float(sender.doubleValue)
    volumeSlider.doubleValue = sender.doubleValue
  }

  @objc
  private func showOutputMenu() {
    let menu = NSMenu()
    let devices = AudioOutputDevices.outputDevices()
    let current = AudioOutputDevices.defaultOutputDevice()
    if devices.isEmpty {
      let empty = NSMenuItem(title: L10n.tr("Audio Output"), action: nil, keyEquivalent: "")
      empty.isEnabled = false
      menu.addItem(empty)
    } else {
      for device in devices {
        let item = NSMenuItem(
          title: device.name,
          action: #selector(selectOutputDevice(_:)),
          keyEquivalent: ""
        )
        item.target = self
        item.representedObject = device.id
        item.state = device.id == current ? .on : .off
        menu.addItem(item)
      }
    }
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
      at: NSPoint(x: outputButton.bounds.midX, y: outputButton.bounds.minY - 4),
      in: outputButton
    )
  }

  @objc
  private func selectOutputDevice(_ sender: NSMenuItem) {
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
