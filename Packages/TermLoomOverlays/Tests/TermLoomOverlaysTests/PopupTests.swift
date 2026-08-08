import TermLoom
import Testing

@testable import TermLoomOverlays

@Suite struct PopupTests {
  @Test func layoutClampsAndAnchorsWithinMargins() {
    let area = Rect(x: 10, y: 5, width: 100, height: 40)
    #expect(
      PopupLayout(size: .cells(width: 30, height: 10)).resolve(in: area)
        == Rect(x: 45, y: 20, width: 30, height: 10))
    #expect(
      PopupLayout(
        size: .percentage(width: 50, height: 50),
        placement: .bottomTrailing,
        margins: .all(2)
      ).resolve(in: area) == Rect(x: 60, y: 25, width: 48, height: 18))
    #expect(
      PopupLayout(size: .cells(width: .max, height: .max)).resolve(
        in: Rect(x: 0, y: 0, width: 5, height: 3))
        == Rect(x: 1, y: 1, width: 3, height: 1))
  }

  @Test func overlayRendersInOrderAndControlsBaseCursorVisibility() {
    let area = Rect(x: 0, y: 0, width: 8, height: 1)
    let base = TextField(TextFieldState(text: "base"), id: "base")
    let layer = Text("top")
    let environment = RenderEnvironment(focusedControl: "base")
    var hiddenFrame = Frame(buffer: Buffer(area: area), environment: environment)

    let hidden = Overlay(isPresented: true, base: base, layer: layer)
    hidden.render(in: area, into: &hiddenFrame)
    #expect(hiddenFrame.buffer[Position(x: 0, y: 0)].symbol == "t")
    #expect(hiddenFrame.buffer[Position(x: 1, y: 0)].symbol == "o")
    #expect(hiddenFrame.buffer[Position(x: 2, y: 0)].symbol == "p")
    #expect(hiddenFrame.cursorPosition == nil)
    #expect(hiddenFrame.interactions.focusableControls.isEmpty)

    let visible = Overlay(
      isPresented: true, isModal: false, hidesBaseCursor: false, base: base, layer: layer)
    var visibleFrame = Frame(buffer: Buffer(area: area), environment: environment)
    visible.render(in: area, into: &visibleFrame)
    #expect(visibleFrame.cursorPosition != nil)
    #expect(visibleFrame.interactions.focusableControls == ["base"])
  }

  @Test func popupClearsOnlyItsPanelAndForwardsCursorMetadata() {
    let area = Rect(x: 0, y: 0, width: 30, height: 10)
    var frame = Frame(buffer: Buffer(area: area, repeating: Cell(symbol: ".")))
    let popup = Popup(
      layout: PopupLayout(size: .cells(width: 20, height: 5)),
      title: "Search",
      borderStyle: Style(foreground: .cyan),
      padding: .all(1)
    ) {
      TextField(TextFieldState(text: "query"), id: "query")
    }
    let environment = RenderEnvironment(focusedControl: "query")

    frame.environment = environment
    popup.render(in: area, into: &frame)

    #expect(frame.buffer[Position(x: 0, y: 0)].symbol == ".")
    #expect(frame.buffer[Position(x: 5, y: 2)].symbol == "╭")
    #expect(frame.cursorPosition != nil)
    #expect(frame.interactions.focusableControls.contains("query"))
  }
}
