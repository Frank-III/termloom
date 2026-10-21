import Foundation
import Testing

@testable import TermLoom

#if canImport(Darwin)
  import Darwin
#endif

/// `Terminal` frames on an `ANSIBackend` are written as one write that contains the changed cells
/// and only the cursor changes (shape, position, visibility), inside the synchronized update.
///
/// The reference is the previous behavior, reproduced exactly by `LegacyFrameBackend`: a backend
/// that forwards every call to an `ANSIBackend`, so `Terminal` presents frames with the separate
/// `draw`, `setCursorStyle` and `setCursor` calls it always made. `CursorScreen` applies both byte
/// streams to a virtual terminal and the tests compare the screens after every step.
@Suite struct CursorPresentationTests {
  // MARK: Equivalence

  @Test func randomFrameSequencesLeaveTheTerminalExactlyAsBefore() throws {
    var seed: UInt64 = 0xC05E5
    for scenario in CursorScenario.all {
      for run in 0..<6 {
        seed &+= 0x9E37_79B9
        var harness = try CursorEquivalenceHarness(scenario: scenario)
        var generator = CursorStepGenerator(seed: seed, scenario: scenario)
        for index in 0..<80 {
          let step = generator.next(area: harness.area)
          let label = "\(scenario.name) run \(run) step \(index) \(step)"
          let matches = try harness.perform(step, label: label)
          if !matches { return }
          if case .resize(let area) = step { generator.adopt(area) }
        }
        #expect(harness.newBytes > 0)
      }
    }
  }

  // MARK: Unchanged cursor

  @Test func framesWithoutChangesWriteNothing() throws {
    for synchronized in [true, false] {
      for caret in [Position(x: 3, y: 1), nil] {
        var recording = try RecordingTerminal(synchronized: synchronized)
        try recording.draw("AB", caret: caret)
        let writes = recording.sink.writeCount
        for _ in 0..<5 { try recording.draw("AB", caret: caret) }
        #expect(recording.sink.writeCount == writes)
      }
    }
  }

  @Test func cursorChangesEmitOnlyWhatChanged() throws {
    var recording = try RecordingTerminal(synchronized: true)
    try recording.draw("AB", caret: Position(x: 3, y: 1))
    let cells = "\u{1B}[1;1H\u{1B}[0mAB\u{1B}[0m"
    #expect(recording.written() == synchronized(cells + "\u{1B}[6 q\u{1B}[2;4H\u{1B}[?25h"))
    // The caret moves: only the move.
    try recording.draw("AB", caret: Position(x: 4, y: 1))
    #expect(recording.written() == synchronized("\u{1B}[2;5H"))
    // Only the shape changes.
    try recording.draw("AB", caret: Position(x: 4, y: 1), style: .steadyBlock)
    #expect(recording.written() == synchronized("\u{1B}[2 q"))
    // Hiding resets the shape exactly as `Frame.placeCursor(at: nil)` always did.
    try recording.draw("AB", caret: nil)
    #expect(recording.written() == synchronized("\u{1B}[0 q\u{1B}[?25l"))
    try recording.draw("AB", caret: nil)
    #expect(recording.written().isEmpty)
    // Nothing moved the hidden cursor, so showing it at the same place needs no move.
    try recording.draw("AB", caret: Position(x: 4, y: 1))
    #expect(recording.written() == synchronized("\u{1B}[6 q\u{1B}[?25h"))
    // One cell changes under a fixed caret: drawing moved the cursor, so it is moved back.
    try recording.draw("CB", caret: Position(x: 4, y: 1))
    #expect(recording.written() == synchronized("\u{1B}[1;1H\u{1B}[0mC\u{1B}[0m\u{1B}[2;5H"))
    #expect(recording.sink.writeCount == 6)
  }

  @Test func withoutSynchronizedOutputAFrameIsStillOneWrite() throws {
    var recording = try RecordingTerminal(synchronized: false)
    try recording.draw("AB", caret: Position(x: 3, y: 1))
    let cells = "\u{1B}[1;1H\u{1B}[0mAB\u{1B}[0m"
    #expect(recording.written() == cells + "\u{1B}[6 q\u{1B}[2;4H\u{1B}[?25h")
    try recording.draw("AB", caret: Position(x: 4, y: 1))
    #expect(recording.written() == "\u{1B}[2;5H")
    try recording.draw("AB", caret: Position(x: 4, y: 1))
    #expect(recording.written().isEmpty)
    #expect(recording.sink.writeCount == 2)
  }

  @Test func theFirstFrameEmitsTheCompleteCursorStateEvenWithoutCellChanges() throws {
    var recording = try RecordingTerminal(synchronized: true)
    try recording.draw("", caret: nil)
    #expect(recording.written() == synchronized("\u{1B}[0 q\u{1B}[?25l"))
  }

  private func synchronized(_ bytes: String) -> String {
    "\u{1B}[?2026h" + bytes + "\u{1B}[?2026l"
  }

  // MARK: Synchronized output

