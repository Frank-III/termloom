// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "ratatui-postcat-example",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "ratatui-postcat", targets: ["PostcatExample"])
  ],
  traits: [
    .trait(
      name: "DevTools",
      description: "Enable the F12 diagnostics overlay from RatatuiDevTools"
    )
  ],
  dependencies: [
    .package(path: "../..", traits: ["SyntaxHighlighting"]),
    .package(path: "../../Packages/RatatuiDevTools", traits: ["Overlays"]),
    .package(path: "../../Packages/RatatuiOverlays"),
    .package(path: "../../Packages/RatatuiTextArea"),
  ],
  targets: [
    .target(
      name: "PostcatExampleCore",
      dependencies: [
        .product(name: "Ratatui", package: "ratetui-swift"),
        .product(name: "RatatuiSyntaxHighlighting", package: "ratetui-swift"),
        .product(name: "RatatuiOverlays", package: "RatatuiOverlays"),
        .product(name: "RatatuiTextArea", package: "RatatuiTextArea"),
        .product(
          name: "RatatuiDevTools", package: "RatatuiDevTools",
          condition: .when(traits: ["DevTools"])),
      ]
    ),
    .executableTarget(
      name: "PostcatExample",
      dependencies: ["PostcatExampleCore"]
    ),
    .testTarget(
      name: "PostcatExampleCoreTests",
      dependencies: ["PostcatExampleCore", .product(name: "Ratatui", package: "ratetui-swift")]
    ),
  ],
  swiftLanguageModes: [.v6]
)
