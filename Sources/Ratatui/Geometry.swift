public struct Position: Hashable, Sendable {
  public var x: Int { didSet { x = max(0, x) } }
  public var y: Int { didSet { y = max(0, y) } }

  public init(x: Int, y: Int) {
    self.x = max(0, x)
    self.y = max(0, y)
  }

  public func offset(by offset: Offset) -> Self {
    Self(
      x: saturatingOffset(x, by: offset.x),
      y: saturatingOffset(y, by: offset.y)
    )
  }
}

public struct Offset: Hashable, Sendable {
  public var x: Int
  public var y: Int

  public init(x: Int, y: Int) {
    self.x = x
    self.y = y
  }

  public static let zero = Self(x: 0, y: 0)
}

public struct Size: Hashable, Sendable {
  public var width: Int { didSet { width = max(0, width) } }
  public var height: Int { didSet { height = max(0, height) } }

  public init(width: Int, height: Int) {
    self.width = max(0, width)
    self.height = max(0, height)
  }

  public static let zero = Self(width: 0, height: 0)

  public var area: Int {
    width.multipliedReportingOverflow(by: height).overflow ? Int.max : width * height
  }
}

public struct Rect: Hashable, Sendable {
  public var x: Int {
    didSet {
      x = max(0, x)
      width = min(max(0, width), Int.max - x)
    }
  }
  public var y: Int {
    didSet {
      y = max(0, y)
      height = min(max(0, height), Int.max - y)
    }
  }
  public var width: Int { didSet { width = min(max(0, width), Int.max - x) } }
  public var height: Int { didSet { height = min(max(0, height), Int.max - y) } }

  public init(x: Int, y: Int, width: Int, height: Int) {
    let x = max(0, x)
    let y = max(0, y)
    self.x = x
    self.y = y
    self.width = min(max(0, width), Int.max - x)
    self.height = min(max(0, height), Int.max - y)
  }

  public init(origin: Position = Position(x: 0, y: 0), size: Size) {
    self.init(x: origin.x, y: origin.y, width: size.width, height: size.height)
  }

  public static let zero = Self(x: 0, y: 0, width: 0, height: 0)

  public var size: Size {
    Size(width: width, height: height)
  }

  public var area: Int {
    width.multipliedReportingOverflow(by: height).overflow ? Int.max : width * height
  }

  public var isEmpty: Bool {
    width <= 0 || height <= 0
  }

  public var left: Int { x }
  public var top: Int { y }
  public var right: Int { saturatingAdd(max(0, x), max(0, width)) }
  public var bottom: Int { saturatingAdd(max(0, y), max(0, height)) }

  public func contains(_ position: Position) -> Bool {
    position.x >= x && position.y >= y && position.x < right && position.y < bottom
  }

  public func inset(by insets: Insets) -> Rect {
    let leading = max(0, insets.leading)
    let trailing = max(0, insets.trailing)
    let top = max(0, insets.top)
    let bottom = max(0, insets.bottom)
    let horizontal = min(max(0, width), saturatingAdd(leading, trailing))
    let vertical = min(max(0, height), saturatingAdd(top, bottom))
    return Rect(
      x: saturatingAdd(max(0, x), leading),
      y: saturatingAdd(max(0, y), top),
      width: max(0, width) - horizontal,
      height: max(0, height) - vertical
    )
  }

  public func outset(by insets: Insets) -> Rect {
    let left = max(0, x - min(max(0, x), max(0, insets.leading)))
    let top = max(0, y - min(max(0, y), max(0, insets.top)))
    let right = saturatingAdd(self.right, max(0, insets.trailing))
    let bottom = saturatingAdd(self.bottom, max(0, insets.bottom))
    return Rect(x: left, y: top, width: right - left, height: bottom - top)
  }

  public func offset(by offset: Offset) -> Rect {
    let maxX = Int.max - max(0, width)
    let maxY = Int.max - max(0, height)
    return Rect(
      x: min(saturatingOffset(max(0, x), by: offset.x), maxX),
      y: min(saturatingOffset(max(0, y), by: offset.y), maxY),
      width: width,
      height: height
    )
  }

  public func resized(to size: Size) -> Rect {
    Rect(x: x, y: y, width: size.width, height: size.height)
  }

