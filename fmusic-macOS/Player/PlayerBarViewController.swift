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

  private let volumeOverlayPill = VolumeOverlayPillView()
  private var volumeOverlayWidthConstraint: NSLayoutConstraint?
  private var isVolumeExpanded = false
  private var lastNonZeroVolume: Float = 0.5
  nonisolated(unsafe) private var volumeOutsideMonitor: Any?

  /// Called when the user toggles the lyrics side pane.
  var onToggleLyricsPane: (() -> Void)?

  /// Called when the user toggles the queue side pane.
  var onToggleQueuePane: (() -> Void)?

  /// Whether the lyrics pane is currently visible (drives the toggle highlight).
  var isLyricsPaneVisible = false {
    didSet { updateLyricsButton() }
  }

  /// Whether the queue pane is currently visible (drives the toggle highlight).
  var isQueuePaneVisible = false {
    didSet { updateQueueButton() }
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

    volumeOverlayPill.translatesAutoresizingMaskIntoConstraints = false
    volumeOverlayPill.isHidden = true
    volumeOverlayPill.alphaValue = 0
    volumeOverlayPill.onVolumeChange = { [weak self] value in
      self?.applyVolume(value)
    }
    volumeOverlayPill.onSpeakerClick = { [weak self] in
      self?.toggleMute()
    }
    capsule.addSubview(volumeOverlayPill, positioned: .above, relativeTo: nil)
    let volumeWidth = volumeOverlayPill.widthAnchor.constraint(equalToConstant: 44)
    volumeOverlayWidthConstraint = volumeWidth
    NSLayoutConstraint.activate([
      volumeOverlayPill.trailingAnchor.constraint(equalTo: capsule.trailingAnchor, constant: -6),
      volumeOverlayPill.centerYAnchor.constraint(equalTo: capsule.centerYAnchor),
      volumeWidth,
      volumeOverlayPill.heightAnchor.constraint(equalToConstant: 44),
    ])

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
    collapseVolumeOverlay(animated: false)
    PlaybackClock.shared.unsubscribe(clockToken)
    clockToken = nil
  }

  deinit {
    if let volumeOutsideMonitor {
      NSEvent.removeMonitor(volumeOutsideMonitor)
    }
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

    volumeIcon.image = symbolImage(Self.volumeSymbolName(for: player.volume), size: 14)
    volumeIcon.isBordered = false
    volumeIcon.bezelStyle = .regularSquare
    volumeIcon.imagePosition = .imageOnly
    volumeIcon.contentTintColor = .labelColor
    volumeIcon.target = self
    volumeIcon.action = #selector(volumeIconPressed)
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
    updateQueueButton()
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
        artworkDisplayPreference: setting.artworkDisplayPreference,
        maxPixelSize: 160
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
    syncVolumeUI(player.volume)
  }

  private func updateLyricsButton() {
    // Catalyst keeps every normal utility icon at .label; only the active
    // toggles use the accent tint.
    lyricsButton.contentTintColor = isLyricsPaneVisible
      ? MacTheme.accentColor
      : .labelColor
  }

  private func updateQueueButton() {
    queueButton.contentTintColor = isQueuePaneVisible
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
    updateQueueButton()
    progressFill.layer?.backgroundColor = MacTheme.accentColor.cgColor
  }

  @objc
  private func playbackSettingsChanged() {
    syncVolumeUI(FmusicKit.shared.storage.settings.user.playerVolume)
  }

  private static func volumeSymbolName(for volume: Float) -> String {
    if volume <= 0.001 { return "speaker.slash.fill" }
    if volume < 0.34 { return "speaker.wave.1.fill" }
    if volume < 0.67 { return "speaker.wave.2.fill" }
    return "speaker.wave.3.fill"
  }

  private func syncVolumeUI(_ volume: Float) {
    let clamped = min(max(volume, 0), 1)
    if clamped > 0.01 {
      lastNonZeroVolume = clamped
    }
    volumeSlider.doubleValue = Double(clamped)
    volumeIcon.image = symbolImage(Self.volumeSymbolName(for: clamped), size: 14)
    volumeOverlayPill.setVolume(clamped)
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
    onToggleLyricsPane?()
  }

  @objc
  private func showQueue() {
    onToggleQueuePane?()
  }

  @objc
  private func showMoreMenu() {
    let audioOutputEntry = makeAudioOutputMenuEntry()
    var entries: [PlayerMoreMenuPanel.Entry] = []

    if let song = player.currentlyPlaying?.asSong {
      let playlistOptions = entityActions.addToPlaylistOptions(for: song)
      let playlistEntry: PlayerMoreMenuPanel.Entry = playlistOptions.isEmpty
        ? .item(L10n.tr("Add to Playlist"), symbol: "text.badge.plus", enabled: false) {}
        : .submenu(L10n.tr("Add to Playlist"), symbol: "text.badge.plus", options: playlistOptions)

      entries.append(contentsOf: [
        // Group 1: Song actions
        .item(
          song.isFavorite ? L10n.tr("Unmark favorite") : L10n.tr("Favorite"),
          symbol: song.isFavorite ? "heart.fill" : "heart",
          iconTint: song.isFavorite ? MacTheme.accentColor : nil
        ) { [weak self] in
          self?.entityActions.toggleFavorite()
        },
        playlistEntry,
        .item(L10n.tr("Instant Mix"), symbol: "sparkles") { [weak self] in
          self?.entityActions.instantMix()
        },
        .separator,
        // Group 2: Navigation
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
        .separator,
        // Group 3: Lyrics & Audio Output
        .item(
          L10n.tr("Desktop Lyrics"),
          symbol: "text.bubble",
          isChecked: storage.settings.user.isDesktopLyricsEnabled
        ) { [weak self] in
          self?.entityActions.toggleDesktopLyrics()
        },
        .item(L10n.tr("Match Online Lyrics"), symbol: "magnifyingglass") { [weak self] in
          self?.entityActions.matchOnlineLyrics()
        },
        audioOutputEntry,
        .separator,
        // Group 4: File & sharing
        .item(
          L10n.tr("Download"),
          symbol: "arrow.down.circle",
          enabled: entityActions.canDownload(song)
        ) { [weak self] in
          self?.entityActions.download(song)
        },
        .item(L10n.tr("Share"), symbol: "square.and.arrow.up") { [weak self] in
          guard let self else { return }
          self.entityActions.share(song, relativeTo: self.moreButton)
        },
      ])
    } else {
      entries = [
        .item(
          L10n.tr("Desktop Lyrics"),
          symbol: "text.bubble",
          isChecked: storage.settings.user.isDesktopLyricsEnabled
        ) { [weak self] in
          self?.entityActions.toggleDesktopLyrics()
        },
        audioOutputEntry,
      ]
    }

    let panel = PlayerMoreMenuPanel()
    playerMoreMenuPanel = panel
    panel.present(entries: entries, anchor: moreButton)
  }

  private func makeAudioOutputMenuEntry() -> PlayerMoreMenuPanel.Entry {
    let devices = AudioOutputDevices.outputDevices()
    let current = AudioOutputDevices.defaultOutputDevice()
    var items: [PlayerMoreMenuPanel.SubmenuOption] = devices.map { device in
      PlayerMoreMenuPanel.SubmenuOption(
        device.name,
        isChecked: device.id == current
      ) {
        AudioOutputDevices.setDefaultOutputDevice(device.id)
      }
    }
    if !items.isEmpty {
      items.append(.separator)
    }
    items.append(PlayerMoreMenuPanel.SubmenuOption(L10n.tr("Open System Sound Settings")) { [weak self] in
      self?.openSoundSettings()
    })
    return .submenu(L10n.tr("Audio Output"), symbol: "airplayaudio", items: items)
  }

  @objc
  private func volumeIconPressed() {
    if isVolumeExpanded {
      toggleMute()
    } else {
      expandVolumeOverlay()
    }
  }

  private func applyVolume(_ value: Float) {
    let clamped = min(max(value, 0), 1)
    FmusicKit.shared.player.volume = clamped
    syncVolumeUI(clamped)
  }

  private func toggleMute() {
    if player.volume > 0.001 {
      lastNonZeroVolume = player.volume
      applyVolume(0)
    } else {
      let restored = lastNonZeroVolume > 0.01 ? lastNonZeroVolume : 0.5
      applyVolume(restored)
    }
  }

  private func expandedVolumePillWidth() -> CGFloat {
    // Covers the 4 right-side utility buttons (more / lyrics / queue / volume)
    // with balanced concentric margins without encroaching on the track info.
    let rightWidth = rightGroupView?.frame.width ?? 134
    return max(144, round(rightWidth) + 22)
  }

  private func expandVolumeOverlay() {
    guard !isVolumeExpanded else { return }
    isVolumeExpanded = true
    syncVolumeUI(player.volume)
    let targetWidth = expandedVolumePillWidth()
    volumeOverlayPill.setExpandedWidth(targetWidth)
    volumeOverlayPill.isHidden = false
    installVolumeOutsideMonitor()

    if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      // Start as a 44×44 circle centered on the speaker icon, then grow leftwards.
      volumeOverlayWidthConstraint?.constant = 44
      volumeOverlayPill.alphaValue = 0
      volumeOverlayPill.setScrubBarAlpha(0)
      capsule.layoutSubtreeIfNeeded()

      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.28
        context.allowsImplicitAnimation = true
        context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
        volumeOverlayWidthConstraint?.animator().constant = targetWidth
        volumeOverlayPill.animator().alphaValue = 1
        volumeOverlayPill.animateScrubBarAlpha(to: 1)
        rightGroupView?.animator().alphaValue = 0
        capsule.layoutSubtreeIfNeeded()
      }
    } else {
      volumeOverlayWidthConstraint?.constant = targetWidth
      volumeOverlayPill.alphaValue = 1
      volumeOverlayPill.setScrubBarAlpha(1)
      rightGroupView?.alphaValue = 0
    }
  }

  private func collapseVolumeOverlay(animated: Bool) {
    removeVolumeOutsideMonitor()
    guard isVolumeExpanded else { return }
    isVolumeExpanded = false
    if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      NSAnimationContext.runAnimationGroup({ context in
        context.duration = 0.22
        context.allowsImplicitAnimation = true
        context.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.2, 1.0)
        volumeOverlayWidthConstraint?.animator().constant = 44
        volumeOverlayPill.animator().alphaValue = 0
        volumeOverlayPill.animateScrubBarAlpha(to: 0)
        rightGroupView?.animator().alphaValue = 1
        capsule.layoutSubtreeIfNeeded()
      }, completionHandler: { [weak self] in
        Task { @MainActor [weak self] in
          guard let self, !self.isVolumeExpanded else { return }
          self.volumeOverlayPill.isHidden = true
        }
      })
    } else {
      volumeOverlayWidthConstraint?.constant = 44
      volumeOverlayPill.alphaValue = 0
      volumeOverlayPill.setScrubBarAlpha(0)
      volumeOverlayPill.isHidden = true
      rightGroupView?.alphaValue = 1
    }
  }

  private func installVolumeOutsideMonitor() {
    removeVolumeOutsideMonitor()
    volumeOutsideMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown, .keyDown]
    ) { [weak self] event in
      guard let self, self.isVolumeExpanded else { return event }
      if event.type == .keyDown {
        if event.keyCode == 53 {
          self.collapseVolumeOverlay(animated: true)
          return nil
        }
        return event
      }
      let location = self.volumeOverlayPill.convert(event.locationInWindow, from: nil)
      if !self.volumeOverlayPill.bounds.contains(location) {
        self.collapseVolumeOverlay(animated: true)
      }
      return event
    }
  }

  private func removeVolumeOutsideMonitor() {
    if let volumeOutsideMonitor {
      NSEvent.removeMonitor(volumeOutsideMonitor)
      self.volumeOutsideMonitor = nil
    }
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

// MARK: - VolumeOverlayPillView

/// Apple Music macOS 26 style inline expanding volume pill: a crisp rounded
/// capsule overlaying the right side of the player bar with a thumb-less scrub
/// bar on the left and a dynamic mute/unmute speaker button on the right.
@MainActor
private final class VolumeOverlayPillView: NSView {
  var onVolumeChange: ((Float) -> Void)?
  var onSpeakerClick: (() -> Void)?

  private let backdropView = NSView()
  private let scrubBar = VolumeScrubBar()
  private let speakerButton = NSButton()
  private var scrubBarWidthConstraint: NSLayoutConstraint?
  private var currentVolume: Float = 0.5

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.masksToBounds = false
    layer?.shadowColor = NSColor.black.cgColor
    layer?.shadowOpacity = 0.12
    layer?.shadowRadius = 8
    layer?.shadowOffset = CGSize(width: 0, height: -1)

    backdropView.wantsLayer = true
    backdropView.layer?.cornerRadius = 22
    backdropView.layer?.cornerCurve = .continuous
    backdropView.layer?.masksToBounds = true
    backdropView.layer?.borderWidth = 0.5
    backdropView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(backdropView)

    scrubBar.translatesAutoresizingMaskIntoConstraints = false
    scrubBar.onScrub = { [weak self] value in
      self?.onVolumeChange?(value)
    }
    backdropView.addSubview(scrubBar)

    speakerButton.isBordered = false
    speakerButton.bezelStyle = .regularSquare
    speakerButton.imagePosition = .imageOnly
    speakerButton.contentTintColor = .labelColor
    speakerButton.target = self
    speakerButton.action = #selector(speakerPressed)
    speakerButton.toolTip = L10n.tr("Volume")
    speakerButton.translatesAutoresizingMaskIntoConstraints = false
    backdropView.addSubview(speakerButton)

    let scrubWidth = scrubBar.widthAnchor.constraint(equalToConstant: 91)
    scrubBarWidthConstraint = scrubWidth
    NSLayoutConstraint.activate([
      backdropView.topAnchor.constraint(equalTo: topAnchor),
      backdropView.leadingAnchor.constraint(equalTo: leadingAnchor),
      backdropView.trailingAnchor.constraint(equalTo: trailingAnchor),
      backdropView.bottomAnchor.constraint(equalTo: bottomAnchor),

      // Center aligns 1:1 with the collapsed volumeIcon inside the player bar.
      speakerButton.trailingAnchor.constraint(equalTo: backdropView.trailingAnchor, constant: -11),
      speakerButton.centerYAnchor.constraint(equalTo: backdropView.centerYAnchor),
      speakerButton.widthAnchor.constraint(equalToConstant: 28),
      speakerButton.heightAnchor.constraint(equalToConstant: 28),

      scrubBar.trailingAnchor.constraint(equalTo: speakerButton.leadingAnchor, constant: -10),
      scrubBar.centerYAnchor.constraint(equalTo: backdropView.centerYAnchor),
      scrubWidth,
      scrubBar.heightAnchor.constraint(equalToConstant: 24),
    ])

    applyAppearance()
    setVolume(currentVolume)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(appearanceDidChange),
      name: .macAppearanceChanged,
      object: nil
    )
  }

  required init?(coder: NSCoder) {
    nil
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  func setExpandedWidth(_ width: CGFloat) {
    // Reserve 16 pt left margin, 10 pt gap, 28 pt speaker, 11 pt right margin.
    scrubBarWidthConstraint?.constant = max(48, width - 65)
  }

  func setScrubBarAlpha(_ alpha: CGFloat) {
    scrubBar.alphaValue = alpha
  }

  func animateScrubBarAlpha(to alpha: CGFloat) {
    scrubBar.animator().alphaValue = alpha
  }

  func setVolume(_ volume: Float) {
    let clamped = min(max(volume, 0), 1)
    currentVolume = clamped
    scrubBar.value = CGFloat(clamped)
    let symbol: String
    if clamped <= 0.001 {
      symbol = "speaker.slash.fill"
    } else if clamped < 0.34 {
      symbol = "speaker.wave.1.fill"
    } else if clamped < 0.67 {
      symbol = "speaker.wave.2.fill"
    } else {
      symbol = "speaker.wave.3.fill"
    }
    speakerButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 15, weight: .medium))
  }

  @objc
  private func speakerPressed() {
    onSpeakerClick?()
  }

  @objc
  private func appearanceDidChange() {
    applyAppearance()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyAppearance()
  }

  override func layout() {
    super.layout()
    let radius = bounds.height / 2
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    backdropView.layer?.cornerRadius = radius
    layer?.shadowPath = CGPath(
      roundedRect: bounds,
      cornerWidth: radius,
      cornerHeight: radius,
      transform: nil
    )
    CATransaction.commit()
  }

  private func applyAppearance() {
    let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    backdropView.layer?.backgroundColor = isDark
      ? NSColor(white: 0.20, alpha: 0.96).cgColor
      : NSColor(white: 0.99, alpha: 0.96).cgColor
    backdropView.layer?.borderColor = isDark
      ? NSColor.white.withAlphaComponent(0.14).cgColor
      : NSColor.black.withAlphaComponent(0.08).cgColor
    layer?.shadowOpacity = isDark ? 0.32 : 0.12
    scrubBar.needsDisplay = true
  }
}

