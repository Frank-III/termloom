import Highlight
import HighlightLanguagesExtended
import TermLoom

public struct TerminalSyntaxHighlighter: Sendable {
  private let engine: Highlighter

  public init() {
    engine = Highlighter(languages: AllLanguages.all)
  }

  public func highlight(
    _ code: String, language: String?, theme: SyntaxTheme, background: Color? = nil
  ) -> [Span] {
    guard let language, let result = engine.highlight(code, language: language) else {
      var style = theme.plain.style
      if let background { style.background = background }
      return [Span(code, style: style)]
    }
    var spans: [Span] = []
    append(result.tree, inherited: theme.plain, theme: theme, background: background, to: &spans)
    return spans.isEmpty ? [Span(code, style: theme.plain.style)] : spans
  }

  public func highlightLines(
    _ code: String, language: String?, theme: SyntaxTheme, background: Color? = nil
  ) -> [[Span]] {
    var lines: [[Span]] = [[]]
    for span in highlight(code, language: language, theme: theme, background: background) {
      let pieces = span.content.split(separator: "\n", omittingEmptySubsequences: false)
      for (index, piece) in pieces.enumerated() {
        if index > 0 { lines.append([]) }
        if !piece.isEmpty { lines[lines.count - 1].append(Span(String(piece), style: span.style)) }
      }
    }
    return lines
  }

  public static func language(forPath path: String) -> String? {
    let filename = path.split(separator: "/").last.map(String.init)?.lowercased() ?? ""
    if let direct = filenames[filename] { return direct }
    let ext = filename.split(separator: ".").last.map(String.init) ?? ""
    return extensions[ext]
  }

  private func append(
    _ node: HighlightNode, inherited: SyntaxTokenStyle, theme: SyntaxTheme,
    background: Color?, to spans: inout [Span]
  ) {
    switch node {
    case .text(let text):
      guard !text.isEmpty else { return }
      var style = inherited.style
      if let background { style.background = background }
      if let last = spans.last, last.style == style {
        spans[spans.count - 1] = Span(last.content + text, style: style)
      } else {
        spans.append(Span(text, style: style))
      }
    case .element(let scope, let children):
      let style = scope.map(theme.style(for:)) ?? inherited
      for child in children {
        append(child, inherited: style, theme: theme, background: background, to: &spans)
      }
    }
  }

  private static let filenames: [String: String] = [
    "dockerfile": "dockerfile", "makefile": "makefile", "package.swift": "swift",
    "cargo.toml": "ini", ".gitignore": "plaintext", ".env": "ini",
  ]

  private static let extensions: [String: String] = [
    "swift": "swift", "rs": "rust", "zig": "zig", "c": "c", "h": "c", "cc": "cpp",
    "cpp": "cpp", "hpp": "cpp", "m": "objectivec", "mm": "objectivec", "go": "go",
    "js": "javascript", "mjs": "javascript", "cjs": "javascript", "jsx": "javascript",
    "ts": "typescript", "tsx": "typescript", "py": "python", "rb": "ruby", "php": "php",
    "java": "java", "kt": "kotlin", "kts": "kotlin", "cs": "csharp", "sh": "bash",
    "bash": "bash", "zsh": "bash", "fish": "bash", "json": "json", "jsonl": "json",
    "yaml": "yaml", "yml": "yaml", "toml": "ini", "ini": "ini", "xml": "xml",
    "html": "xml", "css": "css", "scss": "scss", "sql": "sql", "md": "markdown",
    "diff": "diff", "patch": "diff", "proto": "protobuf", "dart": "dart",
  ]
}
