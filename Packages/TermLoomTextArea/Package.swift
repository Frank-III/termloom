// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "termloom-textarea",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "TermLoomTextArea", targets: ["TermLoomTextArea"])
  ],
  dependencies: [
    .package(path: "../..", traits: [])
  ],
  targets: [
    .target(
      name: "TermLoomTextArea",
      dependencies: [.product(name: "TermLoom", package: "termloom")]
    ),
    .testTarget(
      name: "TermLoomTextAreaTests",
      dependencies: ["TermLoomTextArea", .product(name: "TermLoom", package: "termloom")]
    ),
  ],
  swiftLanguageModes: [.v6]
)
