public struct BackendCapabilities: OptionSet, Hashable, Sendable {
  public let rawValue: UInt16

  public init(rawValue: UInt16) {
    self.rawValue = rawValue
  }

  public static let windowPixelSize = Self(rawValue: 1 << 2)
  public static let synchronizedOutput = Self(rawValue: 1 << 3)
  public static let regionalClears = Self(rawValue: 1 << 4)
  public static let inlineViewport = Self(rawValue: 1 << 5)
  public static let indexedColor = Self(rawValue: 1 << 6)
  public static let trueColor = Self(rawValue: 1 << 7)
  public static let underlineColor = Self(rawValue: 1 << 8)
}

public enum ClearRegion: Hashable, Sendable {
  case all
  case afterCursor
  case beforeCursor
  case currentLine
  case untilNewLine
}

public enum CursorStyle: Hashable, Sendable {
  case defaultUserShape
  case blinkingBlock
  case steadyBlock
  case blinkingUnderline
  case steadyUnderline
  case blinkingBar
  case steadyBar
}

public struct WindowSize: Hashable, Sendable {
  public var cells: Size
  public var pixels: Size?

  public init(cells: Size, pixels: Size? = nil) {
    self.cells = cells
    self.pixels = pixels
  }
}

public enum BackendOperationError: Error, Equatable {
  case unsupported(String)
}

public enum HistoryInsertionBatchPosition: Hashable, Sendable {
  case single
  case first
  case middle
  case last
}

public protocol Backend {
  var capabilities: BackendCapabilities { get }
  var viewportOrigin: Position { get }
  mutating func setViewportOrigin(_ origin: Position) throws
  mutating func size() throws -> Size
  mutating func windowSize() throws -> WindowSize
  mutating func draw(_ updates: [CellUpdate]) throws
  mutating func flush() throws
  mutating func clear() throws
  mutating func clear(_ region: ClearRegion) throws
  mutating func setCursor(_ position: Position?) throws
  mutating func setCursorStyle(_ style: CursorStyle) throws
}

/// Optional backend facet for terminals that can append physical lines below the cursor.
public protocol LineAppendingBackend: Backend {
  mutating func appendLines(_ count: UInt16) throws
}

/// Optional backend facet required by inline native-history insertion.
///
/// Conforming backends provide region movement. `insertHistory` is an optional native-scrollback fast path;
/// returning `false` selects `Terminal`'s generic fallback, which still requires the backend to implement
/// native-scrollback insertion. Visual region scrolling alone cannot preserve displaced terminal history.
public protocol InlineHistoryBackend: Backend {
  mutating func insertHistory(_ buffer: Buffer) throws -> Bool
  mutating func insertHistory(
    _ buffer: Buffer, batchPosition: HistoryInsertionBatchPosition
  ) throws -> Bool
  /// Inserts history while restoring the retained live viewport when the batch finishes.
  /// Backends with buffered output can override this to make the final insertion and restoration
  /// one visual transaction.
  mutating func insertHistory(
    _ buffer: Buffer,
    batchPosition: HistoryInsertionBatchPosition,
    restoring viewport: Buffer?
  ) throws -> Bool
  mutating func scrollRegionUp(_ rows: Range<UInt16>, by count: UInt16) throws
  /// Scroll a top-anchored region while retaining displaced rows in native terminal scrollback.
  /// This is distinct from visual CSI region scrolling, whose discarded rows are not history in
  /// several terminal emulators.
  mutating func scrollRegionUpIntoScrollback(_ rows: Range<UInt16>, by count: UInt16) throws
  mutating func scrollRegionDown(_ rows: Range<UInt16>, by count: UInt16) throws
}

extension Backend {
  public var capabilities: BackendCapabilities { [] }
  public var viewportOrigin: Position { Position(x: 0, y: 0) }
  public mutating func setViewportOrigin(_ origin: Position) throws {
    throw BackendOperationError.unsupported("viewport origin")
  }
  public mutating func setCursor(_ position: Position?) throws {}
  public mutating func setCursorStyle(_ style: CursorStyle) throws {}
  public mutating func flush() throws {}
  public mutating func clear(_ region: ClearRegion) throws {
    guard region == .all else { throw BackendOperationError.unsupported("regional clear") }
    try clear()
  }
  public mutating func windowSize() throws -> WindowSize { WindowSize(cells: try size()) }
}

