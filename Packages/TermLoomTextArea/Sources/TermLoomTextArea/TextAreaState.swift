import TermLoom

public struct TextPosition: Hashable, Sendable, Comparable {
  public var row: Int
  public var column: Int

  public init(row: Int, column: Int) {
    self.row = max(0, row)
    self.column = max(0, column)
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.row == rhs.row ? lhs.column < rhs.column : lhs.row < rhs.row
  }
}

public struct TextAreaState: Hashable, Sendable {
  private struct Snapshot: Hashable, Sendable {
    var lines: [String]
    var cursor: TextPosition
    var selectionAnchor: TextPosition?
  }

  public private(set) var lines: [String]
  public var cursor: TextPosition
  public var selectionAnchor: TextPosition?
  public var verticalOffset: Int
  public var horizontalOffset: Int
  public var maximumHistory: Int
  private var undoStack: [Snapshot]
  private var redoStack: [Snapshot]

  public init(
    text: String = "",
    cursor: TextPosition? = nil,
    selectionAnchor: TextPosition? = nil,
    verticalOffset: Int = 0,
    horizontalOffset: Int = 0,
    maximumHistory: Int = 100
  ) {
    lines = Self.split(text)
    self.cursor = cursor ?? TextPosition(row: lines.count - 1, column: lines.last?.count ?? 0)
    self.selectionAnchor = selectionAnchor
    self.verticalOffset = max(0, verticalOffset)
    self.horizontalOffset = max(0, horizontalOffset)
    self.maximumHistory = max(0, maximumHistory)
    undoStack = []
    redoStack = []
    reconcile()
  }

  public var text: String {
    get { lines.joined(separator: "\n") }
    set {
      saveUndo()
      lines = Self.split(newValue)
      cursor = TextPosition(row: lines.count - 1, column: lines.last?.count ?? 0)
      selectionAnchor = nil
      reconcile()
    }
  }

  public var selectedRange: (lower: TextPosition, upper: TextPosition)? {
    guard let selectionAnchor, selectionAnchor != cursor else { return nil }
    return selectionAnchor < cursor ? (selectionAnchor, cursor) : (cursor, selectionAnchor)
  }

  public var selectedText: String? {
    guard let range = selectedRange else { return nil }
    if range.lower.row == range.upper.row {
      return slice(lines[range.lower.row], range.lower.column..<range.upper.column)
    }
    var selected = [suffix(lines[range.lower.row], from: range.lower.column)]
    if range.upper.row - range.lower.row > 1 {
      selected.append(contentsOf: lines[(range.lower.row + 1)..<range.upper.row])
    }
    selected.append(prefix(lines[range.upper.row], through: range.upper.column))
    return selected.joined(separator: "\n")
  }

  @discardableResult
  public mutating func handle(_ event: TerminalEvent) -> Bool {
    reconcile()
    switch event {
    case .paste(let value):
      replaceSelectionAndInsert(value)
      return true
    case .key(let key) where key.kind != .release:
      return handle(key)
    default:
      return false
    }
  }

  @discardableResult
  public mutating func handle(
    _ event: TerminalEvent,
    when focusedControl: ControlID?,
    is id: ControlID
  ) -> Bool {
    guard focusedControl == id else { return false }
    return handle(event)
  }

  public mutating func selectAll() {
    selectionAnchor = TextPosition(row: 0, column: 0)
    cursor = TextPosition(row: lines.count - 1, column: lines.last?.count ?? 0)
  }

  @discardableResult
  public mutating func undo() -> Bool {
    guard let previous = undoStack.popLast() else { return false }
    redoStack.append(snapshot)
    restore(previous)
    return true
  }

  @discardableResult
  public mutating func redo() -> Bool {
    guard let next = redoStack.popLast() else { return false }
    undoStack.append(snapshot)
    restore(next)
    return true
  }

  public mutating func ensureCursorVisible(viewport: Size, gutterWidth: Int = 0) {
    reconcile()
    let height = max(1, viewport.height)
    if cursor.row < verticalOffset {
      verticalOffset = cursor.row
    } else if cursor.row >= verticalOffset + height {
      verticalOffset = cursor.row - height + 1
    }

    let width = max(1, viewport.width - max(0, gutterWidth))
    let cursorColumn = TerminalWidth.of(prefix(lines[cursor.row], through: cursor.column))
    if cursorColumn < horizontalOffset {
      horizontalOffset = cursorColumn
    } else if cursorColumn >= horizontalOffset + width {
      horizontalOffset = cursorColumn - width + 1
    }
  }

