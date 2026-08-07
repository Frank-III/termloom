import Foundation
import Observation
import Ratatui

#if canImport(Darwin)
  import Darwin
#endif

struct Row: Hashable, Sendable {
  var name: String
  var value: Int
}

@Observable final class BenchmarkModel {
  var selectedRow = 0
}

struct BenchmarkSample: Codable {
  var name: String
  var iterations: Int
  var seconds: Double
  var nanosecondsPerIteration: Double
  var iterationsPerSecond: Double
  var cellUpdatesPerIteration: Double?
  var outputBytesPerIteration: Double?
  var retainedBytesDelta: Int64?
  var peakResidentBytes: Int64?
}

struct BenchmarkOptions {
  var iterations = 5_000
  var suite = "frames"
  var emitsJSON = false

  init(arguments: [String]) {
    var index = 0
    while index < arguments.count {
      switch arguments[index] {
      case "--iterations":
        if arguments.indices.contains(index + 1), let value = Int(arguments[index + 1]) {
          iterations = max(1, value)
          index += 1
        }
      case "--suite":
        if arguments.indices.contains(index + 1) {
          suite = arguments[index + 1]
          index += 1
        }
      case "--json":
        emitsJSON = true
      default:
        if let value = Int(arguments[index]) { iterations = max(1, value) }
      }
      index += 1
    }
  }
}

private struct SingleCell: Widget {
  var symbol: String

  func render(in area: Rect, into frame: inout Frame) {
    guard !area.isEmpty else { return }
    frame.buffer.setString(symbol, at: Position(x: area.x, y: area.y))
  }
}

private struct InteractionGrid: Widget {
  var count: Int

  func render(in area: Rect, into frame: inout Frame) {
    guard area.width > 0, area.height > 0 else { return }
    frame.buffer.setString("interaction grid", at: Position(x: area.x, y: area.y))
    for index in 0..<count {
      frame.addInteraction(
        InteractionRegion(
          control: ControlID("item-\(index)"),
          area: Rect(
            x: area.x &+ UInt16(index % Int(area.width)),
            y: area.y &+ UInt16((index / Int(area.width)) % Int(area.height)),
            width: 1,
            height: 1),
          action: ActionID("activate-\(index)"),
          isFocusable: true))
    }
  }
}

private let rows = (0..<30).map { Row(name: "worker-\($0)", value: $0 * 7) }
private let clock = ContinuousClock()

private func dashboard(selectedRow: Int) -> some Widget {
  Block(title: "Workers") {
    Table(rows, selectedRow: selectedRow) {
      TableColumn("Name", value: \.name, width: .flex(2))
      TableColumn("Value", value: \.value, alignment: .trailing)
    }
  }
}

private func seconds(_ duration: Duration) -> Double {
  let components = duration.components
  return Double(components.seconds) + Double(components.attoseconds) / 1e18
}

private func retainedBytes() -> Int64? {
  #if canImport(Darwin)
    var statistics = malloc_statistics_t()
    malloc_zone_statistics(malloc_default_zone(), &statistics)
    return Int64(statistics.size_in_use)
  #else
    return nil
  #endif
}

private func peakResidentBytes() -> Int64? {
  #if canImport(Darwin)
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
    return Int64(usage.ru_maxrss)
  #else
    return nil
  #endif
}

private func measure(
  _ name: String,
  iterations: Int,
  operation: (Int) throws -> Int
) rethrows -> BenchmarkSample {
  let retainedBefore = retainedBytes()
  var cellUpdates = 0
  let elapsed = try clock.measure {
    for iteration in 0..<iterations {
      cellUpdates += try operation(iteration)
    }
  }
  let retainedAfter = retainedBytes()
  let elapsedSeconds = seconds(elapsed)
  return BenchmarkSample(
    name: name,
    iterations: iterations,
    seconds: elapsedSeconds,
    nanosecondsPerIteration: elapsedSeconds * 1e9 / Double(iterations),
    iterationsPerSecond: Double(iterations) / elapsedSeconds,
    cellUpdatesPerIteration: Double(cellUpdates) / Double(iterations),
    outputBytesPerIteration: nil,
    retainedBytesDelta: retainedBefore.flatMap { before in
      retainedAfter.map { $0 - before }
    },
    peakResidentBytes: peakResidentBytes())
}

