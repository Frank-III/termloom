public struct Span: Hashable, Sendable, ExpressibleByStringLiteral, Stylable {
  public var content: String
  public var style: Style

  public init(_ content: String, style: Style = .plain) {
    self.content = content
    self.style = style
  }

  public init(stringLiteral value: String) {
    self.init(value)
  }

  public var width: Int { TerminalWidth.of(content) }

}

@resultBuilder
public enum SpanBuilder {
  public static func buildExpression(_ expression: Span) -> [Span] { [expression] }
  public static func buildExpression(_ expression: String) -> [Span] { [Span(expression)] }
  public static func buildBlock(_ components: [Span]...) -> [Span] { components.flatMap { $0 } }
  public static func buildOptional(_ component: [Span]?) -> [Span] { component ?? [] }
  public static func buildEither(first component: [Span]) -> [Span] { component }
  public static func buildEither(second component: [Span]) -> [Span] { component }
  public static func buildArray(_ components: [[Span]]) -> [Span] { components.flatMap { $0 } }
}

public struct Line: Hashable, Sendable, ExpressibleByStringLiteral, Stylable, Widget {
  public var spans: [Span]
  public var style: Style
  public var alignment: Alignment?

  public init(
    _ content: String,
    style: Style = .plain,
    alignment: Alignment? = nil
  ) {
    spans = [Span(content)]
    self.style = style
    self.alignment = alignment
  }

  public init(
    _ spans: [Span],
    style: Style = .plain,
    alignment: Alignment? = nil
  ) {
    self.spans = spans
    self.style = style
    self.alignment = alignment
  }

  public init(
    style: Style = .plain,
    alignment: Alignment? = nil,
    @SpanBuilder spans: () -> [Span]
  ) {
    self.spans = spans()
    self.style = style
    self.alignment = alignment
  }

  public init(stringLiteral value: String) {
    self.init(value)
  }

  public var width: Int { spans.reduce(0) { $0 + $1.width } }
  public var content: String { spans.map(\.content).joined() }

  public func alignment(_ alignment: Alignment) -> Self {
    var copy = self
    copy.alignment = alignment
    return copy
  }

  public func pushSpan(_ span: Span) -> Self {
    var copy = self
    copy.spans.append(span)
    return copy
  }

  public func render(in area: Rect, into frame: inout Frame) {
    render(in: area, into: &frame.buffer, parentStyle: .plain, parentAlignment: nil)
  }

  func render(
    in area: Rect,
    into buffer: inout Buffer,
    parentStyle: Style,
    parentAlignment: Alignment?
  ) {
    let area = area.intersection(buffer.area)
    guard !area.isEmpty else { return }
    let row = Rect(x: area.x, y: area.y, width: area.width, height: 1)
    let lineWidth = width
    guard lineWidth > 0 else { return }
    if style != .plain { buffer.setStyle(style, in: row) }
    let areaWidth = Int(row.width)
    let resolvedAlignment = alignment ?? parentAlignment ?? .leading
    let leadingSkip: Int
    let indent: Int
    if lineWidth <= areaWidth {
      leadingSkip = 0
      indent =
        switch resolvedAlignment {
        case .leading: 0
        case .center: (areaWidth - lineWidth) / 2
        case .trailing: areaWidth - lineWidth
        }
    } else {
      indent = 0
      leadingSkip =
        switch resolvedAlignment {
        case .leading: 0
        case .center: (lineWidth - areaWidth) / 2
        case .trailing: lineWidth - areaWidth
        }
    }

    var skipped = 0
    var position = Position(
      x: UInt16(clamping: Int(row.x) + indent),
      y: row.y
    )
    let end = Int(row.x) + Int(row.width)
    for span in spans {
      for character in span.content {
        let characterWidth = TerminalWidth.of(character)
        if skipped < leadingSkip {
          let endOfCharacter = skipped + characterWidth
          if endOfCharacter > leadingSkip {
            position.x = UInt16(
              clamping: Int(position.x) + endOfCharacter - leadingSkip
            )
          }
          skipped = endOfCharacter
          continue
        }
        guard characterWidth > 0 else { continue }
        guard Int(position.x) + characterWidth <= end else { return }
        let inherited =
          buffer.cell(at: position)?.style
          ?? parentStyle.patching(style)
        position = buffer.setString(
          String(character),
          at: position,
          style: inherited.patching(span.style),
          maxWidth: UInt16(clamping: end - Int(position.x))
        )
      }
    }
  }
}

