//
//  PodcastEpisodeListViewController.swift
//  fmusic-macOS
//
//  Episode page of one podcast: header (back, artwork, name, episode count) plus
//  the episode list with publish date and duration. Double-click plays an episode.
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

/// Episode list pushed by `PodcastsViewController` for one podcast.
@MainActor
final class PodcastEpisodeListViewController: NSViewController, NSTableViewDataSource,
  NSTableViewDelegate {
  var onBack: (() -> Void)?

  private let podcast: Podcast
  private let backButton = NSButton()
  private let artworkView = NSImageView()
  private let nameLabel = NSTextField(labelWithString: "")
  private let infoLabel = NSTextField(labelWithString: "")
  private let emptyLabel = NSTextField(wrappingLabelWithString: "")
  private let tableView = NSTableView()
  private let scrollView = NSScrollView()

  private var episodes: [PodcastEpisode] = []

  private enum Column {
    static let title = NSUserInterfaceItemIdentifier("podcastEpisodeTitle")
    static let date = NSUserInterfaceItemIdentifier("podcastEpisodeDate")
    static let duration = NSUserInterfaceItemIdentifier("podcastEpisodeDuration")
  }

  init(podcast: Podcast) {
    self.podcast = podcast
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    nil
  }

  // MARK: - Lifecycle

  override func loadView() {
    let root = ThemedBackgroundView()

    backButton.image = NSImage(
      systemSymbolName: "chevron.left",
      accessibilityDescription: L10n.tr("Podcasts")
    )
    backButton.isBordered = false
    backButton.bezelStyle = .regularSquare
    backButton.imagePosition = .imageLeading
    backButton.title = L10n.tr("Podcasts")
    backButton.font = MacTheme.bodyFont
    backButton.contentTintColor = MacTheme.accentColor
    backButton.target = self
    backButton.action = #selector(goBack)
    backButton.translatesAutoresizingMaskIntoConstraints = false

    artworkView.imageScaling = .scaleProportionallyUpOrDown
    artworkView.wantsLayer = true
    artworkView.layer?.cornerRadius = 8
    artworkView.layer?.masksToBounds = true
    artworkView.translatesAutoresizingMaskIntoConstraints = false

    nameLabel.font = .systemFont(ofSize: 24, weight: .bold)
    nameLabel.lineBreakMode = .byTruncatingTail
    nameLabel.translatesAutoresizingMaskIntoConstraints = false

    infoLabel.font = MacTheme.bodyFont
    infoLabel.textColor = MacTheme.secondaryTextColor
    infoLabel.translatesAutoresizingMaskIntoConstraints = false

    emptyLabel.font = .systemFont(ofSize: MacTheme.bodyFontSize)
    emptyLabel.textColor = MacTheme.secondaryTextColor
    emptyLabel.alignment = .center
    emptyLabel.translatesAutoresizingMaskIntoConstraints = false

    configureTableView()
    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.drawsBackground = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    let header = NSView()
    header.translatesAutoresizingMaskIntoConstraints = false

    root.addSubview(backButton)
    root.addSubview(header)
    header.addSubview(artworkView)
    header.addSubview(nameLabel)
    header.addSubview(infoLabel)
    root.addSubview(scrollView)
    root.addSubview(emptyLabel)

    NSLayoutConstraint.activate([
      backButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
      backButton.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),

      header.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 10),
      header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
      header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
      header.heightAnchor.constraint(equalToConstant: 120),

      artworkView.leadingAnchor.constraint(equalTo: header.leadingAnchor),
      artworkView.centerYAnchor.constraint(equalTo: header.centerYAnchor),
      artworkView.widthAnchor.constraint(equalToConstant: 120),
      artworkView.heightAnchor.constraint(equalToConstant: 120),

      nameLabel.leadingAnchor.constraint(equalTo: artworkView.trailingAnchor, constant: 18),
      nameLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor),
      nameLabel.bottomAnchor.constraint(equalTo: header.centerYAnchor, constant: -4),

      infoLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
      infoLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
      infoLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 6),

      scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
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
      selector: #selector(reloadEpisodes),
      name: .librarySongsSynced,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(reloadEpisodes),
      name: .accountActiveChanged,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(themeDidChange),
      name: .macThemeColorChanged,
      object: nil
    )
    reloadEpisodes()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  private func configureTableView() {
    let titleColumn = NSTableColumn(identifier: Column.title)
    titleColumn.title = L10n.tr("Title")
    titleColumn.width = 420
    titleColumn.minWidth = 200

    let dateColumn = NSTableColumn(identifier: Column.date)
    dateColumn.title = L10n.tr("Date Added")
    dateColumn.width = 130
    dateColumn.minWidth = 100
    dateColumn.maxWidth = 180

    let durationColumn = NSTableColumn(identifier: Column.duration)
    durationColumn.title = L10n.tr("Duration")
    durationColumn.width = 60
    durationColumn.minWidth = 56
    durationColumn.maxWidth = 80

    [titleColumn, dateColumn, durationColumn].forEach(tableView.addTableColumn)

    tableView.rowHeight = MacTheme.songRowHeight
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
    let play = NSMenuItem(
      title: L10n.tr("Play"),
      action: #selector(playSelectedRow),
      keyEquivalent: ""
    )
    play.target = self
    menu.addItem(play)
    return menu
  }

  private var librarySetting: AccountSetting {
    FmusicKit.shared.storage.settings.accounts.activeSetting.read
  }

  // MARK: - Data

  @objc
  private func reloadEpisodes() {
    episodes = podcast.episodes

    nameLabel.stringValue = podcast.title
    if episodes.isEmpty {
      infoLabel.stringValue = ""
    } else {
      infoLabel.stringValue = "\(episodes.count) \(L10n.tr("Podcast Episodes"))"
    }
    artworkView.image = LMLibraryArtwork.image(for: podcast, setting: librarySetting)

    tableView.reloadData()
    emptyLabel.stringValue = L10n.tr("No Podcast Episodes")
    emptyLabel.isHidden = !episodes.isEmpty
  }

  @objc
  private func themeDidChange() {
    reloadEpisodes()
  }

  // MARK: - Actions

  @objc
  private func goBack() {
    onBack?()
  }

  @objc
  private func handleDoubleClick() {
    play(row: tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow)
  }

  @objc
  private func playSelectedRow() {
    play(row: tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow)
  }

  private func play(row: Int) {
    guard row >= 0, row < episodes.count else { return }
    // Only episodes that are available to the user can be played; map the clicked
    // episode into that filtered list because the rows show every episode.
    let playables = episodes.filter { $0.isAvailableToUser() }
    let episode = episodes[row]
    guard let index = playables.firstIndex(where: { $0.managedObject === episode.managedObject })
    else { return }
    FmusicKit.shared.player.play(context: PlayContext(
      containable: podcast,
      index: index,
      playables: playables
    ))
  }

  // MARK: - NSTableViewDataSource

  func numberOfRows(in tableView: NSTableView) -> Int {
    episodes.count
  }

  // MARK: - NSTableViewDelegate

  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    let rowView = ThemedRowView()
    rowView.cornerRadius = 5
    rowView.horizontalInset = 10
    return rowView
  }

  func tableView(
    _ tableView: NSTableView,
    viewFor tableColumn: NSTableColumn?,
    row: Int
  )
    -> NSView? {
    guard row < episodes.count, let tableColumn else { return nil }
    let episode = episodes[row]

    switch tableColumn.identifier {
    case Column.title:
      return textCell(
        Column.title,
        text: episode.title,
        font: MacTheme.titleFont,
        color: episode.isAvailableToUser() ? .labelColor : MacTheme.secondaryTextColor,
        alignment: .left
      )
    case Column.date:
      return textCell(
        Column.date,
        text: episode.publishDate.asShortDayMonthString,
        font: MacTheme.bodyFont,
        color: MacTheme.secondaryTextColor,
        alignment: .left
      )
    case Column.duration:
      return textCell(
        Column.duration,
        text: ClockTime(timeInSeconds: episode.duration).asShortString(),
        font: MacTheme.tabularBodyFont,
        color: MacTheme.secondaryTextColor,
        alignment: .right
      )
    default:
      return nil
    }
  }

  private func textCell(
    _ identifier: NSUserInterfaceItemIdentifier,
    text: String,
    font: NSFont,
    color: NSColor,
    alignment: NSTextAlignment
  )
    -> NSView {
    let cell = tableView.makeView(withIdentifier: identifier, owner: self) as?
      LMTextCellView ?? LMTextCellView()
    cell.identifier = identifier
    cell.configure(text: text, font: font, color: color, alignment: alignment)
    return cell
  }
}
