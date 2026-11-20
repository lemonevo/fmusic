//
//  LyricsSearchPreviewPane.swift
//  fmusic-macOS
//
//  Read-only preview of one online lyrics search result inside the lyrics search
//  page. Shows the converted lyric lines (including translations), the detected
//  native format and an "Apply Lyrics" action.
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

/// Self-contained preview column of the lyrics search page.
///
/// The pane owns no networking: the controller feeds it a finished
/// `OnlineLyricsMatch` and gets an `onApply` callback when the user presses the
/// apply button.
@MainActor
final class LyricsSearchPreviewPane: NSView {
  /// Called when "Apply Lyrics" is pressed while a result is being previewed.
  var onApply: (() -> Void)?

  private let titleLabel = NSTextField(labelWithString: "")
  private let metaLabel = NSTextField(labelWithString: "")
  private let formatLabel = NSTextField(labelWithString: "")
  private let scrollView = NSScrollView()
  private let textView = NSTextView()
  private let statusLabel = NSTextField(wrappingLabelWithString: "")
  private let spinner = NSProgressIndicator()
  private let applyButton = NSButton()

  // MARK: - Init

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    configure()
  }

  required init?(coder: NSCoder) {
    nil
  }

  // MARK: - Layout

  private func configure() {
    wantsLayer = true

    titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
    titleLabel.lineBreakMode = .byTruncatingTail
    titleLabel.maximumNumberOfLines = 1
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    metaLabel.font = MacTheme.secondaryFont
    metaLabel.textColor = MacTheme.secondaryTextColor
    metaLabel.lineBreakMode = .byTruncatingTail
    metaLabel.maximumNumberOfLines = 1
    metaLabel.translatesAutoresizingMaskIntoConstraints = false

    formatLabel.font = MacTheme.secondaryFont
    formatLabel.textColor = MacTheme.secondaryTextColor
    formatLabel.lineBreakMode = .byTruncatingTail
    formatLabel.maximumNumberOfLines = 1
    formatLabel.translatesAutoresizingMaskIntoConstraints = false

    configureTextView()
    scrollView.documentView = textView
    scrollView.hasVerticalScroller = true
    scrollView.drawsBackground = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    statusLabel.font = MacTheme.bodyFont
    statusLabel.textColor = MacTheme.secondaryTextColor
    statusLabel.alignment = .center
    statusLabel.translatesAutoresizingMaskIntoConstraints = false

    spinner.style = .spinning
    spinner.controlSize = .small
    spinner.isDisplayedWhenStopped = false
    spinner.translatesAutoresizingMaskIntoConstraints = false

    applyButton.title = L10n.tr("Apply Lyrics")
    applyButton.bezelStyle = .rounded
    applyButton.target = self
    applyButton.action = #selector(applyClicked)
    applyButton.translatesAutoresizingMaskIntoConstraints = false
    applyButton.isEnabled = false

    addSubview(titleLabel)
    addSubview(metaLabel)
    addSubview(formatLabel)
    addSubview(scrollView)
    addSubview(spinner)
    addSubview(statusLabel)
    addSubview(applyButton)

    NSLayoutConstraint.activate([
      titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 2),
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
      titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),

      metaLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
      metaLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
      metaLabel.trailingAnchor.constraint(equalTo: trailingAnchor),

      formatLabel.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: 2),
      formatLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
      formatLabel.trailingAnchor.constraint(equalTo: trailingAnchor),

      scrollView.topAnchor.constraint(equalTo: formatLabel.bottomAnchor, constant: 10),
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),

      statusLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
      statusLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
      statusLabel.widthAnchor.constraint(lessThanOrEqualTo: scrollView.widthAnchor, constant: -24),

      spinner.centerXAnchor.constraint(equalTo: statusLabel.centerXAnchor),
      spinner.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -8),

      scrollView.bottomAnchor.constraint(equalTo: applyButton.topAnchor, constant: -10),
      applyButton.trailingAnchor.constraint(equalTo: trailingAnchor),
      applyButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
      applyButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
    ])

    showPlaceholder()
  }

  private func configureTextView() {
    textView.isEditable = false
    textView.isSelectable = true
    textView.drawsBackground = false
    textView.textContainerInset = NSSize(width: 2, height: 6)
    textView.minSize = NSSize(width: 0, height: 0)
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    textView.textContainer?.containerSize = NSSize(
      width: 0,
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.textContainer?.widthTracksTextView = true
  }

  // MARK: - States

  /// Nothing selected yet / no usable results.
  func showPlaceholder() {
    renderHeader(title: L10n.tr("Lyrics Preview"), meta: "", format: "")
    applyButton.isEnabled = false
    scrollView.isHidden = true
    spinner.stopAnimation(nil)
    spinner.isHidden = true
    statusLabel.stringValue = L10n.tr("Enter a song or artist to search.")
    statusLabel.isHidden = false
  }

  /// A result is selected and its lyrics are being fetched.
  func showLoading(for result: OnlineLyricsSearchResult) {
    renderHeader(
      title: result.title,
      meta: Self.metaText(for: result),
      format: ""
    )
    applyButton.isEnabled = false
    scrollView.isHidden = true
    statusLabel.stringValue = L10n.tr("Loading lyrics…")
    statusLabel.isHidden = false
    spinner.isHidden = false
    spinner.startAnimation(nil)
  }

  /// Fetching the lyrics failed (provider error, no lines, offline, …).
  func showFailure(
    for result: OnlineLyricsSearchResult,
    message: String = L10n.tr("Could not load lyrics for this result.")
  ) {
    renderHeader(
      title: result.title,
      meta: Self.metaText(for: result),
      format: ""
    )
    applyButton.isEnabled = false
    scrollView.isHidden = true
    spinner.stopAnimation(nil)
    spinner.isHidden = true
    statusLabel.stringValue = message
    statusLabel.isHidden = false
  }

  /// Fetched lyrics ready to preview and apply.
  func show(match: OnlineLyricsMatch, result: OnlineLyricsSearchResult) {
    renderHeader(
      title: result.title,
      meta: Self.metaText(for: result),
      format: Self.formatText(for: match)
    )
    textView.textStorage?.setAttributedString(Self.attributedLyrics(match))
    scrollView.isHidden = false
    spinner.stopAnimation(nil)
    spinner.isHidden = true
    statusLabel.isHidden = true
    applyButton.isEnabled = true
    if let clipView = textView.enclosingScrollView?.contentView {
      clipView.scroll(to: .zero)
      textView.enclosingScrollView?.reflectScrolledClipView(clipView)
    }
  }

  // MARK: - Content

  private func renderHeader(title: String, meta: String, format: String) {
    titleLabel.stringValue = title
    metaLabel.stringValue = meta
    metaLabel.isHidden = meta.isEmpty
    formatLabel.stringValue = format
    formatLabel.isHidden = format.isEmpty
  }

  @objc
  private func applyClicked() {
    onApply?()
  }

  // MARK: - Formatting

  private static func metaText(for result: OnlineLyricsSearchResult) -> String {
    var parts = [result.artist, result.album]
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    if let duration = durationText(result.duration) {
      parts.append(duration)
    }
    parts.append(result.sourceName)
    return parts.joined(separator: " · ")
  }

  private static func formatText(for match: OnlineLyricsMatch) -> String {
    var parts = [
      match.format.rawValue,
      match.isWordTimed ? L10n.tr("Word timed") : L10n.tr("Synced lyrics"),
    ]
    if match.hasTranslation {
      parts.append(L10n.tr("Bilingual"))
    }
    return parts.joined(separator: " · ")
  }

  private static func durationText(_ milliseconds: Int) -> String? {
    guard milliseconds > 0 else { return nil }
    let seconds = milliseconds / 1_000
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
  }

  private static func attributedLyrics(_ match: OnlineLyricsMatch) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 5
    paragraph.paragraphSpacing = 4

    let output = NSMutableAttributedString()
    for line in match.lines {
      let isTranslation = line.isTranslation
      output.append(NSAttributedString(
        string: line.text + "\n",
        attributes: [
          .font: NSFont.systemFont(ofSize: isTranslation ? 12 : 15),
          .foregroundColor: isTranslation ? NSColor.secondaryLabelColor : NSColor.labelColor,
          .paragraphStyle: paragraph,
        ]
      ))
    }
    return output
  }
}
