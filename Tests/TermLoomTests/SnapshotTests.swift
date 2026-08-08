import Foundation
import TermLoomTestSupport
import Testing

@testable import TermLoom

@Suite struct SnapshotTests {
  @Test func compositeDashboard() {
    var buffer = Buffer(area: Rect(x: 0, y: 0, width: 44, height: 14))
    Block(title: "Swift systems", padding: .all(1), borderMerge: .exact) {
      VStack(spacing: 1) {
        Paragraph(wrap: .word) {
          Line {
            Span("Typed state").bold()
            Span(" at the edges; compact cells in the renderer.")
          }
        }.frame(.length(2))
        Gauge(ratio: 0.68, label: "frame budget 68%").frame(.length(1))
        BarChart(
          groups: [
            BarGroup("Host", bars: [Bar("CPU", value: 7), Bar("MEM", value: 5)]),
            BarGroup("I/O", bars: [Bar("NET", value: 9)]),
          ],
          maximum: 10,
          barWidth: 3
        )
        Scrollbar(
          contentLength: 100,
          viewportLength: 25,
          position: 50,
          orientation: .horizontalBottom,
          beginSymbol: "←",
          endSymbol: "→"
        ).frame(.length(1))
      }
    }.render(in: buffer.area, into: &buffer)

    assertTerminal(buffer) {
      """
      │╭─ Swift systems ──────────────────────────╮│
      ││                                          ││
      ││ Typed state at the edges; compact cells  ││
      ││ in the renderer.                         ││
      ││                                          ││
      ││ ████████████frame budget 68%░░░░░░░░░░░░ ││
      ││                                          ││
      ││ ▆▆▆ ▄▄▄  ▇▇▇                             ││
      ││ CPU MEM  NET                             ││
      ││  Host    I/O                             ││
      ││                                          ││
      ││ ←───────────────────█████████──────────→ ││
      ││                                          ││
      │╰──────────────────────────────────────────╯│
      """
    }
  }

  @Test func ansiDiffStream() throws {
    let pipe = Pipe()
    var backend = ANSIBackend(
      output: pipe.fileHandleForWriting,
      fallbackSize: Size(width: 4, height: 1)
    )
    try backend.draw([
      CellUpdate(
        position: Position(x: 0, y: 0),
        cell: Cell(
          symbol: "A",
          style: Style(foreground: .cyan, modifiers: [.bold])
        )
      ),
      CellUpdate(position: Position(x: 1, y: 0), cell: Cell(symbol: "界", width: 2)),
      CellUpdate(position: Position(x: 3, y: 0), cell: Cell(symbol: "!")),
    ])
    try pipe.fileHandleForWriting.close()
    let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

    assertTerminalCodes(output) {
      """
      <ESC>[?2026h<ESC>[1;1H<ESC>[0;1;36mA<ESC>[0m界!<ESC>[0m<ESC>[?2026l
      """
    }
  }
}
