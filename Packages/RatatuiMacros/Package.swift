// swift-tools-version: 6.2

import CompilerPluginSupport
import PackageDescription

let package = Package(
  name: "ratatui-macros",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "RatatuiMacros", targets: ["RatatuiMacros"])
  ],
  dependencies: [
    .package(path: "../..", traits: []),
    .package(url: "https://github.com/swiftlang/swift-syntax", from: "603.0.0"),
  ],
  targets: [
    .macro(
      name: "RatatuiWidgetMacros",
      dependencies: [
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
      ]
    ),
    .target(
      name: "RatatuiMacros",
      dependencies: [
        "RatatuiWidgetMacros",
        .product(name: "Ratatui", package: "ratetui-swift"),
      ]
    ),
    .testTarget(
      name: "RatatuiMacrosTests",
      dependencies: [
        "RatatuiMacros",
        "RatatuiWidgetMacros",
        .product(name: "Ratatui", package: "ratetui-swift"),
        .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
