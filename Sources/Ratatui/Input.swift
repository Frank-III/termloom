import Foundation

public struct KeyModifiers: OptionSet, Hashable, Sendable {
  public let rawValue: UInt16

  public init(rawValue: UInt16) {
    self.rawValue = rawValue
  }

  public static let shift = Self(rawValue: 1 << 0)
  public static let control = Self(rawValue: 1 << 1)
  public static let option = Self(rawValue: 1 << 2)
  public static let command = Self(rawValue: 1 << 3)
  public static let hyper = Self(rawValue: 1 << 4)
  public static let meta = Self(rawValue: 1 << 5)
  public static let capsLock = Self(rawValue: 1 << 6)
  public static let numLock = Self(rawValue: 1 << 7)
}

public enum KeyEventKind: Hashable, Sendable {
  case press
  case `repeat`
  case release
}

public struct KeyboardEnhancementFlags: OptionSet, Hashable, Sendable {
  public let rawValue: UInt8

  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  public static let disambiguateEscapeCodes = Self(rawValue: 1 << 0)
  public static let reportEventKinds = Self(rawValue: 1 << 1)
  public static let reportAlternateKeys = Self(rawValue: 1 << 2)
  public static let reportAllKeys = Self(rawValue: 1 << 3)
  public static let reportAssociatedText = Self(rawValue: 1 << 4)
}

public enum TerminalDeviceAttributeKind: Hashable, Sendable {
  case primary
  case secondary
}

public struct TerminalDeviceAttributes: Hashable, Sendable {
  public var kind: TerminalDeviceAttributeKind
  public var parameters: [UInt16]

  public init(_ kind: TerminalDeviceAttributeKind, parameters: [UInt16]) {
    self.kind = kind
    self.parameters = parameters
  }
}

public enum TerminalModeStatus: UInt16, Hashable, Sendable {
  case notRecognized = 0
  case set = 1
  case reset = 2
  case permanentlySet = 3
  case permanentlyReset = 4
}

public struct TerminalModeReport: Hashable, Sendable {
  public var mode: UInt16
  public var status: TerminalModeStatus
  public var isPrivate: Bool

  public init(mode: UInt16, status: TerminalModeStatus, isPrivate: Bool) {
    self.mode = mode
    self.status = status
    self.isPrivate = isPrivate
  }
}

public enum Key: Hashable, Sendable {
  case character(Character)
  case enter
  case escape
  case tab
  case backspace
  case delete
  case insert
  case up
  case down
  case left
  case right
  case home
  case end
  case pageUp
  case pageDown
  case function(Int)
  case capsLock
  case scrollLock
  case numLock
  case printScreen
  case pause
  case menu
  case keypad(KeypadKey)
  case media(MediaKey)
  case unidentified(UInt32)
}

public enum KeypadKey: Hashable, Sendable {
  case digit(UInt8)
  case decimal
  case divide
  case multiply
  case subtract
  case add
  case enter
  case equal
  case separator
  case left
  case right
  case up
  case down
  case pageUp
  case pageDown
  case home
  case end
  case insert
  case delete
  case begin
}

public enum MediaKey: Hashable, Sendable {
  case play
  case pause
  case playPause
  case reverse
  case stop
  case fastForward
  case rewind
  case nextTrack
  case previousTrack
  case record
  case lowerVolume
  case raiseVolume
  case mute
}

public struct KeyEvent: Hashable, Sendable {
  public var key: Key
  public var modifiers: KeyModifiers
  public var kind: KeyEventKind
  public var text: String?

  public init(
    _ key: Key,
    modifiers: KeyModifiers = [],
    kind: KeyEventKind = .press,
    text: String? = nil
  ) {
    self.key = key
    self.modifiers = modifiers
    self.kind = kind
    self.text = text
  }
}

public enum MouseButton: Hashable, Sendable {
  case left
  case middle
  case right
}

public enum MouseEventKind: Hashable, Sendable {
  case down(MouseButton)
  case up(MouseButton?)
  case drag(MouseButton)
  case moved
  case scrollUp
  case scrollDown
}

