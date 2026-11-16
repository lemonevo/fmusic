//
//  LyricsSearchVC.swift
//  fmusic
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

import fmusicKit
import UIKit

// MARK: - LyricsSearchVC

/// Free text search for online lyrics. Picked results are previewed and can be
/// applied to the currently playing song.
class LyricsSearchVC: BasicTableViewController {
  override var sceneTitle: String? { L10n.tr("Lyrics Search") }

  private enum Section: Int, CaseIterable {
    case target = 0
    case results = 1
  }

  private static let cellIdentifier = LyricsSearchCell.identifier
  private static let statusCellIdentifier = "LyricsSearchStatusCell"
  private static let sourceOrder: [OnlineLyricsSource] = [.netease, .qqmusic, .kugou, .lrclib]

  private var results = [OnlineLyricsSearchResult]()
  private var query = ""
  private var searchTask: Task<(), Never>?
  private var isSearching = false
  private var hasSearched = false
  private var selectedSource: OnlineLyricsSource?
  private var filterButton: UIBarButtonItem!

  private var formats = [String: OnlineLyricsFormat]()
  private var attemptedFormats = Set<String>()
  private var probeQueue = [OnlineLyricsSearchResult]()
  private var queuedProbeIDs = Set<String>()
  private var probeTasks = [String: Task<(), Never>]()
  private var activeProbes = 0
  private var probeGeneration = 0
  private static let maxConcurrentProbes = 4

  private var visibleResults: [OnlineLyricsSearchResult] {
    guard let selectedSource else { return results }
    return results.filter { $0.source == selectedSource }
  }

  private var targetSong: Song? { appDelegate.player.currentlyPlaying?.asSong }

  init() {
    super.init(style: .plain)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    tableView.register(LyricsSearchCell.self, forCellReuseIdentifier: Self.cellIdentifier)
    tableView.register(
      UITableViewCell.self,
      forCellReuseIdentifier: Self.statusCellIdentifier
    )
    tableView.estimatedRowHeight = PlayableTableCell.rowHeight
    configureSearchController(placeholder: L10n.tr("Search lyrics by song or artist"))
    configureFilterButton()

    appDelegate.notificationHandler.register(
      self,
      selector: #selector(playerDidChange),
      name: .playerPlay,
      object: nil
    )
    appDelegate.notificationHandler.register(
      self,
      selector: #selector(playerDidChange),
      name: .playerStop,
      object: nil
    )
  }

  override func viewIsAppearing(_ animated: Bool) {
    super.viewIsAppearing(animated)
    extendSafeAreaToAccountForMiniPlayer()
    tableView.reloadSections(IndexSet(integer: Section.target.rawValue), with: .none)
  }

  @objc
  private func playerDidChange() {
    tableView.reloadSections(IndexSet(integer: Section.target.rawValue), with: .none)
  }

  // MARK: Filter

  private func configureFilterButton() {
    filterButton = UIBarButtonItem.createSortBarButton()
    navigationItem.rightBarButtonItem = filterButton
    updateFilterMenu()
  }

  private func updateFilterMenu() {
    let allAction = UIAction(
      title: L10n.tr("All Sources"),
      state: selectedSource == nil ? .on : .off
    ) { [weak self] _ in
      self?.selectSource(nil)
    }
    let sourceActions = Self.sourceOrder.map { source in
      UIAction(
        title: source.displayName,
        state: selectedSource == source ? .on : .off
      ) { [weak self] _ in
        self?.selectSource(source)
      }
    }
    filterButton.menu = UIMenu(
      title: L10n.tr("Filter"),
      children: [allAction, UIMenu(options: .displayInline, children: sourceActions)]
    )
  }

  private func selectSource(_ source: OnlineLyricsSource?) {
    selectedSource = source
    updateFilterMenu()
    tableView.reloadSections(IndexSet(integer: Section.results.rawValue), with: .none)
  }

  // MARK: Search

