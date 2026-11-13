//
//  AudioOutputPicker.swift
//  fmusic
//
//  System audio output menu for the AirPlay button: lists the CoreAudio output devices and
//  switches the default output device.
//

import CoreAudio
import UIKit

// MARK: - AudioOutputDeviceInfo

struct AudioOutputDeviceInfo {
  enum Kind {
    case builtIn
    case bluetooth
    case usb
    case display
    case virtual
    case other
  }

  let id: AudioDeviceID
  let name: String
  let kind: Kind
  let isDefault: Bool
}

// MARK: - AudioOutputRouting

enum AudioOutputRouting {
  private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

  private static func address(
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
  )
    -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: scope,
      mElement: kAudioObjectPropertyElementMain
    )
  }

  static func defaultOutputDeviceID() -> AudioDeviceID? {
    var deviceID = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var propertyAddress = address(kAudioHardwarePropertyDefaultOutputDevice)
    guard AudioObjectGetPropertyData(
      systemObject,
      &propertyAddress,
      0,
      nil,
      &size,
      &deviceID
    ) == noErr else { return nil }
    return deviceID
  }

  static func outputDevices() -> [AudioOutputDeviceInfo] {
    var size = UInt32(0)
    var propertyAddress = address(kAudioHardwarePropertyDevices)
    guard AudioObjectGetPropertyDataSize(systemObject, &propertyAddress, 0, nil, &size) == noErr
    else { return [] }
    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    guard count > 0 else { return [] }

    var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
    guard AudioObjectGetPropertyData(
      systemObject,
      &propertyAddress,
      0,
      nil,
      &size,
      &deviceIDs
    ) == noErr else { return [] }

    let activeDeviceID = defaultOutputDeviceID()
    return deviceIDs.compactMap { deviceID -> AudioOutputDeviceInfo? in
      guard outputChannelCount(of: deviceID) > 0,
            let name = deviceName(of: deviceID),
            !name.isEmpty,
            // Catalyst registers a private aggregate device as its own output; not user-selectable.
            !name.hasPrefix("CADefaultDeviceAggregate")
      else { return nil }
      return AudioOutputDeviceInfo(
        id: deviceID,
        name: name,
        kind: deviceKind(of: deviceID),
        isDefault: deviceID == activeDeviceID
      )
    }
  }

  @discardableResult
  static func setDefaultOutputDevice(_ deviceID: AudioDeviceID) -> Bool {
    var deviceID = deviceID
    var propertyAddress = address(kAudioHardwarePropertyDefaultOutputDevice)
    let size = UInt32(MemoryLayout<AudioDeviceID>.size)
    return AudioObjectSetPropertyData(
      systemObject,
      &propertyAddress,
      0,
      nil,
      size,
      &deviceID
    ) == noErr
  }

  private static func outputChannelCount(of deviceID: AudioDeviceID) -> Int {
    var propertyAddress = address(kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeOutput)
    var size = UInt32(0)
    guard AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &size) == noErr,
          size > 0
    else { return 0 }
    let buffer = UnsafeMutableRawPointer.allocate(
      byteCount: Int(size),
      alignment: MemoryLayout<AudioBufferList>.alignment
    )
    defer { buffer.deallocate() }
    guard AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, buffer) == noErr
    else { return 0 }
    let bufferList = UnsafeMutableAudioBufferListPointer(
      buffer.assumingMemoryBound(to: AudioBufferList.self)
    )
    return bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
  }

  private static func deviceName(of deviceID: AudioDeviceID) -> String? {
    var propertyAddress = address(kAudioObjectPropertyName)
    var name: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    guard AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, &name) == noErr
    else { return nil }
    return name as String
  }

  private static func deviceKind(of deviceID: AudioDeviceID) -> AudioOutputDeviceInfo.Kind {
    var transportType = UInt32(0)
    var propertyAddress = address(kAudioDevicePropertyTransportType)
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(
      deviceID,
      &propertyAddress,
      0,
      nil,
      &size,
      &transportType
    ) == noErr else { return .other }

    switch transportType {
    case kAudioDeviceTransportTypeBuiltIn: return .builtIn
    case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
    case kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeThunderbolt: return .usb
    case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return .display
    case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate: return .virtual
    default: return .other
    }
  }
}

// MARK: - AudioOutputPicker

