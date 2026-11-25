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

  private let progressTrack = SeekTrackView()
  private let progressFill = NSView()
  private let shuffleHighlight = NSView()
  private let repeatHighlight = NSView()
  private let glassSheen = GlassSheenView()
  private var progressFillWidth: NSLayoutConstraint?
  private var progressFraction: CGFloat = 0
  private var isSeekingProgress = false

  private var infoGroup: NSView?
  private weak var capsuleView: NSView?
  private var controlsGroupView: NSStackView?
  private var rightGroupView: NSStackView?
  private var compactMode: Bool?
  private var playerMoreMenuPanel: PlayerMoreMenuPanel?
  private weak var glassBackdropView: NSView?
  private let entityActions = PlayerEntityActions()

  /// Called when the user toggles the lyrics side pane.
  var onToggleLyricsPane: (() -> Void)?

  /// Whether the lyrics pane is currently visible (drives the toggle highlight).
  var isLyricsPaneVisible = false {
    didSet { updateLyricsButton() }
  }

  private var clockToken: UUID?
  private var isUpdatingProgress = false

  private var player: PlayerFacade { FmusicKit.shared.player }
  private var storage: PersistentStorage { FmusicKit.shared.storage }

  /// Catalyst `SplitVC.miniPlayerWidth/Height`: a fixed, centred 700 x 54 capsule.
  static let capsuleHeight: CGFloat = 54
  static let capsuleWidth: CGFloat = 700

  // MARK: - Lifecycle

  override func loadView() {
    let root = NSView()
    root.translatesAutoresizingMaskIntoConstraints = false
    root.wantsLayer = true

    // The Catalyst bar uses `UIGlassEffect` (Liquid Glass). AppKit's equivalent is
    // `NSGlassEffectView` on macOS 26; older systems fall back to vibrancy.
    // Keep the root unmasked so the outer shadow is not clipped; only the glass
    // backdrop view itself clips its own corners (Catalyst glassContainer).
    capsule.wantsLayer = true
    capsule.layer?.backgroundColor = NSColor.clear.cgColor
    capsule.layer?.masksToBounds = false
    capsule.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(capsule)

    let glassBackdrop: NSView
    if #available(macOS 26.0, *) {
      let glass = NSGlassEffectView()
      glass.style = .regular
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
    if glassBackdrop.layer == nil { glassBackdrop.wantsLayer = true }
    glassBackdrop.layer?.masksToBounds = true
    glassBackdrop.layer?.cornerRadius = Self.capsuleHeight / 2
    glassBackdrop.layer?.borderWidth = 0.5
    glassBackdropView = glassBackdrop
    capsule.addSubview(glassBackdrop)

    // Inner top highlight + imperceptible bottom bounce: this is what makes the
    // glass read as a curved, translucent surface instead of a flat grey bar.
    glassSheen.translatesAutoresizingMaskIntoConstraints = false
    capsule.addSubview(glassSheen)

    NSLayoutConstraint.activate([
      glassBackdrop.topAnchor.constraint(equalTo: capsule.topAnchor),
      glassBackdrop.leadingAnchor.constraint(equalTo: capsule.leadingAnchor),
      glassBackdrop.trailingAnchor.constraint(equalTo: capsule.trailingAnchor),
      glassBackdrop.bottomAnchor.constraint(equalTo: capsule.bottomAnchor),

      glassSheen.topAnchor.constraint(equalTo: capsule.topAnchor),
      glassSheen.leadingAnchor.constraint(equalTo: capsule.leadingAnchor),
      glassSheen.trailingAnchor.constraint(equalTo: capsule.trailingAnchor),
      glassSheen.bottomAnchor.constraint(equalTo: capsule.bottomAnchor),
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
    // Three-section bar: left transport cluster hugs left, middle flexes, right
    // utilities hug right. Stack views have no intrinsic width, so they need the
    // stack-specific hugging API — setContentHuggingPriority does not apply to them.
    controlsGroup.setHuggingPriority(.required, for: .horizontal)
    controlsGroup.setClippingResistancePriority(.required, for: .horizontal)
    controlsGroup.translatesAutoresizingMaskIntoConstraints = false

    let infoGroup = NSView()
    self.infoGroup = infoGroup
    let titleStack = infoStack()
    infoGroup.translatesAutoresizingMaskIntoConstraints = false
    titleStack.translatesAutoresizingMaskIntoConstraints = false
    infoGroup.addSubview(artworkView)
    infoGroup.addSubview(titleStack)
    NSLayoutConstraint.activate([
      artworkView.leadingAnchor.constraint(equalTo: infoGroup.leadingAnchor),
      artworkView.centerYAnchor.constraint(equalTo: infoGroup.centerYAnchor),
      titleStack.leadingAnchor.constraint(equalTo: artworkView.trailingAnchor, constant: 9),
      titleStack.trailingAnchor.constraint(equalTo: infoGroup.trailingAnchor),
      titleStack.centerYAnchor.constraint(equalTo: infoGroup.centerYAnchor),
    ])
    // Tapping the cover/title opens the large Now Playing page, like the Catalyst
    // mini player opening PopupPlayerVC. The labels and the image view are NSControls
    // that swallow the click, so a transparent button covers the whole info block
    // instead of a gesture recognizer on the container.
    let openNowPlaying = NSButton(title: "", target: self, action: #selector(openNowPlayingPage))
    openNowPlaying.isBordered = false
    openNowPlaying.translatesAutoresizingMaskIntoConstraints = false
    openNowPlaying.toolTip = L10n.tr("Now Playing")
    openNowPlaying.setAccessibilityLabel(L10n.tr("Now Playing"))
    infoGroup.addSubview(openNowPlaying)
    NSLayoutConstraint.activate([
      openNowPlaying.leadingAnchor.constraint(equalTo: infoGroup.leadingAnchor),
      openNowPlaying.trailingAnchor.constraint(equalTo: infoGroup.trailingAnchor),
      openNowPlaying.topAnchor.constraint(equalTo: infoGroup.topAnchor),
      openNowPlaying.bottomAnchor.constraint(equalTo: infoGroup.bottomAnchor),
    ])

    let rightGroup = NSStackView(views: [
      moreButton,
      lyricsButton,
      queueButton,
      outputButton,
      volumeIcon,
    ])
    rightGroup.orientation = .horizontal
    rightGroup.alignment = .centerY
    rightGroup.spacing = 12
    // A stack view has no intrinsic width, so the slack between the transport cluster
    // and this one would be handed to it and the icons would bunch at its leading edge,
    // leaving a long empty strip before the capsule's trailing edge. Stacks need the
    // stack-specific hugging API; setContentHuggingPriority is ignored for this.
    rightGroup.setHuggingPriority(.required, for: .horizontal)
    rightGroup.setClippingResistancePriority(.required, for: .horizontal)
    rightGroupView = rightGroup
    rightGroup.translatesAutoresizingMaskIntoConstraints = false

    let infoTrailing = infoGroup.trailingAnchor.constraint(
      equalTo: rightGroup.leadingAnchor,
      constant: -18
    )

    capsuleView = capsule
    capsule.addSubview(controlsGroup)
    capsule.addSubview(infoGroup)
    capsule.addSubview(rightGroup)

    // Catalyst draws the active shuffle/repeat fill as a circular tinted plate.
    // A dedicated view keeps it perfectly round; the NSButton's own layer is not
    // square because of its alignment-rect insets.
    for (highlight, button, size) in [
      (shuffleHighlight, shuffleButton, CGFloat(26)),
      (repeatHighlight, repeatButton, CGFloat(26)),
    ] {
      highlight.wantsLayer = true
      highlight.layer?.cornerRadius = size / 2
      highlight.layer?.backgroundColor = NSColor.clear.cgColor
      highlight.translatesAutoresizingMaskIntoConstraints = false
      capsule.addSubview(highlight, positioned: .below, relativeTo: controlsGroup)
      NSLayoutConstraint.activate([
        highlight.centerXAnchor.constraint(equalTo: button.centerXAnchor),
        highlight.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        highlight.widthAnchor.constraint(equalToConstant: size),
        highlight.heightAnchor.constraint(equalToConstant: size),
      ])
    }
    NSLayoutConstraint.activate([
      controlsGroup.leadingAnchor.constraint(equalTo: capsule.leadingAnchor, constant: 18),
      controlsGroup.centerYAnchor.constraint(equalTo: capsule.centerYAnchor, constant: -2),

      rightGroup.trailingAnchor.constraint(equalTo: capsule.trailingAnchor, constant: -18),
      rightGroup.centerYAnchor.constraint(equalTo: capsule.centerYAnchor, constant: -2),

      infoGroup.leadingAnchor.constraint(equalTo: controlsGroup.trailingAnchor, constant: 12),
      // The info block takes all the slack: the utility cluster hugs its content, so
      // this equality only stretches the info block and keeps the icons at the edge.
      infoTrailing,
      infoGroup.centerYAnchor.constraint(equalTo: capsule.centerYAnchor, constant: -7),
      // Give the info block a real hit area: without a height the transparent
      // "open Now Playing" button collapses to its intrinsic 2 pt.
      infoGroup.heightAnchor.constraint(equalToConstant: 40),
    ])

    NSLayoutConstraint.activate([
      capsule.topAnchor.constraint(equalTo: root.topAnchor),
      capsule.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      capsule.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      capsule.bottomAnchor.constraint(equalTo: root.bottomAnchor),
      capsule.heightAnchor.constraint(equalToConstant: Self.capsuleHeight),


    ])

    // The progress line runs directly under the artwork + title block.
    NSLayoutConstraint.activate([
      progressTrack.leadingAnchor.constraint(equalTo: infoGroup.leadingAnchor),
      progressTrack.trailingAnchor.constraint(equalTo: infoGroup.trailingAnchor),
    ])

    capsule.addSubview(progressTrack, positioned: .above, relativeTo: nil)
    applyGlassStyle()

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
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(glassStyleChanged),
      name: .macGlassStyleChanged,
      object: nil
    )

  }

  override func viewDidAppear() {
    super.viewDidAppear()
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
    titleLabel.alignment = .center
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    artistLabel.font = .systemFont(ofSize: 10.5)
    artistLabel.textColor = .secondaryLabelColor
    artistLabel.alignment = .center
    artistLabel.lineBreakMode = .byTruncatingTail
    artistLabel.translatesAutoresizingMaskIntoConstraints = false
    let stack = NSStackView(views: [titleLabel, artistLabel])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 0
    // Fill width so the title truncates instead of sizing the capsule.
    titleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    artistLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
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
      action: #selector(cycleRepeatMode),
      width: 26
    )
    playPauseButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
  }

  private func configureAccessibilityLabels() {
    shuffleButton.setAccessibilityLabel(L10n.tr("Shuffle"))
    previousButton.setAccessibilityLabel(L10n.tr("Previous"))
    nextButton.setAccessibilityLabel(L10n.tr("Next"))
    repeatButton.setAccessibilityLabel(L10n.tr("Repeat"))
    moreButton.setAccessibilityLabel(L10n.tr("More"))
    lyricsButton.setAccessibilityLabel(L10n.tr("Lyrics"))
    queueButton.setAccessibilityLabel(L10n.tr("Queue"))
    outputButton.setAccessibilityLabel(L10n.tr("Audio Output"))
    volumeIcon.setAccessibilityLabel(L10n.tr("Volume"))
    refreshPlaybackState()
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
    volumeIcon.contentTintColor = .labelColor
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
    // Clear hit area; SeekTrackView draws the 3 pt Catalyst line itself so a
    // 10 pt tall view stays easy to click without looking heavy.
    progressTrack.wantsLayer = true
    progressTrack.layer?.backgroundColor = NSColor.clear.cgColor
    progressTrack.translatesAutoresizingMaskIntoConstraints = false
    progressTrack.toolTip = L10n.tr("Seek")
    progressTrack.durationProvider = { [weak self] in
      self?.player.duration ?? 0
    }
    progressTrack.onScrub = { [weak self] fraction in
      self?.seek(to: fraction)
    }
    progressTrack.onStep = { [weak self] deltaSeconds in
      guard let self else { return }
      let duration = self.player.duration
      guard duration.isFinite, duration > 0 else { return }
      let target = min(max(self.player.elapsedTime + deltaSeconds, 0), duration)
      self.player.seek(toSecond: target)
      self.progressFraction = CGFloat(target / duration)
      self.updateProgressFill()
    }

    progressFill.wantsLayer = true
    progressFill.layer?.backgroundColor = MacTheme.accentColor.cgColor
    progressFill.layer?.cornerRadius = 4
    progressFill.translatesAutoresizingMaskIntoConstraints = false
    progressTrack.addSubview(progressFill)

    capsule.addSubview(progressTrack)
    NSLayoutConstraint.activate([
      progressTrack.bottomAnchor.constraint(equalTo: capsule.bottomAnchor),
      progressTrack.heightAnchor.constraint(equalToConstant: 14),

      progressFill.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
      progressFill.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
      progressFill.heightAnchor.constraint(equalToConstant: 8),
    ])
    let width = progressFill.widthAnchor.constraint(equalToConstant: 0)
    progressFillWidth = width
    width.isActive = true
  }

  private func configure(
    button: NSButton,
    symbol: String,
    size: CGFloat,
    action: Selector,
    width: CGFloat = 24
  ) {
    button.image = symbolImage(symbol, size: size)
    button.isBordered = false
    button.bezelStyle = .regularSquare
    button.imagePosition = .imageOnly
    button.target = self
    button.action = action
    button.contentTintColor = .labelColor
    button.translatesAutoresizingMaskIntoConstraints = false
    button.widthAnchor.constraint(equalToConstant: width).isActive = true
    button.heightAnchor.constraint(equalToConstant: 26).isActive = true
  }

  private func symbolImage(_ name: String, size: CGFloat) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: nil)?
      .withSymbolConfiguration(
        NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
      )
  }

  private func applyGlassStyle() {
    let style = GlassStyleManager.configuration
    if #available(macOS 26.0, *), let glass = glassBackdropView as? NSGlassEffectView {
      glass.style = style.material == .clear ? .clear : .regular
    }
    glassBackdropView?.alphaValue = style.glassAlpha
    glassBackdropView?.layer?.borderColor =
      NSColor.white.withAlphaComponent(style.borderAlpha).cgColor
    glassSheen.apply(style: style)
    if let layer = capsule.layer {
      layer.shadowColor = NSColor.black.cgColor
      layer.shadowOpacity = Float(style.shadowOpacity)
      layer.shadowRadius = style.shadowRadius
      layer.shadowOffset = style.shadowOffset
    }
  }

  @objc
  private func glassStyleChanged() {
    applyGlassStyle()
  }

  override func viewDidLayout() {
    super.viewDidLayout()
    // Apply the shadow once the view is in a window: assigning layer properties in
    // loadView can be a no-op because the backing layer is created later, which left
    // the capsule flat against the page (observed shadowOpacity = 0 at runtime).
    applyGlassStyle()
    if let layer = capsule.layer {
      layer.shadowPath = CGPath(
        roundedRect: capsule.bounds,
        cornerWidth: Self.capsuleHeight / 2,
        cornerHeight: Self.capsuleHeight / 2,
        transform: nil
      )
    }
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
    let setting = storage.settings.accounts.activeSetting.read
    let newImage: NSImage
    if let playable = player.currentlyPlaying {
      newImage = ArtworkImageLoader.image(
        for: playable,
        themePreference: setting.themePreference,
        artworkDisplayPreference: setting.artworkDisplayPreference
      )
    } else {
      newImage = ArtworkImageLoader.generatedImage(
        theme: setting.themePreference,
        artworkType: .song
      )
    }
    if artworkView.image !== newImage,
       !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
       let layer = artworkView.layer {
      let fade = CATransition()
      fade.type = .fade
      fade.duration = 0.22
      fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      layer.add(fade, forKey: "artworkCrossfade")
    }
    artworkView.image = newImage
  }

  private func refreshPlaybackState() {
    let symbol = player.isPlaying ? "pause.fill" : "play.fill"
    playPauseButton.image = symbolImage(symbol, size: 21)
    playPauseButton.setAccessibilityLabel(
      player.isPlaying ? L10n.tr("Pause") : L10n.tr("Play")
    )
  }

  private func updateModeButtons() {
    let accent = MacTheme.accentColor
    shuffleButton.contentTintColor = player.isShuffle ? accent : .secondaryLabelColor
    shuffleHighlight.layer?.backgroundColor = player.isShuffle
      ? accent.withAlphaComponent(0.16).cgColor
      : NSColor.clear.cgColor
    let repeatActive = player.repeatMode != .off
    repeatHighlight.layer?.backgroundColor = repeatActive
      ? accent.withAlphaComponent(0.16).cgColor
      : NSColor.clear.cgColor
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
    // Catalyst keeps every normal utility icon at .label; only the active
    // toggles use the accent tint.
    lyricsButton.contentTintColor = isLyricsPaneVisible
      ? MacTheme.accentColor
      : .labelColor
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
    progressTrack.currentFraction = progressFraction
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
  private func seek(to fraction: CGFloat) {
    let duration = player.duration
    guard duration.isFinite, duration > 0 else { return }
    player.seek(toSecond: Double(min(max(fraction, 0), 1)) * duration)
    progressFraction = fraction
    updateProgressFill()
  }

  @objc
  private func openNowPlayingPage() {
    AppDelegate.sharedAppDelegate?.showNowPlaying(nil)
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
    guard let song = player.currentlyPlaying?.asSong else { return }

    var entries: [PlayerMoreMenuPanel.Entry] = [
      .item(L10n.tr("Instant Mix"), symbol: "sparkles") { [weak self] in
        self?.entityActions.instantMix()
      },
      .separator,
      .item(
        L10n.tr("Show Album"),
        symbol: "square.stack",
        enabled: song.album != nil
      ) { [weak self] in
        self?.entityActions.showAlbum()
      },
      .item(
        L10n.tr("Show Artist"),
        symbol: "music.mic",
        enabled: song.artist != nil
      ) { [weak self] in
        self?.entityActions.showArtist()
      },
      .item(L10n.tr("Desktop Lyrics"), symbol: "text.bubble") { [weak self] in
        self?.entityActions.toggleDesktopLyrics()
      },
      .item(L10n.tr("Match Online Lyrics"), symbol: "magnifyingglass") { [weak self] in
        self?.entityActions.matchOnlineLyrics()
      },
      .separator,
      .item(
        song.isFavorite ? L10n.tr("Unmark favorite") : L10n.tr("Favorite"),
        symbol: "heart"
      ) { [weak self] in
        self?.entityActions.toggleFavorite()
      },
      .rating(song.rating) { [weak self] rating in
        self?.entityActions.setRating(rating)
      },
      .separator,
    ]

    let playlistOptions = entityActions.addToPlaylistOptions(for: song)
    if playlistOptions.isEmpty {
      entries.append(.item(
        L10n.tr("Add to Playlist"),
        symbol: "text.badge.plus",
        enabled: false
      ) {})
    } else {
      entries.append(.submenu(
        L10n.tr("Add to Playlist"),
        symbol: "text.badge.plus",
        options: playlistOptions
      ))
    }
    entries.append(.item(
      L10n.tr("Download"),
      symbol: "arrow.down.circle",
      enabled: entityActions.canDownload(song)
    ) { [weak self] in
      self?.entityActions.download(song)
    })
    entries.append(.item(L10n.tr("Share"), symbol: "square.and.arrow.up") { [weak self] in
      guard let self else { return }
      self.entityActions.share(song, relativeTo: self.moreButton)
    })

    let panel = PlayerMoreMenuPanel()
    playerMoreMenuPanel = panel
    panel.present(entries: entries, anchor: moreButton)
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

// MARK: - SeekTrackView

/// Click/drag seek bar matching the behaviour of the Catalyst `SeekableTimeSlider`.
/// Top-lit inner glow for the glass capsule. Decorative only; it must never
/// intercept the player controls underneath it.
private final class GlassSheenView: NSView {
  private let gradient = CAGradientLayer()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = PlayerBarViewController.capsuleHeight / 2
    layer?.masksToBounds = true
    gradient.locations = [0, 0.42, 0.72, 1]
    gradient.startPoint = CGPoint(x: 0.5, y: 1)
    gradient.endPoint = CGPoint(x: 0.5, y: 0)
    layer?.addSublayer(gradient)
    apply(style: GlassStyleManager.configuration)
  }

  required init?(coder: NSCoder) {
    nil
  }

  func apply(style: GlassStyleConfiguration) {
    gradient.colors = [
      NSColor.white.withAlphaComponent(style.sheenTopAlpha).cgColor,
      NSColor.white.withAlphaComponent(style.sheenMidAlpha).cgColor,
      NSColor.clear.cgColor,
      NSColor.white.withAlphaComponent(style.sheenMidAlpha * 0.5).cgColor,
    ]
  }

  override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer?.cornerRadius = bounds.height / 2
    gradient.frame = bounds
    CATransaction.commit()
  }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class SeekTrackView: NSView {
  var onScrub: ((CGFloat) -> Void)?
  var onStep: ((TimeInterval) -> Void)?
  var durationProvider: (() -> TimeInterval)?
  var currentFraction: CGFloat = 0

  private var isHovered = false
  private var isDragging = false

  override var acceptsFirstResponder: Bool { true }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(
      NSTrackingArea(
        rect: .zero,
        options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
        owner: self,
        userInfo: nil
      )
    )
  }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .pointingHand)
  }

  override func mouseEntered(with event: NSEvent) {
    isHovered = true
    updateHoverTooltip(for: event)
    needsDisplay = true
  }

  override func mouseMoved(with event: NSEvent) {
    updateHoverTooltip(for: event)
  }

  override func mouseExited(with event: NSEvent) {
    isHovered = false
    toolTip = L10n.tr("Seek")
    if !isDragging { needsDisplay = true }
  }

  override func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 123: // Left Arrow
      onStep?(-5)
    case 124: // Right Arrow
      onStep?(5)
    default:
      super.keyDown(with: event)
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    // 8 pt line; hover/drag slightly brightens the soft track.
    let bar = NSRect(x: 0, y: 0, width: bounds.width, height: 8)
    let alpha: CGFloat = isDragging ? 0.30 : (isHovered ? 0.24 : 0.18)
    NSColor.secondaryLabelColor.withAlphaComponent(alpha).setFill()
    NSBezierPath(roundedRect: bar, xRadius: 4, yRadius: 4).fill()
  }

  override func mouseDown(with event: NSEvent) {
    isDragging = true
    needsDisplay = true
    report(event)
    // Track the drag until mouse-up.
    while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
      if next.type == .leftMouseDragged {
        report(next)
      } else {
        break
      }
    }
    isDragging = false
    needsDisplay = true
  }

  private func report(_ event: NSEvent) {
    guard bounds.width > 0 else { return }
    let x = convert(event.locationInWindow, from: nil).x
    let fraction = min(max(x / bounds.width, 0), 1)
    updateHoverTooltip(for: event)
    onScrub?(fraction)
  }

  private func updateHoverTooltip(for event: NSEvent) {
    let duration = durationProvider?() ?? 0
    guard bounds.width > 0, duration.isFinite, duration > 0 else {
      toolTip = L10n.tr("Seek")
      return
    }
    let x = convert(event.locationInWindow, from: nil).x
    let fraction = min(max(x / bounds.width, 0), 1)
    let hovered = ClockTime(timeInSeconds: Int(Double(fraction) * duration)).asShortString()
    let total = ClockTime(timeInSeconds: Int(duration)).asShortString()
    toolTip = "\(hovered) / \(total)"
  }

  // MARK: - Accessibility

  override func isAccessibilityElement() -> Bool { true }

  override func accessibilityRole() -> NSAccessibility.Role? { .slider }

  override func accessibilityLabel() -> String? { L10n.tr("Seek") }

  override func accessibilityMinValue() -> Any? { 0.0 }

  override func accessibilityMaxValue() -> Any? {
    let duration = durationProvider?() ?? 0
    return duration.isFinite && duration > 0 ? duration : 0.0
  }

  override func accessibilityValue() -> Any? {
    let duration = durationProvider?() ?? 0
    guard duration.isFinite, duration > 0 else { return 0.0 }
    return Double(currentFraction) * duration
  }

  override func accessibilityPerformIncrement() -> Bool {
    onStep?(5)
    return true
  }

  override func accessibilityPerformDecrement() -> Bool {
    onStep?(-5)
    return true
  }
}
