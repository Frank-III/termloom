import Foundation
import Testing

@testable import TermLoom

/// `ANSIBackend.draw` writes escape sequences straight into a byte buffer and emits SGR changes as
/// a difference from the previous style. These tests prove that a terminal ends up in exactly the
/// state the previous implementation produced: `ANSIReferenceEmitter` below is a verbatim copy of
/// that implementation, and `VirtualTerminal` applies both outputs to a virtual screen (characters,
/// per-cell rendition, cursor, saved cursor, current rendition, private modes).
@Suite struct ANSIOutputEquivalenceTests {
  static let configurations: [ANSIBackendConfiguration] = {
    var result: [ANSIBackendConfiguration] = []
    for profile in [ANSIColorProfile.trueColor, .indexed256, .ansi16] {
      for underlineColor in [true, false] {
        for synchronized in [true, false] {
          result.append(
            ANSIBackendConfiguration(
              colorProfile: profile,
              supportsUnderlineColor: underlineColor,
              supportsSynchronizedOutput: synchronized))
        }
      }
    }
    return result
  }()

  static let addressings: [CursorAddressing] = [
    .absolute,
    .savedOrigin,
    .savedBottom(viewportHeight: 6),
    .absoluteOrigin(Position(x: 3, y: 2)),
  ]

  // MARK: Equivalence

  @Test func randomFramesRenderIdenticallyToTheReferenceEmitter() throws {
    var generator = ANSIOutputGenerator(seed: 0x5EED_0004)
    let area = Rect(x: 0, y: 0, width: 14, height: 6)
    for trial in 0..<720 {
      let configuration = Self.configurations[trial % Self.configurations.count]
      let addressing =
        Self.addressings[(trial / Self.configurations.count) % Self.addressings.count]
      let palette = (0..<4).map { _ in generator.style() }
      let previous = generator.buffer(area: area, palette: palette)
      let next = generator.mutated(previous, palette: palette)
      let frames = [
        allUpdates(of: previous),
        next.diff(from: previous),
        generator.randomUpdates(area: area, palette: palette),
        allUpdates(of: next),
      ]
      let matches = try rendersIdentically(
        frames,
        configuration: configuration,
        addressing: addressing,
        initialRendition: generator.rendition(),
        label: "trial \(trial)")
      if !matches { return }
    }
  }

  @Test func benchmarkScenariosRenderIdenticallyAndNeverGrow() throws {
    for configuration in Self.configurations {
      let isFull = configuration == .full
      for scenario in ANSIOutputScenario.all {
        let updates = scenario.updates(width: isFull ? 120 : 60, height: isFull ? 40 : 12)
        let matches = try rendersIdentically(
          [updates, updates],
          configuration: configuration,
          addressing: .absolute,
          initialRendition: VirtualRendition(),
          label: "\(scenario.name) \(configuration)")
        if !matches { return }
      }
    }
  }

  @Test func styleChurnIsStrictlyShorterThanTheReferenceEmitter() throws {
    for scenario in ANSIOutputScenario.all where scenario.changesStyle {
      let updates = scenario.updates(width: 120, height: 40)
      let reference = ANSIReferenceEmitter(configuration: .full, cursorAddressing: .absolute)
      let oldBytes = reference.draw(updates)
      let newBytes = try drawnBytes(updates, configuration: .full, addressing: .absolute)
      #expect(newBytes.count < oldBytes.count, "\(scenario.name)")
    }
  }

  @Test func constantStyleOutputIsByteIdenticalToTheReferenceEmitter() throws {
    for configuration in Self.configurations {
      for addressing in Self.addressings {
        let updates = ANSIOutputScenario.constantStyle.updates(width: 20, height: 4)
        let reference = ANSIReferenceEmitter(
          configuration: configuration, cursorAddressing: addressing)
        let newBytes = try drawnBytes(updates, configuration: configuration, addressing: addressing)
        #expect(newBytes == reference.draw(updates))
      }
    }
  }

  // MARK: Runs and transitions

  @Test func runsOfOneStyleEmitNoSGRBetweenCells() throws {
    let style = Style(
      foreground: .rgb(1, 2, 3),
      background: .indexed(200),
      underlineColor: .red,
      modifiers: [.bold, .italic, .underlined])
    let updates = (0..<20).map { column in
      CellUpdate(
        position: Position(x: column, y: 0),
        cell: Cell(symbol: column.isMultiple(of: 2) ? "a" : "b", style: style))
    }
    let bytes = try drawnBytes(updates, configuration: .full, addressing: .absolute)
    let prefix = "\u{1B}[?2026h\u{1B}[1;1H\u{1B}[0;1;3;4;38;2;1;2;3;48;5;200;58;5;1m"
    let suffix = "abababababababababab\u{1B}[0m\u{1B}[?2026l"
    #expect(String(decoding: bytes, as: UTF8.self) == prefix + suffix)
  }

