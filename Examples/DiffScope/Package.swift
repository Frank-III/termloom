// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "ratatui-diffscope-example",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "ratatui-diffscope", targets: ["DiffScopeExample"])
  ],
  dependencies: [
    .package(path: "../..", traits: []),
    .package(path: "../../Packages/RatatuiOverlays"),
  ],
  targets: [
    .target(
      name: "DiffScopeExampleCore",
      dependencies: [
        .product(name: "Ratatui", package: "ratetui-swift"),
        .product(name: "RatatuiOverlays", package: "RatatuiOverlays"),
      ]
    ),
    .executableTarget(
      name: "DiffScopeExample",
      dependencies: ["DiffScopeExampleCore"]
    ),
    .testTarget(
      name: "DiffScopeExampleCoreTests",
      dependencies: [
        "DiffScopeExampleCore",
        .product(name: "Ratatui", package: "ratetui-swift"),
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
