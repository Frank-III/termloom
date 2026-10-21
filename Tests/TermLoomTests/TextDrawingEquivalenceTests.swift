import Testing

@testable import TermLoom

/// The printable-ASCII fast paths and the measure-once glyph pipeline must draw exactly what the
/// previous grapheme-by-grapheme implementation drew. The `TextDrawingReference` namespace below is a
/// verbatim copy of that implementation (Buffer.setString, Line rendering, Paragraph wrapping and
/// rendering, the Table plain-line renderer), written against the public Buffer API. Every
/// comparison checks the buffer area and, per cell, the symbol's UTF-8 bytes, style, width and
/// continuation flag, so canonically equivalent but differently encoded symbols would fail too.
@Suite struct TextDrawingEquivalenceTests {
  // MARK: Corpus

  /// Edge cases: empty, ASCII, control characters, tab, DEL, CR LF, combining marks, ZWJ and
  /// modifier emoji, flags, presentation selectors, wide and three-column graphemes, zero-width
  /// spaces and joiners, cross-grapheme ligatures and whitespace used by the word wrapper.
  static let corpus: [String] = [
    "",
    "a",
    "Hello, World!",
    String((0x20...0x7E).map { Character(Unicode.Scalar(UInt8($0))) }),
    "\t",
    "a\tb",
    "\u{0}",
    "\u{1B}[31mred\u{1B}[0m",
    "\u{7F}",
    "x\u{7F}y",
    "a\r\nb",
    "\r\n",
    "\n",
    "\u{85}",
    "e\u{301}",
    "\u{301}",
    "a\u{301}\u{302}b",
    "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}",
    "\u{1F44D}\u{1F3FD}",
    "\u{1F1EF}\u{1F1F5}\u{1F1FA}\u{1F1F8}",
    "\u{1F1EF}",
    "\u{2714}\u{FE0F}",
    "\u{2714}\u{FE0E}",
    "\u{231A}\u{FE0E}",
    "#\u{FE0F}\u{20E3}",
    "\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}",
    "\u{754C}",
    "\u{754C}a\u{754C}",
    "\u{65E5}\u{672C}\u{8A9E}",
    "\u{FF71}\u{FF9E}",
    "\u{200B}",
    "\u{200D}",
    "a\u{200D}b",
    "\u{FE0F}",
    "\u{0644}\u{0627}",
    "\u{1100}\u{1161}\u{11A8}",
    "\u{115F}",
    "\u{17D8}",
    "\u{17A4}",
    "<\u{0338}",
    "\u{201C}\u{FE01}",
    "\u{2026}",
    "  leading",
    "trailing   ",
    "a b  c   d",
    "\u{00A0}nbsp\u{00A0}",
    "foo\u{200B}bar",
    "caf\u{E9} na\u{EF}ve",
    "\u{D55C}\u{AD6D}\u{C5B4} text",
    "word word word word",
    "x",
    " ",
  ]

  /// Short pieces mixed into random strings so graphemes meet at every kind of boundary.
  static let pieces: [String] = [
    "a", "b", "Z", " ", "  ", "-", "~", "\t", "\u{0}", "\u{7F}", "\r", "\n", "\r\n",
    "\u{301}", "e\u{301}", "\u{200D}", "\u{200B}", "\u{FE0F}", "\u{FE0E}", "\u{754C}",
    "\u{1F468}\u{200D}\u{1F469}", "\u{1F44D}", "\u{1F3FD}", "\u{1F1EF}", "\u{1F1F5}",
    "\u{2714}", "\u{17D8}", "\u{0644}", "\u{0627}", "\u{00A0}", "\u{FF9E}", "word", "longer",
  ]

  static func randomString(_ generator: inout TextDrawingGenerator, maxPieces: Int = 8) -> String {
    let count = Int(generator.next() % UInt64(maxPieces + 1))
    var result = ""
    for _ in 0..<count {
      result += pieces[Int(generator.next() % UInt64(pieces.count))]
    }
    return result
  }

  static func randomASCII(_ generator: inout TextDrawingGenerator, maxLength: Int = 24) -> String {
    let count = Int(generator.next() % UInt64(maxLength + 1))
    return String(
      (0..<count).map { _ in
        Character(Unicode.Scalar(UInt8(0x20 + generator.next() % 0x5F)))
      })
  }

  static func strings(seed: UInt64, randomCount: Int) -> [String] {
    var generator = TextDrawingGenerator(seed: seed)
    var result = corpus
    for index in 0..<randomCount {
      result.append(
        index.isMultiple(of: 3)
          ? randomASCII(&generator) : randomString(&generator))
    }
    return result
  }

