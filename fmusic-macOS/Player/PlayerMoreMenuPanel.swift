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

/// Custom glass menu used by the player capsule's “more” button. It mirrors the
/// Catalyst entity menu (grouped actions, inline rating) and is anchored above the
/// button, never below it.
@MainActor
final class PlayerMoreMenuPanel: NSObject {
  struct Entry {
    enum Kind {
      case item
      case separator
      case submenu
      case rating
    }

    var kind: Kind
    var title: String = ""
    var symbol: String?
    var enabled: Bool = true
    var handler: (() -> Void)?
    var options: [(String, () -> Void)] = []
    var rating: Int = 0
    var onRate: ((Int) -> Void)?

    static func item(
      _ title: String,
      symbol: String? = nil,
      enabled: Bool = true,
      handler: @escaping () -> Void
    ) -> Entry {
      Entry(kind: .item, title: title, symbol: symbol, enabled: enabled, handler: handler)
    }

    static func submenu(
      _ title: String,
      symbol: String? = nil,
      options: [(String, () -> Void)]
    ) -> Entry {
      Entry(kind: .submenu, title: title, symbol: symbol, options: options)
    }

    static func rating(_ rating: Int, onRate: @escaping (Int) -> Void) -> Entry {
      Entry(kind: .rating, rating: rating, onRate: onRate)
    }

    static var separator: Entry { Entry(kind: .separator) }
  }

