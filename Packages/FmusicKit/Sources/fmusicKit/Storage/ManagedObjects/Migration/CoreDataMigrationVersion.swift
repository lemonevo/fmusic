//
//  CoreDataVersion.swift
//  CoreDataMigration-Example
//
//  Created by William Boles on 02/01/2019.
//  Copyright © 2019 William Boles. All rights reserved.
//

import CoreData
import Foundation

enum CoreDataMigrationVersion: String, CaseIterable {
  case v49 =
    "fmusic v49" // Remove PlayableFile and Artwork data (they were already deprecated); Account: add apiType
  case v50 = "fmusic v50" // Remove ScrobbleEntry

  // MARK: - Current

  static var current: CoreDataMigrationVersion {
    guard let latest = allCases.last else {
      fatalError("no model versions found")
    }

    return latest
  }

  // MARK: - Migration

  func nextVersion() -> CoreDataMigrationVersion? {
    switch self {
    case .v49:
      return .v50
    case .v50:
      return nil
    }
  }
}