  static let styles: [Style] = [
    .plain,
    Style(foreground: .red),
    Style(background: .blue, modifiers: [.bold]),
    Style(foreground: .green, removedModifiers: [.bold]),
  ]

  /// Buffers with existing wide glyphs, continuations and styles, so overwrites must clear
  /// partially covered glyphs exactly like before.
  static func prefilledBuffers(area: Rect) -> [Buffer] {
    let empty = Buffer(area: area)
    var wide = Buffer(area: area)
    for row in 0..<area.height {
      TextDrawingReference.setString(
        &wide,
        String(repeating: "\u{754C}", count: area.width),
        at: Position(x: area.x + row % 2, y: area.y + row),
        style: Style(background: .magenta)
      )
    }
    var mixed = Buffer(area: area)
    for row in 0..<area.height {
      TextDrawingReference.setString(
        &mixed,
        "a\u{754C}b\u{1F468}\u{200D}\u{1F469}c\u{17D8}de\u{301}fghijklmnop",
        at: Position(x: area.x, y: area.y + row),
        style: Style(foreground: .yellow, modifiers: [.italic])
      )
    }
    return [empty, wide, mixed]
  }

  // MARK: Comparison

  static func mismatch(_ actual: Buffer, _ expected: Buffer) -> String? {
    guard actual.area == expected.area else {
      return "area \(actual.area) != \(expected.area)"
    }
    for position in expected.area.positions() {
      let lhs = actual[position]
      let rhs = expected[position]
      if !lhs.symbol.utf8.elementsEqual(rhs.symbol.utf8) || lhs.style != rhs.style
        || lhs.width != rhs.width || lhs.isContinuation != rhs.isContinuation
      {
        return "cell \(position): \(lhs) != \(rhs)"
      }
    }
    return nil
  }

  // MARK: Width

  @Test func stringWidthMatchesReference() {
    var generator = TextDrawingGenerator(seed: 1)
    var samples = Self.strings(seed: 2, randomCount: 600)
    for _ in 0..<200 {
      // Arbitrary ASCII including control characters and DEL.
      let count = Int(generator.next() % 20)
      samples.append(
        String((0..<count).map { _ in Character(Unicode.Scalar(UInt8(generator.next() % 0x80))) }))
    }
    for string in samples {
      let scalars = string.unicodeScalars.map { String($0.value, radix: 16) }
      for policy in [TerminalWidthPolicy.standard, .cjk] {
        let width = TerminalWidth.of(string, policy: policy)
        let expected = TextDrawingReference.stringWidth(string, policy: policy)
        #expect(width == expected, "\(scalars) \(policy)")
      }
    }
  }

  @Test func printableASCIIClassificationMatchesGraphemeWidths() {
    for string in Self.strings(seed: 3, randomCount: 600) {
      let isPrintable = TerminalWidth.isPrintableASCII(string)
      let expected = string.unicodeScalars.allSatisfy { (0x20...0x7E).contains($0.value) }
      #expect(isPrintable == expected)
      if isPrintable {
        // Each byte is its own one-column grapheme.
        #expect(string.count == string.utf8.count)
        #expect(string.allSatisfy { TerminalWidth.of($0) == 1 })
      }
    }
  }

  // MARK: Buffer

  @Test func setStringMatchesReference() {
    let area = Rect(x: 3, y: 2, width: 9, height: 3)
    let maxWidths: [Int?] = [nil, -1, 0, 1, 2, 3, 5, 100]
    var generator = TextDrawingGenerator(seed: 4)
    var failures = 0
    for string in Self.strings(seed: 5, randomCount: 300) {
      for start in Self.prefilledBuffers(area: area) {
        for _ in 0..<6 {
          let position = Position(
            x: area.x - 1 + Int(generator.next() % UInt64(area.width + 2)),
            y: area.y - 1 + Int(generator.next() % UInt64(area.height + 2))
          )
          let maxWidth = maxWidths[Int(generator.next() % UInt64(maxWidths.count))]
          let style = Self.styles[Int(generator.next() % UInt64(Self.styles.count))]
          var actual = start
          var expected = start
          let actualEnd = actual.setString(
            string, at: position, style: style, maxWidth: maxWidth)
          let expectedEnd = TextDrawingReference.setString(
            &expected, string, at: position, style: style, maxWidth: maxWidth)
          let difference = Self.mismatch(actual, expected)
          if actualEnd != expectedEnd || difference != nil {
            failures += 1
            Issue.record(
              """
              setString(\(string.debugDescription), at: \(position), maxWidth: \
              \(String(describing: maxWidth))): end \(actualEnd) vs \(expectedEnd); \
              \(difference ?? "same cells")
              """)
          }
          if failures > 5 { return }
        }
      }
    }
  }

