import TermLoom
import Testing

@testable import TermLoomDevTools

@Suite struct DevToolsTests {
  @Test func statisticsAndBoundedLogsRemainDeterministic() {
    var state = DevToolsState(logCapacity: 2)
    state.terminalSize = Size(width: 120, height: 40)
    state.record(frameMilliseconds: 4, changedCells: 10, outputBytes: 80)
    state.record(frameMilliseconds: 8, changedCells: 2, outputBytes: 12)
    state.log("first")
    state.log("second", level: .warning)
    state.log("third", level: .error)

    #expect(state.frames.count == 2)
    #expect(state.frames.lastMilliseconds == 8)
    #expect(state.frames.averageMilliseconds == 6)
    #expect(state.frames.maximumMilliseconds == 8)
    #expect(state.logs.map(\.message) == ["second", "third"])
  }

  @Test func measuringAFrameReturnsItsResultAndRecordsTime() {
    var state = DevToolsState()
    let value = state.measureFrame { 42 }

    #expect(value == 42)
    #expect(state.frames.count == 1)
    #expect(state.frames.lastMilliseconds >= 0)
  }

  @Test func panelRendersMetricsAndLogs() {
    var state = DevToolsState()
    state.terminalSize = Size(width: 80, height: 24)
    state.record(frameMilliseconds: 12.5, changedCells: 8, outputBytes: 64)
    state.log("request completed")
    let area = Rect(x: 0, y: 0, width: 60, height: 10)
    var buffer = Buffer(area: area)

    DevToolsPanel(state).render(in: area, into: &buffer, environment: RenderEnvironment())

    let output = (area.y..<area.bottom).map { y in
      (area.x..<area.right).map { x in buffer[Position(x: x, y: y)].symbol }.joined()
    }.joined(separator: "\n")
    #expect(output.contains("TermLoom DevTools"))
    #expect(output.contains("12.50ms"))
    #expect(output.contains("request completed"))
  }
}
