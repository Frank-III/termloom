import TermLoomTestSupport
import Testing

@testable import TermLoom

@Suite struct TextTests {
  @Test func richTextMatchesUpstreamAlignmentAndTruncation() {
    let text = Text([
      Line("123456789", alignment: .trailing),
      Line("123456789", alignment: .center),
      Line("123456789", alignment: .leading),
    ])

    assertWidget(text, size: Size(width: 5, height: 3)) {
      """
      │56789│
      │34567│
      │12345│
      """
    }
  }

  @Test func textLineAndSpanStylesComposeInOrder() {
    let text = Text(
      [
        Line(style: Style(foreground: .green, modifiers: [.italic])) {
          Span("A").foregroundStyle(.red).bold()
          Span("B")
        },
        Line(""),
      ],
      style: Style(background: .blue, modifiers: [.dim])
    )
    var buffer = Buffer(area: Rect(x: 0, y: 0, width: 4, height: 2))
    text.render(in: buffer.area, into: &buffer)

    assertWidget(text, size: buffer.area.size) {
      """
      │AB  │
      │    │
      """
    }
    #expect(buffer[Position(x: 0, y: 0)].style.foreground == .red)
    #expect(buffer[Position(x: 0, y: 0)].style.background == .blue)
    #expect(buffer[Position(x: 0, y: 0)].style.modifiers == [.bold, .dim, .italic])
    #expect(buffer[Position(x: 1, y: 0)].style.foreground == .green)
    #expect(buffer[Position(x: 1, y: 0)].style.modifiers == [.dim, .italic])
    #expect(buffer[Position(x: 3, y: 0)].style.foreground == .green)
    #expect(buffer[Position(x: 0, y: 1)].style.foreground == nil)
    #expect(buffer[Position(x: 0, y: 1)].style.background == .blue)
    #expect(buffer[Position(x: 0, y: 1)].style.modifiers == [.dim])
  }

  @Test func richTextMutationMeasurementAndResetFollowUpstreamSemantics() {
    var text = Text("")
    #expect(text.width == 0)
    #expect(text.height == 1)

    text = Text([])
    text.appendSpan(Span("Hello").foregroundStyle(.cyan))
    text.appendSpan(Span(", "))
    text.appendLine(Line("world").rightAligned())
    #expect(text.lines.map(\.content) == ["Hello, ", "world"])
    #expect(text.width == 7)
    #expect(text.height == 2)

    #expect(Text("first\nsecond").height == 2)
    #expect(Text("trailing newline\n").height == 1)

    let fullyStyled =
      Span("reset")
      .foregroundStyle(.red)
      .backgroundStyle(.blue)
      .underlineStyle(.cyan)
      .bold()
      .dim()
      .italic()
      .underlined()
      .reversed()
      .hidden()
      .crossedOut()
      .resetStyle()
    #expect(fullyStyled.style.foreground == .reset)
    #expect(fullyStyled.style.background == .reset)
    #expect(fullyStyled.style.underlineColor == .reset)
    #expect(fullyStyled.style.modifiers.isEmpty)
    #expect(fullyStyled.style.removedModifiers == .all)
  }

  @Test func textPreservesMeaningfulEmptyRowsAndTerminalNewlineSemantics() {
    #expect(Text("a\n\nb").lines.map(\.content) == ["a", "", "b"])
    #expect(Text("\na").lines.map(\.content) == ["", "a"])
    #expect(Text("a\n").lines.map(\.content) == ["a"])
    #expect(Text("\n").lines.map(\.content) == [""])

    for value in ["a\n\nb", "\na", "a\n", "\n", ""] {
      var text = Text("placeholder")
      text.content = value
      #expect(text.lines == Text(value).lines)

      let representedContent = text.content
      let representedLines = text.lines
      text.content = representedContent
      #expect(text.lines == representedLines)
    }

    var trailingEmptyRows = Text([Line("a"), Line(""), Line("")])
    let representedContent = trailingEmptyRows.content
    #expect(representedContent == "a\n\n\n")
    trailingEmptyRows.content = representedContent
    #expect(trailingEmptyRows.lines.map(\.content) == ["a", "", ""])
  }