  @Test func everyCursorEscapeIsInsideTheSynchronizedUpdate() throws {
    var generator = CursorStepGenerator(seed: 0x54C, scenario: CursorScenario.all[0])
    var recording = try RecordingTerminal(synchronized: true, size: Size(width: 12, height: 6))
    let area = Rect(x: 0, y: 0, width: 12, height: 6)
    for index in 0..<300 {
      let writes = recording.sink.writeCount
      let (strokes, caret, style) = generator.nextFrame(area: area)
      try recording.terminal.draw { frame in
        for stroke in strokes { stroke.render(into: &frame) }
        frame.placeCursor(at: caret, style: style)
      }
      #expect(recording.sink.writeCount - writes <= 1, "frame \(index)")
      let bytes = recording.written()
      guard !bytes.isEmpty else { continue }
      #expect(bytes.hasPrefix("\u{1B}[?2026h"), "frame \(index)")
      #expect(bytes.hasSuffix("\u{1B}[?2026l"), "frame \(index)")
      #expect(bytes.components(separatedBy: "\u{1B}[?2026").count == 3, "frame \(index)")
    }
  }

  // MARK: Invalidation

  @Test func everyOtherTerminalOperationMakesTheNextFrameResendTheCursor() throws {
    for operation in InvalidatingOperation.allCases {
      var recording = try RecordingTerminal(synchronized: true)
      try recording.draw("AB", caret: Position(x: 3, y: 1))
      try recording.draw("AB", caret: Position(x: 3, y: 1))
      _ = recording.written()
      try operation.perform(on: &recording)
      _ = recording.written()
      try recording.draw("AB", caret: Position(x: 3, y: 1))
      let resent = recording.written()
      #expect(resent.hasSuffix("\u{1B}[6 q\u{1B}[2;4H\u{1B}[?25h\u{1B}[?2026l"), "\(operation)")
      try recording.draw("AB", caret: Position(x: 3, y: 1))
      #expect(recording.written().isEmpty, "\(operation)")
    }
  }

  @Test func fixedViewportResizeMakesTheNextFrameResendTheCursor() throws {
    let sink = FrameOutputSink()
    let output = TransactionalTerminalOutput(directWrite: sink.write)
    var backend = ANSIBackend(
      output: CursorScenario.nullDevice, fallbackSize: Size(width: 12, height: 6))
    backend.outputWriter = { try output.write($0) }
    backend.outputGeneration = { output.generation }
    var terminal = try Terminal(
      backend: backend, viewport: .fixed(Rect(x: 2, y: 1, width: 8, height: 4)))
    let render: (inout Frame) -> Void = { frame in
      frame.buffer.setString("AB", at: Position(x: 2, y: 1))
      frame.placeCursor(at: Position(x: 4, y: 2), style: .steadyBar)
    }
    try terminal.draw(render)
    try terminal.draw(render)
    _ = sink.take()
    try terminal.resize(to: Rect(x: 2, y: 1, width: 9, height: 4))
    _ = sink.take()
    try terminal.draw(render)
    let bytes = String(decoding: sink.take(), as: UTF8.self)
    #expect(bytes.hasSuffix("\u{1B}[6 q\u{1B}[3;5H\u{1B}[?25h\u{1B}[?2026l"))
  }

  @Test func historyInsertionMakesTheNextFrameResendTheCursor() throws {
    for strategy in [ANSIHistoryInsertionStrategy.scrollingRegion, .terminalOutput] {
      let sink = FrameOutputSink()
      let output = TransactionalTerminalOutput(directWrite: sink.write)
      var backend = ANSIBackend(
        output: CursorScenario.nullDevice,
        fallbackSize: Size(width: 12, height: 8),
        viewportHeight: 3,
        viewportOrigin: Position(x: 0, y: 3),
        cursorAddressing: .absoluteOrigin(Position(x: 0, y: 3)),
        configuration: ANSIBackendConfiguration(historyInsertionStrategy: strategy))
      backend.outputWriter = { try output.write($0) }
      backend.outputGeneration = { output.generation }
      var terminal = try Terminal(backend: backend)
      let render: (inout Frame) -> Void = { frame in
        frame.buffer.setString("LIVE", at: Position(x: 0, y: 0))
        frame.placeCursor(at: Position(x: 4, y: 0), style: .steadyBar)
      }
      try terminal.draw(render)
      try terminal.draw(render)
      _ = sink.take()
      try terminal.insertBefore(height: 1) { buffer in
        buffer.setString("HISTORY", at: Position(x: 0, y: 0))
      }
      #expect(!sink.take().isEmpty, "\(strategy)")
      try terminal.draw(render)
      let bytes = String(decoding: sink.take(), as: UTF8.self)
      #expect(bytes.contains("\u{1B}[6 q"), "\(strategy)")
      #expect(bytes.hasSuffix("\u{1B}[?25h\u{1B}[?2026l"), "\(strategy)")
    }
  }

