//
//  FlacTagReader.swift
//  fmusicKit
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import Foundation

// MARK: - FlacTags

struct FlacTags: Sendable {
  var title: String?
  var artist: String?
  var album: String?
  var albumArtist: String?
  var genre: String?
  var year: Int?
  var track: Int?
  var disc: Int?
  var lyrics: String?
  var duration: Int?
  var picture: Data?
}

// MARK: - FlacTagReader

/// Minimal FLAC metadata reader for STREAMINFO, VORBIS_COMMENT and PICTURE blocks.
/// AVFoundation does not consistently surface Vorbis comments and embedded
/// pictures, so the local/WebDAV indexers use this reader for FLAC files.
enum FlacTagReader {
  private static let marker = Data("fLaC".utf8)
  private static let maximumMetadataSize = 64 * 1024 * 1024

  static func read(url: URL) -> FlacTags? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }

    guard let fileMarker = try? handle.read(upToCount: 4),
          fileMarker == marker
    else { return nil }

    var tags = FlacTags()
    var readBytes = 0

    while let header = try? handle.read(upToCount: 4), header.count == 4 {
      readBytes += 4
      let isLast = (header[0] & 0x80) != 0
      let blockType = header[0] & 0x7F
      let blockLength = (Int(header[1]) << 16) | (Int(header[2]) << 8) | Int(header[3])
      guard blockLength >= 0, readBytes + blockLength <= maximumMetadataSize else { break }

      guard let body = try? handle.read(upToCount: blockLength), body.count == blockLength
      else { break }
      readBytes += blockLength

      switch blockType {
      case 0:
        parseStreamInfo(body, into: &tags)
      case 4:
        parseVorbisComments(body, into: &tags)
      case 6:
        if tags.picture == nil {
          tags.picture = parsePicture(body)
        }
      default:
        break
      }

      if isLast { break }
    }
    return tags
  }

  private static func parseStreamInfo(_ data: Data, into tags: inout FlacTags) {
    guard data.count >= 18 else { return }
    let sampleRate = (Int(data[10]) << 12) | (Int(data[11]) << 4) | (Int(data[12]) >> 4)
    var totalSamples = Int(data[13] & 0x0F) << 32
    totalSamples |= Int(data[14]) << 24
    totalSamples |= Int(data[15]) << 16
    totalSamples |= Int(data[16]) << 8
    totalSamples |= Int(data[17])
    guard sampleRate > 0, totalSamples > 0 else { return }
    tags.duration = Int((Double(totalSamples) / Double(sampleRate)).rounded())
  }

  private static func parseVorbisComments(_ data: Data, into tags: inout FlacTags) {
    var offset = 0
    guard let vendorLength: UInt32 = readUInt32LE(data, offset: &offset) else { return }
    guard skip(Int(vendorLength), in: data, offset: &offset) else { return }
    guard let commentCount: UInt32 = readUInt32LE(data, offset: &offset) else { return }

    for _ in 0 ..< min(Int(commentCount), 10_000) {
      guard let length: UInt32 = readUInt32LE(data, offset: &offset),
            let end = offsetSafe(offset, Int(length), in: data)
      else { return }
      let commentData = data[offset ..< end]
      offset = end
      guard let comment = String(data: commentData, encoding: .utf8),
            let separator = comment.firstIndex(of: "=")
      else { continue }
      let key = comment[..<separator].lowercased()
      let value = String(comment[comment.index(after: separator)...])
      apply(key: key, value: value, into: &tags)
    }
  }

  private static func apply(key: String, value: String, into tags: inout FlacTags) {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    switch key {
    case "title":
      tags.title = tags.title ?? trimmed
    case "artist":
      tags.artist = tags.artist ?? trimmed
    case "album":
      tags.album = tags.album ?? trimmed
    case "album artist", "albumartist":
      tags.albumArtist = tags.albumArtist ?? trimmed
    case "genre":
      tags.genre = tags.genre ?? trimmed
    case "date", "year":
      if tags.year == nil {
        tags.year = firstNumber(in: trimmed, maxDigits: 4)
      }
    case "track", "tracknumber":
      if tags.track == nil {
        tags.track = firstNumber(in: trimmed, maxDigits: 3)
      }
    case "disc", "discnumber":
      if tags.disc == nil {
        tags.disc = firstNumber(in: trimmed, maxDigits: 3)
      }
    case "lyrics", "unsynced lyrics", "unsyncedlyrics":
      tags.lyrics = tags.lyrics ?? trimmed
    default:
      break
    }
  }

  private static func parsePicture(_ data: Data) -> Data? {
    var offset = 0
    guard let pictureType: UInt32 = readUInt32BE(data, offset: &offset),
          let mimeLength: UInt32 = readUInt32BE(data, offset: &offset),
          skip(Int(mimeLength), in: data, offset: &offset),
          let descriptionLength: UInt32 = readUInt32BE(data, offset: &offset),
          skip(Int(descriptionLength), in: data, offset: &offset)
    else { return nil }
    guard skip(16, in: data, offset: &offset),
          let pictureLength: UInt32 = readUInt32BE(data, offset: &offset),
          let end = offsetSafe(offset, Int(pictureLength), in: data)
    else { return nil }
    // 3 == front cover; fall back to any picture block if no front cover exists.
    _ = pictureType
    return Data(data[offset ..< end])
  }

  private static func readUInt32BE(_ data: Data, offset: inout Int) -> UInt32? {
    guard let end = offsetSafe(offset, 4, in: data) else { return nil }
    var value: UInt32 = 0
    for index in offset ..< end {
      value = (value << 8) | UInt32(data[index])
    }
    offset = end
    return value
  }

  private static func readUInt32LE(_ data: Data, offset: inout Int) -> UInt32? {
    guard let end = offsetSafe(offset, 4, in: data) else { return nil }
    var value: UInt32 = 0
    var shift: UInt32 = 0
    for index in offset ..< end {
      value |= UInt32(data[index]) << shift
      shift += 8
    }
    offset = end
    return value
  }

  private static func skip(_ count: Int, in data: Data, offset: inout Int) -> Bool {
    guard let end = offsetSafe(offset, count, in: data) else { return false }
    offset = end
    return true
  }

  private static func offsetSafe(_ offset: Int, _ count: Int, in data: Data) -> Int? {
    guard offset >= 0, count >= 0, offset + count <= data.count else { return nil }
    return offset + count
  }

  private static func firstNumber(in value: String, maxDigits: Int) -> Int? {
    let digits = value.prefix { $0.isNumber }.prefix(maxDigits)
    guard !digits.isEmpty else { return nil }
    return Int(digits)
  }
}
