import Foundation
import TermLoomTestSupport
import Testing

@testable import TermLoom

private struct MinimalBackend: Backend {
  var drawnUpdates: [CellUpdate] = []

  mutating func size() throws -> Size { Size(width: 4, height: 1) }
  mutating func draw(_ updates: [CellUpdate]) throws { drawnUpdates = updates }
  mutating func clear() throws { drawnUpdates = [] }
}

private enum InjectedOutputError: Error {
  case failed
}

private final class FailOnceOutput {
  var bytes: [UInt8] = []
  var callCount = 0
  let failingCall: Int

  init(failingCall: Int) {
    self.failingCall = failingCall
  }

  func write(_ data: Data) throws {
    callCount += 1
    if callCount == failingCall { throw InjectedOutputError.failed }
    bytes.append(contentsOf: data)
  }
}

private final class RecordedOutput {
  var writes: [Data] = []

  func write(_ data: Data) {
    writes.append(data)
  }
}

private final class PartiallyFailingOutput {
  var bytes: [UInt8] = []
  var callCount = 0
  let failingCall: Int
  let writtenPrefixCount: Int

  init(failingCall: Int, writtenPrefixCount: Int) {
    self.failingCall = failingCall
    self.writtenPrefixCount = writtenPrefixCount
  }

  func write(_ data: Data) throws {
    callCount += 1
    if callCount == failingCall {
      bytes.append(contentsOf: data.prefix(writtenPrefixCount))
      throw InjectedOutputError.failed
    }
    bytes.append(contentsOf: data)
  }
}

private func historyBuffer(_ content: String, width: Int = 10) -> Buffer {
  var buffer = Buffer(area: Rect(x: 0, y: 0, width: width, height: 1))
  buffer.setString(content, at: Position(x: 0, y: 0))
  return buffer
}

private func terminalOutputBackend() -> ANSIBackend {
  ANSIBackend(
    fallbackSize: Size(width: 10, height: 8),
    viewportHeight: 2,
    viewportOrigin: Position(x: 0, y: 1),
    cursorAddressing: .absoluteOrigin(Position(x: 0, y: 1)),
    configuration: ANSIBackendConfiguration(historyInsertionStrategy: .terminalOutput)
  )
}

@Suite struct BackendTests {
  @Test func minimalBackendDoesNotImplementAdvancedHistoryOperations() throws {
    var terminal = try Terminal(backend: MinimalBackend())
    _ = try terminal.draw { frame in frame.render(Text("core")) }
    #expect(terminal.backend.drawnUpdates.count == 4)
    #expect(terminal.backend.capabilities.isEmpty)
  }

  @Test func cursorStylesUseDECSCUSRAndAreObservableInTests() throws {
    var testBackend = TestBackend(width: 10, height: 2)
    try testBackend.setCursorStyle(.steadyBar)
    #expect(testBackend.cursorStyle == .steadyBar)

    let pipe = Pipe()
    var ansi = ANSIBackend(
      output: pipe.fileHandleForWriting,
      fallbackSize: Size(width: 10, height: 2))
    try ansi.setCursorStyle(.steadyBar)
    try ansi.setCursorStyle(.defaultUserShape)
    try pipe.fileHandleForWriting.close()
    let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    #expect(output == "\u{1B}[6 q\u{1B}[0 q")
  }

  @Test func testBackendScrollsRegionsAndCapturesScrollback() throws {
    var backend = TestBackend(width: 1, height: 4)
    try backend.draw(
      ["A", "B", "C", "D"].enumerated().map {
        CellUpdate(position: Position(x: 0, y: Int($0.offset)), cell: Cell(symbol: $0.element))
      }
    )

    try backend.scrollRegionUp(0..<4, by: 2)
    assertTerminal(backend.buffer) {
      """
      │C│
      │D│
      │ │
      │ │
      """
    }
    #expect(backend.scrollback.map { $0[0].symbol } == ["A", "B"])

    try backend.scrollRegionDown(0..<3, by: 1)
    assertTerminal(backend.buffer) {
      """
      │ │
      │C│
      │D│
      │ │
      """
    }
  }