  @Test func transactionalOutputCountsWritesDiscardsAndRecoveries() throws {
    let sink = FrameOutputSink()
    let output = TransactionalTerminalOutput(directWrite: sink.write)
    let start = output.generation
    try output.write(Data("a".utf8))
    #expect(output.generation != start)
    let afterWrite = output.generation
    _ = try? output.withTransaction { () throws -> Void in throw CursorTestError.discarded }
    #expect(output.generation != afterWrite)
    let afterDiscard = output.generation
    sink.failsNextWrite = true
    #expect(throws: CursorTestError.self) {
      try output.withTransaction { try output.write(Data("b".utf8)) }
    }
    #expect(output.generation != afterDiscard)
  }

  #if canImport(Darwin)
    @MainActor
    @Test func sessionSuspendAndResumeMakeTheNextFrameResendTheCursor() throws {
      var master: Int32 = -1
      var slave: Int32 = -1
      var window = winsize(ws_row: 8, ws_col: 20, ws_xpixel: 0, ws_ypixel: 0)
      #expect(openpty(&master, &slave, nil, nil, &window) == 0)
      guard master >= 0, slave >= 0 else { return }
      defer {
        close(master)
        close(slave)
      }
      _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)
      let session = try TerminalSession(
        viewport: .fullscreen, inputDescriptor: slave,
        output: FileHandle(fileDescriptor: slave, closeOnDealloc: false),
        backendConfiguration: .full)
      defer { try? session.restore() }
      var terminal = try Terminal(
        backend: session.makeBackend(), viewport: session.configuredViewport)
      let render: (inout Frame) -> Void = { frame in
        frame.buffer.setString("EDIT", at: Position(x: 0, y: 0))
        frame.placeCursor(at: Position(x: 4, y: 0), style: .steadyBar)
      }
      try terminal.draw(render)
      _ = Self.drain(master)
      try terminal.draw(render)
      #expect(Self.drain(master).isEmpty)

      try session.suspend()
      try session.resume()
      _ = Self.drain(master)
      try terminal.draw(render)
      let bytes = String(decoding: Self.drain(master), as: UTF8.self)
      #expect(bytes.contains("\u{1B}[6 q\u{1B}[1;5H\u{1B}[?25h"))
    }

    private static func drain(_ descriptor: Int32) -> [UInt8] {
      var result: [UInt8] = []
      var chunk = [UInt8](repeating: 0, count: 4096)
      while true {
        let count = read(descriptor, &chunk, chunk.count)
        guard count > 0 else { break }
        result.append(contentsOf: chunk[..<count])
      }
      return result
    }
  #endif
}

// MARK: - Recording terminal

/// Operations after which the backend no longer knows the terminal's cursor state.
enum InvalidatingOperation: CaseIterable {
  case clear
  case regionalClear
  case setCursor
  case hideCursor
  case setCursorStyle
  case draw
  case appendLines
  case scrollRegionUp
  case scrollRegionDown
  case scrollRegionUpIntoScrollback
  case setViewportOrigin
  case outOfBandWrite
  case discardedTransaction
  case failedFrameWrite

  func perform(on recording: inout RecordingTerminal) throws {
    switch self {
    case .clear:
      try recording.terminal.clear()
    case .regionalClear:
      try recording.withBackend { try $0.clear(.afterCursor) }
    case .setCursor:
      try recording.withBackend { try $0.setCursor(Position(x: 3, y: 1)) }
    case .hideCursor:
      try recording.withBackend { try $0.setCursor(nil) }
    case .setCursorStyle:
      try recording.withBackend { try $0.setCursorStyle(.steadyBar) }
    case .draw:
      let update = CellUpdate(position: Position(x: 9, y: 3), cell: Cell(symbol: "Z"))
      try recording.withBackend { try $0.draw([update]) }
    case .appendLines:
      try recording.withBackend { try $0.appendLines(1) }
    case .scrollRegionUp:
      try recording.withBackend { try $0.scrollRegionUp(0..<2, by: 1) }
    case .scrollRegionDown:
      try recording.withBackend { try $0.scrollRegionDown(0..<2, by: 1) }
    case .scrollRegionUpIntoScrollback:
      try recording.withBackend { try $0.scrollRegionUpIntoScrollback(0..<2, by: 1) }
    case .setViewportOrigin:
      try recording.withBackend { try $0.setViewportOrigin(Position(x: 0, y: 0)) }
    case .outOfBandWrite:
      try recording.output.write(Data("\u{1B}[?25h".utf8))
    case .discardedTransaction:
      let output = recording.output
      do {
        try output.withTransaction { () throws -> Void in
          try output.write(Data("\u{1B}[3;3H".utf8))
          throw CursorTestError.discarded
        }
        Issue.record("the transaction was not discarded")
      } catch {}
    case .failedFrameWrite:
      recording.sink.failsNextWrite = true
      do {
        try recording.draw("AB", caret: Position(x: 5, y: 2))
        Issue.record("the frame write did not fail")
      } catch {}
    }
  }
}

enum CursorTestError: Error {
  case injected
  case discarded
}

final class FrameOutputSink {
  private(set) var bytes: [UInt8] = []
  private(set) var writeCount = 0
  var failsNextWrite = false

  func write(_ data: Data) throws {
    if failsNextWrite {
      failsNextWrite = false
      throw CursorTestError.injected
    }
    writeCount += 1
    bytes.append(contentsOf: data)
  }

  func take() -> [UInt8] {
    defer { bytes.removeAll() }
    return bytes
  }
}

/// A full-screen `Terminal<ANSIBackend>` whose output goes through a `TransactionalTerminalOutput`,
/// as in a `TerminalSession`.
struct RecordingTerminal {
  let sink = FrameOutputSink()
  let output: TransactionalTerminalOutput
  var terminal: Terminal<ANSIBackend>

