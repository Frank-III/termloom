import Foundation
import Highlight
import HighlightLanguagesExtended
import Ratatui

public struct TerminalSyntaxHighlighter: Sendable {
  private let engine: Highlighter
  private let engineLock: NSLock
  private let cache: CacheStorage

  public init() {
    engine = Highlighter(languages: AllLanguages.all)
    engineLock = NSLock()
    cache = CacheStorage()
  }

  public func highlight(
    _ code: String, language: String?, theme: SyntaxTheme, background: Color? = nil
  ) -> [Span] {
    let codeBytes = code.utf8.count
    guard cache.canStore(codeBytes: codeBytes) else {
      return makeSpans(code, language: language, theme: theme, background: background)
    }

    let key = CacheKey(code: code, language: language, theme: theme, background: background)
    if let cached = cache.value(for: key) { return cached }
    let spans = makeSpans(code, language: language, theme: theme, background: background)
    return cache.insert(spans, for: key, codeBytes: codeBytes)
  }

  private func makeSpans(
    _ code: String, language: String?, theme: SyntaxTheme, background: Color?
  ) -> [Span] {
    let result: HighlightResult?
    if let language {
      // swift-highlight advertises concurrent use, but serializing one shared engine also protects grammar warmup.
      engineLock.lock()
      result = engine.highlight(code, language: language)
      engineLock.unlock()
    } else {
      result = nil
    }

    if let result {
      var highlighted: [Span] = []
      append(
        result.tree, inherited: theme.plain, theme: theme, background: background,
        to: &highlighted)
      if !highlighted.isEmpty { return highlighted }
    }

    var style = theme.plain.style
    if let background { style.background = background }
    return [Span(code, style: style)]
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

  private struct CacheKey: Hashable, Sendable {
    var code: String
    var language: String?
    var theme: SyntaxTheme
    var background: Color?
  }

  private struct CacheEntry: Sendable {
    var spans: [Span]
    var codeBytes: Int
    var lastAccess: UInt64
  }

  private struct CacheState: Sendable {
    var clock: UInt64 = 0
    var cachedCodeBytes = 0
    var entries: [CacheKey: CacheEntry] = [:]
    var hits: UInt64 = 0
    var misses: UInt64 = 0
  }

  private final class CacheStorage: @unchecked Sendable {
    private static let capacity = 256
    private static let maximumEntryCodeBytes = 16 * 1_024
    private static let maximumCachedCodeBytes = 1_024 * 1_024

    private let lock = NSLock()
    private var state = CacheState()

    func canStore(codeBytes: Int) -> Bool {
      codeBytes <= Self.maximumEntryCodeBytes
    }

    func value(for key: CacheKey) -> [Span]? {
      lock.lock()
      defer { lock.unlock() }

      guard var entry = state.entries[key] else {
        state.misses &+= 1
        return nil
      }
      state.clock &+= 1
      entry.lastAccess = state.clock
      state.entries[key] = entry
      state.hits &+= 1
      return entry.spans
    }

    func insert(_ spans: [Span], for key: CacheKey, codeBytes: Int) -> [Span] {
      guard codeBytes <= Self.maximumEntryCodeBytes else { return spans }
      lock.lock()
      defer { lock.unlock() }

      if var existing = state.entries[key] {
        state.clock &+= 1
        existing.lastAccess = state.clock
        state.entries[key] = existing
        return existing.spans
      }

      while state.entries.count >= Self.capacity
        || state.cachedCodeBytes + codeBytes > Self.maximumCachedCodeBytes
      {
        guard
          let leastRecentlyUsed = state.entries.min(by: {
            $0.value.lastAccess < $1.value.lastAccess
          })?.key,
          let removed = state.entries.removeValue(forKey: leastRecentlyUsed)
        else { break }
        state.cachedCodeBytes -= removed.codeBytes
      }

      state.clock &+= 1
      state.entries[key] = CacheEntry(
        spans: spans, codeBytes: codeBytes, lastAccess: state.clock)
      state.cachedCodeBytes += codeBytes
      return spans
    }

    var statistics: (entries: Int, cachedCodeBytes: Int, hits: UInt64, misses: UInt64) {
      lock.lock()
      defer { lock.unlock() }
      return (state.entries.count, state.cachedCodeBytes, state.hits, state.misses)
    }
  }

  internal var cacheStatistics:
    (
      entries: Int, cachedCodeBytes: Int, hits: UInt64, misses: UInt64
    )
  {
    cache.statistics
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
