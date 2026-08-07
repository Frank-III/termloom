import Foundation
import Testing

@testable import Ratatui

@Suite struct InputParserTests {
  @Test func parsesTextControlAndArrowKeys() {
    var parser = InputParser()

    let events = parser.feed(Data("aA\u{03}\u{1B}[A".utf8))

    #expect(
      events == [
        .key(KeyEvent(.character("a"))),
        .key(KeyEvent(.character("A"), modifiers: [.shift])),
        .key(KeyEvent(.character("c"), modifiers: [.control])),
        .key(KeyEvent(.up)),
      ]
    )
  }

  @Test func parsesTabAndOptionBackspaceControlInput() {
    var parser = InputParser()
    #expect(
      parser.feed(Data([0x09, 0x1B, 0x7F]))
        == [
          .key(KeyEvent(.tab)),
          .key(KeyEvent(.backspace, modifiers: [.option])),
        ])
  }

  @Test func retainsFragmentedEscapeSequences() {
    var parser = InputParser()

    #expect(parser.feed(Data([0x1B])) == [])
    #expect(parser.feed(Data([0x5B])) == [])
    #expect(parser.feed(Data([0x31, 0x3B])) == [])
    #expect(
      parser.feed(Data([0x35, 0x43]))
        == [.key(KeyEvent(.right, modifiers: [.control]))]
    )
  }

  @Test func flushesStandaloneEscapeAfterTimeout() {
    var parser = InputParser()

    #expect(parser.feed(Data([0x1B])) == [])
    #expect(parser.flushEscape() == .key(KeyEvent(.escape)))
    #expect(parser.flushEscape() == nil)
  }

  @Test func bracketedPasteCanArriveInMultipleChunks() {
    var parser = InputParser()

    #expect(parser.feed(Data("\u{1B}[200~hello".utf8)) == [])
    #expect(
      parser.feed(Data("\nworld\u{1B}[201~".utf8))
        == [.paste("hello\nworld")]
    )
  }

  @Test func parsesUnicodeAndModifiedNavigation() {
    var parser = InputParser()

    #expect(
      parser.feed(Data("界\u{1B}[1;4D\u{1B}[Z".utf8))
        == [
          .key(KeyEvent(.character("界"))),
          .key(KeyEvent(.left, modifiers: [.shift, .option])),
          .key(KeyEvent(.tab, modifiers: [.shift])),
        ]
    )
  }

  @Test func parsesSGRMouseEvents() {
    var parser = InputParser()

    #expect(
      parser.feed(Data("\u{1B}[<0;12;4M\u{1B}[<0;12;4m\u{1B}[<65;2;3M".utf8))
        == [
          .mouse(MouseEvent(.down(.left), at: Position(x: 11, y: 3))),
          .mouse(MouseEvent(.up(.left), at: Position(x: 11, y: 3))),
          .mouse(MouseEvent(.scrollDown, at: Position(x: 1, y: 2))),
        ]
    )
  }

  @Test func parsesTerminalFocusReports() {
    var parser = InputParser()

    #expect(
      parser.feed(Data("\u{1B}[I\u{1B}[O".utf8))
        == [.terminalFocus(true), .terminalFocus(false)]
    )
  }

  @Test func parsesKittyKeyboardEventsWithoutLeakingProtocolDetails() {
    var parser = InputParser()

    #expect(
      parser.feed(Data("\u{1B}[97;6:2;65u\u{1B}[57352;9:3u\u{1B}[57376u".utf8))
        == [
          .key(
            KeyEvent(
              .character("a"),
              modifiers: [.shift, .control],
              kind: .repeat,
              text: "A"
            )
          ),
          .key(KeyEvent(.up, modifiers: [.command], kind: .release)),
          .key(KeyEvent(.function(13))),
        ]
    )
  }

  @Test func parsesKittyLocksKeypadMediaAndHighFunctionKeys() {
    var parser = InputParser()

    #expect(
      parser.feed(
        Data(
          "\u{1B}[57358u\u{1B}[57363u\u{1B}[57398u\u{1B}[57406u\u{1B}[57427u\u{1B}[57430u\u{1B}[57440u"
            .utf8
        )
      )
        == [
          .key(KeyEvent(.capsLock)),
          .key(KeyEvent(.menu)),
          .key(KeyEvent(.function(35))),
          .key(KeyEvent(.keypad(.digit(7)))),
          .key(KeyEvent(.keypad(.begin))),
          .key(KeyEvent(.media(.playPause))),
          .key(KeyEvent(.media(.mute))),
        ]
    )
  }

  @Test func parsesKittyKeyboardCapabilityResponses() {
    var parser = InputParser()
    #expect(parser.feed(Data("\u{1B}[?".utf8)) == [])
    #expect(
      parser.feed(Data("27u".utf8))
        == [
          .keyboardEnhancementFlags([
            .disambiguateEscapeCodes,
            .reportEventKinds,
            .reportAllKeys,
            .reportAssociatedText,
          ])
        ]
    )
  }

  @Test func parsesDeviceCursorAndTerminalModeReports() {
    var parser = InputParser()
    #expect(parser.feed(Data("\u{1B}[?1;2".utf8)) == [])
    #expect(
      parser.feed(
        Data(
          "c\u{1B}[>0;95;0c\u{1B}[12;34R\u{1B}[?2026;1$y\u{1B}[4;2$y".utf8
        )
      )
        == [
          .deviceAttributes(TerminalDeviceAttributes(.primary, parameters: [1, 2])),
          .deviceAttributes(TerminalDeviceAttributes(.secondary, parameters: [0, 95, 0])),
          .cursorPositionReport(Position(x: 33, y: 11)),
          .terminalModeReport(
            TerminalModeReport(mode: 2026, status: .set, isPrivate: true)
          ),
          .terminalModeReport(
            TerminalModeReport(mode: 4, status: .reset, isPrivate: false)
          ),
        ]
    )
  }
}
