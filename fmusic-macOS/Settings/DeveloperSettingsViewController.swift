//
//  DeveloperSettingsViewController.swift
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
import fmusicKit

/// 开发者: diagnostics, data/cache folder shortcuts and default artwork generation.
///
/// This page ports the Catalyst `DeveloperView` (which only offers "Generate Default
/// Artworks") and adds the support actions that are useful on the Mac: a JSON diagnostics
/// dump (same payload as Support ▸ Export log), shortcuts to the shared data folder and the
/// artwork cache, a diagnostics summary and the default artwork generator.
@MainActor
final class DeveloperSettingsViewController: SettingsPageViewController {
  private var previewImageViews: [NSImageView] = []

  init() {
    super.init(title: L10n.tr("Developer"))
  }

  required init?(coder: NSCoder) {
    nil
  }

  private var storage: PersistentStorage { FmusicKit.shared.storage }
  private var library: LibraryStorage { storage.main.library }
  private var cacheFileManager: CacheFileManager { .shared }

  private var activeAccountInfo: AccountInfo? { storage.settings.accounts.active }

  // MARK: - Form

  override func buildForm() {
    addButton(title: L10n.tr("Copy Diagnostics")) { [weak self] in
      self?.copyDiagnostics()
    }
    addButton(title: L10n.tr("Open Data Folder")) { [weak self] in
      self?.openDataFolder()
    }
    addButton(title: L10n.tr("Open Artwork Cache Folder")) { [weak self] in
      self?.openArtworkCacheFolder()
    }
    addButton(title: L10n.tr("Generate Default Artworks")) { [weak self] in
      self?.generateDefaultArtworks()
    }

    addSection(
      header: L10n.tr("Diagnostics"),
      footer: L10n.tr("The diagnostics contain the account, library counts, player state and the latest events."),
      rows: makeDiagnosticsRows()
    )

    addSection(
      header: L10n.tr("Default Artworks"),
      footer: L10n.tr(
        "Regenerates the placeholder artwork for every theme, artwork type and light/dark mode from the shared core artwork definitions, writes the PNG files to the same cache location and file names the Catalyst app uses, and clears the in-memory artwork cache. The macOS UI resolves its placeholders from the bundled asset catalog, so the regenerated files are mainly a best-effort parity/debugging aid."
      ),
      rows: [makeArtworkPreviewRow()]
    )
  }

  // MARK: - Diagnostics

  private func makeDiagnosticsRows() -> [NSView] {
    var rows = [NSView]()

    let credentials = storage.settings.accounts.activeSetting.read.loginCredentials
    rows.append(makeValueRow(
      title: L10n.tr("Account"),
      value: credentials?.username ?? L10n.tr("No account is signed in.")
    ))
    rows.append(makeValueRow(
      title: L10n.tr("Server"),
      value: credentials?.serverUrl ?? "—"
    ))

    if let accountInfo = activeAccountInfo {
      let account = library.getAccount(info: accountInfo)
      let counts: [(String, Int)] = [
        (L10n.tr("Songs"), library.getSongCount(for: account)),
        (L10n.tr("Albums"), library.getAlbumCount(for: account)),
        (L10n.tr("Artists"), library.getArtistCount(for: account)),
        (L10n.tr("Genres"), library.getGenreCount(for: account)),
        (L10n.tr("Playlists"), library.getPlaylistCount(for: account)),
        (L10n.tr("Podcasts"), library.getPodcastCount(for: account)),
        (L10n.tr("Radios"), library.getRadioCount(for: account)),
      ]
      for (title, count) in counts {
        rows.append(makeValueRow(title: title, value: String(count)))
      }
    }

    let version = Bundle.main.object(
      forInfoDictionaryKey: "CFBundleShortVersionString"
    ) as? String ?? "—"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    rows.append(makeValueRow(title: L10n.tr("Version"), value: version))
    rows.append(makeValueRow(title: L10n.tr("Build Number"), value: build))
    rows.append(makeValueRow(
      title: L10n.tr("Data Folder"),
      value: CoreDataPersistentManager.storeDirectoryURL.path
    ))
    rows.append(makeValueRow(
      title: L10n.tr("Database Path"),
      value: CoreDataPersistentManager.storeURL.path
    ))
    if let accountInfo = activeAccountInfo,
       let artworkPath = cacheFileManager
       .getOrCreateAbsoluteArtworksDirectory(for: accountInfo)?.path {
      rows.append(makeValueRow(title: L10n.tr("Artwork Cache"), value: artworkPath))
    }
    return rows
  }

  // MARK: - Actions

  private func copyDiagnostics() {
    let json = LogData.collectInformation(fmusicData: FmusicKit.shared).asJSONString()
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(json, forType: .string)
    presentAlert(
      title: L10n.tr("Copy Diagnostics"),
      message: L10n.tr("Diagnostic information copied to the clipboard.")
    )
  }

  private func openDataFolder() {
    let folderURL = CoreDataPersistentManager.storeDirectoryURL
    try? FileManager.default.createDirectory(
      at: folderURL,
      withIntermediateDirectories: true
    )
    NSWorkspace.shared.open(folderURL)
  }

