//
//  StorageSettingsViewController.swift
//  fmusic-macOS
//
//  Native AppKit port of Catalyst `StorageSettingsView`. Cache statistics come from
//  the shared `CacheFileManager`; the cache-limit popup writes the same
//  `UserSettings.cacheLimit` binding the Catalyst settings screen writes.
//

import AppKit
import fmusicKit

@MainActor
final class StorageSettingsViewController: SettingsPageViewController, NSTextFieldDelegate {
  private enum CacheSizeUnit: Int {
    case mb = 0
    case gb = 1

    var bytesPerUnit: Double {
      switch self {
      case .mb: 1_000_000
      case .gb: 1_000_000_000
      }
    }
  }

  private static let maxLimitBytes: Int = 10_000 * 1_000_000_000

  private var refreshTimer: Timer?
  private var limitField: NSTextField?
  private var selectedUnit: CacheSizeUnit = .gb
  private var cachedCountRow: NSView?
  private var cacheSizeRow: NSView?
  private var clearCacheButton: SettingsButton?

  init() {
    super.init(title: L10n.tr("Storage"))
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func buildForm() {
    let limit = SettingsStore.user.cacheLimit
    let (initialText, initialUnit) = Self.displayComponents(for: limit)
    selectedUnit = initialUnit

    let field = NSTextField(string: initialText)
    field.placeholderString = L10n.tr("No Limit")
    field.alignment = .right
    field.bezelStyle = .roundedBezel
    field.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    field.usesSingleLineMode = true
    field.lineBreakMode = .byTruncatingTail
    field.delegate = self
    field.target = self
    field.action = #selector(limitFieldCommitted)
    field.translatesAutoresizingMaskIntoConstraints = false
    field.widthAnchor.constraint(equalToConstant: 88).isActive = true
    limitField = field

    let unitControl = SettingsSegmentedControl(
      labels: ["MB", "GB"],
      selectedIndex: initialUnit.rawValue
    ) { [weak self] index in
      guard let self, let unit = CacheSizeUnit(rawValue: index) else { return }
      self.selectedUnit = unit
      self.commitLimitInput()
    }

    let limitControl = NSStackView(views: [field, unitControl])
    limitControl.orientation = .horizontal
    limitControl.alignment = .centerY
    limitControl.spacing = 8
    limitControl.translatesAutoresizingMaskIntoConstraints = false

    let limitRow = makeRow(
      title: L10n.tr("Cache Size Limit"),
      subtitle: L10n.tr("Enter 0 or leave blank for no limit."),
      control: limitControl
    )

    let cachedRow = makeValueRow(title: L10n.tr("Cached Songs"), value: "0")
    let sizeRow = makeValueRow(title: L10n.tr("Complete Cache Size"), value: "")
    cachedCountRow = cachedRow
    cacheSizeRow = sizeRow

    let autoCleanupRow = makeSwitchRow(
      title: L10n.tr("Automatically Clean Cache"),
      subtitle: L10n.tr(
        "Remove the least recently used cached audio, artwork and lyrics files when the cache limit is exceeded. The currently playing file and files touched in the last 15 minutes are protected."
      ),
      isOn: UserDefaults.standard.bool(
        forKey: CacheFileManager.automaticEvictionDefaultsKey
      )
    ) { [weak self] isOn in
      UserDefaults.standard.set(
        isOn,
        forKey: CacheFileManager.automaticEvictionDefaultsKey
      )
      if isOn {
        self?.evictCacheIfNeeded()
        self?.refreshStats()
      }
    }

    let clearButton = SettingsButton(
      title: L10n.tr("Clear All Cache"),
      isEnabled: false
    ) { [weak self] in
      self?.confirmClearAllCache()
    }
    clearCacheButton = clearButton
    let clearCacheRow = makeRow(
      title: L10n.tr("Clear All Cache"),
      subtitle: L10n.tr(
        "This will delete all cached songs for this account from this Mac. Your original music files on the server or source folder are not touched."
      ),
      control: clearButton
    )

    addSection(
      header: L10n.tr("Cache"),
      rows: [cachedRow, sizeRow, limitRow, autoCleanupRow, clearCacheRow]
    )
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    refreshStats()

    refreshTimer = Timer.scheduledTimer(
      timeInterval: 1,
      target: self,
      selector: #selector(refreshStats),
      userInfo: nil,
      repeats: true
    )
  }

  private func evictCacheIfNeeded() {
    guard let accountInfo = SettingsStore.activeAccount else { return }
    let limit = SettingsStore.user.cacheLimit
    guard limit > 0,
          UserDefaults.standard.bool(forKey: CacheFileManager.automaticEvictionDefaultsKey)
    else { return }
    let plan = CacheFileManager.shared.makeCacheEvictionPlan(
      for: accountInfo,
      limitBytes: Int64(limit)
    )
    guard !plan.isEmpty else { return }
    CacheFileManager.shared.applyCacheEvictionPlan(plan, accountInfo: accountInfo)
  }

  override func viewWillDisappear() {
    super.viewWillDisappear()
    commitLimitInput()
    refreshTimer?.invalidate()
    refreshTimer = nil
  }

  @objc
  private func limitFieldCommitted() {
    commitLimitInput()
  }

  func controlTextDidEndEditing(_ obj: Notification) {
    commitLimitInput()
  }

  private func commitLimitInput() {
    guard let field = limitField else { return }
    let raw = field.stringValue
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: ",", with: "")
    if raw.isEmpty {
      applyCacheLimit(0)
      return
    }
    guard let value = Double(raw), value.isFinite else {
      let (text, _) = Self.displayComponents(for: SettingsStore.user.cacheLimit, preferredUnit: selectedUnit)
      field.stringValue = text
      return
    }
    if value <= 0 {
      applyCacheLimit(0)
      field.stringValue = ""
      return
    }
    let rawBytes = (value * selectedUnit.bytesPerUnit).rounded()
    let clampedBytes = Int(min(rawBytes, Double(Self.maxLimitBytes)))
    applyCacheLimit(clampedBytes)
    field.stringValue = Self.formatNumber(Double(clampedBytes) / selectedUnit.bytesPerUnit)
  }