  @Test func lineDirectlyConstructsDynamicSpansWithoutChangingStyles() {
    let spans = [
      Span("red", style: Style(foreground: .red, modifiers: [.bold])),
      Span(" plain"),
    ]
    let line = Line(spans, style: Style(background: .blue), alignment: .trailing)

    #expect(line.spans == spans)
    #expect(line.style == Style(background: .blue))
    #expect(line.alignment == .trailing)
    let buffer = assertWidget(line, size: Size(width: 10, height: 1)) {
      """
      │ red plain│
      """
    }
    #expect(buffer[Position(x: 1, y: 0)].style.foreground == .red)
    #expect(buffer[Position(x: 1, y: 0)].style.background == .blue)
    #expect(buffer[Position(x: 1, y: 0)].style.modifiers == [.bold])
    #expect(buffer[Position(x: 5, y: 0)].style.foreground == nil)
    #expect(buffer[Position(x: 5, y: 0)].style.background == .blue)

    let empty = Line([])
    #expect(empty.spans.isEmpty)
    assertWidget(empty, size: Size(width: 3, height: 1)) {
      """
      │   │
      """
    }
  }

  @Test func lineTruncationPreservesPartialWideGlyphCellsLikeUpstream() {
    let ordinaryCases: [(Alignment, Int, String)] = [
      (.leading, 4, "1234"),
      (.leading, 5, "1234 "),
      (.leading, 6, "1234🦀"),
      (.leading, 7, "1234🦀7"),
      (.trailing, 4, "7890"),
      (.trailing, 5, " 7890"),
      (.trailing, 6, "🦀7890"),
      (.trailing, 7, "4🦀7890"),
    ]
    for (alignment, width, expected) in ordinaryCases {
      var buffer = Buffer(area: Rect(x: 0, y: 0, width: width, height: 1))
      Line("1234🦀7890", alignment: alignment).render(in: buffer.area, into: &buffer)
      #expect(buffer.lines() == [expected])
    }

    let multiSpanCases: [(Int, String)] = [
      (4, "c🦀d"),
      (5, "bc🦀d"),
      (6, "Xbc🦀d"),
      (7, "🦀bc🦀d"),
      (8, "a🦀bc🦀d"),
    ]
    for (width, expected) in multiSpanCases {
      var buffer = Buffer(
        area: Rect(x: 0, y: 0, width: width, height: 1),
        repeating: Cell(symbol: "X")
      )
      Line(alignment: .trailing) {
        Span("a🦀b")
        Span("c🦀d")
      }.render(in: buffer.area, into: &buffer)
      #expect(buffer.lines() == [expected])
    }

    let flagCases: [(Int, String)] = [
      (1, " "),
      (2, "🇺🇸"),
      (3, "🇺🇸1"),
      (4, "🇺🇸12"),
      (5, "🇺🇸123"),
      (6, "🇺🇸1234"),
      (7, "🇺🇸1234 "),
    ]
    for (width, expected) in flagCases {
      var buffer = Buffer(area: Rect(x: 0, y: 0, width: width, height: 1))
      Line("🇺🇸1234").render(in: buffer.area, into: &buffer)
      #expect(buffer.lines() == [expected])
    }
  }

  @Test func paragraphAcceptsRichTextWithoutLosingInheritedAlignmentOrStyle() {
    let text = Text(
      [
        Line { Span("red").foregroundStyle(.red) },
        Line("left", alignment: .leading),
      ],
      style: Style(background: .blue),
      alignment: .trailing
    )
    let paragraph = Paragraph(text)
    var buffer = Buffer(area: Rect(x: 0, y: 0, width: 6, height: 2))
    paragraph.render(in: buffer.area, into: &buffer)

    assertWidget(paragraph, size: buffer.area.size) {
      """
      │   red│
      │left  │
      """
    }
    #expect(buffer.lines() == ["   red", "left  "])
    #expect(buffer[Position(x: 3, y: 0)].style.foreground == .red)
    #expect(buffer[Position(x: 0, y: 1)].style.background == .blue)
  }

  @Test func plainTableFastPathKeepsRichTextTruncationSemantics() {
    let table = Table(["1234🦀7890"]) {
      TableColumn("", width: .length(5), alignment: .trailing) { $0 }
    }

    assertWidget(table, size: Size(width: 5, height: 2)) {
      """
      │     │
      │ 7890│
      """
    }
  }

  @Test func maskedTextCountsGraphemesAndNeverLeaksThroughDiagnostics() {
    let masked = Masked("a👨‍👩‍👧‍👦e\u{301}", mask: "x")
    #expect(masked.maskedValue == "xxx")
    #expect(masked.description == "xxx")
    #expect(masked.debugDescription == "xxx")
    #expect(String(describing: masked) == "xxx")
    #expect(String(reflecting: masked) == "xxx")

    assertWidget(masked, size: Size(width: 5, height: 1)) {
      """
      │xxx  │
      """
    }
    assertWidget(
      Paragraph(wrap: .none) {
        Line {
          Span("password: ").bold()
          Span(masked, style: Style(foreground: .cyan))
        }
      },
      size: Size(width: 14, height: 1)
    ) {
      """
      │password: xxx │
      """
    }
  }
}
