import Ratatui

public struct TextArea: Widget, StatefulWidget {
  public typealias State = TextAreaState

  public var value: TextAreaState
  public var id: ControlID
  public var placeholder: String
  public var showsLineNumbers: Bool
  public var style: Style
  public var focusedStyle: Style
  public var selectionStyle: Style
  public var lineNumberStyle: Style
  public var cursorShape: CursorStyle

  public init(
    _ value: TextAreaState = TextAreaState(),
    id: ControlID,
    placeholder: String = "",
    showsLineNumbers: Bool = false,
    style: Style = .plain,
    focusedStyle: Style = Style(modifiers: [.underlined]),
    selectionStyle: Style = Style(modifiers: [.reversed]),
    lineNumberStyle: Style = Style(modifiers: [.dim]),
    cursorShape: CursorStyle = .steadyBar
  ) {
    self.value = value
    self.id = id
    self.placeholder = placeholder
    self.showsLineNumbers = showsLineNumbers
    self.style = style
    self.focusedStyle = focusedStyle
    self.selectionStyle = selectionStyle
    self.lineNumberStyle = lineNumberStyle
    self.cursorShape = cursorShape
  }

  public func render(in area: Rect, into frame: inout Frame) {
    var state = value
    render(in: area, into: &frame, state: &state)
  }

  public func render(in area: Rect, into frame: inout Frame, state: inout TextAreaState) {
    guard !area.isEmpty else { return }
    let focused = frame.environment.focusedControl == id
    let activeStyle = focused ? style.patching(focusedStyle) : style
    frame.buffer.fill(area, with: Cell(symbol: " ", style: activeStyle))
    frame.addInteraction(InteractionRegion(control: id, area: area))

    let gutter = gutterWidth(for: state)
    state.ensureCursorVisible(viewport: area.size, gutterWidth: gutter)

    if state.lines.count == 1, state.lines[0].isEmpty, !placeholder.isEmpty {
      frame.buffer.setString(
        placeholder,
        at: Position(x: area.x + UInt16(clamping: gutter), y: area.y),
        style: activeStyle.adding(.dim),
        maxWidth: UInt16(clamping: max(0, Int(area.width) - gutter)))
    } else {
      let visibleRows =
        state
        .verticalOffset..<min(
          state.lines.count, state.verticalOffset + Int(area.height))
      for sourceRow in visibleRows {
        let targetY = Int(area.y) + sourceRow - state.verticalOffset
        if showsLineNumbers {
          let number = String(sourceRow + 1)
          let label = String(repeating: " ", count: max(0, gutter - 1 - number.count)) + number
          frame.buffer.setString(
            label + " ",
            at: Position(x: area.x, y: UInt16(clamping: targetY)),
            style: lineNumberStyle,
            maxWidth: UInt16(clamping: gutter))
        }
        renderLine(
          state.lines[sourceRow],
          sourceRow: sourceRow,
          at: Position(
            x: area.x + UInt16(clamping: gutter),
            y: UInt16(clamping: targetY)),
          width: max(0, Int(area.width) - gutter),
          horizontalOffset: state.horizontalOffset,
          selection: state.selectedRange,
          style: activeStyle,
          into: &frame.buffer)
      }
    }

    if focused {
      frame.placeCursor(at: cursorPosition(in: area, state: state), style: cursorShape)
    }
  }

  private func cursorPosition(in area: Rect, state: TextAreaState) -> Position? {
    var state = state
    let gutter = gutterWidth(for: state)
    state.ensureCursorVisible(viewport: area.size, gutterWidth: gutter)
    let row = state.cursor.row - state.verticalOffset
    guard row >= 0, row < Int(area.height) else { return nil }
    let prefix = String(state.lines[state.cursor.row].prefix(state.cursor.column))
    let column = TerminalWidth.of(prefix) - state.horizontalOffset
    return Position(
      x: UInt16(
        clamping: Int(area.x) + gutter
          + min(max(0, column), max(0, Int(area.width) - gutter - 1))),
      y: UInt16(clamping: Int(area.y) + row))
  }

  private func gutterWidth(for state: TextAreaState) -> Int {
    showsLineNumbers ? String(max(1, state.lines.count)).count + 1 : 0
  }

  private func renderLine(
    _ line: String,
    sourceRow: Int,
    at origin: Position,
    width: Int,
    horizontalOffset: Int,
    selection: (lower: TextPosition, upper: TextPosition)?,
    style: Style,
    into buffer: inout Buffer
  ) {
    guard width > 0 else { return }
    var sourceColumn = 0
    var targetColumn = 0
    for (characterIndex, character) in line.enumerated() {
      let characterWidth = TerminalWidth.of(character)
      defer { sourceColumn += characterWidth }
      guard sourceColumn + characterWidth > horizontalOffset else { continue }
      guard targetColumn + characterWidth <= width else { break }
      let position = TextPosition(row: sourceRow, column: characterIndex)
      let selected = selection.map { position >= $0.lower && position < $0.upper } ?? false
      buffer.setString(
        String(character),
        at: Position(x: origin.x + UInt16(clamping: targetColumn), y: origin.y),
        style: selected ? style.patching(selectionStyle) : style,
        maxWidth: UInt16(clamping: width - targetColumn))
      targetColumn += characterWidth
    }
  }
}
