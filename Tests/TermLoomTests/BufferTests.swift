import CustomDump
import Foundation
import TermLoomTestSupport
import Testing

@testable import TermLoom

@Suite struct BufferTests {
  @Test func completeCellReplacementPreservesRowMajorContents() {
    var buffer = Buffer(area: Rect(x: 3, y: 4, width: 2, height: 2))
    let cells = ["a", "b", "c", "d"].map { Cell(symbol: $0) }

    buffer.replaceCells(cells)

    #expect(buffer[Position(x: 3, y: 4)].symbol == "a")
    #expect(buffer[Position(x: 4, y: 4)].symbol == "b")
    #expect(buffer[Position(x: 3, y: 5)].symbol == "c")
    #expect(buffer[Position(x: 4, y: 5)].symbol == "d")
  }

  @Test func wideCharactersOccupyTwoCells() {
    var buffer = Buffer(area: Rect(x: 0, y: 0, width: 5, height: 1))

    buffer.setString("A界B", at: Position(x: 0, y: 0))

    assertTerminal(buffer) {
      """
      │A界B │
      """
    }
    #expect(buffer.cell(at: Position(x: 2, y: 0))?.isContinuation == true)
  }

  @Test func diffOnlyReturnsChangedCells() {
    let before = Buffer(area: Rect(x: 0, y: 0, width: 4, height: 1))
    var after = before
    after.setString("Hi", at: Position(x: 1, y: 0))

    expectNoDifference(
      after.diff(from: before).map(\.position),
      [Position(x: 1, y: 0), Position(x: 2, y: 0)]
    )
  }

  @Test func overwritingWideCharactersClearsTheirContinuation() {
    var buffer = Buffer(area: Rect(x: 0, y: 0, width: 4, height: 1))
    buffer.setString("界", at: Position(x: 0, y: 0))

    buffer.setString("A", at: Position(x: 0, y: 0))

    assertTerminal(buffer) {
      """
      │A   │
      """
    }
    #expect(buffer.cell(at: Position(x: 1, y: 0)) == .empty)
  }

  @Test func overwritingAContinuationClearsTheWholeWideCharacter() {
    var buffer = Buffer(area: Rect(x: 0, y: 0, width: 4, height: 1))
    buffer.setString("界", at: Position(x: 0, y: 0))

    buffer.setString("A", at: Position(x: 1, y: 0))

    assertTerminal(buffer) {
      """
      │ A  │
      """
    }
  }

  @Test func fillingAcrossAContinuationPreservesBufferInvariants() {
    var buffer = Buffer(area: Rect(x: 0, y: 0, width: 4, height: 1))
    buffer.setString("界", at: Position(x: 0, y: 0))

    buffer.fill(
      Rect(x: 1, y: 0, width: 1, height: 1),
      with: Cell(symbol: "X")
    )

    assertTerminal(buffer) {
      """
      │ X  │
      """
    }
    #expect(buffer.cell(at: Position(x: 0, y: 0)) == .empty)
  }

  @Test func borderSymbolsMergeWithoutOverwritingApplicationContent() {
    var buffer = Buffer(area: Rect(x: 0, y: 0, width: 3, height: 1))
    buffer.setString("│x┃", at: Position(x: 0, y: 0))

    buffer.mergeSymbol("─", at: Position(x: 0, y: 0), strategy: .exact)
    buffer.mergeSymbol("─", at: Position(x: 1, y: 0), strategy: .exact)
    buffer.mergeSymbol("━", at: Position(x: 2, y: 0), strategy: .fuzzy)

    assertTerminal(buffer) {
      """
      │┼x╋│
      """
    }
  }

  @Test func terminalWidthCoversComposedUnicodeFamilies() {
    #expect(TerminalWidth.of("a") == 1)
    #expect(TerminalWidth.of("e\u{301}") == 1)
    #expect(TerminalWidth.of("\u{301}") == 0)
    #expect(TerminalWidth.of("界") == 2)
    #expect(TerminalWidth.of("👨‍👩‍👧‍👦") == 2)
    #expect(TerminalWidth.of("🇺🇸") == 2)
    #expect(TerminalWidth.of("1️⃣") == 2)
    #expect(TerminalWidth.of("©") == 1)
    #expect(TerminalWidth.of("©️") == 2)
    #expect(TerminalWidth.of("\u{7}") == 0)
  }

  @Test func terminalWidthMatchesUpstreamHalfwidthSoundMarkRules() {
    #expect(TerminalWidth.of("ﾞ") == 1)
    #expect(TerminalWidth.of("ﾟ") == 1)
    #expect(TerminalWidth.of("ｶﾞ") == 2)
    #expect(TerminalWidth.of("ﾊﾟ") == 2)
    #expect(TerminalWidth.of("aﾞ") == 2)
    #expect(TerminalWidth.of("1ﾟ") == 2)
    #expect(TerminalWidth.of("あﾞ") == 3)
    #expect(TerminalWidth.of("紅ﾞ") == 3)
    #expect(TerminalWidth.of("ｶ\u{3099}") == 1)
    #expect(TerminalWidth.of("ガ") == 2)
    #expect(TerminalWidth.of("aｶﾞb") == 4)
    #expect(TerminalWidth.of("あｶﾞ") == 4)
  }

