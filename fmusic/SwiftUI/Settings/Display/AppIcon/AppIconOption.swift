//
//  AppIconOption.swift
//  fmusic
//
//  Created by David Klopp on 09.11.26.
//  Copyright © 2026 Maximilian Bauer. All rights reserved.
//
import Foundation

struct AppIconOption: Identifiable {
  let title: String
  let iconName: String?
  let previewName: String
  let category: AppIconCategory

  var id: String { iconName ?? "Default" }

  static let all: [AppIconOption] = [
    AppIconOption(
      title: "Default",
      iconName: nil,
      previewName: "fmusicAppIconPreview",
      category: .fmusic
    ),
    AppIconOption(
      title: "Teal",
      iconName: "fmusicTeal",
      previewName: "fmusicTealPreview",
      category: .fmusic
    ),
    AppIconOption(
      title: "Green",
      iconName: "fmusicGreen",
      previewName: "fmusicGreenPreview",
      category: .fmusic
    ),
    AppIconOption(
      title: "Yellow",
      iconName: "fmusicYellow",
      previewName: "fmusicYellowPreview",
      category: .fmusic
    ),
    AppIconOption(
      title: "Orange",
      iconName: "fmusicOrange",
      previewName: "fmusicOrangePreview",
      category: .fmusic
    ),
    AppIconOption(
      title: "Red",
      iconName: "fmusicRed",
      previewName: "fmusicRedPreview",
      category: .fmusic
    ),
    AppIconOption(
      title: "Pink",
      iconName: "fmusicPink",
      previewName: "fmusicPinkPreview",
      category: .fmusic
    ),
    AppIconOption(
      title: "Purple",
      iconName: "fmusicPurple",
      previewName: "fmusicPurplePreview",
      category: .fmusic
    ),
    AppIconOption(
      title: "Music Blue",
      iconName: "fmusicMusicBlue",
      previewName: "fmusicMusicBluePreview",
      category: .music
    ),
    AppIconOption(
      title: "Music Teal",
      iconName: "fmusicMusicTeal",
      previewName: "fmusicMusicTealPreview",
      category: .music
    ),
    AppIconOption(
      title: "Music Green",
      iconName: "fmusicMusicGreen",
      previewName: "fmusicMusicGreenPreview",
      category: .music
    ),
    AppIconOption(
      title: "Music Yellow",
      iconName: "fmusicMusicYellow",
      previewName: "fmusicMusicYellowPreview",
      category: .music
    ),
    AppIconOption(
      title: "Music Orange",
      iconName: "fmusicMusicOrange",
      previewName: "fmusicMusicOrangePreview",
      category: .music
    ),
    AppIconOption(
      title: "Music Red",
      iconName: "fmusicMusicRed",
      previewName: "fmusicMusicRedPreview",
      category: .music
    ),
    AppIconOption(
      title: "Music Pink",
      iconName: "fmusicMusicPink",
      previewName: "fmusicMusicPinkPreview",
      category: .music
    ),
    AppIconOption(
      title: "Music Purple",
      iconName: "fmusicMusicPurple",
      previewName: "fmusicMusicPurplePreview",
      category: .music
    ),
    AppIconOption(
      title: "Music Single",
      iconName: "fmusicMusicSingle",
      previewName: "fmusicMusicSinglePreview",
      category: .music
    ),
    AppIconOption(
      title: "Music Single Gradient",
      iconName: "fmusicMusicSingleGradient",
      previewName: "fmusicMusicSingleGradientPreview",
      category: .music
    ),
  ]
}
