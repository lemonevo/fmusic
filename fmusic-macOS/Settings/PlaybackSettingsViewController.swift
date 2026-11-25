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

    // MARK: Audio & transitions

    let volumeRow = makeSliderRow(
      title: L10n.tr("Volume"),
      value: Double(SettingsStore.player.volume),
      range: 0 ... 1,
      sliderWidth: 220,
      valueFormatter: { value in "\(Int((value * 100).rounded()))%" }
    ) { value in
      SettingsStore.player.volume = Float(value)
    }

    let crossfadeValues = [0, 3, 5, 8]
    let crossfadeTitles = crossfadeValues.map { seconds in
      seconds == 0 ? L10n.tr("Off") : L10n.tr("%d seconds", seconds)
    }
    let crossfadeIndex = crossfadeValues.firstIndex(of: user.crossfadeSeconds) ?? 0
    let crossfadeRow = makePopupRow(
      title: L10n.tr("Crossfade"),
      subtitle: L10n.tr("Crossfade Footer"),
      titles: crossfadeTitles,
      selectedIndex: crossfadeIndex
    ) { index in
      guard index >= 0, index < crossfadeValues.count else { return }
      let seconds = crossfadeValues[index]
      SettingsStore.updateUser { $0.crossfadeSeconds = seconds }
      SettingsStore.player.updateCrossfadeDuration(seconds: seconds)
    }

    let replayGainRow = makeSwitchRow(
      title: L10n.tr("Enable ReplayGain"),
      subtitle: L10n.tr(
        "Automatically normalize track volume based on replay gain information for consistent loudness."
      ),
      isOn: user.isReplayGainEnabled
    ) { isOn in
      SettingsStore.updateUser { $0.isReplayGainEnabled = isOn }
      SettingsStore.player.updateReplayGainEnabled(isEnabled: isOn)
    }
    addSection(
      header: L10n.tr("Audio"),
      rows: [volumeRow, crossfadeRow, replayGainRow]
    )

    // MARK: Playback behaviour

    let resumeRow = makeSwitchRow(
      title: L10n.tr("Song Playback Resume"),
      subtitle: L10n.tr(
        "Keeps track of song progress so playback continues from the previously saved position."
      ),
      isOn: user.isPlayerSongPlaybackResumeEnabled
    ) { isOn in
      SettingsStore.updateUser { $0.isPlayerSongPlaybackResumeEnabled = isOn }
    }

    let manualPlaybackRow = makeSwitchRow(
      title: L10n.tr("Manual Playback"),
      subtitle: L10n.tr("Enable to start playback only when the Play button is pressed."),
      isOn: user.isPlaybackStartOnlyOnPlay
    ) { isOn in
      SettingsStore.updateUser { $0.isPlaybackStartOnlyOnPlay = isOn }
    }

    let autoplayRow = makeSwitchRow(
      title: L10n.tr("Autoplay After End"),
      subtitle: L10n.tr(
        "When the queue ends, automatically continue playback using Instant Mix to find similar songs."
      ),
      isOn: user.isAutoplayEnabled
    ) { isOn in
      SettingsStore.updateUser { $0.isAutoplayEnabled = isOn }
    }
    addSection(
      header: L10n.tr("Playback Behavior"),
      rows: [resumeRow, manualPlaybackRow, autoplayRow]
    )

    // MARK: Lyrics sync

    let lyricsOffsetRow = makeSliderRow(
      title: L10n.tr("Lyrics Offset"),
      subtitle: L10n.tr(
        "Positive values show the lyrics earlier, negative values later. 0 ms keeps the lyrics in sync."
      ),
      value: Double(user.lyricsOffsetMs),
      range: -500 ... 500,
      step: 50,
      sliderWidth: 180,
      valueWidth: 100,
      valueFormatter: { value in
        Self.lyricsOffsetDescription(Int(value.rounded()))
      }
    ) { value in
      let offset = min(500, max(-500, Int(value.rounded())))
      guard offset != SettingsStore.user.lyricsOffsetMs else { return }
      // Copy-mutate-assign like every other settings control so the packaged settings
      // observer encodes the new value exactly once.
      SettingsStore.updateUser { $0.lyricsOffsetMs = offset }
      // Lyrics pages, the sidebar lyrics pane and the desktop lyrics overlay cache the
      // offset and re-read it when this core notification arrives.
      FmusicKit.shared.notificationHandler.post(
        name: .lyricsOffsetChanged,
        object: nil,
        userInfo: nil
      )
    }
    addSection(header: L10n.tr("Lyrics Sync"), rows: [lyricsOffsetRow])
  }

  /// Mirrors the wording used by the lyrics page and the desktop lyrics offset controls.
  private static func lyricsOffsetDescription(_ milliseconds: Int) -> String {
    guard milliseconds != 0 else { return L10n.tr("Synced") }
    let seconds = String(format: "%.1fs", abs(Double(milliseconds)) / 1_000)
    let direction = milliseconds > 0
      ? L10n.tr("Lyrics ahead by")
      : L10n.tr("Lyrics behind by")
    return "\(direction) \(seconds)"
  }
}