@resultBuilder
public enum LineBuilder {
  public static func buildExpression(_ expression: Line) -> [Line] { [expression] }
  public static func buildExpression(_ expression: String) -> [Line] { [Line(expression)] }
  public static func buildBlock(_ components: [Line]...) -> [Line] { components.flatMap { $0 } }
  public static func buildOptional(_ component: [Line]?) -> [Line] { component ?? [] }
  public static func buildEither(first component: [Line]) -> [Line] { component }
  public static func buildEither(second component: [Line]) -> [Line] { component }
  public static func buildArray(_ components: [[Line]]) -> [Line] { components.flatMap { $0 } }
}

public enum WrapMode: Hashable, Sendable {
  case none
  case character
  case word
}

public struct Paragraph: Widget, Hashable, Sendable {
  public var lines: [Line]
  public var style: Style
  public var wrap: WrapMode
  public var scroll: UInt16
  public var horizontalScroll: UInt16
  public var trimLeadingWhitespace: Bool

  public init(
    _ content: String,
    style: Style = .plain,
    wrap: WrapMode = .none,
    scroll: UInt16 = 0,
    horizontalScroll: UInt16 = 0,
    trimLeadingWhitespace: Bool = true
  ) {
    lines = content.split(separator: "\n", omittingEmptySubsequences: false).map {
      Line(String($0))
    }
    self.style = style
    self.wrap = wrap
    self.scroll = scroll
    self.horizontalScroll = horizontalScroll
    self.trimLeadingWhitespace = trimLeadingWhitespace
  }

  public init(
    style: Style = .plain,
    wrap: WrapMode = .none,
    scroll: UInt16 = 0,
    horizontalScroll: UInt16 = 0,
    trimLeadingWhitespace: Bool = true,
    @LineBuilder lines: () -> [Line]
  ) {
    self.lines = lines()
    self.style = style
    self.wrap = wrap
    self.scroll = scroll
    self.horizontalScroll = horizontalScroll
    self.trimLeadingWhitespace = trimLeadingWhitespace
  }

  public init(
    _ text: Text,
    wrap: WrapMode = .none,
    scroll: UInt16 = 0,
    horizontalScroll: UInt16 = 0,
    trimLeadingWhitespace: Bool = true
  ) {
    lines = text.lines.map { line in
      guard line.alignment == nil, let alignment = text.alignment else { return line }
      return line.alignment(alignment)
    }
    style = text.style
    self.wrap = wrap
    self.scroll = scroll
    self.horizontalScroll = horizontalScroll
    self.trimLeadingWhitespace = trimLeadingWhitespace
  }

  public func render(in area: Rect, into frame: inout Frame) {
    guard !area.isEmpty else { return }
    if style != .plain {
      frame.buffer.setStyle(style, in: area)
    }
    let width = Int(area.width)
    let height = Int(area.height)
    if wrap == .none {
      for (row, sourceLine) in lines.dropFirst(Int(scroll)).prefix(height).enumerated() {
        guard let visualLine = visualLines(for: sourceLine, width: width).first else { continue }
        render(visualLine, at: row, width: width, in: area, into: &frame.buffer)
      }
      return
    }

    var remainingScroll = Int(scroll)
    var renderedLineCount = 0
    for sourceLine in lines {
      let neededLineCount = remainingScroll + height - renderedLineCount
      guard neededLineCount > 0 else { break }
      let sourceVisualLines = visualLines(
        for: sourceLine,
        width: width,
        maximumCount: neededLineCount
      )
      if remainingScroll >= sourceVisualLines.count {
        remainingScroll -= sourceVisualLines.count
        continue
      }

      for unscrolledLine in sourceVisualLines.dropFirst(remainingScroll) {
        render(
          unscrolledLine,
          at: renderedLineCount,
          width: width,
          in: area,
          into: &frame.buffer
        )
        renderedLineCount += 1
        guard renderedLineCount < height else { return }
      }
      remainingScroll = 0
    }
  }