  @Test func stylesThatRenderTheSameEmitNoSGRBetweenCells() throws {
    // Each pair differs as a `Style` but selects the same terminal rendition.
    let pairs: [(Style, Style)] = [
      (Style(foreground: .red), Style(foreground: .red, background: .reset)),
      (Style(modifiers: [.bold]), Style(modifiers: [.bold]).removing(.italic)),
      (
        Style(foreground: .blue, underlineColor: .green),
        Style(foreground: .blue, underlineColor: .reset)
      ),
    ]
    for (index, pair) in pairs.enumerated() {
      var configuration = ANSIBackendConfiguration.full
      if index == 2 { configuration.supportsUnderlineColor = false }
      let bytes = try drawnBytes(
        twoCells(pair.0, pair.1), configuration: configuration, addressing: .absolute)
      let sequences = sgrParameters(in: bytes)
      #expect(sequences.count == 2, "pair \(index): \(sequences)")
      #expect(sequences.last == "0")
    }
  }

  @Test func styleChangesEmitOnlyTheChangedAttributes() throws {
    let cases = [
      TransitionCase(.plain, Style(foreground: .red), "31"),
      TransitionCase(
        Style(foreground: .red, modifiers: [.bold]),
        Style(foreground: .blue, modifiers: [.bold]),
        "34"),
      TransitionCase(
        Style(foreground: .rgb(10, 20, 30), modifiers: [.bold, .italic]),
        Style(foreground: .rgb(10, 20, 30), modifiers: [.italic]),
        "22"),
      TransitionCase(
        Style(foreground: .rgb(10, 20, 30), modifiers: [.bold, .dim]),
        Style(foreground: .rgb(10, 20, 30), modifiers: [.dim]),
        "22;2"),
      TransitionCase(
        Style(background: .indexed(100), modifiers: [.italic, .underlined]),
        Style(background: .indexed(100), modifiers: [.italic]),
        "24"),
      TransitionCase(
        Style(foreground: .rgb(5, 5, 5), modifiers: [.reversed, .hidden, .crossedOut]),
        Style(foreground: .rgb(5, 5, 5), modifiers: [.hidden]),
        "27;29"),
      TransitionCase(
        Style(foreground: .indexed(196), underlineColor: .rgb(1, 1, 1), modifiers: [.underlined]),
        Style(foreground: .indexed(196), underlineColor: .rgb(2, 2, 2), modifiers: [.underlined]),
        "58;2;2;2;2"),
      TransitionCase(
        Style(foreground: .rgb(10, 20, 30), background: .rgb(1, 2, 3)),
        Style(foreground: .rgb(10, 20, 31), background: .reset),
        "38;2;10;20;31;49"),
      // The full form is used when it is not longer than the difference.
      TransitionCase(Style(foreground: .rgb(1, 2, 3)), Style(modifiers: [.bold]), "0;1"),
      TransitionCase(
        Style(modifiers: [.reversed, .hidden, .crossedOut]),
        Style(modifiers: [.hidden]),
        "0;8"),
      TransitionCase(
        Style(foreground: .lightRed, background: .lightBlue, underlineColor: .white),
        Style(foreground: .gray, background: .darkGray),
        "0;37;100"),
      // A target that renders like the terminal default keeps today's reset form.
      TransitionCase(
        Style(foreground: .red, underlineColor: .indexed(42), modifiers: [.underlined]),
        Style(foreground: .reset, background: .reset, underlineColor: .reset),
        "0;39;49;59"),
      TransitionCase(Style(foreground: .cyan, modifiers: [.bold]), .plain, "0"),
    ]
    for transition in cases {
      let bytes = try drawnBytes(
        twoCells(transition.from, transition.to), configuration: .full, addressing: .absolute)
      let sequences = sgrParameters(in: bytes)
      #expect(sequences.count == 3, "\(sequences)")
      #expect(sequences.dropFirst().first == transition.expected, "\(transition): \(sequences)")
    }
  }

  @Test func decimalSerializationMatchesStringConversion() {
    var values = [
      0, 1, 9, 10, 11, 99, 100, 101, 255, 999, 1_000, 65_535, 1_000_000, -1, -9, -10, -100,
      Int.max, Int.min, Int.max - 1, Int.min + 1,
    ]
    var generator = ANSIOutputGenerator(seed: 7)
    for _ in 0..<1_000 {
      values.append(Int(truncatingIfNeeded: generator.next()) >> Int(generator.next() % 64))
    }
    for value in values {
      var bytes: [UInt8] = [0x41]
      bytes.appendANSIDecimal(value)
      #expect(bytes == [0x41] + Array(String(value).utf8), "\(value)")
    }
  }