  @Test func generatedUnicode17TablesExposeAnExplicitCJKPolicy() {
    #expect(TerminalWidth.unicodeVersion == (17, 0, 0))
    #expect(TerminalWidth.of("·") == 1)
    #expect(TerminalWidth.of("·", policy: .cjk) == 2)
    #expect(TerminalWidth.of("·") == 1)
    #expect(TerminalWidth.of("·", policy: .cjk) == 2)
    #expect(TerminalWidth.of("¨", policy: .cjk) == 1)
    #expect(TerminalWidth.of("ˉ", policy: .cjk) == 1)
    #expect(TerminalWidth.of("ᅠ") == 0)
    #expect(TerminalWidth.of("ㅤ") == 0)
    #expect(TerminalWidth.of("ﾠ") == 0)
    #expect(TerminalWidth.of("가") == 2)
    #expect(TerminalWidth.of("A·界", policy: .standard) == 4)
    #expect(TerminalWidth.of("A·界", policy: .cjk) == 5)
  }

  @Test func contextualWidthsMatchUnicodeWidthSequenceRules() {
    let widths: [(String, Int, Int)] = [
      ("#\u{FE0F}", 2, 2),
      ("*\u{301}\u{FE0F}", 1, 1),
      ("♈\u{FE0E}", 1, 2),
      ("♈\u{FE0F}", 2, 2),
      ("‘\u{FE01}", 2, 1),
      ("لا", 1, 1),
      ("ل\u{065F}\u{065E}أ", 1, 1),
      ("א\u{200D}ל", 1, 1),
      ("ꓹꓼ", 1, 1),
      ("𐰲\u{200D}𐰃", 1, 1),
      ("ⵏ⵿ⴾ", 1, 1),
      ("ᨕᨗ\u{200D}ᨐ", 1, 1),
      ("ល្ង", 1, 1),
      ("🇵🇸\u{200D}🕊️\u{200D}🇮🇱", 2, 2),
      ("🇮🇱\u{200D}🕊️\u{200D}\u{200D}🇵🇸", 4, 4),
      ("👪\u{200D}\u{200D}🏿", 4, 4),
      ("*\u{FE0F}\u{200D}👪", 2, 2),
      ("*\u{20E3}\u{FE0F}\u{200D}👪", 3, 3),
      ("*\u{FE0F}\u{FE0F}\u{20E3}\u{200D}👪", 4, 4),
      (
        "🏴\u{E0067}\u{E0062}\u{E0077}\u{E006C}\u{E0073}\u{E007F}\u{200D}Ⓜ️",
        2,
        2
      ),
      ("🏴\u{E0031}\u{E007F}\u{200D}Ⓜ️", 4, 4),
      ("🏴\u{E0031}\u{E0031}\u{E0031}\u{E007F}\u{200D}Ⓜ️", 2, 2),
      ("🇦🇦\u{200D}🇦🇦", 2, 2),
      ("🇦🇦\u{200D}🇦🇦🇦", 3, 3),
      ("🇦🇦\u{200D}\u{200D}🇦🇦", 4, 4),
      ("🇦🇦\u{200D}🇦\u{200D}🇦🇦", 5, 5),
      ("🇦🇦\u{200D}🇦🇦\u{200D}🇦🇦", 2, 2),
      ("🇦🇦\u{200D}🇦🇦🇦🇦\u{200D}🇦🇦", 4, 4),
      ("=\u{0338}", 1, 2),
      ("=\u{0301}\u{0338}", 1, 2),
      ("\u{16D63}\u{16D67}", 1, 1),
      ("\u{16D63}\u{16D68}", 1, 1),
    ]
    for (value, standard, cjk) in widths {
      #expect(TerminalWidth.of(value) == standard, "standard width of \(value.debugDescription)")
      #expect(
        TerminalWidth.of(value, policy: .cjk) == cjk,
        "CJK width of \(value.debugDescription)"
      )
    }
  }

  @Test func scalarSpecialCasesMatchUnicodeWidth() {
    #expect(TerminalWidth.of("\u{115F}") == 2)
    #expect(TerminalWidth.of("\u{17A4}") == 2)
    #expect(TerminalWidth.of("\u{17D8}") == 3)
    #expect(TerminalWidth.of("\u{2D7F}") == 1)
  }

  @Test func allUnicode17QualifiedEmojiOccupyTwoCells() throws {
    let fixture = try #require(Bundle.module.url(forResource: "emoji-test", withExtension: "txt"))
    let contents = try String(contentsOf: fixture, encoding: .utf8)
    var checked = 0
    var failures: [String] = []
    for line in contents.split(separator: "\n") where !line.hasPrefix("#") {
      let fields = line.split(separator: ";", maxSplits: 1)
      guard fields.count == 2 else { continue }
      let status = fields[1].trimmingCharacters(in: .whitespaces)
      guard status.hasPrefix("fully-qualified") || status.hasPrefix("component") else { continue }
      let scalars = fields[0].split(separator: " ").compactMap {
        UInt32($0, radix: 16).flatMap(UnicodeScalar.init)
      }
      let emoji = String(String.UnicodeScalarView(scalars))
      checked += 1
      let standard = TerminalWidth.of(emoji)
      let cjk = TerminalWidth.of(emoji, policy: .cjk)
      if standard != 2 || cjk != 2 {
        failures.append("\(fields[0]): standard=\(standard), cjk=\(cjk)")
      }
    }
    #expect(checked == 3_953)
    expectNoDifference(failures, [])
  }

  @Test func zeroWidthMarksComposeIntoThePreviousCell() {
    var buffer = Buffer(area: Rect(x: 0, y: 0, width: 4, height: 1))
    var cursor = buffer.setString("e", at: Position(x: 0, y: 0))
    cursor = buffer.setString("\u{301}", at: cursor)
    cursor = buffer.setString("界", at: cursor)
    _ = buffer.setString("\u{301}", at: cursor)

    #expect(cursor == Position(x: 3, y: 0))
    #expect(buffer.cell(at: Position(x: 0, y: 0))?.symbol == "e\u{301}")
    #expect(buffer.cell(at: Position(x: 1, y: 0))?.symbol == "界\u{301}")
    #expect(buffer.cell(at: Position(x: 2, y: 0))?.isContinuation == true)
  }

  @Test func emojiSequencesRenderAsSingleWideGraphemes() {
    for emoji in ["🤷", "🐻‍❄️", "👁️‍🗨️", "⌨️"] {
      var buffer = Buffer(
        area: Rect(x: 0, y: 0, width: 7, height: 1),
        repeating: Cell(symbol: "x")
      )
      buffer.setString(emoji, at: Position(x: 0, y: 0))
      #expect(buffer.lines() == [emoji + "xxxxx"])
      #expect(buffer.cell(at: Position(x: 0, y: 0))?.width == 2)
      #expect(buffer.cell(at: Position(x: 1, y: 0))?.isContinuation == true)
    }
  }

  @Test func diffExplicitlyClearsChangedVS16TrailingCells() {
    var previous = Buffer(area: Rect(x: 0, y: 0, width: 2, height: 1))
    previous.setString("ab", at: Position(x: 0, y: 0))
    var next = Buffer(area: previous.area)
    next.setString("⌨️", at: Position(x: 0, y: 0))

    let updates = next.diff(from: previous)
    expectNoDifference(updates.map(\.position), [Position(x: 0, y: 0), Position(x: 1, y: 0)])
    #expect(updates[0].cell.symbol == "⌨️")
    #expect(updates[1].cell == .empty)
  }

  @Test func diffIgnoresInvisibleStyleChangesInWideTrailingCells() {
    var previous = Buffer(area: Rect(x: 0, y: 0, width: 3, height: 1))
    previous.setString("⚠️x", at: Position(x: 0, y: 0), style: Style(foreground: .lightBlue))
    var next = previous
    next.setStyle(Style(foreground: .reset), in: Rect(x: 0, y: 0, width: 2, height: 1))

    let updates = next.diff(from: previous)
    expectNoDifference(updates.map(\.position), [Position(x: 0, y: 0)])
  }

  @Test func regionStylesResizeAndMergeRemainCoordinateAware() {
    var styled = Buffer(
      area: Rect(x: 0, y: 0, width: 3, height: 1),
      repeating: Cell(symbol: "x", style: Style(foreground: .red))
    )
    styled.setStyle(
      Style(background: .blue, modifiers: [.bold]), in: Rect(x: 1, y: 0, width: 2, height: 1))
    #expect(styled.cell(at: Position(x: 0, y: 0))?.style.background == nil)
    #expect(styled.cell(at: Position(x: 1, y: 0))?.style.foreground == .red)
    #expect(styled.cell(at: Position(x: 1, y: 0))?.style.background == .blue)
    #expect(styled.cell(at: Position(x: 1, y: 0))?.style.modifiers.contains(.bold) == true)
    assertTerminal(styled) {
      """
      │xxx│
      """
    }

    var resized = Buffer(area: Rect(x: 0, y: 0, width: 2, height: 2))
    resized.setString("ab", at: Position(x: 0, y: 0))
    resized.setString("cd", at: Position(x: 0, y: 1))
    resized.resize(to: Rect(x: 0, y: 0, width: 4, height: 1))
    assertTerminal(resized) {
      """
      │abcd│
      """
    }
    resized.resize(to: Rect(x: 0, y: 0, width: 2, height: 1))
    assertTerminal(resized) {
      """
      │ab│
      """
    }

    var base = Buffer(area: Rect(x: 1, y: 2, width: 2, height: 1))
    base.setString("AB", at: Position(x: 1, y: 2))
    var overlay = Buffer(area: Rect(x: 2, y: 2, width: 2, height: 1))
    overlay.setString("xy", at: Position(x: 2, y: 2))
    base.merge(overlay)
    #expect(base.area == Rect(x: 1, y: 2, width: 3, height: 1))
    assertTerminal(base) {
      """
      │Axy│
      """
    }
  }
}
