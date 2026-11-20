//
//  M3UController.swift
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
import UniformTypeIdentifiers
import fmusicKit

/// Owns the File ▸ 导入 M3U 歌单 / 导出 M3U menu commands.
///
/// The macOS app has no playlist context in its menu, so the controller is a singleton
/// targeted directly by `MainMenuBuilder` (no AppDelegate wiring required):
///
/// * import parses the picked file with the shared core `M3UCodec`, matches the entries
///   against the active account's songs with `M3UImportMatcher` (the exact matching rules
///   of the Catalyst importer) and creates a playlist through `LibraryStorage`.
/// * export offers the playlist that is currently opened on the playlist page (found
///   read-only in the view-controller hierarchy) or the current play queue, then writes
///   the file with `M3UCodec.export`.
@MainActor
final class M3UController: NSObject {
  static let shared = M3UController()

  private var storage: PersistentStorage { FmusicKit.shared.storage }
  private var player: PlayerFacade { FmusicKit.shared.player }
  private var library: LibraryStorage { storage.main.library }

  // MARK: - Import

  @objc
  func importM3UPlaylist(_ sender: Any?) {
    guard let accountInfo = storage.settings.accounts.active else {
      presentAlert(
        title: L10n.tr("M3U Import"),
        message: L10n.tr("No account is signed in.")
      )
      return
    }

    let panel = NSOpenPanel()
    panel.title = L10n.tr("Import M3U Playlist")
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    var contentTypes = [UTType]()
    for fileExtension in ["m3u", "m3u8"] {
      if let type = UTType(filenameExtension: fileExtension),
         !contentTypes.contains(type) {
        contentTypes.append(type)
      }
    }
    if !contentTypes.isEmpty {
      panel.allowedContentTypes = contentTypes
    }

    if let window = hostWindow {
      panel.beginSheetModal(for: window) { [weak self] response in
        guard response == .OK, let url = panel.url else { return }
        self?.performImport(from: url, accountInfo: accountInfo)
      }
    } else if panel.runModal() == .OK, let url = panel.url {
      performImport(from: url, accountInfo: accountInfo)
    }
  }

  private func performImport(from url: URL, accountInfo: AccountInfo) {
    let isSecurityScoped = url.startAccessingSecurityScopedResource()
    defer { if isSecurityScoped { url.stopAccessingSecurityScopedResource() } }

    guard let data = try? Data(contentsOf: url),
          let content = String(data: data, encoding: .utf8)
          ?? String(data: data, encoding: .isoLatin1)
    else {
      presentAlert(
        title: L10n.tr("M3U Import"),
        message: L10n.tr("The M3U file could not be read."),
        style: .warning
      )
      return
    }

    let entries = M3UCodec.parse(content)
    guard !entries.isEmpty else {
      presentAlert(
        title: L10n.tr("M3U Import"),
        message: L10n.tr("No tracks found in this M3U file."),
        style: .warning
      )
      return
    }

    let account = library.getAccount(info: accountInfo)
    let songs = library.getSongs(for: account)
    let result = M3UImportMatcher.match(entries: entries, songs: songs)
    guard !result.matches.isEmpty else {
      presentAlert(
        title: L10n.tr("M3U Import"),
        message: L10n.tr("No matching songs found in the library."),
        style: .warning
      )
      return
    }

    let playlist = library.createPlaylist(account: account)
    let fileName = url.deletingPathExtension().lastPathComponent
    playlist.name = fileName.isEmpty ? L10n.tr("Imported Playlist") : fileName
    playlist.append(playables: result.matches)
    library.saveContext()

    // The playlist pages reload on `.librarySongsSynced`; post it so the new playlist
    // shows up immediately after the import.
    FmusicKit.shared.notificationHandler.post(
      name: .librarySongsSynced,
      object: nil,
      userInfo: nil
    )

    presentAlert(
      title: L10n.tr("M3U Import"),
      message: L10n.tr(
        "Imported %d songs. %d entries were skipped.",
        result.matches.count,
        result.unmatchedCount
      )
    )
  }

  // MARK: - Export

  @objc
  func exportM3U(_ sender: Any?) {
    guard storage.settings.accounts.active != nil else {
      presentAlert(
        title: L10n.tr("Export M3U"),
        message: L10n.tr("No account is signed in.")
      )
      return
    }

    if let playlist = currentPlaylist() {
      presentSourceChooser(playlist: playlist)
    } else {
      beginExport(source: .queue)
    }
  }