  private func openArtworkCacheFolder() {
    guard let accountInfo = activeAccountInfo,
          let folderURL = cacheFileManager
          .getOrCreateAbsoluteArtworksDirectory(for: accountInfo)
    else {
      presentAlert(
        title: L10n.tr("Open Artwork Cache Folder"),
        message: L10n.tr("No account is signed in.")
      )
      return
    }
    NSWorkspace.shared.open(folderURL)
  }

  // MARK: - Default artworks

  private func generateDefaultArtworks() {
    var written = 0
    var failed = 0
    for theme in ThemePreference.allCases {
      for artworkType in ArtworkType.allCases {
        for lightDarkMode in LightDarkModeType.allCases {
          let fileName = theme.description + artworkType.description + lightDarkMode
            .description + ".png"
          guard let relativeURL = URL(string: fileName),
                let absoluteURL = cacheFileManager
                .getAbsolutefmusicPath(relFilePath: relativeURL),
                let image = Self.makeDefaultArtwork(
                  theme: theme,
                  artworkType: artworkType,
                  lightDarkMode: lightDarkMode
                ),
                let data = image.platformPNGData()
          else {
            failed += 1
            continue
          }
          do {
            try cacheFileManager.writeDataExcludedFromBackup(
              data: data,
              to: absoluteURL,
              accountInfo: nil
            )
            written += 1
          } catch {
            failed += 1
          }
        }
      }
    }
    ArtworkImageLoader.clearCache()
    updateArtworkPreviews()
    presentAlert(
      title: L10n.tr("Generate Default Artworks"),
      message: L10n.tr(
        "Generated %d artworks. %d could not be written.",
        written,
        failed
      ),
      style: failed > 0 ? .warning : .informational
    )
  }

  /// One placeholder artwork, rendered with AppKit exactly like the Catalyst
  /// `UIImage.generateArtwork` helper (grey light/dark background plus a theme coloured
  /// artwork type icon, or the inverted colours for playlists).
  ///
  /// The core's `ArtworkImageLoader.generatedImage` reads pre-rendered imagesets from the
  /// package catalog; those imagesets only ship 3x PNGs, which `actool` drops for the
  /// macOS SDK, so on the Mac the helper yields an empty image. Rendering the placeholder
  /// here keeps the developer action useful (and independent of the asset catalog).
  private static func makeDefaultArtwork(
    theme: ThemePreference,
    artworkType: ArtworkType,
    lightDarkMode: LightDarkModeType
  )
    -> NSImage? {
    let side = CGFloat(ArtworkIconSizeType.defaultSize)
    guard side > 0 else { return nil }

    let largeIconTypes: [ArtworkType] = [.album, .artist, .folder, .genre, .podcast, .radio]
    let iconSizeType: ArtworkIconSizeType = largeIconTypes.contains(artworkType) ? .big : .small
    let switchColors = artworkType == .playlist
    let grayScale: CGFloat = lightDarkMode == .light ? 0.85 : 0.15
    let grayColor = NSColor(white: grayScale, alpha: 1)
    let backgroundColor = switchColors ? theme.asColor : grayColor
    let iconTintColor = switchColors ? grayColor : theme.asColor
    let iconInset = iconSizeType.rawValue
    let icon = artworkType.image.asPlatformImage.platformTinted(with: iconTintColor)

    return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
      backgroundColor.setFill()
      rect.fill()
      icon.draw(
        in: rect.insetBy(dx: iconInset, dy: iconInset),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
      )
      return true
    }
  }

  /// A horizontal strip with one preview per artwork type for the active theme, so the
  /// generated placeholders are visible without opening a library page.
  private func makeArtworkPreviewRow() -> NSView {
    let stack = NSStackView()
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 6
    stack.translatesAutoresizingMaskIntoConstraints = false

    previewImageViews = []
    for artworkType in ArtworkType.allCases {
      let imageView = NSImageView()
      imageView.imageScaling = .scaleProportionallyUpOrDown
      imageView.toolTip = artworkType.description
      imageView.wantsLayer = true
      imageView.layer?.cornerRadius = 4
      imageView.layer?.masksToBounds = true
      imageView.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        imageView.widthAnchor.constraint(equalToConstant: 40),
        imageView.heightAnchor.constraint(equalToConstant: 40),
      ])
      stack.addArrangedSubview(imageView)
      previewImageViews.append(imageView)
    }
    updateArtworkPreviews()
    return SettingsRowView(title: "", control: stack)
  }

  private func updateArtworkPreviews() {
    let theme = storage.settings.accounts.activeSetting.read.themePreference
    for (index, artworkType) in ArtworkType.allCases.enumerated() {
      guard index < previewImageViews.count else { continue }
      previewImageViews[index].image = Self.makeDefaultArtwork(
        theme: theme,
        artworkType: artworkType,
        lightDarkMode: .light
      )
    }
  }

  // MARK: - Alerts

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
    if let window = view.window {
      alert.beginSheetModal(for: window)
    } else {
      alert.runModal()
    }
  }
}