  @Test func setGraphemeMatchesSetStringOfOneCharacter() {
    let area = Rect(x: 1, y: 1, width: 6, height: 2)
    var failures = 0
    let characters = Self.strings(seed: 6, randomCount: 200).flatMap { Array($0) }
    for character in characters {
      for start in Self.prefilledBuffers(area: area) {
        for x in (area.x - 1)...(area.x + area.width) {
          for maxWidth in [-1, 0, 1, 2, 3, 10] {
            let position = Position(x: x, y: area.y + 1)
            var actual = start
            var expected = start
            let actualEnd = actual.setGrapheme(
              character,
              width: TerminalWidth.of(character),
              at: position,
              style: Style(foreground: .cyan),
              maxWidth: maxWidth
            )
            let expectedEnd = TextDrawingReference.setString(
              &expected, String(character), at: position, style: Style(foreground: .cyan),
              maxWidth: maxWidth)
            let difference = Self.mismatch(actual, expected)
            if actualEnd != expectedEnd || difference != nil {
              failures += 1
              Issue.record(
                """
                setGrapheme(\(String(character).debugDescription), at: \(position), \
                maxWidth: \(maxWidth)): end \(actualEnd) vs \(expectedEnd); \
                \(difference ?? "same cells")
                """)
            }
            if failures > 5 { return }
          }
        }
      }
    }
  }

  @Test func asciiFastPathProducesExpectedCellsAroundWideGlyphs() {
    var buffer = Buffer(area: Rect(x: 0, y: 0, width: 6, height: 1))
    buffer.setString("\u{754C}\u{754C}\u{754C}", at: Position(x: 0, y: 0))

    // Starts on a continuation and stops on the head of a wide glyph at the clip edge.
    let end = buffer.setString("ab", at: Position(x: 1, y: 0), maxWidth: 2)

    #expect(end == Position(x: 3, y: 0))
    #expect(buffer.lines() == [" ab \u{754C}"])
    #expect(buffer[Position(x: 3, y: 0)] == .empty)
    #expect(buffer[Position(x: 4, y: 0)].width == 2)
    #expect(buffer[Position(x: 5, y: 0)].isContinuation)
  }

  // MARK: Line

  static func randomLine(_ generator: inout TextDrawingGenerator, strings: [String]) -> Line {
    let spanCount = Int(generator.next() % 4)
    let spans = (0..<spanCount).map { _ in
      Span(
        strings[Int(generator.next() % UInt64(strings.count))],
        style: styles[Int(generator.next() % UInt64(styles.count))]
      )
    }
    let alignments: [Alignment?] = [nil, .leading, .center, .trailing]
    return Line(
      spans,
      style: styles[Int(generator.next() % UInt64(styles.count))],
      alignment: alignments[Int(generator.next() % UInt64(alignments.count))]
    )
  }

  @Test func lineRenderingMatchesReference() {
    let bufferArea = Rect(x: 2, y: 1, width: 12, height: 2)
    let strings = Self.strings(seed: 7, randomCount: 200)
    var generator = TextDrawingGenerator(seed: 8)
    var failures = 0
    for _ in 0..<3_000 {
      let line = Self.randomLine(&generator, strings: strings)
      let parentAlignments: [Alignment?] = [nil, .leading, .center, .trailing]
      let parentAlignment = parentAlignments[Int(generator.next() % 4)]
      let parentStyle = Self.styles[Int(generator.next() % UInt64(Self.styles.count))]
      let x = bufferArea.x - 1 + Int(generator.next() % 5)
      let width = Int(generator.next() % 15)
      let area = Rect(x: x, y: bufferArea.y + 1, width: width, height: 1)
      let starts = Self.prefilledBuffers(area: bufferArea)
      let start = starts[Int(generator.next() % UInt64(starts.count))]
      var actual = start
      var expected = start
      line.render(
        in: area, into: &actual, parentStyle: parentStyle, parentAlignment: parentAlignment)
      TextDrawingReference.renderLine(
        line, in: area, into: &expected, parentStyle: parentStyle,
        parentAlignment: parentAlignment)
      if let difference = Self.mismatch(actual, expected) {
        failures += 1
        Issue.record("\(line) in \(area): \(difference)")
      }
      if failures > 5 { return }
    }
  }

