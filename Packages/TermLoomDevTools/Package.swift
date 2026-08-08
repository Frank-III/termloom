// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "termloom-devtools",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "TermLoomDevTools", targets: ["TermLoomDevTools"])
  ],
  traits: [
    .trait(
      name: "Overlays",
      description: "Enable the ready-made popup presentation from TermLoomOverlays"
    ),
    .default(enabledTraits: ["Overlays"]),
  ],
  dependencies: [
    .package(path: "../..", traits: []),
    .package(path: "../TermLoomOverlays"),
  ],
  targets: [
    .target(
      name: "TermLoomDevTools",
      dependencies: [
        .product(name: "TermLoom", package: "termloom"),
        .product(
          name: "TermLoomOverlays", package: "TermLoomOverlays",
          condition: .when(traits: ["Overlays"])),
      ]
    ),
    .testTarget(
      name: "TermLoomDevToolsTests",
      dependencies: [
        "TermLoomDevTools",
        .product(name: "TermLoom", package: "termloom"),
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
