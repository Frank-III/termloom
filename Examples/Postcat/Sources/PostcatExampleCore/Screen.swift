import Ratatui
import RatatuiOverlays
import RatatuiTextArea

public struct PostcatScreen: Widget, Sendable {
  public var method: HTTPMethod
  public var url: TextFieldState
  public var requestBody: TextAreaState
  public var focus: AppFocus
  public var editing: Bool
  public var response: APIResponse?
  public var responseTab: ResponseTab
  public var responseLines: [Line]
  public var responseScroll: Int
  public var wrapsResponse: Bool
  public var loading: Bool
  public var error: String?
  public var statusMessage: String?
  public var showsHelp: Bool
  public var spinnerFrame: Int

  public func render(in area: Rect, into frame: inout Frame) {
    guard !area.isEmpty else { return }
    frame.buffer.fill(
      area,
      with: Cell(symbol: " ", style: Style(foreground: ExampleTheme.foreground)))
    let regions = layout(in: area)
    renderHeader(in: regions.header, into: &frame)
    renderURL(in: regions.url, into: &frame)
    renderRequest(in: regions.request, into: &frame)
    renderResponse(in: regions.response, into: &frame)
    renderStatus(in: regions.status, into: &frame)
    if showsHelp {
      renderHelp(in: area, into: &frame)
      frame.placeCursor(at: nil)
    }
  }

  private struct Regions {
    var header: Rect
    var url: Rect
    var request: Rect
    var response: Rect
    var status: Rect
  }

  private func layout(in area: Rect) -> Regions {
    let rows = Layout(
      .vertical,
      constraints: [.length(1), .length(3), .percentage(38), .flex(1), .length(1)]
    ).split(area)
    return Regions(
      header: rows[0], url: rows[1], request: rows[2], response: rows[3], status: rows[4])
  }

  private func paneBlock(_ title: String, focused: Bool) -> Block<EmptyWidget> {
    Block(
      title: title,
      borderStyle: Style(foreground: focused ? ExampleTheme.accent : ExampleTheme.border),
      titleStyle: Style(
        foreground: focused ? ExampleTheme.accent : ExampleTheme.dim,
        modifiers: focused ? [.bold] : []
      )
    )
  }

  private func renderHeader(
    in area: Rect, into frame: inout Frame
  ) {
    Line([
      Span(
        " ⚡ postcat swift ",
        style: Style(
          foreground: ExampleTheme.dark, background: ExampleTheme.accent, modifiers: [.bold])),
      Span("  Ratatui example", style: Style(foreground: ExampleTheme.dim)),
    ]).render(in: area, into: &frame)
    Line(
      [
        Span("? ", style: Style(foreground: ExampleTheme.accent, modifiers: [.bold])),
        Span("help ", style: Style(foreground: ExampleTheme.dim)),
      ], alignment: .trailing
    ).render(in: area, into: &frame)
  }

  private func urlInputArea(in area: Rect) -> Rect {
    let inner = paneBlock("", focused: false).inner(area)
    let methodWidth = min(12, inner.width)
    return Rect(
      x: inner.x + methodWidth,
      y: inner.y,
      width: inner.width > methodWidth ? inner.width - methodWidth : 0,
      height: min(1, inner.height))
  }

  private func renderURL(
    in area: Rect, into frame: inout Frame
  ) {
    let block = paneBlock("", focused: focus == .url)
    block.render(in: area, into: &frame)
    let inner = block.inner(area)
    guard !inner.isEmpty else { return }
    let methodArea = Rect(x: inner.x, y: inner.y, width: min(12, inner.width), height: 1)
    Line([
      Span(
        " \(TerminalWidth.padded(method.rawValue, to: 7))",
        style: Style(
          foreground: ExampleTheme.method(method), modifiers: [.bold])),
      Span("▾ │", style: Style(foreground: ExampleTheme.dim)),
    ]).render(in: methodArea, into: &frame)
    let field = TextField(
      url,
      id: "postcat-url",
      placeholder: "https://httpbin.org/anything",
      style: Style(foreground: ExampleTheme.foreground),
      focusedStyle: editing && focus == .url ? Style(modifiers: [.underlined]) : .plain)
    var fieldEnvironment = frame.environment
    fieldEnvironment.focusedControl = editing && focus == .url ? "postcat-url" : nil
    frame.render(
      field,
      in: urlInputArea(in: area),
      environment: fieldEnvironment,
      collectsInteractions: !showsHelp)
  }

  private func requestInputArea(in area: Rect) -> Rect {
    let inner = paneBlock("", focused: false).inner(area)
    return Rect(
      x: inner.x + min(1, inner.width),
      y: inner.y + min(2, inner.height),
      width: inner.width > 2 ? inner.width - 2 : 0,
      height: inner.height > 2 ? inner.height - 2 : 0)
  }

  private func renderRequest(
    in area: Rect, into frame: inout Frame
  ) {
    let block = paneBlock(" Request ", focused: focus == .request)
    block.render(in: area, into: &frame)
    let inner = block.inner(area)
    guard inner.height > 0 else { return }
    Line([
      Span(
        " Body ", style: Style(foreground: ExampleTheme.accent, modifiers: [.bold, .underlined])),
      Span("  JSON", style: Style(foreground: ExampleTheme.dim)),
    ]).render(
      in: Rect(x: inner.x, y: inner.y, width: inner.width, height: 1),
      into: &frame)
    guard inner.height > 2 else { return }
    var editorEnvironment = frame.environment
    editorEnvironment.focusedControl = editing && focus == .request ? "postcat-body" : nil
    frame.render(
      TextArea(
        requestBody,
        id: "postcat-body",
        placeholder: method == .get ? "GET requests have no body" : "{\"hello\": \"world\"}",
        showsLineNumbers: true,
        style: Style(foreground: ExampleTheme.foreground),
        focusedStyle: editing && focus == .request ? Style(modifiers: [.underlined]) : .plain),
      in: requestInputArea(in: area),
      environment: editorEnvironment,
      collectsInteractions: !showsHelp)
  }

