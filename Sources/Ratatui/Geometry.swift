public struct Position: Hashable, Sendable {
  public var x: UInt16
  public var y: UInt16

  public init(x: UInt16, y: UInt16) {
    self.x = x
    self.y = y
  }

  public func offset(by offset: Offset) -> Self {
    Self(
      x: UInt16(clamping: Int(x) + offset.x),
      y: UInt16(clamping: Int(y) + offset.y)
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
  public var width: UInt16
  public var height: UInt16

  public init(width: UInt16, height: UInt16) {
    self.width = width
    self.height = height
  }

  public static let zero = Self(width: 0, height: 0)

  public var area: Int { Int(width) * Int(height) }
}

public struct Rect: Hashable, Sendable {
  public var x: UInt16
  public var y: UInt16
  public var width: UInt16
  public var height: UInt16

  public init(x: UInt16, y: UInt16, width: UInt16, height: UInt16) {
    self.x = x
    self.y = y
    self.width = min(width, UInt16.max - x)
    self.height = min(height, UInt16.max - y)
  }

  public init(origin: Position = Position(x: 0, y: 0), size: Size) {
    self.init(x: origin.x, y: origin.y, width: size.width, height: size.height)
  }

  public static let zero = Self(x: 0, y: 0, width: 0, height: 0)

  public var size: Size {
    Size(width: width, height: height)
  }

  public var area: Int {
    Int(width) * Int(height)
  }

  public var isEmpty: Bool {
    width == 0 || height == 0
  }

  public var left: UInt16 { x }
  public var top: UInt16 { y }
  public var right: UInt16 { UInt16(clamping: Int(x) + Int(width)) }
  public var bottom: UInt16 { UInt16(clamping: Int(y) + Int(height)) }

  public func contains(_ position: Position) -> Bool {
    position.x >= x
      && position.y >= y
      && Int(position.x) < Int(x) + Int(width)
      && Int(position.y) < Int(y) + Int(height)
  }

  public func inset(by insets: Insets) -> Rect {
    let horizontal = min(Int(width), Int(insets.leading) + Int(insets.trailing))
    let vertical = min(Int(height), Int(insets.top) + Int(insets.bottom))
    return Rect(
      x: UInt16(clamping: Int(x) + Int(insets.leading)),
      y: UInt16(clamping: Int(y) + Int(insets.top)),
      width: UInt16(clamping: Int(width) - horizontal),
      height: UInt16(clamping: Int(height) - vertical)
    )
  }

  public func outset(by insets: Insets) -> Rect {
    let left = max(0, Int(x) - Int(insets.leading))
    let top = max(0, Int(y) - Int(insets.top))
    let right = min(Int(UInt16.max), Int(self.right) + Int(insets.trailing))
    let bottom = min(Int(UInt16.max), Int(self.bottom) + Int(insets.bottom))
    return Rect(
      x: UInt16(left),
      y: UInt16(top),
      width: UInt16(right - left),
      height: UInt16(bottom - top)
    )
  }

  public func offset(by offset: Offset) -> Rect {
    let maxX = Int(UInt16.max) - Int(width)
    let maxY = Int(UInt16.max) - Int(height)
    return Rect(
      x: UInt16(clamping: min(max(0, Int(x) + offset.x), maxX)),
      y: UInt16(clamping: min(max(0, Int(y) + offset.y), maxY)),
      width: width,
      height: height
    )
  }

  public func resized(to size: Size) -> Rect {
    Rect(x: x, y: y, width: size.width, height: size.height)
  }

  public func union(_ other: Rect) -> Rect {
    let left = min(Int(x), Int(other.x))
    let top = min(Int(y), Int(other.y))
    let right = max(Int(self.right), Int(other.right))
    let bottom = max(Int(self.bottom), Int(other.bottom))
    return Rect(
      x: UInt16(left),
      y: UInt16(top),
      width: UInt16(right - left),
      height: UInt16(bottom - top)
    )
  }

  public func intersection(_ other: Rect) -> Rect {
    let left = max(Int(x), Int(other.x))
    let top = max(Int(y), Int(other.y))
    let right = min(Int(self.right), Int(other.right))
    let bottom = min(Int(self.bottom), Int(other.bottom))
    guard right > left, bottom > top else {
      return Rect(x: UInt16(clamping: left), y: UInt16(clamping: top), width: 0, height: 0)
    }
    return Rect(
      x: UInt16(left),
      y: UInt16(top),
      width: UInt16(right - left),
      height: UInt16(bottom - top)
    )
  }

  public func intersects(_ other: Rect) -> Bool {
    x < other.right && right > other.x && y < other.bottom && bottom > other.y
  }

  public func clamped(to bounds: Rect) -> Rect {
    let width = min(width, bounds.width)
    let height = min(height, bounds.height)
    let x = min(max(x, bounds.x), bounds.right - width)
    let y = min(max(y, bounds.y), bounds.bottom - height)
    return Rect(x: x, y: y, width: width, height: height)
  }

  public func rows() -> RectRows { RectRows(self) }
  public func columns() -> RectColumns { RectColumns(self) }
  public func positions() -> RectPositions { RectPositions(self) }
}

public struct RectRows: Sequence, IteratorProtocol, Sendable {
  private let rect: Rect
  private var row: UInt16 = 0

  fileprivate init(_ rect: Rect) { self.rect = rect }

  public mutating func next() -> Rect? {
    guard row < rect.height else { return nil }
    defer { row += 1 }
    return Rect(x: rect.x, y: rect.y + row, width: rect.width, height: 1)
  }
}

public struct RectColumns: Sequence, IteratorProtocol, Sendable {
  private let rect: Rect
  private var column: UInt16 = 0

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
    return Position(
      x: UInt16(clamping: Int(rect.x) + index % Int(rect.width)),
      y: UInt16(clamping: Int(rect.y) + index / Int(rect.width))
    )
  }
}

public struct Insets: Hashable, Sendable {
  public var top: UInt16
  public var leading: UInt16
  public var bottom: UInt16
  public var trailing: UInt16

  public init(
    top: UInt16 = 0,
    leading: UInt16 = 0,
    bottom: UInt16 = 0,
    trailing: UInt16 = 0
  ) {
    self.top = top
    self.leading = leading
    self.bottom = bottom
    self.trailing = trailing
  }

  public static func all(_ value: UInt16) -> Self {
    Self(top: value, leading: value, bottom: value, trailing: value)
  }
}

public enum Axis: Hashable, Sendable {
  case horizontal
  case vertical
}

public enum Constraint: Hashable, Sendable {
  case min(UInt16)
  case max(UInt16)
  case length(UInt16)
  case percentage(UInt16)
  case ratio(numerator: UInt16, denominator: UInt16)
  /// Distributes remaining space by weight. This is Ratatui's `Fill`
  /// constraint, spelled `flex` to read naturally at Swift call sites.
  case flex(UInt16)

  public static var fill: Self {
    .flex(1)
  }
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
