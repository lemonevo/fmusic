//
//  PlatformImage+Symbols.swift
//  fmusicKit
//
//  Created by Maximilian Bauer on 06.06.22.
//  Copyright (c) 2022 Maximilian Bauer. All rights reserved.
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

import Foundation

// The UI images used throughout the app. On iOS/iPadOS/Mac Catalyst `PlatformImage`
// is `UIImage`, so `UIImage.play` and friends keep working unchanged; on macOS the
// very same names are available on `NSImage`.

@MainActor
extension PlatformImage {
  public static let airplayaudio = PlatformImages.symbol(fmusicImage.airplayaudio.systemName)
  public static let album = PlatformImages.symbol(fmusicImage.album.systemName)
  public static let antenna = PlatformImages.symbol(fmusicImage.antenna.systemName)
  public static let artist = PlatformImages.symbol(fmusicImage.artist.systemName)
  public static let appIcon = PlatformImages.asset(named: "Icon-1024") ?? PlatformImages.empty
  public static let arrowRight = PlatformImages.symbol(fmusicImage.arrowRight.systemName)
  public static let arrowTurnUp = PlatformImages.symbol(fmusicImage.arrowTurnUp.systemName)
  public static let audioVisualizer = PlatformImages
    .symbol(fmusicImage.audioVisualizer.systemName)
  public static let backwardFill = PlatformImages.symbol(fmusicImage.backwardFill.systemName)
  public static let backwardMenu = PlatformImages.symbol(fmusicImage.backwardMenu.systemName)
  public static let ban = PlatformImages.symbol(fmusicImage.ban.systemName)
  public static let bars = PlatformImages.symbol(fmusicImage.bars.systemName)
  public static let bell = PlatformImages.symbol(fmusicImage.bell.systemName)
  public static let cache = download
  public static let cancleDownloads = PlatformImages
    .symbol(fmusicImage.cancleDownloads.systemName)
  public static let check = PlatformImages.symbol(fmusicImage.check.systemName)
  public static let circle = PlatformImages.symbol(fmusicImage.circle.systemName)
  public static let clear = PlatformImages.symbol(fmusicImage.clear.systemName)
  public static let clipboard = PlatformImages.symbol(fmusicImage.clipboard.systemName)
  public static let clock = PlatformImages.symbol(fmusicImage.clock.systemName)
  public static let cloudX = PlatformImages.symbol(fmusicImage.cloudX.systemName)
  public static let currentSongMenu = PlatformImages
    .symbol(fmusicImage.currentSongMenu.systemName)
  public static let display = PlatformImages.symbol(fmusicImage.display.systemName)
  public static let doc = PlatformImages.symbol(fmusicImage.doc.systemName)
  public static let documents = PlatformImages.symbol(fmusicImage.documents.systemName)
  public static let download = PlatformImages.symbol(fmusicImage.download.systemName)
  public static let ellipsis = PlatformImages.symbol(fmusicImage.ellipsis.systemName)
  public static let equalizer = PlatformImages.symbol(fmusicImage.equalizer.systemName)
  public static let exclamation = PlatformImages.symbol(fmusicImage.exclamation.systemName)
  public static let filter = PlatformImages.symbol(fmusicImage.filter.systemName)
  public static let followLink = PlatformImages.symbol(fmusicImage.followLink.systemName)
  public static let folder = PlatformImages.symbol(fmusicImage.folder.systemName)
  public static let forwardFill = PlatformImages.symbol(fmusicImage.forwardFill.systemName)
  public static let forwardMenu = PlatformImages.symbol(fmusicImage.forwardMenu.systemName)
  public static let genre = PlatformImages.symbol(fmusicImage.genre.systemName)
  public static let goBackward15 = PlatformImages.symbol(fmusicImage.goBackward15.systemName)
  public static let goForward30 = PlatformImages.symbol(fmusicImage.goForward30.systemName)
  public static let grid = PlatformImages.symbol(fmusicImage.grid.systemName)
  public static let hammer = PlatformImages.symbol(fmusicImage.hammer.systemName)
  public static let heartEmpty = PlatformImages.symbol(fmusicImage.heartEmpty.systemName)
  public static let heartFill = PlatformImages.symbol(fmusicImage.heartFill.systemName)
  public static let heartSlash = PlatformImages.symbol(fmusicImage.heartSlash.systemName)
  public static let home = PlatformImages.symbol(fmusicImage.home.systemName)
  public static let info = PlatformImages.symbol(fmusicImage.info.systemName)
  public static let isSelected = PlatformImages.symbol(fmusicImage.isSelected.systemName)
  public static let listBullet = PlatformImages.symbol(fmusicImage.listBullet.systemName)
  public static let login = PlatformImages.symbol(fmusicImage.login.systemName)
  public static let lyrics = PlatformImages.symbol(fmusicImage.lyrics.systemName)
  public static let miniPlayer = PlatformImages.symbol(fmusicImage.miniPlayer.systemName)
  public static let minus = PlatformImages.symbol(fmusicImage.minus.systemName)
  public static let musicLibrary = PlatformImages.symbol(fmusicImage.musicLibrary.systemName)
  public static let musicalNotes = PlatformImages.symbol(fmusicImage.musicalNotes.systemName)
  public static let pause = PlatformImages.symbol(fmusicImage.pause.systemName)
  public static let pauseMenu = PlatformImages.symbol(fmusicImage.pauseMenu.systemName)
  public static let password = PlatformImages.symbol(fmusicImage.password.systemName)
  public static let person = PlatformImages.symbol(fmusicImage.person.systemName)
  public static let photo = PlatformImages.symbol(fmusicImage.photo.systemName)
  public static let play = PlatformImages.symbol(fmusicImage.play.systemName)
  public static let playCircle = PlatformImages.symbol(fmusicImage.playCircle.systemName)
  public static let playMenu = PlatformImages.symbol(fmusicImage.playMenu.systemName)
  public static let playbackRate = PlatformImages.symbol(fmusicImage.playbackRate.systemName)
  public static let playlist = PlatformImages.symbol(fmusicImage.playlist.systemName)
  public static let playlistDisplayStyle = PlatformImages
    .symbol(fmusicImage.playlistDisplayStyle.systemName)
  public static let playlistPlus = PlatformImages.symbol(fmusicImage.playlistPlus.systemName)
  public static let playlistX = PlatformImages.symbol(fmusicImage.playlistX.systemName)
  public static let plus = PlatformImages.symbol(fmusicImage.plus.systemName)
  public static let plusCircle = PlatformImages.symbol(fmusicImage.plusCircle.systemName)
  public static let radio = PlatformImages.symbol(fmusicImage.radio.systemName)
  public static let redo = PlatformImages.symbol(fmusicImage.redo.systemName)
  public static let refresh = PlatformImages.symbol(fmusicImage.refresh.systemName)
  public static let repeatAll = PlatformImages.symbol(fmusicImage.repeatAll.systemName)
  public static let repeatMenu = PlatformImages.symbol(fmusicImage.repeatMenu.systemName)
  public static let repeatOff = PlatformImages.symbol(fmusicImage.repeatOff.systemName)
  public static let repeatOne = PlatformImages.symbol(fmusicImage.repeatOne.systemName)
  public static let resize = PlatformImages.symbol(fmusicImage.resize.systemName)
  public static let search = PlatformImages.symbol(fmusicImage.search.systemName)
  public static let server = PlatformImages.symbol(fmusicImage.server.systemName)
  public static let serverUrl = PlatformImages.symbol(fmusicImage.serverUrl.systemName)
  public static let settings = PlatformImages.symbol(fmusicImage.settings.systemName)
  public static let shuffle = PlatformImages.symbol(fmusicImage.shuffle.systemName)
  public static let instantMix = PlatformImages.symbol(fmusicImage.instantMix.systemName)
  public static let infinity = PlatformImages.symbol(fmusicImage.infinity.systemName)
  public static let shuffleMenu = PlatformImages.symbol(fmusicImage.shuffleMenu.systemName)
  public static let skipBackward10 = PlatformImages
    .symbol(fmusicImage.skipBackward10.systemName)
  public static let skipBackward15 = PlatformImages
    .symbol(fmusicImage.skipBackward15.systemName)
  public static let skipBackwardMenu = PlatformImages
    .symbol(fmusicImage.skipBackwardMenu.systemName)
  public static let skipForward10 = PlatformImages
    .symbol(fmusicImage.skipForward10.systemName)
  public static let skipForward30 = PlatformImages
    .symbol(fmusicImage.skipForward30.systemName)
  public static let skipForwardMenu = PlatformImages
    .symbol(fmusicImage.skipForwardMenu.systemName)
  public static let sleep = PlatformImages.symbol(fmusicImage.sleep.systemName)
  public static let sleepFill = PlatformImages.symbol(fmusicImage.sleepFill.systemName)
  public static let sort = PlatformImages.symbol(fmusicImage.sort.systemName)
  public static let sparkles = PlatformImages.symbol(fmusicImage.sparkles.systemName)
  public static let squareArrow = PlatformImages.symbol(fmusicImage.squareArrow.systemName)
  public static let starEmpty = PlatformImages.symbol(fmusicImage.starEmpty.systemName)
  public static let starFill = PlatformImages.symbol(fmusicImage.starFill.systemName)
  public static let starSlash = PlatformImages.symbol(fmusicImage.starSlash.systemName)
  public static let startDownload = PlatformImages
    .symbol(fmusicImage.startDownload.systemName)
  public static let stop = PlatformImages.symbol(fmusicImage.stop.systemName)
  public static let stopMenu = PlatformImages.symbol(fmusicImage.stopMenu.systemName)
  public static let trash = PlatformImages.symbol(fmusicImage.trash.systemName)
  public static let triangleDown = PlatformImages.symbol(fmusicImage.triangleDown.systemName)
  public static let unSelected = PlatformImages.symbol(fmusicImage.unSelected.systemName)
  public static let userCircleCheckmark = PlatformImages
    .symbol(fmusicImage.userCircleCheckmark.systemName)
  public static let userCirclePlus = PlatformImages
    .symbol(fmusicImage.userCirclePlus.systemName)
  public static let userPerson = PlatformImages.symbol(fmusicImage.userPerson.systemName)
  public static let volumeMax = PlatformImages.symbol(fmusicImage.volumeMax.systemName)
  public static let volumeMin = PlatformImages.symbol(fmusicImage.volumeMin.systemName)
  public static let xmark = PlatformImages.symbol(fmusicImage.xmark.systemName)

