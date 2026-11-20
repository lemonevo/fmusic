//
//  PlaybackSettingsViewController.swift
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

/// 播放: volume, crossfade and player behaviour options.
@MainActor
final class PlaybackSettingsViewController: SettingsPageViewController {
  init() {
    super.init(title: L10n.tr("Playback"))
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func buildForm() {
    let user = SettingsStore.user

    // MARK: Volume (applies and persists immediately)

    let volumeRow = makeSliderRow(
      title: L10n.tr("Volume"),
      value: Double(SettingsStore.player.volume),
      range: 0 ... 1,
      sliderWidth: 220,
      valueFormatter: { value in "\(Int((value * 100).rounded()))%" }
    ) { value in
      SettingsStore.player.volume = Float(value)
    }
    addSection(rows: [volumeRow])

    // MARK: Crossfade

    let crossfadeValues = [0, 3, 5, 8]
    let crossfadeTitles = crossfadeValues.map { seconds in
      seconds == 0 ? L10n.tr("Off") : L10n.tr("%d seconds", seconds)
    }
    let crossfadeIndex = crossfadeValues.firstIndex(of: user.crossfadeSeconds) ?? 0
    let crossfadeRow = makePopupRow(
      title: L10n.tr("Crossfade"),
      titles: crossfadeTitles,
      selectedIndex: crossfadeIndex
    ) { index in
      guard index >= 0, index < crossfadeValues.count else { return }
      let seconds = crossfadeValues[index]
      SettingsStore.updateUser { $0.crossfadeSeconds = seconds }
      SettingsStore.player.updateCrossfadeDuration(seconds: seconds)
    }
    addSection(rows: [crossfadeRow])

    // MARK: ReplayGain

    let replayGainRow = makeSwitchRow(
      title: L10n.tr("Enable ReplayGain"),
      isOn: user.isReplayGainEnabled
    ) { isOn in
      SettingsStore.updateUser { $0.isReplayGainEnabled = isOn }
      SettingsStore.player.updateReplayGainEnabled(isEnabled: isOn)
    }
    addSection(
      footer: L10n.tr(
        "Automatically normalize track volume based on replay gain information for consistent loudness."
      ),
      rows: [replayGainRow]
    )

    // MARK: Playback behaviour

    let resumeRow = makeSwitchRow(
      title: L10n.tr("Song Playback Resume"),
      isOn: user.isPlayerSongPlaybackResumeEnabled
    ) { isOn in
      SettingsStore.updateUser { $0.isPlayerSongPlaybackResumeEnabled = isOn }
    }
    addSection(
      footer: L10n.tr(
        "Keeps track of song progress so playback continues from the previously saved position."
      ),
      rows: [resumeRow]
    )

    let manualPlaybackRow = makeSwitchRow(
      title: L10n.tr("Manual Playback"),
      isOn: user.isPlaybackStartOnlyOnPlay
    ) { isOn in
      SettingsStore.updateUser { $0.isPlaybackStartOnlyOnPlay = isOn }
    }
    addSection(
      footer: L10n.tr("Enable to start playback only when the Play button is pressed."),
      rows: [manualPlaybackRow]
    )

    let autoplayRow = makeSwitchRow(
      title: L10n.tr("Autoplay After End"),
      isOn: user.isAutoplayEnabled
    ) { isOn in
      SettingsStore.updateUser { $0.isAutoplayEnabled = isOn }
    }
    addSection(
      footer: L10n.tr(
        "When the queue ends, automatically continue playback using Instant Mix to find similar songs."
      ),
      rows: [autoplayRow]
    )
  }
}