  @Test func outputBufferIsReusedWithoutLeakingPreviousFrames() throws {
    let sink = ANSIOutputSink()
    var backend = ANSIBackend(fallbackSize: Size(width: 10, height: 2))
    backend.outputWriter = sink.write
    try backend.draw(twoCells(Style(foreground: .red), Style(foreground: .blue)))
    try backend.draw([CellUpdate(position: Position(x: 4, y: 1), cell: Cell(symbol: "z"))])
    #expect(sink.writes.count == 2)
    let last = String(decoding: sink.writes.last ?? Data(), as: UTF8.self)
    #expect(last == "\u{1B}[?2026h\u{1B}[2;5H\u{1B}[0mz\u{1B}[0m\u{1B}[?2026l")
  }

  // MARK: Helpers

  private struct TransitionCase {
    var from: Style
    var to: Style
    var expected: String

    init(_ from: Style, _ to: Style, _ expected: String) {
      self.from = from
      self.to = to
      self.expected = expected
    }
  }

  private func twoCells(_ first: Style, _ second: Style) -> [CellUpdate] {
    [
      CellUpdate(position: Position(x: 0, y: 0), cell: Cell(symbol: "A", style: first)),
      CellUpdate(position: Position(x: 1, y: 0), cell: Cell(symbol: "B", style: second)),
    ]
  }

  private func drawnBytes(
    _ updates: [CellUpdate],
    configuration: ANSIBackendConfiguration,
    addressing: CursorAddressing
  ) throws -> [UInt8] {
    let sink = ANSIOutputSink()
    var backend = ANSIBackend(
      fallbackSize: Size(width: 200, height: 60),
      cursorAddressing: addressing,
      configuration: configuration)
    backend.outputWriter = sink.write
    try backend.draw(updates)
    return sink.writes.reduce(into: [UInt8]()) { $0.append(contentsOf: $1) }
  }

  /// Draws `frames` one after another with both emitters on one backend each, applies the output
  /// to two virtual terminals and compares them after every frame. Also checks that the new output
  /// is never longer than the reference output.
  private func rendersIdentically(
    _ frames: [[CellUpdate]],
    configuration: ANSIBackendConfiguration,
    addressing: CursorAddressing,
    initialRendition: VirtualRendition,
    label: String
  ) throws -> Bool {
    let reference = ANSIReferenceEmitter(
      configuration: configuration, cursorAddressing: addressing)
    let sink = ANSIOutputSink()
    var backend = ANSIBackend(
      fallbackSize: Size(width: 200, height: 60),
      cursorAddressing: addressing,
      configuration: configuration)
    backend.outputWriter = sink.write
    var oldTerminal = VirtualTerminal(
      savedCursor: Position(x: 0, y: 10), rendition: initialRendition)
    var newTerminal = oldTerminal
    for (index, updates) in frames.enumerated() {
      let oldBytes = reference.draw(updates)
      sink.writes.removeAll()
      try backend.draw(updates)
      let newBytes = sink.writes.reduce(into: [UInt8]()) { $0.append(contentsOf: $1) }
      try oldTerminal.apply(oldBytes)
      try newTerminal.apply(newBytes)
      #expect(newBytes.count <= oldBytes.count, "\(label) frame \(index)")
      #expect(oldTerminal == newTerminal, "\(label) frame \(index)")
      if newBytes.count > oldBytes.count || oldTerminal != newTerminal { return false }
    }
    return true
  }

  private func allUpdates(of buffer: Buffer) -> [CellUpdate] {
    var updates: [CellUpdate] = []
    for y in buffer.area.y..<(buffer.area.y + buffer.area.height) {
      for x in buffer.area.x..<(buffer.area.x + buffer.area.width) {
        let position = Position(x: x, y: y)
        updates.append(CellUpdate(position: position, cell: buffer[position]))
      }
    }
    return updates
  }

  /// The parameter strings of every SGR sequence (`CSI … m`) in `bytes`.
  private func sgrParameters(in bytes: [UInt8]) -> [String] {
    var result: [String] = []
    var index = 0
    while index + 1 < bytes.count {
      guard bytes[index] == 0x1B, bytes[index + 1] == 0x5B else {
        index += 1
        continue
      }
      var end = index + 2
      while end < bytes.count, (0x30...0x3F).contains(bytes[end]) { end += 1 }
      if end < bytes.count, bytes[end] == 0x6D {
        result.append(String(decoding: bytes[(index + 2)..<end], as: UTF8.self))
      }
      index = end
    }
    return result
  }
}

// MARK: - Scenarios shared with the `output` benchmark suite

struct ANSIOutputScenario: Sendable {
  var name: String
  var changesStyle: Bool
  var style: @Sendable (_ column: Int, _ row: Int) -> Style
  var symbol: @Sendable (_ column: Int, _ row: Int) -> String

  func updates(width: Int, height: Int) -> [CellUpdate] {
    var updates: [CellUpdate] = []
    for row in 0..<height {
      for column in 0..<width {
        updates.append(
          CellUpdate(
            position: Position(x: column, y: row),
            cell: Cell(symbol: symbol(column, row), style: style(column, row))))
      }
    }
    return updates
  }

  static let letters = "abcdefghijklmnopqrstuvwxyz".map { String($0) }