  override func updateSearchResults(for searchController: UISearchController) {
    let text = searchController.searchBar.text?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard text != query else { return }
    query = text
    searchTask?.cancel()
    resetFormatProbes()

    guard text.count >= 2 else {
      results = []
      isSearching = false
      hasSearched = false
      tableView.reloadData()
      return
    }

    guard appDelegate.storage.settings.user.isOnlineMode else {
      results = []
      isSearching = false
      hasSearched = true
      tableView.reloadData()
      return
    }

    results = []
    isSearching = true
    hasSearched = true
    tableView.reloadData()

    searchTask = Task { @MainActor [weak self] in
      let found = await OnlineLyricsService.shared.searchLyrics(keyword: text)
      guard let self, !Task.isCancelled, query == text else { return }
      results = found
      isSearching = false
      tableView.reloadData()
    }
  }

  // MARK: Table

  override func numberOfSections(in tableView: UITableView) -> Int {
    Section.allCases.count
  }

  override func tableView(
    _ tableView: UITableView,
    numberOfRowsInSection section: Int
  )
    -> Int {
    switch Section(rawValue: section) {
    case .target: 1
    case .results: max(visibleResults.count, 1)
    case nil: 0
    }
  }

  override func tableView(
    _ tableView: UITableView,
    titleForHeaderInSection section: Int
  )
    -> String? {
    switch Section(rawValue: section) {
    case .target:
      return L10n.tr("Now Playing")
    case .results:
      guard hasSearched else { return nil }
      guard let selectedSource else { return L10n.tr("Search Results") }
      return "\(L10n.tr("Search Results")) · \(selectedSource.displayName)"
    case nil:
      return nil
    }
  }

  override func tableView(
    _ tableView: UITableView,
    heightForHeaderInSection section: Int
  )
    -> CGFloat {
    28
  }

  override func tableView(
    _ tableView: UITableView,
    heightForRowAt indexPath: IndexPath
  )
    -> CGFloat {
    if Section(rawValue: indexPath.section) == .results, visibleResults.isEmpty {
      return 48
    }
    return PlayableTableCell.rowHeight
  }

  override func tableView(
    _ tableView: UITableView,
    willDisplayHeaderView view: UIView,
    forSection section: Int
  ) {
    guard let header = view as? UITableViewHeaderFooterView else { return }
    var content = header.defaultContentConfiguration()
    content.text = tableView.dataSource?.tableView?(tableView, titleForHeaderInSection: section)
    content.textProperties.font = .preferredFont(forTextStyle: .footnote)
    content.textProperties.color = .secondaryLabel
    header.contentConfiguration = content
  }

  override func tableView(
    _ tableView: UITableView,
    willDisplay cell: UITableViewCell,
    forRowAt indexPath: IndexPath
  ) {
    guard Section(rawValue: indexPath.section) == .results,
          visibleResults.indices.contains(indexPath.row)
    else { return }
    requestFormatIfNeeded(visibleResults[indexPath.row])
  }

