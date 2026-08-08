// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "termloom-overlays",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "TermLoomOverlays", targets: ["TermLoomOverlays"])
  ],
  dependencies: [
    .package(path: "../..", traits: [])
  ],
  targets: [
    .target(
      name: "TermLoomOverlays",
      dependencies: [.product(name: "TermLoom", package: "termloom")]
    ),
    .testTarget(
      name: "TermLoomOverlaysTests",
      dependencies: ["TermLoomOverlays", .product(name: "TermLoom", package: "termloom")]
    ),
  ],
  swiftLanguageModes: [.v6]
)