private func frameBenchmarks(iterations: Int) throws -> [BenchmarkSample] {
  var samples: [BenchmarkSample] = []

  var dashboardTerminal = try Terminal(backend: TestBackend(width: 120, height: 40))
  samples.append(
    try measure("frame/dashboard-diff", iterations: iterations) { iteration in
      try dashboardTerminal.draw { frame in
        frame.render(dashboard(selectedRow: iteration % rows.count))
      }.updates
    })

  let model = BenchmarkModel()
  var observedTerminal = try Terminal(backend: TestBackend(width: 120, height: 40))
  samples.append(
    try measure("frame/dashboard-observation", iterations: iterations) { iteration in
      model.selectedRow = iteration % rows.count
      let widget = withObservationTracking {
        dashboard(selectedRow: model.selectedRow)
      } onChange: {
      }
      let result: Result<CompletedFrame, any Error> = withObservationTracking {
        Result {
          try observedTerminal.draw { frame in frame.render(widget) }
        }
      } onChange: {
      }
      return try result.get().updates
    })

  var staticTerminal = try Terminal(backend: TestBackend(width: 120, height: 40))
  _ = try staticTerminal.draw { $0.render(Fill(" ")) }
  samples.append(
    try measure("frame/static", iterations: iterations) { _ in
      try staticTerminal.draw { $0.render(Fill(" ")) }.updates
    })

  var singleCellTerminal = try Terminal(backend: TestBackend(width: 120, height: 40))
  samples.append(
    try measure("frame/one-cell", iterations: iterations) { iteration in
      try singleCellTerminal.draw {
        $0.render(SingleCell(symbol: iteration.isMultiple(of: 2) ? "A" : "B"))
      }.updates
    })

  var fullFrameTerminal = try Terminal(backend: TestBackend(width: 120, height: 40))
  samples.append(
    try measure("frame/full-churn", iterations: iterations) { iteration in
      try fullFrameTerminal.draw {
        $0.render(
          Fill(
            iteration.isMultiple(of: 2) ? "A" : "B",
            style: Style(background: iteration.isMultiple(of: 2) ? .blue : .magenta)))
      }.updates
    })

  var cursorTerminal = try Terminal(backend: TestBackend(width: 120, height: 40))
  _ = try cursorTerminal.draw { $0.render(Fill(" ")) }
  samples.append(
    try measure("frame/cursor-only", iterations: iterations) { iteration in
      try cursorTerminal.draw { frame in
        frame.render(Fill(" "))
        frame.placeCursor(
          at: Position(x: UInt16(iteration % 120), y: UInt16((iteration / 120) % 40)),
          style: .steadyBar)
      }.updates
    })

  var emptyInteractionTerminal = try Terminal(backend: TestBackend(width: 120, height: 40))
  samples.append(
    try measure("frame/0-interactions", iterations: iterations) { _ in
      try emptyInteractionTerminal.draw { $0.render(InteractionGrid(count: 0)) }.updates
    })

  var interactionTerminal = try Terminal(backend: TestBackend(width: 120, height: 40))
  samples.append(
    try measure("frame/100-interactions", iterations: iterations) { _ in
      try interactionTerminal.draw { $0.render(InteractionGrid(count: 100)) }.updates
    })

  return samples
}

private func primitiveBenchmarks(iterations: Int) throws -> [BenchmarkSample] {
  var samples: [BenchmarkSample] = []

  for dimension in [16, 64, 255] {
    let scaledIterations = max(1, iterations / max(1, dimension / 16))
    var retainedCellCount = 0
    var sample = measure(
      "buffer/empty/\(dimension)x\(dimension)", iterations: scaledIterations
    ) { _ in
      let buffer = Buffer(
        area: Rect(
          x: 0, y: 0, width: UInt16(dimension), height: UInt16(dimension)))
      retainedCellCount ^= buffer.count
      return 0
    }
    sample.cellUpdatesPerIteration = nil
    withExtendedLifetime(retainedCellCount) {}
    samples.append(sample)
  }

  let constraints = Array(repeating: Constraint.flex(1), count: 10)
  var layoutChecksum = 0
  var layoutSample = measure("layout/10-fill", iterations: iterations) { _ in
    let areas = Layout(.vertical, constraints: constraints).split(
      Rect(x: 0, y: 0, width: 120, height: 40))
    layoutChecksum ^= areas.count
    return 0
  }
  layoutSample.cellUpdatesPerIteration = nil
  withExtendedLifetime(layoutChecksum) {}
  samples.append(layoutSample)

  for lineCount in [64, 2_048] {
    let text = Text(
      (0..<lineCount).map {
        Line("line \($0) alpha beta gamma delta epsilon zeta eta theta")
      })
    let paragraph = Paragraph(text, wrap: .word, trimLeadingWhitespace: false)
    var buffer = Buffer(area: Rect(x: 0, y: 0, width: 100, height: 50))
    let scaledIterations = max(1, iterations / max(1, lineCount / 64))
    var sample = measure(
      "paragraph/wrap/\(lineCount)-lines", iterations: scaledIterations
    ) { _ in
      buffer.reset()
      paragraph.render(
        in: buffer.area, into: &buffer, environment: RenderEnvironment())
      return 0
    }
    sample.cellUpdatesPerIteration = nil
    samples.append(sample)
  }

  let scrolledText = Text(
    (0..<2_048).map {
      Line("line \($0) alpha beta gamma delta epsilon zeta eta theta")
    })
  let scrolledParagraph = Paragraph(
    scrolledText,
    wrap: .word,
    scroll: 1_024,
    trimLeadingWhitespace: false
  )
  var scrolledBuffer = Buffer(area: Rect(x: 0, y: 0, width: 100, height: 50))
  var scrolledSample = measure(
    "paragraph/wrap/2048-lines/scrolled-1024", iterations: max(1, iterations / 32)
  ) { _ in
    scrolledBuffer.reset()
    scrolledParagraph.render(
      in: scrolledBuffer.area,
      into: &scrolledBuffer,
      environment: RenderEnvironment()
    )
    return 0
  }
  scrolledSample.cellUpdatesPerIteration = nil
  samples.append(scrolledSample)

  for rowCount in [64, 2_048] {
    let tableRows = (0..<rowCount).map { Row(name: "worker-\($0)", value: $0 * 7) }
    let table = Table(tableRows, selectedRow: rowCount / 2) {
      TableColumn("Name", value: \.name, width: .flex(2))
      TableColumn("Value", value: \.value, alignment: .trailing)
    }
    var buffer = Buffer(area: Rect(x: 0, y: 0, width: 120, height: 50))
    let scaledIterations = max(1, iterations / max(1, rowCount / 64))
    var sample = measure(
      "table/render/\(rowCount)x2", iterations: scaledIterations
    ) { _ in
      buffer.reset()
      table.render(in: buffer.area, into: &buffer, environment: RenderEnvironment())
      return 0
    }
    sample.cellUpdatesPerIteration = nil
    samples.append(sample)
  }

  return samples
}