  override func tableView(
    _ tableView: UITableView,
    cellForRowAt indexPath: IndexPath
  )
    -> UITableViewCell {
    switch Section(rawValue: indexPath.section) {
    case .target:
      return targetCell(tableView)
    case .results:
      guard visibleResults.indices.contains(indexPath.row) else {
        return statusCell(tableView)
      }
      return resultCell(tableView, result: visibleResults[indexPath.row])
    case nil:
      return UITableViewCell()
    }
  }

  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    switch Section(rawValue: indexPath.section) {
    case .target:
      guard let song = targetSong else { return }
      let text = [song.title, song.artist?.name]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
      guard !text.isEmpty else { return }
      searchController.searchBar.text = text
      updateSearchResults(for: searchController)
    case .results:
      guard visibleResults.indices.contains(indexPath.row) else { return }
      let previewVC = LyricsPreviewVC(result: visibleResults[indexPath.row])
      navigationController?.pushViewController(previewVC, animated: true)
    case nil:
      break
    }
  }

  // MARK: Cells

  private func dequeueCell(_ tableView: UITableView) -> LyricsSearchCell {
    tableView.dequeueReusableCell(withIdentifier: Self.cellIdentifier) as! LyricsSearchCell
  }

  private func targetCell(_ tableView: UITableView) -> UITableViewCell {
    let cell = dequeueCell(tableView)
    if let song = targetSong {
      cell.set(
        title: song.title,
        subtitle: song.artist?.name ?? "",
        source: L10n.tr("Search this song"),
        duration: "",
        format: nil,
        metaColor: .tintColor,
        icon: .search
      )
      cell.selectionStyle = .default
    } else {
      cell.set(
        title: L10n.tr("No song is playing. Play a song first, then apply lyrics to it."),
        subtitle: "",
        source: "",
        duration: "",
        format: nil,
        metaColor: .secondaryLabel,
        icon: .currentSongMenu
      )
      cell.selectionStyle = .none
    }
    return cell
  }

  private func resultCell(
    _ tableView: UITableView,
    result: OnlineLyricsSearchResult
  )
    -> UITableViewCell {
    let cell = dequeueCell(tableView)
    cell.set(
      title: result.title,
      subtitle: result.artist.isEmpty ? result.album : result.artist,
      source: result.sourceName,
      duration: Self.durationText(result.duration),
      format: formats[result.id],
      metaColor: .secondaryLabel,
      icon: .currentSongMenu
    )
    cell.selectionStyle = .default
    return cell
  }

  // MARK: Format probes

  private func resetFormatProbes() {
    probeGeneration &+= 1
    probeQueue.removeAll()
    queuedProbeIDs.removeAll()
    formats.removeAll()
    attemptedFormats.removeAll()
    for task in probeTasks.values {
      task.cancel()
    }
    probeTasks.removeAll()
    activeProbes = 0
  }

  private func requestFormatIfNeeded(_ result: OnlineLyricsSearchResult) {
    guard formats[result.id] == nil,
          !attemptedFormats.contains(result.id),
          !queuedProbeIDs.contains(result.id),
          probeTasks[result.id] == nil
    else { return }
    queuedProbeIDs.insert(result.id)
    probeQueue.append(result)
    pumpFormatProbes()
  }

  private func pumpFormatProbes() {
    while activeProbes < Self.maxConcurrentProbes, !probeQueue.isEmpty {
      let result = probeQueue.removeFirst()
      queuedProbeIDs.remove(result.id)
      activeProbes += 1
      let generation = probeGeneration
      probeTasks[result.id] = Task { @MainActor [weak self] in
        let format = await OnlineLyricsService.shared.probeFormat(result)
        guard let self else { return }
        probeTasks[result.id] = nil
        guard generation == probeGeneration else { return }
        activeProbes -= 1
        if let format {
          formats[result.id] = format
          reloadFormatRow(for: result.id)
        } else {
          attemptedFormats.insert(result.id)
        }
        pumpFormatProbes()
      }
    }
  }

  private func reloadFormatRow(for id: String) {
    guard let row = visibleResults.firstIndex(where: { $0.id == id }) else { return }
    let indexPath = IndexPath(row: row, section: Section.results.rawValue)
    guard tableView.indexPathsForVisibleRows?.contains(indexPath) == true else { return }
    tableView.reloadRows(at: [indexPath], with: .none)
  }

  private func statusCell(_ tableView: UITableView) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(
      withIdentifier: Self.statusCellIdentifier
    ) ?? UITableViewCell(style: .default, reuseIdentifier: Self.statusCellIdentifier)

    let text: String
    if !appDelegate.storage.settings.user.isOnlineMode {
      text = L10n.tr("Online lyrics search is unavailable in offline mode.")
    } else if isSearching {
      text = L10n.tr("Searching lyrics…")
    } else if !hasSearched {
      text = L10n.tr("Enter a song or artist to search.")
    } else if !results.isEmpty {
      text = L10n.tr("No results from this source.")
    } else {
      text = L10n.tr("No lyrics found.")
    }

    var content = UIListContentConfiguration.cell()
    content.text = text
    content.textProperties.font = .systemFont(ofSize: 13)
    content.textProperties.color = .secondaryLabel
    content.textProperties.numberOfLines = 0
    cell.contentConfiguration = content
    cell.selectionStyle = .none
    return cell
  }

  private static func durationText(_ milliseconds: Int) -> String {
    guard milliseconds > 0 else { return "" }
    let seconds = milliseconds / 1_000
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
  }
}

