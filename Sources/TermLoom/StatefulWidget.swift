/// A widget whose viewport state is owned by the application and reconciled
/// during rendering.
public protocol StatefulWidget {
  associatedtype State

  func render(
    in area: Rect,
    into frame: inout Frame,
    state: inout State
  )
}

extension StatefulWidget {
  /// Renders only the visual cells into a standalone buffer.
  ///
  /// Use `Frame.render(_:in:state:)` when interaction and cursor metadata must be retained.
  public func render(
    in area: Rect,
    into buffer: inout Buffer,
    environment: RenderEnvironment = RenderEnvironment(),
    state: inout State
  ) {
    var frame = Frame(buffer: buffer, environment: environment)
    frame.render(self, in: area, state: &state)
    buffer = frame.buffer
  }
}

public struct ListState: Hashable, Sendable {
  public var offset: Int
  public var selected: Int?

  public init(offset: Int = 0, selected: Int? = nil) {
    self.offset = max(0, offset)
    self.selected = selected
  }

  public mutating func select(_ index: Int?) {
    selected = index
    if index == nil { offset = 0 }
  }

  public mutating func selectNext(in indices: Range<Int>, wrapping: Bool = false) {
    guard !indices.isEmpty else { return select(nil) }
    let next = selected.map { $0 + 1 } ?? indices.lowerBound
    select(
      next < indices.upperBound ? next : (wrapping ? indices.lowerBound : indices.upperBound - 1))
  }

  public mutating func selectPrevious(in indices: Range<Int>, wrapping: Bool = false) {
    guard !indices.isEmpty else { return select(nil) }
    let previous = selected.map { $0 - 1 } ?? indices.upperBound - 1
    select(
      previous >= indices.lowerBound
        ? previous : (wrapping ? indices.upperBound - 1 : indices.lowerBound))
  }

  mutating func reconcile(itemCount: Int, viewportLength: Int) {
    guard itemCount > 0, viewportLength > 0 else {
      offset = 0
      selected = nil
      return
    }
    if let selected {
      let selected = min(max(0, selected), itemCount - 1)
      self.selected = selected
      if selected < offset { offset = selected }
      if selected >= offset + viewportLength { offset = selected - viewportLength + 1 }
    }
    offset = min(max(0, offset), max(0, itemCount - viewportLength))
  }
}

public struct TableState: Hashable, Sendable {
  public var offset: Int
  public var selectedRow: Int?
  public var selectedColumn: Int?

  public init(offset: Int = 0, selectedRow: Int? = nil, selectedColumn: Int? = nil) {
    self.offset = max(0, offset)
    self.selectedRow = selectedRow
    self.selectedColumn = selectedColumn
  }

  public var selectedCell: (row: Int, column: Int)? {
    guard let selectedRow, let selectedColumn else { return nil }
    return (selectedRow, selectedColumn)
  }

  /// Selects a row without changing the selected column.
  public mutating func selectRow(_ index: Int?) {
    selectedRow = index
    if index == nil { offset = 0 }
  }

  public mutating func selectColumn(_ index: Int?) {
    selectedColumn = index
  }

  public mutating func selectCell(_ cell: (row: Int, column: Int)?) {
    if let cell {
      selectedRow = cell.row
      selectedColumn = cell.column
    } else {
      offset = 0
      selectedRow = nil
      selectedColumn = nil
    }
  }

  public mutating func select(row: Int?, column: Int? = nil) {
    selectedRow = row
    selectedColumn = row == nil ? nil : column
    if row == nil { offset = 0 }
  }

  public mutating func selectNextRow() {
    selectRow(Self.saturatingAdd(selectedRow ?? 0, 1))
  }

  public mutating func selectPreviousRow() {
    selectRow(
      selectedRow.map { value in
        value > 0 ? value - 1 : 0
      } ?? .max
    )
  }

  public mutating func selectNextColumn() {
    selectColumn(Self.saturatingAdd(selectedColumn ?? 0, 1))
  }

  public mutating func selectPreviousColumn() {
    selectColumn(
      selectedColumn.map { value in
        value > 0 ? value - 1 : 0
      } ?? .max
    )
  }

  public mutating func selectFirstRow() {
    selectRow(0)
  }

  public mutating func selectLastRow() {
    selectRow(.max)
  }

  public mutating func selectFirstColumn() {
    selectColumn(0)
  }

  public mutating func selectLastColumn() {
    selectColumn(.max)
  }

  public mutating func scrollDown(by amount: Int) {
    selectRow(Self.saturatingAdd(max(0, selectedRow ?? 0), max(0, amount)))
  }

  public mutating func scrollUp(by amount: Int) {
    selectRow(max(0, max(0, selectedRow ?? 0) - max(0, amount)))
  }

  public mutating func scrollRight(by amount: Int) {
    selectColumn(Self.saturatingAdd(max(0, selectedColumn ?? 0), max(0, amount)))
  }

  public mutating func scrollLeft(by amount: Int) {
    selectColumn(max(0, max(0, selectedColumn ?? 0) - max(0, amount)))
  }

  public mutating func selectNextRow(in indices: Range<Int>, wrapping: Bool = false) {
    var listState = ListState(offset: offset, selected: selectedRow)
    listState.selectNext(in: indices, wrapping: wrapping)
    offset = listState.offset
    selectedRow = listState.selected
  }

  public mutating func selectPreviousRow(in indices: Range<Int>, wrapping: Bool = false) {
    var listState = ListState(offset: offset, selected: selectedRow)
    listState.selectPrevious(in: indices, wrapping: wrapping)
    offset = listState.offset
    selectedRow = listState.selected
  }

  mutating func reconcile(rowCount: Int, columnCount: Int, viewportLength: Int) {
    var listState = ListState(offset: offset, selected: selectedRow)
    listState.reconcile(itemCount: rowCount, viewportLength: viewportLength)
    offset = listState.offset
    selectedRow = listState.selected
    if columnCount == 0 {
      selectedColumn = nil
    } else if let selectedColumn {
      self.selectedColumn = min(max(0, selectedColumn), columnCount - 1)
    }
  }

  mutating func visibleRows(
    rowHeights: [Int],
    rowContentHeights: [Int]? = nil,
    viewportHeight: Int
  ) -> Range<Int> {
    guard viewportHeight > 0, !rowHeights.isEmpty else {
      offset = 0
      if rowHeights.isEmpty { selectedRow = nil }
      return 0..<0
    }
    if let selectedRow {
      self.selectedRow = min(max(0, selectedRow), rowHeights.count - 1)
    }
    let contentHeights: [Int]
    if let rowContentHeights, rowContentHeights.count == rowHeights.count {
      contentHeights = rowContentHeights
    } else {
      contentHeights = rowHeights
    }
    var first = min(max(0, offset), rowHeights.count - 1)
    if let selectedRow {
      first = min(first, selectedRow)
    }
    var last = first
    var usedHeight = 0
    while last < rowHeights.count,
      usedHeight + contentHeights[last] <= viewportHeight
    {
      usedHeight += rowHeights[last]
      last += 1
    }
    if let selectedRow {
      while selectedRow >= last, last < rowHeights.count {
        usedHeight += rowHeights[last]
        last += 1
        while usedHeight > viewportHeight, first < last {
          usedHeight -= rowHeights[first]
          first += 1
        }
      }
    }
    if usedHeight < viewportHeight, last < rowHeights.count {
      last += 1
    }
    offset = first
    return first..<last
  }

  private static func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
    let (result, overflow) = lhs.addingReportingOverflow(rhs)
    return overflow ? .max : result
  }
}