  static func letter(_ index: Int) -> String {
    letters[index % letters.count]
  }

  static let constantStyle = ANSIOutputScenario(
    name: "constant-style",
    changesStyle: false,
    style: { _, _ in Style(foreground: .lightGreen, background: .black, modifiers: [.bold]) },
    symbol: { column, row in ANSIOutputScenario.letter(column + row) })

  static let all: [ANSIOutputScenario] = [
    constantStyle,
    ANSIOutputScenario(
      name: "truecolor-every-cell",
      changesStyle: true,
      style: { column, row in
        Style(
          foreground: .rgb(UInt8(column % 128 * 2), UInt8(row % 40 * 6), 128),
          background: .rgb(20, 20, UInt8((column + row) % 256)))
      },
      symbol: { column, _ in ANSIOutputScenario.letter(column) }),
    ANSIOutputScenario(
      name: "indexed-every-cell",
      changesStyle: true,
      style: { column, row in
        Style(
          foreground: .indexed(UInt8((column + row * 7) % 256)),
          background: .indexed(UInt8((column * 3 + row) % 256)))
      },
      symbol: { column, _ in ANSIOutputScenario.letter(column) }),
    ANSIOutputScenario(
      name: "style-every-4-cells",
      changesStyle: true,
      style: { column, row in ANSIOutputScenario.groupStyle((column / 4 + row) % 3) },
      symbol: { column, _ in ANSIOutputScenario.letter(column) }),
    ANSIOutputScenario(
      name: "attribute-toggles",
      changesStyle: true,
      style: { column, row in
        Style(foreground: .cyan, modifiers: Modifier(rawValue: UInt16((column + row) % 128)))
      },
      symbol: { column, _ in ANSIOutputScenario.letter(column) }),
    ANSIOutputScenario(
      name: "dashboard-mixed",
      changesStyle: true,
      style: { column, row in ANSIOutputScenario.dashboardStyle(column: column, row: row) },
      symbol: { column, row in column == 0 ? "│" : ANSIOutputScenario.letter(column * 7 + row) }),
  ]

  static func groupStyle(_ group: Int) -> Style {
    switch group {
    case 0: Style(foreground: .red, background: .indexed(236))
    case 1: Style(foreground: .green, background: .indexed(237), modifiers: [.bold])
    default: Style(foreground: .rgb(200, 120, 40), background: .indexed(238))
    }
  }

  /// A dashboard-like layout: a bold header, zebra-striped rows, a highlighted selected row,
  /// colored value columns and a dim border.
  static func dashboardStyle(column: Int, row: Int) -> Style {
    if row == 0 { return Style(foreground: .white, background: .blue, modifiers: [.bold]) }
    if column == 0 { return Style(foreground: .darkGray, modifiers: [.dim]) }
    var style = Style(foreground: .gray)
    if column >= 80 {
      style.foreground = .indexed(214)
    } else if column >= 40 {
      style.foreground = .rgb(120, 200, 120)
    }
    if row == 7 {
      style.background = .rgb(60, 60, 90)
      style = style.adding(.italic)
    } else if row.isMultiple(of: 2) {
      style.background = .indexed(236)
    }
    if column >= 80, column < 90 { style = style.adding(.bold) }
    return style
  }
}

// MARK: - Random frames

struct ANSIOutputGenerator {
  private var state: UInt64

