import Foundation
import Ratatui

public struct DevToolsPanel: Widget, Hashable, Sendable {
  public var state: DevToolsState
  public var title: String
  public var style: Style
  public var borderStyle: Style

  public init(
    _ state: DevToolsState,
    title: String = "Ratatui DevTools",
    style: Style = Style(foreground: .white),
    borderStyle: Style = Style(foreground: .cyan)
  ) {
    self.state = state
    self.title = title
    self.style = style
    self.borderStyle = borderStyle
  }

  public func render(in area: Rect, into frame: inout Frame) {
    guard !area.isEmpty else { return }
    let block = Block(
      title: " \(title) ",
      style: style,
      borderStyle: borderStyle,
      titleStyle: borderStyle.adding(.bold),
      padding: Padding(top: 0, leading: 1, bottom: 0, trailing: 1),
      content: Text(""))
    frame.render(block, in: area)
    let inner = block.inner(area)
    guard !inner.isEmpty else { return }

    let rows = summaryLines + logLines(limit: max(0, inner.height - summaryLines.count - 1))
    frame.render(
      Paragraph(Text(rows), wrap: .character, trimLeadingWhitespace: false),
      in: inner)
  }

  private var summaryLines: [Line] {
    let frames = state.frames
    let terminal = state.terminalSize.map { "\($0.width)×\($0.height)" } ?? "unknown"
    let cells = frames.lastChangedCells.map(String.init) ?? "—"
    let bytes = frames.lastOutputBytes.map(String.init) ?? "—"
    return [
      Line {
        Span("terminal ", style: Style(foreground: .darkGray))
        Span(terminal)
        Span("   frames ", style: Style(foreground: .darkGray))
        Span(String(frames.count))
      },
      Line {
        Span("last ", style: Style(foreground: .darkGray))
        Span(milliseconds(frames.lastMilliseconds), style: metricStyle(frames.lastMilliseconds))
        Span("   avg ", style: Style(foreground: .darkGray))
        Span(
          milliseconds(frames.averageMilliseconds), style: metricStyle(frames.averageMilliseconds))
        Span("   max ", style: Style(foreground: .darkGray))
        Span(
          milliseconds(frames.maximumMilliseconds), style: metricStyle(frames.maximumMilliseconds))
      },
      Line {
        Span("fps≈ ", style: Style(foreground: .darkGray))
        Span(String(format: "%.1f", frames.estimatedFramesPerSecond))
        Span("   cells ", style: Style(foreground: .darkGray))
        Span(cells)
        Span("   bytes ", style: Style(foreground: .darkGray))
        Span(bytes)
      },
      Line("─ logs", style: Style(foreground: .darkGray)),
    ]
  }

  private func logLines(limit: Int) -> [Line] {
    guard limit > 0 else { return [] }
    return state.logs.suffix(limit).map { entry in
      Line {
        Span("\(entry.sequence) ", style: Style(foreground: .darkGray))
        Span(
          entry.level.rawValue.padding(toLength: 7, withPad: " ", startingAt: 0),
          style: levelStyle(entry.level))
        Span(entry.message)
      }
    }
  }

  private func milliseconds(_ value: Double) -> String {
    String(format: "%.2fms", value)
  }

  private func metricStyle(_ milliseconds: Double) -> Style {
    Style(foreground: milliseconds <= 8.33 ? .green : milliseconds <= 16.67 ? .yellow : .red)
  }

  private func levelStyle(_ level: DevToolsLogLevel) -> Style {
    switch level {
    case .trace: Style(foreground: .darkGray)
    case .info: Style(foreground: .cyan)
    case .warning: Style(foreground: .yellow)
    case .error: Style(foreground: .red)
    }
  }
}
