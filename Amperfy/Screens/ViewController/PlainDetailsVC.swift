//
//  PlainDetailsVC.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 01.02.24.
//  Copyright (c) 2024 Maximilian Bauer. All rights reserved.
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

import AmperfyKit
import Foundation
import MarqueeLabel
import UIKit

class PlainDetailsVC: UIViewController {
  @IBOutlet
  weak var headerLabel: UILabel!
  @IBOutlet
  weak var detailsTextView: UITextView!

  private var rootView: UIViewController?
  private var player: PlayerFacade?
  private var lyricsRelFilePath: URL?
  private var lyricsAccount: Account?

  override func viewDidLoad() {
    super.viewDidLoad()
    view.setBackgroundBlur(style: .prominent)
    detailsTextView.textAlignment = .center

    if let presentationController = presentationController as? UISheetPresentationController {
      presentationController.detents = [
        .large(),
      ]
      if traitCollection.horizontalSizeClass == .compact {
        presentationController.detents.append(.medium())
      }
    }
  }

  override func viewIsAppearing(_ animated: Bool) {
    super.viewIsAppearing(animated)
    refresh()
  }

  func display(player: PlayerFacade, on rootView: UIViewController) {
    self.rootView = rootView
    self.player = player
    lyricsRelFilePath = nil
  }

  func display(lyricsRelFilePath: URL, lyricsAccount: Account, on rootView: UIViewController) {
    self.rootView = rootView
    player = nil
    self.lyricsRelFilePath = lyricsRelFilePath
    self.lyricsAccount = lyricsAccount
  }

  func refresh() {
    if let lyricsRelFilePath = lyricsRelFilePath, let lyricsAccount {
      detailsTextView.text = ""
      headerLabel.text = L10n.tr("Lyrics")
      Task { @MainActor in do {
        let lyricsList = try await appDelegate.getMeta(lyricsAccount.info).librarySyncer
          .parseLyrics(relFilePath: lyricsRelFilePath)
        self.displayLyrics(lyricsList: lyricsList)
      } catch {
        self.detailsTextView.text = L10n.tr("Lyrics are not available anymore.")
      }}
    } else if let player = player {
      headerLabel.text = L10n.tr("Player Info")
      var details = ""
      details += L10n.tr("Play Time") + "\n"
      details += L10n.tr("Remaining: %@", player.remainingPlayDuration.asDurationString) + "\n"
      details += L10n.tr("Total: %@", player.totalPlayDuration.asDurationString) + "\n"
      details += "\n"
      details += "\n"
      details += L10n.tr("Queue Items") + "\n"
      details += L10n.tr("Previous: %d", player.prevQueueCount) + "\n"
      details += L10n.tr("User: %d", player.userQueueCount) + "\n"
      details += L10n.tr("Next: %d", player.nextQueueCount) + "\n"
      detailsTextView.text = details
    }
  }

  private func displayLyrics(lyricsList: LyricsList) {
    guard let structuredLyrics = lyricsList.lyrics.object(at: 0) else { return }
    let lyricsLines = structuredLyrics.line
      .reduce("") { $0 == "" ? $1.value : $0 + "\n" + $1.value }
    detailsTextView.text = lyricsLines
  }

  @IBAction
  func pressedClose(_ sender: Any) {
    dismiss(animated: true)
  }
}
