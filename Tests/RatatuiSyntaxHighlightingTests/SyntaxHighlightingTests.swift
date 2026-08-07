import Foundation
import RatatuiSyntaxHighlighting
import Testing

@Suite struct SyntaxHighlightingTests {
  @Test func highlightsMultipleLanguagesAndDetectsPaths() {
    let highlighter = TerminalSyntaxHighlighter()
    let theme = SyntaxTheme.named("dracula")!
    let swift = highlighter.highlight("let answer = 42", language: "swift", theme: theme)
    let rust = highlighter.highlight("fn main() {}", language: "rust", theme: theme)
    let unknown = highlighter.highlight("let answer = 42", language: nil, theme: theme)

    #expect(swift.map(\.content).joined() == "let answer = 42")
    #expect(rust.map(\.content).joined() == "fn main() {}")
    #expect(Set(swift.map(\.style)).count > 1)
    #expect(unknown.count == 1)
    #expect(TerminalSyntaxHighlighter.language(forPath: "Sources/App.swift") == "swift")
    #expect(TerminalSyntaxHighlighter.language(forPath: "Dockerfile") == "dockerfile")
  }

  @Test func exposesCodexThemeCatalog() {
    #expect(SyntaxTheme.builtins.count == 32)
    #expect(SyntaxTheme.named("base16-ocean-dark") != nil)
    #expect(SyntaxTheme.named("catppuccin-mocha") != nil)
  }

  @Test func loadsTextMateTheme() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("Custom.tmTheme")
    let plist: [String: Any] = [
      "name": "Custom",
      "settings": [
        ["settings": ["foreground": "#DDDDDD", "background": "#101010"]],
        ["scope": "comment.line", "settings": ["foreground": "#778899", "fontStyle": "italic"]],
      ],
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try data.write(to: url)

    let theme = try SyntaxTheme.textMateTheme(at: url)
    #expect(theme.name == "Custom")
    #expect(theme.style(for: "comment").modifiers.contains(.italic))
  }
}
