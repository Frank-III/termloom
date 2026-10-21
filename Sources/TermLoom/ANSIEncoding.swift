/// One color slot (foreground, background, or underline) of the terminal's graphic rendition, as
/// `ANSIBackend` encodes it for its configured color profile.
struct ANSIColorCode: Hashable, Sendable {
  enum Kind: UInt8, Hashable, Sendable {
    /// The style leaves the slot unset; the full SGR form emits nothing for it.
    case unset
    /// The style requests the terminal default explicitly (`39`, `49`, or `59`).
    case explicitDefault
    /// A single SGR code such as `31` or `104`, stored in `first`.
    case basic
    /// A 256-color palette index (`38;5;n`), stored in `first`.
    case indexed
    /// A 24-bit color (`38;2;r;g;b`).
    case rgb
  }

  var kind: Kind
  var first: UInt8 = 0
  var second: UInt8 = 0
  var third: UInt8 = 0

  static let unset = Self(kind: .unset)
  static let explicitDefault = Self(kind: .explicitDefault)

  static func basic(_ code: Int) -> Self {
    Self(kind: .basic, first: UInt8(truncatingIfNeeded: code))
  }

  static func indexed(_ index: UInt8) -> Self {
    Self(kind: .indexed, first: index)
  }

  static func rgb(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Self {
    Self(kind: .rgb, first: red, second: green, third: blue)
  }

  /// Whether the slot shows the terminal's default color once a reset has been applied.
  var isTerminalDefault: Bool {
    kind == .unset || kind == .explicitDefault
  }

  /// Whether both codes leave the terminal showing the same color.
  func rendersSame(as other: Self) -> Bool {
    isTerminalDefault ? other.isTerminalDefault : self == other
  }
}

/// The terminal-visible SGR state that `ANSIBackend` establishes for one `Style`.
///
/// `attributes` uses the bit order of `Modifier`: bold, dim, italic, underlined, reversed, hidden,
/// crossed out. Only these seven attributes are ever emitted.
struct ANSIGraphicState: Hashable, Sendable {
  static let attributeCount = 7
  static let attributeMask: UInt8 = 0x7F

  var attributes: UInt8
  var foreground: ANSIColorCode
  var background: ANSIColorCode
  var underlineColor: ANSIColorCode

  /// Whether the state renders exactly like the terminal after `CSI 0 m`.
  var isTerminalDefault: Bool {
    attributes == 0 && foreground.isTerminalDefault && background.isTerminalDefault
      && underlineColor.isTerminalDefault
  }

  /// Whether both states leave the terminal rendering cells identically.
  func rendersSame(as other: Self) -> Bool {
    attributes == other.attributes
      && foreground.rendersSame(as: other.foreground)
      && background.rendersSame(as: other.background)
      && underlineColor.rendersSame(as: other.underlineColor)
  }

  /// The SGR parameter that sets the attribute at `bit`: 1, 2, 3, 4, 7, 8, 9.
  static func onCode(_ bit: Int) -> Int {
    bit < 4 ? bit + 1 : bit + 3
  }

  /// The SGR parameter that clears the attribute at `bit`: 22 (bold and dim), 23, 24, 27, 28, 29.
  static func offCode(_ bit: Int) -> Int {
    if bit < 2 { return 22 }
    return bit < 4 ? bit + 21 : bit + 23
  }
}

extension [UInt8] {
  /// Appends the UTF-8 bytes of an ASCII escape-sequence literal.
  mutating func appendANSI(_ text: StaticString) {
    text.withUTF8Buffer { bytes in
      append(contentsOf: bytes)
    }
  }

  /// Appends `value` in decimal, matching `String(value)` byte for byte.
  mutating func appendANSIDecimal(_ value: Int) {
    if value < 0 { append(0x2D) }
    appendANSIDecimal(magnitude: value.magnitude)
  }

  /// Appends an unsigned `value` in decimal without creating a `String`.
  mutating func appendANSIDecimal(magnitude value: UInt) {
    if value < 10 {
      append(0x30 &+ UInt8(truncatingIfNeeded: value))
      return
    }
    if value < 100 {
      append(0x30 &+ UInt8(truncatingIfNeeded: value / 10))
      append(0x30 &+ UInt8(truncatingIfNeeded: value % 10))
      return
    }
    var digitCount = 1
    var probe = value
    while probe >= 10 {
      probe /= 10
      digitCount += 1
    }
    let start = count
    append(contentsOf: repeatElement(UInt8(0x30), count: digitCount))
    var remaining = value
    var index = start + digitCount - 1
    while remaining > 0 {
      self[index] = 0x30 &+ UInt8(truncatingIfNeeded: remaining % 10)
      remaining /= 10
      index -= 1
    }
  }

