import TermLoomTestSupport
import Testing

@testable import TermLoom

@Suite struct TerminalViewportTests {
  @Test func fixedViewportUsesItsExactTerminalCoordinateArea() throws {
    var backend = TestBackend(width: 8, height: 5)
    for position in backend.buffer.area.positions() {
      backend.setScreenCell(Cell(symbol: "."), at: position)
    }
    let area = Rect(x: 2, y: 1, width: 3, height: 2)
    var terminal = try Terminal(backend: backend, viewport: .fixed(area))
    var observedArea = Rect.zero

    let completed = try terminal.draw { frame in
      observedArea = frame.area
      frame.render(Fill("X"))
      frame.placeCursor(at: Position(x: 4, y: 2), style: .steadyBar)
    }

    #expect(observedArea == area)
    #expect(completed.buffer.area == area)
    #expect(terminal.backend.cursorPosition == Position(x: 4, y: 2))
    #expect(terminal.backend.cursorStyle == .steadyBar)
    assertTerminal(terminal.backend.buffer) {
      """
      │........│
      │..XXX...│
      │..XXX...│
      │........│
      │........│
      """
    }
  }

  @Test func fixedViewportDoesNotAutoresizeWithThePhysicalBackend() throws {
    let area = Rect(x: 2, y: 1, width: 3, height: 2)
    var terminal = try Terminal(
      backend: TestBackend(width: 8, height: 5), viewport: .fixed(area))

    terminal.withBackend { backend in
      backend.resize(width: 12, height: 7)
    }
    let completed = try terminal.draw { frame in
      frame.render(Fill("X"))
    }

    #expect(completed.buffer.area == area)
    #expect(terminal.viewport == .fixed(area))
    #expect(terminal.backend.buffer.area == Rect(x: 0, y: 0, width: 12, height: 7))
  }

  @Test func explicitFixedResizeClearsTheOldRegionAndAdoptsTheNewArea() throws {
    var backend = TestBackend(width: 8, height: 5)
    for position in backend.buffer.area.positions() {
      backend.setScreenCell(Cell(symbol: "."), at: position)
    }
    var terminal = try Terminal(
      backend: backend,
      viewport: .fixed(Rect(x: 2, y: 1, width: 3, height: 2)))
    _ = try terminal.draw { frame in frame.render(Fill("X")) }

    let replacement = Rect(x: 0, y: 3, width: 4, height: 1)
    try terminal.resize(to: replacement)
    let completed = try terminal.draw { frame in frame.render(Fill("Y")) }

    #expect(completed.buffer.area == replacement)
    #expect(terminal.viewport == .fixed(replacement))
    assertTerminal(terminal.backend.buffer) {
      """
      │........│
      │..   ...│
      │..   ...│
      │YYYY....│
      │........│
      """
    }
  }

  @Test func fixedClearPreservesEveryCellOutsideTheViewport() throws {
    var backend = TestBackend(width: 6, height: 4)
    for position in backend.buffer.area.positions() {
      backend.setScreenCell(Cell(symbol: "#"), at: position)
    }
    var terminal = try Terminal(
      backend: backend,
      viewport: .fixed(Rect(x: 1, y: 1, width: 3, height: 2)))
    _ = try terminal.draw { frame in frame.render(Fill("X")) }

    try terminal.clear()

    assertTerminal(terminal.backend.buffer) {
      """
      │######│
      │#   ##│
      │#   ##│
      │######│
      """
    }
  }

  @Test func nonFixedViewportRejectsExplicitFixedResize() throws {
    var terminal = try Terminal(backend: TestBackend(width: 4, height: 2))

    #expect(throws: TerminalViewportError.requiresFixedViewport) {
      try terminal.resize(to: Rect(x: 1, y: 1, width: 2, height: 1))
    }
  }
}
