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
final class StorageSettingsViewController: SettingsPageViewController {
  private enum LimitValue {
    static let values: [Int] = {
      var result = stride(from: 10, through: 100, by: 10).map { $0 * 1_000_000 }
      result.append(contentsOf: stride(from: 125, through: 950, by: 25).map { $0 * 1_000_000 })
      result.append(contentsOf: stride(from: 1, through: 10, by: 1).map { $0 * 1_000_000_000 })
      return [0] + result
    }()

    static func title(_ value: Int) -> String {
      value == 0 ? L10n.tr("No Limit") : Int64(value).asByteString
    }
  }

  private var refreshTimer: Timer?
  private var limitRow: NSView?
  private var cachedCountRow: NSView?
  private var cacheSizeRow: NSView?
  private var clearCacheButton: SettingsButton?

  init() {
    super.init(title: L10n.tr("Storage & Artwork"))
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func buildForm() {
    let limit = SettingsStore.user.cacheLimit
    let limitRow = makePopupRow(
      title: L10n.tr("Cache Size Limit"),
      titles: LimitValue.values.map(LimitValue.title),
      selectedIndex: max(0, LimitValue.values.firstIndex(of: limit) ?? 0)
    ) { [weak self] index in
      guard index >= 0, index < LimitValue.values.count else { return }
      SettingsStore.updateUser { $0.cacheLimit = LimitValue.values[index] }
      self?.evictCacheIfNeeded()
      self?.refreshStats()
    }
    self.limitRow = limitRow

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
    refreshTimer?.invalidate()
    refreshTimer = nil
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