// MARK: - LyricsSearchCell

private final class LyricsSearchCell: UITableViewCell {
  static let identifier = "LyricsSearchCell"

  private let iconView = UIImageView()
  private let titleLabel = UILabel()
  private let subtitleLabel = UILabel()
  private let sourceLabel = UILabel()
  private let durationLabel = UILabel()

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)

    contentView.layoutMargins = UIView.defaultMarginCell

    iconView.contentMode = .center
    iconView.tintColor = .secondaryLabel
    iconView.backgroundColor = .tertiarySystemFill
    iconView.layer.cornerRadius = 6
    iconView.clipsToBounds = true

    titleLabel.font = .systemFont(ofSize: 13)
    titleLabel.numberOfLines = 0
    titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    subtitleLabel.font = .systemFont(ofSize: 11)
    subtitleLabel.textColor = .secondaryLabel
    subtitleLabel.numberOfLines = 1
    subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    sourceLabel.font = .systemFont(ofSize: 11)
    sourceLabel.textAlignment = .right
    sourceLabel.numberOfLines = 1
    sourceLabel.setContentHuggingPriority(.required, for: .horizontal)
    sourceLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

    durationLabel.font = .systemFont(ofSize: 11)
    durationLabel.textColor = .secondaryLabel
    durationLabel.textAlignment = .right
    durationLabel.numberOfLines = 1

    let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
    textStack.axis = .vertical
    textStack.spacing = 2

    let metaStack = UIStackView(arrangedSubviews: [sourceLabel, durationLabel])
    metaStack.axis = .vertical
    metaStack.alignment = .trailing
    metaStack.spacing = 1

    for view in [iconView, textStack, metaStack] {
      view.translatesAutoresizingMaskIntoConstraints = false
      contentView.addSubview(view)
    }

    let margins = contentView.layoutMarginsGuide
    NSLayoutConstraint.activate([
      iconView.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
      iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      iconView.widthAnchor.constraint(equalToConstant: 48),
      iconView.heightAnchor.constraint(equalToConstant: 48),

      textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
      textStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      textStack.trailingAnchor.constraint(
        lessThanOrEqualTo: metaStack.leadingAnchor,
        constant: -10
      ),

      metaStack.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
      metaStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func set(
    title: String,
    subtitle: String,
    source: String,
    duration: String,
    format: OnlineLyricsFormat?,
    metaColor: UIColor,
    icon: UIImage
  ) {
    titleLabel.text = title
    subtitleLabel.text = subtitle
    subtitleLabel.isHidden = subtitle.isEmpty

    if let format {
      let text = NSMutableAttributedString(
        string: format.rawValue,
        attributes: [
          .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
          .foregroundColor: format.isWordTimed ? UIColor.tintColor : UIColor.secondaryLabel,
        ]
      )
      if !source.isEmpty {
        text.append(NSAttributedString(
          string: " · \(source)",
          attributes: [
            .font: UIFont.systemFont(ofSize: 11),
            .foregroundColor: UIColor.secondaryLabel,
          ]
        ))
      }
      sourceLabel.attributedText = text
      sourceLabel.isHidden = false
    } else {
      sourceLabel.attributedText = nil
      sourceLabel.text = source
      sourceLabel.textColor = metaColor
      sourceLabel.isHidden = source.isEmpty
    }

    durationLabel.text = duration
    durationLabel.isHidden = duration.isEmpty

    iconView.image = icon.withRenderingMode(.alwaysTemplate)
  }
}
