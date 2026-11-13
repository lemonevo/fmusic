//
//  TestAccountInfo.swift
//  fmusicKitTests
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

// MARK: - TestAccountInfo

enum TestAccountInfo {
  static let test1ServerHash = "111Server"
  static let test1UserHash = "111User"
  static let test1ApiType = BackenApiType.local
  static let test2ServerHash = "22-S"
  static let test2UserHash = "22-U"
  static let test2ApiType = BackenApiType.webdav

  static func create1() -> AccountInfo {
    AccountInfo(
      serverHash: Self.test1ServerHash,
      userHash: Self.test1UserHash,
      apiType: Self.test1ApiType
    )
  }

  static func create2() -> AccountInfo {
    AccountInfo(
      serverHash: Self.test2ServerHash,
      userHash: Self.test2UserHash,
      apiType: Self.test2ApiType
    )
  }
}
