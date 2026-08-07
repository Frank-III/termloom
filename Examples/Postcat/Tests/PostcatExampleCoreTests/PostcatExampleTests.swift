import Ratatui
import Testing

@testable import PostcatExampleCore

@MainActor
@Suite struct PostcatExampleTests {
  @Test func observationModeUsesInvalidationInsteadOfExplicitOrPeriodicRedraws() async {
    let app = PostcatApplication(
      renderingMode: .observation,
      sender: { _ in
        APIResponse(status: 204, headers: [], body: "", durationMilliseconds: 1)
      })

    #expect(app.automaticallyTracksObservableState)
    #expect(!app.needsPeriodicRedraw)
    #expect(await app.update(.key(KeyEvent(.character("m")))) == .ignore)
    #expect(app.method == HTTPMethod.post)
    #expect(await app.update(.key(KeyEvent(.character("s")))) == .ignore)
    await app.waitForCurrentRequest()
    #expect(app.response?.status == 204)
    #expect(!app.loading)
  }

  @Test func startupRendersTheRequestBuilderAndResponsePlaceholder() {
    let app = PostcatApplication(sender: { _ in
      APIResponse(status: 200, body: "{}")
    })

    let output = render(app.body, width: 100, height: 32)

    #expect(output.contains("postcat swift"))
    #expect(output.contains("GET"))
    #expect(output.contains("Request"))
    #expect(output.contains("Response"))
    #expect(output.contains("ready when you are"))
    #expect(output.contains("NORMAL"))
  }

  @Test func keyboardNavigationEditingAndMethodCyclingRemainApplicationPolicy() async {
    let app = PostcatApplication(sender: { _ in
      APIResponse(status: 204, body: "")
    })

    _ = await app.update(.key(KeyEvent(.character("m"))))
    #expect(app.method == .post)
    _ = await app.update(.key(KeyEvent(.tab)))
    #expect(app.focus == .request)
    _ = await app.update(.key(KeyEvent(.character("i"))))
    #expect(app.editing)
    _ = await app.update(.key(KeyEvent(.character("x"))))
    #expect(app.requestBody.text.hasSuffix("x"))
    _ = await app.update(.key(KeyEvent(.character("u"), modifiers: [.control])))
    #expect(!app.requestBody.text.hasSuffix("x"))
    _ = await app.update(.key(KeyEvent(.escape)))
    #expect(!app.editing)
  }

  @Test func injectedTransportCompletesARealApplicationTurnAndPrettyPrintsJSON() async {
    let app = PostcatApplication(sender: { request in
      #expect(request.method == .get)
      #expect(request.url == "https://example.test/data")
      return APIResponse(
        status: 200,
        reason: "ok",
        headers: [("content-type", "application/json")],
        body: "{\"answer\":42}",
        durationMilliseconds: 7)
    })
    app.url = TextFieldState(text: "https://example.test/data")

    _ = await app.update(.key(KeyEvent(.character("s"))))
    await app.waitForCurrentRequest()

    #expect(!app.loading)
    #expect(app.response?.status == 200)
    let renderedJSON = app.renderedResponse.map(\.content).joined(separator: "\n")
    #expect(renderedJSON.contains("\"answer\""))
    #expect(renderedJSON.contains("42"))
    let output = render(app.body, width: 100, height: 32)
    #expect(output.contains("200 ok"))
    #expect(output.contains("answer"))
  }

  @Test func responseTabsAndScrollingUseFrameworkPrimitivesWithoutCoreHTTPPolicy() async {
    let app = PostcatApplication(sender: { _ in
      APIResponse(
        status: 200,
        headers: [("x-one", "1"), ("x-two", "2")],
        body: (0..<80).map { "line \($0)" }.joined(separator: "\n"))
    })

    _ = await app.update(.key(KeyEvent(.character("s"))))
    await app.waitForCurrentRequest()
    app.focus = .response
    _ = await app.update(.key(KeyEvent(.character("j"))))
    #expect(app.responseScroll == 1)
    app.responseScroll = .max
    let bottom = render(app.body, width: 80, height: 20)
    #expect(bottom.contains("line 79"))

    _ = await app.update(.key(KeyEvent(.character("]"))))
    #expect(app.responseTab == .headers)
    #expect(app.renderedResponse.map(\.content).joined().contains("x-one"))

    var terminal = try! Terminal(backend: TestBackend(width: 80, height: 20))
    let frame = try! terminal.draw { $0.render(app.body) }
    let bodyTab = frame.interactions.regions.first {
      $0.action == ActionID("postcat.response.body")
    }
    #expect(bodyTab?.area.height == 1)
    #expect(bodyTab?.area.width == TerminalWidth.of(" Body "))
    _ = await app.update(.action("postcat.response.body"))
    #expect(app.focus == .response)
    #expect(app.responseTab == .body)
  }

  private func render<W: Widget>(_ screen: W, width: Int, height: Int) -> String {
    let area = Rect(x: 0, y: 0, width: width, height: height)
    var buffer = Buffer(area: area)
    screen.render(in: area, into: &buffer, environment: RenderEnvironment())
    return (0..<height).map { y in
      (0..<width).map { x in
        buffer[Position(x: x, y: y)].symbol
      }.joined()
    }.joined(separator: "\n")
  }
}
