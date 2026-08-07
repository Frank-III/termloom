public protocol Widget {
  func render(in area: Rect, into frame: inout Frame)
}

/// A widget whose preferred terminal-cell size can be calculated without a render pass.
public protocol IntrinsicSizeWidget: Widget {
  var intrinsicSize: Size { get }
}

extension Widget {
  /// Renders only the visual cells into a standalone buffer.
  ///
  /// Use `Frame.render(_:in:)` when interaction and cursor metadata must be retained.
  public func render(
    in area: Rect,
    into buffer: inout Buffer,
    environment: RenderEnvironment = RenderEnvironment()
  ) {
    var frame = Frame(buffer: buffer, environment: environment)
    frame.render(self, in: area)
    buffer = frame.buffer
  }
}

extension String: Widget {
  public func render(in area: Rect, into frame: inout Frame) {
    frame.render(Text(self), in: area)
  }
}

extension String {
  public func span(style: Style = .plain) -> Span {
    Span(self, style: style)
  }

  public func line(style: Style = .plain, alignment: Alignment? = nil) -> Line {
    Line(self, style: style, alignment: alignment)
  }

  public func text(style: Style = .plain, alignment: Alignment? = nil) -> Text {
    Text(self, style: style, alignment: alignment)
  }
}

public enum Alignment: Hashable, Sendable {
  case leading
  case center
  case trailing
}

public struct Text: Widget, Hashable, Sendable, Stylable {
  public var lines: [Line]
  public var style: Style
  public var alignment: Alignment?

  public init(_ content: String, style: Style = .plain, alignment: Alignment? = nil) {
    let splitLines = content.split(separator: "\n").map { Line(String($0)) }
    lines = splitLines.isEmpty ? [Line("")] : splitLines
    self.style = style
    self.alignment = alignment
  }

  public init(_ lines: [Line], style: Style = .plain, alignment: Alignment? = nil) {
    self.lines = lines
    self.style = style
    self.alignment = alignment
  }

  public init(style: Style = .plain, alignment: Alignment? = nil, @LineBuilder lines: () -> [Line])
  {
    self.lines = lines()
    self.style = style
    self.alignment = alignment
  }

  public var content: String {
    get { lines.map(\.content).joined(separator: "\n") }
    set {
      let splitLines = newValue.split(separator: "\n").map { Line(String($0)) }
      lines = splitLines.isEmpty ? [Line("")] : splitLines
    }
  }

  public var width: Int {
    lines.map(\.width).max() ?? 0
  }

  public var height: Int {
    lines.count
  }

  public func render(in area: Rect, into frame: inout Frame) {
    guard !area.isEmpty else { return }
    if style != .plain { frame.buffer.setStyle(style, in: area) }
    let renderedLineCount = min(lines.count, Int(area.height))
    for index in 0..<renderedLineCount {
      lines[index].render(
        in: Rect(x: area.x, y: area.y + UInt16(index), width: area.width, height: 1),
        into: &frame.buffer,
        parentStyle: style,
        parentAlignment: alignment)
    }
  }
}

extension Text: ExpressibleByStringLiteral, ExpressibleByArrayLiteral {
  public init(stringLiteral value: String) {
    self.init(value)
  }

  public init(arrayLiteral elements: Line...) {
    self.init(elements)
  }
}

extension Text {
  public mutating func appendLine(_ line: Line) {
    lines.append(line)
  }

  public mutating func appendSpan(_ span: Span) {
    if lines.isEmpty {
      lines.append(Line { span })
    } else {
      lines[lines.count - 1].spans.append(span)
    }
  }

  public func pushLine(_ line: Line) -> Self {
    var copy = self
    copy.appendLine(line)
    return copy
  }

  public func pushSpan(_ span: Span) -> Self {
    var copy = self
    copy.appendSpan(span)
    return copy
  }

  public func alignment(_ alignment: Alignment) -> Self {
    var copy = self
    copy.alignment = alignment
    return copy
  }

  public func aligned(_ alignment: Alignment) -> Self { self.alignment(alignment) }
  public func leftAligned() -> Self { alignment(.leading) }
  public func centered() -> Self { alignment(.center) }
  public func rightAligned() -> Self { alignment(.trailing) }
}

extension Span {
  public func content(_ content: String) -> Self {
    var copy = self
    copy.content = content
    return copy
  }

  public func leftAligned() -> Line { Line { self }.alignment(.leading) }
  public func centered() -> Line { Line { self }.alignment(.center) }
  public func rightAligned() -> Line { Line { self }.alignment(.trailing) }
}

extension Line {
  public func leftAligned() -> Self { alignment(.leading) }
  public func centered() -> Self { alignment(.center) }
  public func rightAligned() -> Self { alignment(.trailing) }
}

public struct Fill: Widget, Hashable, Sendable, Stylable {
  public var symbol: String
  public var style: Style

  public init(_ symbol: String = " ", style: Style = .plain) {
    self.symbol = symbol
    self.style = style
  }

  public func symbol(_ symbol: String) -> Self {
    var copy = self
    copy.symbol = symbol
    return copy
  }

  public func style(_ style: Style) -> Self {
    var copy = self
    copy.style = style
    return copy
  }

  public func foregroundStyle(_ color: Color) -> Self {
    var copy = self
    copy.style.foreground = color
    return copy
  }

  public func backgroundStyle(_ color: Color) -> Self {
    var copy = self
    copy.style.background = color
    return copy
  }

  public func bold(_ active: Bool = true) -> Self {
    var copy = self
    copy.style = active ? copy.style.adding(.bold) : copy.style.removing(.bold)
    return copy
  }

  public func render(in area: Rect, into frame: inout Frame) {
    guard TerminalWidth.of(symbol) == 1 else { return }
    frame.buffer.fill(area, with: Cell(symbol: symbol, style: style))
  }
}