public struct MouseEvent: Hashable, Sendable {
  public var kind: MouseEventKind
  public var position: Position
  public var modifiers: KeyModifiers

  public init(
    _ kind: MouseEventKind,
    at position: Position,
    modifiers: KeyModifiers = []
  ) {
    self.kind = kind
    self.position = position
    self.modifiers = modifiers
  }
}

public enum TerminalEvent: Hashable, Sendable {
  case key(KeyEvent)
  case mouse(MouseEvent)
  case paste(String)
  case resize(Size)
  case terminalFocus(Bool)
  case keyboardEnhancementFlags(KeyboardEnhancementFlags)
  case deviceAttributes(TerminalDeviceAttributes)
  case cursorPositionReport(Position)
  case terminalModeReport(TerminalModeReport)
  case action(ActionID)
  case focusChanged(ControlID?)
  case endOfInput
}

/// Turns arbitrarily chunked terminal input bytes into semantic events.
public struct InputParser: Sendable {
  private var bytes: [UInt8] = []
  private var readIndex = 0

  public init() {}

  public mutating func feed(_ data: Data) -> [TerminalEvent] {
    bytes.append(contentsOf: data)
    var events: [TerminalEvent] = []
    while let parsed = parseOne() {
      readIndex += parsed.consumed
      if let event = parsed.event {
        events.append(event)
      }
    }
    compact()
    return events
  }

  /// Resolves a lone Escape byte after the caller's escape-sequence timeout expires.
  public mutating func flushEscape() -> TerminalEvent? {
    guard bytes.count - readIndex == 1, bytes[readIndex] == 0x1B else { return nil }
    readIndex += 1
    compact()
    return .key(KeyEvent(.escape))
  }

  private mutating func parseOne() -> (consumed: Int, event: TerminalEvent?)? {
    let available = bytes.count - readIndex
    guard available > 0 else { return nil }

    let pasteStart: [UInt8] = [0x1B, 0x5B, 0x32, 0x30, 0x30, 0x7E]
    let pasteEnd: [UInt8] = [0x1B, 0x5B, 0x32, 0x30, 0x31, 0x7E]
    if matches(pasteStart, at: readIndex) {
      guard let end = find(pasteEnd, after: readIndex + pasteStart.count) else { return nil }
      let contentStart = readIndex + pasteStart.count
      let content = String(decoding: bytes[contentStart..<end], as: UTF8.self)
      return (end + pasteEnd.count - readIndex, .paste(content))
    }

    let first = bytes[readIndex]
    if first == 0x1B {
      guard available > 1 else { return nil }
      let second = bytes[readIndex + 1]
      if second == 0x7F || second == 0x08 {
        return (2, .key(KeyEvent(.backspace, modifiers: [.option])))
      }
      if second == 0x5B || second == 0x4F {
        guard let final = escapeSequenceEnd(startingAt: readIndex + 2) else { return nil }
        let sequence = Array(bytes[readIndex...final])
        return (sequence.count, parseEscapeSequence(sequence))
      }

      let length = utf8Length(of: second)
      guard available >= length + 1 else { return nil }
      let characterBytes = bytes[(readIndex + 1)..<(readIndex + 1 + length)]
      guard let character = String(decoding: characterBytes, as: UTF8.self).first else {
        return (length + 1, nil)
      }
      return (
        length + 1,
        .key(KeyEvent(.character(character), modifiers: [.option]))
      )
    }

    if let event = parseControl(first) {
      return (1, .key(event))
    }

    let length = utf8Length(of: first)
    guard available >= length else { return nil }
    let characterBytes = bytes[readIndex..<(readIndex + length)]
    guard let character = String(decoding: characterBytes, as: UTF8.self).first else {
      return (length, nil)
    }
    let isUppercase = String(character) != String(character).lowercased()
    return (
      length,
      .key(KeyEvent(.character(character), modifiers: isUppercase ? [.shift] : []))
    )
  }