  private func renderResponse(
    in area: Rect, into frame: inout Frame
  ) {
    let block = paneBlock(" Response ", focused: focus == .response)
    block.render(in: area, into: &frame)
    let inner = block.inner(area)
    guard inner.height >= 2 else { return }
    let metadata = response.map {
      "\($0.status) \($0.reason) · \($0.durationMilliseconds) ms · \(humanSize($0.size)) "
    }
    let metadataWidth = metadata.map { TerminalWidth.of($0) } ?? 0
    let tabArea = Rect(
      x: inner.x,
      y: inner.y,
      width: max(0, inner.width - min(inner.width, metadataWidth)),
      height: 1
    )
    Tabs(
      [
        Line(
          "Body",
          style: Style(
            foreground: responseTab == .body ? ExampleTheme.accent : ExampleTheme.dim,
            modifiers: responseTab == .body ? [.bold, .underlined] : [])),
        Line(
          "Headers",
          style: Style(
            foreground: responseTab == .headers ? ExampleTheme.accent : ExampleTheme.dim,
            modifiers: responseTab == .headers ? [.bold, .underlined] : [])),
      ],
      selectedIndex: responseTab == .body ? 0 : 1,
      divider: "",
      selectedStyle: .plain,
      interactions: showsHelp
        ? []
        : [
          InteractionDescriptor(control: "postcat-response-body", action: "postcat.response.body"),
          InteractionDescriptor(
            control: "postcat-response-headers", action: "postcat.response.headers"),
        ]
    ).render(in: tabArea, into: &frame)
    if let response, let metadata {
      Line(
        metadata, style: Style(foreground: ExampleTheme.status(response.status)),
        alignment: .trailing
      )
      .render(
        in: Rect(x: inner.x, y: inner.y, width: inner.width, height: 1),
        into: &frame)
    }
    let content = Rect(
      x: inner.x + min(1, inner.width),
      y: inner.y + min(2, inner.height),
      width: inner.width > 2 ? inner.width - 2 : 0,
      height: inner.height > 2 ? inner.height - 2 : 0)
    guard !content.isEmpty else { return }
    if loading {
      let spinner = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
      Text("\(spinner[spinnerFrame % spinner.count]) sending request…", alignment: .center)
        .foregroundStyle(ExampleTheme.accent)
        .render(in: content, into: &frame)
    } else if let error {
      Text("Request failed\n\n\(error)", alignment: .center)
        .foregroundStyle(ExampleTheme.red)
        .render(in: content, into: &frame)
    } else if response == nil {
      Text("⚡\n\nready when you are\n\ni edit · enter send · ? help", alignment: .center)
        .foregroundStyle(ExampleTheme.dim)
        .render(in: content, into: &frame)
    } else if wrapsResponse {
      var paragraph = Paragraph(
        Text(responseLines), wrap: .word, trimLeadingWhitespace: false)
      paragraph.scroll = responseScroll
      paragraph.render(in: content, into: &frame)
    } else {
      let viewport = RowViewport(
        totalRows: responseLines.count,
        viewportRows: content.height,
        offset: responseScroll
      )
      Paragraph(
        Text(Array(responseLines[viewport.visibleRange])),
        wrap: .none,
        trimLeadingWhitespace: false
      ).render(in: content, into: &frame)
    }
  }

  private func renderStatus(
    in area: Rect, into frame: inout Frame
  ) {
    let mode = editing ? " INSERT " : " NORMAL "
    let modeColor = editing ? ExampleTheme.green : ExampleTheme.border
    let hints: String =
      if showsHelp {
        "esc close"
      } else if editing {
        focus == .url ? "enter send · esc done · ctrl-u clear" : "esc done · ctrl-u clear"
      } else if area.width < 90 {
        "tab panes · i edit · s send · ? help · q quit"
      } else {
        "tab panes · i edit · m method · s send · [ ] tabs · j/k scroll · q quit"
      }
    Line([
      Span(" "),
      Span(
        mode,
        style: Style(
          foreground: editing ? ExampleTheme.dark : ExampleTheme.pale,
          background: modeColor,
          modifiers: [.bold])),
      Span("  \(hints)", style: Style(foreground: ExampleTheme.dim)),
    ]).render(in: area, into: &frame)
    if let statusMessage {
      Line(statusMessage + " ", style: Style(foreground: ExampleTheme.green), alignment: .trailing)
        .render(in: area, into: &frame)
    }
  }

  private func renderHelp(
    in area: Rect, into frame: inout Frame
  ) {
    Popup(
      layout: PopupLayout(size: .cells(width: 66, height: 18)),
      title: " Keys ",
      style: Style(foreground: ExampleTheme.foreground, background: ExampleTheme.dark),
      borderStyle: Style(foreground: ExampleTheme.accent),
      titleStyle: Style(foreground: ExampleTheme.accent, modifiers: [.bold]),
      padding: .all(1),
      content: Text(
        "Panes\n  tab / shift-tab     move focus\n  1 / 2 / 3           url · request · response\n\nRequest\n  i                    edit focused field\n  m / M                cycle HTTP method\n  s / enter            send request\n\nResponse\n  [ / ]                body · headers\n  j / k, g / G         scroll\n  w                    toggle wrapping\n\nGlobal\n  ?                    this help\n  q                    quit"
      ).foregroundStyle(ExampleTheme.foreground)
    ).render(in: area, into: &frame)
  }
}
