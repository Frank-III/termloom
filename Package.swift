// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "ratetui-swift",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "Ratatui", targets: ["Ratatui"]),
    .library(name: "RatatuiSyntaxHighlighting", targets: ["RatatuiSyntaxHighlighting"]),
    .library(name: "RatatuiTestSupport", targets: ["RatatuiTestSupport"]),
    .executable(name: "ratatui-demo", targets: ["RatatuiDemo"]),
    .executable(name: "ratatui-benchmark", targets: ["RatatuiBenchmark"]),
    .executable(name: "ratatui-counter", targets: ["RatatuiCounter"]),
    .executable(name: "ratatui-gallery", targets: ["RatatuiGallery"]),
    .executable(name: "ratatui-observation", targets: ["RatatuiObservationDemo"]),
  ],
  traits: [
    .trait(
      name: "SyntaxHighlighting",
      description: "Enable the Highlight-based RatatuiSyntaxHighlighting product"
    ),
    .trait(
      name: "TestSupport",
      description: "Enable inline snapshots and CustomDump-backed framework tests"
    ),
    .default(enabledTraits: ["SyntaxHighlighting", "TestSupport"]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/danelyan/swift-highlight",
      from: "1.0.1"
    ),
    .package(
      url: "https://github.com/pointfreeco/swift-custom-dump",
      from: "1.0.0"
    ),
    .package(
      url: "https://github.com/pointfreeco/swift-snapshot-testing",
      from: "1.0.0"
    ),
  ],
  targets: [
    .target(name: "Ratatui"),
    .target(
      name: "RatatuiSyntaxHighlighting",
      dependencies: [
        "Ratatui",
        .product(
          name: "Highlight", package: "swift-highlight",
          condition: .when(traits: ["SyntaxHighlighting"])),
        .product(
          name: "HighlightAttributed", package: "swift-highlight",
          condition: .when(traits: ["SyntaxHighlighting"])),
        .product(
          name: "HighlightLanguages", package: "swift-highlight",
          condition: .when(traits: ["SyntaxHighlighting"])),
      ]
    ),
    .target(
      name: "RatatuiTestSupport",
      dependencies: [
        "Ratatui",
        .product(
          name: "InlineSnapshotTesting", package: "swift-snapshot-testing",
          condition: .when(traits: ["TestSupport"])),
      ]
    ),
    .executableTarget(
      name: "RatatuiDemo",
      dependencies: ["Ratatui"]
    ),
    .executableTarget(
      name: "RatatuiBenchmark",
      dependencies: ["Ratatui"]
    ),
    .executableTarget(
      name: "RatatuiCounter",
      dependencies: ["Ratatui"]
    ),
    .executableTarget(
      name: "RatatuiGallery",
      dependencies: ["Ratatui"]
    ),
    .executableTarget(
      name: "RatatuiObservationDemo",
      dependencies: ["Ratatui"]
    ),
    .testTarget(
      name: "RatatuiTests",
      dependencies: [
        "Ratatui",
        .target(name: "RatatuiTestSupport", condition: .when(traits: ["TestSupport"])),
        .product(
          name: "CustomDump", package: "swift-custom-dump",
          condition: .when(traits: ["TestSupport"])),
      ],
      resources: [.copy("Fixtures/emoji-test.txt")]
    ),
    .testTarget(
      name: "RatatuiSyntaxHighlightingTests",
      dependencies: ["RatatuiSyntaxHighlighting"]
    ),
  ],
  swiftLanguageModes: [.v6]
)
