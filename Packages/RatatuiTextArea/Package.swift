// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "ratatui-textarea",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "RatatuiTextArea", targets: ["RatatuiTextArea"])
  ],
  dependencies: [
    .package(path: "../..", traits: [])
  ],
  targets: [
    .target(
      name: "RatatuiTextArea",
      dependencies: [.product(name: "Ratatui", package: "ratetui-swift")]
    ),
    .testTarget(
      name: "RatatuiTextAreaTests",
      dependencies: ["RatatuiTextArea", .product(name: "Ratatui", package: "ratetui-swift")]
    ),
  ],
  swiftLanguageModes: [.v6]
)