  @Test func truncatedLinesWithEllipsisRenderLikeReference() {
    let strings = Self.strings(seed: 9, randomCount: 100)
    var generator = TextDrawingGenerator(seed: 10)
    var failures = 0
    for _ in 0..<1_000 {
      let columns = Int(generator.next() % 10)
      let ellipses: [Span?] = [Span("\u{2026}"), Span("..."), Span("\u{754C}"), nil]
      let ellipsis = ellipses[Int(generator.next() % UInt64(ellipses.count))]
      let line = Self.randomLine(&generator, strings: strings)
        .truncated(to: columns, ellipsis: ellipsis)
        .fitted(to: columns, alignment: .center, ellipsis: ellipsis)
      let area = Rect(x: 0, y: 0, width: 12, height: 1)
      var actual = Buffer(area: area)
      var expected = Buffer(area: area)
      Text([line]).render(in: area, into: &actual)
      TextDrawingReference.renderLine(
        line, in: area, into: &expected, parentStyle: .plain, parentAlignment: nil)
      if let difference = Self.mismatch(actual, expected) {
        failures += 1
        Issue.record("\(line): \(difference)")
      }
      if failures > 5 { return }
    }
  }

  // MARK: Paragraph

  @Test func paragraphRenderingMatchesReference() {
    let bufferArea = Rect(x: 1, y: 1, width: 11, height: 5)
    let strings = Self.strings(seed: 11, randomCount: 200)
    var generator = TextDrawingGenerator(seed: 12)
    var failures = 0
    for _ in 0..<4_000 {
      let lineCount = Int(generator.next() % 4)
      var paragraph = Paragraph(
        "",
        style: Self.styles[Int(generator.next() % UInt64(Self.styles.count))],
        wrap: [WrapMode.none, .character, .word][Int(generator.next() % 3)],
        scroll: Int(generator.next() % 3),
        horizontalScroll: [0, 0, 1, 3, 7][Int(generator.next() % 5)],
        trimLeadingWhitespace: generator.next().isMultiple(of: 2)
      )
      paragraph.lines = (0..<lineCount).map { _ in
        Self.randomLine(&generator, strings: strings)
      }
      let area = Rect(
        x: bufferArea.x + Int(generator.next() % 3),
        y: bufferArea.y + Int(generator.next() % 2),
        width: Int(generator.next() % 11),
        height: Int(generator.next() % 5)
      )
      let starts = Self.prefilledBuffers(area: bufferArea)
      let start = starts[Int(generator.next() % UInt64(starts.count))]
      var actual = start
      var expected = start
      paragraph.render(in: area, into: &actual)
      ReferenceParagraph(paragraph).render(in: area, into: &expected)
      if let difference = Self.mismatch(actual, expected) {
        failures += 1
        Issue.record("\(paragraph) in \(area): \(difference)")
      }
      for width in 0..<6 {
        #expect(
          paragraph.lineCount(width: width)
            == ReferenceParagraph(paragraph).lineCount(width: width))
      }
      if failures > 5 { return }
    }
  }

  // MARK: Table

  @Test func tablePlainLinesMatchReference() {
    let bufferArea = Rect(x: 1, y: 0, width: 10, height: 1)
    let strings = Self.strings(seed: 14, randomCount: 300)
    var failures = 0
    for string in strings {
      for alignment in [Alignment.leading, .center, .trailing] {
        for width in [0, 1, 2, 3, 5, 10] {
          for style in [Style.plain, Style(foreground: .red)] {
            let area = Rect(x: 1, y: 0, width: width, height: 1)
            for start in Self.prefilledBuffers(area: bufferArea) {
              var actual = start
              var expected = start
              Table<TableRow>.renderPlainLine(
                string, style: style, alignment: alignment, in: area, into: &actual)
              TextDrawingReference.renderPlainLine(
                string, style: style, alignment: alignment, in: area, into: &expected)
              if let difference = Self.mismatch(actual, expected) {
                failures += 1
                Issue.record("\(string.debugDescription) \(alignment) \(width): \(difference)")
              }
              if failures > 5 { return }
            }
          }
        }
      }
    }
  }
}

/// Deterministic generator so failures reproduce.
struct TextDrawingGenerator {
  private var state: UInt64

  init(seed: UInt64) { state = seed }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var value = state
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
    return value ^ (value >> 31)
  }
}