@MainActor
enum AudioOutputPicker {
  static let panelWidth: CGFloat = 230
  static let rowHeight: CGFloat = 38
  static let verticalPadding: CGFloat = 6

  private static weak var activeOverlay: AudioOutputPickerOverlay?

  private static var appDelegateFromApp: AppDelegate? {
    UIApplication.shared.delegate as? AppDelegate
  }

  static var isPresented: Bool { activeOverlay != nil }

  static func toggle(above anchorView: UIView) {
    if isPresented {
      dismiss()
    } else {
      present(above: anchorView)
    }
  }

  static func present(above anchorView: UIView) {
    guard activeOverlay == nil,
          let window = anchorView.window
    else { return }

    let devices = AudioOutputRouting.outputDevices()
    guard !devices.isEmpty else { return }

    let panel = AudioOutputPickerPanel(devices: devices)
    let overlay = AudioOutputPickerOverlay(frame: window.bounds)
    overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    overlay.onDismiss = { dismiss() }
    window.addSubview(overlay)

    let panelHeight = panel.intrinsicHeight
    let anchor = anchorView.convert(anchorView.bounds, to: window)
    var originY = anchor.minY - 8 - panelHeight
    if originY < window.safeAreaInsets.top + 8 {
      originY = anchor.maxY + 8
    }
    let originX = min(
      max(anchor.maxX - panelWidth, 8),
      window.bounds.width - panelWidth - 8
    )
    panel.frame = CGRect(
      x: originX,
      y: originY,
      width: panelWidth,
      height: panelHeight
    )
    overlay.addSubview(panel)

    panel.onSelect = { [weak overlay] device in
      AudioOutputRouting.setDefaultOutputDevice(device.id)
      overlay?.onDismiss?()
    }

    activeOverlay = overlay
    appDelegateFromApp?.audioOutputPickerDismissHandler = { dismiss() }

    panel.alpha = 0
    panel.transform = CGAffineTransform(translationX: 0, y: 4)
    overlay.alpha = 0
    UIView.animate(
      withDuration: 0.14,
      delay: 0,
      options: [.curveEaseOut, .allowUserInteraction]
    ) {
      overlay.alpha = 1
      panel.alpha = 1
      panel.transform = .identity
    }
  }

  static func dismiss() {
    guard let overlay = activeOverlay else { return }
    activeOverlay = nil
    appDelegateFromApp?.audioOutputPickerDismissHandler = nil
    let panel = overlay.subviews.first
    UIView.animate(
      withDuration: 0.1,
      delay: 0,
      options: [.curveEaseIn, .allowUserInteraction]
    ) {
      overlay.alpha = 0
      panel?.alpha = 0
    } completion: { _ in
      overlay.removeFromSuperview()
    }
  }
}

// MARK: - AudioOutputPickerOverlay

private final class AudioOutputPickerOverlay: UIControl {
  var onDismiss: (() -> ())?

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    addTarget(self, action: #selector(backgroundTapped), for: .touchUpInside)
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  @objc
  private func backgroundTapped() {
    onDismiss?()
  }
}

// MARK: - AudioOutputPickerPanel

private final class AudioOutputPickerPanel: UIView {
  var onSelect: ((AudioOutputDeviceInfo) -> ())?

  private let devices: [AudioOutputDeviceInfo]

  var intrinsicHeight: CGFloat {
    AudioOutputPicker.verticalPadding * 2 + CGFloat(devices.count) * AudioOutputPicker.rowHeight
  }

