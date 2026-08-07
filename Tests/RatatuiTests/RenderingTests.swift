import CustomDump
import RatatuiTestSupport
import Testing

@testable import Ratatui

private struct Person {
  var name: String
  var score: Int
}

private final class RenderCounter {
  var value = 0
}

private struct OnePassProbe: Widget {
  let counter: RenderCounter

  func render(in area: Rect, into frame: inout Frame) {
    counter.value += 1
    frame.buffer.setString("ONE", at: Position(x: area.x, y: area.y))
    frame.addInteraction(
      InteractionRegion(
        control: "probe", area: area, action: "activate"))
    frame.placeCursor(at: Position(x: area.x, y: area.y), style: .steadyBar)
  }
}

@Suite struct RenderingTests {
  @Test func swiftNativeCompositionRendersDeterministically() throws {
    var backend = TestBackend(width: 32, height: 9)
    var terminal = try Terminal(backend: backend)
    let people = [
      Person(name: "Blob", score: 42),
      Person(name: "Sblob", score: 7),
    ]

    let first = try terminal.draw { frame in
      frame.render(
        Block(title: "Scores") {
          VStack {
            Text("Leaderboard").bold().frame(.length(1))
            Table(people, selectedRow: 1) {
              TableColumn("Name", value: \.name, width: .flex(2))
              TableColumn("Score", value: \.score, alignment: .trailing)
            }
          }
        }
      )
    }

    assertTerminal(first.buffer) {
      """
      │╭─ Scores ─────────────────────╮│
      ││Leaderboard                   ││
      ││Name                     Score││
      ││Blob                        42││
      ││Sblob                        7││
      ││                              ││
      ││                              ││
      ││                              ││
      │╰──────────────────────────────╯│
      """
    }
    #expect(first.updates > 0)

    let second = try terminal.draw { frame in
      frame.render(
        Block(title: "Scores") {
          VStack {
            Text("Leaderboard").bold().frame(.length(1))
            Table(people, selectedRow: 1) {
              TableColumn("Name", value: \.name, width: .flex(2))
              TableColumn("Score", value: \.score, alignment: .trailing)
            }
          }
        }
      )
    }
    #expect(second.updates == 0)

    backend = terminal.backend
    expectNoDifference(backend.buffer, second.buffer)
    #expect(backend.flushCount == 2)
  }

  @Test func oneRenderPassProducesCellsInteractionsAndCursorMetadata() throws {
    let counter = RenderCounter()
    var terminal = try Terminal(backend: TestBackend(width: 6, height: 2))

    let completed = try terminal.draw { frame in
      frame.render(AnyWidget(OnePassProbe(counter: counter)))
    }

    #expect(counter.value == 1)
    #expect(completed.buffer.lines()[0] == "ONE   ")
    #expect(
      completed.interactions.regions
        == [
          InteractionRegion(
            control: "probe", area: Rect(x: 0, y: 0, width: 6, height: 2),
            action: "activate")
        ])
    #expect(terminal.backend.cursorPosition == Position(x: 0, y: 0))
    #expect(terminal.backend.cursorStyle == .steadyBar)
  }

  @Test func frameCanPlaceTheHardwareCursor() throws {
    var terminal = try Terminal(backend: TestBackend(width: 10, height: 2))

    try terminal.draw { frame in
      frame.render(Text("Name: "))
      frame.placeCursor(at: Position(x: 6, y: 0))
    }

    #expect(terminal.backend.cursorPosition == Position(x: 6, y: 0))
  }
}