// MARK: - Reference implementation (the drawing code before the fast paths)

/// Verbatim copies of the pre-fast-path drawing code. Only `Buffer` internals are replaced by
/// the equivalent public subscript, and `TerminalWidth.of(String)` keeps its old two-pass ASCII
/// check. Do not optimize these.
enum TextDrawingReference {
  static func stringWidth(_ string: String, policy: TerminalWidthPolicy) -> Int {
    if string.utf8.allSatisfy({ $0 < 0x80 }) {
      return string.utf8.reduce(into: 0) { width, byte in
        if byte >= 0x20, byte != 0x7F { width += 1 }
      }
    }
    // The non-ASCII algorithm is unchanged.
    return TerminalWidth.of(string, policy: policy)
  }

  @discardableResult
  static func setString(
    _ buffer: inout Buffer,
    _ string: String,
    at position: Position,
    style: Style = .plain,
    maxWidth: Int? = nil
  ) -> Position {
    let area = buffer.area
    guard area.contains(position) else { return position }

    let areaEnd = area.x + area.width
    let requestedEnd = maxWidth.map { position.x + Int($0) } ?? areaEnd
    let endX = min(areaEnd, requestedEnd)
    var x = position.x

    for character in string {
      let width = TerminalWidth.of(character)
      if width == 0 {
        appendZeroWidth(&buffer, character, beforeX: x, y: position.y)
        continue
      }
      guard x + width <= endX else { break }
      for occupiedX in x..<(x + width) {
        clearGlyph(&buffer, at: Position(x: occupiedX, y: position.y))
      }
      let cellPosition = Position(x: x, y: position.y)
      buffer.setCell(
        Cell(
          symbol: String(character),
          style: style,
          width: UInt8(clamping: width),
          isContinuation: false
        ),
        at: cellPosition
      )
      if width > 1 {
        for continuation in 1..<width {
          buffer.setCell(
            Cell(symbol: "", style: style, width: 0, isContinuation: true),
            at: Position(x: (x + continuation), y: position.y)
          )
        }
      }
      x += width
    }
    return Position(x: x, y: position.y)
  }

  private static func clearGlyph(_ buffer: inout Buffer, at position: Position) {
    let area = buffer.area
    guard area.contains(position) else { return }
    var startX = position.x
    while startX > area.x {
      let cell = buffer[Position(x: startX, y: position.y)]
      guard cell.isContinuation else { break }
      startX -= 1
    }

    let start = Position(x: startX, y: position.y)
    let width = max(1, Int(buffer[start].width))
    let endX = min(area.x + area.width, startX + width)
    for x in startX..<endX {
      buffer[Position(x: x, y: position.y)] = .empty
    }
  }

  private static func appendZeroWidth(
    _ buffer: inout Buffer,
    _ character: Character,
    beforeX x: Int,
    y: Int
  ) {
    let area = buffer.area
    guard x > area.x else { return }
    var targetX = x - 1
    while targetX > area.x {
      let position = Position(x: targetX, y: y)
      guard buffer[position].isContinuation else { break }
      targetX -= 1
    }
    let position = Position(x: targetX, y: y)
    guard area.contains(position), !buffer[position].isContinuation else { return }
    buffer[position].symbol.append(contentsOf: String(character))
  }

  static func measureLine(_ line: Line) -> Int {
    line.spans.reduce(0) { $0 + stringWidth($1.content, policy: .standard) }
  }

