public enum Color: Hashable, Sendable, LosslessStringConvertible {
  case reset
  case black
  case red
  case green
  case yellow
  case blue
  case magenta
  case cyan
  case gray
  case darkGray
  case lightRed
  case lightGreen
  case lightYellow
  case lightBlue
  case lightMagenta
  case lightCyan
  case white
  case indexed(UInt8)
  case rgb(UInt8, UInt8, UInt8)

  public init?(_ description: String) {
    let normalized =
      description
      .lowercased()
      .replacingOccurrences(of: " ", with: "")
      .replacingOccurrences(of: "-", with: "")
      .replacingOccurrences(of: "_", with: "")
      .replacingOccurrences(of: "bright", with: "light")
      .replacingOccurrences(of: "grey", with: "gray")
      .replacingOccurrences(of: "silver", with: "gray")
      .replacingOccurrences(of: "lightblack", with: "darkgray")
      .replacingOccurrences(of: "lightwhite", with: "white")
      .replacingOccurrences(of: "lightgray", with: "white")
    switch normalized {
    case "reset": self = .reset
    case "black": self = .black
    case "red": self = .red
    case "green": self = .green
    case "yellow": self = .yellow
    case "blue": self = .blue
    case "magenta": self = .magenta
    case "cyan": self = .cyan
    case "gray": self = .gray
    case "darkgray": self = .darkGray
    case "lightred": self = .lightRed
    case "lightgreen": self = .lightGreen
    case "lightyellow": self = .lightYellow
    case "lightblue": self = .lightBlue
    case "lightmagenta": self = .lightMagenta
    case "lightcyan": self = .lightCyan
    case "white": self = .white
    default:
      if let index = UInt8(description) {
        self = .indexed(index)
      } else if description.count == 7, description.first == "#",
        let value = UInt32(description.dropFirst(), radix: 16)
      {
        self = .rgb(
          UInt8(truncatingIfNeeded: value >> 16),
          UInt8(truncatingIfNeeded: value >> 8),
          UInt8(truncatingIfNeeded: value)
        )
      } else {
        return nil
      }
    }
  }

  public var description: String {
    switch self {
    case .reset: "Reset"
    case .black: "Black"
    case .red: "Red"
    case .green: "Green"
    case .yellow: "Yellow"
    case .blue: "Blue"
    case .magenta: "Magenta"
    case .cyan: "Cyan"
    case .gray: "Gray"
    case .darkGray: "DarkGray"
    case .lightRed: "LightRed"
    case .lightGreen: "LightGreen"
    case .lightYellow: "LightYellow"
    case .lightBlue: "LightBlue"
    case .lightMagenta: "LightMagenta"
    case .lightCyan: "LightCyan"
    case .white: "White"
    case .indexed(let index): String(index)
    case .rgb(let red, let green, let blue):
      "#\(Self.hex(red))\(Self.hex(green))\(Self.hex(blue))"
    }
  }

  public init(rgb value: UInt32) {
    self = .rgb(
      UInt8(truncatingIfNeeded: value >> 16),
      UInt8(truncatingIfNeeded: value >> 8),
      UInt8(truncatingIfNeeded: value)
    )
  }

  private static func hex(_ value: UInt8) -> String {
    let value = String(value, radix: 16, uppercase: true)
    return value.count == 1 ? "0\(value)" : value
  }
}

public struct Modifier: OptionSet, Hashable, Sendable {
  public let rawValue: UInt16

  public init(rawValue: UInt16) {
    self.rawValue = rawValue
  }

  public static let bold = Self(rawValue: 1 << 0)
  public static let dim = Self(rawValue: 1 << 1)
  public static let italic = Self(rawValue: 1 << 2)
  public static let underlined = Self(rawValue: 1 << 3)
  public static let reversed = Self(rawValue: 1 << 4)
  public static let hidden = Self(rawValue: 1 << 5)
  public static let crossedOut = Self(rawValue: 1 << 6)
  public static let all: Self = [
    .bold, .dim, .italic, .underlined, .reversed, .hidden, .crossedOut,
  ]
}

