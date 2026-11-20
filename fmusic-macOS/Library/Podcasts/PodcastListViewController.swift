//
//  PodcastListViewController.swift
//  fmusic-macOS
//
//  List half of the podcasts page: artwork, name and episode count per podcast.
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
import fmusicKit

/// Podcast list managed by `PodcastsViewController`; double-click opens the episodes.
@MainActor
final class PodcastListViewController: NSViewController, NSTableViewDataSource,
  NSTableViewDelegate {
  var onSelect: ((Podcast) -> Void)?

  private let titleLabel = NSTextField(labelWithString: L10n.tr("Podcasts"))
  private let countLabel = NSTextField(labelWithString: "")
  private let emptyLabel = NSTextField(wrappingLabelWithString: "")
  private let tableView = NSTableView()
  private let scrollView = NSScrollView()

  private var podcasts: [Podcast] = []

  private enum Column {
    static let artwork = NSUserInterfaceItemIdentifier("podcastArtwork")
    static let name = NSUserInterfaceItemIdentifier("podcastName")
    static let episodes = NSUserInterfaceItemIdentifier("podcastEpisodeCount")
  }

  override func loadView() {
    let root = ThemedBackgroundView()

    titleLabel.font = MacTheme.largeTitleFont
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    countLabel.font = MacTheme.secondaryFont
    countLabel.textColor = MacTheme.secondaryTextColor
    countLabel.translatesAutoresizingMaskIntoConstraints = false

    emptyLabel.font = .systemFont(ofSize: MacTheme.bodyFontSize)
    emptyLabel.textColor = MacTheme.secondaryTextColor
    emptyLabel.alignment = .center
    emptyLabel.translatesAutoresizingMaskIntoConstraints = false

    configureTableView()
    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.drawsBackground = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    root.addSubview(titleLabel)
    root.addSubview(countLabel)
    root.addSubview(scrollView)
    root.addSubview(emptyLabel)

    NSLayoutConstraint.activate([
      titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
      titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),

      countLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      countLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),

      scrollView.topAnchor.constraint(equalTo: countLabel.bottomAnchor, constant: 12),
      scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

      emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
      emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
      emptyLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
    ])

    self.view = root
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(reloadPodcasts),
      name: .librarySongsSynced,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(reloadPodcasts),
      name: .accountActiveChanged,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(themeDidChange),
      name: .macThemeColorChanged,
      object: nil
    )
    reloadPodcasts()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  // MARK: - Table view

  private func configureTableView() {
    let artworkColumn = NSTableColumn(identifier: Column.artwork)
    artworkColumn.title = ""
    artworkColumn.width = 64
    artworkColumn.minWidth = 64
    artworkColumn.maxWidth = 64

    let nameColumn = NSTableColumn(identifier: Column.name)
    nameColumn.title = L10n.tr("Podcasts")
    nameColumn.width = 380
    nameColumn.minWidth = 180

    let episodesColumn = NSTableColumn(identifier: Column.episodes)
    episodesColumn.title = L10n.tr("Podcast Episodes")
    episodesColumn.width = 130
    episodesColumn.minWidth = 90
    episodesColumn.maxWidth = 180

    [artworkColumn, nameColumn, episodesColumn].forEach(tableView.addTableColumn)

    tableView.rowHeight = 56
    tableView.style = .fullWidth
    tableView.selectionHighlightStyle = .regular
    tableView.allowsMultipleSelection = false
    tableView.allowsEmptySelection = true
    tableView.usesAlternatingRowBackgroundColors = false
    tableView.backgroundColor = .clear
    tableView.gridStyleMask = []
    tableView.dataSource = self
    tableView.delegate = self
    tableView.doubleAction = #selector(handleDoubleClick)
    tableView.target = self
    tableView.menu = makeContextMenu()
  }

  private func makeContextMenu() -> NSMenu {
    let menu = NSMenu()
    let open = NSMenuItem(
      title: L10n.tr("Show Podcast"),
      action: #selector(openSelectedRow),
      keyEquivalent: ""
    )
    open.target = self
    menu.addItem(open)
    return menu
  }

  private var librarySetting: AccountSetting {
    FmusicKit.shared.storage.settings.accounts.activeSetting.read
  }

  // MARK: - Data

  @objc
  private func reloadPodcasts() {
    let storage = FmusicKit.shared.storage
    guard let accountInfo = storage.settings.accounts.active else {
      podcasts = []
      tableView.reloadData()
      countLabel.stringValue = ""
      emptyLabel.stringValue = L10n.tr("No Podcasts")
      emptyLabel.isHidden = false
      return
    }
    let account = storage.main.library.getAccount(info: accountInfo)
    podcasts = storage.main.library.getPodcasts(for: account)
    tableView.reloadData()
    countLabel.stringValue = podcasts.isEmpty ? "" : "\(podcasts.count)"
    emptyLabel.stringValue = L10n.tr("No Podcasts")
    emptyLabel.isHidden = !podcasts.isEmpty
  }

  @objc
  private func themeDidChange() {
    tableView.reloadData()
  }

  // MARK: - Actions

  @objc
  private func handleDoubleClick() {
    open(row: tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow)
  }

  @objc
  private func openSelectedRow() {
    open(row: tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow)
  }

  private func open(row: Int) {
    guard row >= 0, row < podcasts.count else { return }
    onSelect?(podcasts[row])
  }

  // MARK: - NSTableViewDataSource

  func numberOfRows(in tableView: NSTableView) -> Int {
    podcasts.count
  }

  // MARK: - NSTableViewDelegate

  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    let rowView = ThemedRowView()
    rowView.cornerRadius = 6
    rowView.horizontalInset = 10
    return rowView
  }

  func tableView(
    _ tableView: NSTableView,
    viewFor tableColumn: NSTableColumn?,
    row: Int
  )
    -> NSView? {
    guard row < podcasts.count, let tableColumn else { return nil }
    let podcast = podcasts[row]

    switch tableColumn.identifier {
    case Column.artwork:
      let cell = tableView.makeView(withIdentifier: Column.artwork, owner: self) as?
        LMArtworkCellView ?? LMArtworkCellView()
      cell.identifier = Column.artwork
      cell.display(
        image: LMLibraryArtwork.image(for: podcast, setting: librarySetting),
        size: 44
      )
      return cell
    case Column.name:
      let cell = tableView.makeView(withIdentifier: Column.name, owner: self) as?
        LMTextCellView ?? LMTextCellView()
      cell.identifier = Column.name
      cell.configure(
        text: podcast.title,
        font: .systemFont(ofSize: MacTheme.titleFontSize, weight: .medium),
        color: .labelColor
      )
      return cell
    case Column.episodes:
      let cell = tableView.makeView(withIdentifier: Column.episodes, owner: self) as?
        LMTextCellView ?? LMTextCellView()
      cell.identifier = Column.episodes
      cell.configure(
        text: "\(podcast.episodeCount)",
        font: MacTheme.tabularBodyFont,
        color: MacTheme.secondaryTextColor,
        alignment: .right
      )
      return cell
    default:
      return nil
    }
  }
}