  init(synchronized: Bool, size: Size = Size(width: 10, height: 4)) throws {
    output = TransactionalTerminalOutput(directWrite: sink.write)
    var backend = ANSIBackend(
      output: CursorScenario.nullDevice,
      fallbackSize: size,
      configuration: ANSIBackendConfiguration(supportsSynchronizedOutput: synchronized))
    let output = output
    backend.outputWriter = { try output.write($0) }
    backend.outputGeneration = { output.generation }
    terminal = try Terminal(backend: backend)
  }

  mutating func draw(_ text: String, caret: Position?, style: CursorStyle = .steadyBar) throws {
    try terminal.draw { frame in
      frame.buffer.setString(text, at: Position(x: 0, y: 0))
      frame.placeCursor(at: caret, style: style)
    }
  }

  mutating func withBackend(_ operation: (inout ANSIBackend) throws -> Void) throws {
    try terminal.withBackend(operation)
  }

  func written() -> String {
    String(decoding: sink.take(), as: UTF8.self)
  }
}

// MARK: - Reference backend

/// Forwards every call to an `ANSIBackend`. `Terminal` presents frames to it with the separate
/// `draw`, `setCursorStyle` and `setCursor` calls, which write exactly the bytes every frame wrote
/// before cursor changes were tracked.
struct LegacyFrameBackend: Backend, LineAppendingBackend, InlineHistoryBackend {
  var inner: ANSIBackend

  var capabilities: BackendCapabilities { inner.capabilities }
  var viewportOrigin: Position { inner.viewportOrigin }
  mutating func setViewportOrigin(_ origin: Position) throws {
    try inner.setViewportOrigin(origin)
  }
  mutating func size() throws -> Size { try inner.size() }
  mutating func windowSize() throws -> WindowSize { try inner.windowSize() }
  mutating func draw(_ updates: [CellUpdate]) throws { try inner.draw(updates) }
  mutating func flush() throws { try inner.flush() }
  mutating func clear() throws { try inner.clear() }
  mutating func clear(_ region: ClearRegion) throws { try inner.clear(region) }
  mutating func setCursor(_ position: Position?) throws { try inner.setCursor(position) }
  mutating func setCursorStyle(_ style: CursorStyle) throws { try inner.setCursorStyle(style) }
  mutating func appendLines(_ count: Int) throws { try inner.appendLines(count) }
  mutating func insertHistory(_ buffer: Buffer) throws -> Bool {
    try inner.insertHistory(buffer)
  }
  mutating func insertHistory(
    _ buffer: Buffer, batchPosition: HistoryInsertionBatchPosition
  ) throws -> Bool {
    try inner.insertHistory(buffer, batchPosition: batchPosition)
  }
  mutating func insertHistory(
    _ buffer: Buffer,
    batchPosition: HistoryInsertionBatchPosition,
    restoring viewport: Buffer?
  ) throws -> Bool {
    try inner.insertHistory(buffer, batchPosition: batchPosition, restoring: viewport)
  }
  mutating func scrollRegionUp(_ rows: Range<Int>, by count: Int) throws {
    try inner.scrollRegionUp(rows, by: count)
  }
  mutating func scrollRegionUpIntoScrollback(_ rows: Range<Int>, by count: Int) throws {
    try inner.scrollRegionUpIntoScrollback(rows, by: count)
  }
  mutating func scrollRegionDown(_ rows: Range<Int>, by count: Int) throws {
    try inner.scrollRegionDown(rows, by: count)
  }
}

// MARK: - Scenarios and steps

struct CursorScenario: Sendable {
  var name: String
  var screen: Size
  var addressing: CursorAddressing
  var viewportHeight: Int?
  var fixedArea: Rect?
  var synchronized: Bool
  var historyStrategy: ANSIHistoryInsertionStrategy
  /// Where the terminal's saved cursor (DECSC) is before the first frame.
  var savedCursor: Position

  var supportsHistory: Bool {
    if case .absoluteOrigin = addressing { return true }
    return false
  }

  /// A non-terminal output, so `ANSIBackend.size()` always uses the fallback size.
  static var nullDevice: FileHandle { FileHandle(forWritingAtPath: "/dev/null")! }

  static let all: [CursorScenario] = {
    var result: [CursorScenario] = []
    for synchronized in [true, false] {
      let suffix = synchronized ? "sync" : "no-sync"
      result.append(
        CursorScenario(
          name: "fullscreen \(suffix)", screen: Size(width: 12, height: 6),
          addressing: .absolute, synchronized: synchronized,
          historyStrategy: .scrollingRegion, savedCursor: Position(x: 0, y: 0)))
      result.append(
        CursorScenario(
          name: "fixed \(suffix)", screen: Size(width: 12, height: 6),
          addressing: .absolute, fixedArea: Rect(x: 2, y: 1, width: 8, height: 4),
          synchronized: synchronized, historyStrategy: .scrollingRegion,
          savedCursor: Position(x: 0, y: 0)))
      for strategy in [ANSIHistoryInsertionStrategy.scrollingRegion, .terminalOutput] {
        result.append(
          CursorScenario(
            name: "inline \(strategy) \(suffix)", screen: Size(width: 12, height: 8),
            addressing: .absoluteOrigin(Position(x: 0, y: 3)), viewportHeight: 3,
            synchronized: synchronized, historyStrategy: strategy,
            savedCursor: Position(x: 0, y: 0)))
      }
      result.append(
        CursorScenario(
          name: "saved origin \(suffix)", screen: Size(width: 12, height: 6),
          addressing: .savedOrigin, synchronized: synchronized,
          historyStrategy: .scrollingRegion, savedCursor: Position(x: 0, y: 1)))
      result.append(
        CursorScenario(
          name: "saved bottom \(suffix)", screen: Size(width: 12, height: 6),
          addressing: .savedBottom(viewportHeight: 4), viewportHeight: 4,
          synchronized: synchronized, historyStrategy: .scrollingRegion,
          savedCursor: Position(x: 0, y: 5)))
    }
    return result
  }()