  private func parseControl(_ byte: UInt8) -> KeyEvent? {
    switch byte {
    case 0x0D: return KeyEvent(.enter)
    case 0x09: return KeyEvent(.tab)
    case 0x7F, 0x08: return KeyEvent(.backspace)
    case 0x01...0x1A:
      return KeyEvent(
        .character(Character(UnicodeScalar(byte + 0x60))),
        modifiers: [.control]
      )
    default: return nil
    }
  }

  private func parseEscapeSequence(_ sequence: [UInt8]) -> TerminalEvent? {
    guard sequence.count >= 3, let final = sequence.last else { return nil }
    let isCSI = sequence[1] == 0x5B
    let parameters = isCSI ? Array(sequence.dropFirst(2).dropLast()) : []
    if isCSI, parameters.first == 0x3C, final == 0x4D || final == 0x6D {
      return parseMouse(parameters.dropFirst(), isRelease: final == 0x6D)
    }
    if isCSI, parameters.isEmpty, final == 0x49 { return .terminalFocus(true) }
    if isCSI, parameters.isEmpty, final == 0x4F { return .terminalFocus(false) }
    if isCSI, parameters.first == 0x3F, final == 0x75 {
      let value = UInt8(String(decoding: parameters.dropFirst(), as: UTF8.self)) ?? 0
      return .keyboardEnhancementFlags(KeyboardEnhancementFlags(rawValue: value))
    }
    if isCSI, final == 0x63, let prefix = parameters.first,
      prefix == 0x3F || prefix == 0x3E
    {
      let kind: TerminalDeviceAttributeKind = prefix == 0x3F ? .primary : .secondary
      let values = String(decoding: parameters.dropFirst(), as: UTF8.self)
        .split(separator: ";", omittingEmptySubsequences: false)
        .compactMap { UInt16($0) }
      return .deviceAttributes(TerminalDeviceAttributes(kind, parameters: values))
    }
    if isCSI, final == 0x52 {
      let values = String(decoding: parameters, as: UTF8.self)
        .split(separator: ";", omittingEmptySubsequences: false)
        .compactMap { UInt16($0) }
      if values.count == 2, values[0] > 0, values[1] > 0 {
        return .cursorPositionReport(Position(x: values[1] - 1, y: values[0] - 1))
      }
    }
    if isCSI, final == 0x79, parameters.last == 0x24 {
      let privateMode = parameters.first == 0x3F
      let fields = String(
        decoding: parameters.dropFirst(privateMode ? 1 : 0).dropLast(),
        as: UTF8.self
      ).split(separator: ";", omittingEmptySubsequences: false)
      if fields.count == 2,
        let mode = UInt16(fields[0]),
        let rawStatus = UInt16(fields[1]),
        let status = TerminalModeStatus(rawValue: rawStatus)
      {
        return .terminalModeReport(
          TerminalModeReport(mode: mode, status: status, isPrivate: privateMode)
        )
      }
    }
    if isCSI, final == 0x75 { return parseKittyKey(parameters) }
    var modifiers: KeyModifiers = []

    if final == 0x5A {
      modifiers.insert(.shift)
    } else if let separator = parameters.lastIndex(of: 0x3B) {
      let modifierBytes = parameters[(separator + 1)...]
      if let encoded = Int(String(decoding: modifierBytes, as: UTF8.self)) {
        let bits = max(0, encoded - 1)
        if bits & 1 != 0 { modifiers.insert(.shift) }
        if bits & 2 != 0 { modifiers.insert(.option) }
        if bits & 4 != 0 { modifiers.insert(.control) }
      }
    }

    let key: Key?
    switch final {
    case 0x41: key = .up
    case 0x42: key = .down
    case 0x43: key = .right
    case 0x44: key = .left
    case 0x48: key = .home
    case 0x46: key = .end
    case 0x5A: key = .tab
    case 0x50: key = .function(1)
    case 0x51: key = .function(2)
    case 0x52: key = .function(3)
    case 0x53: key = .function(4)
    case 0x7E: key = tildeKey(parameters)
    default: key = nil
    }
    return key.map { .key(KeyEvent($0, modifiers: modifiers)) }
  }

