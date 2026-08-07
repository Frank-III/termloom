public enum BorderMergeStrategy: Hashable, Sendable {
  case replace
  case exact
  case fuzzy

  public func merge(_ previous: Character, _ next: Character) -> Character {
    guard self != .replace else { return next }
    guard let previousGlyph = BorderGlyph(previous) else { return previous }
    guard let nextGlyph = BorderGlyph(next) else { return next }

    let connections = previousGlyph.connections.union(nextGlyph.connections)
    let weight: BorderWeight
    if previousGlyph.weight == nextGlyph.weight {
      weight = nextGlyph.weight
    } else if self == .fuzzy {
      weight = nextGlyph.weight
    } else {
      return next
    }

    if self == .exact,
      previousGlyph.isRounded || nextGlyph.isRounded,
      connections != nextGlyph.connections
    {
      return next
    }
    return BorderGlyph.character(for: connections, weight: weight) ?? next
  }
}

private struct BorderConnections: OptionSet, Hashable {
  let rawValue: UInt8

  static let right = Self(rawValue: 1 << 0)
  static let up = Self(rawValue: 1 << 1)
  static let left = Self(rawValue: 1 << 2)
  static let down = Self(rawValue: 1 << 3)
}

private enum BorderWeight: Hashable {
  case light
  case heavy
  case double
}

private struct BorderGlyph {
  var connections: BorderConnections
  var weight: BorderWeight
  var isRounded: Bool

  private static let light: [Character: BorderConnections] = [
    "─": [.left, .right], "│": [.up, .down],
    "┌": [.right, .down], "┐": [.left, .down],
    "└": [.right, .up], "┘": [.left, .up],
    "├": [.right, .up, .down], "┤": [.left, .up, .down],
    "┬": [.left, .right, .down], "┴": [.left, .right, .up],
    "┼": [.left, .right, .up, .down],
    "╭": [.right, .down], "╮": [.left, .down],
    "╰": [.right, .up], "╯": [.left, .up],
  ]
  private static let heavy: [Character: BorderConnections] = [
    "━": [.left, .right], "┃": [.up, .down],
    "┏": [.right, .down], "┓": [.left, .down],
    "┗": [.right, .up], "┛": [.left, .up],
    "┣": [.right, .up, .down], "┫": [.left, .up, .down],
    "┳": [.left, .right, .down], "┻": [.left, .right, .up],
    "╋": [.left, .right, .up, .down],
  ]
  private static let double: [Character: BorderConnections] = [
    "═": [.left, .right], "║": [.up, .down],
    "╔": [.right, .down], "╗": [.left, .down],
    "╚": [.right, .up], "╝": [.left, .up],
    "╠": [.right, .up, .down], "╣": [.left, .up, .down],
    "╦": [.left, .right, .down], "╩": [.left, .right, .up],
    "╬": [.left, .right, .up, .down],
  ]
  private static let rounded: Set<Character> = ["╭", "╮", "╰", "╯"]

  private init(
    connections: BorderConnections,
    weight: BorderWeight,
    isRounded: Bool
  ) {
    self.connections = connections
    self.weight = weight
    self.isRounded = isRounded
  }

  init?(_ character: Character) {
    if let connections = Self.light[character] {
      self.init(
        connections: connections,
        weight: .light,
        isRounded: Self.rounded.contains(character)
      )
    } else if let connections = Self.heavy[character] {
      self.init(connections: connections, weight: .heavy, isRounded: false)
    } else if let connections = Self.double[character] {
      self.init(connections: connections, weight: .double, isRounded: false)
    } else {
      return nil
    }
  }

  static func character(
    for connections: BorderConnections,
    weight: BorderWeight
  ) -> Character? {
    switch (connections, weight) {
    case ([.left, .right], .light): "─"
    case ([.up, .down], .light): "│"
    case ([.right, .down], .light): "┌"
    case ([.left, .down], .light): "┐"
    case ([.right, .up], .light): "└"
    case ([.left, .up], .light): "┘"
    case ([.right, .up, .down], .light): "├"
    case ([.left, .up, .down], .light): "┤"
    case ([.left, .right, .down], .light): "┬"
    case ([.left, .right, .up], .light): "┴"
    case ([.left, .right, .up, .down], .light): "┼"
    case ([.left, .right], .heavy): "━"
    case ([.up, .down], .heavy): "┃"
    case ([.right, .down], .heavy): "┏"
    case ([.left, .down], .heavy): "┓"
    case ([.right, .up], .heavy): "┗"
    case ([.left, .up], .heavy): "┛"
    case ([.right, .up, .down], .heavy): "┣"
    case ([.left, .up, .down], .heavy): "┫"
    case ([.left, .right, .down], .heavy): "┳"
    case ([.left, .right, .up], .heavy): "┻"
    case ([.left, .right, .up, .down], .heavy): "╋"
    case ([.left, .right], .double): "═"
    case ([.up, .down], .double): "║"
    case ([.right, .down], .double): "╔"
    case ([.left, .down], .double): "╗"
    case ([.right, .up], .double): "╚"
    case ([.left, .up], .double): "╝"
    case ([.right, .up, .down], .double): "╠"
    case ([.left, .up, .down], .double): "╣"
    case ([.left, .right, .down], .double): "╦"
    case ([.left, .right, .up], .double): "╩"
    case ([.left, .right, .up, .down], .double): "╬"
    default: nil
    }
  }
}