  func makeBackend(output: TransactionalTerminalOutput) -> ANSIBackend {
    var origin: Position?
    if case .absoluteOrigin(let position) = addressing { origin = position }
    var backend = ANSIBackend(
      output: Self.nullDevice,
      fallbackSize: screen,
      viewportHeight: viewportHeight,
      viewportOrigin: origin,
      cursorAddressing: addressing,
      configuration: ANSIBackendConfiguration(
        supportsSynchronizedOutput: synchronized, historyInsertionStrategy: historyStrategy))
    backend.outputWriter = { try output.write($0) }
    return backend
  }

  var viewport: Viewport {
    fixedArea.map { Viewport.fixed($0) } ?? .fullscreen
  }
}

struct CursorStroke: CustomStringConvertible {
  var text: String
  var offset: Offset
  var style: Style

  func render(into frame: inout Frame) {
    frame.buffer.setString(
      text,
      at: Position(x: frame.area.x + offset.x, y: frame.area.y + offset.y),
      style: style)
  }

  var description: String { "\(text)@\(offset.x),\(offset.y)" }
}

enum CursorStep: CustomStringConvertible {
  /// A frame: strokes drawn over a blank viewport and a caret relative to the viewport.
  case frame(strokes: [CursorStroke], caret: Offset?, style: CursorStyle)
  case failingFrame(strokes: [CursorStroke], caret: Offset?, style: CursorStyle)
  case discardedFrame(strokes: [CursorStroke], caret: Offset?, style: CursorStyle)
  case clear
  case resize(Rect)
  case outOfBand(String)
  case history(height: Int, text: String)
  case setCursor(Offset?)
  case setCursorStyle(CursorStyle)

  var description: String {
    switch self {
    case .frame(let strokes, let caret, let style):
      "frame \(strokes) caret \(String(describing: caret)) \(style)"
    case .failingFrame(_, let caret, _): "failing frame caret \(String(describing: caret))"
    case .discardedFrame(_, let caret, _): "discarded frame caret \(String(describing: caret))"
    case .clear: "clear"
    case .resize(let area): "resize \(area)"
    case .outOfBand(let text): "out of band \(text.debugDescription)"
    case .history(let height, let text): "history \(height) \(text)"
    case .setCursor(let offset): "setCursor \(String(describing: offset))"
    case .setCursorStyle(let style): "setCursorStyle \(style)"
    }
  }
}

struct CursorStepGenerator {
  private var state: UInt64
  private let scenario: CursorScenario
  private var strokes: [CursorStroke] = []
  private var caret: Offset? = Offset(x: 1, y: 1)
  private var style = CursorStyle.steadyBar

  static let styles: [CursorStyle] = [
    .defaultUserShape, .blinkingBlock, .steadyBlock, .blinkingUnderline, .steadyUnderline,
    .blinkingBar, .steadyBar,
  ]
  static let palette: [Style] = [
    .plain, Style(foreground: .red), Style(foreground: .rgb(1, 2, 3), modifiers: [.bold]),
    Style(background: .indexed(17), modifiers: [.underlined]),
  ]
  static let outOfBand = [
    // `TerminalSession.suspend()` followed by a shell command and `resume()`.
    "\u{1B}[?2026l\u{1B}[r\u{1B}[0m\u{1B}[?7h\u{1B}[0 q\u{1B}[?25h$ vim\r\n\u{1B}[?25l",
    // `reanchorAfterResize` / `clearScrollbackAndResetViewport`.
    "\u{1B}[?25l\u{1B}[3J\u{1B}[2J\u{1B}[H",
    "\u{1B}[5 q",
    "\u{1B}[2;2H",
    "\u{1B}[?25h",
  ]

  init(seed: UInt64, scenario: CursorScenario) {
    state = seed
    self.scenario = scenario
  }