  @Test func appendLinesPreservesOverflowAsBlankScrollbackRows() throws {
    var backend = TestBackend(width: 1, height: 5)
    try backend.draw(
      ["A", "B", "C", "D", "E"].enumerated().map {
        CellUpdate(position: Position(x: 0, y: Int($0.offset)), cell: Cell(symbol: $0.element))
      }
    )
    try backend.setCursor(Position(x: 0, y: 4))
    try backend.appendLines(8)

    assertTerminal(backend.buffer) {
      """
      │ │
      │ │
      │ │
      │ │
      │ │
      """
    }
    #expect(backend.scrollback.map { $0[0].symbol } == ["A", "B", "C", "D", "E", " ", " ", " "])
    #expect(backend.cursorPosition == Position(x: 0, y: 4))
  }

  @Test func backendFacetsAndWindowSizeAreExplicit() throws {
    var backend = TestBackend(width: 80, height: 24)
    let _: any LineAppendingBackend = backend
    let _: any InlineHistoryBackend = backend
    #expect(
      try backend.windowSize()
        == WindowSize(
          cells: Size(width: 80, height: 24),
          pixels: Size(width: 640, height: 480)
        ))
  }

  @Test func ansiRegionScrollingUsesScopedMargins() throws {
    let pipe = Pipe()
    var backend = ANSIBackend(
      output: pipe.fileHandleForWriting,
      fallbackSize: Size(width: 10, height: 10)
    )

    try backend.scrollRegionUp(2..<7, by: 3)
    try backend.scrollRegionUpIntoScrollback(2..<7, by: 3)
    try backend.scrollRegionDown(1..<5, by: 2)
    try pipe.fileHandleForWriting.close()

    let output = String(
      decoding: pipe.fileHandleForReading.readDataToEndOfFile(),
      as: UTF8.self
    )
    assertTerminalCodes(output) {
      """
      <ESC>7<ESC>[3;7r<ESC>[3S<ESC>[r<ESC>8<ESC>7<ESC>[3;7r<ESC>[7;1H<CR>
      <CR>
      <CR>
      <ESC>[r<ESC>8<ESC>7<ESC>[2;5r<ESC>[2T<ESC>[r<ESC>8
      """
    }
  }

  @Test func supatermSelectsWholeTerminalHistoryInsertion() {
    let configuration = ANSIBackendConfiguration.detected(environment: [
      "TERM": "xterm-ghostty", "SUPATERM_SOCKET_PATH": "/tmp/supaterm.sock",
    ])
    #expect(configuration.historyInsertionStrategy == .terminalOutput)
    #expect(
      ANSIBackendConfiguration.detected(environment: ["TERM": "xterm-ghostty"])
        .historyInsertionStrategy == .scrollingRegion)
  }

  @Test func terminalOutputHistoryClearsTheLivePaneAndReservesItAgain() throws {
    let pipe = Pipe()
    var backend = ANSIBackend(
      output: pipe.fileHandleForWriting,
      fallbackSize: Size(width: 10, height: 6), viewportHeight: 2,
      viewportOrigin: Position(x: 0, y: 4),
      cursorAddressing: .absoluteOrigin(Position(x: 0, y: 4)),
      configuration: ANSIBackendConfiguration(
        supportsSynchronizedOutput: true, historyInsertionStrategy: .terminalOutput))
    var history = Buffer(area: Rect(x: 0, y: 0, width: 10, height: 2))
    history.setString("FIRST", at: Position(x: 0, y: 0))
    history.setString("SECOND", at: Position(x: 0, y: 1))

    #expect(try backend.insertHistory(history))
    #expect(backend.viewportOrigin == Position(x: 0, y: 4))
    try pipe.fileHandleForWriting.close()
    let output = String(
      decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    #expect(output.contains("\u{1B}[r\u{1B}[?7l\u{1B}[5;1H\u{1B}[2K"))
    #expect(output.contains("\u{1B}[0m\u{1B}[?7h"))
    let historyStart = output.range(of: "\u{1B}[r\u{1B}[?7l")!.lowerBound
    #expect(!output[historyStart...].contains("\u{1B}[?2026"))
    #expect(output.contains("FIRST\u{1B}[0m\r\n\u{1B}[2K"))
    #expect(output.contains("SECOND\u{1B}[0m\r\n\u{1B}[2K\r\n\u{1B}[2K"))
    #expect(!output.contains("\u{1B}[1;4r"))
  }

  @Test func terminalOutputHistorySerializesMappedStyledAndWideCells() throws {
    let output = RecordedOutput()
    var backend = terminalOutputBackend()
    backend.outputWriter = output.write
    var history = Buffer(area: Rect(x: 3, y: 4, width: 8, height: 2))
    history.setString(
      "Q界Z", at: Position(x: 4, y: 4),
      style: Style(foreground: .red, modifiers: [.bold]))
    history.setString(
      "R", at: Position(x: 5, y: 5),
      style: Style(foreground: .cyan, modifiers: [.underlined]))

    #expect(try backend.insertHistory(history))
    #expect(output.writes.count == 2)
    let transaction = String(decoding: output.writes.last ?? Data(), as: UTF8.self)
    #expect(transaction.contains("\u{1B}[0;1;31mQ界Z\u{1B}[0m"))
    #expect(transaction.contains("\u{1B}[0;4;36mR\u{1B}[0m"))
    #expect(transaction.components(separatedBy: "Q").count - 1 == 1)
    #expect(transaction.components(separatedBy: "界").count - 1 == 1)
    #expect(transaction.components(separatedBy: "Z").count - 1 == 1)
    #expect(transaction.components(separatedBy: "R").count - 1 == 1)
  }

  @Test func terminalOutputHistoryRestoresAMappedRetainedViewportAtTheLogicalOrigin() throws {
    let output = RecordedOutput()
    var backend = terminalOutputBackend()
    backend.outputWriter = output.write
    var history = Buffer(area: Rect(x: 3, y: 4, width: 6, height: 1))
    history.setString("HIST", at: Position(x: 3, y: 4))
    var viewport = Buffer(area: Rect(x: 7, y: 9, width: 6, height: 2))
    viewport.setString("L界VE", at: Position(x: 7, y: 9))
    viewport.setString("TAIL", at: Position(x: 7, y: 10))

    #expect(
      try backend.insertHistory(history, batchPosition: .single, restoring: viewport))
    #expect(output.writes.count == 1)
    let transaction = String(decoding: output.writes[0], as: UTF8.self)
    let historyRange = transaction.range(of: "HIST")
    let synchronizationRange = transaction.range(of: "\u{1B}[?2026h")
    let liveRange = transaction.range(of: "L界VE")
    #expect(historyRange != nil)
    #expect(synchronizationRange != nil)
    #expect(liveRange != nil)
    if let historyRange, let synchronizationRange, let liveRange {
      #expect(historyRange.upperBound <= synchronizationRange.lowerBound)
      #expect(synchronizationRange.upperBound <= liveRange.lowerBound)
    }
    #expect(transaction.contains("\u{1B}[3;1H\u{1B}[2K"))
    #expect(transaction.contains("\u{1B}[4;1H\u{1B}[2K"))
    #expect(!transaction.contains("\u{1B}[3;8H"))
    #expect(transaction.components(separatedBy: "界").count - 1 == 1)
    #expect(transaction.components(separatedBy: "TAIL").count - 1 == 1)
  }

  @Test func terminalOutputHistoryBatchReservesLiveRowsOnlyAfterFinalChunk() throws {
    let pipe = Pipe()
    var backend = ANSIBackend(
      output: pipe.fileHandleForWriting,
      fallbackSize: Size(width: 10, height: 6), viewportHeight: 2,
      viewportOrigin: Position(x: 0, y: 4),
      cursorAddressing: .absoluteOrigin(Position(x: 0, y: 4)),
      configuration: ANSIBackendConfiguration(historyInsertionStrategy: .terminalOutput))
    var first = Buffer(area: Rect(x: 0, y: 0, width: 10, height: 1))
    first.setString("FIRST", at: Position(x: 0, y: 0))
    var last = Buffer(area: Rect(x: 0, y: 0, width: 10, height: 1))
    last.setString("LAST", at: Position(x: 0, y: 0))

    #expect(try backend.insertHistory(first, batchPosition: .first))
    #expect(try backend.insertHistory(last, batchPosition: .last))
    try pipe.fileHandleForWriting.close()
    let output = String(
      decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

    #expect(output.components(separatedBy: "\u{1B}[?7l").count - 1 == 1)
    #expect(output.components(separatedBy: "\u{1B}[?7h").count - 1 == 1)
    #expect(output.contains("FIRST\u{1B}[0m\r\n\u{1B}[2K\u{1B}[0mLAST"))
    #expect(output.hasSuffix("\r\n\u{1B}[2K\r\n\u{1B}[2K\u{1B}[0m\u{1B}[?7h"))
  }

  @Test func terminalRestoresLiveViewportInTheFinalHistoryWrite() throws {
    let output = RecordedOutput()
    var backend = ANSIBackend(
      fallbackSize: Size(width: 10, height: 6),
      viewportHeight: 2,
      viewportOrigin: Position(x: 0, y: 4),
      cursorAddressing: .absoluteOrigin(Position(x: 0, y: 4)),
      configuration: ANSIBackendConfiguration(historyInsertionStrategy: .terminalOutput)
    )
    backend.outputWriter = output.write
    var terminal = try Terminal(backend: backend)
    try terminal.draw { frame in
      frame.render(Paragraph("LIVE-A\nLIVE-B"))
    }
    output.writes.removeAll()

    try terminal.insertBefore(height: 1) { buffer in
      buffer.setString("HISTORY", at: Position(x: 0, y: 0))
    }

    #expect(output.writes.count == 1)
    let transaction = String(decoding: output.writes[0], as: UTF8.self)
    let history = transaction.range(of: "HISTORY")!
    let synchronization = transaction.range(of: "\u{1B}[?2026h")!
    let live = transaction.range(of: "LIVE-A")!
    #expect(history.upperBound <= synchronization.lowerBound)
    #expect(synchronization.upperBound <= live.lowerBound)
    #expect(transaction.hasSuffix("\u{1B}[?2026l"))

    output.writes.removeAll()
    let completed = try terminal.draw { frame in
      frame.render(Paragraph("LIVE-A\nLIVE-B"))
    }
    #expect(completed.updates == 0)
  }

  @Test func failedAtomicHistoryRestorationCleansUpAndCanRetry() throws {
    let initialOutput = RecordedOutput()
    var backend = terminalOutputBackend()
    backend.outputWriter = initialOutput.write
    var terminal = try Terminal(backend: backend)
    try terminal.draw { frame in
      frame.render(Paragraph("LIVE-A\nLIVE-B"))
    }

    let failedOutput = PartiallyFailingOutput(failingCall: 1, writtenPrefixCount: 16)
    terminal.withBackend { $0.outputWriter = failedOutput.write }
    #expect(throws: InjectedOutputError.self) {
      try terminal.insertBefore(height: 1) { buffer in
        buffer.setString("FAILED", at: Position(x: 0, y: 0))
      }
    }
    try terminal.insertBefore(height: 1) { buffer in
      buffer.setString("RECOVERED", at: Position(x: 0, y: 0))
    }

    let output = String(decoding: failedOutput.bytes, as: UTF8.self)
    #expect(output.contains("\u{1B}[r\u{1B}[0m\u{1B}[?7h"))
    #expect(output.contains("RECOVERED"))
    #expect(output.contains("LIVE-A"))
    #expect(output.hasSuffix("\u{1B}[?2026l"))
    #expect(terminal.backend.viewportOrigin == Position(x: 0, y: 2))
  }

  @Test func failedHistoryChunkRestoresProtocolsAndDiscardsTheBatch() throws {
    let sink = FailOnceOutput(failingCall: 2)
    var backend = ANSIBackend(
      fallbackSize: Size(width: 10, height: 6), viewportHeight: 2,
      viewportOrigin: Position(x: 0, y: 4),
      cursorAddressing: .absoluteOrigin(Position(x: 0, y: 4)),
      configuration: ANSIBackendConfiguration(historyInsertionStrategy: .terminalOutput))
    backend.outputWriter = sink.write
    var failed = Buffer(area: Rect(x: 0, y: 0, width: 10, height: 1))
    failed.setString("FAILED", at: Position(x: 0, y: 0))
    var recovered = Buffer(area: Rect(x: 0, y: 0, width: 10, height: 1))
    recovered.setString("RECOVERED", at: Position(x: 0, y: 0))

    #expect(throws: InjectedOutputError.self) {
      _ = try backend.insertHistory(failed, batchPosition: .first)
    }
    #expect(try backend.insertHistory(recovered, batchPosition: .last))

    let output = String(decoding: sink.bytes, as: UTF8.self)
    #expect(output.contains("\u{1B}[r\u{1B}[0m\u{1B}[?7h"))
    #expect(output.contains("RECOVERED"))
    #expect(!output.contains("FAILED"))
    #expect(output.hasSuffix("\r\n\u{1B}[2K\r\n\u{1B}[2K\u{1B}[0m\u{1B}[?7h"))
  }

  @Test func failedHistoryChunksAtEveryBatchPositionDiscardTransactionState() throws {
    let scenarios:
      [(
        preceding: [HistoryInsertionBatchPosition], failed: HistoryInsertionBatchPosition, call: Int
      )] = [
        ([], .single, 2),
        ([], .first, 2),
        ([.first], .middle, 3),
        ([.first, .middle], .last, 4),
        ([], .first, 1),
      ]

    for scenario in scenarios {
      let sink = FailOnceOutput(failingCall: scenario.call)
      var backend = terminalOutputBackend()
      backend.outputWriter = sink.write
      for (index, position) in scenario.preceding.enumerated() {
        #expect(
          try backend.insertHistory(
            historyBuffer("PRE-\(index)"),
            batchPosition: position
          ))
      }

      #expect(throws: InjectedOutputError.self) {
        _ = try backend.insertHistory(
          historyBuffer("FAILED"),
          batchPosition: scenario.failed
        )
      }
      #expect(try backend.insertHistory(historyBuffer("RECOVERED")))
      #expect(backend.viewportOrigin == Position(x: 0, y: 2))

      let output = String(decoding: sink.bytes, as: UTF8.self)
      #expect(output.contains("\u{1B}[r\u{1B}[0m\u{1B}[?7h"))
      #expect(output.contains("RECOVERED"))
      #expect(!output.contains("FAILED"))
      #expect(output.hasSuffix("\r\n\u{1B}[2K\r\n\u{1B}[2K\u{1B}[0m\u{1B}[?7h"))
    }
  }

  @Test func partialHistoryWriteStillRestoresProtocolsAndAllowsRecovery() throws {
    let sink = PartiallyFailingOutput(failingCall: 2, writtenPrefixCount: 12)
    var backend = terminalOutputBackend()
    backend.outputWriter = sink.write

    #expect(throws: InjectedOutputError.self) {
      _ = try backend.insertHistory(historyBuffer("PARTIAL"), batchPosition: .first)
    }
    #expect(try backend.insertHistory(historyBuffer("RECOVERED")))
    #expect(backend.viewportOrigin == Position(x: 0, y: 2))

    let output = String(decoding: sink.bytes, as: UTF8.self)
    #expect(output.contains("\u{1B}[?7l"))
    #expect(output.contains("\u{1B}[r\u{1B}[0m\u{1B}[?7h"))
    #expect(output.contains("RECOVERED"))
    #expect(output.hasSuffix("\r\n\u{1B}[2K\r\n\u{1B}[2K\u{1B}[0m\u{1B}[?7h"))
  }

  @Test func missingFirstBatchMarkerStartsARecoverableTransaction() throws {
    let pipe = Pipe()
    var backend = terminalOutputBackend()
    backend.outputWriter = { data in try pipe.fileHandleForWriting.write(contentsOf: data) }

    #expect(try backend.insertHistory(historyBuffer("MIDDLE"), batchPosition: .middle))
    #expect(try backend.insertHistory(historyBuffer("LAST"), batchPosition: .last))
    #expect(backend.viewportOrigin == Position(x: 0, y: 3))
    try pipe.fileHandleForWriting.close()

    let output = String(
      decoding: pipe.fileHandleForReading.readDataToEndOfFile(),
      as: UTF8.self
    )
    #expect(output.components(separatedBy: "\u{1B}[?7l").count - 1 == 1)
    #expect(output.components(separatedBy: "\u{1B}[?7h").count - 1 == 1)
    #expect(output.contains("MIDDLE\u{1B}[0m\r\n\u{1B}[2K\u{1B}[0mLAST"))
  }

  @Test func fullWidthHistoryRowsDoNotAutowrapOrEmitClippedCells() throws {
    let pipe = Pipe()
    var backend = ANSIBackend(
      output: pipe.fileHandleForWriting,
      fallbackSize: Size(width: 4, height: 4),
      viewportHeight: 1,
      viewportOrigin: Position(x: 0, y: 1),
      cursorAddressing: .absoluteOrigin(Position(x: 0, y: 1)),
      configuration: ANSIBackendConfiguration(historyInsertionStrategy: .terminalOutput)
    )
    var row = Buffer(area: Rect(x: 0, y: 0, width: 4, height: 1))
    row.setString("ABCDE", at: Position(x: 0, y: 0))

    #expect(try backend.insertHistory(row))
    try pipe.fileHandleForWriting.close()
    let output = String(
      decoding: pipe.fileHandleForReading.readDataToEndOfFile(),
      as: UTF8.self
    )
    let disabledWrap = output.range(of: "\u{1B}[?7l")!.upperBound
    let rowContent = output.range(of: "ABCD")!
    let enabledWrap = output.range(of: "\u{1B}[?7h")!.lowerBound
    #expect(disabledWrap <= rowContent.lowerBound)
    #expect(rowContent.upperBound <= enabledWrap)
    #expect(!output.contains("ABCDE"))
  }

  @Test func testBackendClearsRelativeToCursor() throws {
    var backend = TestBackend(width: 4, height: 3)
    try backend.draw(
      (0..<12).map {
        CellUpdate(
          position: Position(x: Int($0 % 4), y: Int($0 / 4)),
          cell: Cell(symbol: "X")
        )
      }
    )
    try backend.setCursor(Position(x: 1, y: 1))

    try backend.clear(.untilNewLine)
    assertTerminal(backend.buffer) {
      """
      │XXXX│
      │X   │
      │XXXX│
      """
    }
    try backend.clear(.beforeCursor)
    assertTerminal(backend.buffer) {
      """
      │    │
      │    │
      │XXXX│
      """
    }
  }

  @Test func ansiBackendEmitsScopedClearSequences() throws {
    let pipe = Pipe()
    var backend = ANSIBackend(
      output: pipe.fileHandleForWriting,
      fallbackSize: Size(width: 10, height: 10)
    )
    try backend.clear(.afterCursor)
    try backend.clear(.beforeCursor)
    try backend.clear(.currentLine)
    try backend.clear(.untilNewLine)
    try pipe.fileHandleForWriting.close()

    let output = String(
      decoding: pipe.fileHandleForReading.readDataToEndOfFile(),
      as: UTF8.self
    )
    assertTerminalCodes(output) {
      """
      <ESC>[0J<ESC>[1J<ESC>[2K<ESC>[0K
      """
    }
  }
}
