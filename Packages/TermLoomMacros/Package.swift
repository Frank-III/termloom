// swift-tools-version: 6.2

import CompilerPluginSupport
import PackageDescription

let package = Package(
  name: "termloom-macros",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "TermLoomMacros", targets: ["TermLoomMacros"])
  ],
  dependencies: [
    .package(path: "../..", traits: []),
    .package(url: "https://github.com/swiftlang/swift-syntax", from: "603.0.0"),
  ],
  targets: [
    .macro(
      name: "TermLoomWidgetMacros",
      dependencies: [
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
      ]
    ),
    .target(
      name: "TermLoomMacros",
      dependencies: [
        "TermLoomWidgetMacros",
        .product(name: "TermLoom", package: "termloom"),
      ]
    ),
    .testTarget(
      name: "TermLoomMacrosTests",
      dependencies: [
        "TermLoomMacros",
        "TermLoomWidgetMacros",
        .product(name: "TermLoom", package: "termloom"),
        .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