  init(seed: UInt64) { state = seed }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var value = state
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
    return value ^ (value >> 31)
  }

  mutating func below(_ bound: Int) -> Int {
    Int(next() % UInt64(bound))
  }

  static let namedColors: [Color] = [
    .black, .red, .green, .yellow, .blue, .magenta, .cyan, .gray, .darkGray, .lightRed,
    .lightGreen, .lightYellow, .lightBlue, .lightMagenta, .lightCyan, .white,
  ]

  /// Single- and double-width symbols that never join into one grapheme when concatenated.
  static let symbols = ["a", "b", "Z", " ", "#", "é", "界", "🙂"]

  mutating func color() -> Color? {
    switch below(8) {
    case 0, 1: return nil
    case 2: return .reset
    case 3, 4: return Self.namedColors[below(Self.namedColors.count)]
    case 5: return .indexed(UInt8(truncatingIfNeeded: next()))
    default:
      // Few distinct channel values so consecutive styles often share a color.
      let levels: [UInt8] = [0, 95, 128, 255]
      return .rgb(levels[below(4)], levels[below(4)], levels[below(4)])
    }
  }

  mutating func style() -> Style {
    var modifiers = Modifier(rawValue: UInt16(truncatingIfNeeded: next()) & 0x7F)
    if below(3) == 0 { modifiers = [] }
    let foreground = color()
    let background = color()
    let underlineColor = color()
    var style = Style(
      foreground: foreground, background: background, underlineColor: underlineColor,
      modifiers: modifiers)
    if below(5) == 0 { style = style.removing(Modifier(rawValue: 1 << UInt16(below(7)))) }
    return style
  }

  /// A palette style, the previous style, or the previous style with one attribute changed.
  mutating func style(after previous: Style, palette: [Style]) -> Style {
    switch below(10) {
    case 0, 1, 2, 3: return previous
    case 4, 5: return palette[below(palette.count)]
    case 6:
      let modifier = Modifier(rawValue: 1 << UInt16(below(7)))
      if previous.modifiers.contains(modifier) { return previous.removing(modifier) }
      return previous.adding(modifier)
    case 7:
      var style = previous
      style.foreground = color()
      return style
    case 8:
      var style = previous
      style.background = color()
      return style
    default:
      var style = previous
      style.underlineColor = color()
      return style
    }
  }

  mutating func symbol() -> String {
    Self.symbols[below(Self.symbols.count)]
  }

  mutating func buffer(area: Rect, palette: [Style]) -> Buffer {
    var buffer = Buffer(area: area)
    var style = palette[0]
    for row in 0..<area.height {
      var column = 0
      while column < area.width {
        style = self.style(after: style, palette: palette)
        let symbol = self.symbol()
        buffer.setString(symbol, at: Position(x: column, y: row), style: style)
        column += max(1, TerminalWidth.of(symbol))
      }
    }
    return buffer
  }

  mutating func mutated(_ buffer: Buffer, palette: [Style]) -> Buffer {
    var result = buffer
    var style = palette[below(palette.count)]
    for _ in 0..<below(buffer.area.width * buffer.area.height / 2) {
      style = self.style(after: style, palette: palette)
      let position = Position(x: below(buffer.area.width), y: below(buffer.area.height))
      result.setString(symbol(), at: position, style: style)
    }
    return result
  }

  /// Unordered updates, including explicit wide cells and continuation cells.
  mutating func randomUpdates(area: Rect, palette: [Style]) -> [CellUpdate] {
    var updates: [CellUpdate] = []
    var style = palette[0]
    for _ in 0..<below(40) {
      style = self.style(after: style, palette: palette)
      let position = Position(x: below(area.width), y: below(area.height))
      let cell: Cell
      switch below(6) {
      case 0: cell = Cell(symbol: "界", style: style, width: 2)
      case 1: cell = Cell(symbol: "", style: style, isContinuation: true)
      default: cell = Cell(symbol: symbol(), style: style)
      }
      updates.append(CellUpdate(position: position, cell: cell))
      if below(2) == 0 {
        updates.append(
          CellUpdate(
            position: Position(x: position.x + 1, y: position.y),
            cell: Cell(symbol: symbol(), style: self.style(after: style, palette: palette))))
      }
    }
    return updates
  }

  /// An arbitrary rendition the terminal may be in before a frame.
  mutating func rendition() -> VirtualRendition {
    VirtualRendition(
      attributes: UInt8(truncatingIfNeeded: next()) & 0x7F,
      foreground: below(2) == 0 ? .terminalDefault : .basic(31),
      background: below(2) == 0 ? .terminalDefault : .indexed(17),
      underlineColor: below(2) == 0 ? .terminalDefault : .rgb(1, 2, 3))
  }
}

final class ANSIOutputSink {
  var writes: [Data] = []

  func write(_ data: Data) {
    writes.append(data)
  }
}

// MARK: - Virtual terminal

enum VirtualColor: Hashable {
  case terminalDefault
  case basic(Int)
  case indexed(Int)
  case rgb(Int, Int, Int)
}

/// The SGR state of a terminal. Attribute bits: bold, dim, italic, underlined, reversed, hidden,
/// crossed out.
struct VirtualRendition: Hashable {
  var attributes: UInt8 = 0
  var foreground = VirtualColor.terminalDefault
  var background = VirtualColor.terminalDefault
  var underlineColor = VirtualColor.terminalDefault
}

struct VirtualCell: Hashable {
  var text: String
  var rendition: VirtualRendition
  var isContinuation: Bool
}

enum VirtualTerminalError: Error {
  case unsupported(String)
}

/// A minimal ANSI interpreter for the sequences `ANSIBackend.draw` emits: ESC 7/8, CUP, CHA, CUU,
/// CUD, SGR (ECMA-48 semantics: 22 clears bold and dim; 0 resets every attribute and color,
/// including the underline color), and private mode set/reset. Text advances the cursor by the
/// grapheme's terminal width.
struct VirtualTerminal: Equatable {
  var cells: [Position: VirtualCell] = [:]
  var cursor = Position(x: 0, y: 0)
  var savedCursor: Position
  var rendition: VirtualRendition
  var privateModes: [Int: Bool] = [:]

  init(savedCursor: Position, rendition: VirtualRendition) {
    self.savedCursor = savedCursor
    self.rendition = rendition
  }

