import RatatuiTestSupport
import Testing

@testable import Ratatui

@Suite struct WidgetTests {
  @Test func paragraphDefaultsToUpstreamTruncation() {
    let paragraph = Paragraph("Hello World")
    #expect(paragraph.wrap == .none)
    #expect(paragraph.lineCount(width: 5) == 1)
    assertWidget(paragraph, size: Size(width: 5, height: 2)) {
      """
      │Hello│
      │     │
      """
    }
  }

  @Test func paragraphWrapsStyledContent() {
    let buffer = assertWidget(
      Paragraph(wrap: .word) {
        Line {
          Span("Swift ").bold()
          Span("terminal UI")
        }
      },
      size: Size(width: 8, height: 3)
    ) {
      """
      │Swift   │
      │terminal│
      │UI      │
      """
    }
    #expect(buffer.cell(at: Position(x: 0, y: 0))?.style.modifiers.contains(.bold) == true)
  }

  @Test func paragraphScrollsAcrossWrappedSourceLineBoundaries() {
    assertWidget(
      Paragraph(wrap: .character, scroll: 2) {
        Line("abcdefghij")
        Line("界界界")
        Line("tail")
      },
      size: Size(width: 4, height: 3)
    ) {
      """
      │ij  │
      │界界│
      │界  │
      """
    }

    assertWidget(
      Paragraph("zero\none\ntwo", scroll: 1),
      size: Size(width: 4, height: 2)
    ) {
      """
      │one │
      │two │
      """
    }
  }

  @Test func paragraphMatchesUpstreamWordBoundaryFixtures() {
    let content =
      "This is a long line of text that should wrap      and contains a superultramegagigalong word."
    assertWidget(
      Paragraph(content, wrap: .word),
      size: Size(width: 12, height: 9)
    ) {
      """
      │This is a   │
      │long line of│
      │text that   │
      │should wrap │
      │and contains│
      │a           │
      │superultrame│
      │gagigalong  │
      │word.       │
      """
    }
  }

  @Test func paragraphPreservesIndentationAndNonbreakingSpaces() {
    assertWidget(
      Paragraph(
        "               4 Indent\n                 must wrap!",
        wrap: .word,
        trimLeadingWhitespace: false
      ),
      size: Size(width: 10, height: 6)
    ) {
      """
      │          │
      │    4     │
      │Indent    │
      │          │
      │      must│
      │wrap!     │
      """
    }

    assertWidget(
      Paragraph("AAAAAAAAAAAAAAA AAAA\u{00A0}AAA", wrap: .word),
      size: Size(width: 20, height: 2)
    ) {
      """
      │AAAAAAAAAAAAAAA     │
      │AAAA AAA            │
      """
    }
  }

  @Test func paragraphMeasuresReflowAndHandlesZeroOrOverwideGlyphs() {
    let paragraph = Paragraph(wrap: .word) {
      Line {
        Span("foo\u{200B}").bold()
        Span("bar")
      }
      Line("wide: 界")
    }
    #expect(paragraph.lineCount(width: 3) == 5)
    #expect(paragraph.lineWidth == 8)

    assertWidget(
      Paragraph("foo\u{200B}bar", wrap: .word),
      size: Size(width: 3, height: 2)
    ) {
      """
      │foo│
      │bar│
      """
    }

    assertWidget(
      Paragraph("界a", wrap: .character),
      size: Size(width: 1, height: 1)
    ) {
      """
      │a│
      """
    }
  }

  @Test func paragraphBaseStyleCoversASCIIAndWideCellAreas() {
    let buffer = assertWidget(
      Paragraph(style: Style(background: .green)) {
        Line("abc")
        Line("あいう")
        Line("ｶﾞｷﾞｸﾞ")
      },
      size: Size(width: 10, height: 3)
    ) {
      """
      │abc       │
      │あいう    │
      │ｶﾞｷﾞｸﾞ    │
      """
    }

    for y: UInt16 in 0..<3 {
      for x: UInt16 in 0..<10 {
        #expect(buffer.cell(at: Position(x: x, y: y))?.style.background == .green)
      }
    }
    #expect(buffer.cell(at: Position(x: 0, y: 1))?.symbol == "あ")
    #expect(buffer.cell(at: Position(x: 2, y: 1))?.symbol == "い")
    #expect(buffer.cell(at: Position(x: 4, y: 1))?.symbol == "う")
    #expect(buffer.cell(at: Position(x: 0, y: 2))?.symbol == "ｶﾞ")
    #expect(buffer.cell(at: Position(x: 2, y: 2))?.symbol == "ｷﾞ")
    #expect(buffer.cell(at: Position(x: 4, y: 2))?.symbol == "ｸﾞ")
  }

  @Test func paragraphTruncationStopsAtTheFirstOverwideGlyph() {
    assertWidget(Paragraph("界a"), size: Size(width: 1, height: 1)) {
      """
      │ │
      """
    }
    assertWidget(Paragraph("界a", wrap: .character), size: Size(width: 1, height: 1)) {
      """
      │a│
      """
    }
  }

  @Test func paragraphMatchesUpstreamDoubleWidthReflow() {
    let content =
      "コンピュータ上で文字を扱う場合、典型的には文字による通信を行う場合にその両端点では、"
    let paragraph = Paragraph(content, wrap: .word)
    #expect(paragraph.lineCount(width: 20) == 5)
    assertWidget(paragraph, size: Size(width: 20, height: 5)) {
      """
      │コンピュータ上で文字│
      │を扱う場合、典型的に│
      │は文字による通信を行│
      │う場合にその両端点で│
      │は、                │
      """
    }
  }

  @Test func tabsSupportRichTitlesAndAlignment() {
    let buffer = assertWidget(
      Tabs(
        [
          Line { Span("One").foregroundStyle(.cyan) },
          Line { Span("Two").bold() },
        ],
        selectedIndex: 1,
        divider: "|",
        alignment: .trailing
      ),
      size: Size(width: 20, height: 1)
    ) {
      """
      │          One | Two │
      """
    }
    #expect(buffer.cell(at: Position(x: 10, y: 0))?.style.foreground == .cyan)
    #expect(buffer.cell(at: Position(x: 16, y: 0))?.style.modifiers.contains(.reversed) == true)
  }

  @Test func metricWidgetsRenderDeterministically() {
    assertWidget(
      VStack {
        Gauge(ratio: 0.5, label: "50%").frame(.length(1))
        Sparkline([0, 1, 2, 3, 4, 5], bounds: 0...5).frame(.length(1))
      },
      size: Size(width: 12, height: 3)
    ) {
      """
      │████50%░░░░░│
      │ ▁▃▄▆█      │
      │            │
      """
    }
  }

  @Test func sparklineBarsPatchIndividualAndAbsentStyles() {
    let buffer = assertWidget(
      Sparkline(
        [
          SparklineBar(0, style: Style(foreground: .red)),
          SparklineBar(1),
          SparklineBar(nil),
          SparklineBar(3, style: Style(foreground: .blue)),
        ],
        bounds: 0...3,
        style: Style(background: .white, modifiers: .bold),
        absentValueStyle: Style(foreground: .green),
        absentValueSymbol: "·"
      ),
      size: Size(width: 4, height: 2)
    ) {
      """
      │  ·█│
      │ ▅·█│
      """
    }

    #expect(buffer.cell(at: Position(x: 0, y: 1))?.style.foreground == .red)
    #expect(buffer.cell(at: Position(x: 1, y: 1))?.style.foreground == nil)
    #expect(buffer.cell(at: Position(x: 2, y: 0))?.style.foreground == .green)
    #expect(buffer.cell(at: Position(x: 3, y: 0))?.style.foreground == .blue)
    #expect(buffer.cell(at: Position(x: 3, y: 0))?.style.background == .white)
    #expect(buffer.cell(at: Position(x: 3, y: 0))?.style.modifiers.contains(.bold) == true)
  }

  @Test func sparklineAcceptsCanonicalAndCustomSymbolSets() {
    assertWidget(
      VStack {
        Sparkline([0, 1, 2, 3, 4, 5, 6, 7, 8], bounds: 0...8).frame(.length(1))
        Sparkline(
          [0, 1, 2, 3, 4, 5, 6, 7, 8],
          bounds: 0...8,
          symbolSet: .threeLevels
        ).frame(.length(1))
      },
      size: Size(width: 9, height: 2)
    ) {
      """
      │ ▁▂▃▄▅▆▇█│
      │  ▄▄▄▄▄██│
      """
    }
  }

  @Test func groupedBarChartsUseFractionalResolutionAndDirections() {
    var vertical = Buffer(area: Rect(x: 0, y: 0, width: 7, height: 5))
    BarChart(
      groups: [
        BarGroup("G", bars: [Bar("A", value: 0.5)]),
        BarGroup("H", bars: [Bar("B", value: 1)]),
      ],
      maximum: 1,
      barWidth: 1,
      spacing: 1,
      groupSpacing: 1
    ).render(in: vertical.area, into: &vertical)
    assertTerminal(vertical) {
      """
      │  █    │
      │▄ █    │
      │█ █    │
      │A B    │
      │G H    │
      """
    }

    var horizontal = Buffer(area: Rect(x: 0, y: 0, width: 10, height: 1))
    BarChart(
      [Bar("A", value: 0.5)],
      maximum: 1,
      direction: .horizontal
    ).render(in: horizontal.area, into: &horizontal)
    assertTerminal(horizontal) {
      """
      │A ████    │
      """
    }
  }

  @Test func scrollbarSupportsStateOrientationAndEndpointSymbols() {
    var state = ScrollbarState(contentLength: 10, viewportLength: 2, position: 4)
    assertWidget(
      Scrollbar(
        contentLength: 0,
        viewportLength: 0,
        position: 0,
        orientation: .verticalRight,
        beginSymbol: "↑",
        endSymbol: "↓"
      ),
      size: Size(width: 3, height: 6),
      state: &state
    ) {
      """
      │  ↑│
      │  ││
      │  █│
      │  ││
      │  ││
      │  ↓│
      """
    }
    state.scrollToEnd()
    #expect(state.position == 8)
    state.scroll(by: -3)
    #expect(state.position == 5)
  }

  @Test func chartUsesBrailleResolution() {
    var buffer = Buffer(area: Rect(x: 0, y: 0, width: 4, height: 2))
    Chart(
      [
        Dataset(points: [(0, 0), (1, 1)], marker: .braille, graphType: .line)
      ], x: 0...1, y: 0...1
    ).render(in: buffer.area, into: &buffer)

    #expect(buffer.lines().joined().contains { $0.unicodeScalars.first?.value ?? 0 >= 0x2800 })
  }