extension InlineHistoryBackend {
  public mutating func insertHistory(_ buffer: Buffer) throws -> Bool { false }
  public mutating func insertHistory(
    _ buffer: Buffer, batchPosition: HistoryInsertionBatchPosition
  ) throws -> Bool {
    try insertHistory(buffer)
  }
  public mutating func insertHistory(
    _ buffer: Buffer,
    batchPosition: HistoryInsertionBatchPosition,
    restoring viewport: Buffer?
  ) throws -> Bool {
    let inserted = try insertHistory(buffer, batchPosition: batchPosition)
    let finishesBatch = batchPosition == .single || batchPosition == .last
    guard inserted, finishesBatch, let viewport else { return inserted }

    var updates: [CellUpdate] = []
    updates.reserveCapacity(Int(viewport.area.width) * Int(viewport.area.height))
    for row in 0..<Int(viewport.area.height) {
      for column in 0..<Int(viewport.area.width) {
        let source = Position(
          x: UInt16(clamping: Int(viewport.area.x) + column),
          y: UInt16(clamping: Int(viewport.area.y) + row)
        )
        guard let cell = viewport.cell(at: source) else { continue }
        updates.append(
          CellUpdate(
            position: Position(x: UInt16(clamping: column), y: UInt16(clamping: row)),
            cell: cell
          ))
      }
    }
    try draw(updates)
    return true
  }
  public mutating func scrollRegionUpIntoScrollback(
    _ rows: Range<UInt16>, by count: UInt16
  ) throws {
    throw BackendOperationError.unsupported("native scrollback insertion")
  }
}

public struct TestBackend: Backend, LineAppendingBackend, InlineHistoryBackend, Sendable {
  public private(set) var buffer: Buffer
  public private(set) var cursorPosition: Position?
  public private(set) var cursorStyle: CursorStyle
  public private(set) var scrollback: [[Cell]]
  public private(set) var flushCount: UInt64
  private var inlineViewportArea: Rect?

  public var capabilities: BackendCapabilities {
    var result: BackendCapabilities = [.windowPixelSize, .regionalClears]
    if inlineViewportArea != nil { result.insert(.inlineViewport) }
    return result
  }

  public var viewportOrigin: Position {
    inlineViewportArea.map { Position(x: $0.x, y: $0.y) } ?? Position(x: 0, y: 0)
  }

  public init(width: UInt16, height: UInt16) {
    buffer = Buffer(
      area: Rect(x: 0, y: 0, width: width, height: height)
    )
    cursorPosition = nil
    cursorStyle = .defaultUserShape
    scrollback = []
    flushCount = 0
    inlineViewportArea = nil
  }

  public init(screenWidth: UInt16, screenHeight: UInt16, viewport: Rect) {
    buffer = Buffer(area: Rect(x: 0, y: 0, width: screenWidth, height: screenHeight))
    cursorPosition = nil
    cursorStyle = .defaultUserShape
    scrollback = []
    flushCount = 0
    let x = min(viewport.x, screenWidth)
    let y = min(viewport.y, screenHeight)
    inlineViewportArea = Rect(
      x: x,
      y: y,
      width: min(viewport.width, screenWidth - x),
      height: min(viewport.height, screenHeight - y)
    )
  }

  public mutating func size() throws -> Size {
    inlineViewportArea?.size ?? buffer.area.size
  }

  public mutating func windowSize() throws -> WindowSize {
    WindowSize(cells: buffer.area.size, pixels: Size(width: 640, height: 480))
  }

  public mutating func draw(_ updates: [CellUpdate]) throws {
    for update in updates {
      buffer.setCell(
        update.cell,
        at: Position(
          x: UInt16(clamping: Int(viewportOrigin.x) + Int(update.position.x)),
          y: UInt16(clamping: Int(viewportOrigin.y) + Int(update.position.y))
        )
      )
    }
  }

  public mutating func flush() throws {
    flushCount &+= 1
  }

  public mutating func clear() throws {
    buffer.reset()
  }

  public mutating func clear(_ region: ClearRegion) throws {
    guard region != .all else { return try clear() }
    guard buffer.area.width > 0, buffer.area.height > 0 else { return }
    let cursor = cursorPosition ?? Position(x: 0, y: 0)
    let width = Int(buffer.area.width)
    let height = Int(buffer.area.height)
    let cursorX = min(width - 1, Int(cursor.x))
    let cursorY = min(height - 1, Int(cursor.y))

    func shouldClear(x: Int, y: Int) -> Bool {
      switch region {
      case .all: true
      case .afterCursor: y > cursorY || (y == cursorY && x >= cursorX)
      case .beforeCursor: y < cursorY || (y == cursorY && x <= cursorX)
      case .currentLine: y == cursorY
      case .untilNewLine: y == cursorY && x >= cursorX
      }
    }
    for y in 0..<height {
      for x in 0..<width where shouldClear(x: x, y: y) {
        buffer.setCell(.empty, at: Position(x: UInt16(x), y: UInt16(y)))
      }
    }
  }

