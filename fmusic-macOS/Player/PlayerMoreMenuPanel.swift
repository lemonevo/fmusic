//
//  PlayerMoreMenuPanel.swift
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

/// Custom glass menu used by the player capsule's “more” button, anchored above the
/// button with grouped actions, subtle hairlines, and native hover/checkmark feedback.
@MainActor
final class PlayerMoreMenuPanel: NSObject {
  struct SubmenuOption {
    let title: String
    let isChecked: Bool
    let isSeparator: Bool
    let handler: (() -> Void)?

    init(_ title: String, isChecked: Bool = false, handler: @escaping () -> Void) {
      self.title = title
      self.isChecked = isChecked
      self.isSeparator = false
      self.handler = handler
    }

    private init(separator: Bool) {
      self.title = ""
      self.isChecked = false
      self.isSeparator = separator
      self.handler = nil
    }

    static var separator: SubmenuOption { SubmenuOption(separator: true) }
  }

  struct Entry {
    enum Kind {
      case item
      case separator
      case submenu
    }

    var kind: Kind
    var title: String = ""
    var symbol: String?
    var iconTint: NSColor?
    var isChecked: Bool = false
    var enabled: Bool = true
    var handler: (() -> Void)?
    var options: [SubmenuOption] = []

    static func item(
      _ title: String,
      symbol: String? = nil,
      iconTint: NSColor? = nil,
      isChecked: Bool = false,
      enabled: Bool = true,
      handler: @escaping () -> Void
    ) -> Entry {
      Entry(
        kind: .item,
        title: title,
        symbol: symbol,
        iconTint: iconTint,
        isChecked: isChecked,
        enabled: enabled,
        handler: handler
      )
    }

    static func submenu(
      _ title: String,
      symbol: String? = nil,
      enabled: Bool = true,
      options: [(String, () -> Void)]
    ) -> Entry {
      Entry(
        kind: .submenu,
        title: title,
        symbol: symbol,
        enabled: enabled,
        options: options.map { SubmenuOption($0.0, handler: $0.1) }
      )
    }

    static func submenu(
      _ title: String,
      symbol: String? = nil,
      enabled: Bool = true,
      items: [SubmenuOption]
    ) -> Entry {
      Entry(
        kind: .submenu,
        title: title,
        symbol: symbol,
        enabled: enabled,
        options: items
      )
    }

    static var separator: Entry { Entry(kind: .separator) }
  }

  private static let menuWidth: CGFloat = 232
  /// Transparent margin reserved for the glass-shadow layer; keeps the system
  /// window shadow from overriding the shared glass style.
  private static let shadowInset: CGFloat = 22
  private static var panelWidth: CGFloat { menuWidth + shadowInset * 2 }

  private let panel: NSPanel
  private weak var anchorView: NSView?
  private var outsideMonitor: Any?
  private var submenuHandlers: [() -> Void] = []

