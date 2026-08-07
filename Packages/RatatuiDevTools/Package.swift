// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "ratatui-devtools",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "RatatuiDevTools", targets: ["RatatuiDevTools"])
  ],
  traits: [
    .trait(
      name: "Overlays",
      description: "Enable the ready-made popup presentation from RatatuiOverlays"
    ),
    .default(enabledTraits: ["Overlays"]),
  ],
  dependencies: [
    .package(path: "../..", traits: []),
    .package(path: "../RatatuiOverlays"),
  ],
  targets: [
    .target(
      name: "RatatuiDevTools",
      dependencies: [
        .product(name: "Ratatui", package: "ratetui-swift"),
        .product(
          name: "RatatuiOverlays", package: "RatatuiOverlays",
          condition: .when(traits: ["Overlays"])),
      ]
    ),
    .testTarget(
      name: "RatatuiDevToolsTests",
      dependencies: [
        "RatatuiDevTools",
        .product(name: "Ratatui", package: "ratetui-swift"),
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