  public mutating func setCursor(_ position: Position?) throws {
    cursorPosition = position
  }

  public mutating func setCursorStyle(_ style: CursorStyle) throws {
    cursorStyle = style
  }

  public mutating func setViewportOrigin(_ origin: Position) throws {
    guard var viewport = inlineViewportArea else {
      throw BackendOperationError.unsupported("viewport origin")
    }
    viewport.x = min(origin.x, buffer.area.width)
    viewport.y = min(origin.y, buffer.area.height)
    inlineViewportArea = viewport
  }

  public mutating func resize(width: UInt16, height: UInt16) {
    buffer = Buffer(area: Rect(x: 0, y: 0, width: width, height: height))
    inlineViewportArea = nil
  }

  public mutating func setScreenCell(_ cell: Cell, at position: Position) {
    buffer.setCell(cell, at: position)
  }

  public mutating func appendLines(_ count: UInt16) throws {
    guard count > 0, buffer.area.width > 0, buffer.area.height > 0 else { return }
    let cursor = cursorPosition ?? Position(x: 0, y: 0)
    let lastRow = Int(buffer.area.height) - 1
    let linesAfterCursor = max(0, lastRow - Int(cursor.y))
    let overflow = max(0, Int(count) - linesAfterCursor)
    if overflow > 0 {
      try scrollRegionUp(0..<buffer.area.height, by: UInt16(clamping: overflow))
    }
    cursorPosition = Position(
      x: UInt16(clamping: min(Int(cursor.x) + 1, Int(buffer.area.width) - 1)),
      y: UInt16(clamping: min(lastRow, Int(cursor.y) + Int(count)))
    )
  }

  public mutating func scrollRegionUp(_ rows: Range<UInt16>, by count: UInt16) throws {
    let range = clipped(rows)
    guard !range.isEmpty, count > 0 else { return }
    let amount = min(range.count, Int(count))
    let original = range.map(row)
    if range.lowerBound == 0 {
      var displaced = Array(original.prefix(amount))
      if Int(count) > amount {
        displaced.append(
          contentsOf: repeatElement(emptyRow(), count: Int(count) - amount)
        )
      }
      appendToScrollback(displaced)
    }
    for (offset, destination) in range.enumerated() {
      writeRow(offset + amount < original.count ? original[offset + amount] : nil, to: destination)
    }
  }

  public mutating func scrollRegionUpIntoScrollback(
    _ rows: Range<UInt16>, by count: UInt16
  ) throws {
    try scrollRegionUp(rows, by: count)
  }

  public mutating func scrollRegionDown(_ rows: Range<UInt16>, by count: UInt16) throws {
    let range = clipped(rows)
    guard !range.isEmpty, count > 0 else { return }
    let amount = min(range.count, Int(count))
    let original = range.map(row)
    for (offset, destination) in range.enumerated() {
      writeRow(offset >= amount ? original[offset - amount] : nil, to: destination)
    }
  }

  private func clipped(_ rows: Range<UInt16>) -> Range<Int> {
    let lower = min(Int(buffer.area.height), Int(rows.lowerBound))
    let upper = min(Int(buffer.area.height), Int(rows.upperBound))
    return min(lower, upper)..<max(lower, upper)
  }

  private func row(_ y: Int) -> [Cell] {
    (0..<Int(buffer.area.width)).compactMap {
      buffer.cell(at: Position(x: UInt16(clamping: $0), y: UInt16(clamping: y)))
    }
  }

  private func emptyRow() -> [Cell] {
    Array(repeating: .empty, count: Int(buffer.area.width))
  }

  private mutating func appendToScrollback(_ rows: [[Cell]]) {
    scrollback.append(contentsOf: rows)
    let overflow = max(0, scrollback.count - Int(UInt16.max))
    if overflow > 0 {
      scrollback.removeFirst(overflow)
    }
  }

  private mutating func writeRow(_ cells: [Cell]?, to y: Int) {
    for x in 0..<Int(buffer.area.width) {
      buffer.setCell(
        cells?[x] ?? .empty,
        at: Position(x: UInt16(clamping: x), y: UInt16(clamping: y))
      )
    }
  }
}
