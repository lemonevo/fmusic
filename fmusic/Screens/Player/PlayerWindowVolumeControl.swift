//
//  PlayerWindowVolumeControl.swift
//  fmusic
//
//  Apple Music keeps the volume slider in the window title bar row, right-aligned.
//  Mac Catalyst exposes the native title bar through UITitlebar; NSToolbarItem can
//  host a UIBarButtonItem whose customView is a regular UIKit view, so the same
//  blurred capsule used in the player can live in the title bar.
//

import fmusicKit
import UIKit

#if targetEnvironment(macCatalyst)
  import AppKit

  @MainActor
  final class PlayerWindowVolumeControl: NSObject, NSToolbarDelegate {
    private static let volumeItemIdentifier = NSToolbarItem.Identifier("PlayerVolume")
    private static let toolbarIdentifier = NSToolbar.Identifier("PlayerVolumeToolbar")

    // PlayerFacade is not class-bound, so it cannot be held weakly; the player is owned by
    // the app delegate and outlives this control.
    private var player: PlayerFacade?
    private weak var scene: UIWindowScene?
    private let toolbar = NSToolbar(identifier: toolbarIdentifier)
    private let container = UIView()
    private let slider = VolumeSlider()
    private var savedTitleVisibility: UITitlebarTitleVisibility?
    private var savedSeparatorStyle: UITitlebarSeparatorStyle?
    private var savedToolbarStyle: UITitlebarToolbarStyle?

    private(set) var isAttached = false

    init(player: PlayerFacade) {
      self.player = player
      super.init()
      toolbar.delegate = self
      toolbar.displayMode = .iconOnly
      toolbar.allowsUserCustomization = false
      toolbar.autosavesConfiguration = false
      configureVolumeView()
    }

    private func configureVolumeView() {
      container.layer.cornerRadius = 14
      container.layer.cornerCurve = .continuous
      container.backgroundColor = UIColor.white.withAlphaComponent(0.12)
      container.layer.borderWidth = 1.0 / UIScreen.main.scale
      container.layer.borderColor = UIColor.white.withAlphaComponent(0.22).cgColor
      container.translatesAutoresizingMaskIntoConstraints = false

      let icon = UIImageView(
        image: UIImage(
          systemName: "speaker.wave.2.fill",
          withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        )
      )
      icon.tintColor = .white
      icon.setContentHuggingPriority(.required, for: .horizontal)
      icon.setContentCompressionResistancePriority(.required, for: .horizontal)

      slider.contentColor = .white
      slider.value = player?.volume ?? 1
      slider.accessibilityLabel = L10n.tr("Volume")
      slider.addTarget(self, action: #selector(volumeChanged(_:)), for: .valueChanged)

      let stack = UIStackView(arrangedSubviews: [slider, icon])
      stack.axis = .horizontal
      stack.spacing = 7
      stack.alignment = .center
      stack.translatesAutoresizingMaskIntoConstraints = false
      container.addSubview(stack)
      NSLayoutConstraint.activate([
        container.widthAnchor.constraint(equalToConstant: 180),
        container.heightAnchor.constraint(equalToConstant: 28),
        stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
        stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -9),
        stack.topAnchor.constraint(equalTo: container.topAnchor),
        stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      ])
    }

    /// Installs the volume item into the window title bar.
    func attach(to scene: UIWindowScene?) {
      guard let scene, let titlebar = scene.titlebar, !isAttached else { return }
      self.scene = scene
      savedTitleVisibility = titlebar.titleVisibility
      savedSeparatorStyle = titlebar.separatorStyle
      savedToolbarStyle = titlebar.toolbarStyle
      titlebar.titleVisibility = .hidden
      titlebar.separatorStyle = .none
      titlebar.toolbarStyle = .unifiedCompact
      titlebar.toolbar = toolbar
      isAttached = true
      syncFromPlayer()
    }

    func detach() {
      defer {
        isAttached = false
        scene = nil
      }
      guard isAttached, let titlebar = scene?.titlebar else { return }
      titlebar.toolbar = nil
      if let savedTitleVisibility { titlebar.titleVisibility = savedTitleVisibility }
      if let savedSeparatorStyle { titlebar.separatorStyle = savedSeparatorStyle }
      if let savedToolbarStyle { titlebar.toolbarStyle = savedToolbarStyle }
      savedTitleVisibility = nil
      savedSeparatorStyle = nil
      savedToolbarStyle = nil
    }

    func syncFromPlayer() {
      guard let player else { return }
      slider.value = player.volume
    }

    @objc
    private func volumeChanged(_ sender: VolumeSlider) {
      player?.volume = sender.value
    }

    // MARK: - NSToolbarDelegate

    func toolbar(
      _ toolbar: NSToolbar,
      itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
      willBeInsertedIntoToolbar flag: Bool
    )
      -> NSToolbarItem? {
      guard itemIdentifier == Self.volumeItemIdentifier else { return nil }
      let barButton = UIBarButtonItem(customView: container)
      let item = NSToolbarItem(itemIdentifier: itemIdentifier, barButtonItem: barButton)
      item.label = L10n.tr("Volume")
      item.paletteLabel = L10n.tr("Volume")
      item.toolTip = L10n.tr("Volume")
      return item
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
      [.flexibleSpace, Self.volumeItemIdentifier]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
      [.flexibleSpace, Self.volumeItemIdentifier]
    }
  }
#endif
