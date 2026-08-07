import Foundation
import Ratatui
import Testing

@testable import RatatuiSyntaxHighlighting

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

  @Test func repeatedHighlightsReuseABoundedInputSensitiveCache() {
    let highlighter = TerminalSyntaxHighlighter()
    let theme = SyntaxTheme.named("dracula")!
    let code = "let answer = 42"

    let first = highlighter.highlight(code, language: "swift", theme: theme)
    let second = highlighter.highlight(code, language: "swift", theme: theme)
    let alternateBackground = highlighter.highlight(
      code, language: "swift", theme: theme, background: .blue)
    let alternateLanguage = highlighter.highlight(code, language: nil, theme: theme)
    let alternateTheme = highlighter.highlight(
      code, language: "swift", theme: SyntaxTheme.named("github")!)

    #expect(first == second)
    #expect(alternateBackground != first)
    #expect(alternateLanguage != first)
    #expect(alternateTheme != first)
    #expect(highlighter.cacheStatistics.entries == 4)
    #expect(highlighter.cacheStatistics.hits == 1)
    #expect(highlighter.cacheStatistics.misses == 4)

    for index in 0..<300 {
      _ = highlighter.highlight("let value = \(index)", language: "swift", theme: theme)
    }
    #expect(highlighter.cacheStatistics.entries == 256)
    #expect(highlighter.cacheStatistics.cachedCodeBytes <= 1_024 * 1_024)
  }

  @Test func concurrentCacheMissesRemainDeterministic() async {
    let reference = TerminalSyntaxHighlighter()
    let highlighter = TerminalSyntaxHighlighter()
    let theme = SyntaxTheme.named("dracula")!
    let expected = reference.highlight("let shared = 42", language: "swift", theme: theme)

    let results = await withTaskGroup(of: [Span].self, returning: [[Span]].self) { group in
      for _ in 0..<32 {
        group.addTask {
          highlighter.highlight("let shared = 42", language: "swift", theme: theme)
        }
      }
      var values: [[Span]] = []
      for await value in group { values.append(value) }
      return values
    }

    let statistics = highlighter.cacheStatistics
    #expect(results.count == 32)
    #expect(results.allSatisfy { $0 == expected })
    #expect(statistics.entries == 1)
    #expect(statistics.misses >= 1)
    #expect(statistics.hits + statistics.misses == 32)
  }

  @Test func cacheEvictsByAggregateCodeBytesBeforeEntryCapacity() {
    let highlighter = TerminalSyntaxHighlighter()
    let theme = SyntaxTheme.named("dracula")!

    for index in 0..<80 {
      _ = highlighter.highlight(
        String(repeating: "x", count: 15_000) + "\(index)", language: nil, theme: theme)
    }

    #expect(highlighter.cacheStatistics.entries == 69)
    #expect(highlighter.cacheStatistics.cachedCodeBytes <= 1_024 * 1_024)
  }

  @Test func cacheEvictionUsesLeastRecentlyAccessedEntry() {
    let highlighter = TerminalSyntaxHighlighter()
    let theme = SyntaxTheme.named("dracula")!

    for index in 0..<256 {
      _ = highlighter.highlight("value \(index)", language: nil, theme: theme)
    }
    _ = highlighter.highlight("value 0", language: nil, theme: theme)
    _ = highlighter.highlight("value 256", language: nil, theme: theme)
    _ = highlighter.highlight("value 0", language: nil, theme: theme)
    _ = highlighter.highlight("value 1", language: nil, theme: theme)

    let statistics = highlighter.cacheStatistics
    #expect(statistics.entries == 256)
    #expect(statistics.hits == 2)
    #expect(statistics.misses == 258)
  }

  @Test func oversizedHighlightsDoNotRemainCached() {
    let highlighter = TerminalSyntaxHighlighter()
    let theme = SyntaxTheme.named("dracula")!
    let code = String(repeating: "let value = 42; ", count: 1_100)

    let first = highlighter.highlight(code, language: "swift", theme: theme)
    let second = highlighter.highlight(code, language: "swift", theme: theme)

    #expect(first == second)
    #expect(highlighter.cacheStatistics.entries == 0)
    #expect(highlighter.cacheStatistics.hits == 0)
    #expect(highlighter.cacheStatistics.misses == 0)
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