  init(devices: [AudioOutputDeviceInfo]) {
    self.devices = devices
    super.init(frame: .zero)
    backgroundColor = .clear
    layer.cornerRadius = 12
    layer.cornerCurve = .continuous
    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOpacity = 0.12
    layer.shadowRadius = 12
    layer.shadowOffset = CGSize(width: 0, height: 4)

    let glass = UIVisualEffectView()
    let glassEffect = UIGlassEffect(style: .regular)
    glassEffect.isInteractive = false
    glass.effect = glassEffect
    glass.layer.cornerRadius = 12
    glass.layer.cornerCurve = .continuous
    glass.clipsToBounds = true
    glass.translatesAutoresizingMaskIntoConstraints = false
    addSubview(glass)

    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = 0
    stack.translatesAutoresizingMaskIntoConstraints = false
    for device in devices {
      let row = AudioOutputDeviceRow(device: device)
      row.onTap = { [weak self] in self?.onSelect?(device) }
      row.heightAnchor.constraint(equalToConstant: AudioOutputPicker.rowHeight).isActive = true
      stack.addArrangedSubview(row)
    }
    addSubview(stack)
    NSLayoutConstraint.activate([
      glass.topAnchor.constraint(equalTo: topAnchor),
      glass.leadingAnchor.constraint(equalTo: leadingAnchor),
      glass.trailingAnchor.constraint(equalTo: trailingAnchor),
      glass.bottomAnchor.constraint(equalTo: bottomAnchor),
      stack.topAnchor.constraint(
        equalTo: topAnchor,
        constant: AudioOutputPicker.verticalPadding
      ),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
      stack.bottomAnchor.constraint(
        equalTo: bottomAnchor,
        constant: -AudioOutputPicker.verticalPadding
      ),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

// MARK: - AudioOutputDeviceRow

private final class AudioOutputDeviceRow: UIControl {
  var onTap: (() -> ())?

  private let device: AudioOutputDeviceInfo

  init(device: AudioOutputDeviceInfo) {
    self.device = device
    super.init(frame: .zero)

    let iconView = UIImageView(image: Self.icon(for: device.kind))
    iconView.tintColor = .label
    iconView.contentMode = .scaleAspectFit
    iconView.translatesAutoresizingMaskIntoConstraints = false
    iconView.widthAnchor.constraint(equalToConstant: 22).isActive = true

    let nameLabel = UILabel()
    nameLabel.text = device.name
    nameLabel.font = .systemFont(ofSize: 13)
    nameLabel.textColor = .label
    nameLabel.lineBreakMode = .byTruncatingMiddle

    let checkmarkView = UIImageView(
      image: UIImage(
        systemName: "checkmark",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
      )
    )
    checkmarkView.tintColor = .label
    checkmarkView.translatesAutoresizingMaskIntoConstraints = false
    checkmarkView.isHidden = !device.isDefault

    let stack = UIStackView(arrangedSubviews: [iconView, nameLabel, checkmarkView])
    stack.axis = .horizontal
    stack.alignment = .center
    stack.spacing = 10
    stack.isUserInteractionEnabled = false
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      stack.topAnchor.constraint(equalTo: topAnchor),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor),
      iconView.heightAnchor.constraint(equalToConstant: 22),
      checkmarkView.widthAnchor.constraint(equalToConstant: 14),
    ])

    layer.cornerRadius = 8
    layer.cornerCurve = .continuous
    addTarget(self, action: #selector(tapped), for: .touchUpInside)
    let hover = UIHoverGestureRecognizer(target: self, action: #selector(hoverChanged(_:)))
    addGestureRecognizer(hover)

    isAccessibilityElement = true
    accessibilityLabel = device.name
    accessibilityTraits = device.isDefault ? [.button, .selected] : [.button]
  }

  override func accessibilityActivate() -> Bool {
    onTap?()
    return true
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var isHighlighted: Bool {
    didSet { updateBackground() }
  }

  @objc
  private func tapped() {
    onTap?()
  }

  @objc
  private func hoverChanged(_ recognizer: UIHoverGestureRecognizer) {
    switch recognizer.state {
    case .began, .changed:
      backgroundColor = UIColor.label.withAlphaComponent(0.06)
    case .ended, .cancelled:
      backgroundColor = isHighlighted ? UIColor.label.withAlphaComponent(0.1) : .clear
    default:
      break
    }
  }

  private func updateBackground() {
    backgroundColor = isHighlighted ? UIColor.label.withAlphaComponent(0.1) : .clear
  }

  private static func icon(for kind: AudioOutputDeviceInfo.Kind) -> UIImage? {
    let configuration = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
    let symbolName: String
    switch kind {
    case .builtIn: symbolName = "laptopcomputer"
    case .bluetooth: symbolName = "airpodspro"
    case .usb: symbolName = "hifispeaker"
    case .display: symbolName = "display"
    case .virtual: symbolName = "waveform"
    case .other: symbolName = "speaker.wave.2"
    }
    return UIImage(systemName: symbolName, withConfiguration: configuration)
      ?? UIImage(systemName: "speaker.wave.2", withConfiguration: configuration)
  }
}
