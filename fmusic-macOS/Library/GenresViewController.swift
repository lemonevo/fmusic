//
//  GenresViewController.swift
//  fmusic-macOS
//
//  `.genres` — simple genre list based on the shared `LibraryStorage.getGenres`.
//

import AppKit
import fmusicKit

@MainActor
final class GenresViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
  private let tableView = NSTableView()
  private let scrollView = NSScrollView()
  private let titleLabel = NSTextField(labelWithString: L10n.tr("Genres"))
  private var genres: [Genre] = []
  private let columnID = NSUserInterfaceItemIdentifier("genreColumn")
  private let cellID = NSUserInterfaceItemIdentifier("genreCell")

  override func loadView() {
    let root = ThemedBackgroundView()
    titleLabel.font = MacTheme.largeTitleFont
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    let column = NSTableColumn(identifier: columnID)
    column.resizingMask = .autoresizingMask
    tableView.addTableColumn(column)
    tableView.headerView = nil
    tableView.rowHeight = 44
    tableView.style = .plain
    tableView.backgroundColor = .clear
    tableView.dataSource = self
    tableView.delegate = self

    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.drawsBackground = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    root.addSubview(titleLabel)
    root.addSubview(scrollView)
    NSLayoutConstraint.activate([
      titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
      titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
      scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
      scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
    ])
    view = root
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    NotificationCenter.default.addObserver(
      self, selector: #selector(reloadGenres), name: .librarySongsSynced, object: nil
    )
    NotificationCenter.default.addObserver(
      self, selector: #selector(reloadGenres), name: .accountActiveChanged, object: nil
    )
    reloadGenres()
  }

  @objc private func reloadGenres() {
    let storage = FmusicKit.shared.storage
    guard let accountInfo = storage.settings.accounts.active else {
      genres = []
      tableView.reloadData()
      return
    }
    let library = storage.main.library
    genres = library.getGenres(for: library.getAccount(info: accountInfo))
    tableView.reloadData()
  }

  func numberOfRows(in tableView: NSTableView) -> Int { genres.count }

  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    let rowView = ThemedRowView()
    rowView.cornerRadius = 6
    rowView.horizontalInset = 10
    return rowView
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let cell = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView
      ?? NSTableCellView()
    cell.identifier = cellID
    let field: NSTextField
    if let existing = cell.textField {
      field = existing
    } else {
      field = NSTextField(labelWithString: "")
      field.translatesAutoresizingMaskIntoConstraints = false
      cell.addSubview(field)
      NSLayoutConstraint.activate([
        field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 16),
        field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
      ])
      cell.textField = field
    }
    let genre = genres[row]
    field.stringValue = "\(genre.name) — \(genre.albumCount) \(L10n.tr("Albums"))"
    return cell
  }
}
