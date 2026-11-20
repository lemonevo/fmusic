//
//  LibraryTableCells.swift
//  fmusic-macOS
//
//  Shared table cell views and artwork lookups for the AppKit library pages
//  (search, favorite songs, playlists, queue and now playing).
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

// MARK: - LMLibraryArtwork

/// Artwork lookups shared by the library pages. Keeps the theme/artwork display
/// preferences in one place so every new page renders the same cached images.
@MainActor
enum LMLibraryArtwork {
  static func image(
    for entity: AbstractLibraryEntity,
    setting: AccountSetting
  )
    -> NSImage {
    ArtworkImageLoader.image(
      for: entity,
      themePreference: setting.themePreference,
      artworkDisplayPreference: setting.artworkDisplayPreference
    )
  }

  /// Playlists are not library entities: render their first artwork item, or fall
  /// back to the generated playlist placeholder.
  static func image(
    for playlist: Playlist,
    setting: AccountSetting
  )
    -> NSImage {
    if let playable = playlist.artworkItems.first?.playable {
      return ArtworkImageLoader.image(
        for: playable,
        themePreference: setting.themePreference,
        artworkDisplayPreference: setting.artworkDisplayPreference
      )
    }
    return ArtworkImageLoader.generatedImage(
      theme: setting.themePreference,
      artworkType: .playlist
    )
  }
}

// MARK: - LMTextCellView

/// Single-line text cell used by the flat library tables.
@MainActor
final class LMTextCellView: NSTableCellView {
  private let label = NSTextField(labelWithString: "")

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.lineBreakMode = .byTruncatingTail
    addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
      label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
    self.textField = label
  }

  required init?(coder: NSCoder) {
    nil
  }

  func configure(
    text: String,
    font: NSFont,
    color: NSColor,
    alignment: NSTextAlignment = .left,
    lineBreakMode: NSLineBreakMode = .byTruncatingTail
  ) {
    label.stringValue = text
    label.font = font
    label.textColor = color
    label.alignment = alignment
    label.lineBreakMode = lineBreakMode
  }
}

// MARK: - LMArtworkCellView

/// Small square artwork cell (song/album/artist rows).
@MainActor
final class LMArtworkCellView: NSTableCellView {
  private let artworkView = NSImageView()
  private var widthConstraint: NSLayoutConstraint!
  private var heightConstraint: NSLayoutConstraint!

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    artworkView.translatesAutoresizingMaskIntoConstraints = false
    artworkView.imageScaling = .scaleProportionallyUpOrDown
    artworkView.wantsLayer = true
    artworkView.layer?.cornerRadius = 4
    artworkView.layer?.masksToBounds = true
    addSubview(artworkView)
    widthConstraint = artworkView.widthAnchor.constraint(equalToConstant: 32)
    heightConstraint = artworkView.heightAnchor.constraint(equalToConstant: 32)
    NSLayoutConstraint.activate([
      widthConstraint,
      heightConstraint,
      artworkView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
      artworkView.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
    self.imageView = artworkView
  }

  required init?(coder: NSCoder) {
    nil
  }

  func display(image: NSImage?, size: CGFloat = 32) {
    widthConstraint.constant = size
    heightConstraint.constant = size
    artworkView.layer?.cornerRadius = size <= 32 ? 4 : 6
    artworkView.image = image
  }
}

// MARK: - LMPlayableRowCellView

/// Apple Music style two-line row (artwork, title, subtitle, trailing text).
@MainActor
final class LMPlayableRowCellView: NSTableCellView {
  private let artworkView = NSImageView()
  private let titleLabel = NSTextField(labelWithString: "")
  private let subtitleLabel = NSTextField(labelWithString: "")
  private let trailingLabel = NSTextField(labelWithString: "")
  private var artworkWidthConstraint: NSLayoutConstraint!
  private var artworkHeightConstraint: NSLayoutConstraint!
  private var titleLeadingConstraint: NSLayoutConstraint!

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    artworkView.translatesAutoresizingMaskIntoConstraints = false
    artworkView.imageScaling = .scaleProportionallyUpOrDown
    artworkView.wantsLayer = true
    artworkView.layer?.cornerRadius = 5
    artworkView.layer?.masksToBounds = true

    titleLabel.font = MacTheme.titleFont
    titleLabel.lineBreakMode = .byTruncatingTail
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    subtitleLabel.font = MacTheme.secondaryFont
    subtitleLabel.textColor = MacTheme.secondaryTextColor
    subtitleLabel.lineBreakMode = .byTruncatingTail
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
    trailingLabel.font = MacTheme.tabularBodyFont
    trailingLabel.textColor = MacTheme.secondaryTextColor
    trailingLabel.alignment = .right
    trailingLabel.lineBreakMode = .byTruncatingTail
    trailingLabel.translatesAutoresizingMaskIntoConstraints = false

    addSubview(artworkView)
    addSubview(titleLabel)
    addSubview(subtitleLabel)
    addSubview(trailingLabel)

    artworkWidthConstraint = artworkView.widthAnchor.constraint(equalToConstant: 32)
    artworkHeightConstraint = artworkView.heightAnchor.constraint(equalToConstant: 32)
    titleLeadingConstraint = titleLabel.leadingAnchor.constraint(
      equalTo: artworkView.trailingAnchor,
      constant: 10
    )

    NSLayoutConstraint.activate([
      artworkWidthConstraint,
      artworkHeightConstraint,
      artworkView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      artworkView.centerYAnchor.constraint(equalTo: centerYAnchor),

      titleLeadingConstraint,
      titleLabel.trailingAnchor.constraint(equalTo: trailingLabel.leadingAnchor, constant: -8),
      titleLabel.bottomAnchor.constraint(equalTo: centerYAnchor, constant: -1),

      subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
      subtitleLabel.topAnchor.constraint(equalTo: centerYAnchor, constant: 1),

      trailingLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
      trailingLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
      trailingLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 90),
    ])

    self.imageView = artworkView
    self.textField = titleLabel
  }

  required init?(coder: NSCoder) {
    nil
  }

  func configure(
    image: NSImage?,
    title: String,
    subtitle: String?,
    trailing: String?,
    artworkSize: CGFloat = 32,
    showsArtwork: Bool = true
  ) {
    artworkView.isHidden = !showsArtwork
    if showsArtwork {
      artworkWidthConstraint.constant = artworkSize
      artworkHeightConstraint.constant = artworkSize
      titleLeadingConstraint.constant = 10
    } else {
      artworkWidthConstraint.constant = 0
      artworkHeightConstraint.constant = 0
      titleLeadingConstraint.constant = 2
    }
    artworkView.image = image
    titleLabel.stringValue = title
    subtitleLabel.stringValue = subtitle ?? ""
    subtitleLabel.isHidden = (subtitle?.isEmpty ?? true)
    trailingLabel.stringValue = trailing ?? ""
    trailingLabel.isHidden = (trailing?.isEmpty ?? true)
  }
}
