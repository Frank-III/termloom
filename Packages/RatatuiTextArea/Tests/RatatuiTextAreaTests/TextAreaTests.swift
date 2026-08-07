import Ratatui
import Testing

@testable import RatatuiTextArea

@Suite struct TextAreaTests {
  @Test func editingSplitsAndMergesLinesWithoutBreakingGraphemes() {
    var state = TextAreaState(text: "hello🌍\nworld")
    state.cursor = TextPosition(row: 0, column: 6)

    let handledEnter = state.handle(.key(KeyEvent(.enter)))
    #expect(handledEnter)
    #expect(state.lines == ["hello🌍", "", "world"])
    #expect(state.cursor == TextPosition(row: 1, column: 0))
    let handledBackspace = state.handle(.key(KeyEvent(.backspace)))
    #expect(handledBackspace)
    #expect(state.lines == ["hello🌍", "world"])
    #expect(state.cursor == TextPosition(row: 0, column: 6))
  }

  @Test func pasteSelectionUndoAndRedoAreValueSemantic() {
    var state = TextAreaState(text: "one\ntwo\nthree")
    state.selectionAnchor = TextPosition(row: 0, column: 1)
    state.cursor = TextPosition(row: 2, column: 2)
    #expect(state.selectedText == "ne\ntwo\nth")

    let handledPaste = state.handle(.paste("X\nY"))
    #expect(handledPaste)
    #expect(state.text == "oX\nYree")
    let undone = state.undo()
    #expect(undone)
    #expect(state.text == "one\ntwo\nthree")
    let redone = state.redo()
    #expect(redone)
    #expect(state.text == "oX\nYree")
  }

  @Test func shiftedMovementSelectsAndOrdinaryMovementClearsSelection() {
    var state = TextAreaState(text: "abc\ndef", cursor: TextPosition(row: 0, column: 1))

    let handledRight = state.handle(.key(KeyEvent(.right, modifiers: [.shift])))
    #expect(handledRight)
    #expect(state.selectedText == "b")
    let handledDown = state.handle(.key(KeyEvent(.down, modifiers: [.shift])))
    #expect(handledDown)
    #expect(state.selectedText == "bc\nde")
    let handledLeft = state.handle(.key(KeyEvent(.left)))
    #expect(handledLeft)
    #expect(state.selectedRange == nil)
  }

  @Test func shellAndWordBindingsMatchTheSingleLineFieldConventions() {
    var state = TextAreaState(text: "alpha beta gamma", cursor: TextPosition(row: 0, column: 11))

    let deletedWord = state.handle(.key(KeyEvent(.character("w"), modifiers: [.control])))
    #expect(deletedWord)
    #expect(state.text == "alpha gamma")
    let clearedPrefix = state.handle(.key(KeyEvent(.character("u"), modifiers: [.control])))
    #expect(clearedPrefix)
    #expect(state.text == "gamma")
    let clearedSuffix = state.handle(.key(KeyEvent(.character("k"), modifiers: [.control])))
    #expect(clearedSuffix)
    #expect(state.text.isEmpty)
  }

  @Test func lineNumbersAreRightAligned() {
    var state = TextAreaState(text: (1...12).map { "row \($0)" }.joined(separator: "\n"))
    state.cursor = TextPosition(row: 0, column: 0)
    let widget = TextArea(state, id: "editor", showsLineNumbers: true)
    let area = Rect(x: 0, y: 0, width: 12, height: 12)
    var buffer = Buffer(area: area)

    widget.render(in: area, into: &buffer, state: &state)

    #expect(line(in: buffer, row: 0).hasPrefix(" 1 "))
    #expect(line(in: buffer, row: 9).hasPrefix("10 "))
  }

  @Test func renderingReconcilesViewportLineNumbersSelectionAndCursor() {
    var state = TextAreaState(
      text: (1...20).map { "row \($0) 界" }.joined(separator: "\n"),
      cursor: TextPosition(row: 19, column: 8))
    state.selectionAnchor = TextPosition(row: 18, column: 0)
    let widget = TextArea(state, id: "editor", showsLineNumbers: true)
    let area = Rect(x: 0, y: 0, width: 16, height: 4)
    var frame = Frame(
      buffer: Buffer(area: area),
      environment: RenderEnvironment(focusedControl: "editor"))

    frame.render(widget, in: area, state: &state)

    #expect(state.verticalOffset == 16)
    #expect(line(in: frame.buffer, row: 3).contains("20"))
    #expect(frame.cursorPosition?.y == 3)
    #expect(frame.cursorStyle == .steadyBar)
  }

  private func line(in buffer: Buffer, row: Int) -> String {
    (buffer.area.x..<buffer.area.right).map { x in
      buffer[Position(x: x, y: row)].symbol
    }.joined()
  }
}
