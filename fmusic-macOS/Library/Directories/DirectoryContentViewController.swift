//
//  DirectoryContentViewController.swift
//  fmusic-macOS
//
//  One level of the directory browser: the subfolders (drill-down rows with a
//  chevron) and the songs stored in the current music folder/directory.
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

/// Folder/song list for one directory level, managed by `DirectoriesViewController`.
@MainActor
final class DirectoryContentViewController: NSViewController, NSTableViewDataSource,
  NSTableViewDelegate {
  var onBack: (() -> Void)?
  var onOpenFolder: ((DirectoryNode) -> Void)?

  private let node: DirectoryNode?
  private let backTitle: String?

  private let backButton = NSButton()
  private let titleLabel = NSTextField(labelWithString: "")
  private let infoLabel = NSTextField(labelWithString: "")
  private let emptyLabel = NSTextField(wrappingLabelWithString: "")
  private let tableView = NSTableView()
  private let scrollView = NSScrollView()

  private enum Row {
    case folder(DirectoryNode)
    case song(Song)
  }

  private var rows: [Row] = []
  private var songs: [Song] = []

  private enum Column {
    static let name = NSUserInterfaceItemIdentifier("directoryName")
    static let duration = NSUserInterfaceItemIdentifier("directoryDuration")
  }

  /// Cell reuse identifiers (the name column hosts two different row visuals).
  private enum CellID {
    static let folder = NSUserInterfaceItemIdentifier("directoryFolderCell")
    static let songName = NSUserInterfaceItemIdentifier("directorySongNameCell")
    static let songDuration = NSUserInterfaceItemIdentifier("directorySongDurationCell")
  }

  init(node: DirectoryNode?, backTitle: String?) {
    self.node = node
    self.backTitle = backTitle
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
      accessibilityDescription: L10n.tr("Directories")
    )
    backButton.isBordered = false
    backButton.bezelStyle = .regularSquare
    backButton.imagePosition = .imageLeading
    backButton.title = backTitle ?? ""
    backButton.font = MacTheme.bodyFont
    backButton.contentTintColor = MacTheme.accentColor
    backButton.target = self
    backButton.action = #selector(goBack)
    backButton.isHidden = onBack == nil
    backButton.translatesAutoresizingMaskIntoConstraints = false

    titleLabel.font = MacTheme.largeTitleFont
    titleLabel.lineBreakMode = .byTruncatingTail
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    infoLabel.font = MacTheme.secondaryFont
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

    root.addSubview(backButton)
    root.addSubview(titleLabel)
    root.addSubview(infoLabel)
    root.addSubview(scrollView)
    root.addSubview(emptyLabel)

    // The back button is hidden at the root, so the title sits at the top there.
    let titleTop = backButton.isHidden
      ? titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 20)
      : titleLabel.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 8)

    NSLayoutConstraint.activate([
      backButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
      backButton.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),

      titleTop,
      titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
      titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -24),

      infoLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      infoLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),

      scrollView.topAnchor.constraint(equalTo: infoLabel.bottomAnchor, constant: 12),
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
      selector: #selector(reloadContent),
      name: .librarySongsSynced,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(reloadContent),
      name: .accountActiveChanged,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(themeDidChange),
      name: .macThemeColorChanged,
      object: nil
    )
    reloadContent()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  private func configureTableView() {
    let nameColumn = NSTableColumn(identifier: Column.name)
    nameColumn.title = L10n.tr("Name")
    nameColumn.width = 480
    nameColumn.minWidth = 200

    let durationColumn = NSTableColumn(identifier: Column.duration)
    durationColumn.title = L10n.tr("Duration")
    durationColumn.width = 60
    durationColumn.minWidth = 56
    durationColumn.maxWidth = 80

    [nameColumn, durationColumn].forEach(tableView.addTableColumn)

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
  private func reloadContent() {
    let storage = FmusicKit.shared.storage
    guard let accountInfo = storage.settings.accounts.active else {
      rows = []
      songs = []
      tableView.reloadData()
      titleLabel.stringValue = node?.name ?? L10n.tr("Directories")
      infoLabel.stringValue = ""
      emptyLabel.stringValue = L10n.tr("No Directories")
      emptyLabel.isHidden = false
      return
    }

    let account = storage.main.library.getAccount(info: accountInfo)
    let folders: [DirectoryNode]
    let folderSongs: [Song]

    switch node {
    case nil:
      folders = storage.main.library.getMusicFolders(for: account)
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        .map { DirectoryNode.musicFolder($0) }
      folderSongs = []
    case .musicFolder(let musicFolder):
      let current = storage.main.library.getMusicFolders(for: account)
        .first { $0.managedObject.objectID == musicFolder.managedObject.objectID } ?? musicFolder
      folders = current.directories
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        .map { DirectoryNode.directory($0) }
      folderSongs = current.songs
    case .directory(let directory):
      // Re-fetch the directory wrapper so a library sync is reflected immediately.
      let current = storage.main.library
        .getDirectories(account: account, ids: [directory.id])[directory.id] ?? directory
      folders = current.subdirectories
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        .map { DirectoryNode.directory($0) }
      folderSongs = current.songs
    }

    songs = folderSongs
      .filter { $0.isAvailableToUser() }
      .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    rows = folders.map { Row.folder($0) } + songs.map { Row.song($0) }

    titleLabel.stringValue = node?.name ?? L10n.tr("Directories")

    var infoParts = [String]()
    if !folders.isEmpty {
      infoParts.append("\(folders.count) \(L10n.tr("Directories"))")
    }
    if !songs.isEmpty {
      infoParts.append(LibraryCountText.songs(songs.count))
    }
    infoLabel.stringValue = infoParts.joined(separator: " · ")

    tableView.reloadData()
    if node == nil {
      emptyLabel.stringValue = L10n.tr("No Directories")
    } else {
      emptyLabel.stringValue = L10n.tr("No Directories or Songs")
    }
    emptyLabel.isHidden = !rows.isEmpty
  }

  @objc
  private func themeDidChange() {
    tableView.reloadData()
  }

  // MARK: - Actions

  @objc
  private func goBack() {
    onBack?()
  }

  @objc
  private func handleDoubleClick() {
    let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
    activate(row: row)
  }

  @objc
  private func playSelectedRow() {
    let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
    guard row >= 0, row < rows.count else { return }
    switch rows[row] {
    case .folder:
      playFolder(row: row)
    case .song:
      playSong(row: row)
    }
  }

  /// Double-click on a folder drills into it, double-click on a song starts playback
  /// with the current directory's songs as context.
  private func activate(row: Int) {
    guard row >= 0, row < rows.count else { return }
    switch rows[row] {
    case .folder(let node):
      onOpenFolder?(node)
    case .song:
      playSong(row: row)
    }
  }

  /// Plays every song stored in the current folder (used by the "Play" context menu
  /// entry on folder rows).
  private func playFolder(row: Int) {
    guard row >= 0, row < rows.count, case .folder(let node) = rows[row] else { return }
    switch node {
    case .directory(let directory):
      guard !directory.playables.isEmpty else { return }
      FmusicKit.shared.player.play(context: PlayContext(containable: directory))
    case .musicFolder(let musicFolder):
      let playables = musicFolder.songs.filter { $0.isAvailableToUser() }
      guard !playables.isEmpty else { return }
      FmusicKit.shared.player.play(context: PlayContext(
        name: musicFolder.name,
        playables: playables
      ))
    }
  }

  private func playSong(row: Int) {
    guard row >= 0, row < rows.count else { return }
    guard case .song(let song) = rows[row] else { return }
    guard let index = songs.firstIndex(where: { $0.managedObject === song.managedObject })
    else { return }
    FmusicKit.shared.player.play(context: PlayContext(
      name: node?.name ?? L10n.tr("Directories"),
      index: index,
      playables: songs
    ))
  }

  // MARK: - NSTableViewDataSource

  func numberOfRows(in tableView: NSTableView) -> Int {
    rows.count
  }

  // MARK: - NSTableViewDelegate

  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    guard row < rows.count else { return MacTheme.songRowHeight }
    if case .song = rows[row] {
      // Two-line song rows (title + artist) need a little more room than folders.
      return 44
    }
    return MacTheme.songRowHeight
  }

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
    guard row < rows.count, let tableColumn else { return nil }

    switch (rows[row], tableColumn.identifier) {
    case (.folder(let node), Column.name):
      let cell = tableView.makeView(withIdentifier: CellID.folder, owner: self) as?
        DirectoryFolderCellView ?? DirectoryFolderCellView()
      cell.identifier = CellID.folder
      cell.configure(title: node.name)
      return cell
    case (.song(let song), Column.name):
      let cell = tableView.makeView(withIdentifier: CellID.songName, owner: self) as?
        LMPlayableRowCellView ?? LMPlayableRowCellView()
      cell.identifier = CellID.songName
      cell.configure(
        image: LMLibraryArtwork.image(for: song, setting: librarySetting),
        title: song.title,
        subtitle: song.creatorName,
        trailing: nil
      )
      return cell
    case (.song(let song), Column.duration):
      let cell = tableView.makeView(withIdentifier: CellID.songDuration, owner: self) as?
        LMTextCellView ?? LMTextCellView()
      cell.identifier = CellID.songDuration
      cell.configure(
        text: ClockTime(timeInSeconds: song.duration).asShortString(),
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

// MARK: - DirectoryFolderCellView

/// Folder row: folder icon, name and a trailing chevron that signals the drill-down.
@MainActor
private final class DirectoryFolderCellView: NSTableCellView {
  private let iconView = NSImageView()
  private let titleLabel = NSTextField(labelWithString: "")
  private let chevronView = NSImageView()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    iconView.image = NSImage(
      systemSymbolName: "folder.fill",
      accessibilityDescription: L10n.tr("Directories")
    )
    iconView.contentTintColor = MacTheme.accentColor
    iconView.imageScaling = .scaleProportionallyDown
    iconView.translatesAutoresizingMaskIntoConstraints = false

    titleLabel.font = MacTheme.titleFont
    titleLabel.lineBreakMode = .byTruncatingTail
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    chevronView.image = NSImage(
      systemSymbolName: "chevron.right",
      accessibilityDescription: nil
    )
    chevronView.contentTintColor = MacTheme.secondaryTextColor
    chevronView.imageScaling = .scaleProportionallyDown
    chevronView.translatesAutoresizingMaskIntoConstraints = false

    addSubview(iconView)
    addSubview(titleLabel)
    addSubview(chevronView)

    NSLayoutConstraint.activate([
      iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
      iconView.widthAnchor.constraint(equalToConstant: 20),
      iconView.heightAnchor.constraint(equalToConstant: 20),

      titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
      titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
      titleLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: chevronView.leadingAnchor,
        constant: -8
      ),

      chevronView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
      chevronView.centerYAnchor.constraint(equalTo: centerYAnchor),
      chevronView.widthAnchor.constraint(equalToConstant: 12),
      chevronView.heightAnchor.constraint(equalToConstant: 12),
    ])
    self.textField = titleLabel
    self.imageView = iconView
  }

  required init?(coder: NSCoder) {
    nil
  }

  func configure(title: String) {
    titleLabel.stringValue = title
  }
}