  private mutating func random() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var value = state
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
    return value ^ (value >> 31)
  }

  private mutating func below(_ bound: Int) -> Int {
    Int(random() % UInt64(max(1, bound)))
  }

  private mutating func offset(in area: Rect) -> Offset {
    Offset(x: below(area.width), y: below(area.height))
  }

  mutating func adopt(_ area: Rect) {
    strokes = []
    caret = caret.map { Offset(x: min($0.x, area.width - 1), y: min($0.y, area.height - 1)) }
  }

  /// The next frame: usually a small change of the content or the cursor, sometimes none.
  mutating func nextFrame(area: Rect) -> ([CursorStroke], Position?, CursorStyle) {
    let (strokes, caret, style) = nextFrameParts(area: area)
    let position = caret.map { Position(x: area.x + $0.x, y: area.y + $0.y) }
    return (strokes, position, style)
  }

  private mutating func nextFrameParts(area: Rect) -> ([CursorStroke], Offset?, CursorStyle) {
    if below(4) == 0 {
      // Unchanged frame.
      return (strokes, caret, style)
    }
    if below(2) == 0 {
      let texts = ["a", "bc", "界", "x界y", "  ", "longer text"]
      let stroke = CursorStroke(
        text: texts[below(texts.count)], offset: offset(in: area),
        style: Self.palette[below(Self.palette.count)])
      if strokes.count > 4 || below(4) == 0 { strokes.removeFirst(min(strokes.count, 2)) }
      strokes.append(stroke)
    }
    if below(2) == 0 {
      switch below(6) {
      case 0: caret = nil
      case 1: style = Self.styles[below(Self.styles.count)]
      case 2:
        caret = offset(in: area)
        style = Self.styles[below(Self.styles.count)]
      default:
        // A text-input caret moving along its row.
        let current = caret ?? Offset(x: 0, y: below(area.height))
        caret = Offset(x: (current.x + 1) % area.width, y: current.y)
      }
    }
    return (strokes, caret, style)
  }

  mutating func next(area: Rect) -> CursorStep {
    switch below(20) {
    case 0: return .clear
    case 1:
      return .outOfBand(Self.outOfBand[below(Self.outOfBand.count)])
    case 2 where scenario.supportsHistory:
      return .history(height: 1 + below(3), text: "history \(below(100))")
    case 3 where scenario.fixedArea != nil:
      return .resize(
        Rect(x: below(3), y: below(2), width: 6 + below(4), height: 2 + below(3)))
    case 4: return .setCursor(below(3) == 0 ? nil : offset(in: area))
    case 5: return .setCursorStyle(Self.styles[below(Self.styles.count)])
    case 6:
      let (strokes, caret, style) = nextFrameParts(area: area)
      return .failingFrame(strokes: strokes, caret: caret, style: style)
    case 7:
      let (strokes, caret, style) = nextFrameParts(area: area)
      return .discardedFrame(strokes: strokes, caret: caret, style: style)
    default:
      let (strokes, caret, style) = nextFrameParts(area: area)
      return .frame(strokes: strokes, caret: caret, style: style)
    }
  }
}

// MARK: - Harness

struct CursorEquivalenceHarness {
  let scenario: CursorScenario
  let oldSink = FrameOutputSink()
  let newSink = FrameOutputSink()
  let oldOutput: TransactionalTerminalOutput
  let newOutput: TransactionalTerminalOutput
  var old: Terminal<LegacyFrameBackend>
  var new: Terminal<ANSIBackend>
  var oldScreen: CursorScreen
  var newScreen: CursorScreen
  private(set) var area: Rect
  private(set) var oldBytes = 0
  private(set) var newBytes = 0

  init(scenario: CursorScenario) throws {
    self.scenario = scenario
    oldOutput = TransactionalTerminalOutput(directWrite: oldSink.write)
    newOutput = TransactionalTerminalOutput(directWrite: newSink.write)
    old = try Terminal(
      backend: LegacyFrameBackend(inner: scenario.makeBackend(output: oldOutput)),
      viewport: scenario.viewport)
    var backend = scenario.makeBackend(output: newOutput)
    let newOutput = newOutput
    backend.outputGeneration = { newOutput.generation }
    var sizing = backend
    let size = try sizing.size()
    new = try Terminal(backend: backend, viewport: scenario.viewport)
    oldScreen = CursorScreen(size: scenario.screen, savedCursor: scenario.savedCursor)
    newScreen = oldScreen
    area = scenario.fixedArea ?? Rect(size: size)
  }

  /// Applies `step` to both terminals and compares the virtual screens. Returns `false` after the
  /// first mismatch.
  mutating func perform(_ step: CursorStep, label: String) throws -> Bool {
    let oldSink = oldSink
    let newSink = newSink
    let oldOutput = oldOutput
    let newOutput = newOutput
    let oldFailed = Self.apply(step, to: &old, sink: oldSink, output: oldOutput)
    let newFailed = Self.apply(step, to: &new, sink: newSink, output: newOutput)
    if case .resize(let area) = step { self.area = area }
    let oldStep = oldSink.take()
    let newStep = newSink.take()
    oldBytes += oldStep.count
    newBytes += newStep.count
    try oldScreen.apply(oldStep)
    try newScreen.apply(newStep)
    #expect(oldScreen == newScreen, "\(label)")
    if case .frame = step {
      #expect(oldFailed == nil && newFailed == nil, "\(label)")
      #expect(!newScreen.isSynchronizing, "\(label)")
    }
    if case .failingFrame = step {
      // A frame with nothing to write cannot fail any more; nothing reached either terminal.
      #expect(oldStep.isEmpty && newStep.isEmpty, "\(label)")
    }
    return oldScreen == newScreen
  }

