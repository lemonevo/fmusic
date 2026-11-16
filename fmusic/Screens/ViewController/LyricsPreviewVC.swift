//
//  LyricsPreviewVC.swift
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

// MARK: - LyricsPreviewVC

/// Shows the lyrics of a search result and applies them to the current song.
class LyricsPreviewVC: UIViewController {
  private let result: OnlineLyricsSearchResult
  private var match: OnlineLyricsMatch?
  private var loadTask: Task<(), Never>?

  private let titleLabel = UILabel()
  private let detailLabel = UILabel()
  private let metaLabel = UILabel()
  private let targetLabel = UILabel()
  private let textView = UITextView()
  private let spinner = UIActivityIndicatorView(style: .medium)
  private let statusLabel = UILabel()
  private let applyButton = UIButton(type: .system)

  init(result: OnlineLyricsSearchResult) {
    self.result = result
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var title: String? {
    get { L10n.tr("Lyrics Preview") }
    set {}
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    configureHeader()
    configureContent()
    configureApplyButton()
    loadLyrics()
  }

  override func viewIsAppearing(_ animated: Bool) {
    super.viewIsAppearing(animated)
    extendSafeAreaToAccountForMiniPlayer()
    updateTargetLabel()
  }

  // MARK: Layout

  private func configureHeader() {
    titleLabel.text = result.title
    titleLabel.font = .preferredFont(forTextStyle: .title3)
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.numberOfLines = 2

    detailLabel.text = [result.artist, result.album]
      .filter { !$0.isEmpty }
      .joined(separator: " · ")
    detailLabel.font = .preferredFont(forTextStyle: .subheadline)
    detailLabel.adjustsFontForContentSizeCategory = true
    detailLabel.textColor = .secondaryLabel
    detailLabel.numberOfLines = 1

    metaLabel.font = .preferredFont(forTextStyle: .caption1)
    metaLabel.adjustsFontForContentSizeCategory = true
    metaLabel.textColor = .secondaryLabel
    metaLabel.numberOfLines = 1

    let header = UIStackView(arrangedSubviews: [titleLabel, detailLabel, metaLabel])
    header.axis = .vertical
    header.spacing = 3
    header.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(header)
    view.addSubview(spinner)
    view.addSubview(statusLabel)
    view.addSubview(textView)
    view.addSubview(targetLabel)
    view.addSubview(applyButton)

    header.translatesAutoresizingMaskIntoConstraints = false
    spinner.translatesAutoresizingMaskIntoConstraints = false
    statusLabel.translatesAutoresizingMaskIntoConstraints = false
    textView.translatesAutoresizingMaskIntoConstraints = false
    targetLabel.translatesAutoresizingMaskIntoConstraints = false
    applyButton.translatesAutoresizingMaskIntoConstraints = false

    let guide = view.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
      header.topAnchor.constraint(equalTo: guide.topAnchor, constant: 18),
      header.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
      header.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -20),

      spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -24),
      statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 8),
      statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

      textView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 14),
      textView.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
      textView.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -20),
      textView.bottomAnchor.constraint(equalTo: targetLabel.topAnchor, constant: -12),

      targetLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
      targetLabel.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -20),
      targetLabel.bottomAnchor.constraint(equalTo: applyButton.topAnchor, constant: -10),

      applyButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
      applyButton.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -20),
      applyButton.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -16),
      applyButton.heightAnchor.constraint(equalToConstant: 40),
    ])
  }

  private func configureContent() {
    textView.isEditable = false
    textView.isSelectable = true
    textView.alwaysBounceVertical = true
    textView.backgroundColor = .clear
    textView.textContainerInset = .zero
    textView.textContainer.lineFragmentPadding = 0
    textView.isHidden = true

    statusLabel.font = .preferredFont(forTextStyle: .subheadline)
    statusLabel.adjustsFontForContentSizeCategory = true
    statusLabel.textColor = .secondaryLabel
    statusLabel.text = L10n.tr("Loading lyrics…")
    statusLabel.numberOfLines = 0

    targetLabel.font = .preferredFont(forTextStyle: .caption1)
    targetLabel.adjustsFontForContentSizeCategory = true
    targetLabel.textColor = .secondaryLabel
    targetLabel.numberOfLines = 2
    updateTargetLabel()

    spinner.startAnimating()
  }

  private func configureApplyButton() {
    var configuration = UIButton.Configuration.filled()
    configuration.title = L10n.tr("Apply Lyrics")
    configuration.cornerStyle = .medium
    applyButton.configuration = configuration
    applyButton.isEnabled = false
    applyButton.addTarget(self, action: #selector(applyPressed), for: .touchUpInside)
  }

  private func updateTargetLabel() {
    guard let song = appDelegate.player.currentlyPlaying?.asSong else {
      targetLabel.textColor = .secondaryLabel
      targetLabel.text = L10n.tr("Play a song to apply lyrics.")
      return
    }
    let artist = song.artist?.name ?? ""
    let title = artist.isEmpty ? song.title : "\(song.title) — \(artist)"
    if mismatchDetail(for: song) != nil {
      targetLabel.textColor = .systemOrange
      targetLabel.text = L10n.tr("Apply to: %@ (does not match this lyric)", title)
    } else {
      targetLabel.textColor = .secondaryLabel
      targetLabel.text = L10n.tr("Apply to: %@", title)
    }
  }

  // MARK: Loading

  private func loadLyrics() {
    let result = result
    loadTask = Task { @MainActor [weak self] in
      let match = await OnlineLyricsService.shared.preview(result)
      guard let self, !Task.isCancelled else { return }
      spinner.stopAnimating()
      spinner.isHidden = true
      guard let match else {
        statusLabel.text = L10n.tr("Could not load lyrics for this result.")
        return
      }
      self.match = match
      statusLabel.isHidden = true
      textView.attributedText = Self.attributedLyrics(match)
      textView.isHidden = false
      metaLabel.text = Self.metaText(for: match, result: result)
      applyButton.isEnabled = true
    }
  }

  private static func attributedLyrics(_ match: OnlineLyricsMatch) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 4
    paragraph.paragraphSpacing = 3

    let text = NSMutableAttributedString()
    for line in match.lines {
      let isTranslation = line.isTranslation
      text.append(NSAttributedString(
        string: line.text + "\n",
        attributes: [
          .font: UIFont.preferredFont(forTextStyle: isTranslation ? .callout : .body),
          .foregroundColor: isTranslation ? UIColor.secondaryLabel : UIColor.label,
          .paragraphStyle: paragraph,
        ]
      ))
    }
    return text
  }

  private static func metaText(
    for match: OnlineLyricsMatch,
    result: OnlineLyricsSearchResult
  )
    -> String {
    var parts = [match.isWordTimed ? L10n.tr("Word timed") : L10n.tr("Synced lyrics")]
    parts.append(match.format.rawValue)
    if match.hasTranslation {
      parts.append(L10n.tr("Bilingual"))
    }
    let seconds = result.duration / 1_000
    if seconds > 0 {
      parts.append(String(format: "%d:%02d", seconds / 60, seconds % 60))
    }
    parts.append(result.sourceName)
    return parts.joined(separator: " · ")
  }

  // MARK: Apply

  @objc
  private func applyPressed() {
    guard let match else { return }
    guard let song = appDelegate.player.currentlyPlaying?.asSong else {
      presentAlert(L10n.tr("No song is playing. Play a song first, then apply lyrics to it."))
      return
    }

    let mismatch = mismatchDetail(for: song)
    if song.lyricsRelFilePath != nil {
      let alert = UIAlertController(
        title: L10n.tr("This song already has lyrics. Replace them?"),
        message: mismatch.map { $0 + "\n" + L10n.tr("Timings may not line up.") },
        preferredStyle: .alert
      )
      alert.addAction(UIAlertAction(title: L10n.tr("Cancel"), style: .cancel))
      alert.addAction(UIAlertAction(title: L10n.tr("Replace"), style: .destructive) { _ in
        self.apply(match, to: song)
      })
      present(alert, animated: true)
      return
    }

    guard let mismatch else {
      apply(match, to: song)
      return
    }
    let alert = UIAlertController(
      title: L10n.tr("Lyrics may not match"),
      message: mismatch + "\n" + L10n.tr("Timings may not line up. Apply anyway?"),
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: L10n.tr("Cancel"), style: .cancel))
    alert.addAction(UIAlertAction(title: L10n.tr("Apply Anyway"), style: .destructive) { _ in
      self.apply(match, to: song)
    })
    present(alert, animated: true)
  }

  /// Warn when the result is a cover or a different edit: the timestamps then
  /// belong to another recording and drift against the current song.
  private func mismatchDetail(for song: Song) -> String? {
    let currentArtist = comparable(result.artist)
    let targetArtist = comparable(song.creatorName)
    let artistMismatch = !currentArtist.isEmpty && !targetArtist.isEmpty &&
      !currentArtist.contains(targetArtist) && !targetArtist.contains(currentArtist)
    let currentTitle = comparable(result.title)
    let targetTitle = comparable(song.title)
    let titleMismatch = !currentTitle.isEmpty && !targetTitle.isEmpty &&
      !currentTitle.contains(targetTitle) && !targetTitle.contains(currentTitle)
    // Online results report milliseconds; playable durations are stored in seconds.
    let targetDurationMs = song.duration * 1_000
    let durationMismatch = result.duration > 0 && song.duration > 0 &&
      abs(result.duration - targetDurationMs) > 5_000
    guard artistMismatch || titleMismatch || durationMismatch else { return nil }

    let resultParts = [
      result.title,
      result.artist,
      result.duration > 0 ? timeText(result.duration) : "",
    ]
    .filter { !$0.isEmpty }
    .joined(separator: " · ")
    let targetParts = [
      song.title,
      song.creatorName,
      song.duration > 0 ? timeText(targetDurationMs) : "",
    ]
    .filter { !$0.isEmpty }
    .joined(separator: " · ")
    return L10n.tr(
      "This lyric is for %@, but the current song is %@.",
      resultParts,
      targetParts
    )
  }

  private func comparable(_ text: String) -> String {
    text.folding(
      options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
      locale: .current
    )
    .filter { !$0.isWhitespace && !$0.isPunctuation }
  }

  private func timeText(_ milliseconds: Int) -> String {
    let seconds = milliseconds / 1_000
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
  }

  private func apply(_ match: OnlineLyricsMatch, to song: Song) {
    guard OnlineLyricsService.shared.apply(match, to: song) else {
      presentAlert(L10n.tr("Could not load lyrics for this result."))
      return
    }
    let alert = UIAlertController(
      title: L10n.tr("Lyrics applied"),
      message: nil,
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: L10n.tr("OK"), style: .default) { [weak self] _ in
      self?.navigationController?.popViewController(animated: true)
    })
    present(alert, animated: true)
  }

  private func presentAlert(_ message: String) {
    let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: L10n.tr("OK"), style: .default))
    present(alert, animated: true)
  }

  deinit {
    loadTask?.cancel()
  }
}