  public func union(_ other: Rect) -> Rect {
    let left = min(x, other.x)
    let top = min(y, other.y)
    let right = max(self.right, other.right)
    let bottom = max(self.bottom, other.bottom)
    return Rect(x: left, y: top, width: right - left, height: bottom - top)
  }

  public func intersection(_ other: Rect) -> Rect {
    let left = max(x, other.x)
    let top = max(y, other.y)
    let right = min(self.right, other.right)
    let bottom = min(self.bottom, other.bottom)
    guard right > left, bottom > top else {
      return Rect(x: left, y: top, width: 0, height: 0)
    }
    return Rect(x: left, y: top, width: right - left, height: bottom - top)
  }

  public func intersects(_ other: Rect) -> Bool {
    x < other.right && right > other.x && y < other.bottom && bottom > other.y
  }

  public func clamped(to bounds: Rect) -> Rect {
    let width = min(max(0, width), max(0, bounds.width))
    let height = min(max(0, height), max(0, bounds.height))
    let x = min(max(self.x, bounds.x), bounds.right - width)
    let y = min(max(self.y, bounds.y), bounds.bottom - height)
    return Rect(x: x, y: y, width: width, height: height)
  }

  public func rows() -> RectRows { RectRows(self) }
  public func columns() -> RectColumns { RectColumns(self) }
  public func positions() -> RectPositions { RectPositions(self) }
}

public struct RectRows: Sequence, IteratorProtocol, Sendable {
  private let rect: Rect
  private var row = 0

  fileprivate init(_ rect: Rect) { self.rect = rect }

  public mutating func next() -> Rect? {
    guard row < rect.height else { return nil }
    defer { row += 1 }
    return Rect(x: rect.x, y: rect.y + row, width: rect.width, height: 1)
  }
}

public struct RectColumns: Sequence, IteratorProtocol, Sendable {
  private let rect: Rect
  private var column = 0

  fileprivate init(_ rect: Rect) { self.rect = rect }

  public mutating func next() -> Rect? {
    guard column < rect.width else { return nil }
    defer { column += 1 }
    return Rect(x: rect.x + column, y: rect.y, width: 1, height: rect.height)
  }
}

public struct RectPositions: Sequence, IteratorProtocol, Sendable {
  private let rect: Rect
  private var index = 0

  fileprivate init(_ rect: Rect) { self.rect = rect }

  public mutating func next() -> Position? {
    guard rect.width > 0, index < rect.area else { return nil }
    defer { index += 1 }
    return Position(x: rect.x + index % rect.width, y: rect.y + index / rect.width)
  }
}

public struct Insets: Hashable, Sendable {
  public var top: Int { didSet { top = max(0, top) } }
  public var leading: Int { didSet { leading = max(0, leading) } }
  public var bottom: Int { didSet { bottom = max(0, bottom) } }
  public var trailing: Int { didSet { trailing = max(0, trailing) } }

  public init(top: Int = 0, leading: Int = 0, bottom: Int = 0, trailing: Int = 0) {
    self.top = max(0, top)
    self.leading = max(0, leading)
    self.bottom = max(0, bottom)
    self.trailing = max(0, trailing)
  }

  public static func all(_ value: Int) -> Self {
    Self(top: value, leading: value, bottom: value, trailing: value)
  }
}

public enum Axis: Hashable, Sendable {
  case horizontal
  case vertical
}

public enum Constraint: Hashable, Sendable {
  case min(Int)
  case max(Int)
  case length(Int)
  case percentage(Int)
  case ratio(numerator: Int, denominator: Int)
  /// Distributes remaining space by weight. This is Ratatui's `Fill`
  /// constraint, spelled `flex` to read naturally at Swift call sites.
  case flex(Int)

  public static var fill: Self { .flex(1) }
}

/// Positions constrained segments when they do not consume the full layout area.
public enum Flex: Hashable, Sendable {
  case legacy
  case start
  case end
  case center
  case spaceBetween
  case spaceEvenly
  case spaceAround
}

private func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
  let result = lhs.addingReportingOverflow(rhs)
  return result.overflow ? Int.max : result.partialValue
}

private func saturatingOffset(_ value: Int, by offset: Int) -> Int {
  let result = value.addingReportingOverflow(offset)
  if result.overflow { return offset >= 0 ? Int.max : 0 }
  return max(0, result.partialValue)
}