private final class VolumeScrubBar: NSView {
  var onScrub: ((Float) -> Void)?
  var value: CGFloat = 0.5 {
    didSet { needsDisplay = true }
  }

  private let barHeight: CGFloat = 8

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .pointingHand)
  }

  override func draw(_ dirtyRect: NSRect) {
    let y = (bounds.height - barHeight) / 2
    let trackRect = NSRect(x: 0, y: y, width: bounds.width, height: barHeight)
    let radius = barHeight / 2
    let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: radius, yRadius: radius)

    NSGraphicsContext.saveGraphicsState()
    trackPath.addClip()
    NSColor.labelColor.withAlphaComponent(0.18).setFill()
    trackRect.fill()

    let fillWidth = max(0, min(bounds.width, bounds.width * value))
    if fillWidth > 0.5 {
      let fillRect = NSRect(x: 0, y: y, width: fillWidth, height: barHeight)
      NSColor.labelColor.setFill()
      fillRect.fill()
    }
    NSGraphicsContext.restoreGraphicsState()
  }

  override func mouseDown(with event: NSEvent) {
    report(event)
    while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
      if next.type == .leftMouseDragged {
        report(next)
      } else {
        break
      }
    }
  }

  override func scrollWheel(with event: NSEvent) {
    let delta = Float(event.scrollingDeltaY) * 0.01
    guard abs(delta) > 0.0005 else { return }
    let next = min(max(Float(value) + delta, 0), 1)
    value = CGFloat(next)
    onScrub?(next)
  }

  private func report(_ event: NSEvent) {
    guard bounds.width > 0 else { return }
    let x = convert(event.locationInWindow, from: nil).x
    let fraction = min(max(Float(x / bounds.width), 0), 1)
    value = CGFloat(fraction)
    onScrub?(fraction)
  }
}
