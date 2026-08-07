import RatatuiTestSupport
import Testing

@testable import Ratatui

private struct VisualOnlyHistoryBackend: InlineHistoryBackend {
  var visualScrollCount = 0
  private var origin = Position(x: 0, y: 0)

  var capabilities: BackendCapabilities { [.inlineViewport] }
  var viewportOrigin: Position { origin }

  mutating func setViewportOrigin(_ origin: Position) throws { self.origin = origin }
  mutating func size() throws -> Size { Size(width: 4, height: 1) }
  mutating func draw(_ updates: [CellUpdate]) throws {}
  mutating func clear() throws {}
  mutating func scrollRegionUp(_ rows: Range<Int>, by count: Int) throws {
    visualScrollCount += 1
  }
  mutating func scrollRegionDown(_ rows: Range<Int>, by count: Int) throws {}
}

@Suite struct InlineInsertionTests {
  @Test func insertsRowsAboveBottomAnchoredViewportWithoutRedrawingIt() throws {
    var backend = TestBackend(
      screenWidth: 4,
      screenHeight: 6,
      viewport: Rect(x: 0, y: 4, width: 4, height: 2)
    )
    for (row, line) in ["AAAA", "BBBB", "CCCC", "DDDD"].enumerated() {
      for (column, character) in line.enumerated() {
        backend.setScreenCell(
          Cell(symbol: String(character)),
          at: Position(x: column, y: row)
        )
      }
    }

    var terminal = try Terminal(backend: backend)
    try terminal.draw { frame in
      frame.render(Paragraph("VIEW\nPORT", wrap: .none))
    }
    try terminal.insertBefore(height: 2) { buffer in
      buffer.setString("LOG1", at: Position(x: 0, y: 0))
      buffer.setString("LOG2", at: Position(x: 0, y: 1))
    }

    assertTerminal(terminal.backend.buffer) {
      """
      │CCCC│
      │DDDD│
      │LOG1│
      │LOG2│
      │VIEW│
      │PORT│
      """
    }
    #expect(terminal.backend.viewportOrigin == Position(x: 0, y: 4))
  }

  @Test func insertionPushesInlineViewportDownWhenSpaceIsAvailable() throws {
    var backend = TestBackend(
      screenWidth: 10,
      screenHeight: 10,
      viewport: Rect(x: 0, y: 3, width: 10, height: 4)
    )
    for row in 0..<10 {
      for column in 0..<10 {
        backend.setScreenCell(
          Cell(symbol: String(row)),
          at: Position(x: column, y: row)
        )
      }
    }
    var terminal = try Terminal(backend: backend)
    try terminal.insertBefore(height: 1) { buffer in
      buffer.setString("INSERTLINE", at: Position(x: 0, y: 0))
    }

    assertTerminal(terminal.backend.buffer) {
      """
      │0000000000│
      │1111111111│
      │2222222222│
      │INSERTLINE│
      │3333333333│
      │4444444444│
      │5555555555│
      │6666666666│
      │8888888888│
      │9999999999│
      """
    }
    #expect(terminal.backend.viewportOrigin == Position(x: 0, y: 4))
  }

  @Test func genericHistoryFallbackAcceptsEveryBatchPositionIndependently() throws {
    var terminal = try Terminal(
      backend: TestBackend(
        screenWidth: 4,
        screenHeight: 2,
        viewport: Rect(x: 0, y: 0, width: 4, height: 2)
      )
    )
    try terminal.draw { frame in
      frame.render(Paragraph("VIEW\nPORT"))
    }

    for (content, position) in zip(
      ["A", "B", "C"],
      [
        HistoryInsertionBatchPosition.first,
        .middle,
        .last,
      ])
    {
      try terminal.insertBefore(height: 1, batchPosition: position) { buffer in
        buffer.setString(content, at: Position(x: 0, y: 0))
      }
    }

    #expect(terminal.backend.scrollback.map { $0[0].symbol } == ["A", "B", "C"])
    assertTerminal(terminal.backend.buffer) {
      """
      │VIEW│
      │PORT│
      """
    }
  }

