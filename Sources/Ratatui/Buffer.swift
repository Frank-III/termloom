public struct Buffer: Hashable, Sendable {
  public private(set) var area: Rect
  private var storage: ContiguousArray<Cell>

  public init(area: Rect, repeating cell: Cell = .empty) {
    self.area = area
    storage = ContiguousArray(repeating: cell, count: area.area)
  }

  public var count: Int {
    storage.count
  }

  /// Replaces the complete row-major buffer contents without per-cell bounds or glyph cleanup.
  /// This is intended for decoded full-frame transports whose cells already carry valid width and
  /// continuation metadata.
  public mutating func replaceCells(_ cells: [Cell]) {
    precondition(cells.count == storage.count, "replacement cell count must match buffer area")
    storage = ContiguousArray(cells)
  }

  public subscript(position: Position) -> Cell {
    get { storage[index(of: position)] }
    set { storage[index(of: position)] = newValue }
  }

  public func cell(at position: Position) -> Cell? {
    guard area.contains(position) else { return nil }
    return storage[index(of: position)]
  }

  public mutating func setCell(_ cell: Cell, at position: Position) {
    guard area.contains(position) else { return }
    storage[index(of: position)] = cell
  }

  public mutating func mergeSymbol(
    _ symbol: Character,
    at position: Position,
    style: Style = .plain,
    strategy: BorderMergeStrategy
  ) {
    if strategy == .replace {
      setString(String(symbol), at: position, style: style)
      return
    }
    guard area.contains(position), TerminalWidth.of(symbol) == 1 else { return }
    let previous = storage[index(of: position)]
    guard previous.width == 1, !previous.isContinuation, let previousSymbol = previous.symbol.first
    else {
      setString(String(symbol), at: position, style: style)
      return
    }
    if previousSymbol == " " {
      setString(String(symbol), at: position, style: style)
      return
    }
    let merged = strategy.merge(previousSymbol, symbol)
    let mergedStyle = merged == previousSymbol && merged != symbol ? previous.style : style
    setString(String(merged), at: position, style: mergedStyle)
  }

  @discardableResult
  public mutating func setString(
    _ string: String,
    at position: Position,
    style: Style = .plain,
    maxWidth: UInt16? = nil
  ) -> Position {
    guard area.contains(position) else { return position }

    let areaEnd = Int(area.x) + Int(area.width)
    let requestedEnd = maxWidth.map { Int(position.x) + Int($0) } ?? areaEnd
    let endX = min(areaEnd, requestedEnd)
    var x = Int(position.x)

    for character in string {
      let width = TerminalWidth.of(character)
      if width == 0 {
        appendZeroWidth(character, beforeX: x, y: position.y)
        continue
      }
      guard x + width <= endX else { break }
      for occupiedX in x..<(x + width) {
        clearGlyph(at: Position(x: UInt16(clamping: occupiedX), y: position.y))
      }
      let cellPosition = Position(x: UInt16(clamping: x), y: position.y)
      setCell(
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
          setCell(
            Cell(symbol: "", style: style, width: 0, isContinuation: true),
            at: Position(x: UInt16(clamping: x + continuation), y: position.y)
          )
        }
      }
      x += width
    }
    return Position(x: UInt16(clamping: x), y: position.y)
  }

  public mutating func fill(_ area: Rect, with cell: Cell) {
    let clipped = intersection(area, self.area)
    guard !clipped.isEmpty, cell.width == 1, !cell.isContinuation else { return }
    for y in Int(clipped.y)..<(Int(clipped.y) + Int(clipped.height)) {
      for x in Int(clipped.x)..<(Int(clipped.x) + Int(clipped.width)) {
        clearGlyph(at: Position(x: UInt16(x), y: UInt16(y)))
      }
    }
    for y in Int(clipped.y)..<(Int(clipped.y) + Int(clipped.height)) {
      for x in Int(clipped.x)..<(Int(clipped.x) + Int(clipped.width)) {
        storage[index(of: Position(x: UInt16(x), y: UInt16(y)))] = cell
      }
    }
  }

  public mutating func setStyle(_ style: Style, in area: Rect) {
    let clipped = self.area.intersection(area)
    guard !clipped.isEmpty else { return }
    for position in clipped.positions() {
      let index = index(of: position)
      storage[index].style = storage[index].style.patching(style)
    }
  }

  /// Reshapes the linear cell storage to a new mapped area.
  ///
  /// This matches Ratatui's buffer primitive: existing cells retain their
  /// linear order, excess cells are truncated, and new cells are empty.
  public mutating func resize(to area: Rect) {
    let targetCount = area.area
    if storage.count > targetCount {
      storage.removeLast(storage.count - targetCount)
    } else if storage.count < targetCount {
      storage.append(contentsOf: repeatElement(.empty, count: targetCount - storage.count))
    }
    self.area = area
  }

  /// Expands this buffer to contain both areas and overlays `other` by coordinate.
  public mutating func merge(_ other: Buffer) {
    let mergedArea = area.union(other.area)
    var merged = Buffer(area: mergedArea)
    for position in area.positions() {
      merged[position] = self[position]
    }
    for position in other.area.positions() {
      merged[position] = other[position]
    }
    self = merged
  }

  public mutating func reset() {
    storage.withContiguousMutableStorageIfAvailable { cells in
      cells.update(repeating: .empty)
    }
  }

  public func diff(from previous: Buffer) -> [CellUpdate] {
    guard area == previous.area else {
      return allUpdates()
    }
    var updates: [CellUpdate] = []
    updates.reserveCapacity(storage.count / 8)
    var index = storage.startIndex
    while index < storage.endIndex {
      let current = storage[index]
      if current.isContinuation {
        index += 1
        continue
      }
      let width = max(1, Int(current.width))
      if current != previous.storage[index] {
        updates.append(CellUpdate(position: position(of: index), cell: current))
        if width > 1, current.symbol.unicodeScalars.contains(where: { $0.value == 0xFE0F }) {
          let trailingEnd = min(storage.endIndex, index + width)
          for trailingIndex in (index + 1)..<trailingEnd
          where storage[trailingIndex].symbol != previous.storage[trailingIndex].symbol {
            updates.append(
              CellUpdate(position: position(of: trailingIndex), cell: .empty)
            )
          }
        }
      }
      index += width
    }
    return updates
  }

  public func lines(trimmingTrailingWhitespace: Bool = false) -> [String] {
    guard area.width > 0, area.height > 0 else { return [] }
    return (0..<Int(area.height)).map { row in
      var line = ""
      for column in 0..<Int(area.width) {
        let position = Position(
          x: UInt16(clamping: Int(area.x) + column),
          y: UInt16(clamping: Int(area.y) + row)
        )
        let cell = storage[index(of: position)]
        if !cell.isContinuation {
          line += cell.symbol
        }
      }
      if trimmingTrailingWhitespace {
        while line.last == " " {
          line.removeLast()
        }
      }
      return line
    }
  }

  private func allUpdates() -> [CellUpdate] {
    storage.indices.map { index in
      CellUpdate(position: position(of: index), cell: storage[index])
    }
  }

  private func index(of position: Position) -> Int {
    let row = Int(position.y) - Int(area.y)
    let column = Int(position.x) - Int(area.x)
    return row * Int(area.width) + column
  }

  private func position(of index: Int) -> Position {
    let width = max(1, Int(area.width))
    return Position(
      x: UInt16(clamping: Int(area.x) + index % width),
      y: UInt16(clamping: Int(area.y) + index / width)
    )
  }

  private mutating func clearGlyph(at position: Position) {
    guard area.contains(position) else { return }
    var startX = Int(position.x)
    while startX > Int(area.x) {
      let cell = storage[
        index(of: Position(x: UInt16(clamping: startX), y: position.y))
      ]
      guard cell.isContinuation else { break }
      startX -= 1
    }

    let start = Position(x: UInt16(clamping: startX), y: position.y)
    let width = max(1, Int(storage[index(of: start)].width))
    let endX = min(Int(area.x) + Int(area.width), startX + width)
    for x in startX..<endX {
      storage[index(of: Position(x: UInt16(clamping: x), y: position.y))] = .empty
    }
  }

  private mutating func appendZeroWidth(_ character: Character, beforeX x: Int, y: UInt16) {
    guard x > Int(area.x) else { return }
    var targetX = x - 1
    while targetX > Int(area.x) {
      let position = Position(x: UInt16(clamping: targetX), y: y)
      guard storage[index(of: position)].isContinuation else { break }
      targetX -= 1
    }
    let position = Position(x: UInt16(clamping: targetX), y: y)
    guard area.contains(position), !storage[index(of: position)].isContinuation else { return }
    storage[index(of: position)].symbol.append(contentsOf: String(character))
  }

  private func intersection(_ lhs: Rect, _ rhs: Rect) -> Rect {
    let left = max(Int(lhs.x), Int(rhs.x))
    let top = max(Int(lhs.y), Int(rhs.y))
    let right = min(Int(lhs.x) + Int(lhs.width), Int(rhs.x) + Int(rhs.width))
    let bottom = min(Int(lhs.y) + Int(lhs.height), Int(rhs.y) + Int(rhs.height))
    guard right > left, bottom > top else { return .zero }
    return Rect(
      x: UInt16(clamping: left),
      y: UInt16(clamping: top),
      width: UInt16(clamping: right - left),
      height: UInt16(clamping: bottom - top)
    )
  }
}