  private func parseKittyKey(_ parameters: [UInt8]) -> TerminalEvent? {
    let fields = String(decoding: parameters, as: UTF8.self)
      .split(separator: ";", omittingEmptySubsequences: false)
    guard let keyField = fields.first,
      let keyCode = UInt32(keyField.split(separator: ":", omittingEmptySubsequences: false)[0])
    else { return nil }

    let modifierFields =
      fields.count > 1
      ? fields[1].split(separator: ":", omittingEmptySubsequences: false) : []
    let encodedModifiers = modifierFields.first.flatMap { Int($0) } ?? 1
    let eventCode = modifierFields.count > 1 ? Int(modifierFields[1]) ?? 1 : 1
    let kind: KeyEventKind
    switch eventCode {
    case 2: kind = .repeat
    case 3: kind = .release
    default: kind = .press
    }

    let modifierBits = max(0, encodedModifiers - 1)
    var modifiers: KeyModifiers = []
    if modifierBits & 1 != 0 { modifiers.insert(.shift) }
    if modifierBits & 2 != 0 { modifiers.insert(.option) }
    if modifierBits & 4 != 0 { modifiers.insert(.control) }
    if modifierBits & 8 != 0 { modifiers.insert(.command) }
    if modifierBits & 16 != 0 { modifiers.insert(.hyper) }
    if modifierBits & 32 != 0 { modifiers.insert(.meta) }
    if modifierBits & 64 != 0 { modifiers.insert(.capsLock) }
    if modifierBits & 128 != 0 { modifiers.insert(.numLock) }

    let text: String?
    if fields.count > 2 {
      let scalars = fields[2].split(separator: ":").compactMap { field in
        UInt32(field).flatMap(UnicodeScalar.init)
      }
      text = scalars.isEmpty ? nil : String(String.UnicodeScalarView(scalars))
    } else {
      text = nil
    }
    return .key(
      KeyEvent(
        kittyKey(code: keyCode),
        modifiers: modifiers,
        kind: kind,
        text: text
      )
    )
  }

  private func kittyKey(code: UInt32) -> Key {
    switch code {
    case 9: return .tab
    case 13: return .enter
    case 27: return .escape
    case 127: return .backspace
    case 57344: return .escape
    case 57345: return .enter
    case 57346: return .tab
    case 57347: return .backspace
    case 57348: return .insert
    case 57349: return .delete
    case 57350: return .left
    case 57351: return .right
    case 57352: return .up
    case 57353: return .down
    case 57354: return .pageUp
    case 57355: return .pageDown
    case 57356: return .home
    case 57357: return .end
    case 57358: return .capsLock
    case 57359: return .scrollLock
    case 57360: return .numLock
    case 57361: return .printScreen
    case 57362: return .pause
    case 57363: return .menu
    case 57364...57398: return .function(Int(code - 57364) + 1)
    case 57399...57408: return .keypad(.digit(UInt8(code - 57399)))
    case 57409: return .keypad(.decimal)
    case 57410: return .keypad(.divide)
    case 57411: return .keypad(.multiply)
    case 57412: return .keypad(.subtract)
    case 57413: return .keypad(.add)
    case 57414: return .keypad(.enter)
    case 57415: return .keypad(.equal)
    case 57416: return .keypad(.separator)
    case 57417: return .keypad(.left)
    case 57418: return .keypad(.right)
    case 57419: return .keypad(.up)
    case 57420: return .keypad(.down)
    case 57421: return .keypad(.pageUp)
    case 57422: return .keypad(.pageDown)
    case 57423: return .keypad(.home)
    case 57424: return .keypad(.end)
    case 57425: return .keypad(.insert)
    case 57426: return .keypad(.delete)
    case 57427: return .keypad(.begin)
    case 57428: return .media(.play)
    case 57429: return .media(.pause)
    case 57430: return .media(.playPause)
    case 57431: return .media(.reverse)
    case 57432: return .media(.stop)
    case 57433: return .media(.fastForward)
    case 57434: return .media(.rewind)
    case 57435: return .media(.nextTrack)
    case 57436: return .media(.previousTrack)
    case 57437: return .media(.record)
    case 57438: return .media(.lowerVolume)
    case 57439: return .media(.raiseVolume)
    case 57440: return .media(.mute)
    case 0...0x10_FFFF:
      return UnicodeScalar(code).map { .character(Character(String($0))) } ?? .unidentified(code)
    default:
      return .unidentified(code)
    }
  }