  public func lineCount(width: UInt16) -> Int {
    guard width > 0 else { return 0 }
    return lines.reduce(0) { $0 + visualLines(for: $1, width: Int(width)).count }
  }

  public var lineWidth: Int {
    lines.map(\.width).max() ?? 0
  }

  fileprivate struct Glyph {
    var character: Character
    var style: Style
    var alignment: Alignment
  }

  private func render(
    _ unscrolledLine: [Glyph],
    at row: Int,
    width: Int,
    in area: Rect,
    into buffer: inout Buffer
  ) {
    let line = horizontallyScrolled(unscrolledLine, width: width)
    let usedWidth = line.reduce(0) { $0 + TerminalWidth.of($1.character) }
    let offset: Int
    switch line.first?.alignment ?? .leading {
    case .leading: offset = 0
    case .center: offset = max(0, (width - usedWidth) / 2)
    case .trailing: offset = max(0, width - usedWidth)
    }
    var position = Position(
      x: UInt16(clamping: Int(area.x) + offset),
      y: UInt16(clamping: Int(area.y) + row)
    )
    for glyph in line {
      guard TerminalWidth.of(glyph.character) > 0 else { continue }
      position = buffer.setString(
        String(glyph.character),
        at: position,
        style: glyph.style,
        maxWidth: UInt16(clamping: Int(area.x) + width - Int(position.x))
      )
    }
  }

  private func visualLines(
    for line: Line,
    width: Int,
    maximumCount: Int? = nil
  ) -> [[Glyph]] {
    guard width > 0, maximumCount != 0 else { return [] }
    let glyphs = line.spans.lazy.flatMap { span in
      let glyphStyle = style.patching(line.style).patching(span.style)
      let alignment = line.alignment ?? .leading
      return span.content.lazy.map {
        Glyph(character: $0, style: glyphStyle, alignment: alignment)
      }
    }
    switch wrap {
    case .none:
      return [Array(glyphs)]
    case .character:
      return wrapCharacters(glyphs, width: width, maximumCount: maximumCount)
    case .word:
      return wrapWords(glyphs, width: width, maximumCount: maximumCount)
    }
  }

  private func wrapCharacters(
    _ glyphs: some Sequence<Glyph>,
    width: Int,
    maximumCount: Int?
  ) -> [[Glyph]] {
    var result: [[Glyph]] = []
    var line: [Glyph] = []
    var lineWidth = 0
    var sawGlyph = false
    for glyph in glyphs {
      sawGlyph = true
      let glyphWidth = TerminalWidth.of(glyph.character)
      guard glyphWidth <= width else { continue }
      if glyphWidth > 0, lineWidth + glyphWidth > width {
        result.append(line)
        if result.count == maximumCount { return result }
        line = []
        lineWidth = 0
      }
      line.append(glyph)
      lineWidth += glyphWidth
    }
    if !line.isEmpty || !sawGlyph { result.append(line) }
    return result
  }