  private static let menuWidth: CGFloat = 224
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
      stack.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 8),
      stack.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -8),
      stack.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -8),
    ])
    content.frame = NSRect(x: 0, y: 0, width: Self.panelWidth, height: 200)
    panel.contentView = content
    content.layoutSubtreeIfNeeded()
    let contentHeight = max(120, stack.fittingSize.height + 16)
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
    stack.spacing = 0
    stack.translatesAutoresizingMaskIntoConstraints = false

    for entry in entries {
      switch entry.kind {
      case .separator:
        stack.addArrangedSubview(makeSeparator())
      case .rating:
        let row = PlayerMenuRatingView(rating: entry.rating) { [weak self] rating in
          guard let self else { return }
          self.close()
          entry.onRate?(rating)
        }
        stack.addArrangedSubview(row)
        row.heightAnchor.constraint(equalToConstant: 30).isActive = true
      case .item, .submenu:
        let row = PlayerMenuRowView(
          title: entry.title,
          symbol: entry.symbol,
          enabled: entry.enabled
        ) { [weak self] rowView in
          guard let self else { return }
          switch entry.kind {
          case .submenu:
            self.showSubmenu(entry.options, from: rowView)
          default:
            self.close()
            entry.handler?()
          }
        }
        stack.addArrangedSubview(row)
        row.heightAnchor.constraint(equalToConstant: 30).isActive = true
      }
    }
    return stack
  }

  private func makeSeparator() -> NSView {
    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false
    container.heightAnchor.constraint(equalToConstant: 7).isActive = true
    let line = NSView()
    line.wantsLayer = true
    line.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor
    line.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(line)
    NSLayoutConstraint.activate([
      line.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
      line.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
      line.centerYAnchor.constraint(equalTo: container.centerYAnchor),
      line.heightAnchor.constraint(equalToConstant: 1),
    ])
    return container
  }

  private func showSubmenu(_ options: [(String, () -> Void)], from row: NSView) {
    guard !options.isEmpty else { return }
    submenuHandlers = options.map(\.1)
    let menu = NSMenu()
    for (index, option) in options.enumerated() {
      let item = NSMenuItem(
        title: option.0,
        action: #selector(submenuChosen(_:)),
        keyEquivalent: ""
      )
      item.target = self
      item.tag = index
      menu.addItem(item)
    }
    menu.popUp(
      positioning: nil,
      at: NSPoint(x: row.bounds.maxX - 8, y: row.bounds.midY),
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
    layer?.shadowOpacity = Float(style.shadowOpacity)
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
  private let highlight = NSView()
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

    highlight.wantsLayer = true
    highlight.layer?.borderWidth = 0.5
    highlight.layer?.cornerRadius = 13.5
    highlight.translatesAutoresizingMaskIntoConstraints = false
    addSubview(highlight)
    NSLayoutConstraint.activate([
      highlight.topAnchor.constraint(equalTo: topAnchor, constant: 0.5),
      highlight.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0.5),
      highlight.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -0.5),
      highlight.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -0.5),
    ])

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
    layer?.borderColor = NSColor.white.withAlphaComponent(style.borderAlpha).cgColor
    highlight.layer?.borderColor =
      NSColor.white.withAlphaComponent(style.borderAlpha * 0.55).cgColor
    effectView?.alphaValue = style.glassAlpha
    if #available(macOS 26.0, *), let glass = effectView as? NSGlassEffectView {
      glass.style = style.material == .clear ? .clear : .regular
    }
    sheen.colors = [
      NSColor.white.withAlphaComponent(style.sheenTopAlpha).cgColor,
      NSColor.white.withAlphaComponent(style.sheenMidAlpha).cgColor,
      NSColor.clear.cgColor,
    ]
  }

  @objc private func glassStyleChanged() {
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

// MARK: - Row views

@MainActor
private final class PlayerMenuRowView: NSView {
  private let iconView = NSImageView()
  private let label = NSTextField(labelWithString: "")
  private let handler: ((NSView) -> Void)?
  private var isHovered = false

  init(title: String, symbol: String?, enabled: Bool, handler: @escaping (NSView) -> Void) {
    self.handler = handler
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = 6
    layer?.cornerCurve = .continuous
    alphaValue = enabled ? 1 : 0.38

    iconView.image = symbol.flatMap {
      NSImage(systemSymbolName: $0, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
    }
    iconView.contentTintColor = .labelColor
    iconView.imageScaling = .scaleProportionallyDown
    iconView.translatesAutoresizingMaskIntoConstraints = false

    label.stringValue = title
    label.font = .systemFont(ofSize: 13)
    label.textColor = .labelColor
    label.lineBreakMode = .byTruncatingTail
    label.translatesAutoresizingMaskIntoConstraints = false

    addSubview(iconView)
    addSubview(label)
    NSLayoutConstraint.activate([
      iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
      iconView.widthAnchor.constraint(equalToConstant: 16),
      iconView.heightAnchor.constraint(equalToConstant: 16),

      label.leadingAnchor.constraint(
        equalTo: symbol == nil ? leadingAnchor : iconView.trailingAnchor,
        constant: symbol == nil ? 10 : 8
      ),
      label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
    let tracking = NSTrackingArea(
      rect: .zero,
      options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(tracking)
    self.isEnabled = enabled
  }

  required init?(coder: NSCoder) {
    nil
  }

  private var isEnabled = true

  override func mouseEntered(with event: NSEvent) {
    isHovered = true
    updateBackground()
  }

  override func mouseExited(with event: NSEvent) {
    isHovered = false
    updateBackground()
  }

  private func updateBackground() {
    layer?.backgroundColor = isHovered
      ? NSColor.labelColor.withAlphaComponent(0.08).cgColor
      : NSColor.clear.cgColor
  }

  override func mouseUp(with event: NSEvent) {
    guard isEnabled,
          bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
    handler?(self)
  }
}

@MainActor
private final class PlayerMenuRatingView: NSView {
  private let onRate: (Int) -> Void

  init(rating: Int, onRate: @escaping (Int) -> Void) {
    self.onRate = onRate
    super.init(frame: .zero)
    let stack = NSStackView()
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 3
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
    ])

    let clear = RatingButton(symbol: "nosign", tag: 0) { [weak self] in
      self?.onRate(0)
    }
    stack.addArrangedSubview(clear)
    for stars in 1...5 {
      let button = RatingButton(
        symbol: stars <= rating ? "star.fill" : "star",
        tag: stars
      ) { [weak self] in
        self?.onRate(stars)
      }
      button.contentTintColor = stars <= rating ? MacTheme.accentColor : .labelColor
      stack.addArrangedSubview(button)
    }
  }

  required init?(coder: NSCoder) {
    nil
  }
}

@MainActor
private final class RatingButton: NSButton {
  private let onPress: () -> Void

  init(symbol: String, tag: Int, onPress: @escaping () -> Void) {
    self.onPress = onPress
    super.init(frame: .zero)
    self.tag = tag
    isBordered = false
    bezelStyle = .regularSquare
    imagePosition = .imageOnly
    image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
    contentTintColor = .labelColor
    target = self
    action = #selector(pressed)
    translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      widthAnchor.constraint(equalToConstant: 16),
      heightAnchor.constraint(equalToConstant: 16),
    ])
  }

  required init?(coder: NSCoder) {
    nil
  }

  @objc private func pressed() {
    onPress()
  }
}
