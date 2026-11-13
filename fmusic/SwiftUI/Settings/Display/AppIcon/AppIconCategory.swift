//
//  AppIconCategory.swift
//  fmusic
//
//  Created by David Klopp on 09.11.26.
//  Copyright © 2026 Maximilian Bauer. All rights reserved.
//
import Foundation

enum AppIconCategory: String, CaseIterable, Identifiable {
  case fmusic
  case music
  case all

  var id: Self { self }

  var title: String {
    switch self {
    case .fmusic: "fmusic"
    case .music: "Music"
    case .all: "All"
    }
  }
}