  @Test func blockSupportsSelectiveBordersAndPositionedTitles() {
    var buffer = Buffer(area: Rect(x: 0, y: 0, width: 16, height: 4))
    let block = Block(
      titles: [
        BlockTitle(Line("L"), position: .top),
        BlockTitle(Line("C", alignment: .center), position: .top),
        BlockTitle(Line("R", alignment: .trailing), position: .bottom),
      ],
      borders: .double,
      borderEdges: [.top, .bottom]
    ) {
      Text("body")
    }

    block.render(in: buffer.area, into: &buffer)

    assertTerminal(buffer) {
      """
      │L══════C════════│
      │body            │
      │                │
      │═══════════════R│
      """
    }
    #expect(block.inner(buffer.area) == Rect(x: 0, y: 1, width: 16, height: 2))
  }

  @Test func blockPaddingMatchesUpstreamFactoriesAndSaturates() {
    #expect(Padding.zero == Padding())
    #expect(Padding.horizontal(1) == Padding(left: 1, right: 1, top: 0, bottom: 0))
    #expect(Padding.vertical(1) == Padding(left: 0, right: 0, top: 1, bottom: 1))
    #expect(Padding.uniform(1) == Padding(left: 1, right: 1, top: 1, bottom: 1))
    #expect(Padding.proportional(2) == Padding(left: 4, right: 4, top: 2, bottom: 2))
    #expect(Padding.symmetric(2, 3) == Padding(left: 2, right: 2, top: 3, bottom: 3))
    #expect(Padding.left(2) == Padding(left: 2, right: 0, top: 0, bottom: 0))
    #expect(Padding.right(2) == Padding(left: 0, right: 2, top: 0, bottom: 0))
    #expect(Padding.top(2) == Padding(left: 0, right: 0, top: 2, bottom: 0))
    #expect(Padding.bottom(2) == Padding(left: 0, right: 0, top: 0, bottom: 2))
    #expect(Padding.proportional(.max).leading == .max)

    let block = Block(
      title: "Padded",
      borders: .plain,
      padding: Padding(left: 2, right: 3, top: 1, bottom: 2)
    ) {
      Text("content")
    }
    #expect(block.horizontalSpace == (3, 4))
    #expect(block.verticalSpace == (2, 3))
    #expect(
      block.inner(Rect(x: 0, y: 0, width: 12, height: 7))
        == Rect(x: 3, y: 2, width: 5, height: 2)
    )
    assertWidget(block, size: Size(width: 12, height: 7)) {
      """
      │┌─ Padded ─┐│
      ││          ││
      ││  conte   ││
      ││          ││
      ││          ││
      ││          ││
      │└──────────┘│
      """
    }