  // Asset symbol generation is enabled by default for Xcode targets but can be disabled
  // by setting the build setting "Generate Asset Symbols"
  // (ASSETCATALOG_COMPILER_GENERATE_ASSET_SYMBOLS) to NO. SwiftPM never generates
  // those symbols, so the catalog symbols the app uses are declared here explicitly.
  public static let podcast = PlatformImages.asset(named: fmusicImage.podcast.assetName)
    ?? PlatformImages.empty
  public static let albumNewest = PlatformImages
    .asset(named: fmusicImage.albumNewest.assetName) ?? PlatformImages.empty
  public static let albumRecent = PlatformImages
    .asset(named: fmusicImage.albumRecent.assetName) ?? PlatformImages.empty
  public static let userQueueInsert = PlatformImages
    .asset(named: fmusicImage.userQueueInsert.assetName) ?? PlatformImages.empty
  // SF-Symbols 5 Regular: custom.text.line.first.and.arrowtriangle.forward.badge.person.crop
  public static let userQueueAppend = PlatformImages
    .asset(named: fmusicImage.userQueueAppend.assetName) ?? PlatformImages.empty
  // SF-Symbols 5 Regular: custom.text.line.last.and.arrowtriangle.forward.badge.person.crop
  public static let contextQueueInsert = PlatformImages
    .asset(named: fmusicImage.contextQueueInsert.assetName) ?? PlatformImages.empty
  // SF-Symbols 5 Regular: custom.text.line.first.and.arrowtriangle.forward
  public static let contextQueueAppend = PlatformImages
    .asset(named: fmusicImage.contextQueueAppend.assetName) ?? PlatformImages.empty
  // SF-Symbols 5 Regular: custom.text.line.last.and.arrowtriangle.forward

  public static let podcastEpisode: PlatformImage = podcast
  public static let podcastQueueInsert = contextQueueInsert
  public static let podcastQueueAppend = contextQueueAppend
}