  /// Returns the error the step threw, if any.
  private static func apply<B: InlineHistoryBackend>(
    _ step: CursorStep,
    to terminal: inout Terminal<B>,
    sink: FrameOutputSink,
    output: TransactionalTerminalOutput
  ) -> (any Error)? {
    func draw(_ strokes: [CursorStroke], _ caret: Offset?, _ style: CursorStyle) throws {
      try terminal.draw { frame in
        for stroke in strokes { stroke.render(into: &frame) }
        let area = frame.area
        frame.placeCursor(
          at: caret.map { Position(x: area.x + $0.x, y: area.y + $0.y) }, style: style)
      }
    }
    do {
      switch step {
      case .frame(let strokes, let caret, let style):
        try draw(strokes, caret, style)
      case .failingFrame(let strokes, let caret, let style):
        sink.failsNextWrite = true
        defer { sink.failsNextWrite = false }
        try draw(strokes, caret, style)
      case .discardedFrame(let strokes, let caret, let style):
        let rollback = terminal.frameRollback()
        defer { terminal.rollBack(to: rollback) }
        try output.withTransaction { () throws -> Void in
          try draw(strokes, caret, style)
          throw CursorTestError.discarded
        }
      case .clear:
        try terminal.clear()
      case .resize(let area):
        try terminal.resize(to: area)
      case .outOfBand(let text):
        try output.write(Data(text.utf8))
      case .history(let height, let text):
        try terminal.insertBefore(height: height) { buffer in
          buffer.setString(text, at: Position(x: 0, y: 0))
        }
      case .setCursor(let offset):
        let position = offset.map { Position(x: $0.x, y: $0.y) }
        try terminal.withBackend { try $0.setCursor(position) }
      case .setCursorStyle(let style):
        try terminal.withBackend { try $0.setCursorStyle(style) }
      }
      return nil
    } catch {
      return error
    }
  }
}

// MARK: - Virtual terminal

struct CursorScreenCell: Hashable {
  var text: String
  var rendition: VirtualRendition

  static let blank = Self(text: " ", rendition: VirtualRendition())
}

/// A small ANSI interpreter for everything `ANSIBackend` and `TerminalSession` emit: text with
/// auto-wrap, CR, LF (scrolling within the margins, scrolled-off top rows become scrollback),
/// ESC 7/8 (position and rendition), CUP, CHA, CUU, CUD, ED, EL, ECH, DECSTBM, SU, SD, SGR,
/// DECSCUSR, and the private modes 7 (auto-wrap), 25 (cursor visible) and 2026 (synchronized).
struct CursorScreen: Equatable {
  let width: Int
  let height: Int
  var rows: [[CursorScreenCell]]
  var scrollback: [[CursorScreenCell]] = []
  var cursor = Position(x: 0, y: 0)
  var savedCursor: Position
  var savedRendition = VirtualRendition()
  var rendition = VirtualRendition()
  var isCursorVisible = true
  var cursorShape = 0
  var autoWrap = true
  var isSynchronizing = false
  var marginTop = 0
  var marginBottom: Int

  init(size: Size, savedCursor: Position) {
    width = size.width
    height = size.height
    rows = Array(
      repeating: Array(repeating: CursorScreenCell.blank, count: size.width), count: size.height)
    self.savedCursor = savedCursor
    marginBottom = size.height - 1
  }

  mutating func apply(_ bytes: [UInt8]) throws {
    var index = 0
    var textStart = 0
    while index < bytes.count {
      let byte = bytes[index]
      guard byte == 0x1B || byte == 0x0D || byte == 0x0A else {
        index += 1
        continue
      }
      write(bytes[textStart..<index])
      if byte == 0x0D {
        cursor.x = 0
        index += 1
      } else if byte == 0x0A {
        lineFeed()
        index += 1
      } else {
        guard index + 1 < bytes.count else { throw VirtualTerminalError.unsupported("lone ESC") }
        switch bytes[index + 1] {
        case 0x37:
          savedCursor = cursor
          savedRendition = rendition
          index += 2
        case 0x38:
          cursor = savedCursor
          rendition = savedRendition
          index += 2
        case 0x5B:
          index = try controlSequence(bytes, start: index + 2)
        default:
          throw VirtualTerminalError.unsupported("ESC \(bytes[index + 1])")
        }
      }
      textStart = index
    }
    write(bytes[textStart..<bytes.count])
  }

  private mutating func controlSequence(_ bytes: [UInt8], start: Int) throws -> Int {
    var end = start
    var prefix: UInt8?
    if end < bytes.count, (0x3C...0x3F).contains(bytes[end]) {
      prefix = bytes[end]
      end += 1
    }
    var parameters: [Int] = []
    var current: Int?
    while end < bytes.count, bytes[end] == 0x3B || (0x30...0x39).contains(bytes[end]) {
      if bytes[end] == 0x3B {
        parameters.append(current ?? 0)
        current = nil
      } else {
        current = (current ?? 0) &* 10 &+ Int(bytes[end] - 0x30)
      }
      end += 1
    }
    parameters.append(current ?? 0)
    var intermediate: UInt8?
    while end < bytes.count, (0x20...0x2F).contains(bytes[end]) {
      intermediate = bytes[end]
      end += 1
    }
    guard end < bytes.count else { throw VirtualTerminalError.unsupported("truncated CSI") }
    try execute(
      final: bytes[end], parameters: parameters, prefix: prefix, intermediate: intermediate)
    return end + 1
  }

