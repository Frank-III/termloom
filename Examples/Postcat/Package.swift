// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "termloom-postcat-example",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "termloom-postcat", targets: ["PostcatExample"])
  ],
  traits: [
    .trait(
      name: "DevTools",
      description: "Enable the F12 diagnostics overlay from TermLoomDevTools"
    )
  ],
  dependencies: [
    .package(path: "../..", traits: ["SyntaxHighlighting"]),
    .package(path: "../../Packages/TermLoomDevTools", traits: ["Overlays"]),
    .package(path: "../../Packages/TermLoomOverlays"),
    .package(path: "../../Packages/TermLoomTextArea"),
  ],
  targets: [
    .target(
      name: "PostcatExampleCore",
      dependencies: [
        .product(name: "TermLoom", package: "termloom"),
        .product(name: "TermLoomSyntaxHighlighting", package: "termloom"),
        .product(name: "TermLoomOverlays", package: "TermLoomOverlays"),
        .product(name: "TermLoomTextArea", package: "TermLoomTextArea"),
        .product(
          name: "TermLoomDevTools", package: "TermLoomDevTools",
          condition: .when(traits: ["DevTools"])),
      ]
    ),
    .executableTarget(
      name: "PostcatExample",
      dependencies: ["PostcatExampleCore"]
    ),
    .testTarget(
      name: "PostcatExampleCoreTests",
      dependencies: ["PostcatExampleCore", .product(name: "TermLoom", package: "termloom")]
    ),
  ],
  swiftLanguageModes: [.v6]
)