  /// Appends one SGR parameter, preceded by `;` unless it is the first in the sequence.
  mutating func appendSGRParameter(_ value: Int, isFirst: inout Bool) {
    if isFirst {
      isFirst = false
    } else {
      append(0x3B)
    }
    appendANSIDecimal(value)
  }

  /// Appends the parameters selecting `color` for a slot whose base is 30 (foreground),
  /// 40 (background), or 50 (underline): `base + 8` introduces extended colors and `base + 9`
  /// selects the default. An unset color appends nothing.
  mutating func appendSGRColor(_ color: ANSIColorCode, base: Int, isFirst: inout Bool) {
    switch color.kind {
    case .unset:
      return
    case .explicitDefault:
      appendSGRParameter(base + 9, isFirst: &isFirst)
    case .basic:
      appendSGRParameter(Int(color.first), isFirst: &isFirst)
    case .indexed:
      appendSGRParameter(base + 8, isFirst: &isFirst)
      appendSGRParameter(5, isFirst: &isFirst)
      appendSGRParameter(Int(color.first), isFirst: &isFirst)
    case .rgb:
      appendSGRParameter(base + 8, isFirst: &isFirst)
      appendSGRParameter(2, isFirst: &isFirst)
      appendSGRParameter(Int(color.first), isFirst: &isFirst)
      appendSGRParameter(Int(color.second), isFirst: &isFirst)
      appendSGRParameter(Int(color.third), isFirst: &isFirst)
    }
  }

  /// Appends the reset-and-set form `CSI 0;… m` that establishes `state` from any prior state.
  mutating func appendFullSGR(_ state: ANSIGraphicState) {
    appendANSI("\u{1B}[0")
    var isFirst = false
    for bit in 0..<ANSIGraphicState.attributeCount {
      let mask: UInt8 = 1 << bit
      if state.attributes & mask != 0 {
        appendSGRParameter(ANSIGraphicState.onCode(bit), isFirst: &isFirst)
      }
    }
    appendSGRColor(state.foreground, base: 30, isFirst: &isFirst)
    appendSGRColor(state.background, base: 40, isFirst: &isFirst)
    appendSGRColor(state.underlineColor, base: 50, isFirst: &isFirst)
    append(0x6D)
  }

  /// Appends the shortest of two SGR sequences that move the terminal from `current` to `target`:
  /// the changed attributes only, or the full reset-and-set form. Appends nothing when both states
  /// render the same. A target that renders like the terminal default always uses the full form.
  mutating func appendSGRTransition(
    from current: ANSIGraphicState,
    to target: ANSIGraphicState
  ) {
    if target.rendersSame(as: current) { return }
    if target.isTerminalDefault {
      appendFullSGR(target)
      return
    }
    let start = count
    appendANSI("\u{1B}[")
    var isFirst = true
    let removed = current.attributes & ~target.attributes
    var added = target.attributes & ~current.attributes
    if removed & 0b11 != 0 {
      // SGR 22 clears both bold and dim; restore whichever the target keeps.
      appendSGRParameter(22, isFirst: &isFirst)
      added |= target.attributes & 0b11
    }
    for bit in 2..<ANSIGraphicState.attributeCount {
      let mask: UInt8 = 1 << bit
      if removed & mask != 0 {
        appendSGRParameter(ANSIGraphicState.offCode(bit), isFirst: &isFirst)
      }
    }
    for bit in 0..<ANSIGraphicState.attributeCount {
      let mask: UInt8 = 1 << bit
      if added & mask != 0 {
        appendSGRParameter(ANSIGraphicState.onCode(bit), isFirst: &isFirst)
      }
    }
    appendSGRColorChange(
      from: current.foreground, to: target.foreground, base: 30, isFirst: &isFirst)
    appendSGRColorChange(
      from: current.background, to: target.background, base: 40, isFirst: &isFirst)
    appendSGRColorChange(
      from: current.underlineColor, to: target.underlineColor, base: 50, isFirst: &isFirst)
    append(0x6D)

    let differenceEnd = count
    appendFullSGR(target)
    let fullLength = count - differenceEnd
    if differenceEnd - start < fullLength {
      removeLast(fullLength)
    } else {
      removeSubrange(start..<differenceEnd)
    }
  }

  private mutating func appendSGRColorChange(
    from current: ANSIColorCode,
    to target: ANSIColorCode,
    base: Int,
    isFirst: inout Bool
  ) {
    if target.rendersSame(as: current) { return }
    appendSGRColor(
      target.isTerminalDefault ? .explicitDefault : target, base: base, isFirst: &isFirst)
  }
}