    let saturated = Block(padding: .uniform(.max)) { Text("hidden") }
    #expect(
      saturated.inner(Rect(x: 4, y: 5, width: 1, height: 1))
        == Rect(x: .max, y: .max, width: 0, height: 0)
    )
  }

  @Test func blockRendersEveryCanonicalBorderFamily() {
    assertWidget(
      VStack {
        HStack {
          Block(borders: .lightDoubleDashed) { Text("") }.frame(.flex(1))
          Block(borders: .heavyDoubleDashed) { Text("") }.frame(.flex(1))
          Block(borders: .lightTripleDashed) { Text("") }.frame(.flex(1))
          Block(borders: .heavyTripleDashed) { Text("") }.frame(.flex(1))
          Block(borders: .lightQuadrupleDashed) { Text("") }.frame(.flex(1))
          Block(borders: .heavyQuadrupleDashed) { Text("") }.frame(.flex(1))
        }.frame(.length(3))
        HStack {
          Block(borders: .quadrantInside) { Text("") }.frame(.flex(1))
          Block(borders: .quadrantOutside) { Text("") }.frame(.flex(1))
          Block(borders: .oneEighthWide) { Text("") }.frame(.flex(1))
          Block(borders: .oneEighthTall) { Text("") }.frame(.flex(1))
          Block(borders: .proportionalWide) { Text("") }.frame(.flex(1))
          Block(borders: .full) { Text("") }.frame(.flex(1))
        }.frame(.length(3))
      },
      size: Size(width: 36, height: 6)
    ) {
      """
      │┌╌╌╌╌┐┏╍╍╍╍┓┌┄┄┄┄┐┏┅┅┅┅┓┌┈┈┈┈┐┏┉┉┉┉┓│
      │╎    ╎╏    ╏┆    ┆┇    ┇┊    ┊┋    ┋│
      │└╌╌╌╌┘┗╍╍╍╍┛└┄┄┄┄┘┗┅┅┅┅┛└┈┈┈┈┘┗┉┉┉┉┛│
      │▗▄▄▄▄▖▛▀▀▀▀▜▁▁▁▁▁▁▕▔▔▔▔▏▄▄▄▄▄▄██████│
      │▐    ▌▌    ▐▏    ▕▕    ▏█    ██    █│
      │▝▀▀▀▀▘▙▄▄▄▄▟▔▔▔▔▔▔▕▁▁▁▁▏▀▀▀▀▀▀██████│
      """
    }
  }

  @Test func clearAndFillClipAndResetCompleteCells() {
    var buffer = Buffer(
      area: Rect(x: 2, y: 2, width: 6, height: 3),
      repeating: Cell(symbol: "x", style: Style(foreground: .red, modifiers: .bold))
    )

    Clear().render(in: Rect(x: 0, y: 3, width: 5, height: 20), into: &buffer)
    Fill("•", style: Style(foreground: .blue))
      .symbol("#")
      .bold()
      .render(in: Rect(x: 6, y: 1, width: 20, height: 3), into: &buffer)

    assertTerminal(buffer) {
      """
      │xxxx##│
      │   x##│
      │   xxx│
      """
    }
    #expect(buffer.cell(at: Position(x: 2, y: 3)) == .empty)
    #expect(buffer.cell(at: Position(x: 6, y: 2))?.symbol == "#")
    #expect(buffer.cell(at: Position(x: 6, y: 2))?.style.foreground == .blue)
    #expect(buffer.cell(at: Position(x: 6, y: 2))?.style.modifiers.contains(.bold) == true)

    let unchanged = buffer
    Clear().render(in: Rect(x: 100, y: 100, width: 1, height: 1), into: &buffer)
    Fill("界").render(in: buffer.area, into: &buffer)
    #expect(buffer == unchanged)
  }

  @Test func adjacentBlocksCanCollapseTheirBorders() {
    var buffer = Buffer(area: Rect(x: 0, y: 0, width: 9, height: 3))
    Block(borders: .plain, borderMerge: .exact) { Text("") }
      .render(in: Rect(x: 0, y: 0, width: 5, height: 3), into: &buffer)
    Block(borders: .plain, borderMerge: .exact) { Text("") }
      .render(in: Rect(x: 4, y: 0, width: 5, height: 3), into: &buffer)

    assertTerminal(buffer) {
      """
      │┌───┬───┐│
      ││   │   ││
      │└───┴───┘│
      """
    }
  }

  @Test func statefulListKeepsSelectionVisible() {
    var state = ListState(selected: 4)
    assertWidget(
      List(["zero", "one", "two", "three", "four", "five"], marker: "> ") { $0 },
      size: Size(width: 8, height: 3),
      state: &state
    ) {
      """
      │  two   │
      │  three │
      │> four  │
      """
    }
    #expect(state.offset == 2)
  }

  @Test func listSupportsMultilineRowsRepeatedMarkersAndDirection() throws {
    var state = ListState(selected: 0)
    var terminal = try Terminal(backend: TestBackend(width: 10, height: 5))
    let selected = try terminal.draw { frame in
      frame.render(
        List(
          ["Item 0\nLine 2", "Item 1", "Item 2"],
          marker: ">>",
          repeatMarker: true
        ) { $0 },
        state: &state
      )
    }

    assertTerminal(selected.buffer) {
      """
      │>>Item 0  │
      │>>Line 2  │
      │  Item 1  │
      │  Item 2  │
      │          │
      """
    }
    #expect(
      selected.buffer.cell(at: Position(x: 4, y: 1))?.style.modifiers.contains(.reversed)
        == true
    )

    var bottom = Buffer(area: Rect(x: 0, y: 0, width: 10, height: 4))
    List(
      ["Item 0", "Item 1", "Item 2"],
      direction: .bottomToTop,
      highlightSpacing: .never
    ) { $0 }.render(in: bottom.area, into: &bottom)
    assertTerminal(bottom) {
      """
      │          │
      │Item 2    │
      │Item 1    │
      │Item 0    │
      """
    }
  }

  @Test func multilineListScrollsByRenderedHeight() {
    var state = ListState(selected: 2)
    assertWidget(
      List(["zero\ncontinued", "one", "two"], marker: "> ") { $0 },
      size: Size(width: 8, height: 2),
      state: &state
    ) {
      """
      │  one   │
      │> two   │
      """
    }
    #expect(state.offset == 1)
  }

  @Test func listScrollPaddingKeepsContextWithoutFlickering() {
    let rows = (0..<6).map { "Item \($0)" }
    var before = ListState(offset: 2, selected: 2)
    assertWidget(
      List(rows, marker: ">> ", scrollPadding: 1) { $0 },
      size: Size(width: 10, height: 4),
      state: &before
    ) {
      """
      │   Item 1 │
      │>> Item 2 │
      │   Item 3 │
      │   Item 4 │
      """
    }
    #expect(before.offset == 1)

    var after = ListState(offset: 1, selected: 4)
    assertWidget(
      List(rows, marker: ">> ", scrollPadding: 2) { $0 },
      size: Size(width: 10, height: 4),
      state: &after
    ) {
      """
      │   Item 2 │
      │   Item 3 │
      │>> Item 4 │
      │   Item 5 │
      """
    }
    let stableOffset = after.offset
    var replay = Buffer(area: Rect(x: 0, y: 0, width: 10, height: 4))
    List(rows, marker: ">> ", scrollPadding: 2) { $0 }
      .render(in: replay.area, into: &replay, state: &after)
    #expect(after.offset == stableOffset)
  }

  @Test func statefulTableKeepsSelectionVisible() {
    var state = TableState(selectedRow: 4, selectedColumn: 0)
    let buffer = assertWidget(
      Table(["zero", "one", "two", "three", "four", "five"]) {
        TableColumn("Value") { $0 }
      },
      size: Size(width: 8, height: 4),
      state: &state
    ) {
      """
      │Value   │
      │two     │
      │three   │
      │four    │
      """
    }
    #expect(state.offset == 2)
    #expect(state.selectedCell?.row == 4)
    #expect(buffer.cell(at: Position(x: 0, y: 3))?.style.modifiers.contains(.bold) == true)
  }

  @Test func tableOffsetsFollowSelectionAcrossTheUpstreamBoundaryMatrix() {
    func render(selectedRow: Int?) -> (buffer: Buffer, offset: Int) {
      var state = TableState(offset: 50, selectedRow: selectedRow)
      var buffer = Buffer(area: Rect(x: 0, y: 0, width: 2, height: 5))
      Table((0..<100).map(String.init), headerConfiguration: .hidden) {
        TableColumn("", width: .length(2)) { $0 }
      }
      .render(in: buffer.area, into: &buffer, state: &state)
      return (buffer, state.offset)
    }

    let noSelection = render(selectedRow: nil)
    assertTerminal(noSelection.buffer) {
      """
      │50│
      │51│
      │52│
      │53│
      │54│
      """
    }
    #expect(noSelection.offset == 50)

    let before = render(selectedRow: 20)
    assertTerminal(before.buffer) {
      """
      │20│
      │21│
      │22│
      │23│
      │24│
      """
    }
    #expect(before.offset == 20)

    let immediatelyBefore = render(selectedRow: 49)
    assertTerminal(immediatelyBefore.buffer) {
      """
      │49│
      │50│
      │51│
      │52│
      │53│
      """
    }
    #expect(immediatelyBefore.offset == 49)

    let atStart = render(selectedRow: 50)
    assertTerminal(atStart.buffer) {
      """
      │50│
      │51│
      │52│
      │53│
      │54│
      """
    }
    #expect(atStart.offset == 50)

    let atEnd = render(selectedRow: 54)
    assertTerminal(atEnd.buffer) {
      """
      │50│
      │51│
      │52│
      │53│
      │54│
      """
    }
    #expect(atEnd.offset == 50)

    let immediatelyAfter = render(selectedRow: 55)
    assertTerminal(immediatelyAfter.buffer) {
      """
      │51│
      │52│
      │53│
      │54│
      │55│
      """
    }
    #expect(immediatelyAfter.offset == 51)

    let after = render(selectedRow: 80)
    assertTerminal(after.buffer) {
      """
      │76│
      │77│
      │78│
      │79│
      │80│
      """
    }
    #expect(after.offset == 76)
  }

  @Test func tableSupportsRowHeightsSpacingFootersAndLayeredSelectionStyles() {
    struct Row {
      var name: String
      var value: Int
    }

    var state = TableState(selectedRow: 2, selectedColumn: 1)
    let buffer = assertWidget(
      Table(
        [
          Row(name: "A\nalias", value: 1),
          Row(name: "B", value: 2),
          Row(name: "C", value: 3),
        ],
        selectedColumnStyle: Style(foreground: .cyan),
        selectedCellStyle: Style(modifiers: [.bold]),
        rowSpacing: 1,
        rowHeight: { $0.name.contains("\n") ? 2 : 1 }
      ) {
        TableColumn("Name", value: \.name, footer: "Total", width: .length(6))
        TableColumn("Value", value: \.value, footer: "2 rows")
      },
      size: Size(width: 12, height: 6),
      state: &state
    ) {
      """
      │Name   Value│
      │B      2    │
      │            │
      │C      3    │
      │            │
      │Total  2 row│
      """
    }
    #expect(state.offset == 1)
    let selectedCell = buffer.cell(at: Position(x: 7, y: 3))
    #expect(selectedCell?.style.foreground == .cyan)
    #expect(selectedCell?.style.modifiers.contains([.bold, .reversed]) == true)
  }

  @Test func tableRendersMultilineCells() throws {
    var buffer = Buffer(area: Rect(x: 0, y: 0, width: 8, height: 4))
    Table(["one\ntwo"], rowHeight: { _ in 2 }) {
      TableColumn("Value") { $0 }
    }.render(in: buffer.area, into: &buffer)

    assertTerminal(buffer) {
      """
      │Value   │
      │one     │
      │two     │
      │        │
      """
    }
  }

  @Test func tableHighlightSpacingPrioritizesTheSelectionColumn() {
    func table(
      selectedRow: Int?,
      spacing: HighlightSpacing,
      width: UInt16 = 15
    ) -> Buffer {
      var buffer = Buffer(area: Rect(x: 0, y: 0, width: width, height: 2))
      Table(
        ["ABCDE|12345"],
        selectedRow: selectedRow,
        highlightSymbol: ">>>",
        highlightSpacing: spacing,
        columnSpacing: 0
      ) {
        TableColumn("Left", width: .fill) { $0.split(separator: "|")[0].description }
        TableColumn("Right", width: .fill) { $0.split(separator: "|")[1].description }
      }.render(in: buffer.area, into: &buffer)
      return buffer
    }

    assertTerminal(table(selectedRow: nil, spacing: .never)) {
      """
      │Left   Right   │
      │ABCDE  12345   │
      """
    }
    assertTerminal(table(selectedRow: 0, spacing: .never)) {
      """
      │Left   Right   │
      │ABCDE  12345   │
      """
    }
    assertTerminal(table(selectedRow: nil, spacing: .whenSelected)) {
      """
      │Left   Right   │
      │ABCDE  12345   │
      """
    }
    assertTerminal(table(selectedRow: 0, spacing: .whenSelected)) {
      """
      │   Left  Right │
      │>>>ABCDE 12345 │
      """
    }
    assertTerminal(table(selectedRow: nil, spacing: .always)) {
      """
      │   Left  Right │
      │   ABCDE 12345 │
      """
    }
    assertTerminal(table(selectedRow: 0, spacing: .always)) {
      """
      │   Left  Right │
      │>>>ABCDE 12345 │
      """
    }
    assertTerminal(table(selectedRow: 0, spacing: .always, width: 8)) {
      """
      │   LeRig│
      │>>>AB123│
      """
    }
  }

  @Test func tableCellsCanSpanColumnsFromTypedRowState() {
    struct Row {
      var primary: String
      var secondary: String
      var spansBothColumns: Bool
    }

    var state = TableState(selectedRow: 0, selectedColumn: 1)
    let buffer = assertWidget(
      Table(
        [
          Row(primary: "spans the row", secondary: "hidden", spansBothColumns: true),
          Row(primary: "left", secondary: "right", spansBothColumns: false),
        ],
        selectedColumnStyle: Style(foreground: .cyan),
        selectedCellStyle: Style(modifiers: [.bold]),
        columnSpacing: 1
      ) {
        TableColumn(
          "Primary",
          value: \.primary,
          width: .fill,
          columnSpan: { $0.spansBothColumns ? 2 : 1 }
        )
        TableColumn("Secondary", value: \.secondary, width: .fill)
      },
      size: Size(width: 20, height: 3),
      state: &state
    ) {
      """
      │Primary   Secondary │
      │spans the row       │
      │left      right     │
      """
    }
    #expect(buffer.cell(at: Position(x: 10, y: 1))?.style.foreground == .cyan)
    #expect(buffer.cell(at: Position(x: 10, y: 1))?.style.modifiers.contains(.bold) == true)
    #expect(buffer.cell(at: Position(x: 0, y: 1))?.style.foreground == nil)
  }

  @Test func tableColumnSpansPreserveUpstreamSelectionWidthPrecedence() {
    func render(selectedRow: Int?, highlightSpacing: HighlightSpacing) -> Buffer {
      var buffer = Buffer(area: Rect(x: 0, y: 0, width: 15, height: 3))
      Table(
        [()],
        selectedRow: selectedRow,
        headerConfiguration: .hidden,
        highlightSymbol: ">>>",
        highlightSpacing: highlightSpacing,
        columnSpacing: 1
      ) {
        TableColumn(
          Line(""),
          cell: { _ in
            TableCell("ABCDEFGHIJK", columnSpan: 2)
          })
        TableColumn("") { _ in "XYZXYZXYZXY" }
        TableColumn("") { _ in "12345678901" }
      }
      .render(in: buffer.area, into: &buffer)
      return buffer
    }

    assertTerminal(render(selectedRow: nil, highlightSpacing: .always)) {
      """
      │   ABCDEFGH 123│
      │               │
      │               │
      """
    }
    assertTerminal(render(selectedRow: 0, highlightSpacing: .always)) {
      """
      │>>>ABCDEFGH 123│
      │               │
      │               │
      """
    }
    assertTerminal(render(selectedRow: nil, highlightSpacing: .whenSelected)) {
      """
      │ABCDEFGHIJ 1234│
      │               │
      │               │
      """
    }
    assertTerminal(render(selectedRow: 0, highlightSpacing: .whenSelected)) {
      """
      │>>>ABCDEFGH 123│
      │               │
      │               │
      """
    }
  }

  @Test func tableFlexPositionsExplicitColumnConstraints() {
    assertWidget(
      Table(
        [()],
        headerConfiguration: .hidden,
        columnSpacing: 1,
        flex: .end
      ) {
        TableColumn("", width: .length(2)) { _ in "A" }
        TableColumn("", width: .length(2)) { _ in "B" }
      },
      size: Size(width: 8, height: 1)
    ) {
      """
      │   A  B │
      """
    }
  }

  @Test func tableColumnConstraintsMatchUpstreamSolverBoundaries() {
    func areas(
      _ constraints: [Constraint],
      width: UInt16,
      selectionWidth: UInt16 = 0,
      flex: Flex = .start
    ) -> [Rect] {
      Table<TableRow>.resolveColumnAreas(
        in: Rect(
          x: selectionWidth,
          y: 0,
          width: width - selectionWidth,
          height: 1
        ),
        constraints: constraints,
        spacing: 1,
        flex: flex
      )
    }

    #expect(
      areas([.length(4), .length(4)], width: 20) == [
        Rect(x: 0, y: 0, width: 4, height: 1), Rect(x: 5, y: 0, width: 4, height: 1),
      ])
    #expect(
      areas([.length(4), .length(4)], width: 20, selectionWidth: 3) == [
        Rect(x: 3, y: 0, width: 4, height: 1), Rect(x: 8, y: 0, width: 4, height: 1),
      ])
    #expect(
      areas([.length(4), .length(4)], width: 7) == [
        Rect(x: 0, y: 0, width: 3, height: 1), Rect(x: 4, y: 0, width: 3, height: 1),
      ])
    #expect(
      areas([.length(4), .length(4)], width: 7, selectionWidth: 3) == [
        Rect(x: 3, y: 0, width: 2, height: 1), Rect(x: 6, y: 0, width: 1, height: 1),
      ])

    #expect(
      areas([.max(4), .max(4)], width: 20) == [
        Rect(x: 0, y: 0, width: 4, height: 1), Rect(x: 5, y: 0, width: 4, height: 1),
      ])
    #expect(
      areas([.max(4), .max(4)], width: 20, selectionWidth: 3) == [
        Rect(x: 3, y: 0, width: 4, height: 1), Rect(x: 8, y: 0, width: 4, height: 1),
      ])
    #expect(
      areas([.max(4), .max(4)], width: 7) == [
        Rect(x: 0, y: 0, width: 3, height: 1), Rect(x: 4, y: 0, width: 3, height: 1),
      ])
    #expect(
      areas([.max(4), .max(4)], width: 7, selectionWidth: 3) == [
        Rect(x: 3, y: 0, width: 2, height: 1), Rect(x: 6, y: 0, width: 1, height: 1),
      ])

    #expect(
      areas([.min(4), .min(4)], width: 20) == [
        Rect(x: 0, y: 0, width: 10, height: 1), Rect(x: 11, y: 0, width: 9, height: 1),
      ])
    #expect(
      areas([.min(4), .min(4)], width: 20, selectionWidth: 3) == [
        Rect(x: 3, y: 0, width: 8, height: 1), Rect(x: 12, y: 0, width: 8, height: 1),
      ])
    #expect(
      areas([.min(4), .min(4)], width: 7) == [
        Rect(x: 0, y: 0, width: 3, height: 1), Rect(x: 4, y: 0, width: 3, height: 1),
      ])
    #expect(
      areas([.min(4), .min(4)], width: 7, selectionWidth: 3) == [
        Rect(x: 3, y: 0, width: 2, height: 1), Rect(x: 6, y: 0, width: 1, height: 1),
      ])

    #expect(
      areas([.percentage(30), .percentage(30)], width: 20) == [
        Rect(x: 0, y: 0, width: 6, height: 1), Rect(x: 7, y: 0, width: 6, height: 1),
      ])
    #expect(
      areas([.percentage(30), .percentage(30)], width: 20, selectionWidth: 3) == [
        Rect(x: 3, y: 0, width: 5, height: 1), Rect(x: 9, y: 0, width: 5, height: 1),
      ])
    #expect(
      areas([.percentage(30), .percentage(30)], width: 7) == [
        Rect(x: 0, y: 0, width: 2, height: 1), Rect(x: 3, y: 0, width: 2, height: 1),
      ])
    #expect(
      areas([.percentage(30), .percentage(30)], width: 7, selectionWidth: 3) == [
        Rect(x: 3, y: 0, width: 1, height: 1), Rect(x: 5, y: 0, width: 1, height: 1),
      ])

    #expect(
      areas(
        [.ratio(numerator: 1, denominator: 3), .ratio(numerator: 1, denominator: 3)], width: 20)
        == [
          Rect(x: 0, y: 0, width: 7, height: 1), Rect(x: 8, y: 0, width: 6, height: 1),
        ])
    #expect(
      areas(
        [.ratio(numerator: 1, denominator: 3), .ratio(numerator: 1, denominator: 3)], width: 20,
        selectionWidth: 3) == [
          Rect(x: 3, y: 0, width: 6, height: 1), Rect(x: 10, y: 0, width: 5, height: 1),
        ])
    #expect(
      areas([.ratio(numerator: 1, denominator: 3), .ratio(numerator: 1, denominator: 3)], width: 7)
        == [
          Rect(x: 0, y: 0, width: 2, height: 1), Rect(x: 3, y: 0, width: 3, height: 1),
        ])
    #expect(
      areas(
        [.ratio(numerator: 1, denominator: 3), .ratio(numerator: 1, denominator: 3)], width: 7,
        selectionWidth: 3) == [
          Rect(x: 3, y: 0, width: 1, height: 1), Rect(x: 5, y: 0, width: 2, height: 1),
        ])

    let minimums: [Constraint] = [.min(10), .min(10), .min(1)]
    #expect(
      areas(minimums, width: 62) == [
        Rect(x: 0, y: 0, width: 20, height: 1),
        Rect(x: 21, y: 0, width: 20, height: 1),
        Rect(x: 42, y: 0, width: 20, height: 1),
      ])
    #expect(
      areas(minimums, width: 62, flex: .legacy) == [
        Rect(x: 0, y: 0, width: 10, height: 1),
        Rect(x: 11, y: 0, width: 10, height: 1),
        Rect(x: 22, y: 0, width: 40, height: 1),
      ])
    #expect(
      areas(minimums, width: 62, flex: .spaceBetween) == [
        Rect(x: 0, y: 0, width: 20, height: 1),
        Rect(x: 21, y: 0, width: 20, height: 1),
        Rect(x: 42, y: 0, width: 20, height: 1),
      ])
  }

  @Test func tableMixedConstraintsRespectUpstreamPriorityOrdering() {
    func widths(_ constraints: [Constraint], flex: Flex = .legacy) -> [UInt16] {
      Table<TableRow>.resolveColumnAreas(
        in: Rect(x: 0, y: 0, width: 100, height: 1),
        constraints: constraints,
        spacing: 0,
        flex: flex
      ).map(\.width)
    }

    let legacyCases: [([Constraint], [UInt16])] = [
      ([.length(25), .length(25)], [25, 75]),
      ([.length(25), .percentage(25)], [25, 75]),
      ([.percentage(25), .length(25)], [75, 25]),
      ([.min(25), .percentage(25)], [75, 25]),
      ([.percentage(25), .min(25)], [25, 75]),
      ([.min(25), .percentage(100)], [25, 75]),
      ([.percentage(100), .min(25)], [75, 25]),
      ([.max(75), .percentage(75)], [25, 75]),
      ([.percentage(75), .max(75)], [75, 25]),
      ([.max(25), .percentage(25)], [25, 75]),
      ([.percentage(25), .max(25)], [75, 25]),
      ([.length(25), .ratio(numerator: 1, denominator: 4)], [25, 75]),
      ([.ratio(numerator: 1, denominator: 4), .length(25)], [75, 25]),
      ([.percentage(25), .ratio(numerator: 1, denominator: 4)], [25, 75]),
      ([.ratio(numerator: 1, denominator: 4), .percentage(25)], [75, 25]),
      ([.ratio(numerator: 1, denominator: 4), .flex(25)], [25, 75]),
      ([.flex(25), .ratio(numerator: 1, denominator: 4)], [75, 25]),
    ]
    for (constraints, expected) in legacyCases {
      #expect(widths(constraints) == expected)
    }

    #expect(widths([.min(10), .length(10)], flex: .start) == [90, 10])
    #expect(widths([.min(10), .percentage(100)], flex: .start) == [10, 90])
    #expect(widths([.percentage(50), .percentage(50)], flex: .start) == [50, 50])
  }

  @Test func tableHighlightSymbolPreservesRichSpanStylesUnderSelection() {
    let buffer = assertWidget(
      Table(
        ["row"],
        selectedRow: 0,
        headerConfiguration: .hidden,
        selectedStyle: Style(background: .blue),
        highlightSymbol: Line {
          Span(">").foregroundStyle(.red)
          Span(">").bold()
        },
        highlightSpacing: .whenSelected
      ) {
        TableColumn("") { $0 }
      },
      size: Size(width: 6, height: 1)
    ) {
      """
      │>>row │
      """
    }

    #expect(buffer.cell(at: Position(x: 0, y: 0))?.style.foreground == .red)
    #expect(buffer.cell(at: Position(x: 0, y: 0))?.style.background == .blue)
    #expect(buffer.cell(at: Position(x: 1, y: 0))?.style.modifiers.contains(.bold) == true)
    #expect(buffer.cell(at: Position(x: 1, y: 0))?.style.background == .blue)
  }

  @Test func tableHighlightSymbolSupportsRichMultilineText() {
    let table = Table(
      [TableRow([TableCell("row")], height: 3)],
      widths: [.length(3)],
      selectedRow: 0,
      selectedStyle: Style(background: .blue),
      highlightSpacing: .whenSelected
    )
    .withHighlightSymbols {
      Line { Span(">").foregroundStyle(.red) }
      Line { Span(">>").bold() }
      Line(">>>")
    }
    let buffer = assertWidget(table, size: Size(width: 8, height: 3)) {
      """
      │>  row  │
      │>>      │
      │>>>     │
      """
    }

    #expect(buffer.cell(at: Position(x: 0, y: 0))?.style.foreground == .red)
    #expect(buffer.cell(at: Position(x: 1, y: 1))?.style.modifiers.contains(.bold) == true)
    #expect(buffer.cell(at: Position(x: 2, y: 2))?.symbol == ">")
    #expect(buffer.cell(at: Position(x: 7, y: 2))?.style.background == .blue)
  }

  @Test func rowOwnedTableCellsMatchUpstreamSequentialSpanConsumption() {
    func render(_ rows: [TableRow], width: UInt16, columnCount: Int) -> Buffer {
      var buffer = Buffer(area: Rect(x: 0, y: 0, width: width, height: UInt16(rows.count)))
      Table(rows, widths: Array(repeating: .length(5), count: columnCount))
        .render(in: buffer.area, into: &buffer)
      return buffer
    }

    assertTerminal(
      render(
        [
          TableRow {
            "Cell1"
            "Cell2"
          },
          TableRow {
            "Cell3"
            "Cell4"
          },
        ],
        width: 15,
        columnCount: 2
      )
    ) {
      """
      │Cell1 Cell2    │
      │Cell3 Cell4    │
      """
    }
    assertTerminal(
      render(
        [
          TableRow {
            TableCell("Cell1", columnSpan: 0)
            "Cell2"
          },
          TableRow {
            "Cell3"
            "Cell4"
          },
        ],
        width: 15,
        columnCount: 2
      )
    ) {
      """
      │Cell2          │
      │Cell3 Cell4    │
      """
    }
    assertTerminal(
      render(
        [
          TableRow {
            TableCell("Cell1", columnSpan: 2)
            "Cell2"
          },
          TableRow {
            "Cell3"
            "Cell4"
          },
        ],
        width: 15,
        columnCount: 2
      )
    ) {
      """
      │Cell1          │
      │Cell3 Cell4    │
      """
    }
    assertTerminal(
      render(
        [
          TableRow {
            TableCell("Cell1", columnSpan: 2)
            "Cell2"
          },
          TableRow {
            "Cell3"
            "Cell4"
            "Cell5"
          },
        ],
        width: 17,
        columnCount: 3
      )
    ) {
      """
      │Cell1       Cell2│
      │Cell3 Cell4 Cell5│
      """
    }
    assertTerminal(
      render(
        [
          TableRow {
            "Cell1"
            TableCell("Cell2", columnSpan: 2)
            "Cell3"
          },
          TableRow {
            "Cell4"
            "Cell5"
            "Cell6"
          },
        ],
        width: 17,
        columnCount: 3
      )
    ) {
      """
      │Cell1 Cell2      │
      │Cell4 Cell5 Cell6│
      """
    }
    assertTerminal(
      render(
        [
          TableRow {
            TableCell("11111111111111111111", columnSpan: 2)
            "22222222222222222222"
          },
          TableRow {
            "33333333333333333333"
            TableCell("44444444444444444444", columnSpan: 2)
            "55555555555555555555"
          },
        ],
        width: 15,
        columnCount: 3
      )
    ) {
      """
      │1111111111 2222│
      │3333 4444444444│
      """
    }

    var geometry = Buffer(area: Rect(x: 0, y: 0, width: 15, height: 1))
    var state = TableState(selectedColumn: 1)
    Table(
      [
        TableRow {
          "A"
          "B"
          "C"
        }
      ],
      widths: [.length(5), .length(5), .length(5)],
      selectedColumnStyle: Style(background: .cyan)
    )
    .render(in: geometry.area, into: &geometry, state: &state)
    #expect(geometry.cell(at: Position(x: 4, y: 0))?.style.background == nil)
    #expect(geometry.cell(at: Position(x: 5, y: 0))?.style.background == .cyan)
    #expect(geometry.cell(at: Position(x: 9, y: 0))?.style.background == .cyan)
    #expect(geometry.cell(at: Position(x: 10, y: 0))?.style.background == nil)
  }

  @Test func rowOwnedTableDerivesColumnCountAcrossBandsAndKeepsRowGeometry() {
    let header = TableRow(style: Style(background: .blue)) {
      "H1"
      "H2"
    }
    let footer = TableRow(style: Style(background: .magenta)) {
      "F1"
      "F2"
      "F3"
      "F4"
    }
    let rows = [
      TableRow(style: Style(background: .green), topMargin: 1) {
        "A"
        "B"
        "C"
      }
    ]
    var state = TableState(selectedColumn: 99)
    let buffer = assertWidget(
      Table(
        rows,
        header: header,
        footer: footer,
        selectedColumnStyle: Style(foreground: .cyan)
      ),
      size: Size(width: 20, height: 5),
      state: &state
    ) {
      """
      │H1   H2             │
      │                    │
      │A    B     C        │
      │                    │
      │F1   F2    F3   F4  │
      """
    }

    #expect(state.selectedColumn == 3)
    #expect(buffer.cell(at: Position(x: 0, y: 0))?.style.background == .blue)
    #expect(buffer.cell(at: Position(x: 0, y: 1))?.style.background == nil)
    #expect(buffer.cell(at: Position(x: 0, y: 2))?.style.background == .green)
    #expect(buffer.cell(at: Position(x: 16, y: 2))?.style.foreground == .cyan)
    #expect(buffer.cell(at: Position(x: 16, y: 4))?.style.background == .magenta)

    var narrowState = TableState(selectedColumn: 99)
    assertWidget(
      Table(rows, widths: [.length(5)], footer: footer),
      size: Size(width: 10, height: 3),
      state: &narrowState
    ) {
      """
      │          │
      │A         │
      │F1        │
      """
    }
    #expect(narrowState.selectedColumn == 3)
  }

  @Test func tableRichCellsComposeStylesAlignmentMultilineAndSpans() {
    struct Row {
      var spanning: Bool
    }

    var state = TableState(selectedRow: 1, selectedColumn: 1)
    let buffer = assertWidget(
      Table(
        [Row(spanning: false), Row(spanning: true)],
        headerStyle: Style(foreground: .yellow),
        footerStyle: Style(background: .magenta),
        selectedStyle: Style(background: .green),
        selectedColumnStyle: Style(foreground: .cyan),
        selectedCellStyle: Style(modifiers: [.underlined]),
        columnSpacing: 1,
        rowHeight: { _ in 2 }
      ) {
        TableColumn(
          Line(alignment: .center) {
            Span("Na").foregroundStyle(.red)
            Span("me").bold()
          },
          footer: Line("total", alignment: .trailing),
          width: .length(8),
          style: Style(background: .blue),
          cell: { row in
            if row.spanning {
              return TableCell(style: Style(modifiers: [.dim]), columnSpan: 2) {
                Line("spanning", alignment: .trailing)
                Line(alignment: .center) { Span("two").foregroundStyle(.red) }
              }
            } else {
              return TableCell(style: Style(modifiers: [.italic])) {
                Line(alignment: .center) {
                  Span("red").foregroundStyle(.red)
                  Span("!").bold()
                }
                Line("tail", alignment: .trailing)
              }
            }
          }
        )
        TableColumn(
          Line("Info", alignment: .trailing),
          footer: Line("done"),
          width: .fill,
          lines: { _ in [Line("right"), Line("edge", alignment: .trailing)] }
        )
      },
      size: Size(width: 17, height: 6),
      state: &state
    ) {
      """
      │  Name       Info│
      │  red!   right   │
      │    tail     edge│
      │         spanning│
      │       two       │
      │   total done    │
      """
    }

    #expect(buffer.cell(at: Position(x: 2, y: 0))?.style.foreground == .red)
    #expect(buffer.cell(at: Position(x: 4, y: 0))?.style.modifiers.contains(.bold) == true)
    #expect(buffer.cell(at: Position(x: 2, y: 1))?.style.foreground == .red)
    #expect(buffer.cell(at: Position(x: 0, y: 1))?.style.background == .blue)
    #expect(buffer.cell(at: Position(x: 0, y: 3))?.style.background == .green)
    #expect(buffer.cell(at: Position(x: 0, y: 3))?.style.foreground == nil)
    #expect(buffer.cell(at: Position(x: 9, y: 3))?.style.foreground == .cyan)
    #expect(buffer.cell(at: Position(x: 9, y: 3))?.style.modifiers.contains(.underlined) == true)
    #expect(buffer.cell(at: Position(x: 3, y: 5))?.style.background == .magenta)
  }

  @Test func tableRowsOwnIndependentMarginsHeightAndStyle() {
    struct Row {
      var first: String
      var second: String
      var configuration: TableRowConfiguration
    }

    let rows = [
      Row(
        first: "Cell1\nLine2",
        second: "Cell2\nLine2",
        configuration: TableRowConfiguration(
          style: Style(background: .blue),
          height: 2,
          topMargin: 1,
          bottomMargin: 1
        )
      ),
      Row(
        first: "Cell3",
        second: "Cell4",
        configuration: TableRowConfiguration(style: Style(foreground: .green))
      ),
    ]
    let buffer = assertWidget(
      Table(rows, columnSpacing: 1, rowConfiguration: \.configuration) {
        TableColumn("First", value: \.first, width: .length(7))
        TableColumn("Second", value: \.second, width: .length(7))
      },
      size: Size(width: 15, height: 6)
    ) {
      """
      │First   Second │
      │               │
      │Cell1   Cell2  │
      │Line2   Line2  │
      │               │
      │Cell3   Cell4  │
      """
    }

    #expect(buffer.cell(at: Position(x: 0, y: 1))?.style.background == nil)
    #expect(buffer.cell(at: Position(x: 0, y: 2))?.style.background == .blue)
    #expect(buffer.cell(at: Position(x: 0, y: 4))?.style.background == nil)
    #expect(buffer.cell(at: Position(x: 0, y: 5))?.style.foreground == .green)

    let clamped = TableRowConfiguration(height: -1, topMargin: -2, bottomMargin: Int.max)
    #expect(clamped.height == 0)
    #expect(clamped.topMargin == 0)
    #expect(clamped.bottomMargin == Int(UInt16.max))
  }

  @Test func tableIncludesAPartialTrailingRowLikeUpstream() {
    struct Row {
      var value: String
      var height: Int
    }

    var state = TableState()
    assertWidget(
      Table(
        [
          Row(value: "first", height: 1),
          Row(value: "second\nline 2\nline 3", height: 3),
        ],
        rowConfiguration: {
          TableRowConfiguration(height: $0.height)
        }
      ) {
        TableColumn("Value", value: \.value)
      },
      size: Size(width: 8, height: 3),
      state: &state
    ) {
      """
      │Value   │
      │first   │
      │second  │
      """
    }
    #expect(state.offset == 0)
  }

  @Test func tableHeaderAndFooterOwnMultilineSizingAndMargins() {
    struct Row {
      var first: String
      var second: String
    }

    let buffer = assertWidget(
      Table(
        [Row(first: "Cell1", second: "Cell2")],
        headerConfiguration: TableRowConfiguration(
          style: Style(background: .blue),
          height: 2,
          bottomMargin: 1
        ),
        footerConfiguration: TableRowConfiguration(
          style: Style(background: .magenta),
          height: 2,
          topMargin: 1
        ),
        columnSpacing: 1
      ) {
        TableColumn(
          header: [Line("Head1"), Line("units", alignment: .trailing)],
          footer: [Line("Foot1"), Line("sum", alignment: .trailing)],
          width: .length(7),
          headerCellStyle: Style(background: .red),
          footerCellStyle: Style(background: .green),
          cell: { TableCell($0.first) }
        )
        TableColumn(
          header: [Line("Head2"), Line("count", alignment: .trailing)],
          footer: [Line("Foot2"), Line("all", alignment: .trailing)],
          width: .length(7),
          cell: { TableCell($0.second) }
        )
      },
      size: Size(width: 15, height: 9)
    ) {
      """
      │Head1   Head2  │
      │  units   count│
      │               │
      │Cell1   Cell2  │
      │               │
      │               │
      │               │
      │Foot1   Foot2  │
      │    sum     all│
      """
    }

    #expect(buffer.cell(at: Position(x: 0, y: 0))?.style.background == .red)
    #expect(buffer.cell(at: Position(x: 8, y: 0))?.style.background == .blue)
    #expect(buffer.cell(at: Position(x: 0, y: 2))?.style.background == nil)
    #expect(buffer.cell(at: Position(x: 0, y: 6))?.style.background == nil)
    #expect(buffer.cell(at: Position(x: 0, y: 7))?.style.background == .green)
    #expect(buffer.cell(at: Position(x: 8, y: 7))?.style.background == .magenta)
  }

  @Test func tableBaseStyleCoversItsAreaAndParticipatesInEveryStyleLayer() {
    let buffer = assertWidget(
      Table(
        ["Cell"],
        style: Style(foreground: .red, background: .blue),
        headerConfiguration: TableRowConfiguration(topMargin: 1),
        rowConfiguration: { _ in
          TableRowConfiguration(style: Style(background: .green))
        }
      ) {
        TableColumn(
          Line("Header"),
          width: .length(6),
          style: Style(foreground: .yellow),
          headerCellStyle: Style(background: .cyan),
          cell: { value in
            TableCell(
              Line {
                Span(String(value.prefix(1)), style: Style(foreground: .magenta))
                Span(String(value.dropFirst()))
              },
              style: Style(background: .white)
            )
          }
        )
      },
      size: Size(width: 8, height: 4)
    ) {
      """
      │        │
      │Header  │
      │Cell    │
      │        │
      """
    }

    #expect(
      buffer.cell(at: Position(x: 7, y: 0))?.style == Style(foreground: .red, background: .blue))
    #expect(buffer.cell(at: Position(x: 0, y: 1))?.style.background == .cyan)
    #expect(buffer.cell(at: Position(x: 0, y: 1))?.style.foreground == .red)
    #expect(buffer.cell(at: Position(x: 0, y: 1))?.style.modifiers.contains(.bold) == true)
    #expect(
      buffer.cell(at: Position(x: 0, y: 2))?.style
        == Style(foreground: .magenta, background: .white))
    #expect(
      buffer.cell(at: Position(x: 1, y: 2))?.style == Style(foreground: .yellow, background: .white)
    )
    #expect(
      buffer.cell(at: Position(x: 7, y: 2))?.style == Style(foreground: .red, background: .green))
    #expect(
      buffer.cell(at: Position(x: 0, y: 3))?.style == Style(foreground: .red, background: .blue))

    var empty = Buffer(area: Rect(x: 0, y: 0, width: 2, height: 1))
    Table<Int>([], style: Style(background: .cyan)) {}
      .render(in: empty.area, into: &empty)
    #expect(empty.cell(at: Position(x: 0, y: 0))?.style.background == .cyan)
    #expect(empty.cell(at: Position(x: 1, y: 0))?.style.background == .cyan)
  }

  @Test func tableTinyAreasAndHiddenHeadersMatchUpstreamPrecedence() {
    let overconstrained = Table(["Cell"]) {
      TableColumn("Header", footer: "Footer", width: .length(10)) { $0 }
    }
    assertWidget(overconstrained, size: Size(width: 1, height: 1)) {
      """
      │ │
      """
    }

    var zero = Buffer(area: .zero)
    overconstrained.render(in: zero.area, into: &zero)
    #expect(zero.area == .zero)
    #expect(zero == Buffer(area: .zero))

    assertWidget(
      Table(["Cell"], headerConfiguration: .hidden) {
        TableColumn("Header") { $0 }
      },
      size: Size(width: 5, height: 1)
    ) {
      """
      │Cell │
      """
    }
  }

  @Test func collectionStateNavigationCanWrapSafely() {
    var list = ListState()
    list.selectPrevious(in: 0..<3)
    #expect(list.selected == 2)
    list.selectNext(in: 0..<3, wrapping: true)
    #expect(list.selected == 0)

    var table = TableState(selectedRow: 0)
    table.selectPreviousRow(in: 0..<3, wrapping: true)
    #expect(table.selectedRow == 2)
  }

  @Test func tableStateSupportsUnboundedNavigationBeforeRender() {
    var state = TableState(offset: 7)
    state.selectFirstRow()
    state.selectPreviousRow()
    #expect(state.selectedRow == 0)
    state.selectNextRow()
    #expect(state.selectedRow == 1)
    state.selectLastRow()
    state.selectNextRow()
    #expect(state.selectedRow == .max)
    state.selectPreviousRow()
    #expect(state.selectedRow == Int.max - 1)
    state.scrollUp(by: Int.max)
    #expect(state.selectedRow == 0)
    state.scrollDown(by: Int.max)
    #expect(state.selectedRow == .max)

    state.selectFirstColumn()
    state.selectPreviousColumn()
    #expect(state.selectedColumn == 0)
    state.selectNextColumn()
    state.scrollRight(by: 15)
    #expect(state.selectedColumn == 16)
    state.scrollLeft(by: 20)
    #expect(state.selectedColumn == 0)
    state.selectLastColumn()
    state.selectNextColumn()
    #expect(state.selectedColumn == .max)

    state.selectCell((row: 3, column: 4))
    #expect(state.selectedCell?.row == 3)
    #expect(state.selectedCell?.column == 4)
    state.selectRow(nil)
    #expect(state.offset == 0)
    #expect(state.selectedRow == nil)
    #expect(state.selectedColumn == 4)
    state.selectCell(nil)
    #expect(state.selectedCell == nil)
    #expect(state.selectedColumn == nil)
  }

  @Test func canvasMarkersAndShapesUseTheirNativeResolution() {
    var quadrant = Buffer(area: Rect(x: 0, y: 0, width: 1, height: 1))
    Canvas(
      x: 0...1,
      y: 0...1,
      points: [CanvasPoint(x: 0, y: 1), CanvasPoint(x: 1, y: 0)],
      marker: .quadrant
    ).render(in: quadrant.area, into: &quadrant)
    assertTerminal(quadrant) {
      """
      │▚│
      """
    }

    var rectangle = Buffer(area: Rect(x: 0, y: 0, width: 5, height: 3))
    Canvas(
      x: 0...4,
      y: 0...2,
      rectangles: [CanvasRectangle(x: 0, y: 0, width: 4, height: 2)],
      marker: .block
    ).render(in: rectangle.area, into: &rectangle)
    assertTerminal(rectangle) {
      """
      │█████│
      │█   █│
      │█████│
      """
    }

    var custom = Buffer(area: Rect(x: 0, y: 0, width: 1, height: 1))
    Canvas(x: 0...1, y: 0...1, points: [CanvasPoint(x: 0.5, y: 0.5)], marker: .custom("+"))
      .render(in: custom.area, into: &custom)
    assertTerminal(custom) {
      """
      │+│
      """
    }
  }

  @Test func canvasCircleMatchesUpstreamBrailleRasterization() {
    assertWidget(
      Canvas(
        x: -10...10,
        y: -10...10,
        circles: [CanvasCircle(center: (5, 2), radius: 5)],
        marker: .braille
      ),
      size: Size(width: 10, height: 5)
    ) {
      """
      │      ⣀⣀⣀ │
      │     ⡞⠁ ⠈⢣│
      │     ⢇⡀ ⢀⡼│
      │      ⠉⠉⠉ │
      │          │
      """
    }
  }

  @Test func canvasLinesMatchUpstreamAcrossEveryMarkerGrid() {
    let markers: [CanvasMarker] = [
      .block, .halfBlock, .bar, .braille, .quadrant, .sextant, .octant, .custom("×"),
      .custom("+"), .dot,
    ]
    var buffer = Buffer(
      area: Rect(x: 0, y: 0, width: UInt16(markers.count * 5), height: 10),
      repeating: Cell(symbol: "x")
    )
    for (index, marker) in markers.enumerated() {
      Canvas(
        x: 0...10,
        y: 0...10,
        lines: [
          CanvasLine(
            from: CanvasPoint(x: 0, y: 0),
            to: CanvasPoint(x: 0, y: 10)
          ),
          CanvasLine(
            from: CanvasPoint(x: 0, y: 0),
            to: CanvasPoint(x: 10, y: 0)
          ),
        ],
        marker: marker
      ).render(
        in: Rect(x: UInt16(index * 5), y: 0, width: 5, height: 5),
        into: &buffer
      )
      Canvas(
        x: 0...10,
        y: 0...10,
        lines: [
          CanvasLine(
            from: CanvasPoint(x: 0, y: 0),
            to: CanvasPoint(x: 10, y: 10)
          ),
          CanvasLine(
            from: CanvasPoint(x: 0, y: 10),
            to: CanvasPoint(x: 10, y: 0)
          ),
        ],
        marker: marker
      ).render(
        in: Rect(x: UInt16(index * 5), y: 5, width: 5, height: 5),
        into: &buffer
      )
    }
    assertTerminal(buffer) {
      """
      │█xxxx█xxxx▄xxxx⡇xxxx▌xxxx▌xxxx▌xxxx×xxxx+xxxx•xxxx│
      │█xxxx█xxxx▄xxxx⡇xxxx▌xxxx▌xxxx▌xxxx×xxxx+xxxx•xxxx│
      │█xxxx█xxxx▄xxxx⡇xxxx▌xxxx▌xxxx▌xxxx×xxxx+xxxx•xxxx│
      │█xxxx█xxxx▄xxxx⡇xxxx▌xxxx▌xxxx▌xxxx×xxxx+xxxx•xxxx│
      │██████▄▄▄▄▄▄▄▄▄⣇⣀⣀⣀⣀▙▄▄▄▄🬲🬭🬭🬭🬭𜷀▂▂▂▂×××××+++++•••••│
      │█xxx██xxx█▄xxx▄⢣xxx⡜▚xxx▞🬧xxx🬔▚xxx▞×xxx×+xxx+•xxx•│
      │x█x█xx█x█xx▄x▄xx⢣x⡜xx▚x▞xx🬧x🬔xx▚x▞xx×x×xx+x+xx•x•x│
      │xx█xxxx█xxxx▄xxxx⣿xxxx█xxxx█xxxx█xxxx×xxxx+xxxx•xx│
      │x█x█xx█x█xx▄x▄xx⡜x⢣xx▞x▚xx🬘x🬣xx▞x▚xx×x×xx+x+xx•x•x│
      │█xxx██xxx█▄xxx▄⡜xxx⢣▞xxx▚🬘xxx🬣▞xxx▚×xxx×+xxx+•xxx•│
      """
    }
  }

  @Test func canvasSupportsSextantAndOctantPseudoPixels() {
    #expect(Symbols.Pixel.quadrants.count == 16)
    #expect(Symbols.Pixel.sextants.count == 64)
    #expect(Symbols.Pixel.octants.count == 256)

    assertWidget(
      Canvas(
        x: 0...1,
        y: 0...1,
        points: [
          CanvasPoint(x: 0, y: 1),
          CanvasPoint(x: 1, y: 0.5),
          CanvasPoint(x: 0, y: 0),
        ],
        marker: .sextant
      ),
      size: Size(width: 1, height: 1)
    ) {
      """
      │🬗│
      """
    }

    assertWidget(
      Canvas(
        x: 0...1,
        y: 0...1,
        points: [
          CanvasPoint(x: 0, y: 1),
          CanvasPoint(x: 1, y: 2.0 / 3.0),
          CanvasPoint(x: 0, y: 1.0 / 3.0),
          CanvasPoint(x: 1, y: 0),
        ],
        marker: .octant
      ),
      size: Size(width: 1, height: 1)
    ) {
      """
      │𜶉│
      """
    }
  }

  @Test func canvasLayersComposeInBuilderOrderAndPatchStyles() {
    let canvas = Canvas(
      x: 0...2,
      y: 0...1,
      points: [
        CanvasPoint(x: 0, y: 0.5, style: Style(background: .blue)),
        CanvasPoint(x: 1, y: 0.5, style: Style(background: .blue)),
        CanvasPoint(x: 2, y: 0.5, style: Style(background: .blue)),
      ],
      marker: .custom(".")
    ) {
      CanvasLayer(
        points: [
          CanvasPoint(
            x: 1,
            y: 0.5,
            style: Style(foreground: .red, modifiers: [.bold])
          )
        ],
        marker: .custom("X")
      )
      CanvasLayer(
        points: [CanvasPoint(x: 2, y: 0.5, style: Style(foreground: .green))],
        marker: .custom("Y")
      )
    }

    let buffer = assertWidget(canvas, size: Size(width: 3, height: 1)) {
      """
      │.XY│
      """
    }
    let composed = buffer.cell(at: Position(x: 1, y: 0))
    #expect(composed?.style.background == .blue)
    #expect(composed?.style.foreground == .red)
    #expect(composed?.style.modifiers.contains(.bold) == true)
  }

  @Test func canvasMapsRenderBothGeographicResolutions() {
    #expect(CanvasMapResolution.low.pointCount == 1_166)
    #expect(CanvasMapResolution.high.pointCount == 5_125)

    let low = assertWidget(
      Canvas(
        x: (-180.0)...180.0,
        y: (-90.0)...90.0,
        maps: [CanvasMap(style: Style(foreground: .cyan))],
        marker: .dot
      ),
      size: Size(width: 32, height: 12)
    ) {
      """
      │        ••••••                  │
      │•••••••••••••••• •••••••••••••••│
      │••••••••••••• ••••••       •••••│
      │     •••••••   ••••••••   •••   │
      │  •  ••••••   •• •••••••••••    │
      │       •••••  ••• ••• •••••     │
      │ •      •• •••   ••••   •••••   │
      │         • ••    ••••    •••••••│
      │         •••     ••      •••• ••│
      │         ••                     │
      │••••••••••••••••••••••••••••••••│
      │•  •       •                  ••│
      """
    }
    #expect(
      low.cell(at: Position(x: 8, y: 0))?.style.foreground == .cyan
    )

    assertWidget(
      Canvas(
        x: (-180.0)...180.0,
        y: (-90.0)...90.0,
        maps: [CanvasMap(resolution: .high)],
        marker: .braille
      ),
      size: Size(width: 32, height: 12)
    ) {
      """
      │     ⣀⣀⣠⣤⣤⡤⠤⠤⠤⣤ ⢀⣠⡄⠠⡤⢀ ⢀⣤⣀      │
      │⣦⣴⢒⠒⠖⠻⠿⢿⣿⣿⡯⣗⡠⢼⣧ ⣀⣴⡶⣦⠼⠿⠿⠋⠉⠉⠉⠛⠋⢓⡲⣒│
      │ ⠙⠛⠉⢷⡄ ⠘⠲⢏⣽⡎⠁  ⢿⠽⠛⢋⡀⣀      ⠐⣿⠹⠏⠁│
      │     ⣇⡀ ⢀⡞⠉    ⡿⢿⣿⣿⡟⠿     ⢶⣯⠟   │
      │  ⡄  ⠈⢷⣿⣽⣧⡀   ⢸⠁ ⠈⠘⣧⢛⡖⡄⡤⣄⣤⣾     │
      │       ⠈⢻⡞⠲⢤  ⠹⠤⢤  ⢘⡇ ⠸⠇⢼⣮⣾⡆    │
      │        ⠘⡇ ⠈⢹   ⠘⡆ ⢯⡀   ⠘⠿⢿⣿⣷⠷⢄ │
      │⠁        ⢸ ⢠⠞    ⡇⢠⠿⠇    ⢰⡚⠈⠙⡆⠚⠈│
      │         ⣸⡼⠋     ⠘⠉       ⠋⠙⢷⠃⢀⡷│
      │         ⠻⠗           ⠁       ⠈ │
      │   ⣀⣀⣀⣠⣤⣄⣴⣿  ⢀⣠⠤⠤⠤⠴⠶⠒⠲⠶⠒⠒⠒⠒⠒⠒⠲⣤ │
      │⠶⠮⠿⠇     ⠙⠛⠛⠛⠋               ⠐⠛⠦│
      """
    }
  }

  @Test func canvasLabelsRenderRichTextAboveEveryLayer() {
    let buffer = assertWidget(
      Canvas(
        x: 0...10,
        y: 0...10,
        points: [CanvasPoint(x: 5, y: 5)],
        labels: [
          CanvasLabel(
            x: 5,
            y: 5,
            content: Line {
              Span("Sw").bold()
              Span("ift").foregroundStyle(.cyan)
            }
          ),
          CanvasLabel("outside", x: 20, y: 20),
        ],
        marker: .block,
        layers: [
          CanvasLayer(
            points: [CanvasPoint(x: 5, y: 5)],
            marker: .custom("X")
          )
        ]
      ),
      size: Size(width: 10, height: 3)
    ) {
      """
      │          │
      │    Swift │
      │          │
      """
    }
    #expect(buffer.cell(at: Position(x: 4, y: 1))?.style.modifiers.contains(.bold) == true)
    #expect(buffer.cell(at: Position(x: 6, y: 1))?.style.foreground == .cyan)
  }

  @Test func canvasClipsCrossingLinesAndFillsToABaseline() {
    let clipped = assertWidget(
      Canvas(
        x: 0...10,
        y: 0...10,
        lines: [
          CanvasLine(
            from: CanvasPoint(x: -10, y: 0, style: Style(foreground: .red)),
            to: CanvasPoint(x: 5, y: 0, style: Style(foreground: .red))
          ),
          CanvasLine(
            from: CanvasPoint(x: -1, y: -1, style: Style(foreground: .cyan)),
            to: CanvasPoint(x: 11, y: 11, style: Style(foreground: .cyan))
          ),
          CanvasLine(
            from: CanvasPoint(x: -10, y: 5),
            to: CanvasPoint(x: -1, y: 5)
          ),
        ],
        marker: .dot
      ),
      size: Size(width: 10, height: 10)
    ) {
      """
      │         •│
      │        • │
      │       •  │
      │      •   │
      │     •    │
      │    •     │
      │   •      │
      │  •       │
      │ •        │
      │••••••    │
      """
    }
    #expect(clipped.cell(at: Position(x: 9, y: 0))?.style.foreground == .cyan)
    #expect(clipped.cell(at: Position(x: 5, y: 9))?.style.foreground == .red)

    assertWidget(
      Canvas(
        x: 0...10,
        y: 0...10,
        filledLines: [
          CanvasFilledLine(
            from: CanvasPoint(x: -1, y: -1),
            to: CanvasPoint(x: 11, y: 11),
            fillToY: 0
          )
        ],
        marker: .dot
      ),
      size: Size(width: 10, height: 10)
    ) {
      """
      │         •│
      │        ••│
      │       •••│
      │      ••••│
      │     •••••│
      │    ••••••│
      │   •••••••│
      │  ••••••••│
      │ •••••••••│
      │••••••••••│
      """
    }
  }

  @Test func canvasHalfBlocksAndBackgroundsPreserveIndependentColors() {
    let halfBlocks = assertWidget(
      Canvas(
        x: 0...1,
        y: 0...1,
        points: [
          CanvasPoint(x: 0, y: 1, style: Style(foreground: .red)),
          CanvasPoint(x: 0, y: 0, style: Style(foreground: .blue)),
          CanvasPoint(x: 1, y: 1, style: Style(foreground: .green)),
        ],
        marker: .halfBlock
      ),
      size: Size(width: 2, height: 1)
    ) {
      """
      │▀▀│
      """
    }
    #expect(halfBlocks.cell(at: Position(x: 0, y: 0))?.style.foreground == .red)
    #expect(halfBlocks.cell(at: Position(x: 0, y: 0))?.style.background == .blue)
    #expect(halfBlocks.cell(at: Position(x: 1, y: 0))?.style.foreground == .green)

    let layeredBlock = assertWidget(
      Canvas(
        x: 0...1,
        y: 0...1,
        points: [CanvasPoint(x: 0, y: 0.5, style: Style(foreground: .red))],
        marker: .block
      ) {
        CanvasLayer(
          points: [CanvasPoint(x: 0, y: 0.5, style: Style(foreground: .green))],
          marker: .custom("x")
        )
      },
      size: Size(width: 1, height: 1)
    ) {
      """
      │x│
      """
    }
    #expect(layeredBlock.cell(at: Position(x: 0, y: 0))?.style.foreground == .green)
    #expect(layeredBlock.cell(at: Position(x: 0, y: 0))?.style.background == .red)

    let background = assertWidget(
      Canvas(
        x: 0...1,
        y: 0...1,
        points: [CanvasPoint(x: 0, y: 0.5)],
        backgroundColor: .magenta,
        marker: .dot
      ),
      size: Size(width: 2, height: 1)
    ) {
      """
      │• │
      """
    }
    #expect(background.cell(at: Position(x: 1, y: 0))?.style.background == .magenta)
  }

  @Test func chartAreaDatasetsFillContinuousSegments() {
    assertWidget(
      Chart(
        [
          Dataset(
            points: [(0, 0), (5, 8), (10, 3)],
            marker: .dot,
            graphType: .area,
            fillToY: 0
          )
        ],
        x: 0...10,
        y: 0...10,
        legendPosition: nil
      ),
      size: Size(width: 12, height: 6)
    ) {
      """
      │            │
      │      ••    │
      │    ••••••  │
      │   •••••••••│
      │ •••••••••••│
      │••••••••••••│
      """
    }
  }

  @Test func chartGraphTypesMatchUpstreamCoreFixtures() {
    let barData: [(Double, Double)] = [
      (0, 0), (2, 1), (4, 4), (6, 8), (8, 9), (10, 10),
    ]
    assertWidget(
      Chart(
        [Dataset(points: barData, marker: .dot, graphType: .bar)],
        x: 0...10,
        y: 0...10,
        legendPosition: nil
      ),
      size: Size(width: 11, height: 11)
    ) {
      """
      │          •│
      │        • •│
      │      • • •│
      │      • • •│
      │      • • •│
      │      • • •│
      │    • • • •│
      │    • • • •│
      │    • • • •│
      │  • • • • •│
      │• • • • • •│
      """
    }

    let overlapping = assertWidget(
      Chart(
        [
          Dataset(
            points: [(0, 0), (5, 5)],
            style: Style(foreground: .blue),
            marker: .block,
            graphType: .line
          ),
          Dataset(
            points: [(0, 5), (5, 0)],
            style: Style(foreground: .red),
            marker: .dot,
            graphType: .line
          ),
        ],
        x: 0...5,
        y: 0...5,
        legendPosition: nil
      ),
      size: Size(width: 5, height: 5)
    ) {
      """
      │•   █│
      │ • █ │
      │  •  │
      │ █ • │
      │█   •│
      """
    }
    #expect(overlapping.cell(at: Position(x: 2, y: 2))?.style.foreground == .red)
    #expect(overlapping.cell(at: Position(x: 2, y: 2))?.style.background == .blue)

    assertWidget(
      Chart(
        [Dataset(points: [(0, 0), (1, 1)])],
        x: 0...1,
        y: 0...1,
        legendPosition: nil
      ),
      size: Size(width: 1, height: 1)
    ) {
      """
      │•│
      """
    }
  }

  @Test func chartBaseStyleCoversItsAreaAndDatasetsPatchIt() {
    let buffer = assertWidget(
      Chart(
        [
          Dataset(
            points: [(0.5, 0.5)],
            style: Style(foreground: .red),
            marker: .dot,
            graphType: .scatter
          )
        ],
        style: Style(background: .green),
        x: 0...1,
        y: 0...1,
        legendPosition: nil
      ),
      size: Size(width: 3, height: 3)
    ) {
      """
      │   │
      │ • │
      │   │
      """
    }
    for position in buffer.area.positions() {
      #expect(buffer.cell(at: position)?.style.background == .green)
    }
    #expect(buffer.cell(at: Position(x: 1, y: 1))?.symbol == "•")
    #expect(buffer.cell(at: Position(x: 1, y: 1))?.style.foreground == .red)
  }

  @Test func chartRendersAxesScatterDataAndLegend() {
    var buffer = Buffer(area: Rect(x: 0, y: 0, width: 20, height: 8))
    Chart(
      [
        Dataset(
          "scatter",
          points: [(0, 0), (10, 10)],
          marker: .custom("*"),
          graphType: .scatter
        )
      ],
      xAxis: ChartAxis(title: "X", bounds: 0...10, labels: ["0", "10"]),
      yAxis: ChartAxis(title: "Y", bounds: 0...10, labels: ["0", "10"])
    ).render(in: buffer.area, into: &buffer)

    #expect(buffer.cell(at: Position(x: 2, y: 3))?.symbol == "│")
    #expect(buffer.cell(at: Position(x: 2, y: 6))?.symbol == "└")
    #expect(buffer.cell(at: Position(x: 3, y: 5))?.symbol == "*")
    assertTerminal(buffer) {
      """
      │10│Y               *│
      │  │                 │
      │  │                 │
      │  │                 │
      │  │                 │
      │0 │*               X│
      │  └─────────────────│
      │  0               10│
      """
    }
  }

  @Test func chartLegendUsesUpstreamBordersConstraintsAndAllPositions() {
    let named = [Dataset("Data", points: [])]
    assertWidget(
      VStack {
        HStack {
          Chart(named, legendPosition: .topLeading, legendConstraints: .always)
          Chart(named, legendPosition: .top, legendConstraints: .always)
          Chart(named, legendPosition: .topTrailing, legendConstraints: .always)
        }.frame(.length(3))
        HStack {
          Chart(named, legendPosition: .bottomLeading, legendConstraints: .always)
          Chart(named, legendPosition: .bottom, legendConstraints: .always)
          Chart(named, legendPosition: .bottomTrailing, legendConstraints: .always)
        }.frame(.length(3))
      },
      size: Size(width: 30, height: 6)
    ) {
      """
      │┌────┐      ┌────┐      ┌────┐│
      ││Data│      │Data│      │Data││
      │└────┘      └────┘      └────┘│
      │┌────┐      ┌────┐      ┌────┐│
      ││Data│      │Data│      │Data││
      │└────┘      └────┘      └────┘│
      """
    }

    var hidden = Buffer(area: Rect(x: 0, y: 0, width: 20, height: 8))
    Chart(
      [Dataset("Dataset #0", points: [(0, 0)])],
      legendConstraints: ChartLegendConstraints(
        width: .ratio(numerator: 1, denominator: 10),
        height: .ratio(numerator: 1, denominator: 4)
      )
    ).render(in: hidden.area, into: &hidden)
    #expect(hidden.lines().joined().contains("Dataset") == false)
  }

  @Test func chartTitlesAndLegendsAvoidEachOtherLikeUpstream() {
    assertWidget(
      Chart(
        [Dataset("Ds1", points: [])],
        yAxis: ChartAxis(title: "The title overlap a legend."),
        legendConstraints: .always
      ),
      size: Size(width: 30, height: 20)
    ) {
      """
      │The title overlap a legend.   │
      │                         ┌───┐│
      │                         │Ds1││
      │                         └───┘│
      │                              │
      │                              │
      │                              │
      │                              │
      │                              │
      │                              │
      │                              │
      │                              │
      │                              │
      │                              │
      │                              │
      │                              │
      │                              │
      │                              │
      │                              │
      │                              │
      """
    }

    assertWidget(
      Chart(
        [Dataset("Ds1", points: [])],
        xAxis: ChartAxis(title: "xxxxxxxxxxxxxxxx"),
        yAxis: ChartAxis(title: "xxxxxxxxxxxxxxxx")
      ),
      size: Size(width: 8, height: 4)
    ) {
      """
      │        │
      │        │
      │        │
      │        │
      """
    }

    for position in [
      ChartLegendPosition.topLeading, .top, .topTrailing, .leading, .trailing, .bottom,
      .bottomLeading, .bottomTrailing,
    ] {
      assertWidget(
        Chart(
          [Dataset("Data", points: [])],
          legendPosition: position,
          legendConstraints: .always
        ),
        size: Size(width: 6, height: 3)
      ) {
        """
        │┌────┐│
        ││Data││
        │└────┘│
        """
      }
    }
  }

  @Test func chartSupportsRichAlignedAxisAndLegendLines() {
    let styledName = Line(alignment: .trailing) {
      Span("Short").foregroundStyle(.cyan)
    }
    let buffer = assertWidget(
      Chart(
        [
          Dataset("Very long name", points: []),
          Dataset(points: []),
          Dataset("", points: []),
          Dataset(name: styledName, points: []),
        ],
        xAxis: ChartAxis(
          title: Line { Span("X axis").bold() },
          labels: [Line("start"), Line("end")],
          labelsAlignment: .center
        ),
        legendConstraints: .always
      ),
      size: Size(width: 20, height: 8)
    ) {
      """
      │    ┌──────────────┐│
      │    │Very long name││
      │    │              ││
      │    │         Short││
      │    └──────────────┘│
      │              X axis│
      │  ──────────────────│
      │ start           end│
      """
    }
    #expect(buffer.cell(at: Position(x: 18, y: 3))?.style.foreground == .cyan)
    #expect(buffer.cell(at: Position(x: 15, y: 5))?.style.modifiers.contains(.bold) == true)
  }

  @Test func paragraphSupportsTrimPolicyAndHorizontalScrolling() {
    var trimmed = Buffer(area: Rect(x: 0, y: 0, width: 4, height: 2))
    Paragraph("one  two", wrap: .word, trimLeadingWhitespace: true)
      .render(in: trimmed.area, into: &trimmed)
    assertTerminal(trimmed) {
      """
      │one │
      │two │
      """
    }

    var preserved = Buffer(area: Rect(x: 0, y: 0, width: 4, height: 2))
    Paragraph("one  two", wrap: .word, trimLeadingWhitespace: false)
      .render(in: preserved.area, into: &preserved)
    assertTerminal(preserved) {
      """
      │one │
      │two │
      """
    }

    var scrolled = Buffer(area: Rect(x: 0, y: 0, width: 3, height: 1))
    Paragraph("abcdef", wrap: .none, horizontalScroll: 2)
      .render(in: scrolled.area, into: &scrolled)
    assertTerminal(scrolled) {
      """
      │cde│
      """
    }
  }

  @Test func lineGaugeAndDirectionalSparklineRenderDeterministically() {
    var gauge = Buffer(area: Rect(x: 0, y: 0, width: 12, height: 1))
    LineGauge(ratio: 0.5, label: "50%")
      .render(in: gauge.area, into: &gauge)
    assertTerminal(gauge) {
      """
      │50% ━━━━────│
      """
    }

    var sparkline = Buffer(area: Rect(x: 0, y: 0, width: 3, height: 1))
    Sparkline(
      [0, nil, 1] as [Double?],
      bounds: 0...1,
      direction: .rightToLeft,
      absentValueSymbol: "░"
    ).render(in: sparkline.area, into: &sparkline)
    assertTerminal(sparkline) {
      """
      │█░ │
      """
    }

    var tall = Buffer(area: Rect(x: 0, y: 0, width: 1, height: 2))
    Sparkline([1], bounds: 0...1).render(in: tall.area, into: &tall)
    assertTerminal(tall) {
      """
      │█│
      │█│
      """
    }
  }

  @Test func blockShadowIsClippedAndDoesNotLeakIntoContent() {
    var buffer = Buffer(area: Rect(x: 0, y: 0, width: 8, height: 4))
    Block(borders: .plain, shadow: .mediumShade()) {
      Text("")
    }.render(in: Rect(x: 0, y: 0, width: 5, height: 3), into: &buffer)

    assertTerminal(buffer) {
      """
      │┌───┐   │
      ││   │▒  │
      │└───┘▒  │
      │ ▒▒▒▒▒  │
      """
    }
  }
}
