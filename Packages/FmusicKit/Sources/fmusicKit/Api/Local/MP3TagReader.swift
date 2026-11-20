//
//  MP3TagReader.swift
//  fmusicKit
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import Foundation
@preconcurrency import ID3TagEditor

// MARK: - MP3Tags

struct MP3Tags: Sendable {
  var title: String?
  var artist: String?
  var album: String?
  var albumArtist: String?
  var genre: String?
  var year: Int?
  var track: Int?
  var disc: Int?
  var lyrics: String?
  var picture: Data?
}

// MARK: - MP3TagReader

enum MP3TagReader {
  static func read(url: URL) -> MP3Tags? {
    guard let tag = try? ID3TagEditor().read(from: url.path) else { return nil }
    let reader = ID3TagContentReader(id3Tag: tag)
    let pictures = reader.attachedPictures()
    let picture = pictures.first(where: { $0.type == .frontCover })?.picture
      ?? pictures.first?.picture

    return MP3Tags(
      title: reader.title(),
      artist: reader.artist(),
      album: reader.album(),
      albumArtist: reader.albumArtist(),
      genre: reader.genre()?.description,
      year: reader.recordingYear(),
      track: reader.trackPosition()?.position,
      disc: reader.discPosition()?.position,
      lyrics: reader.unsynchronizedLyrics().first?.content,
      picture: picture
    )
  }
}