  static func renderLine(
    _ line: Line,
    in area: Rect,
    into buffer: inout Buffer,
    parentStyle: Style,
    parentAlignment: Alignment?
  ) {
    let style = line.style
    let alignment = line.alignment
    let spans = line.spans
    let area = area.intersection(buffer.area)
    guard !area.isEmpty else { return }
    let row = Rect(x: area.x, y: area.y, width: area.width, height: 1)
    let lineWidth = measureLine(line)
    guard lineWidth > 0 else { return }
    if style != .plain { buffer.setStyle(style, in: row) }
    let areaWidth = row.width
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
      x: (row.x + indent),
      y: row.y
    )
    let end = row.x + row.width
    for span in spans {
      for character in span.content {
        let characterWidth = TerminalWidth.of(character)
        if skipped < leadingSkip {
          let endOfCharacter = skipped + characterWidth
          if endOfCharacter > leadingSkip {
            position.x = (position.x + endOfCharacter - leadingSkip)
          }
          skipped = endOfCharacter
          continue
        }
        guard characterWidth > 0 else { continue }
        guard position.x + characterWidth <= end else { return }
        let inherited =
          buffer.cell(at: position)?.style
          ?? parentStyle.patching(style)
        position = setString(
          &buffer,
          String(character),
          at: position,
          style: inherited.patching(span.style),
          maxWidth: (end - position.x)
        )
      }
    }
  }

  static func renderPlainLine(
    _ content: String,
    style: Style,
    alignment: Alignment,
    in area: Rect,
    into buffer: inout Buffer
  ) {
    let area = area.intersection(buffer.area)
    guard !area.isEmpty else { return }
    if style != .plain { buffer.setStyle(style, in: area) }

    let contentWidth = stringWidth(content, policy: .standard)
    guard contentWidth > 0 else { return }
    let areaWidth = area.width
    let leadingSkip: Int
    let indent: Int
    if contentWidth <= areaWidth {
      leadingSkip = 0
      indent =
        switch alignment {
        case .leading: 0
        case .center: (areaWidth - contentWidth) / 2
        case .trailing: areaWidth - contentWidth
        }
    } else {
      indent = 0
      leadingSkip =
        switch alignment {
        case .leading: 0
        case .center: (contentWidth - areaWidth) / 2
        case .trailing: contentWidth - areaWidth
        }
    }

    var skipped = 0
    var position = Position(x: (area.x + indent), y: area.y)
    let end = area.x + area.width
    if leadingSkip == 0 {
      setString(
        &buffer,
        content,
        at: position,
        style: style,
        maxWidth: (end - position.x)
      )
      return
    }
    for character in content {
      let characterWidth = TerminalWidth.of(character)
      if skipped < leadingSkip {
        let endOfCharacter = skipped + characterWidth
        if endOfCharacter > leadingSkip {
          position.x = (position.x + endOfCharacter - leadingSkip)
        }
        skipped = endOfCharacter
        continue
      }
      guard characterWidth > 0 else { continue }
      guard position.x + characterWidth <= end else { return }
      position = setString(
        &buffer,
        String(character),
        at: position,
        style: style,
        maxWidth: (end - position.x)
      )
    }
  }
}

/// The pre-fast-path `Paragraph` rendering and wrapping, verbatim apart from reading the
/// paragraph's public properties and drawing through `TextDrawingReference.setString`.
struct ReferenceParagraph {
  var lines: [Line]
  var style: Style
  var wrap: WrapMode
  var scroll: Int
  var horizontalScroll: Int
  var trimLeadingWhitespace: Bool

  init(_ paragraph: Paragraph) {
    lines = paragraph.lines
    style = paragraph.style
    wrap = paragraph.wrap
    scroll = paragraph.scroll
    horizontalScroll = paragraph.horizontalScroll
    trimLeadingWhitespace = paragraph.trimLeadingWhitespace
  }

  func render(in area: Rect, into buffer: inout Buffer) {
    guard !area.isEmpty else { return }
    if style != .plain {
      buffer.setStyle(style, in: area)
    }
    let width = area.width
    let height = area.height
    if wrap == .none {
      for (row, sourceLine) in lines.dropFirst(Int(scroll)).prefix(height).enumerated() {
        guard let visualLine = visualLines(for: sourceLine, width: width).first else { continue }
        render(visualLine, at: row, width: width, in: area, into: &buffer)
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
          into: &buffer
        )
        renderedLineCount += 1
        guard renderedLineCount < height else { return }
      }
      remainingScroll = 0
    }
  }

  func lineCount(width: Int) -> Int {
    guard width > 0 else { return 0 }
    return lines.reduce(0) { $0 + visualLines(for: $1, width: Int(width)).count }
  }

  struct Glyph {
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
      x: (area.x + offset),
      y: (area.y + row)
    )
    for glyph in line {
      guard TerminalWidth.of(glyph.character) > 0 else { continue }
      position = TextDrawingReference.setString(
        &buffer,
        String(glyph.character),
        at: position,
        style: glyph.style,
        maxWidth: (area.x + width - position.x)
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
      return Array(Self.prefixFitting(glyphs, width: width))
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
    return Array(Self.prefixFitting(Array(glyphs[start...]), width: width))
  }

  private static func prefixFitting(_ glyphs: [Glyph], width: Int) -> ArraySlice<Glyph> {
    var used = 0
    let end =
      glyphs.firstIndex { glyph in
        used += TerminalWidth.of(glyph.character)
        return used > width
      } ?? glyphs.endIndex
    return glyphs[..<end]
  }
}