  override init() {
    panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: 200),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.isFloatingPanel = true
    panel.level = .popUpMenu
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = false
    panel.hidesOnDeactivate = true
    panel.isReleasedWhenClosed = false
    panel.collectionBehavior = [.transient, .canJoinAllSpaces, .ignoresCycle]
    super.init()
  }

  func present(entries: [Entry], anchor: NSView) {
    anchorView = anchor
    let stack = buildStack(entries: entries)

    let content = NSView()
    content.wantsLayer = true
    let shadow = GlassMenuShadowView()
    let background = GlassMenuBackgroundView()
    shadow.translatesAutoresizingMaskIntoConstraints = false
    background.translatesAutoresizingMaskIntoConstraints = false
    stack.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(shadow)
    content.addSubview(background)
    content.addSubview(stack)
    let inset = Self.shadowInset
    NSLayoutConstraint.activate([
      shadow.topAnchor.constraint(equalTo: content.topAnchor, constant: inset),
      shadow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: inset),
      shadow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -inset),
      shadow.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -inset),

      background.topAnchor.constraint(equalTo: content.topAnchor, constant: inset),
      background.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: inset),
      background.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -inset),
      background.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -inset),

      stack.topAnchor.constraint(equalTo: background.topAnchor, constant: 8),
      stack.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 6),
      stack.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -6),
      stack.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -8),
    ])
    content.frame = NSRect(x: 0, y: 0, width: Self.panelWidth, height: 200)
    panel.contentView = content
    content.layoutSubtreeIfNeeded()
    let contentHeight = max(100, stack.fittingSize.height + 16)
    let panelHeight = contentHeight + inset * 2
    panel.setContentSize(NSSize(width: Self.panelWidth, height: panelHeight))
    content.frame = NSRect(x: 0, y: 0, width: Self.panelWidth, height: panelHeight)

    position(above: anchor, size: NSSize(width: Self.panelWidth, height: panelHeight))
    installOutsideMonitor()
    panel.makeKeyAndOrderFront(nil)
  }

  func close() {
    if let outsideMonitor {
      NSEvent.removeMonitor(outsideMonitor)
      self.outsideMonitor = nil
    }
    submenuHandlers.removeAll()
    anchorView = nil
    panel.orderOut(nil)
  }

  // MARK: - Building

  private func buildStack(entries: [Entry]) -> NSStackView {
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .width
    stack.spacing = 2
    stack.translatesAutoresizingMaskIntoConstraints = false

    for entry in entries {
      switch entry.kind {
      case .separator:
        stack.addArrangedSubview(PlayerMenuSeparatorView())
      case .item, .submenu:
        let isSubmenu = entry.kind == .submenu
        let row = PlayerMenuRowView(
          title: entry.title,
          symbol: entry.symbol,
          iconTint: entry.iconTint,
          isChecked: entry.isChecked,
          showsSubmenuChevron: isSubmenu,
          enabled: entry.enabled
        ) { [weak self] rowView in
          guard let self else { return }
          if isSubmenu {
            self.showSubmenu(entry.options, from: rowView)
          } else {
            self.close()
            entry.handler?()
          }
        }
        stack.addArrangedSubview(row)
        row.heightAnchor.constraint(equalToConstant: 32).isActive = true
      }
    }
    return stack
  }

  private func showSubmenu(_ options: [SubmenuOption], from row: NSView) {
    guard !options.isEmpty else { return }
    submenuHandlers.removeAll()
    let menu = NSMenu()
    for option in options {
      if option.isSeparator {
        menu.addItem(.separator())
        continue
      }
      let item = NSMenuItem(
        title: option.title,
        action: option.handler != nil ? #selector(submenuChosen(_:)) : nil,
        keyEquivalent: ""
      )
      item.state = option.isChecked ? .on : .off
      if let handler = option.handler {
        item.target = self
        item.tag = submenuHandlers.count
        submenuHandlers.append(handler)
      } else {
        item.isEnabled = false
      }
      menu.addItem(item)
    }
    menu.popUp(
      positioning: nil,
      at: NSPoint(x: row.bounds.maxX - 4, y: row.bounds.midY),
      in: row
    )
  }

  @objc
  private func submenuChosen(_ sender: NSMenuItem) {
    guard submenuHandlers.indices.contains(sender.tag) else { return }
    let handler = submenuHandlers[sender.tag]
    close()
    handler()
  }

  // MARK: - Position and dismissal

  private func position(above anchor: NSView, size: NSSize) {
    guard let window = anchor.window else { return }
    let anchorInWindow = anchor.convert(anchor.bounds, to: nil)
    let anchorOnScreen = window.convertToScreen(anchorInWindow)
    var origin = NSPoint(
      x: anchorOnScreen.midX - size.width / 2,
      y: anchorOnScreen.maxY + 8 - Self.shadowInset
    )
    if let screen = window.screen ?? NSScreen.main {
      let visible = screen.visibleFrame
      origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
      if origin.y + size.height > visible.maxY - 8 {
        origin.y = visible.maxY - size.height - 8
      }
    }
    panel.setFrameOrigin(origin)
  }

  private func installOutsideMonitor() {
    if let outsideMonitor {
      NSEvent.removeMonitor(outsideMonitor)
      self.outsideMonitor = nil
    }
    outsideMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) {
      [weak self] event in
      guard let self else { return event }
      if event.type == .keyDown, event.keyCode == 53 {
        self.close()
        return nil
      }
      if event.type == .leftMouseDown, event.window !== self.panel {
        self.close()
      }
      return event
    }
  }
}