  public mutating func reconcile() {
    if lines.isEmpty { lines = [""] }
    cursor.row = min(max(0, cursor.row), lines.count - 1)
    cursor.column = min(max(0, cursor.column), lines[cursor.row].count)
    if var anchor = selectionAnchor {
      anchor.row = min(max(0, anchor.row), lines.count - 1)
      anchor.column = min(max(0, anchor.column), lines[anchor.row].count)
      selectionAnchor = anchor == cursor ? nil : anchor
    }
    verticalOffset = min(max(0, verticalOffset), lines.count - 1)
    horizontalOffset = max(0, horizontalOffset)
  }

  private var snapshot: Snapshot {
    Snapshot(lines: lines, cursor: cursor, selectionAnchor: selectionAnchor)
  }

  private mutating func saveUndo() {
    guard maximumHistory > 0 else {
      redoStack.removeAll(keepingCapacity: true)
      return
    }
    undoStack.append(snapshot)
    if undoStack.count > maximumHistory {
      undoStack.removeFirst(undoStack.count - maximumHistory)
    }
    redoStack.removeAll(keepingCapacity: true)
  }

  private mutating func restore(_ value: Snapshot) {
    lines = value.lines
    cursor = value.cursor
    selectionAnchor = value.selectionAnchor
    reconcile()
  }

  private mutating func handle(_ key: KeyEvent) -> Bool {
    let selecting = key.modifiers.contains(.shift)
    switch key.key {
    case .character("z") where key.modifiers.contains(.command) || key.modifiers.contains(.control):
      return selecting ? redo() : undo()
    case .character("a") where key.modifiers.contains(.command):
      selectAll()
    case .character("u") where key.modifiers.contains(.control):
      deleteToStartOfLine()
    case .character("k") where key.modifiers.contains(.control):
      deleteToEndOfLine()
    case .character("w") where key.modifiers.contains(.control):
      deletePreviousWord()
    case .left where key.modifiers.contains(.command):
      move(to: TextPosition(row: cursor.row, column: 0), selecting: selecting)
    case .left where key.modifiers.contains(.option) || key.modifiers.contains(.control):
      move(to: TextPosition(row: cursor.row, column: previousWordBoundary()), selecting: selecting)
    case .right where key.modifiers.contains(.command):
      move(to: TextPosition(row: cursor.row, column: lines[cursor.row].count), selecting: selecting)
    case .right where key.modifiers.contains(.option) || key.modifiers.contains(.control):
      move(to: TextPosition(row: cursor.row, column: nextWordBoundary()), selecting: selecting)
    case .left:
      move(to: previousPosition(), selecting: selecting)
    case .right:
      move(to: nextPosition(), selecting: selecting)
    case .up:
      move(to: verticalPosition(delta: -1), selecting: selecting)
    case .down:
      move(to: verticalPosition(delta: 1), selecting: selecting)
    case .home,
      .character("a") where key.modifiers.contains(.control):
      move(to: TextPosition(row: cursor.row, column: 0), selecting: selecting)
    case .end,
      .character("e") where key.modifiers.contains(.control):
      move(to: TextPosition(row: cursor.row, column: lines[cursor.row].count), selecting: selecting)
    case .enter:
      replaceSelectionAndInsert("\n")
    case .backspace where key.modifiers.contains(.command):
      deleteToStartOfLine()
    case .backspace where key.modifiers.contains(.option) || key.modifiers.contains(.control):
      deletePreviousWord()
    case .backspace:
      deleteBackward()
    case .delete:
      deleteForward()
    case .character(let value)
    where !key.modifiers.contains(.control) && !key.modifiers.contains(.command):
      replaceSelectionAndInsert(String(value))
    default:
      return false
    }
    return true
  }

  private mutating func move(to position: TextPosition, selecting: Bool) {
    if selecting {
      selectionAnchor = selectionAnchor ?? cursor
    } else {
      selectionAnchor = nil
    }
    cursor = position
    reconcile()
  }

  private func previousPosition() -> TextPosition {
    if cursor.column > 0 { return TextPosition(row: cursor.row, column: cursor.column - 1) }
    guard cursor.row > 0 else { return cursor }
    return TextPosition(row: cursor.row - 1, column: lines[cursor.row - 1].count)
  }

  private func nextPosition() -> TextPosition {
    if cursor.column < lines[cursor.row].count {
      return TextPosition(row: cursor.row, column: cursor.column + 1)
    }
    guard cursor.row + 1 < lines.count else { return cursor }
    return TextPosition(row: cursor.row + 1, column: 0)
  }

  private func verticalPosition(delta: Int) -> TextPosition {
    let row = min(max(0, cursor.row + delta), lines.count - 1)
    return TextPosition(row: row, column: min(cursor.column, lines[row].count))
  }

  private func previousWordBoundary() -> Int {
    let characters = Array(lines[cursor.row])
    var index = min(cursor.column, characters.count)
    while index > 0, characters[index - 1].isWhitespace { index -= 1 }
    while index > 0, !characters[index - 1].isWhitespace { index -= 1 }
    return index
  }

