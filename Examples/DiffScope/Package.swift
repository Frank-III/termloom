// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "termloom-diffscope-example",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "termloom-diffscope", targets: ["DiffScopeExample"])
  ],
  dependencies: [
    .package(path: "../..", traits: []),
    .package(path: "../../Packages/TermLoomOverlays"),
  ],
  targets: [
    .target(
      name: "DiffScopeExampleCore",
      dependencies: [
        .product(name: "TermLoom", package: "termloom"),
        .product(name: "TermLoomOverlays", package: "TermLoomOverlays"),
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
        .product(name: "TermLoom", package: "termloom"),
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