// MARK: - Glass shadow

@MainActor
private final class GlassMenuShadowView: NSView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = 14
    layer?.cornerCurve = .continuous
    layer?.masksToBounds = false
    apply(GlassStyleManager.configuration)
  }

  required init?(coder: NSCoder) {
    nil
  }

  private func apply(_ style: GlassStyleConfiguration) {
    layer?.shadowColor = NSColor.black.cgColor
    layer?.shadowOpacity = Float(min(style.shadowOpacity * 1.4, 0.36))
    layer?.shadowRadius = style.shadowRadius
    layer?.shadowOffset = style.shadowOffset
  }

  override func layout() {
    super.layout()
    layer?.shadowPath = CGPath(
      roundedRect: bounds,
      cornerWidth: 14,
      cornerHeight: 14,
      transform: nil
    )
  }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - Glass background

@MainActor
private final class GlassMenuBackgroundView: NSView {
  private let sheen = CAGradientLayer()
  private weak var effectView: NSView?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = 14
    layer?.cornerCurve = .continuous
    layer?.masksToBounds = true
    layer?.borderWidth = 0.5

    let effect: NSView
    if #available(macOS 26.0, *) {
      let glass = NSGlassEffectView()
      glass.cornerRadius = 14
      effect = glass
    } else {
      let visual = NSVisualEffectView()
      visual.material = .popover
      visual.blendingMode = .behindWindow
      visual.state = .active
      visual.wantsLayer = true
      visual.layer?.cornerRadius = 14
      visual.layer?.masksToBounds = true
      effect = visual
    }
    effectView = effect
    effect.translatesAutoresizingMaskIntoConstraints = false
    addSubview(effect)
    NSLayoutConstraint.activate([
      effect.topAnchor.constraint(equalTo: topAnchor),
      effect.leadingAnchor.constraint(equalTo: leadingAnchor),
      effect.trailingAnchor.constraint(equalTo: trailingAnchor),
      effect.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])

    sheen.locations = [0, 0.35, 1]
    sheen.startPoint = CGPoint(x: 0.5, y: 1)
    sheen.endPoint = CGPoint(x: 0.5, y: 0)
    layer?.addSublayer(sheen)

    apply(style: GlassStyleManager.configuration)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(glassStyleChanged),
      name: .macGlassStyleChanged,
      object: nil
    )
  }

  required init?(coder: NSCoder) {
    nil
  }

  deinit { NotificationCenter.default.removeObserver(self) }

  private func apply(style: GlassStyleConfiguration) {
    let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    layer?.borderColor = isDark
      ? NSColor.white.withAlphaComponent(min(style.borderAlpha * 0.55, 0.16)).cgColor
      : NSColor.black.withAlphaComponent(0.10).cgColor
    effectView?.alphaValue = style.glassAlpha
    if #available(macOS 26.0, *), let glass = effectView as? NSGlassEffectView {
      glass.style = style.material == .clear ? .clear : .regular
    }
    let sheenScale: CGFloat = isDark ? 0.35 : 0.75
    sheen.colors = [
      NSColor.white.withAlphaComponent(style.sheenTopAlpha * sheenScale).cgColor,
      NSColor.white.withAlphaComponent(style.sheenMidAlpha * sheenScale).cgColor,
      NSColor.clear.cgColor,
    ]
  }

  @objc private func glassStyleChanged() {
    apply(style: GlassStyleManager.configuration)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    apply(style: GlassStyleManager.configuration)
  }

  override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    sheen.frame = bounds
    CATransaction.commit()
  }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - Separator

@MainActor
private final class PlayerMenuSeparatorView: NSView {
  private let line = NSView()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    translatesAutoresizingMaskIntoConstraints = false
    heightAnchor.constraint(equalToConstant: 9).isActive = true

    line.wantsLayer = true
    line.translatesAutoresizingMaskIntoConstraints = false
    addSubview(line)
    NSLayoutConstraint.activate([
      line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      line.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
      line.centerYAnchor.constraint(equalTo: centerYAnchor),
      line.heightAnchor.constraint(equalToConstant: 0.5),
    ])
    updateColor()
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateColor()
  }

  private func updateColor() {
    let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    line.layer?.backgroundColor = (
      isDark ? NSColor.white.withAlphaComponent(0.11) : NSColor.black.withAlphaComponent(0.09)
    ).cgColor
  }
}

