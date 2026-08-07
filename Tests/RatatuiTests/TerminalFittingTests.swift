import Testing

@testable import Ratatui

@Suite struct TerminalFittingTests {
  @Test func plainFittingPreservesGraphemesAndTerminalColumns() {
    #expect(TerminalWidth.prefix("A界B", fitting: 2) == "A")
    #expect(TerminalWidth.prefix("A界B", fitting: 3) == "A界")
    #expect(TerminalWidth.suffix("A界B", fitting: 3) == "界B")
    #expect(TerminalWidth.prefix("e\u{301}x", fitting: 1) == "e\u{301}")
    #expect(TerminalWidth.prefix("👨‍👩‍👧‍👦x", fitting: 2) == "👨‍👩‍👧‍👦")
    #expect(TerminalWidth.prefix("·x", fitting: 1, policy: .cjk).isEmpty)
  }

  @Test func truncationAndPaddingProduceExactWidths() {
    #expect(TerminalWidth.truncated("abcdef", to: 4) == "abc…")
    #expect(TerminalWidth.truncated("界界", to: 3) == "界…")
    #expect(TerminalWidth.truncated("界", to: 1) == "…")
    #expect(TerminalWidth.truncated("abcdef", to: 4, ellipsis: nil) == "abcd")
    #expect(TerminalWidth.truncated("abcdef", to: 0).isEmpty)

    #expect(TerminalWidth.padded("界", to: 4) == "界  ")
    #expect(TerminalWidth.padded("界", to: 4, alignment: .trailing) == "  界")
    #expect(TerminalWidth.padded("A", to: 4, alignment: .center) == " A  ")
    #expect(TerminalWidth.fitted("abcdef", to: 4) == "abc…")
    #expect(TerminalWidth.of(TerminalWidth.fitted("界abcdef", to: 6)) == 6)
  }

  @Test func richFittingPreservesStylesAndLineMetadata() {
    let red = Style(foreground: .red)
    let blue = Style(foreground: .blue)
    let yellow = Style(foreground: .yellow)
    let base = Style(background: .black)
    let line = Line(
      [Span("AB", style: red), Span("界C", style: blue)],
      style: base,
      alignment: .trailing
    )

    let fitted = line.fitted(
      to: 4,
      ellipsis: Span("…", style: yellow),
      paddingStyle: blue
    )
    #expect(fitted.style == base)
    #expect(fitted.alignment == .trailing)
    #expect(
      fitted.spans == [Span("AB", style: red), Span("…", style: yellow), Span(" ", style: blue)])
    #expect(fitted.width == 4)

    let span = Span("界abcdef", style: red).fitted(to: 5)
    #expect(span.style == red)
    #expect(span.width == 5)

    let splitWidePrefix = Line([Span("界", style: blue), Span("CDE", style: red)])
      .truncated(to: 2, ellipsis: Span("…", style: yellow))
    #expect(splitWidePrefix.spans == [Span("…", style: yellow)])
  }
}
