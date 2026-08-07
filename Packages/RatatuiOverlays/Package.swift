// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "ratatui-overlays",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "RatatuiOverlays", targets: ["RatatuiOverlays"])
  ],
  dependencies: [
    .package(path: "../..", traits: [])
  ],
  targets: [
    .target(
      name: "RatatuiOverlays",
      dependencies: [.product(name: "Ratatui", package: "ratetui-swift")]
    ),
    .testTarget(
      name: "RatatuiOverlaysTests",
      dependencies: ["RatatuiOverlays", .product(name: "Ratatui", package: "ratetui-swift")]
    ),
  ],
  swiftLanguageModes: [.v6]
)