// MARK: - Row views

@MainActor
private final class PlayerMenuRowView: NSView {
  private let iconView = NSImageView()
  private let label = NSTextField(labelWithString: "")
  private let trailingAccessory = NSImageView()
  private let handler: ((NSView) -> Void)?
  private let customIconTint: NSColor?
  private let isEnabled: Bool
  private var isHovered = false

  init(
    title: String,
    symbol: String?,
    iconTint: NSColor?,
    isChecked: Bool,
    showsSubmenuChevron: Bool,
    enabled: Bool,
    handler: @escaping (NSView) -> Void
  ) {
    self.handler = handler
    self.customIconTint = iconTint
    self.isEnabled = enabled
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = 8
    layer?.cornerCurve = .continuous
    alphaValue = enabled ? 1 : 0.38

    iconView.image = symbol.flatMap {
      NSImage(systemSymbolName: $0, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 13.5, weight: .regular))
    }
    iconView.contentTintColor = customIconTint ?? .secondaryLabelColor
    iconView.imageScaling = .scaleProportionallyDown
    iconView.translatesAutoresizingMaskIntoConstraints = false

    label.stringValue = title
    label.font = .systemFont(ofSize: 13, weight: .regular)
    label.textColor = .labelColor
    label.lineBreakMode = .byTruncatingTail
    label.translatesAutoresizingMaskIntoConstraints = false

    trailingAccessory.imageScaling = .scaleProportionallyDown
    trailingAccessory.translatesAutoresizingMaskIntoConstraints = false
    if isChecked {
      trailingAccessory.image = NSImage(
        systemSymbolName: "checkmark",
        accessibilityDescription: nil
      )?.withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
      trailingAccessory.contentTintColor = MacTheme.accentColor
      trailingAccessory.isHidden = false
    } else if showsSubmenuChevron {
      trailingAccessory.image = NSImage(
        systemSymbolName: "chevron.right",
        accessibilityDescription: nil
      )?.withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
      trailingAccessory.contentTintColor = .tertiaryLabelColor
      trailingAccessory.isHidden = false
    } else {
      trailingAccessory.isHidden = true
    }

    addSubview(iconView)
    addSubview(label)
    addSubview(trailingAccessory)
    NSLayoutConstraint.activate([
      iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
      iconView.widthAnchor.constraint(equalToConstant: 16),
      iconView.heightAnchor.constraint(equalToConstant: 16),

      trailingAccessory.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
      trailingAccessory.centerYAnchor.constraint(equalTo: centerYAnchor),
      trailingAccessory.widthAnchor.constraint(equalToConstant: 14),
      trailingAccessory.heightAnchor.constraint(equalToConstant: 14),

      label.leadingAnchor.constraint(
        equalTo: symbol == nil ? leadingAnchor : iconView.trailingAnchor,
        constant: symbol == nil ? 10 : 10
      ),
      label.trailingAnchor.constraint(
        lessThanOrEqualTo: trailingAccessory.isHidden ? trailingAnchor : trailingAccessory.leadingAnchor,
        constant: trailingAccessory.isHidden ? -10 : -6
      ),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])

    let tracking = NSTrackingArea(
      rect: .zero,
      options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(tracking)
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func mouseEntered(with event: NSEvent) {
    guard isEnabled else { return }
    isHovered = true
    updateAppearance()
  }

  override func mouseExited(with event: NSEvent) {
    isHovered = false
    updateAppearance()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateAppearance()
  }

  private func updateAppearance() {
    let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    if isHovered && isEnabled {
      layer?.backgroundColor = (
        isDark ? NSColor.white.withAlphaComponent(0.09) : NSColor.black.withAlphaComponent(0.06)
      ).cgColor
      iconView.contentTintColor = customIconTint ?? .labelColor
    } else {
      layer?.backgroundColor = NSColor.clear.cgColor
      iconView.contentTintColor = customIconTint ?? .secondaryLabelColor
    }
  }

  override func mouseUp(with event: NSEvent) {
    guard isEnabled,
          bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
    handler?(self)
  }
}
