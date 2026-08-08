// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "termloom",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "TermLoom", targets: ["TermLoom"]),
    .library(name: "TermLoomSyntaxHighlighting", targets: ["TermLoomSyntaxHighlighting"]),
    .library(name: "TermLoomTestSupport", targets: ["TermLoomTestSupport"]),
    .executable(name: "termloom-demo", targets: ["TermLoomDemo"]),
    .executable(name: "termloom-benchmark", targets: ["TermLoomBenchmark"]),
    .executable(name: "termloom-counter", targets: ["TermLoomCounter"]),
    .executable(name: "termloom-gallery", targets: ["TermLoomGallery"]),
    .executable(name: "termloom-observation", targets: ["TermLoomObservationDemo"]),
  ],
  traits: [
    .trait(
      name: "SyntaxHighlighting",
      description: "Enable the Highlight-based TermLoomSyntaxHighlighting product"
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
    .target(name: "TermLoom"),
    .target(
      name: "TermLoomSyntaxHighlighting",
      dependencies: [
        "TermLoom",
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
      name: "TermLoomTestSupport",
      dependencies: [
        "TermLoom",
        .product(
          name: "InlineSnapshotTesting", package: "swift-snapshot-testing",
          condition: .when(traits: ["TestSupport"])),
      ]
    ),
    .executableTarget(
      name: "TermLoomDemo",
      dependencies: ["TermLoom"]
    ),
    .executableTarget(
      name: "TermLoomBenchmark",
      dependencies: ["TermLoom"]
    ),
    .executableTarget(
      name: "TermLoomCounter",
      dependencies: ["TermLoom"]
    ),
    .executableTarget(
      name: "TermLoomGallery",
      dependencies: ["TermLoom"]
    ),
    .executableTarget(
      name: "TermLoomObservationDemo",
      dependencies: ["TermLoom"]
    ),
    .testTarget(
      name: "TermLoomTests",
      dependencies: [
        "TermLoom",
        .target(name: "TermLoomTestSupport", condition: .when(traits: ["TestSupport"])),
        .product(
          name: "CustomDump", package: "swift-custom-dump",
          condition: .when(traits: ["TestSupport"])),
      ],
      resources: [.copy("Fixtures/emoji-test.txt")]
    ),
    .testTarget(
      name: "TermLoomSyntaxHighlightingTests",
      dependencies: ["TermLoomSyntaxHighlighting"]
    ),
  ],
  swiftLanguageModes: [.v6]
)