public struct Style: Hashable, Sendable {
  private var foregroundStorage: UInt32
  private var backgroundStorage: UInt32
  private var underlineStorage: UInt32
  private var modifierStorage: UInt32

  public var modifiers: Modifier {
    get { Modifier(rawValue: UInt16(truncatingIfNeeded: modifierStorage & 0x7FFF)) }
    set { modifierStorage = (modifierStorage & 0xFFFF_8000) | UInt32(newValue.rawValue & 0x7FFF) }
  }

  public var removedModifiers: Modifier {
    get { Modifier(rawValue: UInt16(truncatingIfNeeded: (modifierStorage >> 15) & 0x7FFF)) }
    set {
      modifierStorage =
        (modifierStorage & 0xC000_7FFF) | UInt32(newValue.rawValue & 0x7FFF) << 15
    }
  }

  public var foreground: Color? {
    get { Self.color(from: foregroundStorage) }
    set { foregroundStorage = Self.storage(for: newValue) }
  }

  public var background: Color? {
    get { Self.color(from: backgroundStorage) }
    set { backgroundStorage = Self.storage(for: newValue) }
  }

  public var underlineColor: Color? {
    get { Self.color(from: underlineStorage) }
    set { underlineStorage = Self.storage(for: newValue) }
  }

  public init(
    foreground: Color? = nil,
    background: Color? = nil,
    underlineColor: Color? = nil,
    modifiers: Modifier = [],
    removedModifiers: Modifier = []
  ) {
    foregroundStorage = Self.storage(for: foreground)
    backgroundStorage = Self.storage(for: background)
    underlineStorage = Self.storage(for: underlineColor)
    modifierStorage =
      UInt32(modifiers.rawValue & 0x7FFF)
      | UInt32(removedModifiers.rawValue & 0x7FFF) << 15
  }

  public static let plain = Self()
  public static let reset = Self(
    foreground: .reset,
    background: .reset,
    underlineColor: .reset,
    removedModifiers: .all
  )

  public func foreground(_ color: Color) -> Self {
    var copy = self
    copy.foreground = color
    return copy
  }

  public func background(_ color: Color) -> Self {
    var copy = self
    copy.background = color
    return copy
  }

  public func underlineColor(_ color: Color) -> Self {
    var copy = self
    copy.underlineColor = color
    return copy
  }

  public func adding(_ modifier: Modifier) -> Self {
    var copy = self
    let bits = UInt32(modifier.rawValue & 0x7FFF)
    copy.modifierStorage |= bits
    copy.modifierStorage &= ~(bits << 15)
    return copy
  }

  public func removing(_ modifier: Modifier) -> Self {
    var copy = self
    let bits = UInt32(modifier.rawValue & 0x7FFF)
    copy.modifierStorage &= ~bits
    copy.modifierStorage |= bits << 15
    return copy
  }

  public func patching(_ other: Style) -> Self {
    var result = self
    if other.foregroundStorage != Self.noColor {
      result.foregroundStorage = other.foregroundStorage
    }
    if other.backgroundStorage != Self.noColor {
      result.backgroundStorage = other.backgroundStorage
    }
    if other.underlineStorage != Self.noColor {
      result.underlineStorage = other.underlineStorage
    }

    let modifierMask: UInt32 = 0x7FFF
    let added = modifierStorage & modifierMask
    let removed = (modifierStorage >> 15) & modifierMask
    let otherAdded = other.modifierStorage & modifierMask
    let otherRemoved = (other.modifierStorage >> 15) & modifierMask
    let resultAdded = (added & ~otherRemoved) | otherAdded
    let resultRemoved = (removed | otherRemoved) & ~otherAdded
    result.modifierStorage = resultAdded | resultRemoved << 15
    return result
  }

  private static let noColor: UInt32 = 0xFFFF_FFFF
  private static let resetColor: UInt32 = 0xFFFF_FFFE