  @Test func visualScrollingDoesNotSilentlySubstituteForNativeScrollback() throws {
    var terminal = try Terminal(backend: VisualOnlyHistoryBackend())

    do {
      try terminal.insertBefore(height: 1) { buffer in
        buffer.setString("LOG", at: Position(x: 0, y: 0))
      }
      Issue.record("Expected unsupported native scrollback insertion")
    } catch let error as BackendOperationError {
      #expect(error == .unsupported("native scrollback insertion"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }

    #expect(terminal.backend.visualScrollCount == 0)
  }

  @Test func inlineDocumentEmitsAppendOnlyRowsAndWaitsAtMutableBoundaries() {
    var runtime = InlineDocumentRuntime<String>()
    let initial = InlineDocument(
      id: "session",
      blocks: [
        InlineDocumentBlock(
          id: "stream", text: Text([Line("one")]), isComplete: false),
        InlineDocumentBlock(id: "later", text: Text([Line("later")]), isComplete: true),
      ])
    #expect(runtime.reconcile(initial, width: 80).map(\.text.lines) == [[Line("one")]])

    let growing = InlineDocument(
      id: "session",
      blocks: [
        InlineDocumentBlock(
          id: "stream", text: Text([Line("one"), Line("two")]), isComplete: false),
        InlineDocumentBlock(id: "later", text: Text([Line("later")]), isComplete: true),
      ])
    #expect(runtime.reconcile(growing, width: 80).map(\.text.lines) == [[Line("two")]])

    let completed = InlineDocument(
      id: "session",
      blocks: [
        InlineDocumentBlock(
          id: "stream", text: Text([Line("one"), Line("two")]), isComplete: true),
        InlineDocumentBlock(id: "later", text: Text([Line("later")]), isComplete: true),
      ])
    #expect(runtime.reconcile(completed, width: 80).map(\.text.lines) == [[Line("later")]])
  }

  @Test func unchangedInlineDocumentRevisionSkipsStableBlockReconciliation() {
    var runtime = InlineDocumentRuntime<String>()
    let initial = InlineDocument(
      id: "session", revision: 7,
      blocks: [InlineDocumentBlock(id: "message", text: Text([Line("original")]))])
    #expect(runtime.reconcile(initial, width: 80).count == 1)

    // The revision is an application-owned promise. An unchanged value intentionally bypasses the
    // otherwise source-backed rewrite check, while width changes still force a canonical replay.
    let staleButSameRevision = InlineDocument(
      id: "session", revision: 7,
      blocks: [InlineDocumentBlock(id: "message", text: Text([Line("replacement")]))])
    #expect(runtime.reconcile(staleButSameRevision, width: 80).isEmpty)
    #expect(runtime.reconcile(staleButSameRevision, width: 40).first?.resetsScrollback == true)
  }

  @Test func inlineDocumentReplaysAfterRewriteIdentityOrWidthChanges() {
    var runtime = InlineDocumentRuntime<String>()
    let original = InlineDocument(
      id: "session-a",
      blocks: [InlineDocumentBlock(id: "message", text: Text([Line("original")]))])
    _ = runtime.reconcile(original, width: 80)

    let rewritten = InlineDocument(
      id: "session-a",
      blocks: [InlineDocumentBlock(id: "message", text: Text([Line("replacement")]))])
    let rewrite = runtime.reconcile(rewritten, width: 80)
    #expect(rewrite.first?.resetsScrollback == true)
    #expect(rewrite.dropFirst().flatMap(\.text.lines) == [Line("replacement")])

    let widthReplay = runtime.reconcile(rewritten, width: 40)
    #expect(widthReplay.first?.resetsScrollback == true)
    #expect(widthReplay.dropFirst().flatMap(\.text.lines) == [Line("replacement")])

    let identityReplay = runtime.reconcile(
      InlineDocument(
        id: "session-b",
        blocks: [InlineDocumentBlock(id: "message", text: Text([Line("replacement")]))]),
      width: 40)
    #expect(identityReplay.first?.resetsScrollback == true)
  }

  @Test func insertionIntoFullscreenInlineViewportGoesToScrollback() throws {
    var terminal = try Terminal(
      backend: TestBackend(
        screenWidth: 10,
        screenHeight: 4,
        viewport: Rect(x: 0, y: 0, width: 10, height: 4)
      )
    )
    try terminal.draw { frame in
      frame.render(Paragraph("VIEWLINE00\nVIEWLINE01\nVIEWLINE02\nVIEWLINE03"))
    }
    try terminal.insertBefore(height: 2) { buffer in
      buffer.setString("INSERTED00", at: Position(x: 0, y: 0))
      buffer.setString("INSERTED01", at: Position(x: 0, y: 1))
    }

    assertTerminal(terminal.backend.buffer) {
      """
      │VIEWLINE00│
      │VIEWLINE01│
      │VIEWLINE02│
      │VIEWLINE03│
      """
    }
    #expect(
      terminal.backend.scrollback.map { $0.map(\.symbol).joined() } == [
        "INSERTED00", "INSERTED01",
      ])
  }
}