  mutating func apply(_ bytes: [UInt8]) throws {
    var index = 0
    var textStart = 0
    while index < bytes.count {
      guard bytes[index] == 0x1B else {
        index += 1
        continue
      }
      write(bytes[textStart..<index])
      guard index + 1 < bytes.count else { throw VirtualTerminalError.unsupported("lone ESC") }
      switch bytes[index + 1] {
      case 0x37:
        savedCursor = cursor
        index += 2
      case 0x38:
        cursor = savedCursor
        index += 2
      case 0x5B:
        var end = index + 2
        let isPrivate = end < bytes.count && bytes[end] == 0x3F
        if isPrivate { end += 1 }
        var parameters: [Int] = []
        var current = 0
        while end < bytes.count, bytes[end] == 0x3B || (0x30...0x39).contains(bytes[end]) {
          if bytes[end] == 0x3B {
            parameters.append(current)
            current = 0
          } else {
            current = current &* 10 &+ Int(bytes[end] - 0x30)
          }
          end += 1
        }
        parameters.append(current)
        guard end < bytes.count else { throw VirtualTerminalError.unsupported("truncated CSI") }
        try execute(final: bytes[end], parameters: parameters, isPrivate: isPrivate)
        index = end + 1
      default:
        throw VirtualTerminalError.unsupported("ESC \(bytes[index + 1])")
      }
      textStart = index
    }
    write(bytes[textStart..<bytes.count])
  }

  private mutating func write(_ text: ArraySlice<UInt8>) {
    guard !text.isEmpty else { return }
    for character in String(decoding: text, as: UTF8.self) {
      let width = max(1, TerminalWidth.of(character))
      cells[cursor] = VirtualCell(
        text: String(character), rendition: rendition, isContinuation: false)
      for offset in 1..<width {
        cells[Position(x: cursor.x &+ offset, y: cursor.y)] = VirtualCell(
          text: "", rendition: rendition, isContinuation: true)
      }
      cursor = Position(x: cursor.x &+ width, y: cursor.y)
    }
  }

  private mutating func execute(final: UInt8, parameters: [Int], isPrivate: Bool) throws {
    let first = parameters[0]
    switch (final, isPrivate) {
    case (0x48, false):
      let column = parameters.count > 1 ? parameters[1] : 1
      cursor = Position(x: max(1, column) - 1, y: max(1, first) - 1)
    case (0x47, false):
      cursor = Position(x: max(1, first) - 1, y: cursor.y)
    case (0x41, false):
      cursor = Position(x: cursor.x, y: max(0, cursor.y - max(1, first)))
    case (0x42, false):
      cursor = Position(x: cursor.x, y: cursor.y &+ max(1, first))
    case (0x6D, false):
      try applySGR(parameters)
    case (0x68, true):
      privateModes[first] = true
    case (0x6C, true):
      privateModes[first] = false
    default:
      throw VirtualTerminalError.unsupported("CSI \(parameters) \(final) private: \(isPrivate)")
    }
  }

  private mutating func applySGR(_ parameters: [Int]) throws {
    var index = 0
    while index < parameters.count {
      let code = parameters[index]
      index += 1
      switch code {
      case 0: rendition = VirtualRendition()
      case 1: rendition.attributes |= 1 << 0
      case 2: rendition.attributes |= 1 << 1
      case 3: rendition.attributes |= 1 << 2
      case 4: rendition.attributes |= 1 << 3
      case 7: rendition.attributes |= 1 << 4
      case 8: rendition.attributes |= 1 << 5
      case 9: rendition.attributes |= 1 << 6
      case 22: rendition.attributes &= ~0b11
      case 23: rendition.attributes &= ~(1 << 2)
      case 24: rendition.attributes &= ~(1 << 3)
      case 27: rendition.attributes &= ~(1 << 4)
      case 28: rendition.attributes &= ~(1 << 5)
      case 29: rendition.attributes &= ~(1 << 6)
      case 30...37, 90...97: rendition.foreground = .basic(code)
      case 39: rendition.foreground = .terminalDefault
      case 40...47, 100...107: rendition.background = .basic(code)
      case 49: rendition.background = .terminalDefault
      case 59: rendition.underlineColor = .terminalDefault
      case 38, 48, 58:
        let color = try extendedColor(parameters, at: &index)
        if code == 38 {
          rendition.foreground = color
        } else if code == 48 {
          rendition.background = color
        } else {
          rendition.underlineColor = color
        }
      default:
        throw VirtualTerminalError.unsupported("SGR \(code)")
      }
    }
  }

  private func extendedColor(_ parameters: [Int], at index: inout Int) throws -> VirtualColor {
    guard index < parameters.count else { throw VirtualTerminalError.unsupported("SGR 38") }
    let mode = parameters[index]
    if mode == 5, index + 1 < parameters.count {
      index += 2
      return .indexed(parameters[index - 1])
    }
    if mode == 2, index + 3 < parameters.count {
      index += 4
      return .rgb(parameters[index - 3], parameters[index - 2], parameters[index - 1])
    }
    throw VirtualTerminalError.unsupported("SGR extended color \(parameters)")
  }
}