  private func nextWordBoundary() -> Int {
    let characters = Array(lines[cursor.row])
    var index = min(cursor.column, characters.count)
    while index < characters.count, !characters[index].isWhitespace { index += 1 }
    while index < characters.count, characters[index].isWhitespace { index += 1 }
    return index
  }

  private mutating func deleteToStartOfLine() {
    if deleteSelection() { return }
    guard cursor.column > 0 else { return }
    saveUndo()
    lines[cursor.row] = replacing(lines[cursor.row], range: 0..<cursor.column, with: "")
    cursor.column = 0
    reconcile()
  }

  private mutating func deleteToEndOfLine() {
    if deleteSelection() { return }
    guard cursor.column < lines[cursor.row].count else { return }
    saveUndo()
    lines[cursor.row] = replacing(
      lines[cursor.row], range: cursor.column..<lines[cursor.row].count, with: "")
    reconcile()
  }

  private mutating func deletePreviousWord() {
    if deleteSelection() { return }
    let boundary = previousWordBoundary()
    guard boundary < cursor.column else { return }
    saveUndo()
    lines[cursor.row] = replacing(
      lines[cursor.row], range: boundary..<cursor.column, with: "")
    cursor.column = boundary
    reconcile()
  }

  private mutating func deleteBackward() {
    if deleteSelection() { return }
    guard cursor != TextPosition(row: 0, column: 0) else { return }
    saveUndo()
    if cursor.column > 0 {
      lines[cursor.row] = replacing(
        lines[cursor.row], range: (cursor.column - 1)..<cursor.column, with: "")
      cursor.column -= 1
    } else {
      let previousRow = cursor.row - 1
      let previousCount = lines[previousRow].count
      lines[previousRow] += lines[cursor.row]
      lines.remove(at: cursor.row)
      cursor = TextPosition(row: previousRow, column: previousCount)
    }
    selectionAnchor = nil
    reconcile()
  }

  private mutating func deleteForward() {
    if deleteSelection() { return }
    guard cursor.row < lines.count else { return }
    if cursor.column < lines[cursor.row].count {
      saveUndo()
      lines[cursor.row] = replacing(
        lines[cursor.row], range: cursor.column..<(cursor.column + 1), with: "")
    } else if cursor.row + 1 < lines.count {
      saveUndo()
      lines[cursor.row] += lines[cursor.row + 1]
      lines.remove(at: cursor.row + 1)
    } else {
      return
    }
    selectionAnchor = nil
    reconcile()
  }

  @discardableResult
  private mutating func deleteSelection() -> Bool {
    guard let range = selectedRange else { return false }
    saveUndo()
    if range.lower.row == range.upper.row {
      lines[range.lower.row] = replacing(
        lines[range.lower.row], range: range.lower.column..<range.upper.column, with: "")
    } else {
      let merged =
        prefix(lines[range.lower.row], through: range.lower.column)
        + suffix(lines[range.upper.row], from: range.upper.column)
      lines.replaceSubrange(range.lower.row...range.upper.row, with: [merged])
    }
    cursor = range.lower
    selectionAnchor = nil
    reconcile()
    return true
  }

  private mutating func replaceSelectionAndInsert(_ value: String) {
    if selectedRange != nil {
      _ = deleteSelection()
    } else {
      saveUndo()
    }
    let inserted = Self.split(value)
    let current = lines[cursor.row]
    let before = prefix(current, through: cursor.column)
    let after = suffix(current, from: cursor.column)
    if inserted.count == 1 {
      lines[cursor.row] = before + inserted[0] + after
      cursor.column += inserted[0].count
    } else {
      var replacement = inserted
      replacement[0] = before + replacement[0]
      replacement[replacement.count - 1] += after
      lines.replaceSubrange(cursor.row...cursor.row, with: replacement)
      cursor = TextPosition(
        row: cursor.row + replacement.count - 1,
        column: inserted.last?.count ?? 0)
    }
    selectionAnchor = nil
    reconcile()
  }

  private static func split(_ text: String) -> [String] {
    text.replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map(String.init)
  }
}

private func index(_ value: String, _ offset: Int) -> String.Index {
  value.index(value.startIndex, offsetBy: min(max(0, offset), value.count))
}

private func prefix(_ value: String, through offset: Int) -> String {
  String(value[..<index(value, offset)])
}

private func suffix(_ value: String, from offset: Int) -> String {
  String(value[index(value, offset)...])
}

private func slice(_ value: String, _ range: Range<Int>) -> String {
  String(value[index(value, range.lowerBound)..<index(value, range.upperBound)])
}

private func replacing(_ value: String, range: Range<Int>, with replacement: String) -> String {
  var result = value
  result.replaceSubrange(
    index(result, range.lowerBound)..<index(result, range.upperBound), with: replacement)
  return result
}
