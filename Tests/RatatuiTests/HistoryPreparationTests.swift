import Testing

@testable import Ratatui

private struct RecordingNativeHistoryBackend: InlineHistoryBackend {
  var positions: [HistoryInsertionBatchPosition] = []
  var committedBatches: [[String]] = []
  private var pendingRows: [String] = []

  var capabilities: BackendCapabilities { [.inlineViewport] }

  mutating func size() throws -> Size { Size(width: 4, height: 2) }
  mutating func draw(_ updates: [CellUpdate]) throws {}
  mutating func clear() throws {}

  mutating func insertHistory(_ buffer: Buffer) throws -> Bool {
    try insertHistory(buffer, batchPosition: .single)
  }

  mutating func insertHistory(
    _ buffer: Buffer,
    batchPosition: HistoryInsertionBatchPosition
  ) throws -> Bool {
    positions.append(batchPosition)
    let rows = (0..<Int(buffer.area.height)).map { row in
      (0..<Int(buffer.area.width)).compactMap { column in
        buffer.cell(at: Position(x: UInt16(column), y: UInt16(row)))?.symbol
      }.joined()
    }
    switch batchPosition {
    case .single:
      pendingRows.removeAll(keepingCapacity: true)
      committedBatches.append(rows)
    case .first:
      pendingRows = rows
    case .middle:
      pendingRows.append(contentsOf: rows)
    case .last:
      pendingRows.append(contentsOf: rows)
      committedBatches.append(pendingRows)
      pendingRows.removeAll(keepingCapacity: true)
    }
    return true
  }

  mutating func scrollRegionUp(_ rows: Range<UInt16>, by count: UInt16) throws {}
  mutating func scrollRegionUpIntoScrollback(
    _ rows: Range<UInt16>,
    by count: UInt16
  ) throws {}
  mutating func scrollRegionDown(_ rows: Range<UInt16>, by count: UInt16) throws {}
}

@Suite struct HistoryPreparationTests {
  @Test func resetMarkersSplitIndependentNativeHistoryBatches() {
    let prepared = prepareHistoryInsertions(
      [
        insertion("old-a\nold-b"),
        .reset,
        insertion("new-a"),
        insertion("new-b"),
        .reset,
        insertion("latest"),
      ],
      width: 20,
      targetChunkHeight: 1
    )

    #expect(
      prepared.map(\.batchPosition) == [
        .first, .last, .single, .first, .last, .single, .single,
      ])
    #expect(prepared.map(\.height) == [1, 1, 0, 1, 1, 0, 1])
    #expect(prepared[2].insertion.resetsScrollback)
    #expect(prepared[5].insertion.resetsScrollback)
  }

  @Test func pendingHistoryKeepsOnlyTheSuffixAfterTheLastReset() {
    let unchanged = normalizePendingHistoryResets([insertion("a"), insertion("b")])
    #expect(!unchanged.requiresReset)
    #expect(unchanged.insertions.map(\.text.lines) == [[Line("a")], [Line("b")]])

    let reset = normalizePendingHistoryResets([
      insertion("stale-a"),
      .reset,
      insertion("stale-b"),
      .reset,
      insertion("canonical-a"),
      insertion("canonical-b"),
    ])
    #expect(reset.requiresReset)
    #expect(
      reset.insertions.map(\.text.lines) == [
        [Line("canonical-a")], [Line("canonical-b")],
      ])

    let resetOnly = normalizePendingHistoryResets([insertion("stale"), .reset])
    #expect(resetOnly.requiresReset)
    #expect(resetOnly.insertions.isEmpty)
  }

  @Test func batchVocabularyComposesOnASecondNativeBackendModel() throws {
    var terminal = try Terminal(backend: RecordingNativeHistoryBackend())
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

    #expect(terminal.backend.positions == [.first, .middle, .last])
    #expect(terminal.backend.committedBatches == [["A   ", "B   ", "C   "]])
  }

  @Test func oversizedWrappedSourceLinesRemainAtomicAndKeepTheirMeasuredHeight() {
    let prepared = prepareHistoryInsertions(
      [insertion("abcdefghij", wrap: .character)],
      width: 4,
      targetChunkHeight: 2
    )

    #expect(prepared.count == 1)
    #expect(prepared[0].height == 3)
    #expect(prepared[0].batchPosition == .single)
    #expect(prepared[0].insertion.text.lines == [Line("abcdefghij")])
  }

  private func insertion(
    _ content: String,
    wrap: WrapMode = .word
  ) -> TerminalHistoryInsertion {
    TerminalHistoryInsertion(text: Text(content), wrap: wrap)
  }
}