  private mutating func execute(
    final: UInt8, parameters: [Int], prefix: UInt8?, intermediate: UInt8?
  ) throws {
    let first = parameters[0]
    let count = max(1, first)
    switch (final, prefix, intermediate) {
    case (0x48, nil, nil):
      let column = parameters.count > 1 ? parameters[1] : 1
      cursor = Position(
        x: min(width - 1, max(1, column) - 1), y: min(height - 1, max(1, first) - 1))
    case (0x47, nil, nil):
      cursor.x = min(width - 1, count - 1)
    case (0x41, nil, nil):
      cursor = Position(x: min(cursor.x, width - 1), y: max(0, cursor.y - count))
    case (0x42, nil, nil):
      cursor = Position(x: min(cursor.x, width - 1), y: min(height - 1, cursor.y + count))
    case (0x4A, nil, nil):
      try eraseDisplay(first)
    case (0x4B, nil, nil):
      try eraseLine(first)
    case (0x58, nil, nil):
      let y = min(cursor.y, height - 1)
      for x in cursor.x..<min(width, cursor.x + count) { rows[y][x] = .blank }
    case (0x72, nil, nil):
      let top = max(1, first)
      let bottom = parameters.count > 1 && parameters[1] > 0 ? parameters[1] : height
      marginTop = min(height - 1, top - 1)
      marginBottom = max(marginTop, min(height - 1, bottom - 1))
      cursor = Position(x: 0, y: 0)
    case (0x53, nil, nil):
      for _ in 0..<count { scrollUp() }
    case (0x54, nil, nil):
      for _ in 0..<count { scrollDown() }
    case (0x6D, nil, nil):
      try applySGR(parameters)
    case (0x71, nil, 0x20?):
      cursorShape = first
    case (0x68, 0x3F?, nil), (0x6C, 0x3F?, nil):
      let enabled = final == 0x68
      switch first {
      case 7: autoWrap = enabled
      case 25: isCursorVisible = enabled
      case 2026: isSynchronizing = enabled
      default: throw VirtualTerminalError.unsupported("private mode \(first)")
      }
    default:
      throw VirtualTerminalError.unsupported("CSI \(parameters) \(final)")
    }
  }

  private mutating func write(_ text: ArraySlice<UInt8>) {
    guard !text.isEmpty else { return }
    for character in String(decoding: text, as: UTF8.self) {
      let characterWidth = max(1, TerminalWidth.of(character))
      if cursor.x + characterWidth > width {
        if autoWrap {
          cursor.x = 0
          lineFeed()
        } else {
          cursor.x = max(0, width - characterWidth)
        }
      }
      rows[cursor.y][cursor.x] = CursorScreenCell(
        text: String(character), rendition: rendition)
      for offset in 1..<characterWidth where cursor.x + offset < width {
        rows[cursor.y][cursor.x + offset] = CursorScreenCell(text: "", rendition: rendition)
      }
      // At the right margin the cursor stays past the last column until the next character wraps.
      cursor.x += characterWidth
    }
  }

  private mutating func lineFeed() {
    if cursor.y == marginBottom {
      scrollUp()
    } else if cursor.y < height - 1 {
      cursor.y += 1
    }
  }

  private mutating func scrollUp() {
    let removed = rows.remove(at: marginTop)
    if marginTop == 0 { scrollback.append(removed) }
    rows.insert(Array(repeating: .blank, count: width), at: marginBottom)
  }

  private mutating func scrollDown() {
    rows.remove(at: marginBottom)
    rows.insert(Array(repeating: .blank, count: width), at: marginTop)
  }

  private mutating func eraseDisplay(_ mode: Int) throws {
    let x = min(cursor.x, width - 1)
    switch mode {
    case 0:
      for column in x..<width { rows[cursor.y][column] = .blank }
      for row in (cursor.y + 1)..<height { rows[row] = Array(repeating: .blank, count: width) }
    case 1:
      for row in 0..<cursor.y { rows[row] = Array(repeating: .blank, count: width) }
      for column in 0...x { rows[cursor.y][column] = .blank }
    case 2:
      rows = Array(repeating: Array(repeating: .blank, count: width), count: height)
    case 3:
      scrollback.removeAll()
    default:
      throw VirtualTerminalError.unsupported("ED \(mode)")
    }
  }

  private mutating func eraseLine(_ mode: Int) throws {
    let x = min(cursor.x, width - 1)
    switch mode {
    case 0:
      for column in x..<width { rows[cursor.y][column] = .blank }
    case 1:
      for column in 0...x { rows[cursor.y][column] = .blank }
    case 2:
      rows[cursor.y] = Array(repeating: .blank, count: width)
    default:
      throw VirtualTerminalError.unsupported("EL \(mode)")
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
        guard index < parameters.count else { throw VirtualTerminalError.unsupported("SGR") }
        let color: VirtualColor
        if parameters[index] == 5, index + 1 < parameters.count {
          color = .indexed(parameters[index + 1])
          index += 2
        } else if parameters[index] == 2, index + 3 < parameters.count {
          color = .rgb(parameters[index + 1], parameters[index + 2], parameters[index + 3])
          index += 4
        } else {
          throw VirtualTerminalError.unsupported("SGR extended color \(parameters)")
        }
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
}