  private static func storage(for color: Color?) -> UInt32 {
    guard let color else { return noColor }
    switch color {
    case .reset: return resetColor
    case .black: return 0
    case .red: return 1
    case .green: return 2
    case .yellow: return 3
    case .blue: return 4
    case .magenta: return 5
    case .cyan: return 6
    case .gray: return 7
    case .darkGray: return 8
    case .lightRed: return 9
    case .lightGreen: return 10
    case .lightYellow: return 11
    case .lightBlue: return 12
    case .lightMagenta: return 13
    case .lightCyan: return 14
    case .white: return 15
    case .indexed(let value): return 0x0100_0000 | UInt32(value)
    case .rgb(let red, let green, let blue):
      return 0x0200_0000 | UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue)
    }
  }

  private static func color(from storage: UInt32) -> Color? {
    switch storage {
    case noColor: return nil
    case resetColor: return .reset
    case 0: return .black
    case 1: return .red
    case 2: return .green
    case 3: return .yellow
    case 4: return .blue
    case 5: return .magenta
    case 6: return .cyan
    case 7: return .gray
    case 8: return .darkGray
    case 9: return .lightRed
    case 10: return .lightGreen
    case 11: return .lightYellow
    case 12: return .lightBlue
    case 13: return .lightMagenta
    case 14: return .lightCyan
    case 15: return .white
    default:
      switch storage & 0xFF00_0000 {
      case 0x0100_0000: return .indexed(UInt8(truncatingIfNeeded: storage))
      case 0x0200_0000:
        return .rgb(
          UInt8(truncatingIfNeeded: storage >> 16),
          UInt8(truncatingIfNeeded: storage >> 8),
          UInt8(truncatingIfNeeded: storage)
        )
      default: return nil
      }
    }
  }

  internal var cellWidthMetadata: UInt8 {
    UInt8(truncatingIfNeeded: modifierStorage >> 30)
  }

  internal func withCellWidthMetadata(_ width: UInt8) -> Self {
    var copy = self
    copy.modifierStorage =
      (copy.modifierStorage & 0x3FFF_FFFF) | UInt32(min(3, width)) << 30
    return copy
  }

  internal func clearingCellWidthMetadata() -> Self {
    var copy = self
    copy.modifierStorage &= 0x3FFF_FFFF
    return copy
  }
}

/// A value that supports Ratatui-style fluent style composition.
public protocol Stylable {
  var style: Style { get set }
}

extension Stylable {
  public func style(_ style: Style) -> Self {
    var copy = self
    copy.style = style
    return copy
  }

  public func patchStyle(_ style: Style) -> Self {
    var copy = self
    copy.style = copy.style.patching(style)
    return copy
  }

  public func resetStyle() -> Self {
    patchStyle(.reset)
  }

  public func foregroundStyle(_ color: Color) -> Self {
    patchStyle(Style(foreground: color))
  }

  public func backgroundStyle(_ color: Color) -> Self {
    patchStyle(Style(background: color))
  }

  public func underlineStyle(_ color: Color) -> Self {
    patchStyle(Style(underlineColor: color))
  }

  public func bold(_ active: Bool = true) -> Self {
    modifier(.bold, active: active)
  }

  public func dim(_ active: Bool = true) -> Self {
    modifier(.dim, active: active)
  }

  public func italic(_ active: Bool = true) -> Self {
    modifier(.italic, active: active)
  }

  public func underlined(_ active: Bool = true) -> Self {
    modifier(.underlined, active: active)
  }

  public func reversed(_ active: Bool = true) -> Self {
    modifier(.reversed, active: active)
  }

  public func hidden(_ active: Bool = true) -> Self {
    modifier(.hidden, active: active)
  }

  public func crossedOut(_ active: Bool = true) -> Self {
    modifier(.crossedOut, active: active)
  }

  private func modifier(_ modifier: Modifier, active: Bool) -> Self {
    var copy = self
    copy.style = active ? copy.style.adding(modifier) : copy.style.removing(modifier)
    return copy
  }
}
