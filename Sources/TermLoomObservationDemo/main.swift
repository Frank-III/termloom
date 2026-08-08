import Foundation
import Observation
import TermLoom

@Observable
final class ObservationDemoModel {
  var tick = 0
  var progress = 0.0
  var samples: [Double] = []
  var events: [String] = ["model created"]
  var isPaused = false

  func advance() {
    guard !isPaused else { return }
    tick += 1
    progress = Double(tick % 40) / 39
    let sample = Double((tick * 17 + tick * tick * 3) % 100)
    samples.append(sample)
    if samples.count > 48 { samples.removeFirst(samples.count - 48) }
    events.append("tick \(tick): changed four observed properties")
    if events.count > 7 { events.removeFirst(events.count - 7) }
  }

  func togglePause() {
    isPaused.toggle()
    events.append(
      isPaused ? "paused from update(.key); returned .ignore" : "resumed; returned .ignore")
    if events.count > 7 { events.removeFirst(events.count - 7) }
  }

  func reset() {
    tick = 0
    progress = 0
    samples = []
    events = ["reset from update(.key); returned .ignore"]
  }

  func spike() {
    tick += 1
    progress = 1
    samples.append(100)
    events.append("manual spike; returned .ignore")
    if samples.count > 48 { samples.removeFirst(samples.count - 48) }
    if events.count > 7 { events.removeFirst(events.count - 7) }
  }
}

struct ObservationDashboard: Widget {
  let model: ObservationDemoModel

  func render(in area: Rect, into frame: inout Frame) {
    guard !area.isEmpty else { return }
    let shell = Block(
      title: " Swift Observation → immediate-mode TermLoom ",
      style: Style(foreground: .white, background: .black),
      borderStyle: Style(foreground: model.isPaused ? .yellow : .cyan),
      titleStyle: Style(
        foreground: model.isPaused ? .yellow : .cyan,
        modifiers: [.bold]),
      padding: .all(1),
      content: Text(""))
    shell.render(in: area, into: &frame.buffer, environment: frame.environment)
    let inner = shell.inner(area)
    guard !inner.isEmpty else { return }

    let regions = Layout(
      .vertical,
      constraints: [.length(2), .length(3), .fill, .length(2)],
      spacing: 1
    ).split(inner)
    guard regions.count == 4 else { return }

    let state = model.isPaused ? "PAUSED" : "LIVE"
    Line {
      Span(
        "● \(state)",
        style: Style(
          foreground: model.isPaused ? .yellow : .green,
          modifiers: [.bold]))
      Span("   tick \(model.tick)", style: Style(foreground: .white))
      Span("   no periodic redraw protocol", style: Style(foreground: .darkGray))
    }.render(in: regions[0], into: &frame.buffer, environment: frame.environment)

    Block(
      title: " Progress ",
      borderStyle: Style(foreground: .darkGray),
      padding: Padding(top: 0, leading: 1, bottom: 0, trailing: 1),
      content: Gauge(
        ratio: model.progress,
        label: "\(Int(model.progress * 100))%",
        filledStyle: Style(foreground: .black, background: .cyan, modifiers: [.bold]),
        emptyStyle: Style(foreground: .darkGray))
    )
    .render(in: regions[1], into: &frame.buffer, environment: frame.environment)

    let columns = Layout(
      .horizontal, constraints: [.percentage(44), .fill], spacing: 1
    ).split(regions[2])
    if columns.count == 2 {
      Block(
        title: " Observed samples ",
        borderStyle: Style(foreground: .blue),
        padding: .all(1),
        content: Sparkline(
          model.samples.isEmpty ? [0] : model.samples,
          bounds: 0...100,
          style: Style(foreground: .cyan))
      )
      .render(in: columns[0], into: &frame.buffer, environment: frame.environment)

      let lines = model.events.map { Line("  \($0)", style: Style(foreground: .gray)) }
      Block(
        title: " Mutation log ",
        borderStyle: Style(foreground: .magenta),
        padding: Padding(top: 0, leading: 0, bottom: 0, trailing: 1),
        content: Paragraph(Text(lines), wrap: .word)
      )
      .render(in: columns[1], into: &frame.buffer, environment: frame.environment)
    }

    Line {
      Span("space", style: Style(foreground: .cyan, modifiers: [.bold]))
      Span(" pause   ")
      Span("s", style: Style(foreground: .cyan, modifiers: [.bold]))
      Span(" spike   ")
      Span("r", style: Style(foreground: .cyan, modifiers: [.bold]))
      Span(" reset   ")
      Span("q", style: Style(foreground: .cyan, modifiers: [.bold]))
      Span(" quit   ")
      Span("updates intentionally return .ignore", style: Style(foreground: .darkGray))
    }.render(in: regions[3], into: &frame.buffer, environment: frame.environment)
  }
}

@MainActor
final class ObservationDemoApplication: TerminalApplication {
  let model = ObservationDemoModel()

  var body: ObservationDashboard { ObservationDashboard(model: model) }

  func update(_ event: TerminalEvent) async -> ApplicationUpdate {
    guard case .key(let key) = event, key.kind != .release else { return .ignore }
    switch key.key {
    case .character(" "):
      model.togglePause()
      return .ignore
    case .character("r"):
      model.reset()
      return .ignore
    case .character("s"):
      model.spike()
      return .ignore
    case .character("q"),
      .character("c") where key.modifiers.contains(.control):
      return .quit
    default:
      return .ignore
    }
  }
}

let application = ObservationDemoApplication()
let ticker = Task { @MainActor in
  while !Task.isCancelled {
    try? await Task.sleep(for: .milliseconds(350))
    if Task.isCancelled { return }
    application.model.advance()
  }
}
defer { ticker.cancel() }
try await application.run(viewport: .fullscreen)