  private func applyCacheLimit(_ bytes: Int) {
    guard SettingsStore.user.cacheLimit != bytes else { return }
    SettingsStore.updateUser { $0.cacheLimit = bytes }
    evictCacheIfNeeded()
    refreshStats()
  }

  private static func displayComponents(
    for bytes: Int,
    preferredUnit: CacheSizeUnit? = nil
  )
    -> (String, CacheSizeUnit) {
    guard bytes > 0 else {
      return ("", preferredUnit ?? .gb)
    }
    let unit: CacheSizeUnit
    if let preferredUnit {
      unit = preferredUnit
    } else if bytes >= 1_000_000_000, bytes % 100_000_000 == 0 {
      unit = .gb
    } else {
      unit = .mb
    }
    return (formatNumber(Double(bytes) / unit.bytesPerUnit), unit)
  }

  private static func formatNumber(_ value: Double) -> String {
    if abs(value.rounded() - value) < 0.001 {
      return String(Int(value.rounded()))
    }
    var text = String(format: "%.2f", value)
    while text.contains("."), text.hasSuffix("0") {
      text.removeLast()
    }
    if text.hasSuffix(".") {
      text.removeLast()
    }
    return text
  }

  @objc
  private func refreshStats() {
    guard let accountInfo = SettingsStore.activeAccount else {
      clearCacheButton?.isEnabled = false
      return
    }
    let library = SettingsStore.storage.main.library
    let account = library.getAccount(info: accountInfo)
    let cached = library.getCachedSongCount(for: account)
    let bytes = CacheFileManager.shared.getPlayableCacheSize(for: accountInfo)
    let size = bytes > 1_000_000 ? Int64(bytes).asByteString : Int64(0).asByteString

    func update(_ row: NSView?, title: String, value: String) {
      guard let row = row as? SettingsRowView else { return }
      row.updateControl(from: makeValueRow(title: title, value: value))
    }
    update(cachedCountRow, title: L10n.tr("Cached Songs"), value: "\(cached)")
    update(cacheSizeRow, title: L10n.tr("Complete Cache Size"), value: size)
    clearCacheButton?.isEnabled = cached > 0 || bytes > 0
  }

  private func confirmClearAllCache() {
    guard let accountInfo = SettingsStore.activeAccount else { return }
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = L10n.tr("Clear All Cache")
    alert.informativeText = L10n.tr(
      "This will delete all cached songs for this account from this Mac. Your original music files on the server or source folder are not touched."
    )
    let confirmButton = alert.addButton(withTitle: L10n.tr("Clear All Cache"))
    confirmButton.hasDestructiveAction = true
    alert.addButton(withTitle: L10n.tr("Cancel"))

    let performClear = { [weak self] in
      SettingsStore.player.stop()
      let library = SettingsStore.storage.main.library
      let account = library.getAccount(info: accountInfo)
      let meta = FmusicKit.shared.getMeta(accountInfo)
      meta.playableDownloadManager.stop()
      library.deletePlayableCachePaths(for: account)
      library.saveContext()
      CacheFileManager.shared.deletePlayableCache(accountInfo: accountInfo)
      meta.playableDownloadManager.start()
      NotificationCenter.default.post(name: .librarySongsSynced, object: nil)
      self?.refreshStats()
    }

    if let window = view.window {
      alert.beginSheetModal(for: window) { response in
        guard response == .alertFirstButtonReturn else { return }
        Task { @MainActor in
          performClear()
        }
      }
    } else if alert.runModal() == .alertFirstButtonReturn {
      performClear()
    }
  }
}