  /// Sheet that lets the user pick between the opened playlist and the play queue.
  private func presentSourceChooser(playlist: Playlist) {
    let alert = NSAlert()
    alert.messageText = L10n.tr("Export M3U")
    alert.informativeText = L10n.tr("Choose what to export:")
    alert.alertStyle = .informational
    alert.addButton(withTitle: L10n.tr("Export M3U"))
    alert.addButton(withTitle: L10n.tr("Cancel"))

    let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 25))
    popup.addItem(withTitle: L10n.tr("Current Playlist") + ": " + playlist.name)
    popup.addItem(withTitle: L10n.tr("Current Queue"))
    alert.accessoryView = popup

    run(alert) { [weak self] response in
      guard response == .alertFirstButtonReturn else { return }
      let source: M3UExportSource = popup.indexOfSelectedItem == 0
        ? .playlist(playlist)
        : .queue
      self?.beginExport(source: source)
    }
  }

  private func beginExport(source: M3UExportSource) {
    let playables = playables(for: source)
    guard !playables.isEmpty else {
      presentAlert(
        title: L10n.tr("Export M3U"),
        message: source.emptyMessage,
        style: .warning
      )
      return
    }

    let content = M3UCodec.export(playables: playables)
    // `M3UCodec.export` silently drops playables without a URL (radios, streams), so a
    // header-only file means there was nothing exportable after all.
    let exportedEntryCount = content
      .components(separatedBy: .newlines)
      .filter { !$0.isEmpty && !$0.hasPrefix("#") }
      .count
    guard exportedEntryCount > 0 else {
      presentAlert(
        title: L10n.tr("Export M3U"),
        message: source.emptyMessage,
        style: .warning
      )
      return
    }

    let panel = NSSavePanel()
    panel.title = L10n.tr("Export M3U")
    panel.canCreateDirectories = true
    panel.nameFieldStringValue = Self.sanitizedFileName(source.fileName) + ".m3u8"
    if let type = UTType(filenameExtension: "m3u8") {
      panel.allowedContentTypes = [type]
    }

    if let window = hostWindow {
      panel.beginSheetModal(for: window) { [weak self] response in
        guard response == .OK, let url = panel.url else { return }
        self?.write(content: content, to: url)
      }
    } else if panel.runModal() == .OK, let url = panel.url {
      write(content: content, to: url)
    }
  }

  private func write(content: String, to url: URL) {
    do {
      try content.write(to: url, atomically: true, encoding: .utf8)
      presentAlert(
        title: L10n.tr("Export M3U"),
        message: L10n.tr("The M3U file was saved to %@.", url.path)
      )
    } catch {
      presentAlert(
        title: L10n.tr("Export M3U"),
        message: error.localizedDescription,
        style: .warning
      )
    }
  }

  private func playables(for source: M3UExportSource) -> [AbstractPlayable] {
    switch source {
    case let .playlist(playlist):
      let items = library.getPlaylistItems(playlist: playlist)
      return items.compactMap {
        PlaylistItem(library: library, managedObject: $0).playable
      }
    case .queue:
      var queue = player.getAllPrevQueueItems()
      if let current = player.currentlyPlaying {
        queue.append(current)
      }
      queue.append(contentsOf: player.getAllNextQueueItems())
      return queue
    }
  }

  private static func sanitizedFileName(_ name: String) -> String {
    let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
      .union(.newlines)
      .union(.controlCharacters)
    let cleaned = name
      .components(separatedBy: invalidCharacters)
      .joined(separator: "-")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty ? "Playlist" : cleaned
  }

  // MARK: - Current playlist

  /// The playlist opened on the playlist page, if any.
  ///
  /// The playlist page lives inside several container view controllers and does not expose
  /// its playlist to the rest of the app, so it is found read-only by walking the view
  /// controller hierarchy of the open windows (no changes to the playlist pages needed).
  /// `Mirror` is used because the detail controller keeps its playlist in a private stored
  /// property.
  private func currentPlaylist() -> Playlist? {
    for window in NSApp.windows {
      guard let root = window.contentViewController else { continue }
      if let playlist = Self.findPlaylist(in: root) {
        return playlist
      }
    }
    return nil
  }

  private static func findPlaylist(in controller: NSViewController) -> Playlist? {
    if String(describing: type(of: controller)).hasSuffix("PlaylistDetailViewController"),
       let playlist = Mirror(reflecting: controller).children
       .first(where: { $0.label == "playlist" })?.value as? Playlist {
      return playlist
    }
    for child in controller.children {
      if let playlist = findPlaylist(in: child) {
        return playlist
      }
    }
    if let presented = controller.presentedViewControllers {
      for child in presented {
        if let playlist = findPlaylist(in: child) {
          return playlist
        }
      }
    }
    if let splitView = controller as? NSSplitViewController {
      for item in splitView.splitViewItems {
        if let playlist = findPlaylist(in: item.viewController) {
          return playlist
        }
      }
    }
    return nil
  }

  // MARK: - Alerts & panels

  private var hostWindow: NSWindow? {
    if let mainWindow = AppDelegate.sharedAppDelegate?.mainWindowController?.window,
       mainWindow.isVisible {
      return mainWindow
    }
    return NSApp.mainWindow ?? NSApp.keyWindow
  }

  private func presentAlert(
    title: String,
    message: String,
    style: NSAlert.Style = .informational
  ) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = style
    alert.addButton(withTitle: L10n.tr("OK"))
    run(alert) { _ in }
  }

  private func run(
    _ alert: NSAlert,
    completion: @escaping (NSApplication.ModalResponse) -> Void
  ) {
    if let window = hostWindow {
      alert.beginSheetModal(for: window, completionHandler: completion)
    } else {
      completion(alert.runModal())
    }
  }
}

// MARK: - M3UExportSource

/// What an 导出 M3U command exports.
private enum M3UExportSource {
  case playlist(Playlist)
  case queue

  var fileName: String {
    switch self {
    case let .playlist(playlist):
      return playlist.name.isEmpty ? L10n.tr("Playlist") : playlist.name
    case .queue:
      return L10n.tr("Current Queue")
    }
  }

  var emptyMessage: String {
    switch self {
    case .playlist:
      return L10n.tr("This playlist has no songs to export.")
    case .queue:
      return L10n.tr("The current queue has no songs to export.")
    }
  }
}
