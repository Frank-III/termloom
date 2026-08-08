import CustomDump
import TermLoomTestSupport
import Testing

@testable import TermLoom

private struct StatefulCursorProbe: StatefulWidget {
  typealias State = Bool

  func render(in area: Rect, into frame: inout Frame, state: inout Bool) {
    guard !area.isEmpty else { return }
    frame.placeCursor(
      at: Position(x: area.x, y: area.y),
      style: state ? .steadyBar : .steadyBlock)
  }
}

@Suite struct InteractionTests {
  @Test func nestedControlsPreserveLayoutAndIdentity() throws {
    var terminal = try Terminal(backend: TestBackend(width: 24, height: 7))

    let frame = try terminal.draw(
      environment: RenderEnvironment(focusedControl: "save")
    ) { frame in
      frame.render(
        Block(title: "Actions") {
          VStack {
            Button("Save", id: "save", action: "save").frame(.length(1))
            Button("Cancel", id: "cancel", action: "cancel").frame(.length(1))
          }
        }
      )
    }

    expectNoDifference(
      frame.interactions.regions,
      [
        InteractionRegion(
          control: "save",
          area: Rect(x: 1, y: 1, width: 22, height: 1),
          action: "save"
        ),
        InteractionRegion(
          control: "cancel",
          area: Rect(x: 1, y: 2, width: 22, height: 1),
          action: "cancel"
        ),
      ]
    )
    #expect(
      frame.buffer.cell(at: Position(x: 1, y: 1))?.style.modifiers.contains(.reversed) == true
    )
  }

  @Test func composedWidgetsPreserveHardwareCursorThroughErasureStacksAndBlocks() throws {
    let state = TextFieldState(text: "hello")
    var terminal = try Terminal(backend: TestBackend(width: 20, height: 4))

    let frame = try terminal.draw(
      environment: RenderEnvironment(focusedControl: "query")
    ) { frame in
      frame.render(
        Block(title: "Search") {
          VStack {
            TextField(state, id: "query").frame(.length(1))
            Text("results").frame(.length(1))
          }
        })
    }

    #expect(terminal.backend.cursorPosition == Position(x: 6, y: 1))
    #expect(
      frame.interactions.regions.contains(
        InteractionRegion(
          control: "query", area: Rect(x: 1, y: 1, width: 18, height: 1))))
  }

  @Test func focusTraversalReconcilesRemovedControls() {
    let first = InteractionMap(regions: [
      InteractionRegion(control: "one", area: .zero),
      InteractionRegion(control: "two", area: .zero),
    ])
    var focus = FocusManager()

    let initiallyReconciled = focus.reconcile(with: first)
    #expect(initiallyReconciled)
    #expect(focus.focusedControl == "one")
    let advanced = focus.advance(in: first)
    #expect(advanced)
    #expect(focus.focusedControl == "two")

    let second = InteractionMap(regions: [
      InteractionRegion(control: "one", area: .zero)
    ])
    let reconciledAfterRemoval = focus.reconcile(with: second)
    #expect(reconciledAfterRemoval)
    #expect(focus.focusedControl == "one")
  }

  @Test func routerPreservesTabWhenNoFocusableControlsExist() {
    var router = InteractionRouter()
    let event = TerminalEvent.key(KeyEvent(.tab))
    expectNoDifference(
      router.route(event, through: InteractionMap()),
      RoutedInteraction(events: [event])
    )
  }

  @Test func routerTurnsKeyboardAndMouseActivationIntoSemanticActions() {
    let interactions = InteractionMap(regions: [
      InteractionRegion(
        control: "save",
        area: Rect(x: 2, y: 3, width: 8, height: 1),
        action: "save"
      )
    ])
    var router = InteractionRouter()
    _ = router.reconcile(with: interactions)

    expectNoDifference(
      router.route(.key(KeyEvent(.enter)), through: interactions),
      RoutedInteraction(events: [.action("save")])
    )
    expectNoDifference(
      router.route(
        .mouse(MouseEvent(.down(.left), at: Position(x: 4, y: 3))),
        through: interactions
      ),
      RoutedInteraction(events: [.action("save")])
    )
  }

  @Test func routerForwardsReleasesWithoutFocusingOrActivatingAndRoutesRepeats() {
    let interactions = InteractionMap(regions: [
      InteractionRegion(control: "save", area: .zero, action: "save"),
      InteractionRegion(control: "cancel", area: .zero, action: "cancel"),
    ])
    var router = InteractionRouter()
    _ = router.reconcile(with: interactions)

    let tabRelease = TerminalEvent.key(KeyEvent(.tab, kind: .release))
    expectNoDifference(
      router.route(tabRelease, through: interactions),
      RoutedInteraction(events: [tabRelease])
    )
    #expect(router.focus.focusedControl == "save")

    let enterRelease = TerminalEvent.key(KeyEvent(.enter, kind: .release))
    expectNoDifference(
      router.route(enterRelease, through: interactions),
      RoutedInteraction(events: [enterRelease])
    )
    let spaceRelease = TerminalEvent.key(KeyEvent(.character(" "), kind: .release))
    expectNoDifference(
      router.route(spaceRelease, through: interactions),
      RoutedInteraction(events: [spaceRelease])
    )
    #expect(router.focus.focusedControl == "save")

    expectNoDifference(
      router.route(.key(KeyEvent(.tab, kind: .repeat)), through: interactions),
      RoutedInteraction(events: [.focusChanged("cancel")], focusChanged: true)
    )
    expectNoDifference(
      router.route(.key(KeyEvent(.enter, kind: .repeat)), through: interactions),
      RoutedInteraction(events: [.action("cancel")])
    )
  }

  @Test func textFieldStateEditsGraphemesSelectionsWordsAndPaste() {
    var state = TextFieldState(text: "Swift")

    var handled = state.handle(.key(KeyEvent(.left)))
    #expect(handled)
    handled = state.handle(.key(KeyEvent(.left, modifiers: [.shift])))
    #expect(handled)
    #expect(state.selection == 3..<4)
    handled = state.handle(.key(KeyEvent(.character("X"))))
    #expect(handled)
    #expect(state.text == "SwiXt")
    handled = state.handle(.key(KeyEvent(.backspace)))
    #expect(handled)
    handled = state.handle(.paste("界"))
    #expect(handled)
    #expect(state.text == "Swi界t")

    handled = state.handle(.key(KeyEvent(.home)))
    #expect(handled)
    handled = state.handle(.key(KeyEvent(.right, modifiers: [.option])))
    #expect(handled)
    #expect(state.cursor == state.text.count)
    state.selectAll()
    #expect(state.selection == 0..<state.text.count)
  }

  @Test func textFieldElementsAreAtomicAndExpandByIdentity() {
    var state = TextFieldState(text: "before ")
    state.insertElement("[paste]", id: "first")
    state.handle(.paste(" and "))
    state.insertElement("[paste]", id: "second")

    #expect(
      state.expandingElements { id in
        ["first": "ONE", "second": "TWO"][id.rawValue]
      } == "before ONE and TWO")

    state.handle(.key(KeyEvent(.left)))
    #expect(state.cursor == "before [paste] and ".count)
    state.handle(.key(KeyEvent(.right)))
    #expect(state.cursor == state.text.count)
    state.handle(.key(KeyEvent(.backspace)))
    #expect(state.text == "before [paste] and ")
    #expect(state.elements.map(\.id.rawValue) == ["first"])

    state.cursor = "before [pa".count
    state.selectionAnchor = state.cursor - 1
    state.handle(.key(KeyEvent(.backspace)))
    #expect(state.text == "before  and ")
    #expect(state.elements.isEmpty)

    state = TextFieldState()
    state.insertElement("[paste]", id: "paste")
    state.cursor = 3
    state.insert(" after")
    #expect(state.text == "[paste] after")
    #expect(state.expandingElements { _ in "PAYLOAD" } == "PAYLOAD after")

    state = TextFieldState()
    state.insertElement("[paste]", id: "paste")
    state.cursor = 3
    state.insertElement("X", id: "second")
    #expect(state.elements.map(\.range) == [0..<7, 7..<8])
    #expect(
      state.expandingElements { id in id.rawValue == "paste" ? "PAYLOAD" : "SECOND" }
        == "PAYLOADSECOND")

    state.cursor = 1_000
    state.text = "a"
    #expect(state.cursor == 1)
    state.handle(.paste("b"))
    #expect(state.text == "ab")
  }

  @Test func textFieldSupportsShellAndMacWordDeletionBindings() {
    var state = TextFieldState(text: "one two three")
    var handled = state.handle(.key(KeyEvent(.character("w"), modifiers: [.control])))
    #expect(handled)
    #expect(state.text == "one two ")
    handled = state.handle(.key(KeyEvent(.backspace, modifiers: [.option])))
    #expect(handled)
    #expect(state.text == "one ")

    state = TextFieldState(text: "one two three", cursor: 4)
    handled = state.handle(.key(KeyEvent(.character("d"), modifiers: [.option])))
    #expect(handled)
    #expect(state.text == "one three")
    handled = state.handle(.key(KeyEvent(.character("u"), modifiers: [.control])))
    #expect(handled)
    #expect(state.text == "three")

    state = TextFieldState(text: "abc def", cursor: 3)
    handled = state.handle(.key(KeyEvent(.character("k"), modifiers: [.control])))
    #expect(handled)
    #expect(state.text == "abc")
    handled = state.handle(.key(KeyEvent(.character("d"), modifiers: [.control])))
    #expect(handled)
    #expect(state.text == "abc")
  }

  @Test func textFieldOwnsHorizontalScrollingAndHardwareCursor() throws {
    var state = TextFieldState(text: "abcdef")
    var terminal = try Terminal(backend: TestBackend(width: 6, height: 1))
    let frame = try terminal.draw(environment: RenderEnvironment(focusedControl: "query")) {
      frame in
      frame.render(TextField(id: "query"), state: &state)
    }

    #expect(state.horizontalOffset == 1)
    assertTerminal(frame.buffer) {
      """
      │bcdef │
      """
    }
    #expect(terminal.backend.cursorPosition == Position(x: 5, y: 0))
    #expect(
      frame.interactions.regions
        == [InteractionRegion(control: "query", area: frame.buffer.area)]
    )
  }

  @Test func statefulWidgetCanDeriveCursorStyleFromState() throws {
    var state = true
    var terminal = try Terminal(backend: TestBackend(width: 1, height: 1))
    _ = try terminal.draw { frame in
      frame.render(StatefulCursorProbe(), state: &state)
    }

    #expect(terminal.backend.cursorPosition == Position(x: 0, y: 0))
    #expect(terminal.backend.cursorStyle == .steadyBar)
  }

  @Test func textFieldSnapshotComposesInsideAWidgetBody() throws {
    let state = TextFieldState(text: "hello")
    var terminal = try Terminal(backend: TestBackend(width: 5, height: 1))
    let frame = try terminal.draw(environment: RenderEnvironment(focusedControl: "query")) {
      frame in
      frame.render(TextField(state, id: "query"))
    }

    assertTerminal(frame.buffer) {
      """
      │ello │
      """
    }
    #expect(terminal.backend.cursorPosition == Position(x: 4, y: 0))
  }

  @Test func textFieldScrollingNeverBisectsAWideGrapheme() throws {
    var state = TextFieldState(text: "界")
    var terminal = try Terminal(backend: TestBackend(width: 2, height: 1))
    let frame = try terminal.draw(environment: RenderEnvironment(focusedControl: "query")) {
      frame in
      frame.render(TextField(id: "query"), state: &state)
    }

    #expect(state.horizontalOffset == 2)
    assertTerminal(frame.buffer) {
      """
      │  │
      """
    }
    #expect(terminal.backend.cursorPosition == Position(x: 0, y: 0))
  }

  @Test func selectionAndChoiceControlsRenderSemantically() throws {
    var selected = TextFieldState(text: "abc", cursor: 3, selectionAnchor: 1)
    var terminal = try Terminal(backend: TestBackend(width: 12, height: 3))
    let frame = try terminal.draw(environment: RenderEnvironment(focusedControl: "field")) {
      frame in
      frame.render(
        TextField(id: "field"), in: Rect(x: 0, y: 0, width: 12, height: 1), state: &selected)
      frame.render(
        Checkbox("Enabled", isOn: true, id: "check", action: "toggle"),
        in: Rect(x: 0, y: 1, width: 12, height: 1)
      )
      frame.render(
        RadioButton("Fast", isSelected: true, id: "fast", action: "fast"),
        in: Rect(x: 0, y: 2, width: 12, height: 1)
      )
    }

    assertTerminal(frame.buffer) {
      """
      │abc         │
      │[x] Enabled │
      │(•) Fast    │
      """
    }
    #expect(
      frame.buffer.cell(at: Position(x: 1, y: 0))?.style.modifiers.contains(.reversed) == true)
    #expect(frame.interactions.regions.map(\.action) == [nil, "toggle", "fast"])
  }
}
