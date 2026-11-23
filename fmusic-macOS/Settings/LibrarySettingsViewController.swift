//
//  LibrarySettingsViewController.swift
//  fmusic-macOS
//
//  Native AppKit port of Catalyst `LibrarySettingsView`: library counts and
//  background-sync progress, refreshed while the page is visible.
//

import AppKit
import fmusicKit

@MainActor
final class LibrarySettingsViewController: SettingsPageViewController {
  private var refreshTimer: Timer?
  private var countRows: [NSView] = []
  private var progressRow: NSView?

  init() {
    super.init(title: L10n.tr("Library"))
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    refresh()
    refreshTimer = Timer.scheduledTimer(
      timeInterval: 1,
      target: self,
      selector: #selector(refresh),
      userInfo: nil,
      repeats: true
    )
  }

  override func viewWillDisappear() {
    super.viewWillDisappear()
    refreshTimer?.invalidate()
    refreshTimer = nil
  }

  @objc
  private func refresh() {
    let storage = SettingsStore.storage
    guard let accountInfo = storage.settings.accounts.active else { return }
    let account = storage.main.library.getAccount(info: accountInfo)
    let library = storage.main.library

    let playlists = library.getPlaylistCount(for: account)
    let artists = library.getArtistCount(for: account)
    let albums = library.getAlbumCount(for: account)
    let songs = library.getSongCount(for: account)
    let synced = library.getAlbumWithSyncedSongsCount(for: account)
    let syncStatus = storage.settings.accounts
      .getSetting(accountInfo).read.initialSyncCompletionStatus.description
    let progress = albums < 1
      ? "0.0%"
      : String(format: "%.1f%%", Float(synced) * 100 / Float(albums))

    let rows = [
      makeValueRow(title: L10n.tr("Playlists"), value: "\(playlists)"),
      makeValueRow(title: L10n.tr("Artists"), value: "\(artists)"),
      makeValueRow(title: L10n.tr("Albums"), value: "\(albums)"),
      makeValueRow(title: L10n.tr("Songs"), value: "\(songs)"),
      makeValueRow(title: L10n.tr("Initial Sync"), value: syncStatus),
    ]
    let progressValue = makeValueRow(title: L10n.tr("Progress"), value: progress)

    if countRows.isEmpty {
      countRows = rows
      progressRow = progressValue
      addSection(header: L10n.tr("Library"), rows: rows)
      addSection(header: L10n.tr("Background song sync"), rows: [progressValue])
      return
    }

    // Preserve scroll position: swap just the value labels in the existing rows.
    func update(_ row: NSView, with replacement: NSView) {
      guard let existing = row as? SettingsRowView,
            let fresh = replacement as? SettingsRowView else { return }
      existing.updateControl(from: fresh)
    }
    zip(countRows, rows).forEach { update($0.0, with: $0.1) }
    if let progressRow { update(progressRow, with: progressValue) }
  }
}