// MARK: - Reference implementation (the emitter before direct byte output)

/// Verbatim copy of `ANSIBackend.draw` and its helpers before escape sequences were written
/// straight into bytes and SGR changes were emitted as differences. Do not optimize.
struct ANSIReferenceEmitter {
  var configuration: ANSIBackendConfiguration
  var cursorAddressing: CursorAddressing

  func draw(_ updates: [CellUpdate]) -> [UInt8] {
    guard !updates.isEmpty else { return [] }
    var bytes: [UInt8] = []
    bytes.reserveCapacity(updates.count * 16)
    var activeStyle: Style?
    var expectedPosition: Position?

    if configuration.supportsSynchronizedOutput {
      bytes.append(contentsOf: "\u{1B}[?2026h".utf8)
    }
    for update in updates where !update.cell.isContinuation {
      if expectedPosition != update.position {
        bytes.append(contentsOf: cursor(position: update.position).utf8)
      }
      if activeStyle != update.cell.style {
        bytes.append(contentsOf: style(update.cell.style).utf8)
        activeStyle = update.cell.style
      }
      bytes.append(contentsOf: update.cell.symbol.utf8)
      expectedPosition = update.position.offset(
        by: Offset(x: max(1, Int(update.cell.width)), y: 0)
      )
    }
    bytes.append(contentsOf: "\u{1B}[0m".utf8)
    if configuration.supportsSynchronizedOutput {
      bytes.append(contentsOf: "\u{1B}[?2026l".utf8)
    }
    return bytes
  }

  private func cursor(position: Position) -> String {
    switch cursorAddressing {
    case .absolute:
      return "\u{1B}[\(referenceOneBasedANSI(position.y));\(referenceOneBasedANSI(position.x))H"
    case .savedOrigin:
      let vertical = position.y == 0 ? "" : "\u{1B}[\(position.y)B"
      return "\u{1B}8\(vertical)\u{1B}[\(referenceOneBasedANSI(position.x))G"

    case .savedBottom(let viewportHeight):
      let rowsUp = max(0, viewportHeight - 1 - position.y)
      let vertical = rowsUp == 0 ? "" : "\u{1B}[\(rowsUp)A"
      return "\u{1B}8\(vertical)\u{1B}[\(referenceOneBasedANSI(position.x))G"
    case .absoluteOrigin(let origin):
      // Split over two lines only to stay within the line-length limit.
      let row = referenceOneBasedANSI(origin.y, position.y)
      let column = referenceOneBasedANSI(origin.x, position.x)
      return "\u{1B}[\(row);\(column)H"
    }
  }

  private func style(_ style: Style) -> String {
    var codes = ["0"]
    if style.modifiers.contains(.bold) { codes.append("1") }
    if style.modifiers.contains(.dim) { codes.append("2") }
    if style.modifiers.contains(.italic) { codes.append("3") }
    if style.modifiers.contains(.underlined) { codes.append("4") }
    if style.modifiers.contains(.reversed) { codes.append("7") }
    if style.modifiers.contains(.hidden) { codes.append("8") }
    if style.modifiers.contains(.crossedOut) { codes.append("9") }
    if let foreground = style.foreground {
      codes.append(contentsOf: color(foreground, foreground: true))
    }
    if let background = style.background {
      codes.append(contentsOf: color(background, foreground: false))
    }
    if configuration.supportsUnderlineColor, let underlineColor = style.underlineColor {
      codes.append(contentsOf: underlineColorCodes(underlineColor))
    }
    return "\u{1B}[\(codes.joined(separator: ";"))m"
  }

  private func underlineColorCodes(_ color: Color) -> [String] {
    if case .reset = color { return ["59"] }
    let index: UInt8
    switch configuration.colorProfile {
    case .trueColor:
      if case .rgb(let red, let green, let blue) = color {
        return ["58", "2", String(red), String(green), String(blue)]
      }
      index = indexedColor(color)
    case .indexed256:
      index = indexedColor(color)
    case .ansi16:
      index = nearestANSI16Index(rgbColor(color))
    }
    return ["58", "5", String(index)]
  }

  private func indexedColor(_ color: Color) -> UInt8 {
    switch color {
    case .reset, .black: return 0
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
    case .indexed(let value): return value
    case .rgb(let red, let green, let blue):
      return nearestXtermIndex((red, green, blue))
    }
  }

