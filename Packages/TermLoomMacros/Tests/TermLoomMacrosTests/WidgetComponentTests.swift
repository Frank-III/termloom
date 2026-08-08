import TermLoom
import TermLoomMacros
import Testing

@WidgetComponent
private struct Greeting {
  var name: String

  var body: some Widget {
    Text("Hello, \(name)!")
  }
}

@WidgetComponent
private struct SearchField {
  var query: TextFieldState

  var body: some Widget {
    TextField(query, id: "search")
  }
}

@WidgetComponent
private struct ExplicitWidget: Widget {
  var body: some Widget { Text("explicit") }
}

@Suite struct WidgetComponentTests {
  @Test func explicitConformanceDoesNotConflictWithGeneratedForwarding() {
    let area = Rect(x: 0, y: 0, width: 10, height: 1)
    var frame = Frame(buffer: Buffer(area: area))
    frame.render(ExplicitWidget(), in: area)
    #expect(frame.buffer[Position(x: 0, y: 0)].symbol == "e")
  }

  @Test func generatedConformanceRendersBody() {
    let area = Rect(x: 0, y: 0, width: 20, height: 1)
    var frame = Frame(buffer: Buffer(area: area))

    frame.render(Greeting(name: "TermLoom"), in: area)

    let output = (area.x..<area.right).map { x in
      frame.buffer[Position(x: x, y: 0)].symbol
    }.joined()
    #expect(output.hasPrefix("Hello, TermLoom!"))
  }

  @Test func generatedConformancePreservesInteractionsAndCursor() {
    let area = Rect(x: 2, y: 3, width: 10, height: 1)
    let field = SearchField(query: TextFieldState(text: "abc"))
    var frame = Frame(
      buffer: Buffer(area: area),
      environment: RenderEnvironment(focusedControl: "search"))

    frame.render(field, in: area)

    #expect(frame.interactions.focusableControls == ["search"])
    #expect(frame.cursorPosition == Position(x: 5, y: 3))
    #expect(frame.cursorStyle == .defaultUserShape)
  }
}
