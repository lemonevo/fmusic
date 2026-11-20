// swift-tools-version:6.0

import PackageDescription

// Keep the package on the same Swift 6 language mode / upcoming feature set as
// the app target so the migration does not change compilation semantics.
let swift6Settings: [SwiftSetting] = [
  .swiftLanguageMode(.v6),
  // Already part of the Swift 6 language mode in the app target; kept explicitly
  // because the package must compile with the same diagnostics as the app.
  .enableUpcomingFeature("ImportObjcForwardDecls"),
]

// FmusicKit — cross-platform core of fmusic.
//
// The platform-independent library used by both the iOS/iPad app target and the
// native macOS app target. UIKit is only allowed inside `#if canImport(UIKit)`
// sections; shared code goes through the abstractions in `Platform/`.
let package = Package(
  name: "FmusicKit",
  platforms: [
    .iOS(.v17),
    .macOS(.v14),
  ],
  products: [
    .library(
      name: "fmusicKit",
      targets: ["fmusicKit"]
    ),
  ],
  dependencies: [
    // Vendored AudioStreaming 1.4.4 with the FLAC seek patch; do not upgrade blindly.
    .package(path: "../../Vendor/AudioStreaming"),
    .package(url: "https://github.com/ukushu/Ifrit", exact: "2.0.3"),
    .package(url: "https://github.com/chicio/ID3TagEditor", from: "4.6.0"),
  ],
  targets: [
    .target(
      name: "fmusicKit",
      dependencies: [
        .product(name: "AudioStreaming", package: "AudioStreaming"),
        .product(name: "IfritStatic", package: "Ifrit"),
        .product(name: "ID3TagEditor", package: "ID3TagEditor"),
      ],
      path: "Sources/fmusicKit",
      resources: [
        .process("Resources/Assets.xcassets"),
        .process("Resources/fmusic.xcdatamodeld"),
      ],
      swiftSettings: swift6Settings
    ),
  ]
)