  private func parseMouse(
    _ parameterBytes: ArraySlice<UInt8>,
    isRelease: Bool
  ) -> TerminalEvent? {
    let values = String(decoding: parameterBytes, as: UTF8.self)
      .split(separator: ";")
      .compactMap { Int($0) }
    guard values.count == 3, values[1] > 0, values[2] > 0 else { return nil }
    let code = values[0]
    var modifiers: KeyModifiers = []
    if code & 4 != 0 { modifiers.insert(.shift) }
    if code & 8 != 0 { modifiers.insert(.option) }
    if code & 16 != 0 { modifiers.insert(.control) }

    let button: MouseButton?
    switch code & 3 {
    case 0: button = .left
    case 1: button = .middle
    case 2: button = .right
    default: button = nil
    }

    let kind: MouseEventKind
    if code & 64 != 0 {
      kind = code & 1 == 0 ? .scrollUp : .scrollDown
    } else if isRelease {
      kind = .up(button)
    } else if code & 32 != 0 {
      kind = button.map(MouseEventKind.drag) ?? .moved
    } else if let button {
      kind = .down(button)
    } else {
      return nil
    }

    return .mouse(
      MouseEvent(
        kind,
        at: Position(
          x: UInt16(clamping: values[1] - 1),
          y: UInt16(clamping: values[2] - 1)
        ),
        modifiers: modifiers
      )
    )
  }

  private func tildeKey(_ parameters: [UInt8]) -> Key? {
    let first = parameters.split(separator: 0x3B).first ?? []
    switch Int(String(decoding: first, as: UTF8.self)) {
    case 1, 7: return .home
    case 2: return .insert
    case 3: return .delete
    case 4, 8: return .end
    case 5: return .pageUp
    case 6: return .pageDown
    case 11: return .function(1)
    case 12: return .function(2)
    case 13: return .function(3)
    case 14: return .function(4)
    case 15: return .function(5)
    case 17: return .function(6)
    case 18: return .function(7)
    case 19: return .function(8)
    case 20: return .function(9)
    case 21: return .function(10)
    case 23: return .function(11)
    case 24: return .function(12)
    default: return nil
    }
  }

  private func escapeSequenceEnd(startingAt start: Int) -> Int? {
    guard start < bytes.count else { return nil }
    return (start..<bytes.count).first { (0x40...0x7E).contains(bytes[$0]) }
  }

  private func matches(_ pattern: [UInt8], at index: Int) -> Bool {
    guard index + pattern.count <= bytes.count else { return false }
    return pattern.indices.allSatisfy { bytes[index + $0] == pattern[$0] }
  }

  private func find(_ pattern: [UInt8], after start: Int) -> Int? {
    guard bytes.count >= pattern.count, start <= bytes.count - pattern.count else { return nil }
    return (start...(bytes.count - pattern.count)).first { matches(pattern, at: $0) }
  }

  private func utf8Length(of byte: UInt8) -> Int {
    switch byte {
    case 0x00...0x7F: return 1
    case 0xC0...0xDF: return 2
    case 0xE0...0xEF: return 3
    case 0xF0...0xF7: return 4
    default: return 1
    }
  }

  private mutating func compact() {
    guard readIndex > 0 else { return }
    bytes.removeFirst(readIndex)
    readIndex = 0
  }
}