  private func color(_ color: Color, foreground: Bool) -> [String] {
    if case .reset = color { return [String(foreground ? 39 : 49)] }
    switch configuration.colorProfile {
    case .trueColor:
      break
    case .indexed256:
      switch color {
      case .rgb:
        return [foreground ? "38" : "48", "5", String(indexedColor(color))]
      default:
        break
      }
    case .ansi16:
      return ansi16Color(nearestANSI16Index(rgbColor(color)), foreground: foreground)
    }
    let offset = foreground ? 30 : 40
    switch color {
    case .reset: return [String(foreground ? 39 : 49)]
    case .black: return [String(offset)]
    case .red: return [String(offset + 1)]
    case .green: return [String(offset + 2)]
    case .yellow: return [String(offset + 3)]
    case .blue: return [String(offset + 4)]
    case .magenta: return [String(offset + 5)]
    case .cyan: return [String(offset + 6)]
    case .gray: return [String(offset + 7)]
    case .darkGray: return [String(offset + 60)]
    case .lightRed: return [String(offset + 61)]
    case .lightGreen: return [String(offset + 62)]
    case .lightYellow: return [String(offset + 63)]
    case .lightBlue: return [String(offset + 64)]
    case .lightMagenta: return [String(offset + 65)]
    case .lightCyan: return [String(offset + 66)]
    case .white: return [String(offset + 67)]
    case .indexed(let value):
      return [foreground ? "38" : "48", "5", String(value)]
    case .rgb(let red, let green, let blue):
      return [
        foreground ? "38" : "48",
        "2",
        String(red),
        String(green),
        String(blue),
      ]
    }
  }

  private func ansi16Color(_ index: UInt8, foreground: Bool) -> [String] {
    let base = foreground ? 30 : 40
    let code = index < 8 ? base + Int(index) : base + 60 + Int(index - 8)
    return [String(code)]
  }

  private func rgbColor(_ color: Color) -> (UInt8, UInt8, UInt8) {
    switch color {
    case .reset, .black: return (0, 0, 0)
    case .red: return (128, 0, 0)
    case .green: return (0, 128, 0)
    case .yellow: return (128, 128, 0)
    case .blue: return (0, 0, 128)
    case .magenta: return (128, 0, 128)
    case .cyan: return (0, 128, 128)
    case .gray: return (192, 192, 192)
    case .darkGray: return (128, 128, 128)
    case .lightRed: return (255, 0, 0)
    case .lightGreen: return (0, 255, 0)
    case .lightYellow: return (255, 255, 0)
    case .lightBlue: return (0, 0, 255)
    case .lightMagenta: return (255, 0, 255)
    case .lightCyan: return (0, 255, 255)
    case .white: return (255, 255, 255)
    case .indexed(let index): return xtermRGB(index)
    case .rgb(let red, let green, let blue): return (red, green, blue)
    }
  }

  private func xtermRGB(_ index: UInt8) -> (UInt8, UInt8, UInt8) {
    if index < 16 { return ansi16Palette[Int(index)] }
    if index < 232 {
      let offset = Int(index) - 16
      let levels: [UInt8] = [0, 95, 135, 175, 215, 255]
      return (levels[offset / 36], levels[(offset / 6) % 6], levels[offset % 6])
    }
    let level = UInt8(8 + 10 * (Int(index) - 232))
    return (level, level, level)
  }

  private func nearestXtermIndex(_ rgb: (UInt8, UInt8, UInt8)) -> UInt8 {
    var best: UInt8 = 0
    var bestDistance = Int.max
    for candidate in Int(0)...255 {
      let palette = xtermRGB(UInt8(candidate))
      let distance = colorDistance(rgb, palette)
      if distance < bestDistance {
        bestDistance = distance
        best = UInt8(candidate)
      }
    }
    return best
  }

  private func nearestANSI16Index(_ rgb: (UInt8, UInt8, UInt8)) -> UInt8 {
    UInt8(
      ansi16Palette.indices.min { lhs, rhs in
        colorDistance(rgb, ansi16Palette[lhs]) < colorDistance(rgb, ansi16Palette[rhs])
      } ?? 0
    )
  }

  private func colorDistance(
    _ lhs: (UInt8, UInt8, UInt8),
    _ rhs: (UInt8, UInt8, UInt8)
  ) -> Int {
    let red = Int(lhs.0) - Int(rhs.0)
    let green = Int(lhs.1) - Int(rhs.1)
    let blue = Int(lhs.2) - Int(rhs.2)
    return red * red + green * green + blue * blue
  }

  private var ansi16Palette: [(UInt8, UInt8, UInt8)] {
    [
      (0, 0, 0), (128, 0, 0), (0, 128, 0), (128, 128, 0),
      (0, 0, 128), (128, 0, 128), (0, 128, 128), (192, 192, 192),
      (128, 128, 128), (255, 0, 0), (0, 255, 0), (255, 255, 0),
      (0, 0, 255), (255, 0, 255), (0, 255, 255), (255, 255, 255),
    ]
  }
}

private func referenceSaturatingANSIAdd(_ lhs: Int, _ rhs: Int) -> Int {
  let result = lhs.addingReportingOverflow(rhs)
  return result.overflow ? Int.max : max(0, result.partialValue)
}

private func referenceOneBasedANSI(_ components: Int...) -> Int {
  let zeroBased = components.reduce(0, referenceSaturatingANSIAdd)
  return referenceSaturatingANSIAdd(zeroBased, 1)
}
