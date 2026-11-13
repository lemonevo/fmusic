//
//  fmusicKitTests.swift
//  fmusicKitTests
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

@testable import fmusicKit
import XCTest

// MARK: - fmusicKitTests

class fmusicKitTests: XCTestCase {
  override func setUpWithError() throws {
    // Put setup code here. This method is called before the invocation of each test method in the class.
  }

  override func tearDownWithError() throws {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
  }

  func testExample() throws {
    // This is an example of a functional test case.
    // Use XCTAssert and related functions to verify your tests produce the correct results.
    // Any test you write for XCTest can be annotated as throws and async.
    // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
    // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
  }

  func testPerformanceExample() throws {
    // This is an example of a performance test case.
    measure {
      // Put the code you want to measure the time of here.
    }
  }
}

// MARK: - MimeFileConverterTest

class MimeFileConverterTest: XCTestCase {
  func testM4bGetsMp4Extension() {
    XCTAssertEqual(MimeFileConverter.getFilenameExtension(mimeType: "audio/m4b"), "mp4")
    XCTAssertEqual(MimeFileConverter.getFilenameExtension(mimeType: "audio/x-m4b"), "mp4")
  }
}

// MARK: - WebDAVIndexerTest

@MainActor
final class WebDAVIndexerTest: XCTestCase {
  private struct TestConfig: Decodable {
    let url: String
    let username: String
    let password: String
  }

  func testIndexesFilesFromWebDAVServer() async throws {
    let configURL = URL(fileURLWithPath: "/tmp/fmusic_webdav_test.json")
    let config = (try? Data(contentsOf: configURL))
      .flatMap { try? JSONDecoder().decode(TestConfig.self, from: $0) }
    let isExternalLibrary = config != nil
    let serverURL = config?.url ?? "http://127.0.0.1:18080"
    let username = config?.username ?? "test"
    let password = config?.password ?? "test"

    let helper = CoreDataHelper()
    _ = helper.createInMemoryManagedObjectContext()
    let manager = MOCK_CoreDataManager(persistentContainer: helper.persistentContainer)
    let storage = PersistentStorage(coreDataManager: manager)

    var credentials = LoginCredentials(
      serverUrl: serverURL,
      username: username,
      password: password
    )
    credentials.backendApi = .webdav
    let info = Account.createInfo(credentials: credentials)
    let account = storage.main.library.createAccount(info: info)
    storage.main.saveContext()

    let indexer = WebDAVLibraryIndexer(
      account: account,
      storage: storage,
      credentials: credentials
    )
    try await indexer.syncInitial(statusNotifyier: nil)

    let summary = try await storage.async.performAndGet { asyncCompanion
      -> (
        songs: Int,
        title: String,
        album: String,
        artist: String,
        genre: String,
        duration: Int,
        songsWithLyrics: Int,
        songsWithArtwork: Int
      ) in
      let account = asyncCompanion.library.getAccount(info: info)
      let songs = asyncCompanion.library.getSongs(for: account)
      let song = songs.first
      let album = asyncCompanion.library.getAlbums(for: account).first
      let artist = asyncCompanion.library.getArtists(for: account).first
      return (
        songs.count,
        song?.title ?? "",
        album?.name ?? "",
        artist?.name ?? "",
        song?.genre?.name ?? "",
        song?.duration ?? 0,
        songs.filter { $0.lyricsRelFilePath != nil }.count,
        songs.filter { $0.artwork != nil }.count
      )
    }

    if isExternalLibrary {
      XCTAssertGreaterThan(summary.songs, 0)
      XCTAssertFalse(summary.title.isEmpty)
      XCTAssertFalse(summary.album.isEmpty)
      XCTAssertFalse(summary.artist.isEmpty)
      XCTAssertGreaterThan(summary.duration, 0)
      XCTAssertGreaterThan(summary.songsWithLyrics, 0)
      XCTAssertGreaterThan(summary.songsWithArtwork, 0)
    } else {
      XCTAssertEqual(summary.songs, 1)
      XCTAssertEqual(summary.title, "复仇者联盟（The End Of Heroes）")
      XCTAssertEqual(summary.album, "十年漫威")
      XCTAssertEqual(summary.artist, "6＆9")
      XCTAssertEqual(summary.genre, "Pop")
      XCTAssertEqual(summary.duration, 94)
      XCTAssertEqual(summary.songsWithLyrics, 1)
      XCTAssertEqual(summary.songsWithArtwork, 1)
    }
  }
}
