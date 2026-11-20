//
//  LibraryResyncProgressViewController.swift
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

/// Sheet shown while the library is being resynced.
///
/// Owns no sync logic: the account settings page starts `LibraryResyncService` and feeds
/// `update(_:)` from the service's progress callback. The cancel button only forwards the
/// request (`onCancel`); the caller dismisses the sheet when the task finished, which keeps
/// the cancellation safe (the service restarts the background managers before it returns).
@MainActor
final class LibraryResyncProgressViewController: NSViewController {
  /// Called when the user presses Cancel. The caller cancels its resync task.
  var onCancel: (() -> Void)?

  private let titleLabel = NSTextField(labelWithString: L10n.tr("Resync Library"))
  private let statusLabel = NSTextField(labelWithString: L10n.tr("Initial Sync"))
  private let detailLabel = NSTextField(labelWithString: "")
  private let progressIndicator = NSProgressIndicator()
  private let cancelButton = NSButton()

  private var isCancelRequested = false

  init() {
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func loadView() {
    // The sheet is sized from this view's frame; the subviews are laid out with Auto Layout
    // inside it, so the container itself keeps translatesAutoresizingMaskIntoConstraints.
    let container = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 186))
    preferredContentSize = container.frame.size

    titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
    titleLabel.textColor = .labelColor
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    statusLabel.font = MacTheme.bodyFont
    statusLabel.textColor = .labelColor
    statusLabel.lineBreakMode = .byTruncatingTail
    statusLabel.translatesAutoresizingMaskIntoConstraints = false

    detailLabel.font = MacTheme.secondaryFont
    detailLabel.textColor = .secondaryLabelColor
    detailLabel.lineBreakMode = .byTruncatingTail
    detailLabel.translatesAutoresizingMaskIntoConstraints = false

    progressIndicator.style = .bar
    progressIndicator.isIndeterminate = true
    progressIndicator.minValue = 0
    progressIndicator.maxValue = 1
    progressIndicator.doubleValue = 0
    progressIndicator.translatesAutoresizingMaskIntoConstraints = false
    progressIndicator.startAnimation(nil)

    cancelButton.title = L10n.tr("Cancel")
    cancelButton.bezelStyle = .rounded
    cancelButton.keyEquivalent = "\u{1b}"
    cancelButton.target = self
    cancelButton.action = #selector(cancelPressed)
    cancelButton.translatesAutoresizingMaskIntoConstraints = false

    for view in [titleLabel, statusLabel, detailLabel, progressIndicator, cancelButton] {
      container.addSubview(view)
    }

    NSLayoutConstraint.activate([
      titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
      titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
      titleLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: container.trailingAnchor,
        constant: -20
      ),

      statusLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
      statusLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      statusLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: container.trailingAnchor,
        constant: -20
      ),

      progressIndicator.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
      progressIndicator.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      progressIndicator.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
      progressIndicator.heightAnchor.constraint(equalToConstant: 20),

      detailLabel.topAnchor.constraint(equalTo: progressIndicator.bottomAnchor, constant: 8),
      detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      detailLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: container.trailingAnchor,
        constant: -20
      ),

      cancelButton.topAnchor.constraint(
        greaterThanOrEqualTo: detailLabel.bottomAnchor,
        constant: 18
      ),
      cancelButton.trailingAnchor.constraint(
        equalTo: container.trailingAnchor,
        constant: -20
      ),
      cancelButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
    ])

    self.view = container
  }

  // MARK: - Progress

  func update(_ progress: LibrarySyncProgress) {
    switch progress.phase {
    case .preparing:
      statusLabel.stringValue = L10n.tr("Initial Sync")
    case .artist:
      statusLabel.stringValue = L10n.tr("Syncing artists ...")
    case .album:
      statusLabel.stringValue = L10n.tr("Syncing albums ...")
    case .song:
      statusLabel.stringValue = L10n.tr("Syncing songs ...")
    case .playlist:
      statusLabel.stringValue = L10n.tr("Syncing playlists ...")
    case .genre:
      statusLabel.stringValue = L10n.tr("Syncing genres ...")
    case .podcast:
      statusLabel.stringValue = L10n.tr("Syncing podcasts ...")
    case .cache:
      statusLabel.stringValue = L10n.tr("Applying cache ...")
    case .finished:
      statusLabel.stringValue = L10n.tr("Done")
      setCancelEnabled(false)
    }

    if let fraction = progress.fractionCompleted {
      progressIndicator.stopAnimation(nil)
      progressIndicator.isIndeterminate = false
      progressIndicator.doubleValue = fraction
      detailLabel.stringValue = String(
        format: "%d / %d",
        progress.parsedObjectCount,
        progress.totalCount
      )
    } else {
      progressIndicator.isIndeterminate = true
      progressIndicator.startAnimation(nil)
      detailLabel.stringValue = ""
    }
  }

  // MARK: - Cancel

  private func setCancelEnabled(_ isEnabled: Bool) {
    cancelButton.isEnabled = isEnabled
    cancelButton.keyEquivalent = isEnabled ? "\u{1b}" : ""
  }

  @objc
  private func cancelPressed() {
    guard !isCancelRequested else { return }
    isCancelRequested = true
    // The caller cancels the task and dismisses the sheet once the app state is restored;
    // keep the button disabled until then so the request cannot be sent twice.
    setCancelEnabled(false)
    onCancel?()
  }
}