  /// Mirrors Ratatui's streaming word wrapper. Whitespace is held until the
  /// following word is known to fit, which preserves indentation when asked
  /// while allowing boundary whitespace to be trimmed without losing styles.
  private func wrapWords(
    _ glyphs: some Sequence<Glyph>,
    width: Int,
    maximumCount: Int?
  ) -> [[Glyph]] {
    var wrapped: [[Glyph]] = []
    var pendingLine: [Glyph] = []
    var pendingWord: [Glyph] = []
    var pendingWhitespace: [Glyph] = []
    var lineWidth = 0
    var wordWidth = 0
    var whitespaceWidth = 0
    var previousWasNonWhitespace = false

    for glyph in glyphs {
      let glyphWidth = TerminalWidth.of(glyph.character)
      guard glyphWidth <= width else { continue }
      let isWhitespace = Self.isWrappingWhitespace(glyph.character)
      let wordFound = previousWasNonWhitespace && isWhitespace
      let trimmedOverflow =
        pendingLine.isEmpty && trimLeadingWhitespace && wordWidth + glyphWidth > width
      let whitespaceOverflow =
        pendingLine.isEmpty && trimLeadingWhitespace && whitespaceWidth + glyphWidth > width
      let untrimmedOverflow =
        pendingLine.isEmpty && !trimLeadingWhitespace
        && wordWidth + whitespaceWidth + glyphWidth > width

      if wordFound || trimmedOverflow || whitespaceOverflow || untrimmedOverflow {
        if !pendingLine.isEmpty || !trimLeadingWhitespace {
          pendingLine.append(contentsOf: pendingWhitespace)
          lineWidth += whitespaceWidth
        }
        pendingLine.append(contentsOf: pendingWord)
        lineWidth += wordWidth
        pendingWord.removeAll(keepingCapacity: true)
        pendingWhitespace.removeAll(keepingCapacity: true)
        whitespaceWidth = 0
        wordWidth = 0
      }

      let lineFull = lineWidth >= width
      let pendingWordOverflows =
        glyphWidth > 0 && lineWidth + whitespaceWidth + wordWidth >= width
      if lineFull || pendingWordOverflows {
        var remainingWidth = max(0, width - lineWidth)
        wrapped.append(pendingLine)
        if wrapped.count == maximumCount { return wrapped }
        pendingLine = []
        lineWidth = 0

        var consumedWhitespace = 0
        while consumedWhitespace < pendingWhitespace.count {
          let first = pendingWhitespace[consumedWhitespace]
          let firstWidth = TerminalWidth.of(first.character)
          guard firstWidth <= remainingWidth else { break }
          whitespaceWidth -= firstWidth
          remainingWidth -= firstWidth
          consumedWhitespace += 1
        }
        if consumedWhitespace > 0 {
          pendingWhitespace.removeFirst(consumedWhitespace)
        }
        if isWhitespace, pendingWhitespace.isEmpty {
          previousWasNonWhitespace = false
          continue
        }
      }

      if isWhitespace {
        pendingWhitespace.append(glyph)
        whitespaceWidth += glyphWidth
      } else {
        pendingWord.append(glyph)
        wordWidth += glyphWidth
      }
      previousWasNonWhitespace = !isWhitespace
    }

    if pendingLine.isEmpty, pendingWord.isEmpty, !pendingWhitespace.isEmpty,
      trimLeadingWhitespace
    {
      wrapped.append([])
      if wrapped.count == maximumCount { return wrapped }
    }
    if !pendingLine.isEmpty || !trimLeadingWhitespace {
      pendingLine.append(contentsOf: pendingWhitespace)
    }
    pendingLine.append(contentsOf: pendingWord)
    if !pendingLine.isEmpty {
      wrapped.append(pendingLine)
    }
    if wrapped.isEmpty { wrapped.append([]) }
    return wrapped
  }

  private static func isWrappingWhitespace(_ character: Character) -> Bool {
    if character == "\u{200B}" { return true }
    if character == "\u{00A0}" { return false }
    return character.isWhitespace
  }

  private func horizontallyScrolled(_ glyphs: [Glyph], width: Int) -> [Glyph] {
    guard width > 0 else { return [] }
    guard horizontalScroll > 0, glyphs.first?.alignment == .leading else {
      return Array(glyphs.prefixFitting(width: width))
    }
    var skipped = 0
    let start =
      glyphs.firstIndex { glyph in
        let glyphWidth = TerminalWidth.of(glyph.character)
        if skipped + glyphWidth <= Int(horizontalScroll) {
          skipped += glyphWidth
          return false
        }
        return true
      } ?? glyphs.endIndex
    return Array(Array(glyphs[start...]).prefixFitting(width: width))
  }

  public func foregroundStyle(_ color: Color) -> Self {
    var copy = self
    copy.style.foreground = color
    return copy
  }

  public func backgroundStyle(_ color: Color) -> Self {
    var copy = self
    copy.style.background = color
    return copy
  }

  public func bold(_ active: Bool = true) -> Self {
    var copy = self
    copy.style = active ? copy.style.adding(.bold) : copy.style.removing(.bold)
    return copy
  }
}

extension Array where Element == Paragraph.Glyph {
  fileprivate func prefixFitting(width: Int) -> ArraySlice<Element> {
    var used = 0
    let end =
      firstIndex { glyph in
        used += TerminalWidth.of(glyph.character)
        return used > width
      } ?? endIndex
    return self[..<end]
  }
}