private func ansiOutputBenchmark(
  name: String,
  iterations: Int,
  render: (Int, inout Frame) -> Void
) throws -> BenchmarkSample {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("ratatui-benchmark-\(UUID().uuidString).ansi")
  _ = FileManager.default.createFile(atPath: url.path, contents: nil)
  defer { try? FileManager.default.removeItem(at: url) }
  let output = try FileHandle(forWritingTo: url)
  defer { try? output.close() }
  var terminal = try Terminal(
    backend: ANSIBackend(
      output: output,
      fallbackSize: Size(width: 120, height: 40),
      configuration: .full))
  var sample = try measure(name, iterations: iterations) { iteration in
    try terminal.draw { frame in render(iteration, &frame) }.updates
  }
  try output.synchronize()
  let byteCount = try output.offset()
  sample.outputBytesPerIteration = Double(byteCount) / Double(iterations)
  return sample
}

private func outputBenchmarks(iterations: Int) throws -> [BenchmarkSample] {
  let outputIterations = min(iterations, 1_000)
  return [
    try ansiOutputBenchmark(
      name: "ansi/static", iterations: outputIterations
    ) { _, frame in
      frame.render(Fill(" "))
    },
    try ansiOutputBenchmark(
      name: "ansi/one-cell", iterations: outputIterations
    ) { iteration, frame in
      frame.render(SingleCell(symbol: iteration.isMultiple(of: 2) ? "A" : "B"))
    },
    try ansiOutputBenchmark(
      name: "ansi/full-churn", iterations: outputIterations
    ) { iteration, frame in
      frame.render(
        Fill(
          iteration.isMultiple(of: 2) ? "A" : "B",
          style: Style(background: iteration.isMultiple(of: 2) ? .blue : .magenta)))
    },
  ]
}

private func printSamples(_ samples: [BenchmarkSample], asJSON: Bool) throws {
  if asJSON {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try encoder.encode(samples), as: UTF8.self))
    return
  }
  for sample in samples {
    var metrics = [
      String(format: "%.0f ns/iteration", sample.nanosecondsPerIteration),
      String(format: "%.0f iterations/s", sample.iterationsPerSecond),
    ]
    if let updates = sample.cellUpdatesPerIteration {
      metrics.append(String(format: "%.2f cell updates/iteration", updates))
    }
    if let bytes = sample.outputBytesPerIteration {
      metrics.append(String(format: "%.2f output bytes/iteration", bytes))
    }
    if let retained = sample.retainedBytesDelta {
      metrics.append("\(retained) retained bytes")
    }
    if let resident = sample.peakResidentBytes {
      metrics.append("\(resident) peak RSS bytes")
    }
    print("\(sample.name): \(sample.iterations) iterations; \(metrics.joined(separator: "; "))")
  }
}

let options = BenchmarkOptions(arguments: Array(CommandLine.arguments.dropFirst()))
let validSuites = ["frames", "primitives", "output", "all"]
guard validSuites.contains(options.suite) else {
  FileHandle.standardError.write(
    Data("unknown suite '\(options.suite)'; expected \(validSuites.joined(separator: ", "))\n".utf8)
  )
  exit(2)
}

var samples: [BenchmarkSample] = []
if options.suite == "frames" || options.suite == "all" {
  samples += try frameBenchmarks(iterations: options.iterations)
}
if options.suite == "primitives" || options.suite == "all" {
  samples += try primitiveBenchmarks(iterations: options.iterations)
}
if options.suite == "output" || options.suite == "all" {
  samples += try outputBenchmarks(iterations: options.iterations)
}
try printSamples(samples, asJSON: options.emitsJSON)
